"""Headless exercise of the Genesi GGUF library in genesi-ai-turbo: header
parsing, discovery, reference resolution, import safety and the fit report.

Builds real (header-valid) GGUF files in a temp dir — no model downloads, no GPU
and no llama-server needed, so this runs anywhere.
"""
import importlib.machinery
import importlib.util
import os
import struct
import sys
import tempfile
from pathlib import Path

TURBO = (Path(__file__).resolve().parents[1] / "packages" / "genesi-ai-mode"
         / "genesi-ai-turbo")

spec = importlib.util.spec_from_loader(
    "turbo", importlib.machinery.SourceFileLoader("turbo", str(TURBO)))
turbo = importlib.util.module_from_spec(spec)
sys.modules["turbo"] = turbo
spec.loader.exec_module(turbo)
print("turbo module loaded OK")

T_U32, T_STR = 4, 8


def _str(s):
    b = s.encode()
    return struct.pack("<Q", len(b)) + b


def make_gguf(path, kv, pad_mb=2):
    """Write a GGUF whose header carries `kv` (name -> (type, value)), padded to
    a plausible size (gguf_describe infers parameter count from the file size)."""
    out = b"GGUF" + struct.pack("<I", 3)            # magic + version 3
    out += struct.pack("<Q", 0)                     # tensor_count
    out += struct.pack("<Q", len(kv))               # metadata_kv_count
    for key, (vt, val) in kv.items():
        out += _str(key) + struct.pack("<I", vt)
        out += _str(val) if vt == T_STR else struct.pack("<I", val)
    with open(path, "wb") as f:
        f.write(out)
        f.write(b"\0" * (pad_mb * 1024 * 1024))


failures = []


def check(label, cond, detail=""):
    print(f"{'PASS' if cond else 'FAIL'}  {label}{'  ' + detail if detail else ''}")
    if not cond:
        failures.append(label)


def eq(label, got, want):
    check(label, got == want, f"got={got!r} want={want!r}")


tmp = tempfile.mkdtemp(prefix="genesi-gguf-test-")
lib = os.path.join(tmp, "library")
downloads = os.path.join(tmp, "downloads")
os.makedirs(lib)
os.makedirs(downloads)
# GENESI_GGUF_DIR is colon-separated ($PATH convention). Overriding the two
# directory functions instead keeps this test runnable on a Windows dev box,
# where an absolute path carries a drive-letter colon, while still exercising
# the real scan / resolve / import code.
turbo.gguf_library_dir = lambda: lib
turbo._gguf_scan_dirs = lambda: [lib, downloads]

dense = os.path.join(downloads, "test-dense-8b-q4_k_m.gguf")
make_gguf(dense, {
    "general.architecture": (T_STR, "llama"),
    "general.name": (T_STR, "Test Dense 8B"),
    "general.size_label": (T_STR, "8B"),
    "general.file_type": (T_U32, 15),               # Q4_K_M
    "llama.block_count": (T_U32, 32),
    "llama.context_length": (T_U32, 8192),
}, pad_mb=4)

moe = os.path.join(downloads, "test-moe-30b-a3b.gguf")
make_gguf(moe, {
    "general.architecture": (T_STR, "qwen3moe"),
    "general.name": (T_STR, "Test MoE 30B"),
    "general.size_label": (T_STR, "30B"),
    "general.file_type": (T_U32, 15),
    "qwen3moe.expert_count": (T_U32, 128),
    "qwen3moe.block_count": (T_U32, 48),
    "qwen3moe.context_length": (T_U32, 32768),
}, pad_mb=3)

for i in (1, 2):                                    # a sharded set
    make_gguf(os.path.join(downloads, f"big-0000{i}-of-00002.gguf"),
              {"general.name": (T_STR, "Big Sharded")}, pad_mb=2)

with open(os.path.join(downloads, "stub.gguf"), "wb") as f:
    f.write(b"GGUF" + b"\0" * 100)                  # truncated download
with open(os.path.join(downloads, "notes.txt"), "wb") as f:
    f.write(b"hello")

print("\n== gguf_describe: dense ==")
d = turbo.gguf_describe(dense)
eq("architecture", d["arch"], "llama")
eq("name from header", d["name"], "Test Dense 8B")
eq("quant name", d["quant"], "Q4_K_M")
eq("parameter count", d["params_b"], 8.0)
eq("not MoE", d["moe"], False)
eq("context length", d["context"], 8192)

print("\n== gguf_describe: MoE ==")
m = turbo.gguf_describe(moe)
eq("architecture", m["arch"], "qwen3moe")
eq("expert count", m["experts"], 128)
eq("flagged MoE", m["moe"], True)
eq("block count", m["blocks"], 48)
eq("parameter count", m["params_b"], 30.0)

print("\n== gguf_describe: fallbacks ==")
nolabel = os.path.join(downloads, "nolabel.gguf")
make_gguf(nolabel, {"general.file_type": (T_U32, 15)}, pad_mb=128)
n = turbo.gguf_describe(nolabel)
eq("params inferred from file size", n["params_b"], 0.2)
eq("name falls back to the file name", n["name"], "nolabel")

print("\n== scan_gguf_library ==")
names = sorted(os.path.basename(e["path"]) for e in turbo.scan_gguf_library())
check("dense model found", "test-dense-8b-q4_k_m.gguf" in names)
check("MoE model found", "test-moe-30b-a3b.gguf" in names)
check("first shard listed", "big-00001-of-00002.gguf" in names)
check("later shards hidden", "big-00002-of-00002.gguf" not in names)
check("truncated stub ignored", "stub.gguf" not in names)
check("non-gguf ignored", not any(x.endswith(".txt") for x in names))

print("\n== reference detection and resolution ==")
eq("a path is a GGUF ref", turbo.is_gguf_ref(dense), True)
eq("gguf: scheme is a GGUF ref", turbo.is_gguf_ref("gguf:test-moe-30b-a3b"), True)
eq("an ollama tag is not", turbo.is_gguf_ref("llama3.1:8b"), False)
eq("empty is not", turbo.is_gguf_ref(""), False)
eq("resolve a path", turbo.resolve_gguf_ref(dense), os.path.abspath(dense))
eq("resolve gguf:<name>", turbo.resolve_gguf_ref("gguf:test-moe-30b-a3b"), moe)
eq("resolve gguf:<file.gguf>",
   turbo.resolve_gguf_ref("gguf:test-moe-30b-a3b.gguf"), moe)
eq("unknown name resolves to None", turbo.resolve_gguf_ref("gguf:nope"), None)

print("\n== ensure() routes GGUF refs without touching ollama ==")
eq("ensure(path)", turbo.ensure(dense), os.path.abspath(dense))
eq("ensure(gguf:name)", turbo.ensure("gguf:test-moe-30b-a3b"), moe)

print("\n== pick_draft ==")
# A mismatched-tokenizer draft silently corrupts speculative decoding, so a raw
# GGUF must never be paired with a guessed sibling.
eq("no guessed draft for a GGUF", turbo.pick_draft(dense), None)
check("ollama tags still get a draft", turbo.pick_draft("llama3.1:8b") is not None)

print("\n== import_gguf ==")
dest = turbo.import_gguf(dense)
check("copied into the library",
      os.path.isfile(dest) and os.path.dirname(dest) == lib, dest)
check("source left in place (copy, not move)", os.path.isfile(dense))
eq("in_library flag set", turbo.gguf_describe(dest)["in_library"], True)
try:
    turbo.import_gguf(dense)
    check("duplicate rejected", False, "(no error raised)")
except ValueError as e:
    check("duplicate rejected", "already in the library" in str(e), f"({e})")
try:
    turbo.import_gguf(os.path.join(downloads, "notes.txt"))
    check("non-gguf rejected", False, "(no error raised)")
except ValueError as e:
    check("non-gguf rejected", "not a .gguf" in str(e), f"({e})")
bad = os.path.join(downloads, "corrupt.gguf")
with open(bad, "wb") as f:
    f.write(b"XXXX" + b"\0" * (2 * 1024 * 1024))
try:
    turbo.import_gguf(bad)
    check("bad magic rejected", False, "(no error raised)")
except ValueError as e:
    check("bad magic rejected", "not a valid GGUF" in str(e), f"({e})")

print("\n== gguf_fit_report ==")
turbo._detect_vram_mb = lambda: 8192                # simulate an 8 GB card
turbo._total_ram_gb = lambda: 32.0
eq("small dense fits the GPU",
   turbo.gguf_fit_report(dict(m, size_gb=4.0, moe=False))[0], "gpu")
eq("oversized MoE uses expert offload",
   turbo.gguf_fit_report(dict(m, size_gb=17.0))[0], "moe")
eq("oversized dense spills",
   turbo.gguf_fit_report(dict(m, size_gb=17.0, moe=False, experts=0))[0], "spill")
turbo._total_ram_gb = lambda: 8.0
eq("MoE beyond RAM is not recommended",
   turbo.gguf_fit_report(dict(m, size_gb=17.0))[0], "spill")
turbo._detect_vram_mb = lambda: 0
turbo._total_ram_gb = lambda: 16.0
eq("no GPU falls back to CPU",
   turbo.gguf_fit_report(dict(m, size_gb=4.0, moe=False))[0], "cpu")

print("\n" + ("ALL TESTS PASSED" if not failures
              else "FAILURES: " + ", ".join(failures)))
sys.exit(1 if failures else 0)
