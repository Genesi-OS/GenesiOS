"""End-to-end test of genesi-ai-turbo's GGUF subcommands, driven exactly the way
the AI Mode Monitor drives them: a subprocess whose stdout is machine-readable
JSON and whose human text goes to stderr.

No model downloads, no GPU and no llama-server needed.
"""
import json
import os
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

TURBO = (Path(__file__).resolve().parents[1] / "packages" / "genesi-ai-mode"
         / "genesi-ai-turbo")

T_U32, T_STR = 4, 8


def _str(s):
    b = s.encode()
    return struct.pack("<Q", len(b)) + b


def make_gguf(path, kv, pad_mb=2):
    out = b"GGUF" + struct.pack("<I", 3)
    out += struct.pack("<Q", 0)                     # tensor_count
    out += struct.pack("<Q", len(kv))               # metadata_kv_count
    for key, (vt, val) in kv.items():
        out += _str(key) + struct.pack("<I", vt)
        out += _str(val) if vt == T_STR else struct.pack("<I", val)
    with open(path, "wb") as f:
        f.write(out)
        f.write(b"\0" * (pad_mb * 1024 * 1024))


tmp = tempfile.mkdtemp(prefix="genesi-gguf-cli-test-")
os.makedirs(os.path.join(tmp, "lib"))

moe = os.path.join(tmp, "cli-moe-30b.gguf")
make_gguf(moe, {
    "general.architecture": (T_STR, "qwen3moe"),
    "general.name": (T_STR, "CLI MoE 30B"),
    "general.size_label": (T_STR, "30B"),
    "general.file_type": (T_U32, 15),
    "qwen3moe.expert_count": (T_U32, 128),
    "qwen3moe.block_count": (T_U32, 48),
}, pad_mb=3)

# GENESI_GGUF_DIR is colon-separated ($PATH convention), so we point it at a
# RELATIVE directory and run from `tmp`. Same code path, and it stays runnable on
# a Windows dev box where an absolute path carries a drive-letter colon.
LIBNAME = "lib"
env = dict(os.environ, GENESI_GGUF_DIR=LIBNAME)

failures = []


def run(*args, expect_rc=0):
    p = subprocess.run([sys.executable, str(TURBO)] + list(args),
                       capture_output=True, text=True, env=env, cwd=tmp,
                       timeout=120)
    ok = p.returncode == expect_rc
    print(f"{'PASS' if ok else 'FAIL'}  rc={p.returncode} :: "
          f"{' '.join(args)[:64]}")
    if not ok:
        failures.append(" ".join(args))
        print("   stderr:", (p.stderr or "").strip()[:300])
    return p


def check(label, cond, detail=""):
    print(f"{'PASS' if cond else 'FAIL'}  {label}{'  ' + detail if detail else ''}")
    if not cond:
        failures.append(label)


print("== --help documents the GGUF workflow ==")
p = run("--help")
check("mentions gguf-import", "gguf-import" in p.stdout)
check("documents the gguf:<name> form", "gguf:<name>" in p.stdout)

print("\n== gguf-info on an arbitrary path ==")
p = run("gguf-info", moe)
info = json.loads(p.stdout)
check("name from the header", info["name"] == "CLI MoE 30B", info["name"])
check("MoE detected", info["moe"] is True)
check("expert count", info["experts"] == 128, str(info["experts"]))
check("quant name", info["quant"] == "Q4_K_M", info["quant"])
check("carries a fit verdict", info.get("fit") in ("gpu", "moe", "spill", "cpu"),
      str(info.get("fit")))
check("carries fit detail text", bool(info.get("fit_detail")))

print("\n== gguf-import copies into the library ==")
p = run("gguf-import", moe)
dest = p.stdout.strip()
check("path returned is in the library",
      os.path.basename(os.path.dirname(dest)) == LIBNAME, dest)
check("file exists on disk", os.path.isfile(os.path.join(tmp, dest)))
check("human summary went to stderr", "added" in p.stderr.lower())
check("tells the user how to serve it", "genesi-ai-turbo serve" in p.stderr)

print("\n== gguf-list reports it ==")
p = run("gguf-list")
entries = json.loads(p.stdout)
check("library is non-empty", len(entries) >= 1, f"({len(entries)} entries)")
check("imported file is listed",
      any(os.path.basename(e["path"]) == "cli-moe-30b.gguf" for e in entries))
check("every entry carries a fit verdict", all("fit" in e for e in entries))

print("\n== failure modes are clean (no tracebacks) ==")
p = run("gguf-import", moe, expect_rc=1)
check("duplicate explains itself", "already in the library" in p.stderr,
      p.stderr.strip()[:70])
p = run("gguf-info", "gguf:does-not-exist", expect_rc=1)
check("unknown name: no traceback", "Traceback" not in p.stderr)
p = run("gguf-import", os.path.join(tmp, "nope.gguf"), expect_rc=1)
check("missing file reported", "not a file" in p.stderr, p.stderr.strip()[:70])
p = run("gguf-import", expect_rc=1)
check("usage shown when args are missing", "usage:" in p.stderr,
      p.stderr.strip()[:70])

print("\n== gguf:<name> resolves through the CLI ==")
p = run("gguf-info", "gguf:cli-moe-30b")
check("resolved by library name", json.loads(p.stdout)["name"] == "CLI MoE 30B")

print("\n" + ("ALL TESTS PASSED" if not failures
              else "FAILURES: " + ", ".join(failures)))
sys.exit(1 if failures else 0)
