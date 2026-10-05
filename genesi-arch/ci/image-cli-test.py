#!/usr/bin/env python3
"""genesi-ai-image, driven the way the Monitor's Image page drives it.

What is checked, and why each one:

  * The catalog is coherent: every model names files that exist, every file
    has a size, an https URL and a real SHA-256, every model has a variant the
    tool can recommend, and no two files share a name on disk.
  * Downloads land exactly once and correctly: fresh, resumed from a .part,
    from a server that ignores Range, and a checksum mismatch, which must
    DELETE the file rather than leave it to fail minutes into a load.
  * A converting variant (the SDXL checkpoints) downloads its fp16 source,
    converts it with the engine, keeps only the GGUF, and never leaves a
    half-written file that looks like a model.
  * Removing never deletes a file another downloaded model still uses.
  * A whole run against a stand-in sd-cli: the argv per mode (generate,
    instruction edit, img2img), the per-backend flags (flash attention only
    off Vulkan -- upstream says it slows the other backends), the VAE tiling
    an edit needs (encoding has no out-of-memory retry upstream: the 8 GB
    edit failure), and the progress events the page draws.
  * Out of memory: the run retries once in low-memory mode by itself, and
    when that fails too, the error says WHY -- not sd-cli's closing "generate
    failed", which is all the page used to show.
  * Turbo: a warm stand-in sd-server is started once, takes two pictures
    without a restart, carries the Lightning LoRA in the request, and stops
    on `server stop`.
  * Importing a checkpoint reads its family from the tensor names.
  * Against upstream (network; skipped, not failed, without one): every flag
    the tool can pass exists at genesi-sd-cpp's pinned commit, every catalog
    URL answers with the size the catalog expects, and every Hugging Face
    hash is the one the Hub reports -- a hash typed from memory would make a
    good download delete itself.

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
import time
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
            print("         " + str(why)[:600])
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
for k, sub in (("GENESI_IMAGE_MODELS_DIR", "models"), ("GENESI_IMAGE_OUTPUT_DIR", "out"),
               ("GENESI_IMAGE_CACHE_DIR", "cache"), ("GENESI_IMAGE_RUNTIME_DIR", "run")):
    os.environ[k] = str(tmp / sub)
os.environ["GENESI_IMAGE_VRAM_MB"] = "8192"
mod = load_tool()
real_components, real_models = dict(mod.COMPONENTS), list(mod.MODELS)

# ── the catalog ──────────────────────────────────────────────────────────────
print("== the catalog ==")
for m in mod.MODELS:
    check(set(m["caps"]) <= {"generate", "edit", "img2img", "upscale"} and m["caps"],
          "%s declares what it can do" % m["id"], m["caps"])
    check(m["summary"].get("en") and m["summary"].get("pt"), "%s is described in both languages" % m["id"])
    check(m["variants"], "%s has at least one variant" % m["id"])
    for v in m["variants"]:
        parts = mod.variant_parts(m, v)
        for role, ref in parts.items():
            check(role in mod.PART_FLAGS, "%s/%s: role %s maps to a flag" % (m["id"], v["id"], role))
            check(os.path.isabs(ref) or ref in mod.COMPONENTS,
                  "%s/%s: %s names a known file" % (m["id"], v["id"], role), ref)
        if "convert" in v:
            check(v["convert"]["from"] in mod.COMPONENTS, "%s/%s converts a known file" % (m["id"], v["id"]))
    lora = (m.get("turbo") or {}).get("lora")
    if lora:
        check(lora in mod.COMPONENTS, "%s's Turbo LoRA is a known file" % m["id"])
    check(mod.recommended_variant(m, 8192) in m["variants"], "%s recommends a variant on 8 GB" % m["id"])
for cid, c in mod.COMPONENTS.items():
    check(c["url"].startswith("https://") and c["size"] > 0, "%s has an https URL and a size" % cid)
    check(re.fullmatch(r"[0-9a-f]{64}", c["sha256"] or ""), "%s carries a full sha256" % cid, c["sha256"])
files = [c["file"] for c in mod.COMPONENTS.values()]
check(len(files) == len(set(files)), "no two components share a file name")
check(sum(1 for m in mod.MODELS if m["recommended"] and "upscale" not in m["caps"]) == 1,
      "exactly one model is the recommended start")
check(any("unfiltered" in m.get("tags", []) for m in mod.MODELS)
      and any("edit" in m["caps"] for m in mod.MODELS)
      and any("img2img" in m["caps"] for m in mod.MODELS),
      "the catalog has unfiltered models, instruction editors and img2img editors")
sdxl = mod.model_by_id("juggernaut-xl")
check(mod.recommended_variant(sdxl, 8192)["id"] == "q8",
      "an SDXL checkpoint recommends its optimized Q8 over the fp16 file")

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

C = lambda f, path, sha=digest: {"file": f, "url": base + path, "size": len(payload), "sha256": sha}
mod.COMPONENTS = {
    "a": C("a.gguf", "/a"), "a8": C("a8.gguf", "/a8"), "b": C("b.gguf", "/b"),
    "shared": C("shared.safetensors", "/s"), "llm": C("llm.gguf", "/l"),
    "lora": C("lora.safetensors", "/lo"),
    "bad": C("bad.gguf", "/bad", "0" * 64), "gone": dict(C("gone.gguf", "/missing"), size=10),
    "up": C("up.pth", "/up", ""), "ckpt": C("ckpt.safetensors", "/ck"),
}
D = {"steps": 4, "cfg": 1.0, "sampler": "euler", "base": 1024}
mod.MODELS = [
    {"id": "m1", "name": "M1", "summary": {"en": "", "pt": ""}, "license": "MIT",
     "caps": ["generate", "edit"], "tags": [], "parts": {"vae": "shared", "llm": "llm"},
     "variants": [{"id": "q4", "label": "Q4", "parts": {"diffusion": "a"}},
                  {"id": "q8", "label": "Q8", "parts": {"diffusion": "a8"}}],
     "defaults": D, "turbo": {}, "recommended": True},
    {"id": "m2", "name": "M2", "summary": {"en": "", "pt": ""}, "license": "MIT",
     "caps": ["generate", "img2img"], "tags": ["unfiltered"], "parts": {"vae": "shared"},
     "variants": [{"id": "q4", "label": "Q4", "parts": {"diffusion": "b"}}],
     "defaults": dict(D, steps=20, cfg=4.0, negative="ugly"),
     "turbo": {"lora": "lora", "steps": 4, "cfg": 1.0}, "recommended": False},
    {"id": "sx", "name": "SX", "family": "sdxl", "summary": {"en": "", "pt": ""}, "license": "MIT",
     "caps": ["generate", "img2img"], "tags": [], "parts": {"vae": "shared"},
     "variants": [{"id": "q8", "label": "Q8", "convert": {"from": "ckpt", "type": "q8_0",
                                                         "file": "sx-q8_0.gguf", "role": "model"}},
                  {"id": "fp16", "label": "FP16", "parts": {"model": "ckpt"}}],
     "defaults": dict(D, steps=28, cfg=5.5), "turbo": {"cache": "ucache"}, "recommended": False},
    {"id": "upscaler", "name": "Up", "summary": {"en": "", "pt": ""}, "license": "MIT",
     "caps": ["upscale"], "tags": [], "parts": {},
     "variants": [{"id": "x4", "label": "x4", "parts": {"upscale": "up"}}],
     "defaults": {}, "turbo": {}, "recommended": False},
    {"id": "broken", "name": "B", "summary": {"en": "", "pt": ""}, "license": "MIT",
     "caps": ["generate"], "tags": [], "parts": {},
     "variants": [{"id": "x", "label": "x", "parts": {"diffusion": "bad"}}],
     "defaults": D, "turbo": {}, "recommended": False},
    {"id": "notfound", "name": "N", "summary": {"en": "", "pt": ""}, "license": "MIT",
     "caps": ["generate"], "tags": [], "parts": {},
     "variants": [{"id": "x", "label": "x", "parts": {"diffusion": "gone"}}],
     "defaults": D, "turbo": {}, "recommended": False},
]

rc, ev = run(mod, "pull", "m1", "--variant", "q4")
check(rc == 0 and ev[-1].get("event") == "done", "a model variant downloads", ev[-1:])
check(all(Path(mod.component_path(c)).read_bytes() == payload for c in ("a", "shared", "llm")),
      "its files and the shared ones landed intact")
check(not Path(mod.component_path("a8")).exists(), "the other variant is not downloaded")
rc, ev = run(mod, "catalog")
q8 = [v for v in [m for m in ev[0] if m["id"] == "m1"][0]["variants"] if v["id"] == "q8"][0]
check(q8["download"] == len(payload),
      "the other variant's download counts only its own file, not the shared ones already here", q8)
check(not list((tmp / "models").glob("*.part")), "no .part is left behind")

part = Path(mod.component_path("b") + ".part")
part.write_bytes(payload[:120_000])
rc, ev = run(mod, "catalog")
m2 = [m for m in ev[0] if m["id"] == "m2"][0]
check(m2["partial"] and not m2["installed"], "a half-downloaded model reads as partial", m2)
rc, ev = run(mod, "pull", "m2")
check(rc == 0 and Path(mod.component_path("b")).read_bytes() == payload, "a .part resumes into the exact file")
check(Path(mod.component_path("lora")).exists(), "a model's Turbo LoRA comes with it")

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
check(rc != 0 and "404" in ev[-1].get("text", ""), "an HTTP error is one error event naming it", ev[-1:])

# ── the stand-in engine ─────────────────────────────────────────────────────
fake = tmp / "fake_sd_cli.py"
argv_log = tmp / "argv.jsonl"
fake.write_text(r'''
import json, sys, struct, zlib
argv = sys.argv[1:]
open(%r, "a").write(json.dumps(argv) + "\n")
def png(w, h):
    raw = b"".join(b"\x00" + b"\x10\x20\x30" * w for _ in range(h))
    c = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    return b"\x89PNG\r\n\x1a\n" + c(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + c(b"IDAT", zlib.compress(raw)) + c(b"IEND", b"")
if "--list-devices" in argv:
    print("Vulkan0\tFake GPU\nCPU\tFake CPU"); sys.exit(0)
out = argv[argv.index("-o") + 1]
if "-M" in argv and argv[argv.index("-M") + 1] == "convert":
    for i in range(1, 4):
        sys.stdout.write("\r|####| %%d/3 - 900.00MB/s" %% i); sys.stdout.flush()
    open(out, "wb").write(b"GGUF-converted")
    print("\n[INFO ] convert success"); sys.exit(0)
text = " ".join(argv)
if "FAILME" in text or ("OOMME" in text and "--offload-to-cpu" not in text):
    print("[ERROR] ggml_vulkan: Device memory allocation of size 1610612736 failed.")
    print("[ERROR] encode_first_stage failed")
    print("[ERROR] main.cpp:928 - generate failed")
    sys.exit(1)
sys.stdout.write("[INFO ] loading model\n")
for i in range(1, 4):
    sys.stdout.write("\r|##########  | %%d/3 - 512.00MB/s\033[K" %% i); sys.stdout.flush()
sys.stdout.write("\n[INFO ] get_learned_condition completed, taking 120 ms\n")
for i in range(1, 5):
    sys.stdout.write("\r|=====>   | %%d/4 - 1.50s/it\033[K" %% i); sys.stdout.flush()
sys.stdout.write("\n[INFO ] sampling completed, taking 6.02s\n")
sys.stdout.write("\r|##| 2/2 - 300.00MB/s\n[INFO ] decode_first_stage completed\n")
open(out, "wb").write(png(8, 8))
''' % str(argv_log))
os.environ["GENESI_SD_CLI"] = str(fake)
mod.ollama_unload_all = lambda: 0


def last_argv():
    return json.loads(argv_log.read_text().strip().splitlines()[-1])


# ── a converting variant ────────────────────────────────────────────────────
print("== converting variants ==")
rc, ev = run(mod, "pull", "sx")
gguf = tmp / "models" / "sx-q8_0.gguf"
check(rc == 0 and gguf.read_bytes() == b"GGUF-converted" and Path(str(gguf) + ".ok").exists(),
      "an SDXL checkpoint is converted to GGUF after its download", ev[-2:])
check(not Path(mod.component_path("ckpt")).exists(),
      "the 7 GB fp16 source is deleted once converted (no fp16 variant kept)")
check(not list((tmp / "models").glob("*.converting")), "no half-written GGUF is left")
a = last_argv()
check(a[a.index("-M") + 1] == "convert" and a[a.index("--type") + 1] == "q8_0", "the engine is asked for q8_0", a)
rc, ev = run(mod, "catalog")
sxs = [m for m in ev[0] if m["id"] == "sx"][0]
check(sxs["installed"] and [v for v in sxs["variants"] if v["id"] == "q8"][0]["installed"],
      "the converted variant reads as installed")

# ── generate / edit / img2img ───────────────────────────────────────────────
print("== generate / edit / img2img ==")
rc, ev = run(mod, "generate", "--model", "m1", "--prompt", "uma raposa na neve", "--seed", "42")
done = [e for e in ev if e.get("event") == "done"]
check(rc == 0 and done and Path(done[0]["path"]).is_file(), "generate writes a picture", ev[-2:])
a = last_argv()
check(a[a.index("--diffusion-model") + 1] == mod.component_path("a")
      and a[a.index("--vae") + 1] == mod.component_path("shared")
      and a[a.index("--llm") + 1] == mod.component_path("llm"),
      "each part reaches sd-cli under its flag (the installed variant)", a)
check(a[a.index("--seed") + 1] == "42" and a[a.index("--steps") + 1] == "4" and a[a.index("-W") + 1] == "1024",
      "seed, steps and size are passed", a)
check("--diffusion-fa" not in a, "no flash attention on Vulkan (upstream: it slows non-CUDA backends)", a)
check("--vae-tiling" not in a, "a plain generation is not tiled")
prog = [e for e in ev if e.get("event") == "progress"]
phases = [e.get("phase") for e in ev if e.get("event") in ("progress", "phase")]
check("load" in phases and "sample" in phases and phases[-1] == "decode",
      "load, steps and the final decode are told apart -- the VAE's late load bar included", phases)
side = json.loads(Path(done[0]["path"]).with_suffix(".json").read_text(encoding="utf-8"))
check(side.get("prompt") == "uma raposa na neve" and side.get("seed") == 42 and side.get("variant") == "q4",
      "the sidecar records prompt, seed and variant", side)

src = tmp / "src.png"
src.write_bytes(png_bytes(1600, 900))
rc, ev = run(mod, "generate", "--model", "m1", "--mode", "edit", "--prompt", "deixa de noite", "--ref", str(src))
a = last_argv()
w, h = int(a[a.index("-W") + 1]), int(a[a.index("-H") + 1])
check(rc == 0 and a[a.index("-r") + 1] == str(src), "an instruction edit hands the picture over as -r", a)
check("--vae-tiling" in a, "an edit tiles the VAE (encoding has no OOM retry upstream)", a)
check(abs(w / h - 16 / 9) < 0.03 and w % 16 == 0, "an edit keeps the source's shape", (w, h))

rc, ev = run(mod, "generate", "--model", "m2", "--mode", "img2img", "--prompt", "oil painting",
             "--ref", str(src), "--strength", "0.45")
a = last_argv()
check(rc == 0 and a[a.index("-i") + 1] == str(src) and a[a.index("--strength") + 1] == "0.45"
      and "--vae-tiling" in a, "img2img starts from the picture at the asked strength", a)
check(a[a.index("-n") + 1] == "ugly" and a[a.index("--cfg-scale") + 1] == "4.0",
      "a model's own negative prompt and cfg are used", a)
rc, ev = run(mod, "generate", "--model", "m1", "--mode", "img2img", "--prompt", "x", "--ref", str(src))
check(rc == 2, "a model without img2img refuses it", ev[-1:])

rc, ev = run(mod, "generate", "--model", "sx", "--prompt", "portrait")
a = last_argv()
check(rc == 0 and a[a.index("-m") + 1] == str(gguf), "a converted model runs from its GGUF with -m", a)

# Turbo off the warm path: the LoRA and its step count still apply.
os.environ["GENESI_SD_SERVER"] = str(tmp / "no-server")
rc, ev = run(mod, "generate", "--model", "m2", "--prompt", "fast one", "--turbo")
a = last_argv()
check(rc == 0 and a[a.index("--steps") + 1] == "4" and "<lora:lora:1>" in a[a.index("-p") + 1]
      and a[a.index("--lora-model-dir") + 1] == mod.models_dir(),
      "Turbo applies the Lightning LoRA: 4 steps, cfg 1", a)
check("-n" not in a, "no negative prompt is encoded at cfg 1")
del os.environ["GENESI_SD_SERVER"]

# ── out of memory ───────────────────────────────────────────────────────────
print("== out of memory ==")
rc, ev = run(mod, "generate", "--model", "m1", "--prompt", "OOMME big edit", "--ref", str(src), "--mode", "edit")
retry = [e for e in ev if e.get("code") == "retry"]
a = last_argv()
check(rc == 0 and retry and "--offload-to-cpu" in a and "--vae-tiling" in a,
      "an out-of-memory run retries itself in low-memory mode, and succeeds", ev[-3:])
check([e for e in ev if e.get("event") == "done"][0].get("low_memory") is True,
      "the result says it was made in low-memory mode")
rc, ev = run(mod, "generate", "--model", "m1", "--prompt", "FAILME")
err = [e for e in ev if e.get("event") == "error"]
check(rc == 1 and len(err) == 1, "a failure that survives the retry is ONE error event", err)
check(err and "generate failed" not in err[0]["text"] and err[0].get("code") == "oom"
      and "memory" in err[0]["text"], "the error says why (out of video memory), not sd-cli's generic last line", err)
check(err and Path(err[0].get("log", "")).is_file() and "Device memory allocation" in Path(err[0]["log"]).read_text(),
      "the full engine output is kept in last-run.log for the page's Show details", err)

# ── upscale ─────────────────────────────────────────────────────────────────
rc, ev = run(mod, "upscale", "--in", str(src))
check(rc == 2 and ev[-1].get("code") == "no-model", "upscaling before the upscaler is downloaded says so", ev[-1:])
run(mod, "pull", "upscaler")
rc, ev = run(mod, "upscale", "--in", str(src))
a = last_argv()
check(rc == 0 and a[a.index("-M") + 1] == "upscale" and a[a.index("--upscale-model") + 1] == mod.component_path("up"),
      "upscale runs sd-cli's upscale mode with the ESRGAN weights", a)

# ── removal ─────────────────────────────────────────────────────────────────
rc, ev = run(mod, "remove", "m2")
check(not Path(mod.component_path("b")).exists() and Path(mod.component_path("shared")).exists(),
      "removing a model keeps the files another model still uses")

# ── Turbo: the warm server ──────────────────────────────────────────────────
print("== Turbo (warm server) ==")
fake_srv = tmp / "fake_sd_server.py"
bodies = tmp / "bodies.jsonl"
starts = tmp / "starts.log"
fake_srv.write_text(r'''
import base64, json, sys, threading, time, struct, zlib, http.server
argv = sys.argv[1:]
port = int(argv[argv.index("--listen-port") + 1])
open(%r, "a").write(json.dumps(argv) + "\n")
jobs = {}
def png():
    raw = b"\x00" + b"\x10\x20\x30" * 4
    raw = raw * 4
    c = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    return b"\x89PNG\r\n\x1a\n" + c(b"IHDR", struct.pack(">IIBBBBB", 4, 4, 8, 2, 0, 0, 0)) + c(b"IDAT", zlib.compress(raw)) + c(b"IEND", b"")
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, obj):
        b = json.dumps(obj).encode(); self.send_response(code)
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        if self.path == "/sdcpp/v1/capabilities": return self.send(200, {"model": "fake"})
        jid = self.path.rsplit("/", 1)[-1]
        self.send(200, jobs.get(jid, {"status": "failed", "error": {"message": "no job"}}))
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])) or b"{}")
        if self.path.endswith("/cancel"): return self.send(409, {"error": "generating"})
        open(%r, "a").write(json.dumps(body) + "\n")
        jid = "j%%d" %% len(jobs)
        jobs[jid] = {"status": "generating"}
        def work():
            for i in range(1, 5):
                sys.stdout.write("\r|====| %%d/4 - 0.50it/s" %% i); sys.stdout.flush(); time.sleep(0.05)
            sys.stdout.write("\n[INFO ] sampling completed\n"); sys.stdout.flush()
            jobs[jid] = {"status": "completed", "result": {"images": [{"b64_json": base64.b64encode(png()).decode()}]}}
        threading.Thread(target=work, daemon=True).start()
        self.send(202, {"id": jid})
import os
# The real sd-server loads every weight BEFORE it answers.
for i in range(1, 4):
    sys.stdout.write("\r|###| %%d/3 - 100.00MB/s" %% i); sys.stdout.flush()
    time.sleep(float(os.environ.get("FAKE_LOAD_SECONDS", "0")) / 3)
print("\n[INFO ] listening on: http://127.0.0.1:%%d" %% port, flush=True)
http.server.ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
''' % (str(starts), str(bodies)))
os.environ["GENESI_SD_SERVER"] = str(fake_srv)
run(mod, "pull", "m2")
t0 = time.time()
rc, ev = run(mod, "generate", "--model", "m2", "--prompt", "first", "--turbo", "--seed", "1")
check(rc == 0 and any(e.get("text") == "warm engine ready" for e in ev),
      "Turbo starts the warm engine and draws through it", ev[-3:])
rc2, ev2 = run(mod, "generate", "--model", "m2", "--prompt", "second", "--turbo", "--seed", "2")
n_starts = len(starts.read_text().strip().splitlines()) if starts.exists() else 0
check(rc2 == 0 and n_starts == 1, "a second picture reuses the warm engine -- no reload", (rc2, n_starts))
reqs = [json.loads(l) for l in bodies.read_text().splitlines()]
check(reqs and reqs[-1]["prompt"] == "second" and reqs[-1]["sample_params"]["sample_steps"] == 4
      and reqs[-1].get("lora") == [{"path": "lora.safetensors", "multiplier": 1.0}],
      "the request carries prompt, Turbo steps and the LoRA by file name", reqs[-1:])
check(any(e.get("event") == "progress" and e.get("phase") == "sample" for e in ev2),
      "steps are reported from the warm engine's own output")
sv = json.loads(starts.read_text().splitlines()[0])
check("--lora-model-dir" in sv and "--listen-ip" in sv and sv[sv.index("--listen-ip") + 1] == "127.0.0.1",
      "the warm engine listens on loopback only, with the LoRA directory", sv)
run(mod, "server", "stop")
time.sleep(1)
starts.write_text("")
rc, ev = run(mod, "generate", "--model", "m1", "--prompt", "no lora model", "--turbo", "--seed", "3")
sv = json.loads(starts.read_text().strip().splitlines()[-1])
check(rc == 0 and "--lora-model-dir" in sv and sv[sv.index("--lora-model-dir") + 1] == mod.models_dir(),
      "even a model with no LoRA starts the server with a LoRA dir (it scans '.' recursively otherwise)", sv)

rc, ev = run(mod, "generate", "--model", "m2", "--mode", "img2img", "--prompt", "edit", "--ref", str(src), "--turbo")
reqs = [json.loads(l) for l in bodies.read_text().splitlines()]
check(rc == 0 and reqs[-1].get("init_image") and reqs[-1].get("vae_tiling_params") == {"enabled": True},
      "img2img through the warm engine sends the picture and tiles the VAE", list(reqs[-1].keys()))
rc, ev = run(mod, "server", "status")
check(ev and ev[0].get("running") and ev[0].get("model") == "m2", "server status names the warm model", ev)

# A load longer than the idle limit must not get the server killed as
# "idle": the first real run lost its server at exactly WARM_IDLE while it
# was still reading weights.
run(mod, "server", "stop")
time.sleep(1)
os.environ["FAKE_LOAD_SECONDS"] = "9"
os.environ["GENESI_IMAGE_WARM_IDLE"] = "3"
mod.WARM_IDLE = 3
rc, ev = run(mod, "generate", "--model", "m2", "--prompt", "slow load", "--turbo", "--seed", "5")
check(rc == 0 and any(e.get("text") == "warm engine ready" for e in ev),
      "a load longer than the idle limit is waited for, not killed as idle", [e for e in ev if e.get("event") != "progress"][-3:])
check(any(e.get("event") == "progress" and e.get("phase") == "load" for e in ev),
      "the warm engine's load bar reaches the page while it loads")
os.environ["FAKE_LOAD_SECONDS"] = "0"
os.environ["GENESI_IMAGE_WARM_IDLE"] = "600"
mod.WARM_IDLE = 600
rc, ev = run(mod, "server", "stop")
time.sleep(1)
rc, ev = run(mod, "server", "status")
check(ev and not ev[0].get("running"), "server stop gives the GPU back", ev)
del os.environ["GENESI_SD_SERVER"]

# ── import ──────────────────────────────────────────────────────────────────
print("== importing a checkpoint ==")
def fake_safetensors(path, keys):
    hdr = json.dumps({k: {"dtype": "F16", "shape": [1], "data_offsets": [0, 2]} for k in keys}).encode()
    Path(path).write_bytes(struct.pack("<Q", len(hdr)) + hdr + b"\0\0")
xl = tmp / "MyMix XL.safetensors"
fake_safetensors(xl, ["conditioner.embedders.1.model.ln_final.weight", "model.diffusion_model.input_blocks.0.0.weight"])
s15 = tmp / "old15.safetensors"
fake_safetensors(s15, ["cond_stage_model.transformer.text_model.final_layer_norm.weight",
                       "model.diffusion_model.input_blocks.0.0.weight"])
flux_only = tmp / "flux-dit.safetensors"
fake_safetensors(flux_only, ["double_blocks.0.img_attn.qkv.weight"])
mod.COMPONENTS["sdxl-vae"] = C("sdxl_vae.safetensors", "/vae")
check(mod.detect_family(str(xl)) == "sdxl" and mod.detect_family(str(s15)) == "sd15"
      and mod.detect_family(str(flux_only)) == "", "a checkpoint's family is read from its tensor names")
rc, ev = run(mod, "import", str(xl))
check(rc == 0 and ev[-1].get("family") == "sdxl" and Path(mod.component_path("sdxl-vae")).exists(),
      "an SDXL checkpoint imports, and its fp16-safe VAE comes with it", ev[-1:])
rc, ev = run(mod, "import", str(flux_only))
check(rc == 2 and ev[-1].get("code") == "unsupported", "a diffusion-only file is refused, with the reason", ev[-1:])
rc, ev = run(mod, "generate", "--model", "custom-mymix-xl", "--prompt", "mine")
a = last_argv()
check(rc == 0 and a[a.index("-m") + 1] == str(xl), "an imported model generates from the user's own file", a)
rc, ev = run(mod, "remove", "custom-mymix-xl")
check(rc == 0 and xl.exists() and not mod.model_by_id("custom-mymix-xl"),
      "removing an imported model never deletes the user's file")

# ── user LoRAs ──────────────────────────────────────────────────────────────
print("== user LoRAs ==")
def fake_lora(path, keys, pad=0):
    hdr = json.dumps({k: {"dtype": "F16", "shape": [1], "data_offsets": [0, 2]} for k in keys}).encode()
    Path(path).write_bytes(struct.pack("<Q", len(hdr)) + hdr + b"\0\0" + b"\0" * pad)
fams = {
    "sdxl": ["lora_unet_input_blocks_4_1_proj_in.lora_down.weight", "lora_te2_text_model_x.lora_up.weight"],
    "sd15": ["lora_unet_down_blocks_0_attentions_0_transformer_blocks_0_attn1_to_q.lora_down.weight",
             "lora_te_text_model_encoder_layers_0_mlp_fc1.lora_down.weight"],
    "flux": ["lora_unet_double_blocks_0_img_attn_qkv.lora_down.weight"],
    "qwen": ["transformer_blocks.0.img_mod.1.lora_A.weight"],
    "zimage": ["context_refiner.0.attention.to_q.lora_A.weight"],
}
for fam, keys in fams.items():
    f = tmp / ("l-%s.safetensors" % fam)
    fake_lora(f, keys)
    check(mod.detect_lora_family(str(f)) == fam, "a %s LoRA is recognized from its tensor names" % fam,
          mod.detect_lora_family(str(f)))
ckpt = tmp / "old.ckpt"
ckpt.write_bytes(b"\x80\x04pickle")
rc, ev = run(mod, "lora", "import", str(ckpt))
check(rc == 2 and ev[-1].get("code") == "unsafe-format",
      "a .ckpt LoRA is refused -- a pickle can run code when it is loaded", ev[-1:])
rc, ev = run(mod, "lora", "import", str(tmp / "l-flux.safetensors"), "--name", "Film Look",
             "--trigger", "kodak portra")
check(rc == 0 and ev[-1].get("family") == "flux" and (tmp / "models" / "userlora-film-look.safetensors").exists(),
      "a .safetensors LoRA imports into the models dir under a resolvable name", ev[-1:])
rc, ev = run(mod, "lora", "import", str(tmp / "l-sdxl.safetensors"), "--name", "Detail XL")
rc, ev = run(mod, "lora", "list")
ids = {x["id"]: x for x in ev[0]}
check(set(ids) == {"film-look", "detail-xl"} and ids["film-look"]["trigger"] == "kodak portra"
      and ids["detail-xl"]["present"], "lora list shows both, with trigger words", ev[0])

mod.MODELS.append({"id": "fx", "name": "FX", "family": "chroma", "summary": {"en": "", "pt": ""},
                   "license": "MIT", "caps": ["generate", "img2img"], "tags": [],
                   "parts": {"vae": "shared"},
                   "variants": [{"id": "q4", "label": "Q4", "parts": {"diffusion": "b"}}],
                   "defaults": dict(D, steps=10), "turbo": {}, "recommended": False})
run(mod, "pull", "fx")
rc, ev = run(mod, "generate", "--model", "fx", "--prompt", "a portrait", "--lora", "film-look:0.6")
a = last_argv()
pr = a[a.index("-p") + 1]
check(rc == 0 and "<lora:userlora-film-look:0.6>" in pr and "kodak portra" in pr,
      "a LoRA goes into the prompt with its weight, and its trigger words are added", pr)
check(a[a.index("--lora-model-dir") + 1] == mod.models_dir(), "the engine is told where LoRAs live", a)
rc, ev = run(mod, "generate", "--model", "fx", "--prompt", "x", "--lora", "detail-xl")
check(rc == 2 and ev[-1].get("code") == "lora-mismatch", "an SDXL LoRA is refused on a FLUX-family model", ev[-1:])
rc, ev = run(mod, "generate", "--model", "fx", "--mode", "img2img", "--prompt", "x",
             "--ref", str(tmp / "src.png") if (tmp / "src.png").exists() else str(TOOL), "--lora", "film-look")
check(rc == 2 and ev[-1].get("code") in ("lora-generate-only",) , "LoRAs are refused on edits of an existing picture", ev[-1:])
rc, ev = run(mod, "lora", "remove", "film-look")
check(rc == 0 and not (tmp / "models" / "userlora-film-look.safetensors").exists()
      and "film-look" not in {x["id"] for x in mod.load_loras()}, "lora remove deletes our copy and the entry")

# ── masks and kept faces ────────────────────────────────────────────────────
print("== masks and kept faces ==")
try:
    from PySide6.QtGui import QImage, QColor, QPainter
    have_qt = True
except ImportError:
    have_qt = False
    print("  skip masks: no PySide6")
if have_qt:
    # A source picture with a pattern, a mask painting only its right half.
    srcq = QImage(400, 240, QImage.Format_RGB32)
    for y in range(240):
        for x in range(400):
            srcq.setPixel(x, y, QColor((x * 3) % 256, (y * 5) % 256, 90).rgb())
    msrc = tmp / "msrc.png"; srcq.save(str(msrc))
    mq = QImage(400, 240, QImage.Format_Grayscale8); mq.fill(0)
    pp = QPainter(mq); pp.fillRect(260, 0, 140, 240, QColor(255, 255, 255)); pp.end()
    mpng = tmp / "mask.png"; mq.save(str(mpng))
    rc, ev = run(mod, "generate", "--model", "m1", "--mode", "edit", "--prompt", "change the right",
                 "--ref", str(msrc), "--mask", str(mpng))
    done = [e for e in ev if e.get("event") == "done"]
    outp = done[0]["path"] if done else ""
    oq = QImage(outp)
    check(rc == 0 and oq.width() == 400 and oq.height() == 240,
          "a masked edit comes back at the SOURCE's resolution", (oq.width(), oq.height()))
    same_left = all(oq.pixel(x, y) == srcq.pixel(x, y) for x in range(0, 200, 7) for y in range(0, 240, 7))
    changed_right = all(oq.pixel(x, y) != srcq.pixel(x, y) for x in range(330, 400, 7) for y in range(0, 240, 7))
    check(same_left, "every pixel outside the mask is the original's, exactly")
    check(changed_right, "inside the mask the model's picture is used")
    check(not list((tmp / "out").glob("*.raw.png")), "the engine's raw picture is not left in the gallery")
    a = last_argv()
    check("--mask" not in a, "an instruction editor is not handed a mask it does not take (the composite does it)")
    rc, ev = run(mod, "generate", "--model", "m2", "--mode", "img2img", "--prompt", "x",
                 "--ref", str(msrc), "--mask", str(mpng))
    a = last_argv()
    mk = a[a.index("--mask") + 1] if "--mask" in a else ""
    mki = QImage(mk) if mk else QImage()
    check(rc == 0 and mk and mki.width() == int(a[a.index("-W") + 1]),
          "img2img gets sd-cli's own inpainting mask, scaled to the working size", (mk, mki.width()))
    # Kept faces: stand in for OpenCV with a fixed box.
    mod.faces_available = lambda: True
    mod.detect_faces = lambda path: [(40, 60, 80, 80)]
    rc, ev = run(mod, "generate", "--model", "m1", "--mode", "edit", "--prompt", "restyle",
                 "--ref", str(msrc), "--protect-faces")
    done = [e for e in ev if e.get("event") == "done"]
    oq = QImage(done[0]["path"]) if done else QImage()
    face_same = all(oq.pixel(x, y) == srcq.pixel(x, y) for x in range(65, 95, 5) for y in range(85, 115, 5))
    rest_changed = oq.pixel(330, 200) != srcq.pixel(330, 200)
    check(rc == 0 and face_same and rest_changed,
          "with faces protected, the face is the original's and the rest is the edit", ev[-2:])
    check(any(e.get("text") == "protecting 1 face(s)" for e in ev), "the page is told how many faces were kept")
    mod.faces_available = lambda: False
    rc, ev = run(mod, "generate", "--model", "m1", "--mode", "edit", "--prompt", "x",
                 "--ref", str(msrc), "--protect-faces")
    check(rc == 0 and any(e.get("code") == "no-faces" for e in ev),
          "without OpenCV, face protection says what to install and the edit still runs")

    # The page's painted strokes become the mask file in the Monitor backend.
    mon = PKG / "genesi-ai-mode" / "monitor"
    sys.path.insert(0, str(mon))
    try:
        spec = importlib.util.spec_from_file_location("gam_monitor", mon / "genesi_ai_monitor.py")
        gam = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(gam)
    except Exception as e:  # noqa: BLE001 -- report, do not crash the suite
        gam = None
        check(False, "the Monitor backend imports for the mask test", repr(e))
    if gam is not None:
        class _Self:
            n = 0
            def imageMaskPath(self):
                _Self.n += 1
                return str(tmp / ("paint-%d.png" % _Self.n))
        stroke = [{"erase": False, "size": 0.1, "pts": [[0.6, 0.5], [0.9, 0.5]]},
                  {"erase": True, "size": 0.1, "pts": [[0.75, 0.5]]}]
        mp = gam.Backend.writeImageMask(_Self(), json.dumps(stroke), str(msrc), False)
        mi = QImage(mp)
        g = lambda x, y: QColor(mi.pixel(x, y)).red()
        check(mi.width() == 400 and mi.height() == 240,
              "the mask is drawn at the source picture's own size", (mi.width(), mi.height()))
        check(g(260, 120) == 255 and g(345, 120) == 255 and g(20, 20) == 0,
              "painted = white (change), unpainted = black (keep)", (g(260, 120), g(20, 20)))
        check(g(300, 120) == 0, "an eraser dab cuts the painted area back to keep", g(300, 120))
        mp = gam.Backend.writeImageMask(_Self(), json.dumps(stroke), str(msrc), True)
        mi = QImage(mp)
        check(g(260, 120) == 0 and g(20, 20) == 255, "inverted: everything BUT the painted area changes")
        check(gam.Backend.writeImageMask(_Self(), "[]", str(msrc), False) == "",
              "no strokes, no mask file")

# ── pure helpers ─────────────────────────────────────────────────────────────
print("== helpers ==")
check(mod.image_size(str(src)) == (1600, 900), "PNG size from the header")
jpg = tmp / "x.jpg"
jpg.write_bytes(b"\xff\xd8" + b"\xff\xe0" + struct.pack(">H", 16) + b"JFIF\0" + b"\0" * 9
                + b"\xff\xc0" + struct.pack(">HBHHB", 11, 8, 480, 640, 3) + b"\0" * 9 + b"\xff\xd9")
check(mod.image_size(str(jpg)) == (640, 480), "JPEG size from the SOF segment")
for (iw, ih) in ((1024, 1024), (6000, 4000), (300, 2000)):
    fw, fh = mod.fit_size(iw, ih)
    check(fw % 16 == 0 and fh % 16 == 0 and max(fw, fh) <= mod.MAX_SIDE, "fit_size(%d, %d) stays in bounds" % (iw, ih))

p = mod.ProgressParser()
evs = []
for chunk in ("\r|###| 298/298 - 2.10GB/s\n", "[INFO ] get_learned_condition completed, taking 900 ms\n",
              "\r|###| 149/149 - 1.80GB/s\n", "\r|=>  | 1/4 - 84.37s/it\r|====| 4/4 - 0.50it/s\n",
              "[INFO ] sampling completed, taking 337s\n", "\r|###| 140/140 - 0.90GB/s\n"):
    evs += p.feed(chunk)
phases = [e.get("phase") for e in evs]
check("load" not in phases[phases.index("sample"):], "a weight load after the steps is part of finishing", phases)
samp = [e for e in evs if e.get("phase") == "sample"]
check(samp and abs(samp[-1]["sec_per_step"] - 2.0) < 1e-6, "it/s is turned into seconds per step", samp)
p2 = mod.ProgressParser()
p2.feed("[ERROR] ggml_vulkan: Device memory allocation of size 1 failed.\n[ERROR] main.cpp:928 - generate failed\n")
check(p2.oom and "generate failed" not in p2.last_error() and "allocation" in p2.last_error(),
      "the reason is the error BEFORE sd-cli's generic closing line", p2.last_error())

# ── against upstream ─────────────────────────────────────────────────────────
print("== against upstream (network) ==")
mod.COMPONENTS, mod.MODELS = real_components, real_models
pkgbuild = (PKG / "genesi-sd-cpp" / "PKGBUILD").read_text(encoding="utf-8")
commit = re.search(r"^_commit=([0-9a-f]{40})", pkgbuild, re.M).group(1)
cuda = (PKG / "genesi-sd-cpp-cuda" / "PKGBUILD").read_text(encoding="utf-8")
check(re.search(r"^_commit=([0-9a-f]{40})", cuda, re.M).group(1) == commit,
      "the CUDA and Vulkan engines are pinned to the same commit")


def fetch(url, timeout=30):
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "genesi-ci"}),
                                timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")


raw = "https://raw.githubusercontent.com/leejet/stable-diffusion.cpp/%s/" % commit
try:
    upstream = fetch(raw + "examples/common/common.cpp") + fetch(raw + "examples/cli/main.cpp") \
        + fetch(raw + "examples/server/main.cpp") + fetch(raw + "examples/server/runtime.cpp")
except urllib.error.HTTPError as e:
    check(False, "the pinned commit's sources are reachable", "HTTP %s" % e.code)
    upstream = None
except (urllib.error.URLError, OSError) as e:
    print("  skip upstream flags: %s" % e)
    upstream = None

if upstream:
    flags = set()
    for m in real_models:
        for v in m["variants"]:
            for backend in ("cuda", "vulkan", "cpu"):
                for safe in (False, True):
                    if "upscale" in m["caps"]:
                        argv = mod.build_upscale_argv("sd-cli", m, v, "i.png", "o.png")
                    else:
                        s = mod.gen_settings(m, "generate", True)
                        s.update({"lora": "x.safetensors" if (m.get("turbo") or {}).get("lora") else None,
                                  "negative": "n", "cache": (m.get("turbo") or {}).get("cache")})
                        mode = "edit" if "edit" in m["caps"] else "img2img"
                        argv = mod.build_cli_argv("sd-cli", m, v, s, "p", "o.png", 512, 512, 1,
                                                  mode, "r.png", backend, True, safe, 8192)
                    flags.update(a for a in argv if a.startswith("-") and not re.match(r"^-\d", a))
    flags.update(["--listen-ip", "--listen-port"])
    for f in sorted(flags):
        check('"%s"' % f in upstream, "sd-cli at %s accepts %s" % (commit[:8], f))
    try:
        sdsrc = fetch(raw + "src/stable-diffusion.cpp")
        for m in real_models:
            d = m.get("defaults", {})
            for key in ("sampler", "scheduler"):
                if d.get(key):
                    check('"%s"' % d[key] in sdsrc, "%s's %s %s exists upstream" % (m["id"], key, d[key]))
            for c in (m.get("turbo") or {}).get("cache"), :
                if c:
                    check(c in upstream or c in sdsrc, "%s's cache mode %s exists upstream" % (m["id"], c))
    except (urllib.error.URLError, OSError) as e:
        print("  skip sampler names: %s" % e)

# Sizes by HEAD, hashes from the Hub's own API.
hf_sha = {}
for cid, c in real_components.items():
    url = c["url"]
    try:
        req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "genesi-ci"})
        with urllib.request.urlopen(req, timeout=30) as r:
            size = int(r.headers.get("Content-Length") or -1)
        check(size == c["size"], "%s is downloadable at the catalog's size" % cid,
              "server says %s, catalog says %s" % (size, c["size"]))
    except urllib.error.HTTPError as e:
        check(False, "%s is downloadable without a login" % cid, "HTTP %s" % e.code)
        continue
    except (urllib.error.URLError, OSError) as e:
        print("  skip %s: %s" % (cid, e))
        continue
    m = re.match(r"https://huggingface\.co/([^/]+/[^/]+)/resolve/main/(.+)$", url)
    if not m:
        continue
    repo, path = m.groups()
    try:
        if repo not in hf_sha:
            hf_sha[repo] = {s["rfilename"]: (s.get("lfs") or {}).get("sha256", "")
                            for s in json.loads(fetch("https://huggingface.co/api/models/%s?blobs=true" % repo))["siblings"]}
        check(hf_sha[repo].get(path) == c["sha256"], "%s's sha256 is the one the Hub reports" % cid,
              "hub %s, catalog %s" % (hf_sha[repo].get(path), c["sha256"]))
    except (urllib.error.URLError, OSError, ValueError, KeyError) as e:
        print("  skip sha of %s: %s" % (cid, e))

srv.shutdown()
print()
if failures:
    print("%d check(s) failed" % len(failures))
    sys.exit(1)
print("all checks passed")
