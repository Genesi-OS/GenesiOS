#!/usr/bin/env python3
"""
Genesi API Inspector — native interception workbench (Phase 4.5).

A Burp-Suite-style HTTP/HTTPS workbench built *natively on top of mitmproxy's
own Python addon API* instead of just shelling out to mitmweb. mitmproxy stays
the engine: it runs in-process as a `DumpMaster` inside a background asyncio
thread, and a custom addon (`GenesiAddon`) streams flows up to a PySide6/QML UI
and pushes edits/replays back down.

What it gives you (the four classic Burp lanes):
  • Proxy / Intercept — live flow list; pause + edit a request before it goes out,
    then forward or drop it (scoped by an optional host filter).
  • Repeater         — send one request over and over, tweaking it by hand.
  • Intruder         — Sniper-style fuzzing: mark a spot with §…§, feed a payload
    list, fire them all and diff status / length / time.
  • Scanner          — passive checks on every response (missing security headers,
    leaky cookies, CORS *, version disclosure, error/stack-trace leakage…).

Pure front-end over the engine: nothing here weakens TLS or stores traffic off
the machine — it's the same local mitmproxy CA flow the `genesi-netinspect cert`
command already trusts.
"""
import os
import re
import sys
import json
import time
import shutil
import atexit
import signal
import base64
import hashlib
import asyncio
import threading
import subprocess

try:
    from PySide6.QtCore import QObject, Slot, Signal, QUrl
    from PySide6.QtGui import QGuiApplication, QIcon
    from PySide6.QtQml import QQmlApplicationEngine
except ImportError:
    sys.stderr.write(
        "Genesi API Inspector needs PySide6.\n"
        "  Install it with:  sudo pacman -S pyside6\n")
    sys.exit(1)

try:
    from mitmproxy import options, ctx, http
    from mitmproxy.tools.dump import DumpMaster
except ImportError:
    sys.stderr.write(
        "Genesi API Inspector needs mitmproxy (the interception engine).\n"
        "  Install it with:  sudo pacman -S mitmproxy\n")
    sys.exit(1)


PROXY_HOST = os.environ.get("GENESI_PROXY_HOST", "127.0.0.1")
PROXY_PORT = int(os.environ.get("GENESI_PROXY_PORT", "8080"))

CA_CERT = os.path.expanduser("~/.mitmproxy/mitmproxy-ca-cert.pem")

# Chromium-family browsers we can pre-configure as a Burp-style "embedded
# browser" (proxy + per-CA cert exception, isolated profile). First one found wins.
_CHROMIUM_BINS = (
    "chromium", "chromium-browser", "google-chrome-stable", "google-chrome",
    "brave", "brave-browser", "vivaldi-stable", "microsoft-edge", "microsoft-edge-stable",
)


# ───────────────────────────── helpers ─────────────────────────────────────

def _find_chromium():
    """Path of the first Chromium-family browser we can drive, or None."""
    for b in _CHROMIUM_BINS:
        p = shutil.which(b)
        if p:
            return p
    return None


def _ca_spki_sha256_b64():
    """Base64(SHA-256(SubjectPublicKeyInfo)) of the mitmproxy CA — the value
    Chromium's --ignore-certificate-errors-spki-list wants. This lets a
    pre-configured browser trust ONLY our interception CA (exactly that one key),
    instead of trusting the CA system-wide. Returns None if the CA isn't there
    yet. Uses `cryptography`, a hard dependency of mitmproxy (always present)."""
    if not os.path.exists(CA_CERT):
        return None
    try:
        from cryptography import x509
        from cryptography.hazmat.primitives import serialization
        with open(CA_CERT, "rb") as fh:
            cert = x509.load_pem_x509_certificate(fh.read())
        spki = cert.public_key().public_bytes(
            serialization.Encoding.DER,
            serialization.PublicFormat.SubjectPublicKeyInfo)
        return base64.b64encode(hashlib.sha256(spki).digest()).decode("ascii")
    except Exception:                                           # noqa: BLE001
        return None


def _render_raw_request(req) -> str:
    """A flow's request as an editable raw HTTP message."""
    lines = ["%s %s HTTP/%s" % (req.method, req.path,
                                req.http_version.split("/")[-1] if req.http_version else "1.1")]
    for k, v in req.headers.items(multi=True):
        lines.append("%s: %s" % (k, v))
    body = req.get_text(strict=False) or ""
    return "\n".join(lines) + "\n\n" + body


def _render_raw_response(resp) -> str:
    if resp is None:
        return "(no response yet)"
    lines = ["HTTP/%s %s %s" % (
        (resp.http_version or "HTTP/1.1").split("/")[-1],
        resp.status_code, resp.reason or "")]
    for k, v in resp.headers.items(multi=True):
        lines.append("%s: %s" % (k, v))
    body = resp.get_text(strict=False) or ""
    if len(body) > 200000:
        body = body[:200000] + "\n… (truncated)"
    return "\n".join(lines) + "\n\n" + body


def _parse_raw_request(raw: str):
    """(method, path, [(k, v)…], body_bytes) from an edited raw request."""
    raw = raw.replace("\r\n", "\n")
    head, _, body = raw.partition("\n\n")
    lines = [l for l in head.split("\n")]
    request_line = (lines[0] if lines else "GET / HTTP/1.1").strip()
    parts = request_line.split()
    method = parts[0] if parts else "GET"
    path = parts[1] if len(parts) > 1 else "/"
    headers = []
    for ln in lines[1:]:
        if not ln.strip() or ":" not in ln:
            continue
        k, _, v = ln.partition(":")
        headers.append((k.strip(), v.strip()))
    return method, path, headers, body.encode("utf-8", "surrogateescape")


def _apply_raw_to_flow(flow, raw: str):
    """Overwrite a flow's request from edited raw text (keeps scheme/host/port)."""
    method, path, headers, body = _parse_raw_request(raw)
    flow.request.method = method
    flow.request.path = path
    flow.request.headers = http.Headers(
        [(k.encode("latin-1", "ignore"), v.encode("latin-1", "ignore"))
         for k, v in headers])
    # set_content keeps content-length honest, overriding any stale header.
    flow.request.set_content(body)


# ───────── passive scanner: cheap, high-signal checks on a response ─────────

_SECRET_PATTERNS = [
    ("AWS access key", re.compile(r"AKIA[0-9A-Z]{16}")),
    ("Google API key", re.compile(r"AIza[0-9A-Za-z\-_]{35}")),
    ("Slack token", re.compile(r"xox[baprs]-[0-9A-Za-z\-]{10,}")),
    ("JWT", re.compile(r"eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}")),
    ("Private key block", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----")),
    ("Bearer token", re.compile(r"[Bb]earer\s+[A-Za-z0-9_\-\.=]{20,}")),
]
_ERROR_SIGNS = re.compile(
    r"(Traceback \(most recent call last\)|java\.lang\.[A-Za-z.]+Exception|"
    r"Fatal error:|Warning: .*on line \d+|SQLSTATE\[|ORA-\d{5}|"
    r"System\.[A-Za-z.]+Exception)")


def scan_response(flow):
    """Return a list of passive findings for a completed flow."""
    findings = []
    resp = flow.response
    if resp is None:
        return findings
    url = flow.request.pretty_url
    h = resp.headers
    is_https = flow.request.scheme == "https"

    def add(sev, title, detail):
        findings.append({"severity": sev, "title": title, "detail": detail,
                         "url": url, "id": flow.id})

    ctype = h.get("content-type", "")
    is_html = "text/html" in ctype

    # Missing security headers (only meaningful on documents).
    if is_html and 200 <= resp.status_code < 400:
        if "content-security-policy" not in h:
            add("low", "Missing Content-Security-Policy", "No CSP header on an HTML response.")
        if "x-content-type-options" not in h:
            add("info", "Missing X-Content-Type-Options", "nosniff not set — MIME sniffing possible.")
        if "x-frame-options" not in h and "frame-ancestors" not in h.get("content-security-policy", ""):
            add("low", "Missing X-Frame-Options", "Page may be framable (clickjacking).")
        if is_https and "strict-transport-security" not in h:
            add("low", "Missing HSTS", "HTTPS response without Strict-Transport-Security.")

    # Cookie flags.
    for cookie in h.get_all("set-cookie"):
        low = cookie.lower()
        name = cookie.split("=", 1)[0].strip()
        if "httponly" not in low:
            add("low", "Cookie without HttpOnly", "Set-Cookie '%s' is reachable from JS." % name)
        if is_https and "secure" not in low:
            add("low", "Cookie without Secure", "Set-Cookie '%s' may ride over plain HTTP." % name)
        if "samesite" not in low:
            add("info", "Cookie without SameSite", "Set-Cookie '%s' has no SameSite (CSRF surface)." % name)

    # CORS.
    acao = h.get("access-control-allow-origin", "")
    if acao == "*" and h.get("access-control-allow-credentials", "").lower() == "true":
        add("high", "Unsafe CORS", "ACAO '*' together with Allow-Credentials: true.")
    elif acao == "*":
        add("info", "Permissive CORS", "Access-Control-Allow-Origin: * — any origin may read responses.")

    # Version / tech disclosure.
    for hdr in ("server", "x-powered-by", "x-aspnet-version", "x-generator"):
        val = h.get(hdr, "")
        if val and re.search(r"\d", val):
            add("info", "Version disclosure (%s)" % hdr, "%s: %s" % (hdr, val))

    # Error / stack-trace leakage in the body.
    if 200 <= resp.status_code < 600 and ("text" in ctype or "json" in ctype or not ctype):
        body = resp.get_text(strict=False) or ""
        m = _ERROR_SIGNS.search(body)
        if m:
            add("medium", "Error / stack-trace leakage",
                "Response body exposes internals: …%s…" % m.group(0)[:80])
        for label, pat in _SECRET_PATTERNS:
            if pat.search(body):
                add("high", "Possible secret in response (%s)" % label,
                    "A %s-shaped string was found in the response body." % label)
                break

    return findings


# ───────────────────────────── mitmproxy addon ─────────────────────────────

class GenesiAddon:
    """The bridge living inside mitmproxy: captures flows, intercepts, scans,
    and routes replayed flows back to the right UI lane (repeater/intruder)."""

    def __init__(self, backend):
        self.backend = backend
        self.master = None
        self.flows = {}            # flow.id -> flow object
        self.intercept_enabled = False
        self.scope = ""            # substring filter on host; "" = everything

    # -- lifecycle ----------------------------------------------------------
    def running(self):
        self.master = ctx.master
        # Report the port mitmproxy ACTUALLY bound (it may have hopped off a
        # busy 8080), so the desktop proxy + UI point at the real one.
        self.backend._on_proxy_ready(ctx.options.listen_host or PROXY_HOST,
                                     ctx.options.listen_port or PROXY_PORT)

    # -- in-scope helper ----------------------------------------------------
    def _in_scope(self, flow):
        if not self.scope:
            return True
        return self.scope.lower() in flow.request.pretty_host.lower()

    # -- proxy hooks --------------------------------------------------------
    def request(self, flow: http.HTTPFlow):
        self.flows[flow.id] = flow
        kind = flow.metadata.get("genesi_kind")
        if kind:
            return  # replayed (repeater/intruder) — never intercept our own
        self.backend.flowAdded.emit(json.dumps(self._summary(flow)))
        if self.intercept_enabled and self._in_scope(flow):
            flow.intercept()
            self.backend.interceptPaused.emit(json.dumps({
                "id": flow.id,
                "raw": _render_raw_request(flow.request),
                "host": flow.request.pretty_host,
            }))

    def response(self, flow: http.HTTPFlow):
        self.flows[flow.id] = flow
        t0 = flow.metadata.get("genesi_t0")
        ms = int((time.time() - t0) * 1000) if t0 else None
        if ms is not None:
            flow.metadata["genesi_ms"] = ms
        kind = flow.metadata.get("genesi_kind")

        if kind == "repeater":
            self.backend.repeaterResult.emit(json.dumps({
                "raw": _render_raw_response(flow.response),
                "status": flow.response.status_code,
                "length": len(flow.response.raw_content or b""),
                "ms": ms,
            }))
            return
        if kind and kind.startswith("intruder:"):
            _, job, idx, payload = kind.split(":", 3)
            self.backend._intruder_row(job, {
                "idx": int(idx),
                "payload": payload,
                "status": flow.response.status_code,
                "length": len(flow.response.raw_content or b""),
                "ms": ms,
            })
            return

        # Normal proxied traffic: update the list + run the passive scanner.
        self.backend.flowUpdated.emit(json.dumps(self._summary(flow)))
        for finding in scan_response(flow):
            self.backend.scannerFinding.emit(json.dumps(finding))

    def error(self, flow):
        kind = (flow.metadata or {}).get("genesi_kind", "") if hasattr(flow, "metadata") else ""
        if kind == "repeater":
            self.backend.repeaterResult.emit(json.dumps({
                "raw": "(request failed: %s)" % (flow.error.msg if flow.error else "error"),
                "status": 0, "length": 0, "ms": None}))

    # -- serialization ------------------------------------------------------
    def _summary(self, flow):
        r = flow.request
        resp = flow.response
        return {
            "id": flow.id,
            "method": r.method,
            "scheme": r.scheme,
            "host": r.pretty_host,
            "path": r.path if len(r.path) < 120 else r.path[:117] + "…",
            "status": resp.status_code if resp else 0,
            "length": len(resp.raw_content or b"") if resp and resp.raw_content else 0,
            "ctype": (resp.headers.get("content-type", "").split(";")[0] if resp else ""),
            "ms": flow.metadata.get("genesi_ms"),
        }


# ───────────────────────────── proxy engine thread ─────────────────────────

def _free_port(host, preferred, span=20):
    """Return a bindable TCP port: the preferred one, or the next free port in
    [preferred, preferred+span]. This is what makes the inspector resilient to a
    busy 8080 (e.g. a docker container already publishes -p 8080:80) — instead
    of dying with "address already in use" it quietly hops to 8081, 8082, …
    Falls back to the preferred port if the whole range is taken (mitmproxy then
    surfaces the bind error itself)."""
    import socket
    for p in range(preferred, preferred + span + 1):
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            s.bind((host, p))
            return p
        except OSError:
            continue
        finally:
            s.close()
    return preferred


class ProxyEngine(threading.Thread):
    def __init__(self, addon, host, port):
        super().__init__(daemon=True)
        self.addon = addon
        self.host, self.port = host, port
        self.loop = None
        self.master = None

    def run(self):
        try:
            asyncio.run(self._main())
        except Exception as e:                                   # noqa: BLE001
            self.addon.backend.proxyError.emit(str(e))

    async def _main(self):
        self.loop = asyncio.get_running_loop()
        # Hop to a free port if the preferred one is busy (busy 8080, etc.).
        self.port = _free_port(self.host, self.port)
        opts = options.Options(listen_host=self.host, listen_port=self.port)
        try:
            self.master = DumpMaster(opts, with_termlog=False, with_dumper=False)
        except TypeError:
            self.master = DumpMaster(opts)
        self.master.addons.add(self.addon)
        await self.master.run()

    def call(self, fn):
        if self.loop and self.loop.is_running():
            self.loop.call_soon_threadsafe(fn)

    def shutdown(self):
        # On window close the asyncio loop may already be torn down; guarding
        # avoids the "RuntimeError: Event loop is closed" traceback on exit.
        if self.master and self.loop and not self.loop.is_closed():
            try:
                self.loop.call_soon_threadsafe(self.master.shutdown)
            except RuntimeError:
                pass


# ───────────────────────────── Qt backend bridge ───────────────────────────

class Backend(QObject):
    # proxy lifecycle
    proxyReady = Signal(str, int)
    proxyError = Signal(str)
    statusMessage = Signal(str)
    certTrusted = Signal(bool)          # True = trusted system-wide
    # live flow list
    flowAdded = Signal(str)
    flowUpdated = Signal(str)
    flowDetail = Signal(str)            # {id, request, response}
    flowsCleared = Signal()
    # intercept
    interceptPaused = Signal(str)
    interceptStateChanged = Signal(bool)
    # repeater / intruder
    repeaterResult = Signal(str)
    intruderRow = Signal(str)
    intruderDone = Signal(str)          # job id
    # passive scanner
    scannerFinding = Signal(str)        # {severity, title, detail, url} — was
                                        # emitted (see GenesiAddon) but never
                                        # declared, so findings raised
                                        # AttributeError and the QML handler
                                        # bound to a non-existent signal.

    def __init__(self):
        super().__init__()
        self.addon = GenesiAddon(self)
        self.engine = ProxyEngine(self.addon, PROXY_HOST, PROXY_PORT)
        self._desktop_proxied = False
        self._jobs = {}                 # job id -> {"total": n, "got": n}

    # -- startup ------------------------------------------------------------
    def start(self):
        self.engine.start()

    def _on_proxy_ready(self, host, port):
        # Route the desktop through us for the session (reversible on exit).
        try:
            subprocess.run(["genesi-proxy", "on"], env=dict(os.environ,
                           GENESI_PROXY_PORT=str(port)),
                           capture_output=True, timeout=10)
            self._desktop_proxied = True
        except Exception:                                       # noqa: BLE001
            pass
        self.certTrusted.emit(self._cert_is_trusted())
        self.proxyReady.emit(host, port)

    def restore_proxy(self):
        """Flip the desktop proxy back off. Idempotent and cheap — safe to call
        from aboutToQuit, atexit, AND a signal handler, so a crash/kill/logout
        never leaves the desktop stranded behind a dead proxy (the bug where the
        browser showed ERR_PROXY_CONNECTION_FAILED with no inspector running)."""
        if not self._desktop_proxied:
            return
        self._desktop_proxied = False
        try:
            subprocess.run(["genesi-proxy", "off"], capture_output=True, timeout=10)
        except Exception:                                       # noqa: BLE001
            pass

    def shutdown(self):
        self.restore_proxy()
        self.engine.shutdown()

    # -- intercept controls -------------------------------------------------
    @Slot(bool)
    def setIntercept(self, on):
        self.addon.intercept_enabled = bool(on)
        self.interceptStateChanged.emit(bool(on))
        self.statusMessage.emit("Intercept %s" % ("ON" if on else "OFF"))

    @Slot(str)
    def setScope(self, host_substr):
        self.addon.scope = (host_substr or "").strip()
        self.statusMessage.emit("Scope: %s" % (self.addon.scope or "everything"))

    @Slot(str, str)
    def forwardIntercepted(self, flow_id, raw):
        flow = self.addon.flows.get(flow_id)
        if not flow:
            return

        def go():
            try:
                _apply_raw_to_flow(flow, raw)
            except Exception as e:                              # noqa: BLE001
                self.statusMessage.emit("edit error: %s" % e)
            flow.resume()
        self.engine.call(go)
        self.statusMessage.emit("Request forwarded")

    @Slot(str)
    def dropIntercepted(self, flow_id):
        flow = self.addon.flows.get(flow_id)
        if not flow:
            return
        self.engine.call(lambda: flow.kill())
        self.statusMessage.emit("Request dropped")

    # -- flow detail --------------------------------------------------------
    @Slot(str)
    def loadDetail(self, flow_id):
        flow = self.addon.flows.get(flow_id)
        if not flow:
            return
        self.flowDetail.emit(json.dumps({
            "id": flow_id,
            "request": _render_raw_request(flow.request),
            "response": _render_raw_response(flow.response),
        }))

    @Slot(str, result=str)
    def rawRequestOf(self, flow_id):
        flow = self.addon.flows.get(flow_id)
        return _render_raw_request(flow.request) if flow else ""

    @Slot()
    def clearFlows(self):
        self.addon.flows.clear()
        self.flowsCleared.emit()

    # -- repeater -----------------------------------------------------------
    @Slot(str, str)
    def repeaterSend(self, base_flow_id, raw):
        base = self.addon.flows.get(base_flow_id)
        if not base:
            self.statusMessage.emit("No base request to send.")
            return
        nf = base.copy()
        nf.response = None
        nf.metadata["genesi_kind"] = "repeater"
        nf.metadata["genesi_t0"] = time.time()
        try:
            _apply_raw_to_flow(nf, raw)
        except Exception as e:                                  # noqa: BLE001
            self.statusMessage.emit("edit error: %s" % e)
            return
        self.addon.flows[nf.id] = nf
        self.engine.call(lambda: self.addon.master.commands.call("replay.client", [nf]))
        self.statusMessage.emit("Repeater → sent")

    # -- intruder (Sniper) --------------------------------------------------
    @Slot(str, str, str)
    def intruderStart(self, base_flow_id, template, payloads_text):
        base = self.addon.flows.get(base_flow_id)
        if not base:
            self.statusMessage.emit("No base request for Intruder.")
            return
        if "§" not in template or template.count("§") < 2:
            self.statusMessage.emit("Mark a fuzz position with §…§ first.")
            return
        pre, _, rest = template.partition("§")
        marked, _, post = rest.partition("§")
        payloads = [p for p in payloads_text.replace("\r\n", "\n").split("\n") if p != ""]
        if not payloads:
            self.statusMessage.emit("Add at least one payload.")
            return

        job = "%d" % int(time.time() * 1000)
        self._jobs[job] = {"total": len(payloads), "got": 0}
        self.statusMessage.emit("Intruder: firing %d payloads…" % len(payloads))

        for idx, payload in enumerate(payloads):
            raw = pre + payload + post
            nf = base.copy()
            nf.response = None
            # payload is sanitised of separators we use in the kind tag
            safe_payload = payload.replace(":", "∶")[:120]
            nf.metadata["genesi_kind"] = "intruder:%s:%d:%s" % (job, idx, safe_payload)
            nf.metadata["genesi_t0"] = time.time()
            try:
                _apply_raw_to_flow(nf, raw)
            except Exception:                                   # noqa: BLE001
                continue
            self.addon.flows[nf.id] = nf
            self.engine.call(
                (lambda f: lambda: self.addon.master.commands.call("replay.client", [f]))(nf))

    def _intruder_row(self, job, row):
        row["job"] = job
        # restore the original payload text for display
        row["payload"] = row.get("payload", "").replace("∶", ":")
        self.intruderRow.emit(json.dumps(row))
        st = self._jobs.get(job)
        if st:
            st["got"] += 1
            if st["got"] >= st["total"]:
                self.intruderDone.emit(job)
                self._jobs.pop(job, None)

    # -- certificate / proxy plumbing (delegates to the CLI) ----------------
    def _cert_is_trusted(self):
        anchor = "/etc/ca-certificates/trust-source/anchors/genesi-mitmproxy.pem"
        return os.path.exists(anchor)

    @Slot()
    def trustCert(self):
        # The CLI subcommand asks for a password via pkexec/sudo in a terminal.
        try:
            subprocess.Popen(["konsole", "--hold", "-e", "genesi-netinspect", "cert"],
                             start_new_session=True)
            self.statusMessage.emit("Trusting the mitmproxy CA (see the terminal)…")
        except Exception as e:                                  # noqa: BLE001
            self.statusMessage.emit("could not launch cert trust: %s" % e)

    @Slot(result=bool)
    def hasBrowser(self):
        return _find_chromium() is not None

    @Slot()
    def openBrowser(self):
        """Burp-style "open browser": launch a pre-configured Chromium that
        routes through THIS engine's actual bound port and trusts our CA via an
        SPKI exception — in an isolated profile. It does NOT touch the system
        proxy, so it can never strand the desktop (no orphaned-proxy risk), and
        HTTPS decrypts even without `genesi-netinspect cert`."""
        chrome = _find_chromium()
        if not chrome:
            self.statusMessage.emit(
                "No Chromium-family browser found — install chromium.")
            return
        host = self.engine.host or PROXY_HOST
        port = self.engine.port or PROXY_PORT
        profile = os.path.join(
            os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")),
            "genesi-netinspect", "browser-profile")
        try:
            os.makedirs(profile, exist_ok=True)
        except OSError:
            pass
        args = [
            chrome,
            "--proxy-server=http://%s:%d" % (host, port),
            # Force loopback through the proxy too (intercept local dev servers).
            "--proxy-bypass-list=<-loopback>",
            "--user-data-dir=%s" % profile,
            "--no-first-run", "--no-default-browser-check",
            "--new-window", "about:blank",
        ]
        spki = _ca_spki_sha256_b64()
        if spki:
            # Trust exactly our CA's key — not a blanket --ignore-certificate-errors.
            args.insert(3, "--ignore-certificate-errors-spki-list=%s" % spki)
        try:
            subprocess.Popen(args, start_new_session=True)
            self.statusMessage.emit(
                "Opened a pre-configured browser → %s:%d" % (host, port))
        except Exception as e:                                  # noqa: BLE001
            self.statusMessage.emit("could not open browser: %s" % e)


def _silence_mitm_logging():
    # mitmproxy logs to the root logger; keep our stdout clean.
    import logging
    logging.getLogger("mitmproxy").setLevel(logging.ERROR)


def main():
    _silence_mitm_logging()
    # Use the Fusion Qt Quick Controls style, NOT org.kde.desktop. The desktop
    # style delegates control drawing to the system QStyle (Darkly), and Darkly6
    # SIGSEGVs when driven from QML (it dereferences the null QWidget* that
    # qqc2-desktop-style passes to QStyle::drawControl), crashing the app on
    # launch. Fusion is self-drawn (no QStyle), so it can't hit the Darkly bug;
    # QT_QPA_PLATFORMTHEME=kde still gives it the dark Genesi palette.
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Fusion")
    os.environ.setdefault("QT_QPA_PLATFORMTHEME", "kde")
    # In a VM the guest GL stack lies and Qt Quick's RHI SIGSEGVs creating the GL
    # context; fall back to the software scene graph when virtualized (bare metal
    # keeps GPU rendering). A user QT_QUICK_BACKEND always wins (setdefault).
    try:
        if subprocess.run(["systemd-detect-virt", "--quiet"],
                          timeout=4).returncode == 0:
            os.environ.setdefault("QT_QUICK_BACKEND", "software")
    except Exception:
        pass
    try:
        from PySide6.QtQuickControls2 import QQuickStyle
        QQuickStyle.setStyle("Fusion")
    except ImportError:
        pass

    app = QGuiApplication(sys.argv)
    app.setApplicationName("Genesi API Inspector")
    app.setApplicationDisplayName("Genesi API Inspector")
    app.setOrganizationName("Genesi OS")
    # Match the .desktop so the taskbar shows our name+icon, not "python3".
    app.setDesktopFileName("org.genesi.netinspect")
    app.setWindowIcon(QIcon.fromTheme("genesi-netinspect"))

    backend = Backend()
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("backend", backend)
    engine.rootContext().setContextProperty("PROXY_HOST", PROXY_HOST)
    engine.rootContext().setContextProperty("PROXY_PORT", PROXY_PORT)

    here = os.path.dirname(os.path.abspath(__file__))
    engine.load(QUrl.fromLocalFile(os.path.join(here, "Main.qml")))
    if not engine.rootObjects():
        sys.exit(1)

    backend.start()
    app.aboutToQuit.connect(backend.shutdown)

    # Belt-and-suspenders proxy cleanup. aboutToQuit only fires on a clean Qt
    # quit; it does NOT cover SIGTERM (logout/shutdown), SIGHUP (session end) or
    # a hard exit. Register the same idempotent restore on atexit + those
    # signals so the desktop proxy is flipped back off no matter how we die.
    atexit.register(backend.restore_proxy)

    def _on_signal(signum, _frame):
        backend.restore_proxy()
        # Re-raise with the default handler so the process still terminates.
        signal.signal(signum, signal.SIG_DFL)
        os.kill(os.getpid(), signum)

    for _sig in ("SIGTERM", "SIGINT", "SIGHUP"):
        s = getattr(signal, _sig, None)
        if s is not None:
            try:
                signal.signal(s, _on_signal)
            except (ValueError, OSError):
                pass

    # Python signal handlers only run between bytecodes; while Qt's C++ event
    # loop is blocked they'd never fire. A heartbeat timer hands control back to
    # the interpreter often enough for the handlers above to run.
    from PySide6.QtCore import QTimer
    _pump = QTimer()
    _pump.start(300)
    _pump.timeout.connect(lambda: None)

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
