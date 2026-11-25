#!/usr/bin/env python3
"""genesi-ai-video, driven the way the Monitor's Video page drives it.

What is checked, and why each one:

  * The catalog is coherent: every file has a size, an https URL and a real
    SHA-256; no two files share a name on disk -- not even with the IMAGE
    catalog, since both live in one models folder; the two-expert models
    (Wan2.2 A14B) name their high-noise half in every variant and carry BOTH
    Lightning LoRAs; there is a model that keeps a face from a first frame
    and one that keeps a person from a reference, rated best (3).
  * genesi-ai-image on its own never sees a video model: the video catalog
    is handed to it only inside genesi-ai-video's process.
  * Frames are N*step+1 (Wan packs 4 frames per latent, LTX 8) and never past
    a model's longest clip; sizes are multiples of the model's alignment and
    follow the picture being animated.
  * Downloads go through genesi-ai-image's verified path, both Lightning
    LoRAs of a two-expert model land and leave with it, and removing a
    model keeps the text encoder another downloaded model uses.
  * A whole run against a stand-in sd-cli that writes a real MJPG .avi: the
    argv of every mode (t2v, i2v, flf2v, r2v, v2v, extend), the two-expert
    flags, Turbo's LoRAs (the |high_noise| one included), user LoRAs on
    both experts, low memory, the light decoder, the out-of-memory retry,
    and the Image page's warm engine being stopped before a clip.
  * The output: a poster taken from the .avi with no ffmpeg at all, an .mp4
    when ffmpeg is there (the .avi when it is not), the sidecar, the gallery.
  * A Wan LoRA's size (1.3B / 5B / 14B) is read from its tensor widths, and a
    LoRA for another size is refused.
  * The Monitor backend turns the page's options into the CLI's flags.
  * The page itself loads offscreen, in English and Portuguese, and still
    loads when the player (QtMultimedia) cannot.
  * Against upstream (network; skipped, not failed, without one): every flag
    exists at genesi-sd-cpp's pinned commit, every catalog URL answers with
    the catalog's size, and every hash is the one the Hub reports.

No GPU, no engine and no multi-GB download needed.
"""
import atexit
import contextlib
import hashlib
import http.server
import importlib.machinery
import importlib.util
import io
import json
import os
import re
import shutil
import struct
import subprocess
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
AIM = PKG / "genesi-ai-mode"
TOOL = AIM / "genesi-ai-video"
IMAGE_TOOL = AIM / "genesi-ai-image"

failures = []
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass


def ok(what):
    print("  ok   " + what)


def check(cond, what, why=""):
    if cond:
        ok(what)
    else:
        print("  FAIL " + what)
        if why:
            print("         " + str(why)[:700])
        failures.append(what)


def load(path, name):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def run(mod, *argv):
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


# A real 16x16 JPEG: the stand-in engine's frames, and what the poster must be.
JPEG = bytes.fromhex(
    "ffd8ffe000104a46494600010101006400640000ffdb004300100b0c0e0c0a100e0d0e1211101318281a1816"
    "16183123251d283a333d3c3933383740485c4e404457453738506d51575f626768673e4d71797064785c6567"
    "63ffdb0043011112121815182f1a1a2f63423842636363636363636363636363636363636363636363636363"
    "6363636363636363636363636363636363636363636363636363ffc000110800100010030122000211010311"
    "01ffc4001f0000010501010101010100000000000000000102030405060708090a0bffc400b5100002010303"
    "020403050504040000017d01020300041105122131410613516107227114328191a1082342b1c11552d1f024"
    "33627282090a161718191a25262728292a3435363738393a434445464748494a535455565758595a63646566"
    "6768696a737475767778797a838485868788898a92939495969798999aa2a3a4a5a6a7a8a9aab2b3b4b5b6b7"
    "b8b9bac2c3c4c5c6c7c8c9cad2d3d4d5d6d7d8d9dae1e2e3e4e5e6e7e8e9eaf1f2f3f4f5f6f7f8f9faffc400"
    "1f0100030101010101010101010000000000000102030405060708090a0bffc400b511000201020404030407"
    "05040400010277000102031104052131061241510761711322328108144291a1b1c109233352f0156272d10a"
    "162434e125f11718191a262728292a35363738393a434445464748494a535455565758595a63646566676869"
    "6a737475767778797a82838485868788898a92939495969798999aa2a3a4a5a6a7a8a9aab2b3b4b5b6b7b8b9"
    "bac2c3c4c5c6c7c8c9cad2d3d4d5d6d7d8d9dae2e3e4e5e6e7e8e9eaf2f3f4f5f6f7f8f9faffda000c030100"
    "02110311003f00a34514579e7d11ffd9")


tmp = Path(tempfile.mkdtemp(prefix="genesi-video-test-"))
# Gone when the suite ends, whatever happens: nothing here is worth keeping,
# and a run that goes wrong must not leave its files on the runner's disk.
atexit.register(shutil.rmtree, str(tmp), True)
for k, sub in (("GENESI_IMAGE_MODELS_DIR", "models"), ("GENESI_IMAGE_OUTPUT_DIR", "pictures"),
               ("GENESI_IMAGE_CACHE_DIR", "icache"), ("GENESI_IMAGE_RUNTIME_DIR", "run"),
               ("GENESI_VIDEO_OUTPUT_DIR", "out"), ("GENESI_VIDEO_CACHE_DIR", "vcache")):
    os.environ[k] = str(tmp / sub)
os.environ["GENESI_IMAGE_VRAM_MB"] = "8192"
os.environ["GENESI_AI_IMAGE_TOOL"] = str(IMAGE_TOOL)
os.environ["GENESI_FFMPEG"] = str(tmp / "no-ffmpeg")
os.environ["GENESI_FFPROBE"] = str(tmp / "no-ffprobe")

# ── the image tool alone ────────────────────────────────────────────────────
print("== the Image page's tool is untouched ==")
img_alone = load(IMAGE_TOOL, "genesi_ai_image_alone")
check(not any(m["id"].startswith(("wan", "ltx")) for m in img_alone.MODELS),
      "genesi-ai-image on its own lists no video model")
mod = load(TOOL, "genesi_ai_video")
mod._install_catalog()
img = mod.img
real_components = dict(img.COMPONENTS)
check(img.model_by_id("wan22-ti2v-5b") is not None and img.model_by_id("flux2-klein") is not None,
      "inside genesi-ai-video both catalogs resolve (downloads, removal and LoRAs reuse the image code)")
check(img.log_path() == mod.log_path(), "a clip's engine output goes to the Video page's own log")

# ── the catalog ──────────────────────────────────────────────────────────────
print("== the catalog ==")
for m in mod.VIDEO_MODELS:
    check(m["caps"] and set(m["caps"]) <= set(mod.MODES) - {"extend"},
          "%s declares what it can do" % m["id"], m["caps"])
    check(m["summary"].get("en") and m["summary"].get("pt") and m["summary"]["en"] != m["summary"]["pt"],
          "%s is described in both languages" % m["id"])
    check(m["family"] in mod.VIDEO_LORA_FAMILIES, "%s's family has a LoRA rule" % m["id"])
    vid = m["video"]
    check(vid["fps"] in (16, 24) and vid["frame_step"] in (4, 8) and vid["align"] in (16, 32)
          and set(vid["sizes"]) <= set(mod.SIZES),
          "%s has sane frame/size rules" % m["id"], vid)
    check(m.get("face", "") in ("", "start", "subject") and (not m.get("face") or m.get("identity", 0) >= 1),
          "%s says whether and how it keeps a face" % m["id"])
    for v in m["variants"]:
        for role, ref in img.variant_parts(m, v).items():
            check(role in img.PART_FLAGS, "%s/%s: role %s maps to a flag" % (m["id"], v["id"], role))
            check(ref in img.COMPONENTS, "%s/%s: %s names a known file" % (m["id"], v["id"], role), ref)
        if vid.get("moe"):
            check("high_noise" in v["parts"], "%s/%s names its high-noise expert" % (m["id"], v["id"]))
    for lora in img.turbo_loras(m):
        check(lora in img.COMPONENTS, "%s's Turbo LoRA %s is a known file" % (m["id"], lora))
    if vid.get("moe"):
        check(m["turbo"].get("lora") and m["turbo"].get("lora_high"),
              "%s carries Lightning LoRAs for BOTH experts" % m["id"])
    check(img.recommended_variant(m, 8192) in m["variants"], "%s recommends a variant on 8 GB" % m["id"])
for cid, c in mod.VIDEO_COMPONENTS.items():
    check(c["url"].startswith("https://") and c["size"] > 0, "%s has an https URL and a size" % cid)
    check(re.fullmatch(r"[0-9a-f]{64}", c["sha256"] or ""), "%s carries a full sha256" % cid, c["sha256"])
vfiles = [c["file"] for c in mod.VIDEO_COMPONENTS.values()]
ifiles = {c["file"] for c in img_alone.COMPONENTS.values()}
check(len(vfiles) == len(set(vfiles)), "no two video files share a name")
check(not (set(vfiles) & ifiles), "no video file shares a name with an image file (one models folder)",
      set(vfiles) & ifiles)
check(not (set(mod.VIDEO_COMPONENTS) & set(img_alone.COMPONENTS)), "no component id is shared with the image catalog")
check(sum(1 for m in mod.VIDEO_MODELS if m.get("recommended")) == 1, "exactly one model is the recommended start")
start = [m for m in mod.VIDEO_MODELS if m.get("recommended")][0]
check(img.recommended_variant(start, 8192)["id"] in ("q4", "q6", "q8") and "i2v" in start["caps"]
      and not start.get("min_ram_gb"), "the start model animates pictures and needs no 32 GB of RAM", start["id"])
check(any(m.get("face") == "start" and m["identity"] == 3 for m in mod.VIDEO_MODELS)
      and any(m.get("face") == "subject" and m["identity"] == 3 for m in mod.VIDEO_MODELS),
      "the catalog marks the best face-keeping models: from a first frame and from a reference")
check(any(m["video"].get("audio") for m in mod.VIDEO_MODELS), "there is a model that makes sound")
for mode in ("t2v", "i2v", "flf2v", "r2v", "v2v"):
    check(any(mode in m["caps"] for m in mod.VIDEO_MODELS), "some model does %s" % mode)

rc, ev = run(mod, "catalog")
cat = ev[0] if ev else []
check(rc == 0 and len(cat) == len(mod.VIDEO_MODELS) and all(m["kind"] == "video" for m in cat),
      "catalog --json is one array of the video models only", [m.get("id") for m in cat])
c5 = [m for m in cat if m["id"] == "wan22-ti2v-5b"][0]
check(c5["modes"] == ["t2v", "i2v", "extend"] and c5["fps"] == 24 and c5["lora_families"] == ["wan-5b"]
      and c5["turbo"]["kind"] == "lora" and c5["light_vae"],
      "the page is told modes (extend included), fps, LoRA base, Turbo and the light decoder", c5)

# ── frames and sizes ─────────────────────────────────────────────────────────
print("== frames and sizes ==")
for m in mod.VIDEO_MODELS:
    vid = m["video"]
    longest = (int(vid["max_seconds"] * vid["fps"]) // vid["frame_step"]) * vid["frame_step"] + 1
    counts = [mod.frame_count(m, seconds=s / 2.0) for s in range(1, 30)]
    check(all((n - 1) % vid["frame_step"] == 0 and vid["frame_step"] < n <= longest for n in counts),
          "%s: every length is N*%d+1 frames, at most %d" % (m["id"], vid["frame_step"], longest), counts)
    for size in vid["sizes"]:
        for aspect in ("16:9", "9:16", "1:1"):
            w, h = mod.video_size(m, size, aspect)
            check(w % vid["align"] == 0 and h % vid["align"] == 0,
                  "%s %s %s is a multiple of %d" % (m["id"], size, aspect, vid["align"]), (w, h))
w5 = mod.video_size(mod.video_model("wan22-ti2v-5b"), "720p", "16:9")
check(w5 == (1280, 704), "Wan2.2 5B's 720p is its native 1280x704", w5)
w13 = mod.video_size(mod.video_model("wan21-t2v-1.3b"), "720p", "16:9")
check(w13 == (832, 480), "a 480p-only model asked for 720p stays at 480p", w13)
wp = mod.video_size(mod.video_model("wan22-i2v-a14b"), "480p", None, (1080, 1920))
check(wp[0] < wp[1] and abs(wp[0] / wp[1] - 1080 / 1920) < 0.05, "image to video keeps the picture's shape", wp)

# ── downloads ────────────────────────────────────────────────────────────────
print("== downloads ==")
payload = os.urandom(200_000)
digest = hashlib.sha256(payload).hexdigest()


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=srv.serve_forever, daemon=True).start()
base = "http://127.0.0.1:%d" % srv.server_address[1]
for cid in list(mod.VIDEO_COMPONENTS):
    c = img.COMPONENTS[cid]
    img.COMPONENTS[cid] = dict(c, url=base + "/" + cid, size=len(payload), sha256=digest)
run(mod, "catalog")
check(all(img.COMPONENTS[cid]["url"].startswith(base) for cid in mod.VIDEO_COMPONENTS),
      "the stand-in URLs survive the tool's own setup (a second pass once put the real ones "
      "back and the suite downloaded 12 GB from the Hub)")
if failures:
    print("refusing to go on: the next steps would download real models")
    sys.exit(1)

rc, ev = run(mod, "pull", "wan22-i2v-a14b", "--variant", "q3")
m14 = mod.video_model("wan22-i2v-a14b")
need = ["wan22-i2v-lo-q3km", "wan22-i2v-hi-q3km", "wan21-vae", "umt5-q4km", "taew21",
        "wan22-i2v-lightning-lo", "wan22-i2v-lightning-hi"]
check(rc == 0 and all(Path(img.component_path(c)).is_file() and Path(img.component_path(c)).read_bytes() == payload for c in need),
      "a two-expert model downloads both experts, its VAE, encoder, light decoder and BOTH Lightning LoRAs",
      [c for c in need if not Path(img.component_path(c)).exists()])
check(not Path(img.component_path("wan22-i2v-lo-q4km")).exists(), "the other variant is not downloaded")
for mid in ("wan22-ti2v-5b", "wan21-vace-1.3b", "wan21-t2v-1.3b"):
    rc, ev = run(mod, "pull", mid)
    check(rc == 0, "%s downloads" % mid, ev[-1:])
rc, ev = run(mod, "pull", "flux2-klein")
check(rc == 2, "the video tool refuses to pull an image model by mistake", ev[-1:])

# ── the stand-ins: sd-cli, ffmpeg, ffprobe ─────────────────────────────────
fake = tmp / "fake_sd_cli.py"
argv_log = tmp / "argv.jsonl"
fake.write_text(r'''
import json, os, struct, sys
argv = sys.argv[1:]
open(%r, "a").write(json.dumps(argv) + "\n")
if "--list-devices" in argv:
    print("Vulkan0\tFake GPU\nCPU\tFake CPU"); sys.exit(0)
out = argv[argv.index("-o") + 1]
text = " ".join(argv)
if "FAILME" in text or ("OOMME" in text and "--offload-to-cpu" not in text):
    print("[ERROR] ggml_vulkan: Device memory allocation of size 4610612736 failed.")
    print("[ERROR] main.cpp:922 - generate failed")
    sys.exit(1)
jpeg = bytes.fromhex(%r)
n = int(argv[argv.index("--video-frames") + 1])
w, h = int(argv[argv.index("-W") + 1]), int(argv[argv.index("-H") + 1])
fps = int(argv[argv.index("--fps") + 1])
sys.stdout.write("[INFO ] loading model\n")
for i in range(1, 4):
    sys.stdout.write("\r|##########  | %%d/3 - 512.00MB/s\033[K" %% i); sys.stdout.flush()
sys.stdout.write("\n[INFO ] get_learned_condition completed, taking 120 ms\n")
for i in range(1, 5):
    sys.stdout.write("\r|=====>   | %%d/4 - 9.50s/it\033[K" %% i); sys.stdout.flush()
sys.stdout.write("\n[INFO ] sampling completed, taking 38.02s\n")
sys.stdout.write("\r|##| 2/2 - 300.00MB/s\n[INFO ] decode_first_stage completed\n")
def le(*v): return struct.pack("<" + "I" * len(v), *v)
chunk = b"00dc" + le(len(jpeg)) + jpeg + (b"\0" if len(jpeg) %% 2 else b"")
movi = b"LIST" + le(4 + len(chunk) * n) + b"movi" + chunk * n
avih = b"avih" + le(56) + le(1000000 // fps, 0, 0, 0x110, n, 0, 1, w * h * 3, w, h, 0, 0, 0, 0)
hdrl = b"LIST" + le(4 + len(avih)) + b"hdrl" + avih
body = b"AVI " + hdrl + movi
open(out, "wb").write(b"RIFF" + le(len(body)) + body)
print("[INFO ] save result video to '%%s'" %% out)
''' % (str(argv_log), JPEG.hex()))
ff_log = tmp / "ffmpeg.jsonl"
fake_ff = tmp / "fake_ffmpeg.py"
fake_ff.write_text(r'''
import json, os, struct, sys, zlib
a = sys.argv[1:]
open(%r, "a").write(json.dumps(a) + "\n")
def png(w, h):
    raw = b"".join(b"\x00" + b"\x40\x40\x40" * w for _ in range(h))
    c = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    return b"\x89PNG\r\n\x1a\n" + c(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + c(b"IDAT", zlib.compress(raw)) + c(b"IEND", b"")
if os.environ.get("FAKE_FFMPEG_FAIL"):
    sys.stderr.write("fake failure\n"); sys.exit(1)
out = a[-1]
if out.endswith("%%05d.png"):
    n = min(int(a[a.index("-frames:v") + 1]), int(os.environ.get("FAKE_SRC_FRAMES", "500")))
    for i in range(1, n + 1):
        open(out.replace("%%05d", "%%05d" %% i), "wb").write(png(8, 8))
elif out.endswith(".png"):
    open(out, "wb").write(png(1280, 720))
elif out.endswith(".jpg"):
    open(out, "wb").write(bytes.fromhex(%r))
else:
    open(out, "wb").write(b"\0\0\0\x18ftypmp42" + b"x" * 64)
''' % (str(ff_log), JPEG.hex()))
fake_probe = tmp / "fake_ffprobe.py"
fake_probe.write_text('import json\nprint(json.dumps({"streams": [{"width": 1280, "height": 720, '
                      '"r_frame_rate": "24/1"}], "format": {"duration": "2.0"}}))\n')
os.environ["GENESI_SD_CLI"] = str(fake)
img.ollama_unload_all = lambda: 0


def last_argv():
    return json.loads(argv_log.read_text().strip().splitlines()[-1])


def opt(a, flag):
    return a[a.index(flag) + 1] if flag in a else None


def with_ffmpeg(on):
    os.environ["GENESI_FFMPEG"] = str(fake_ff if on else tmp / "no-ffmpeg")
    os.environ["GENESI_FFPROBE"] = str(fake_probe if on else tmp / "no-ffprobe")


src = tmp / "portrait.png"
src.write_bytes(png_bytes(720, 1280))
end = tmp / "end.png"
end.write_bytes(png_bytes(720, 1280))

# ── text to video, no ffmpeg ────────────────────────────────────────────────
print("== text to video ==")
with_ffmpeg(False)
rc, ev = run(mod, "generate", "--model", "wan22-ti2v-5b", "--prompt", "uma raposa correndo na neve",
             "--seconds", "2", "--seed", "7")
a = last_argv()
done = [e for e in ev if e.get("event") == "done"]
check(rc == 0 and done, "a text-to-video run finishes", ev[-2:])
check(a[a.index("-M") + 1] == "vid_gen", "the engine is asked for video mode (-M vid_gen)", a)
check(opt(a, "--diffusion-model") == img.component_path("wan22-5b-q8"),
      "the variant recommended for 8 GB (and downloaded) is the diffusion model", a)
check(opt(a, "--vae") == img.component_path("wan22-vae") and opt(a, "--t5xxl") == img.component_path("umt5-q4km"),
      "the 5B gets ITS VAE (Wan2.2) and the UMT5 encoder", a)
check("--tae" not in a, "the light decoder is not used unless asked", a)
check(opt(a, "--video-frames") == "49" and opt(a, "--fps") == "24" and opt(a, "-W") == "832" and opt(a, "-H") == "480",
      "2 s at 24 fps is 49 frames, at 832x480", a)
check(opt(a, "--flow-shift") == "5.0" and opt(a, "--steps") == "30" and opt(a, "-n"),
      "the model's own shift, steps and negative prompt are used", a)
check("-i" not in a and "--vae-tiling" not in a, "text to video takes no picture and is not tiled", a)
phases = [e.get("phase") for e in ev if e.get("event") in ("progress", "phase")]
check("load" in phases and "sample" in phases and "decode" in phases, "load, steps and decode reach the page", phases)
clip = Path(done[0]["path"]) if done else Path("x")
check(clip.suffix == ".avi" and clip.is_file(), "without ffmpeg the clip is the engine's .avi", clip)
poster = Path(done[0].get("poster", "")) if done else Path("x")
check(poster.is_file() and poster.read_bytes() == JPEG, "the poster is the clip's first frame, read with no ffmpeg")
try:
    from PySide6.QtGui import QImage as _QImage
    check(_QImage(str(poster)).width() == 16, "the poster is a picture Qt can show", str(poster))
except ImportError:
    pass
side = json.loads(clip.with_suffix(".json").read_text(encoding="utf-8")) if clip.is_file() else {}
check(side.get("prompt") == "uma raposa correndo na neve" and side.get("frames") == 49 and side.get("fps") == 24
      and side.get("seed") == 7, "the sidecar records prompt, frames, fps and seed", side)
check(mod.probe(str(clip)) and mod.probe(str(clip))[:2] == (832, 480),
      "an .avi's size is read from its header when there is no ffprobe", mod.probe(str(clip)))

with_ffmpeg(True)
rc, ev = run(mod, "generate", "--model", "wan22-ti2v-5b", "--prompt", "a fox", "--turbo", "--aspect", "9:16")
a = last_argv()
done = [e for e in ev if e.get("event") == "done"]
mp4 = Path(done[0]["path"]) if done else Path("x")
check(rc == 0 and mp4.suffix == ".mp4" and mp4.is_file() and not mp4.with_suffix(".avi").exists(),
      "with ffmpeg the clip becomes an .mp4 and the .avi goes", done)
ffa = json.loads(ff_log.read_text().strip().splitlines()[-1])
check("libx264" in ffa and "yuv420p" in ffa, "the .mp4 is H.264 yuv420p (plays anywhere)", ffa)
pr = opt(a, "-p") or ""
check("<lora:Wan22_TI2V_5B_Turbo_lora_rank_64_fp16:1>" in pr and opt(a, "--steps") == "4"
      and opt(a, "--cfg-scale") == "1.0" and "-n" not in a,
      "Turbo is the 5B's distillation LoRA: 4 steps, cfg 1, no negative", a)
check(opt(a, "-W") == "480" and opt(a, "-H") == "832", "9:16 is portrait", a)
os.environ["FAKE_FFMPEG_FAIL"] = "1"
rc, ev = run(mod, "generate", "--model", "wan21-t2v-1.3b", "--prompt", "rain")
del os.environ["FAKE_FFMPEG_FAIL"]
done = [e for e in ev if e.get("event") == "done"]
check(rc == 0 and done and done[0]["path"].endswith(".avi") and Path(done[0]["path"]).is_file(),
      "a failed .mp4 conversion keeps the .avi -- the clip is not lost", ev[-2:])

# ── modes that take a picture ──────────────────────────────────────────────
print("== image to video, first+last frame, reference ==")
rc, ev = run(mod, "generate", "--model", "wan22-i2v-a14b", "--mode", "i2v", "--prompt", "she smiles",
             "--image", str(src), "--turbo")
a = last_argv()
check(rc == 0 and opt(a, "-i") == str(src) and "--vae-tiling" in a,
      "image to video hands the picture over as the first frame, tiled (encoding has no OOM retry)", a)
w, h = int(opt(a, "-W")), int(opt(a, "-H"))
check(w < h and w % 16 == 0, "a portrait picture makes a portrait clip", (w, h))
check(opt(a, "--high-noise-diffusion-model") == img.component_path("wan22-i2v-hi-q3km")
      and opt(a, "--diffusion-model") == img.component_path("wan22-i2v-lo-q3km"),
      "Wan2.2 A14B gets its high-noise and low-noise experts", a)
check(opt(a, "--high-noise-cfg-scale") == "1.0" and opt(a, "--high-noise-sampling-method") == "euler",
      "the high-noise expert runs at the same cfg and sampler (not upstream's defaults)", a)
pr = opt(a, "-p")
check("<lora:wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise:1>" in pr
      and "<lora:|high_noise|wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise:1>" in pr
      and opt(a, "--steps") == "4", "Turbo puts each Lightning LoRA on its own expert", pr)
check("--high-noise-steps" not in a, "--steps is the total; upstream splits it at the expert boundary", a)
# The stand-in files are 200 KB; with the catalog's REAL sizes, two 14B
# experts cannot sit on an 8 GB card next to their activations.
_fake = dict(img.COMPONENTS)
img.COMPONENTS.update(real_components)
_a = mod.build_video_argv("sd-cli", m14, m14["variants"][0], mod.video_settings(m14, False), "p", "o.avi",
                         832, 480, 49, 1, "i2v", "i.png", None, None, "vulkan", False, 8192)
img.COMPONENTS.update(_fake)
check("--offload-to-cpu" in _a, "two 14B experts on an 8 GB card run with weights in RAM", _a)

rc, ev = run(mod, "generate", "--model", "wan22-i2v-a14b", "--mode", "flf2v", "--prompt", "turns around",
             "--image", str(src), "--end-image", str(end))
a = last_argv()
check(rc == 0 and opt(a, "-i") == str(src) and opt(a, "--end-img") == str(end),
      "first + last frame hands both pictures over", a)
rc, ev = run(mod, "generate", "--model", "wan22-i2v-a14b", "--mode", "flf2v", "--prompt", "x", "--image", str(src))
check(rc == 2 and ev[-1].get("code") == "no-input", "first + last frame without the last frame says so", ev[-1:])
rc, ev = run(mod, "generate", "--model", "wan21-t2v-1.3b", "--mode", "i2v", "--prompt", "x", "--image", str(src))
check(rc == 2 and ev[-1].get("code") == "mode-unsupported", "a text-only model refuses to animate a picture", ev[-1:])
rc, ev = run(mod, "generate", "--model", "wan22-i2v-a14b", "--mode", "i2v", "--prompt", "x",
             "--image", str(tmp / "nope.png"))
check(rc == 2 and ev[-1].get("code") == "no-input", "a missing picture is one clear error", ev[-1:])

rc, ev = run(mod, "generate", "--model", "wan21-vace-1.3b", "--mode", "r2v", "--prompt", "the man on a beach",
             "--image", str(src), "--aspect", "16:9")
a = last_argv()
check(rc == 0 and opt(a, "-i") == str(src) and opt(a, "--vace-strength") == "1.0",
      "a reference (VACE) goes in as -i with its strength", a)
check(int(opt(a, "-W")) > int(opt(a, "-H")), "a reference is placed in a NEW scene: the shape follows the aspect, not the photo", a)

# ── edit a video ───────────────────────────────────────────────────────────
print("== restyle and continue a video ==")
source = tmp / "source.mp4"
source.write_bytes(b"\0\0\0\x18ftypmp42" + b"y" * 64)
with_ffmpeg(False)
rc, ev = run(mod, "generate", "--model", "wan21-vace-1.3b", "--mode", "v2v", "--prompt", "anime style",
             "--video", str(source))
check(rc == 3 and ev[-1].get("code") == "no-ffmpeg", "reading a video without ffmpeg says what to install", ev[-1:])
with_ffmpeg(True)
os.environ["FAKE_SRC_FRAMES"] = "30"
rc, ev = run(mod, "generate", "--model", "wan21-vace-1.3b", "--mode", "v2v", "--prompt", "anime style",
             "--video", str(source), "--seconds", "4")
del os.environ["FAKE_SRC_FRAMES"]
a = last_argv()
cdir = opt(a, "--control-video")
check(rc == 0 and cdir and len([n for n in os.listdir(cdir) if n.endswith(".png")]) == 30,
      "restyling hands the source's frames to VACE as a directory", (rc, cdir, ev[-1:]))
check(opt(a, "--video-frames") == "29", "a source shorter than the clip caps it (30 frames -> 29 = 7*4+1)", opt(a, "--video-frames"))
check(int(opt(a, "-W")) > int(opt(a, "-H")), "the restyled clip keeps the source's 16:9 shape", a)

rc, ev = run(mod, "generate", "--model", "wan22-ti2v-5b", "--mode", "extend", "--prompt", "keeps running",
             "--video", str(source))
a = last_argv()
done = [e for e in ev if e.get("event") == "done"]
calls = [json.loads(l) for l in ff_log.read_text().splitlines()]
lastf = [c for c in calls if "-sseof" in c]
join = [c for c in calls if any("concat=n=2" in x for x in c)]
check(rc == 0 and lastf and opt(a, "-i") == lastf[-1][-1], "continuing starts from the source's last frame", (a, lastf[-1:]))
check(join and join[-1][join[-1].index("-i") + 1] == str(source) and "trim=start_frame=1" in " ".join(join[-1]),
      "the new part is joined after the source, without repeating the shared frame", join[-1:])
check(done and done[0]["path"].endswith(".mp4") and not list((tmp / "out").glob("*.part.avi")),
      "the result is one .mp4, no half-file left", done)

# ── low memory, light decoder, out of memory ──────────────────────────────
print("== low memory ==")
rc, ev = run(mod, "generate", "--model", "wan21-t2v-1.3b", "--prompt", "a boat", "--low-memory", "--light-vae")
a = last_argv()
check(rc == 0 and "--offload-to-cpu" in a and "--vae-tiling" in a, "low-memory mode: weights in RAM, tiled VAE", a)
check(opt(a, "--tae") == img.component_path("taew21") and "--vae" not in a,
      "the light decoder REPLACES the VAE (both at once is not what upstream takes)", a)
rc, ev = run(mod, "generate", "--model", "wan22-ti2v-5b", "--prompt", "OOMME city at night", "--size", "720p")
retry = [e for e in ev if e.get("code") == "retry"]
a = last_argv()
done = [e for e in ev if e.get("event") == "done"]
check(rc == 0 and retry and "--offload-to-cpu" in a and "--tae" in a and opt(a, "-W") == "832",
      "out of memory retries by itself: weights in RAM, light decoder, 480p", (a, ev[-3:]))
check(done and done[0].get("low_memory") is True, "the result says it was made in low-memory mode")
rc, ev = run(mod, "generate", "--model", "wan22-ti2v-5b", "--prompt", "FAILME")
err = [e for e in ev if e.get("event") == "error"]
check(rc == 1 and len(err) == 1 and err[0].get("code") == "oom" and "generate failed" not in err[0]["text"],
      "a failure that survives the retry is ONE error saying why", err)
check(err and Path(err[0].get("log", "")).is_file() and "allocation" in Path(err[0]["log"]).read_text(encoding="utf-8", errors="replace")
      and Path(err[0]["log"]) == Path(mod.log_path()) and not Path(img_alone.log_path()).exists(),
      "the engine's full output is in the Video page's own log, not the Image page's", err)

# The Image page's warm engine holds a model on the same card.
print("== the Image page's warm engine ==")
sleeper = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"])
Path(img.runtime_dir()).mkdir(parents=True, exist_ok=True)
Path(img._state_file()).write_text(json.dumps({"pid": sleeper.pid, "keeper": None, "port": 1, "key": "k",
                                                "model": "flux2-klein"}))
rc, ev = run(mod, "generate", "--model", "wan21-t2v-1.3b", "--prompt", "a boat")
time.sleep(0.5)
check(rc == 0 and any(e.get("code") == "image-warm-stopped" for e in ev) and sleeper.poll() is not None,
      "a clip stops the Image page's warm engine first, and says so", ev[:3])
if sleeper.poll() is None:
    sleeper.kill()

# ── LoRAs ───────────────────────────────────────────────────────────────────
print("== user LoRAs ==")
def fake_lora(path, keys, shape):
    hdr = json.dumps({k: {"dtype": "F16", "shape": shape(k), "data_offsets": [0, 2]} for k in keys}).encode()
    Path(path).write_bytes(struct.pack("<Q", len(hdr)) + hdr + b"\0\0")

def wan_keys(style):
    if style == "kohya":
        return ["lora_unet_blocks_0_self_attn_q.lora_down.weight", "lora_unet_blocks_0_self_attn_q.lora_up.weight",
                "lora_unet_blocks_0_cross_attn_k.lora_down.weight"]
    if style == "diffusers":
        return ["transformer.blocks.0.attn1.to_q.lora_A.weight", "transformer.blocks.0.attn1.to_q.lora_B.weight"]
    return ["diffusion_model.blocks.0.self_attn.q.lora_A.weight", "diffusion_model.blocks.0.self_attn.q.lora_B.weight",
            "diffusion_model.blocks.0.cross_attn.v.lora_A.weight"]

for dim, fam in ((1536, "wan-1.3b"), (3072, "wan-5b"), (5120, "wan-14b")):
    for style in ("comfy", "kohya", "diffusers"):
        f = tmp / ("w-%d-%s.safetensors" % (dim, style))
        fake_lora(f, wan_keys(style), lambda k, d=dim: [32, d] if ("down" in k or "lora_A" in k) else [d, 32])
        check(img.detect_lora_family(str(f)) == fam, "a %s Wan LoRA (%s keys) is recognized" % (fam, style),
              img.detect_lora_family(str(f)))
ltx = tmp / "ltx.safetensors"
fake_lora(ltx, ["transformer_blocks.0.attn1.to_q.lora_A.weight"], lambda k: [32, 4096])
check(img.detect_lora_family(str(ltx)) == "", "an LTX-style `transformer_blocks.N.attn1` LoRA is NOT read as Wan")
sdxl = tmp / "sdxl.safetensors"
fake_lora(sdxl, ["lora_unet_input_blocks_4_1_transformer_blocks_0_attn1_to_q.lora_down.weight",
                 "lora_te2_text_model_x.lora_up.weight"], lambda k: [32, 640])
check(img.detect_lora_family(str(sdxl)) == "sdxl", "an SDXL LoRA is still SDXL (Wan is checked last)")

rc, ev = run(mod, "lora", "import", str(tmp / "w-3072-comfy.safetensors"), "--name", "Pixar Look",
             "--trigger", "pixar style")
check(rc == 0 and ev[-1].get("family") == "wan-5b", "a Wan LoRA imports into the shared store, with its size", ev[-1:])
run(mod, "lora", "import", str(tmp / "w-5120-kohya.safetensors"), "--name", "Orbit Cam")
rc, ev = run(img_alone, "lora", "list")
check(rc == 0 and {x["id"] for x in ev[0]} >= {"pixar-look", "orbit-cam"},
      "the Image page's tool lists the same LoRAs (one store)", ev[:1])
ckpt = tmp / "old.pt"
ckpt.write_bytes(b"\x80\x04pickle")
rc, ev = run(mod, "lora", "import", str(ckpt))
check(rc == 2 and ev[-1].get("code") == "unsafe-format", "a .pt LoRA is refused -- a pickle can run code", ev[-1:])

rc, ev = run(mod, "generate", "--model", "wan22-ti2v-5b", "--prompt", "a dancing robot", "--lora", "pixar-look:0.7")
pr = opt(last_argv(), "-p")
check(rc == 0 and "<lora:userlora-pixar-look:0.7>" in pr and "pixar style" in pr,
      "a 5B LoRA goes into the prompt with its weight and trigger words", pr)
rc, ev = run(mod, "generate", "--model", "wan22-ti2v-5b", "--prompt", "x", "--lora", "orbit-cam")
check(rc == 2 and ev[-1].get("code") == "lora-mismatch", "a 14B LoRA is refused on the 5B", ev[-1:])
rc, ev = run(mod, "generate", "--model", "wan22-i2v-a14b", "--mode", "i2v", "--image", str(src),
             "--prompt", "a slow orbit", "--lora", "orbit-cam:0.9")
pr = opt(last_argv(), "-p")
check(rc == 0 and "<lora:userlora-orbit-cam:0.9>" in pr and "<lora:|high_noise|userlora-orbit-cam:0.9>" in pr,
      "on Wan2.2 A14B a 14B LoRA is applied to BOTH experts", pr)
check(mod.video_state(mod.video_model("ltx23"))["lora_families"] == [], "LTX-2 offers no user LoRAs (none recognized)")

# ── gallery and removal ────────────────────────────────────────────────────
print("== gallery and removal ==")
(tmp / "out" / "half.part.avi").write_bytes(b"RIFF")
rc, ev = run(mod, "gallery")
items = ev[0] if ev else []
check(rc == 0 and items and all(not it["path"].endswith(".part.avi") for it in items)
      and any(it.get("poster") for it in items) and items[0]["mtime"] >= items[-1]["mtime"],
      "the gallery lists finished clips, newest first, with their posters", [Path(i["path"]).name for i in items])
rc, ev = run(mod, "remove", "wan22-i2v-a14b")
check(rc == 0 and not Path(img.component_path("wan22-i2v-lightning-hi")).exists()
      and not Path(img.component_path("wan22-i2v-lightning-lo")).exists()
      and not Path(img.component_path("wan22-i2v-hi-q3km")).exists(),
      "removing a two-expert model deletes both experts and both Lightning LoRAs")
check(Path(img.component_path("umt5-q4km")).exists() and Path(img.component_path("wan21-vae")).exists(),
      "the text encoder and VAE other downloaded models use stay")

# ── the Monitor backend ────────────────────────────────────────────────────
print("== the Monitor backend ==")
mon = AIM / "monitor"
sys.path.insert(0, str(mon))
gam = None
try:
    spec = importlib.util.spec_from_file_location("gam_monitor", mon / "genesi_ai_monitor.py")
    gam = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gam)
except Exception as e:  # noqa: BLE001
    print("  skip backend: %r" % (e,))
if gam is not None:
    class Sig:
        def __init__(self): self.got = []
        def emit(self, *a): self.got.append(a)

    class FakeSelf:
        _turbo = False
        _turbo_model = ""
        _video_proc = None
        def __init__(self):
            self.videoBusy, self.videoEvent = Sig(), Sig()
            self.args = None
        def _video_tool(self): return ["genesi-ai-video"]
        def _image_stream(self, args, on_event, attr, tool=None):
            self.args = args
            on_event({"event": "done", "path": "/x.mp4"})
            return 0
        def loadVideoGallery(self): pass
        def loadVideoInfo(self): pass

    fs = FakeSelf()
    gam.Backend.generateVideo(fs, json.dumps({
        "mode": "flf2v", "model": "wan22-i2v-a14b", "variant": "q4", "prompt": "turns around",
        "image": "file:///tmp/a.png", "endImage": "/tmp/b.png", "video": "/tmp/ignored.mp4",
        "seconds": 3.5, "size": "720p", "aspect": "9:16", "steps": 12, "seed": 9, "turbo": True,
        "lowMemory": True, "lightVae": True, "loras": [{"id": "orbit-cam", "weight": 0.9}]}))
    for _ in range(50):
        if fs.args is not None and fs.videoBusy.got[-1:] == [(False,)]:
            break
        time.sleep(0.05)
    a = fs.args or []
    check(opt(a, "--mode") == "flf2v" and opt(a, "--image") == "/tmp/a.png" and opt(a, "--end-image") == "/tmp/b.png"
          and "--video" not in a, "the page's pictures reach the right flags (file: URLs made paths)", a)
    check(opt(a, "--seconds") == "3.5" and opt(a, "--size") == "720p" and opt(a, "--aspect") == "9:16"
          and opt(a, "--steps") == "12" and opt(a, "--seed") == "9", "length, size, shape, steps and seed reach the tool", a)
    check("--turbo" in a and "--low-memory" in a and "--light-vae" in a and opt(a, "--lora") == "orbit-cam:0.9",
          "Turbo, low memory, the light decoder and LoRAs reach the tool", a)
    src_text = TOOL.read_text(encoding="utf-8")
    flags = [x for x in a if x.startswith("--")]
    check(all('"%s"' % f in src_text for f in flags), "every flag the backend sends is one the tool parses",
          [f for f in flags if '"%s"' % f not in src_text])

# ── the page, offscreen ────────────────────────────────────────────────────
print("== the Video page loads ==")
try:
    from PySide6.QtCore import QObject, Signal, Slot, QUrl, QtMsgType, qInstallMessageHandler
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtQml import QQmlApplicationEngine, QQmlExpression
    have_qt = True
except ImportError:
    have_qt = False
    print("  skip the page: no PySide6")

if have_qt:
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    os.environ["QT_QUICK_CONTROLS_STYLE"] = "Fusion"
    stage = tmp / "qml"
    stage.mkdir()
    for f in (PKG / "genesi-ui-kit" / "components").glob("*.qml"):
        shutil.copy2(f, stage / f.name)
    for f in mon.glob("*.qml"):
        shutil.copy2(f, stage / f.name)
    shutil.copytree(mon / "icons", stage / "icons")
    (stage / "BrokenPlayer.qml").write_text("import QtQuick\nimport NoSuchModule.AtAll\nItem {}\n")
    with_ffmpeg(True)
    rc, ev = run(mod, "status")
    status = ev[0] if ev else {}
    status["engine_installed"] = True
    status["backend"] = "vulkan"
    rc, ev = run(mod, "catalog")
    catalog = ev[0] if ev else []
    rc, ev = run(mod, "gallery")
    gallery_js = json.dumps(ev[0] if ev else [])

    class FakeBackend(QObject):
        videoInfo = Signal(str); videoGallery = Signal(str); videoPullEvent = Signal(str)
        videoPullDone = Signal(bool, str, str); videoEvent = Signal(str); videoBusy = Signal(bool)
        videoPromptEnhanced = Signal(str, str); imageEngineStatus = Signal(str)
        imageLoras = Signal(str); imagePullDone = Signal(bool, str, str)
        calls = []

        def _c(self, name, *a): FakeBackend.calls.append((name,) + a)
        @Slot(result=str)
        def videoPrefs(self): return json.dumps({"turbo": True, "model": "", "mode": "text", "lowMemory": None})
        @Slot(str)
        def setVideoPrefs(self, s): self._c("setVideoPrefs", s)
        @Slot()
        def loadVideoInfo(self): self.videoInfo.emit(json.dumps({"tool": True, "status": status, "catalog": catalog}))
        @Slot()
        def loadVideoGallery(self): self.videoGallery.emit(gallery_js)
        @Slot()
        def loadImageLoras(self): self.imageLoras.emit(json.dumps(mod.img.load_loras()))
        @Slot(str, str)
        def pullVideoModel(self, a, b): self._c("pull", a, b)
        @Slot()
        def cancelVideoPull(self): pass
        @Slot(str, str)
        def removeVideoModel(self, a, b): pass
        @Slot(str)
        def generateVideo(self, s): self._c("generateVideo", s)
        @Slot()
        def cancelVideo(self): pass
        @Slot(str, str, str)
        def enhanceVideoPrompt(self, a, b, c): pass
        @Slot(result=str)
        def videoLog(self): return ""
        @Slot(str, result=str)
        def prepareImageInput(self, s): return json.dumps({"path": str(src), "name": "portrait.png", "width": 720, "height": 1280})
        @Slot(str, result=str)
        def prepareVideoInput(self, s): return json.dumps({"path": str(source), "name": "source.mp4"})
        @Slot(str, str, str)
        def importImageLora(self, a, b, c): pass
        @Slot(str)
        def removeImageLora(self, a): pass
        @Slot(str)
        def installImageEngine(self, a): pass
        @Slot(str)
        def openImageExternally(self, a): pass
        @Slot()
        def openVideoFolder(self): pass
        @Slot(str, result=bool)
        def deleteVideo(self, a): return True
        @Slot(str, str, result=bool)
        def saveVideoAs(self, a, b): return True
        @Slot(str)
        def copyText(self, a): pass

    msgs = []
    qInstallMessageHandler(lambda mode, ctx, text: msgs.append((mode, text)))
    app = QGuiApplication.instance() or QGuiApplication(sys.argv[:1])
    fb = FakeBackend()

    def load_page(lang, player):
        wrapper = stage / ("Wrap-%s-%s.qml" % (lang, player))
        wrapper.write_text("""import QtQuick
import QtQuick.Window
Window {
    width: 1280; height: 820; visible: true
    property alias page: page
    VideoPage {
        id: page
        objectName: "page"
        anchors.fill: parent
        i18n: QtObject { property string lang: "%s" }
        playerSource: Qt.resolvedUrl("%s")
    }
}
""" % (lang, player), encoding="utf-8")
        engine = QQmlApplicationEngine()
        engine.addImportPath(str(HERE.parent / "devtools" / "kirigami-stub"))
        engine.rootContext().setContextProperty("backend", fb)
        engine.load(QUrl.fromLocalFile(str(wrapper)))
        for _ in range(30):
            app.processEvents()
            time.sleep(0.01)
        roots = engine.rootObjects()
        page = roots[0].findChild(QObject, "page") if roots else None
        engine._keep = roots
        return engine, page

    def ev_js(page, engine, expr):
        e = QQmlExpression(engine.contextForObject(page), page, expr)
        val = e.evaluate()
        return val[0] if isinstance(val, tuple) else val

    def texts(obj):
        # Repeater delegates come and go while the page settles; a child that
        # went away between the listing and the read is simply skipped.
        out = []
        try:
            kids = obj.findChildren(QObject)
        except RuntimeError:
            return out
        for ch in kids:
            try:
                t = ch.property("text")
            except Exception:  # noqa: BLE001
                t = None
            if isinstance(t, str) and t:
                out.append(t)
        return out

    def player_missing(t):
        # The ONE warning the page is built to survive: the player's own
        # import failing where QtMultimedia is not installed (the CI runner
        # has PySide6-Essentials only). Anything else from VideoPlayer.qml,
        # and everything from VideoPage.qml, still counts.
        return ("VideoPlayer.qml" in t and "QtMultimedia" in t and "not installed" in t) \
            or "BrokenPlayer" in t or "NoSuchModule" in t

    def errors(since):
        # QML's own warnings name the .qml file; font or multimedia chatter
        # from the platform does not, and is not this page's fault.
        return [t for m_, t in msgs[since:] if m_ in (QtMsgType.QtWarningMsg, QtMsgType.QtCriticalMsg, QtMsgType.QtFatalMsg)
                and ".qml" in t and not player_missing(t)]

    for lang, want in (("en", "Install the engine"), ("pt", "Instale o motor")):
        n0 = len(msgs)
        engine, page = load_page(lang, "VideoPlayer.qml")
        check(page is not None, "the page loads in %s" % lang, [t for _m, t in msgs[n0:]][:6])
        if page is None:
            continue
        found = texts(page)
        check(want in found, "its words are in %s" % lang, found[:8])
        check(ev_js(page, engine, "catalog.length") == len(catalog),
              "the catalog reaches the page (%s)" % lang)
        page.setProperty("mode", "image")
        app.processEvents()
        check(ev_js(page, engine, "activeModel() ? activeModel().id : ''") == "wan22-ti2v-5b",
              "animating a picture picks the best downloaded face-keeping model (%s)" % lang)
        check("picture" in str(ev_js(page, engine, "blockReason()")) or "imagem" in str(ev_js(page, engine, "blockReason()")),
              "it says a picture is needed first (%s)" % lang, ev_js(page, engine, "blockReason()"))
        ev_js(page, engine, "setImage('file:///x.png', 'start')")
        page.setProperty("promptText", "she waves")
        check(ev_js(page, engine, "canRun()") is True, "with a picture and a prompt the run is allowed (%s)" % lang,
              ev_js(page, engine, "blockReason()"))
        ev_js(page, engine, "run()")
        app.processEvents()
        sent = [c for c in FakeBackend.calls if c[0] == "generateVideo"]
        o = json.loads(sent[-1][1]) if sent else {}
        check(o.get("mode") == "i2v" and o.get("image") == str(src) and o.get("model") == "wan22-ti2v-5b"
              and o.get("seconds") and o.get("size") and "aspect" not in o,
              "Animate sends i2v with the picture, length and size -- no aspect (%s)" % lang, o)
        ev_js(page, engine, "busy = false")
        page.setProperty("mode", "video")
        ev_js(page, engine, "setVideo('file:///s.mp4')")
        check(ev_js(page, engine, "engineMode()") == "extend", "Edit a video starts on Continue (%s)" % lang)
        check(len(errors(n0)) == 0, "no QML warning while loading and using it (%s)" % lang, errors(n0)[:5])
        engine.deleteLater()
        app.processEvents()

    n0 = len(msgs)
    engine, page = load_page("en", "BrokenPlayer.qml")
    check(page is not None, "the page still loads when the player cannot (no QtMultimedia)", [t for _m, t in msgs[n0:]][:6])
    if page is not None:
        page.setProperty("current", None)
        ev_js(page, engine, "current = gallery.length ? gallery[0] : ({ path: '/x.mp4', poster: '' })")
        for _ in range(20):
            app.processEvents()
            time.sleep(0.01)
        check(page.property("playerWorks") is False and
              any("Open in player" == t for t in texts(page)),
              "without a player it offers the system's player instead", page.property("playerWorks"))
        check(len(errors(n0)) == 0, "nothing else breaks with the player missing", errors(n0)[:5])

# ── against upstream ─────────────────────────────────────────────────────────
print("== against upstream (network) ==")
img.COMPONENTS.update(real_components)
pkgbuild = (PKG / "genesi-sd-cpp" / "PKGBUILD").read_text(encoding="utf-8")
commit = re.search(r"^_commit=([0-9a-f]{40})", pkgbuild, re.M).group(1)


def fetch(url, timeout=30):
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "genesi-ci"}),
                                timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")


raw = "https://raw.githubusercontent.com/leejet/stable-diffusion.cpp/%s/" % commit
try:
    upstream = fetch(raw + "examples/common/common.cpp") + fetch(raw + "examples/cli/main.cpp")
except urllib.error.HTTPError as e:
    check(False, "the pinned commit's sources are reachable", "HTTP %s" % e.code)
    upstream = None
except (urllib.error.URLError, OSError) as e:
    print("  skip upstream flags: %s" % e)
    upstream = None

if upstream:
    flags = set()
    for m in mod.VIDEO_MODELS:
        for v in m["variants"]:
            for mode in [c for c in m["caps"]] + (["extend"] if "i2v" in m["caps"] else []):
                for safe in (False, True):
                    s = mod.video_settings(m, True)
                    s["loras"].append(("x.safetensors", 0.5, True))
                    argv = mod.build_video_argv("sd-cli", m, v, s, "p", "o.avi", 832, 480, 49, 1, mode,
                                                "i.png", "e.png", "dir", "cuda", safe, 8192,
                                                low_memory=True, light_vae=True)
                    flags.update(x for x in argv if x.startswith("-") and not re.match(r"^-\d", x))
    for f in sorted(flags):
        check('"%s"' % f in upstream, "sd-cli at %s accepts %s" % (commit[:8], f))
    check('"vid_gen"' in upstream, "the pinned sd-cli has the vid_gen mode")
    check('"|high_noise|"' in upstream, "the pinned sd-cli reads |high_noise| LoRAs")

hf_sha = {}
for cid, c in mod.VIDEO_COMPONENTS.items():
    try:
        req = urllib.request.Request(c["url"], method="HEAD", headers={"User-Agent": "genesi-ci"})
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
    m_ = re.match(r"https://huggingface\.co/([^/]+/[^/]+)/resolve/main/(.+)$", c["url"])
    if not m_:
        continue
    repo, path = m_.groups()
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
