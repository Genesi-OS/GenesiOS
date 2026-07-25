"""Exercises how a local GGUF is routed everywhere a model can be chosen.

The rule under test: an Ollama tag follows the user's Turbo preference, but a
GGUF ALWAYS has to go through llama-server (Ollama's chat API only knows its own
registry), so it must work in the chat, Quick Chat and automations whether or not
the Turbo switch is on.

The decision logic lives in the Qt-free genesi_turbo_ctl, so this runs headless.
The Monitor Backend that consumes it is exercised too, behind a minimal PySide6
stub, because the routing there used to be a bare `if self._turbo`.
"""
import importlib.machinery
import importlib.util
import json
import sys
import types
from pathlib import Path

MONITOR = (Path(__file__).resolve().parents[1] / "packages" / "genesi-ai-mode"
           / "monitor")
sys.path.insert(0, str(MONITOR))


def load(name, path):
    spec = importlib.util.spec_from_loader(
        name, importlib.machinery.SourceFileLoader(name, str(path)))
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


ctl = load("genesi_turbo_ctl", MONITOR / "genesi_turbo_ctl.py")
print("genesi_turbo_ctl loaded OK")

failures = []


def check(label, cond, detail=""):
    print(f"{'PASS' if cond else 'FAIL'}  {label}{'  ' + detail if detail else ''}")
    if not cond:
        failures.append(label)


def eq(label, got, want):
    check(label, got == want, f"got={got!r} want={want!r}")


# ── is_gguf_ref ──────────────────────────────────────────────────────────────
print("\n== is_gguf_ref ==")
eq("gguf: scheme", ctl.is_gguf_ref("gguf:qwen3-30b"), True)
eq("a .gguf path", ctl.is_gguf_ref("/home/u/m.gguf"), True)
eq("ollama tag", ctl.is_gguf_ref("llama3.1:8b"), False)
eq("ollama tag with dots", ctl.is_gguf_ref("qwen2.5:7b"), False)
eq("empty", ctl.is_gguf_ref(""), False)
eq("None", ctl.is_gguf_ref(None), False)

# ── the library + labels (CLI stubbed) ───────────────────────────────────────
LISTING = [
    {"path": "/models/qwen3-30b-a3b-q4_k_m.gguf", "name": "Qwen3 30B A3B",
     "params_b": 30.0, "size_gb": 17.2, "moe": True, "fit": "moe"},
    {"path": "/models/tiny.gguf", "name": "", "params_b": 1.1,
     "size_gb": 0.7, "moe": False, "fit": "gpu"},
]


class FakeRun:
    def __init__(self, stdout):
        self.stdout, self.returncode, self.stderr = stdout, 0, ""


calls = {"n": 0}


def fake_run(cmd, **kw):
    calls["n"] += 1
    return FakeRun(json.dumps(LISTING))


ctl.shutil.which = lambda n: "/usr/bin/" + n
ctl.subprocess.run = fake_run

print("\n== list_gguf_models ==")
ctl.invalidate_gguf_cache()
items = ctl.list_gguf_models()
eq("two models listed", len(items), 2)
eq("ref is the stable gguf: form", items[0]["ref"], "gguf:qwen3-30b-a3b-q4_k_m")
eq("MoE flag carried", items[0]["moe"], True)
eq("fit verdict carried", items[0]["fit"], "moe")

print("\n== caching (a picker asks for labels repeatedly) ==")
before = calls["n"]
for _ in range(5):
    ctl.list_gguf_models()
eq("no extra CLI calls while cached", calls["n"], before)
ctl.invalidate_gguf_cache()
ctl.list_gguf_models()
eq("invalidate forces a rescan", calls["n"], before + 1)

print("\n== model_label ==")
eq("ollama tag passes through", ctl.model_label("llama3.1:8b"), "llama3.1:8b")
eq("gguf uses its header name + size",
   ctl.model_label("gguf:qwen3-30b-a3b-q4_k_m"), "Qwen3 30B A3B · 30B (GGUF)")
eq("nameless gguf falls back to the file stem",
   ctl.model_label("gguf:tiny"), "tiny · 1.1B (GGUF)")
eq("unknown gguf still readable (file deleted / drive unplugged)",
   ctl.model_label("gguf:vanished"), "vanished (GGUF)")
eq("empty", ctl.model_label(""), "")

# ── serves_model: the routing decision ───────────────────────────────────────
print("\n== serves_model ==")
ensured = {}


def fake_ensure(model, spec=False, on_status=None, timeout=900, stop_check=None):
    ensured["model"], ensured["spec"] = model, spec
    return True, "Turbo active"


ctl.ensure = fake_ensure

ensured.clear()
force, ok, msg = ctl.serves_model("llama3.1:8b")
eq("ollama tag does not force turbo", force, False)
eq("ollama tag is always ok", ok, True)
check("ollama tag never starts a server", "model" not in ensured)

ensured.clear()
force, ok, msg = ctl.serves_model("gguf:qwen3-30b-a3b-q4_k_m")
eq("gguf forces turbo", force, True)
eq("gguf reports ok when the server came up", ok, True)
eq("ensure got the exact reference", ensured.get("model"),
   "gguf:qwen3-30b-a3b-q4_k_m")

ensured.clear()
force, ok, _ = ctl.serves_model("gguf:x", spec=True)
eq("spec preference is forwarded", ensured.get("spec"), True)


def failing_ensure(model, spec=False, on_status=None, timeout=900, stop_check=None):
    return False, "Turbo backend (llama-server) not installed"


ctl.ensure = failing_ensure
force, ok, msg = ctl.serves_model("gguf:x")
eq("a failed load still forces turbo (no ollama fallback)", force, True)
eq("failure is reported", ok, False)
check("failure carries a reason", "llama-server" in msg, msg)

# ── the Monitor Backend's transport choice ───────────────────────────────────
print("\n== Backend._prepare_transport (PySide6 stubbed) ==")


def _install_qt_stub():
    """Minimal PySide6 so genesi_ai_monitor imports without a Qt runtime."""
    class Signal:
        def __init__(self, *a, **k):
            pass

        def __get__(self, obj, owner=None):
            return types.SimpleNamespace(emit=lambda *a, **k: None,
                                         connect=lambda *a, **k: None)

    def Slot(*a, **k):
        return lambda fn: fn

    class QObject:
        def __init__(self, *a, **k):
            pass

    qtcore = types.ModuleType("PySide6.QtCore")
    qtcore.QObject, qtcore.Signal, qtcore.Slot = QObject, Signal, Slot
    qtcore.QTimer = qtcore.QUrl = qtcore.Qt = object
    qtgui = types.ModuleType("PySide6.QtGui")
    qtgui.QGuiApplication = qtgui.QIcon = qtgui.QFont = qtgui.QFontDatabase = object
    qtqml = types.ModuleType("PySide6.QtQml")
    qtqml.QQmlApplicationEngine = object
    pkg = types.ModuleType("PySide6")
    pkg.QtCore, pkg.QtGui, pkg.QtQml = qtcore, qtgui, qtqml
    for name, mod in (("PySide6", pkg), ("PySide6.QtCore", qtcore),
                      ("PySide6.QtGui", qtgui), ("PySide6.QtQml", qtqml)):
        sys.modules[name] = mod


_install_qt_stub()
try:
    mon = load("genesi_ai_monitor", MONITOR / "genesi_ai_monitor.py")
    backend_ok = True
except Exception as exc:                       # pragma: no cover - env dependent
    print(f"SKIP  Backend import unavailable here ({type(exc).__name__}: {exc})")
    backend_ok = False

if backend_ok:
    B = mon.Backend
    prepare = B._prepare_transport            # unbound: call with a light fake

    class FakeBackend:
        _turbo = False
        _turbo_spec = False
        _turbo_model = ""
        _stop = False
        turboStatus = types.SimpleNamespace(emit=lambda *a, **k: None)

    mon.turbo_ctl = ctl                        # share the stubbed CLI/ensure
    ctl.ensure = fake_ensure

    fb = FakeBackend()
    fb._turbo = False
    use, ok, err = prepare(fb, "llama3.1:8b")
    eq("ollama + turbo off -> ollama transport", (use, ok), (False, True))

    fb = FakeBackend()
    fb._turbo = True
    use, ok, err = prepare(fb, "llama3.1:8b")
    eq("ollama + turbo on -> turbo transport", (use, ok), (True, True))

    fb = FakeBackend()
    fb._turbo = False
    use, ok, err = prepare(fb, "gguf:qwen3-30b-a3b-q4_k_m")
    eq("GGUF + turbo OFF -> turbo transport anyway", (use, ok), (True, True))
    eq("GGUF is remembered as the served model", fb._turbo_model,
       "gguf:qwen3-30b-a3b-q4_k_m")

    fb = FakeBackend()
    fb._turbo = True
    use, ok, err = prepare(fb, "gguf:x")
    eq("GGUF + turbo ON -> turbo transport", (use, ok), (True, True))

    ctl.ensure = failing_ensure
    fb = FakeBackend()
    use, ok, err = prepare(fb, "gguf:x")
    eq("GGUF that fails to load reports an error", ok, False)
    check("error text is surfaced", bool(err), err)
    ctl.ensure = fake_ensure

    # Switching back to Ollama must release a GGUF server we auto-started,
    # otherwise llama-server keeps its VRAM while Ollama loads on top of it.
    stopped = {"n": 0}
    ctl.stop = lambda *a, **k: stopped.__setitem__("n", stopped["n"] + 1)
    ctl.current_model = lambda: "gguf:qwen3-30b-a3b-q4_k_m"
    fb = FakeBackend()
    fb._turbo = False
    use, ok, err = prepare(fb, "llama3.1:8b")
    eq("ollama after an auto-started GGUF -> ollama transport", (use, ok),
       (False, True))
    eq("the auto-started GGUF server was released", stopped["n"], 1)

    stopped["n"] = 0
    fb = FakeBackend()
    fb._turbo = True                           # user deliberately wants Turbo
    prepare(fb, "llama3.1:8b")
    eq("a user-enabled Turbo is never torn down", stopped["n"], 0)

print("\n" + ("ALL TESTS PASSED" if not failures
              else "FAILURES: " + ", ".join(failures)))
sys.exit(1 if failures else 0)
