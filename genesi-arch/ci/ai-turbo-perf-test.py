"""Holds AI Mode's inference tuning to what actually reaches the running server.

Every check here is a setting that looked shipped and silently was not:

  * llama-server's slot count: Turbo decided on ONE slot (extra slots slowed
    single-stream decode) but only ever passed --parallel when it wanted MORE,
    and the server's own default is "auto" = 4 slots + unified KV.
  * --prio 2: an EPERM warning as a user, SCHED_FIFO 80 as root.
  * /etc/genesi-ai-mode/turbo.env: read by the always-warm unit only, never by
    the Turbo the Monitor / Quick Chat / automations start.
  * genesi-aid's nice and P-core pinning: per-thread on Linux, applied to the
    main thread only, never to the compute threads.
  * "hybrid CPU" guessed from per-core max frequency, which amd-pstate's
    preferred-core ranking makes uneven on a uniform Ryzen.
  * the autotuner choosing n_ubatch (a PROMPT knob) by DECODE speed, and
    benching every GPU model fully offloaded -- which cannot load the MoE
    models Turbo runs with experts in RAM.

Headless: genesi-ai-turbo, genesi-aid and genesi-ai-tune are loaded as modules
with their system probes stubbed. With network, the flags Turbo emits are also
held to llama.cpp's PINNED commit (the one both llama.cpp PKGBUILDs build):
each must be defined there, and the server's auto slot default is re-read so
the explicit --parallel stays justified. No network: those are skipped.
"""
import importlib.machinery
import importlib.util
import json
import os
import re
import sys
import tempfile
import types
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PKG = ROOT / "packages" / "genesi-ai-mode"

failures = []


def check(label, cond, detail=""):
    print(f"{'PASS' if cond else 'FAIL'}  {label}{'  ' + detail if detail else ''}")
    if not cond:
        failures.append(label)


def eq(label, got, want):
    check(label, got == want, f"got={got!r} want={want!r}")


def load(name, path):
    spec = importlib.util.spec_from_loader(
        name, importlib.machinery.SourceFileLoader(name, str(path)))
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


# The Turbo env files are read at import. Point HOME somewhere empty first so
# the developer's own ~/.config/genesi/turbo.env cannot change what we test.
_home = tempfile.mkdtemp(prefix="genesi-turbo-home-")
os.environ["HOME"] = os.environ["USERPROFILE"] = _home
for k in list(os.environ):
    if k.startswith("GENESI_"):
        del os.environ[k]

turbo = load("turbo", PKG / "genesi-ai-turbo")
tune = load("tune", PKG / "genesi-ai-tune")

# genesi-aid imports psutil at the top; nothing tested here touches it.
sys.modules.setdefault("psutil", types.ModuleType("psutil"))
aid = load("aid", PKG / "genesi-aid")
print("modules loaded OK")

tmp = Path(tempfile.mkdtemp(prefix="genesi-turbo-perf-"))


# ── turbo.env reaches Turbo however it is started ───────────────────────────
print("\n== env files ==")
user_f, sys_f = tmp / "user.env", tmp / "system.env"
user_f.write_text("# user knobs\nexport GENESI_TURBO_CTX=16384\n"
                  "GENESI_TURBO_FIT='1'\n", encoding="utf-8")
sys_f.write_text("GENESI_TURBO_CTX=4096\nGENESI_TURBO_PARALLEL=\"3\"\n"
                 "GENESI_TURBO_HOST=0.0.0.0\nPATH=/evil\n"
                 "GENESI_TURBO_KV=f16\n", encoding="utf-8")
env = {"GENESI_TURBO_KV": "q4_0"}
filled = turbo.load_env_defaults([str(user_f), str(sys_f)], environ=env)
eq("user file beats system file", env.get("GENESI_TURBO_CTX"), "16384")
eq("quotes stripped", env.get("GENESI_TURBO_FIT"), "1")
eq("system-only knob filled", env.get("GENESI_TURBO_PARALLEL"), "3")
eq("real env var wins over both files", env.get("GENESI_TURBO_KV"), "q4_0")
check("LAN bind is never inherited from a file",
      "GENESI_TURBO_HOST" not in env)
check("only GENESI_* keys are read", "PATH" not in env)
eq("reports what it filled", sorted(filled),
   ["GENESI_TURBO_CTX", "GENESI_TURBO_FIT", "GENESI_TURBO_PARALLEL"])
eq("missing files are fine",
   turbo.load_env_defaults([str(tmp / "nope.env")], environ={}), {})
check("the Turbo module reads the files at import (not only the unit)",
      re.search(r"^load_env_defaults\(\)\s*$", (PKG / "genesi-ai-turbo")
                .read_text(encoding="utf-8"), re.M) is not None)


# ── server_cmd against a stand-in llama-server ─────────────────────────────
# --help text of the pinned build, reduced to the flags server_cmd probes for.
HELP = """
-t, --threads N   -tb, --threads-batch N   --prio N   -c, --ctx-size N
-np, --parallel N   -cb, --cont-batching   --cache-reuse N   --jinja
-fa, --flash-attn [on|off|auto]   -ngl, --gpu-layers, --n-gpu-layers N
  max. number of layers to store in VRAM, either an exact number, 'auto', or 'all'
-lm, --load-mode MODE   --mlock   --slot-save-path PATH
-cmoe, --cpu-moe   -ncmoe, --n-cpu-moe N   -md, --model-draft FNAME
--spec-draft-n-max N   --spec-draft-n-min N   --spec-draft-p-min P
--spec-draft-ngl, -ngld N
--spec-type none,draft-simple,draft-eagle3,ngram-simple,ngram-map-k,ngram-mod
"""

model = tmp / "small-q4.gguf"
model.write_bytes(b"\0" * 1024)          # tiny: fits any card
draft = tmp / "draft.gguf"
draft.write_bytes(b"\0" * 512)

# 3.5 GB card: little enough headroom that the auto rule keeps ONE slot (an 8 GB
# card with this tiny model would legitimately get a second).
GPU_MB = 3584
state = {"vram": GPU_MB, "help": HELP}
turbo.llama_bin = lambda name: "/usr/bin/" + name
turbo._llama_help = lambda: state["help"]
turbo._detect_vram_mb = lambda: state["vram"]
turbo.backend_is_cuda = lambda: False
turbo.mesh_plan = lambda gb: ([], 0.0, "")
turbo.shutil.which = lambda n: None      # no nvidia-smi: GPU only via VRAM probe
os.environ["GENESI_TURBO_NO_TUNE"] = "1"
os.environ["GENESI_TURBO_NO_SLOT_CACHE"] = "1"


def arg(cmd, flag):
    try:
        return cmd[cmd.index(flag) + 1]
    except (ValueError, IndexError):
        return None


print("\n== server_cmd (GPU, model fits) ==")
cmd = turbo.server_cmd(str(model), None)
check("built a command", bool(cmd))
eq("single slot is STATED, not left to the server's auto (=4)",
   arg(cmd, "--parallel"), "1")
check("no --cont-batching for one slot", "--cont-batching" not in cmd)
check("no --prio by default", "--prio" not in cmd)
eq("model-free speculation selected by a name the build lists",
   arg(cmd, "--spec-type"), "ngram-simple")
eq("full offload", arg(cmd, "-ngl"), "999")
eq("flash attention on GPU", arg(cmd, "-fa"), "on")

os.environ["GENESI_TURBO_PARALLEL"] = "3"
cmd3 = turbo.server_cmd(str(model), None)
eq("pinned slots pass through", arg(cmd3, "--parallel"), "3")
check("cont-batching with several slots", "--cont-batching" in cmd3)
eq("_slots reads the count", (turbo._slots(cmd), turbo._slots(cmd3)), (1, 3))
del os.environ["GENESI_TURBO_PARALLEL"]

os.environ["GENESI_TURBO_MLOCK"] = "1"
cmdm = turbo.server_cmd(str(model), None)
eq("mlock uses the non-deprecated --load-mode", arg(cmdm, "--load-mode"), "mlock")
check("and not the deprecated --mlock", "--mlock" not in cmdm)
del os.environ["GENESI_TURBO_MLOCK"]

state["help"] = HELP.replace("ngram-simple,", "")
cmdn = turbo.server_cmd(str(model), None)
check("an unknown --spec-type value is never passed (server would not start)",
      "--spec-type" not in cmdn)
state["help"] = HELP.replace("draft-simple,", "")
cmdd = turbo.server_cmd(str(model), str(draft))
check("draft-simple gated on the build listing it", "--spec-type" not in cmdd)
state["help"] = HELP
cmdd = turbo.server_cmd(str(model), str(draft))
eq("draft speculation when listed", arg(cmdd, "--spec-type"), "draft-simple")

state["help"] = HELP.replace("-np, --parallel N", "")
eq("a build without --parallel (default 1 there) gets no flag",
   arg(turbo.server_cmd(str(model), None), "--parallel"), None)
state["help"] = HELP

print("\n== server_cmd (CPU only) ==")
state["vram"] = 0
cmdc = turbo.server_cmd(str(model), None)
check("CPU: no --prio by default (EPERM as user, SCHED_FIFO as root)",
      "--prio" not in cmdc)
check("CPU: prefill threads still split", "--threads-batch" in cmdc)
eq("CPU: single slot stated", arg(cmdc, "--parallel"), "1")
os.environ["GENESI_TURBO_PRIO"] = "1"
eq("GENESI_TURBO_PRIO passes through",
   arg(turbo.server_cmd(str(model), None), "--prio"), "1")
del os.environ["GENESI_TURBO_PRIO"]
state["vram"] = GPU_MB


print("\n== fallback chain stays a single exec for a plain command ==")
launched = []
turbo.os.execvp = lambda f, c: launched.append(("exec", c))


class _NoPopen:
    def __init__(self, *a, **k):
        launched.append(("popen", a[0]))
        raise RuntimeError("a plain single-slot launch must not need a fallback")


turbo.subprocess.Popen = _NoPopen
try:
    turbo._serve_with_fallback(str(model), None)
except RuntimeError as e:
    pass
eq("plain launch is exec'd directly (no fallback ladder)",
   [k for k, _ in launched], ["exec"])


# ── which cores are fast ─────────────────────────────────────────────────────
print("\n== hybrid CPU detection ==")


def fake_sys(cpus_core=None, cpus_atom=None, topo=None):
    root = Path(tempfile.mkdtemp(prefix="genesi-sys-", dir=tmp))
    if cpus_core is not None:
        (root / "devices" / "cpu_core").mkdir(parents=True)
        (root / "devices" / "cpu_core" / "cpus").write_text(cpus_core + "\n")
    if cpus_atom is not None:
        (root / "devices" / "cpu_atom").mkdir(parents=True)
        (root / "devices" / "cpu_atom" / "cpus").write_text(cpus_atom + "\n")
    for cpu, (pkg, core) in (topo or {}).items():
        t = root / "devices" / "system" / "cpu" / f"cpu{cpu}" / "topology"
        t.mkdir(parents=True)
        (t / "core_id").write_text(str(core))
        (t / "physical_package_id").write_text(str(pkg))
    return root


# i5-13420H-like: 4 P-cores with HT (cpus 0-7) + 4 E-cores (8-11).
hyb = fake_sys("0-7", "8-11", {i: (0, i // 2) for i in range(8)})
eq("hybrid: P physical cores counted, HT deduped",
   turbo._performance_cores(6, sys_root=str(hyb)), 4)
ryzen = fake_sys()                       # uniform CPU: no hybrid PMUs at all
eq("uniform Ryzen: all physical cores (never a frequency guess)",
   turbo._performance_cores(6, sys_root=str(ryzen)), 6)
eq("cpu_core alone (no E-cores) is not hybrid",
   turbo._performance_cores(6, sys_root=str(fake_sys("0-11", None))), 6)
# A cpu_atom PMU that lists no CPUs (E-cores offlined / disabled in firmware):
# nothing slow to avoid, so every core decodes.
no_e = fake_sys("0-3", "", {i: (0, i // 2) for i in range(4)})
eq("empty E-core list is not hybrid (Turbo)",
   turbo._performance_cores(6, sys_root=str(no_e)), 6)
eq("empty E-core list is not hybrid (daemon)",
   aid._performance_cpu_ids(str(no_e / "devices/cpu_core/cpus"),
                            str(no_e / "devices/cpu_atom/cpus")), [])
src_turbo = (PKG / "genesi-ai-turbo").read_text(encoding="utf-8")
check("Turbo no longer reads cpuinfo_max_freq to pick cores",
      "cpuinfo_max_freq" not in re.sub(r"#.*|\"\"\"[\s\S]*?\"\"\"", "",
                                       src_turbo))

eq("cpu list parsing", aid._parse_cpu_list("0-3,8,10-11"),
   [0, 1, 2, 3, 8, 10, 11])
eq("bad cpu list", aid._parse_cpu_list("x-y"), [])
eq("daemon: hybrid P-cores",
   aid._performance_cpu_ids(str(hyb / "devices/cpu_core/cpus"),
                            str(hyb / "devices/cpu_atom/cpus")),
   list(range(8)))
eq("daemon: uniform CPU -> no pinning",
   aid._performance_cpu_ids(str(ryzen / "devices/cpu_core/cpus"),
                            str(ryzen / "devices/cpu_atom/cpus")), [])
src_aid = (PKG / "genesi-aid").read_text(encoding="utf-8")
check("daemon no longer reads cpuinfo_max_freq to pick cores",
      "cpuinfo_max_freq" not in re.sub(r"#.*|\"\"\"[\s\S]*?\"\"\"", "", src_aid))


# ── genesi-aid renices and pins EVERY thread ────────────────────────────────
print("\n== per-thread priority ==")


class FakeOS:
    """Just enough of os for _tune_threads: a process with 3 threads, the main
    one already reniced (as psutil's proc.nice() used to leave it)."""
    PRIO_PROCESS = 0

    def __init__(self):
        self.nice = {100: -5, 101: 0, 102: 0}
        self.aff = {100: {0, 1, 2, 3}, 101: set(range(12)), 102: set(range(12))}

    def listdir(self, path):
        assert path == "/proc/100/task", path
        return [str(t) for t in self.nice]

    def getpriority(self, which, tid):
        return self.nice[tid]

    def setpriority(self, which, tid, v):
        self.nice[tid] = v

    def sched_getaffinity(self, tid):
        return set(self.aff[tid])

    def sched_setaffinity(self, tid, cpus):
        self.aff[tid] = set(cpus)


fos = FakeOS()
real_os, aid.os = aid.os, fos
try:
    rn, pn = aid._tune_threads(100, -5, [0, 1, 2, 3])
    eq("every compute thread reniced (not just the main one)",
       fos.nice, {100: -5, 101: -5, 102: -5})
    eq("every thread pinned", fos.aff,
       {100: {0, 1, 2, 3}, 101: {0, 1, 2, 3}, 102: {0, 1, 2, 3}})
    eq("only the threads that changed are counted", (rn, pn), (2, 2))
    eq("steady state is silent", aid._tune_threads(100, -5, [0, 1, 2, 3]), (0, 0))
    aid._tune_threads(100, 0, None)
    eq("restore resets nice on every thread", set(fos.nice.values()), {0})
finally:
    aid.os = real_os
body = src_aid[src_aid.index("def prioritize_ai_processes"):]
body = body[:body.index("\n    def ", 10)]
check("prioritize_ai_processes goes through _tune_threads",
      "_tune_threads(" in body)
check("prioritize_ai_processes no longer uses process-level proc.nice()",
      "proc.nice(" not in re.sub(r"#.*", "", body))


# ── the autotuner ───────────────────────────────────────────────────────────
print("\n== autotuner ==")


def row(ub, fa, kv, pp, tg_ts, t=6, kv_v=None):
    base = {"n_ubatch": ub, "flash_attn": fa, "type_k": kv,
            "type_v": kv_v or kv, "n_threads": t}
    return [dict(base, n_prompt=512, n_gen=0, avg_ts=pp),
            dict(base, n_prompt=0, n_gen=128, avg_ts=tg_ts)]


rows = []
# Decode barely moves with ubatch (noise); prefill clearly prefers 2048.
rows += row(512, 1, "q8_0", 900.0, 41.3)
rows += row(1024, 1, "q8_0", 1300.0, 40.9)
rows += row(2048, 1, "q8_0", 1700.0, 41.0)
rows += row(512, 0, "f16", 950.0, 38.0)
rows += row(2048, 0, "f16", 1600.0, 38.2)
# An unmatched k/v pair, fastest of all but impossible to reproduce.
rows += row(512, 1, "q8_0", 2000.0, 60.0, kv_v="f16")
ts, cfg = tune.pick_winner(rows, with_threads=False)
eq("decode knobs by decode speed", (cfg.get("fa"), cfg.get("kv")), ("on", "q8_0"))
eq("ubatch by PREFILL speed, not decode noise", cfg.get("ubatch"), 2048)
check("an unmatched k/v row never wins", ts < 50)
check("threads not saved when not swept", "threads" not in cfg)

rows_t = row(512, 1, "q8_0", 500.0, 14.0, t=6) + row(512, 1, "q8_0", 480.0, 9.5, t=12)
eq("threads chosen when swept (MoE / CPU)",
   tune.pick_winner(rows_t, with_threads=True)[1].get("threads"), 6)
eq("nothing measured -> None", tune.pick_winner([], with_threads=False), None)

full = tune.gpu_matrix({"ngl": "999"}, 12)
check("full offload: -ngl 999 and no -ncmoe",
      all(m[m.index("-ngl") + 1] == "999" and "-ncmoe" not in m for m in full))
moe = tune.gpu_matrix({"ngl": "999", "n_cpu_moe": 20, "threads": 6}, 12)
check("MoE: bench uses the server's --n-cpu-moe",
      all(m[m.index("-ncmoe") + 1] == "20" for m in moe))
eq("MoE: thread count swept", moe[0][moe[0].index("-t") + 1], "6,12")
check("MoE: KV swept as matched pairs only",
      all(m[m.index("-ctk") + 1] == m[m.index("-ctv") + 1] for m in moe))
allmoe = tune.gpu_matrix({"ngl": "999", "cpu_moe": True, "threads": 6}, 12)
check("--cpu-moe maps to every layer's experts on the CPU",
      all("-ncmoe" in m for m in allmoe))
eq("dense spill (-ngl auto): nothing reproducible to bench",
   tune.gpu_matrix({"ngl": "auto"}, 12), [])
eq("no placement known: assume full offload",
   tune.gpu_matrix({}, 12)[0][:2], ["-ngl", "999"])


# ── the pinned llama.cpp really has every flag we emit ──────────────────────
print("\n== against llama.cpp's pinned commit (network) ==")
pk = (ROOT / "packages" / "genesi-llama-cpp" / "PKGBUILD").read_text(encoding="utf-8")
pk_cuda = (ROOT / "packages" / "genesi-llama-cpp-cuda" / "PKGBUILD").read_text(
    encoding="utf-8")
commit = re.search(r"^_commit=([0-9a-f]{40})", pk, re.M)
commit_cuda = re.search(r"^_commit=([0-9a-f]{40})", pk_cuda, re.M)
check("both llama.cpp builds pin a commit", bool(commit and commit_cuda))


def fetch(path):
    url = ("https://raw.githubusercontent.com/ggml-org/llama.cpp/%s/%s"
           % (commit.group(1), path))
    try:
        with urllib.request.urlopen(url, timeout=20) as r:
            return r.read().decode("utf-8", "replace")
    except Exception as e:
        print(f"SKIP  {path}: {e}")
        return None


arg_cpp = fetch("common/arg.cpp") if commit else None
if arg_cpp:
    defined = set(re.findall(r'"(-{1,2}[a-z][a-z0-9-]*)"', arg_cpp))
    emitted = set()
    for c in (cmd, cmd3, cmdm, cmdc, cmdd):
        emitted |= {a for a in c[1:] if a.startswith("-") and not
                    re.fullmatch(r"-?\d+(\.\d+)?", a)}
    missing = sorted(emitted - defined)
    eq("every flag Turbo emits exists in the pinned build", missing, [])
    spec_cpp = fetch("common/speculative.cpp")
    if spec_cpp:
        for name in ("draft-simple", "ngram-simple"):
            check(f"--spec-type {name} exists in the pinned build",
                  f'"{name}"' in spec_cpp)
    if "--mlock" in arg_cpp and "--load-mode" not in arg_cpp:
        failures.append("pinned build lost --load-mode")
server_cpp = fetch("tools/server/server.cpp") if commit else None
if server_cpp:
    check("pinned server still defaults to auto slots (why --parallel 1 is "
          "stated)", "n_parallel = 4" in server_cpp)

print()
if failures:
    print(f"{len(failures)} FAILED:")
    for f in failures:
        print("  - " + f)
    sys.exit(1)
print("all AI Mode inference-tuning checks passed")
