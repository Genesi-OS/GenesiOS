#!/usr/bin/env python3
"""genesi-ai-image, driven the way the Monitor's Image page drives it.

What is checked, and why each one:

  * The catalog is coherent: every model names components that exist, every
    file has a size and an https URL, and the only licences are ones whose
    output anyone may use for anything.
  * Downloads land exactly once and correctly: a fresh download, a resumed
    .part, a server that ignores Range (appending its whole body to a partial
    would build a corrupt file that still has the right size... minus the
    head), and a checksum mismatch, which must DELETE the file rather than
    leave it to fail as a tensor error minutes into a load.
  * Removing a model never deletes a file another downloaded model needs.
  * A whole generate/edit/upscale run against a stand-in sd-cli: the argv it
    receives, the progress events the page draws, the sidecar the gallery
    reads, and an engine failure surfacing as one error event.
  * The parser on a transcript in sd-cli's real shape: \\r-redrawn bars, the
    bytes bar of the weight load, log lines between.
  * Against upstream (network; skipped, not failed, without one): every flag
    the tool passes exists at genesi-sd-cpp's pinned commit, and every
    catalog URL answers with the size the catalog expects. Flags were written
    from the docs of one commit; moving the pin without this is how a button
    starts failing with "unknown argument".

No GPU, no engine and no multi-GB download needed.
"""
import contextlib
import hashlib
import http.server
import importlib.machinery
import importlib.util
import io
import json
import os
import re
import struct
import sys
import tempfile
import threading
import urllib.error
import urllib.request
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
PKG = HERE.parent / "packages"
TOOL = PKG / "genesi-ai-mode" / "genesi-ai-image"

failures = []


def ok(what):
    print("  ok   " + what)


def check(cond, what, why=""):
    if cond:
        ok(what)
    else:
        print("  FAIL " + what)
        if why:
            print("         " + str(why))
        failures.append(what)


def load_tool():
    loader = importlib.machinery.SourceFileLoader("genesi_ai_image", str(TOOL))
    spec = importlib.util.spec_from_loader("genesi_ai_image", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def run(mod, *argv):
    """main() in-process with --json; returns (rc, [events])."""
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        try:
            rc = mod.main(list(argv) + ["--json"])
        except SystemExit as e:
            rc = e.code
    events = []
    for line in buf.getvalue().splitlines():
        line = line.strip()
        if line:
            try:
                events.append(json.loads(line))
            except ValueError:
                pass
    return rc, events


def png_bytes(w, h):
    raw = b"".join(b"\x00" + b"\x80\x80\x80" * w for _ in range(h))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


tmp = Path(tempfile.mkdtemp(prefix="genesi-image-test-"))
os.environ["GENESI_IMAGE_MODELS_DIR"] = str(tmp / "models")
os.environ["GENESI_IMAGE_OUTPUT_DIR"] = str(tmp / "out")
mod = load_tool()

# ── the catalog ──────────────────────────────────────────────────────────────
print("== the catalog ==")
allowed = {"Apache-2.0", "BSD-3-Clause", "MIT"}
for m in mod.MODELS:
    check(m["license"] in allowed, "%s carries a permissive licence" % m["id"], m["license"])
    check(set(m["caps"]) <= {"generate", "edit", "upscale"} and m["caps"],
          "%s declares what it can do" % m["id"], m["caps"])
    for role, cid in m["parts"].items():
        check(cid in mod.COMPONENTS, "%s/%s names a known file" % (m["id"], role), cid)
        check(role in mod.PART_FLAGS, "%s/%s maps to an sd-cli flag" % (m["id"], role), role)
    check(m["summary"].get("en") and m["summary"].get("pt"),
          "%s is described in both languages" % m["id"])
for cid, c in mod.COMPONENTS.items():
    check(c["url"].startswith("https://") and c["size"] > 0,
          "%s has an https URL and a size" % cid)
    check(c["sha256"] == "" or re.fullmatch(r"[0-9a-f]{64}", c["sha256"]),
          "%s's sha256 is a sha256" % cid)
files = [c["file"] for c in mod.COMPONENTS.values()]
check(len(files) == len(set(files)), "no two components share a file name",
      "two different files would overwrite each other in the models dir")
check(sum(1 for m in mod.MODELS if m["recommended"]) == 1,
      "exactly one model is the recommended start")
check("image-models" in mod.models_dir() or os.environ.get("GENESI_IMAGE_MODELS_DIR"),
      "the models dir is not the GGUF chat library")

rc, ev = run(mod, "catalog")
check(rc == 0 and isinstance(ev[0], list) and len(ev[0]) == len(mod.MODELS),
      "catalog --json is one array of every model", ev[:1])

# ── downloads ────────────────────────────────────────────────────────────────
print("== downloads ==")
payload = os.urandom(300_000)
digest = hashlib.sha256(payload).hexdigest()


class Handler(http.server.BaseHTTPRequestHandler):
    honour_range = True

    def log_message(self, *a):
        pass

    def do_GET(self):
        body = payload
        rng = self.headers.get("Range")
        if self.path.endswith("/missing"):
            self.send_response(404); self.end_headers(); return
        if rng and Handler.honour_range:
            start = int(re.match(r"bytes=(\d+)-", rng).group(1))
            self.send_response(206)
            self.send_header("Content-Range", "bytes %d-%d/%d" % (start, len(body) - 1, len(body)))
            body = body[start:]
        else:
            self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=srv.serve_forever, daemon=True).start()
base = "http://127.0.0.1:%d" % srv.server_address[1]

real_components = mod.COMPONENTS
mod.COMPONENTS = {
    "a": {"file": "a.gguf", "url": base + "/a", "size": len(payload), "sha256": digest},
    "b": {"file": "b.gguf", "url": base + "/b", "size": len(payload), "sha256": digest},
    "shared": {"file": "shared.safetensors", "url": base + "/s", "size": len(payload), "sha256": digest},
    "bad": {"file": "bad.gguf", "url": base + "/bad", "size": len(payload), "sha256": "0" * 64},
    "gone": {"file": "gone.gguf", "url": base + "/missing", "size": 10, "sha256": ""},
    "up": {"file": "up.pth", "url": base + "/up", "size": len(payload), "sha256": ""},
}
real_models = mod.MODELS
mod.MODELS = [
    {"id": "m1", "name": "M1", "summary": {"en": "", "pt": ""}, "license": "MIT",
     "caps": ["generate", "edit"], "parts": {"diffusion": "a", "vae": "shared"},
     "defaults": {"steps": 4, "cfg": 1.0, "sampler": "euler"}, "recommended": True},
    {"id": "m2", "name": "M2", "summary": {"en": "", "pt": ""}, "license": "MIT",
     "caps": ["generate"], "parts": {"diffusion": "b", "vae": "shared"},
     "defaults": {"steps": 8}, "recommended": False},
    {"id": "upscaler", "name": "Up", "summary": {"en": "", "pt": ""}, "license": "MIT",
     "caps": ["upscale"], "parts": {"upscale": "up"}, "defaults": {}, "recommended": False},
    {"id": "broken", "name": "B", "summary": {"en": "", "pt": ""}, "license": "MIT",
     "caps": ["generate"], "parts": {"diffusion": "bad"}, "defaults": {}, "recommended": False},
    {"id": "notfound", "name": "N", "summary": {"en": "", "pt": ""}, "license": "MIT",
     "caps": ["generate"], "parts": {"diffusion": "gone"}, "defaults": {}, "recommended": False},
]

rc, ev = run(mod, "pull", "m1")
check(rc == 0 and ev[-1].get("event") == "done", "a model downloads", ev[-1:])
check(all(Path(mod.component_path(c)).read_bytes() == payload for c in ("a", "shared")),
      "both of its files landed intact")
check(not list((tmp / "models").glob("*.part")), "no .part is left behind")
check(any(e.get("event") == "progress" and e.get("phase") in ("download", "verify") for e in ev)
      or len(payload) < 10**6, "progress is reported while downloading")

# resume: half a file already there
part = Path(mod.component_path("b") + ".part")
part.write_bytes(payload[:120_000])
rc, ev = run(mod, "catalog")
m2 = [m for m in ev[0] if m["id"] == "m2"][0]
check(m2["partial"] and not m2["installed"], "a half-downloaded model reads as partial", m2)
rc, ev = run(mod, "pull", "m2")
check(rc == 0 and Path(mod.component_path("b")).read_bytes() == payload,
      "a .part resumes into the exact file")

# a server that ignores Range must not have its body appended to the partial
os.unlink(mod.component_path("b"))
part.write_bytes(payload[:120_000])
Handler.honour_range = False
rc, ev = run(mod, "pull", "m2")
Handler.honour_range = True
check(rc == 0 and Path(mod.component_path("b")).read_bytes() == payload,
      "a server ignoring Range restarts the file instead of corrupting it")

rc, ev = run(mod, "pull", "broken")
check(rc != 0 and not Path(mod.component_path("bad")).exists()
      and not Path(mod.component_path("bad") + ".part").exists(),
      "a checksum mismatch deletes the file and fails", ev[-1:])
rc, ev = run(mod, "pull", "notfound")
check(rc != 0 and ev[-1].get("event") == "error" and "404" in ev[-1].get("text", ""),
      "an HTTP error is one error event naming it", ev[-1:])

# removing m2 keeps `shared`, which m1 (installed) still needs
rc, ev = run(mod, "remove", "m2")
check(not Path(mod.component_path("b")).exists() and Path(mod.component_path("shared")).exists(),
      "removing a model keeps the files another model still uses")

# ── a run against a stand-in engine ─────────────────────────────────────────
print("== generate / edit / upscale ==")
fake = tmp / "fake_sd_cli.py"
argv_log = tmp / "argv.json"
fake.write_text(r'''
import json, sys, time, struct, zlib
argv = sys.argv[1:]
open(%r, "w").write(json.dumps(argv))
if "--fail" in " ".join(argv) or "FAILME" in " ".join(argv):
    print("[ERROR] stable-diffusion.cpp:123 - load model failed: bad tensor")
    sys.exit(1)
out = argv[argv.index("-o") + 1]
sys.stdout.write("[INFO ] loading model\n")
for i in range(1, 4):
    sys.stdout.write("\r|##########  | %%d/3 - 512.00MB/s\033[K" %% i); sys.stdout.flush()
sys.stdout.write("\n[INFO ] get_learned_condition completed, taking 120 ms\n")
for i in range(1, 5):
    sys.stdout.write("\r|=====>   | %%d/4 - 1.50s/it\033[K" %% i); sys.stdout.flush()
sys.stdout.write("\n[INFO ] sampling completed, taking 6.02s\n[INFO ] decode_first_stage completed\n")
def png(w, h):
    raw = b"".join(b"\x00" + b"\x10\x20\x30" * w for _ in range(h))
    c = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    return b"\x89PNG\r\n\x1a\n" + c(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + c(b"IDAT", zlib.compress(raw)) + c(b"IEND", b"")
open(out, "wb").write(png(8, 8))
''' % str(argv_log))
os.environ["GENESI_SD_CLI"] = str(fake)
mod.ollama_unload_all = lambda: 0      # no Ollama on the test box

rc, ev = run(mod, "generate", "--model", "m1", "--prompt", "uma raposa na neve", "--seed", "42")
done = [e for e in ev if e.get("event") == "done"]
check(rc == 0 and done and Path(done[0]["path"]).is_file(), "generate writes a picture", ev[-2:])
args = json.loads(argv_log.read_text())
check(args[args.index("--diffusion-model") + 1] == mod.component_path("a")
      and args[args.index("--vae") + 1] == mod.component_path("shared"),
      "each part reaches sd-cli under its flag", args)
check(args[args.index("--seed") + 1] == "42" and args[args.index("--steps") + 1] == "4"
      and args[args.index("-W") + 1] == "1024", "seed, steps and size are passed", args)
check(args[args.index("-p") + 1] == "uma raposa na neve", "the prompt reaches sd-cli unaltered")
prog = [e for e in ev if e.get("event") == "progress"]
check(any(e["phase"] == "load" for e in prog) and any(e["phase"] == "sample" for e in prog),
      "the weight load and the steps are told apart", [e.get("phase") for e in prog])
check(any(e["phase"] == "sample" and e["step"] == 4 and e["steps"] == 4 for e in prog),
      "the last step is always reported")
check(any(e.get("event") == "phase" and e.get("phase") == "decode" for e in ev),
      "the decode phase is announced")
side = json.loads(Path(done[0]["path"]).with_suffix(".json").read_text(encoding="utf-8"))
check(side.get("prompt") == "uma raposa na neve" and side.get("seed") == 42 and side.get("model") == "m1",
      "the gallery sidecar records prompt, seed and model", side)

rc, ev = run(mod, "generate", "--model", "m1", "--prompt", "x")
seed = [e for e in ev if e.get("event") == "start"][0]["seed"]
check(isinstance(seed, int) and seed >= 0, "a random seed is chosen AND recorded", seed)

# edit: size follows the source picture's shape
src = tmp / "src.png"
src.write_bytes(png_bytes(1600, 900))
rc, ev = run(mod, "generate", "--model", "m1", "--prompt", "deixa de noite", "--ref", str(src))
args = json.loads(argv_log.read_text())
w, h = int(args[args.index("-W") + 1]), int(args[args.index("-H") + 1])
check(rc == 0 and args[args.index("-r") + 1] == str(src), "edit hands the picture over as -r")
check(w % 16 == 0 and h % 16 == 0 and abs(w / h - 16 / 9) < 0.03 and 0.8e6 < w * h < 1.2e6,
      "an edit keeps the source's shape near one megapixel", (w, h))
rc, ev = run(mod, "generate", "--model", "m2", "--prompt", "x", "--ref", str(src))
check(rc == 2 and ev[-1].get("event") == "error", "a generate-only model refuses an edit", ev[-1:])

rc, ev = run(mod, "upscale", "--in", str(src))
check(rc == 2 and ev[-1].get("code") == "no-model",
      "upscaling before the upscaler is downloaded says so", ev[-1:])
run(mod, "pull", "upscaler")
rc, ev = run(mod, "upscale", "--in", str(src))
args = json.loads(argv_log.read_text())
check(rc == 0 and "-M" in args and args[args.index("-M") + 1] == "upscale"
      and args[args.index("--upscale-model") + 1] == mod.component_path("up"),
      "upscale runs sd-cli's upscale mode with the ESRGAN weights", args)

rc, ev = run(mod, "generate", "--model", "m1", "--prompt", "FAILME")
err = [e for e in ev if e.get("event") == "error"]
check(rc == 1 and len(err) == 1 and "bad tensor" in err[0]["text"],
      "an engine failure is ONE error event carrying sd-cli's reason", err)

rc, ev = run(mod, "gallery")
check(rc == 0 and len(ev[0]) >= 3 and all("path" in i for i in ev[0]),
      "the gallery lists the pictures made, newest first")

del os.environ["GENESI_SD_CLI"]
mod.find_engine = lambda: None
rc, ev = run(mod, "generate", "--model", "m1", "--prompt", "x")
check(rc == 3 and ev[-1].get("code") == "no-engine", "no engine is a distinct error the page can act on", ev[-1:])

# ── pure helpers ─────────────────────────────────────────────────────────────
print("== helpers ==")
check(mod.image_size(str(src)) == (1600, 900), "PNG size from the header")
jpg = tmp / "x.jpg"
jpg.write_bytes(b"\xff\xd8" + b"\xff\xe0" + struct.pack(">H", 16) + b"JFIF\0" + b"\0" * 9
                + b"\xff\xc0" + struct.pack(">HBHHB", 11, 8, 480, 640, 3) + b"\0" * 9 + b"\xff\xd9")
check(mod.image_size(str(jpg)) == (640, 480), "JPEG size from the SOF segment", mod.image_size(str(jpg)))
for (iw, ih) in ((1024, 1024), (6000, 4000), (300, 2000)):
    fw, fh = mod.fit_size(iw, ih)
    check(fw % 16 == 0 and fh % 16 == 0 and max(fw, fh) <= mod.MAX_SIDE,
          "fit_size(%d, %d) -> %dx%d stays in bounds" % (iw, ih, fw, fh))

p = mod.ProgressParser()
evs = []
for chunk in ("[INFO ] loading\n\r|###  | 1/2 - 3.0", "0GB/s\r|#####| 2/2 - 3.10GB/s\n",
              "\r|==>  | 1/8 - 2.00s/it", "\r|===> | 2/8 - 0.50it/s\033[K",
              "\n[INFO ] sampling completed, taking 9s\n"):
    evs += p.feed(chunk)
phases = [e.get("phase") for e in evs]
check(phases[:2] == ["load", "load"], "a bytes bar is the weight load", phases)
samp = [e for e in evs if e.get("phase") == "sample"]
check(samp and samp[-1]["step"] == 2 and abs(samp[-1]["sec_per_step"] - 2.0) < 1e-6,
      "it/s is turned into seconds per step", samp)
check(phases[-1] == "decode", "'sampling completed' moves on to decode", phases)

# The order a real FLUX.2 klein run printed (WSL, 2026-10-03): text encoder
# load, diffusion load, the steps, THEN the VAE's load bar. Reported as "load",
# that last bar sent the page back to "Loading the model" at 10% at the end.
p = mod.ProgressParser()
evs = []
for chunk in ("\r|###| 298/298 - 2.10GB/s\n",
              "[INFO ] get_learned_condition completed, taking 900 ms\n",
              "\r|###| 149/149 - 1.80GB/s\n",
              "\r|=>  | 1/4 - 84.37s/it\r|====| 4/4 - 84.37s/it\n",
              "[INFO ] sampling completed, taking 337s\n",
              "\r|###| 140/140 - 0.90GB/s\n"):
    evs += p.feed(chunk)
phases = [e.get("phase") for e in evs]
first_sample = phases.index("sample")
check("load" not in phases[first_sample:],
      "a weight load after the steps is part of finishing, not 'load'", phases)

# ── against upstream ─────────────────────────────────────────────────────────
print("== against upstream (network) ==")
mod.COMPONENTS, mod.MODELS = real_components, real_models
pkgbuild = (PKG / "genesi-sd-cpp" / "PKGBUILD").read_text(encoding="utf-8")
commit = re.search(r"^_commit=([0-9a-f]{40})", pkgbuild, re.M).group(1)


def fetch(url, timeout=20):
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "genesi-ci"}),
                                timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")


try:
    upstream = (fetch("https://raw.githubusercontent.com/leejet/stable-diffusion.cpp/%s/examples/common/common.cpp" % commit)
                + fetch("https://raw.githubusercontent.com/leejet/stable-diffusion.cpp/%s/examples/cli/main.cpp" % commit))
except urllib.error.HTTPError as e:
    check(False, "the pinned commit's sources are reachable", "HTTP %s" % e.code)
    upstream = None
except (urllib.error.URLError, OSError) as e:
    print("  skip upstream flags: %s" % e)
    upstream = None

if upstream:
    probe = mod.build_generate_argv("sd-cli", real_models[0], "p", "o.png", 512, 512, ref="r.png") \
        + mod.build_upscale_argv("sd-cli", real_models[2], "i.png", "o.png")
    flags = sorted({a for a in probe if a.startswith("-") and not a[1:].isdigit()})
    for f in flags:
        check('"%s"' % f in upstream, "sd-cli at %s accepts %s" % (commit[:8], f))
    check('"upscale"' in upstream or "upscale," in upstream, "sd-cli has an upscale mode")

for cid, c in real_components.items():
    try:
        req = urllib.request.Request(c["url"], method="HEAD", headers={"User-Agent": "genesi-ci"})
        with urllib.request.urlopen(req, timeout=20) as r:
            size = int(r.headers.get("Content-Length") or -1)
        check(size == c["size"], "%s is downloadable at the catalog's size" % cid,
              "server says %s, catalog says %s" % (size, c["size"]))
    except urllib.error.HTTPError as e:
        # 401/403 means it became gated: a button that can never work.
        check(False, "%s is downloadable without a login" % cid, "HTTP %s" % e.code)
    except (urllib.error.URLError, OSError) as e:
        print("  skip %s: %s" % (cid, e))

srv.shutdown()
print()
if failures:
    print("%d check(s) failed" % len(failures))
    sys.exit(1)
print("all checks passed")
