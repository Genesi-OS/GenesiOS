"""Exercise the freeze-safety logic of genesi-studiod without a Linux session.

The daemon's protection rules are the difference between "background apps pause"
and "the desktop locks up with no way to turn Studio Mode off", so they are
worth testing even though the rest of the daemon needs a real /proc + cgroups.
"""
import importlib.util
import sys
import signal
import types
from pathlib import Path

PKG = Path(__file__).resolve().parent

# Both modules are Linux daemons; give the Windows test host the POSIX bits they
# touch at import time. Nothing under test depends on these values.
import os  # noqa: E402

for name, val in (("getuid", lambda: 1000), ("getpriority", lambda *a: 0),
                  ("setpriority", lambda *a: None),
                  ("sched_getaffinity", lambda p: {0}),
                  ("sched_setaffinity", lambda p, c: None)):
    if not hasattr(os, name):
        setattr(os, name, val)
if not hasattr(os, "PRIO_PROCESS"):
    os.PRIO_PROCESS = 0
# SIGSTOP/SIGCONT are POSIX-only; the daemon references them for the freeze path.
if not hasattr(signal, "SIGSTOP"):
    signal.SIGSTOP = 19
if not hasattr(signal, "SIGCONT"):
    signal.SIGCONT = 18

# genesi-studiod imports genesi_studio_wm at module level; load it under its
# real name first so the daemon's import resolves.
spec = importlib.util.spec_from_file_location(
    "genesi_studio_wm", PKG / "genesi_studio_wm.py")
wm = importlib.util.module_from_spec(spec)
sys.modules["genesi_studio_wm"] = wm
spec.loader.exec_module(wm)

# genesi-studiod has no .py extension, so spec_from_file_location can't guess a
# loader — hand it a source loader explicitly.
from importlib.machinery import SourceFileLoader  # noqa: E402

spec = importlib.util.spec_from_loader(
    "studiod", SourceFileLoader("studiod", str(PKG / "genesi-studiod")))
sd = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sd)

fails = []


def check(label, got, want):
    if got != want:
        fails.append(f"{label}: got {got!r}, want {want!r}")
    print(f"  {'ok ' if got == want else 'FAIL'} {label}")


print("\n_is_protected — compositors/shells/session infra must be protected")
# _comm() reads /proc and returns "" here, so this exercises the app_id path,
# which is what the window backends actually supply.
for app in ["plasmashell", "kwin_wayland", "Hyprland", "gnome-shell", "xfwm4",
            "cinnamon", "budgie-panel", "lxqt-panel", "cosmic-comp", "niri",
            "quickshell", "waybar", "systemd", "pipewire", "xdg-desktop-portal",
            "sddm", "Xwayland", "genesi-studiod"]:
    check(f"{app} protected", sd._is_protected(999999, app), True)

print("\n_is_protected — ordinary user apps must NOT be protected")
for app in ["firefox", "code", "genesi-code", "blender", "steam_app_570",
            "obs", "kdenlive", "libreoffice", "org.mozilla.firefox"]:
    check(f"{app} freezable", sd._is_protected(999999, app), False)

print("\n_is_protected — prefix matching must not overmatch")
# "kwin" is protected, so anything starting with it is too. Verify a plausible
# user app that merely CONTAINS a protected word is still freezable.
check("my-kwin-notes freezable (contains, not prefix)",
      sd._is_protected(999999, "my-kwin-notes"), False)
check("cosmic-app-library protected (real cosmic prefix)",
      sd._is_protected(999999, "cosmic-app-library"), True)


print("\n_suspend_candidates — targets, protected apps and never_freeze excluded")


class FakeStudio:
    """Just enough of Studio to drive _suspend_candidates."""
    cfg = {"never_freeze": ["spotify", "discord"]}
    _suspend_candidates = sd.Studio._suspend_candidates


def W(pid, app_id):
    return wm.Window(pid=pid, app_id=app_id, title="", backend="test")


windows = [
    W(100, "firefox"),        # background app -> suspend
    W(200, "blender"),        # the target     -> skip
    W(300, "plasmashell"),    # compositor     -> skip
    W(400, "spotify"),        # never_freeze   -> skip
    W(500, "kdenlive"),       # background app -> suspend
    W(600, "Discord"),        # never_freeze, case-insensitive -> skip
]
orig_list = wm.list_windows
wm.list_windows = lambda: windows
try:
    got = sorted(w.pid for w in FakeStudio()._suspend_candidates({200}))
finally:
    wm.list_windows = orig_list
check("only firefox + kdenlive are suspended", got, [100, 500])


print("\nthrottle vs freeze — the default must NOT stop the process (Wayland ping)")
# A frozen Wayland client cannot answer the compositor's ping, so it is marked
# "not responding" and a wait/force-quit dialog appears. The default suspend
# method must therefore renice, never SIGSTOP.
_sig_sent = []
_nice_set = []
_orig_kill, _orig_setpri, _orig_getpri = os.kill, os.setpriority, os.getpriority
_orig_children = sd._children
_orig_ionice = sd._ionice_idle
os.kill = lambda pid, sig: _sig_sent.append((pid, sig))
os.getpriority = lambda which, pid: 0
os.setpriority = lambda which, pid, val: _nice_set.append((pid, val))
sd._children = lambda pid, depth=0: [pid + 1000]   # one child, to test the tree
sd._ionice_idle = lambda pid: None


class ThrottleStudio:
    cfg = {"suspend_method": "throttle"}
    _suspend_pid = sd.Studio._suspend_pid
    _throttle_pid = sd.Studio._throttle_pid
    _freeze_pid = sd.Studio._freeze_pid


_entry = ThrottleStudio()._suspend_pid(W(100, "firefox"))
check("throttle never sends a signal (no SIGSTOP)", _sig_sent, [])
check("throttle renices the whole tree to +19",
      sorted(_nice_set), [(100, 19), (1100, 19)])
check("the undo record is a throttle record", _entry["method"], "throttle")
check("it remembers the original nice per pid",
      set(_entry["nice"].keys()), {"100", "1100"})

# The opt-in freeze path must still SIGSTOP (for the X11 user who wants zero CPU).
_sig_sent.clear()


class FreezeStudio:
    cfg = {"suspend_method": "freeze"}
    _suspend_pid = sd.Studio._suspend_pid
    _throttle_pid = sd.Studio._throttle_pid
    _freeze_pid = sd.Studio._freeze_pid


_orig_cgdir = sd._cgroup_dir
sd._cgroup_dir = lambda pid: None                  # force the SIGSTOP path
_fentry = FreezeStudio()._suspend_pid(W(100, "firefox"))
check("opt-in freeze still SIGSTOPs the tree",
      sorted(p for p, s in _sig_sent), [100, 1100])
check("...with SIGSTOP specifically",
      all(s == signal.SIGSTOP for _p, s in _sig_sent), True)
check("freeze record uses the sigstop method", _fentry["method"], "sigstop")

os.kill, os.setpriority, os.getpriority = _orig_kill, _orig_setpri, _orig_getpri
sd._children, sd._ionice_idle, sd._cgroup_dir = \
    _orig_children, _orig_ionice, _orig_cgdir


print("\n_resolve_targets — pid and name matching")


class FakeBackend:
    def supports_focus(self):
        return True

    def focused(self):
        return W(200, "blender")


class S2:
    backend = FakeBackend()
    _resolve_targets = sd.Studio._resolve_targets


s2 = S2()
check("no args -> the focused window",
      [w.pid for w in s2._resolve_targets(None, windows)], [200])
check("by pid", [w.pid for w in s2._resolve_targets(["500"], windows)], [500])
check("by name substring, case-insensitive",
      [w.pid for w in s2._resolve_targets(["FIRE"], windows)], [100])
check("several targets at once",
      sorted(w.pid for w in s2._resolve_targets(["firefox", "kdenlive"], windows)),
      [100, 500])
check("unknown name -> nothing",
      [w.pid for w in s2._resolve_targets(["nosuchapp"], windows)], [])


class NoFocusBackend(FakeBackend):
    def supports_focus(self):
        return False


class S3:
    backend = NoFocusBackend()
    _resolve_targets = sd.Studio._resolve_targets


check("no-focus backend (GNOME/Cosmic) refuses to guess a target",
      S3()._resolve_targets(None, windows), [])

print("\nionice capture/restore — a boosted process must go back to its own class")
spec = importlib.util.spec_from_loader(
    "helperd", SourceFileLoader("helperd", str(PKG / "genesi-studio-helperd")))
hd = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hd)


class FakeRun:
    """Stands in for subprocess.run: canned stdout, and a command recorder."""

    def __init__(self, stdout=""):
        self.stdout = stdout
        self.calls = []
        self.kwargs = []

    def __call__(self, cmd, **kw):
        self.calls.append(cmd)
        self.kwargs.append(kw)
        return types.SimpleNamespace(returncode=0, stdout=self.stdout,
                                     stderr="")


for text, want in [
    ("best-effort: prio 4", [2, 4]),
    ("realtime: prio 0", [1, 0]),
    ("idle", [3, None]),
    ("none: prio 4", [0, 4]),
    ("unparseable garbage", None),
]:
    hd.subprocess.run = FakeRun(text)
    check(f"parse {text!r}", hd._ionice_get([1234]), {1234: want})

# One fork for the whole thread list, and the reply lines map back in order.
hd.subprocess.run = FakeRun("best-effort: prio 4\nidle\nnone: prio 0\n")
check("read three threads at once",
      hd._ionice_get([10, 11, 12]),
      {10: [2, 4], 11: [3, None], 12: [0, 0]})

# A thread that exits mid-read shortens the output. Pairing the remaining lines
# with the tids anyway would restore one thread's class onto another, so the
# batch is discarded and each thread is read on its own instead — losing the
# whole app's baseline over one dead thread would put every surviving thread
# back on the kernel default rather than its own class.
class FakeRunSeq:
    """subprocess.run stand-in with a different stdout per call."""

    def __init__(self, outs):
        self.outs = list(outs)
        self.calls = []
        self.kwargs = []

    def __call__(self, cmd, **kw):
        self.calls.append(cmd)
        self.kwargs.append(kw)
        return types.SimpleNamespace(
            returncode=0, stdout=self.outs.pop(0), stderr="")


rec = FakeRunSeq(["best-effort: prio 4\nidle\n",     # batch: 2 lines for 3 tids
                  "best-effort: prio 4", "idle", "none: prio 0"])
hd.subprocess.run = rec
check("a short reply falls back to one read per thread",
      hd._ionice_get([10, 11, 12]), {10: [2, 4], 11: [3, None], 12: [0, 0]})
check("...and it really did read them one at a time",
      [c[2:] for c in rec.calls], [["10", "11", "12"], ["10"], ["11"], ["12"]])
# A single unreadable thread is dropped, not guessed at.
hd.subprocess.run = FakeRun("")
check("no output for one thread → no baseline", hd._ionice_get([10]), {})

# util-linux translates that line. Without LC_ALL=C a localised "prioridade 4"
# loses the priority and restore silently puts the app on prio 0.
rec = FakeRun("best-effort: prio 4")
hd.subprocess.run = rec
hd._ionice_get([1234])
check("ionice is read under LC_ALL=C", rec.kwargs[-1].get("env", {}).get("LC_ALL"), "C")

# Restoring must rebuild the ORIGINAL class, not a hardcoded default.
for saved, want in [
    ({"1234": [2, 4]}, ["ionice", "-c", "2", "-n", "4", "-p", "1234"]),
    ({"1234": [1, 0]}, ["ionice", "-c", "1", "-n", "0", "-p", "1234"]),
    # idle carries no prio
    ({"1234": [3, None]}, ["ionice", "-c", "3", "-p", "1234"]),
    # unknown -> kernel default
    ({"1234": None}, ["ionice", "-c", "0", "-p", "1234"]),
    ({}, ["ionice", "-c", "0", "-p", "1234"]),
]:
    rec = FakeRun()
    hd.subprocess.run = rec
    hd._ionice_set_many([1234], saved)
    check(f"restore {saved}", rec.calls[-1], want)

# Threads that shared a class go back together, in one call per class.
rec = FakeRun()
hd.subprocess.run = rec
hd._ionice_set_many([10, 11, 12], {"10": [2, 4], "11": [2, 4], "12": [3, None]})
check("threads are regrouped by class",
      sorted(tuple(c) for c in rec.calls),
      sorted([("ionice", "-c", "2", "-n", "4", "-p", "10", "11"),
              ("ionice", "-c", "3", "-p", "12")]))

print("\ndesktop entries — icons and human names for the app picker")
import tempfile  # noqa: E402

tmp = tempfile.mkdtemp()


def desktop(fn, body):
    with open(os.path.join(tmp, fn), "w", encoding="utf-8") as fh:
        fh.write(body)


# A normal app whose window class differs from its file name and its binary.
desktop("firefox.desktop", """[Desktop Entry]
Type=Application
Name=Firefox
Name[pt_BR]=Raposa de Fogo
Icon=firefox-logo
Exec=/usr/lib/firefox/firefox %u
StartupWMClass=Navigator

[Desktop Action new-window]
Name=Nova janela
Icon=wrong-action-icon
""")
# Reverse-DNS id, the Wayland app_id style.
desktop("org.kde.konsole.desktop", """[Desktop Entry]
Type=Application
Name=Konsole
Icon=utilities-terminal
Exec=konsole
""")
# A background agent: NoDisplay means "not a user-facing app" and it must be
# kept out of the index entirely, or it shows up in the picker as if it were one.
desktop("kded6.desktop", """[Desktop Entry]
Type=Application
Name=KDE Daemon
Icon=kde
Exec=kded6
NoDisplay=true
""")

wm._DESKTOP_DIRS = (tmp,)
wm._desktop_index = None          # force a rebuild against the temp dir

check("StartupWMClass wins for the X11 window class",
      wm.desktop_lookup("Navigator"), ("firefox-logo", "Firefox"))
check("reverse-DNS app_id resolves",
      wm.desktop_lookup("org.kde.konsole"), ("utilities-terminal", "Konsole"))
check("bare binary name resolves",
      wm.desktop_lookup("konsole"), ("utilities-terminal", "Konsole"))
check("Exec basename resolves past the %u code",
      wm.desktop_lookup("firefox"), ("firefox-logo", "Firefox"))
check("plain Name wins over localised Name[pt_BR]",
      wm.desktop_lookup("Navigator")[1], "Firefox")
check("action-group Icon does not leak into the entry",
      wm.desktop_lookup("Navigator")[0], "firefox-logo")
check("NoDisplay agent is not indexed",
      wm.desktop_lookup("kded6"), ("application-x-executable", "kded6"))
check("unknown app still yields a renderable icon + label",
      wm.desktop_lookup("totally-unknown-app"),
      ("application-x-executable", "totally-unknown-app"))

# Qt builds WM_CLASS from the binary name, so Genesi's Python/QML apps present
# as "Genesi_ai_monitor" while their desktop entry is genesi-ai-monitor.
desktop("genesi-ai-monitor.desktop", """[Desktop Entry]
Type=Application
Name=Genesi AI Mode Monitor
Icon=genesi-ai-monitor
Exec=/usr/local/bin/genesi-ai-monitor
""")
# A launcher that merely opens a terminal must NOT claim the terminal's name.
desktop("genesi-dev-cuda.desktop", """[Desktop Entry]
Type=Application
Name=Genesi DEV: NVIDIA + CUDA (test)
Icon=genesi-dev
Exec=konsole -e /usr/local/bin/genesi-dev-cuda-setup
""")
wm._desktop_index = None

check("underscored Qt WM_CLASS matches its hyphenated desktop entry",
      wm.desktop_lookup("Genesi_ai_monitor"),
      ("genesi-ai-monitor", "Genesi AI Mode Monitor"))
check("a terminal-launcher entry does not hijack the terminal's identity",
      wm.desktop_lookup("konsole"), ("utilities-terminal", "Konsole"))

# WM_CLASS and desktop-file names often differ only in punctuation: the editor
# presents as "GenesiCode" while its entry is genesi-code. Without a
# separator-insensitive pass every such app fell back to a generic icon.
desktop("genesi-code.desktop", """[Desktop Entry]
Type=Application
Name=Genesi Code
Icon=genesi-code
Exec=/usr/bin/genesi-code
""")
wm._desktop_index = None

check("CamelCase WM_CLASS finds its hyphenated desktop entry",
      wm.desktop_lookup("GenesiCode"), ("genesi-code", "Genesi Code"))
check("the exact entry still wins for the hyphenated form",
      wm.desktop_lookup("genesi-code"), ("genesi-code", "Genesi Code"))
# Precision must outrank the loose pass: Firefox's StartupWMClass is an exact
# hit and must not be displaced by an alphanumeric collision.
check("an exact match is never displaced by the loose pass",
      wm.desktop_lookup("Navigator"), ("firefox-logo", "Firefox"))
check("still no icon invented for a genuinely unknown app",
      wm.desktop_lookup("nothing-like-this-exists")[0],
      "application-x-executable")

# The editor declares StartupWMClass=dev.genesi.GenesiCode, so the full dotted
# class must be tried — keeping only the last component threw away the exact
# key the entry is indexed under.
desktop("genesi-code-full.desktop", """[Desktop Entry]
Type=Application
Name=Genesi Code
Icon=genesi-code
Exec=/usr/bin/genesi-code %U
StartupWMClass=dev.genesi.GenesiCode
""")
wm._desktop_index = None
check("a dotted StartupWMClass matches on the full class",
      wm.desktop_lookup("dev.genesi.GenesiCode"), ("genesi-code", "Genesi Code"))
check("...and when wmctrl prefixes the instance too",
      wm.desktop_lookup("genesicode.dev.genesi.GenesiCode"),
      ("genesi-code", "Genesi Code"))
check("an unmatched dotted class displays only its last component",
      wm.desktop_lookup("com.example.NoSuchApp")[1], "NoSuchApp")

# The veto set is what keeps background agents out of the picker on the
# desktops with no window list (COSMIC, GNOME Wayland). They DO hold a
# connection to the compositor, so the display-socket test alone would let
# them through — exactly what made the first cut of the list show kded6 and
# kaccess instead of the user's apps.
agents = wm._desktop_index_get(want_hidden=True)
check("NoDisplay agent is vetoed by desktop-file name", "kded6" in agents, True)
check("NoDisplay agent is vetoed by Exec basename too", "kded6" in agents, True)
check("a real app is never vetoed", "firefox" in agents, False)
check("a real app is never vetoed (by class)", "navigator" in agents, False)

print("\nX11 window parsing — wmctrl -lxp is the primary desktop's window list")
# Columns are id, desktop, PID, WM_CLASS, host, title — PID comes BEFORE
# WM_CLASS. An earlier fixture had them swapped, which encoded the same
# misreading as the parser and let a total failure (int() raising on every
# line, so the backend returned nothing and the session fell to procfs) pass
# the tests. These first two rows are verbatim real output from a Genesi
# session; treat them as the contract.
_WMCTRL = """\
0x01600012 -1 926  plasmashell.plasmashell  genesi-x8664 Área de trabalho @ QRect(0,0 1920x955)
0x04200008  0 4841 konsole.konsole          genesi-x8664 ~ : fish — Konsole
0x05000003  0 5678 code.Code                genesi-x8664 index.html - LiveSupport
0x05200004  0 9012 N/A                      genesi-x8664
0x05400005  0 3456 genesi_ai_monitor.Genesi_ai_monitor genesi-x8664 Genesi AI Mode Monitor
0x05600006  0 6334 Navigator.firefox        genesi-x8664 Nova aba - Firefox
garbage line that should be ignored
"""
_x11 = wm.X11Backend()
_orig_run, _orig_alive = wm._run, wm._alive
wm._run = lambda cmd, timeout=4: (
    _WMCTRL if cmd[:2] == ["wmctrl", "-lxp"]
    else "_NET_ACTIVE_WINDOW(WINDOW): window id # 0x05000003")
wm._alive = lambda pid: True
_wins = _x11.windows()
wm._run, wm._alive = _orig_run, _orig_alive

check("every real window is parsed", len(_wins), 6)
# The regression that mattered: with pid/wm_class swapped this was 0.
check("the parser does not return an empty list", len(_wins) > 0, True)
check("PID is read from the pid column, not the class column",
      sorted(w.pid for w in _wins), [926, 3456, 4841, 5678, 6334, 9012])
check("a window with an EMPTY title is NOT dropped",
      9012 in [w.pid for w in _wins], True)
check("app_id keeps the FULL class, so dotted StartupWMClass can match",
      [w.app_id for w in _wins if w.pid == 5678], ["code.Code"])
check("an unmatched class still DISPLAYS as its last component",
      [w.name for w in _wins if w.pid == 5678], ["Code"])
check("a Qt app's underscored class resolves to its real name",
      [w.name for w in _wins if w.pid == 3456], ["Genesi AI Mode Monitor"])
check("...and to its real icon",
      [w.icon for w in _wins if w.pid == 3456], ["genesi-ai-monitor"])
check("the active window is flagged focused",
      [w.pid for w in _wins if w.focused], [5678])
check("titles with spaces survive intact",
      [w.title for w in _wins if w.pid == 5678], ["index.html - LiveSupport"])
check("a title with non-ASCII survives",
      [w.title for w in _wins if w.pid == 926],
      ["Área de trabalho @ QRect(0,0 1920x955)"])

# _NET_WM_PID is a convention, not a guarantee. A window without it comes back
# from wmctrl with pid 0; dropping it would hide a real app, so the class is
# matched against the user's processes instead.
_NOPID = "0x07000009  0 0 GenesiCode.GenesiCode genesi-x8664 main.rs - genesi-code\n"
_orig_run, _orig_alive = wm._run, wm._alive
_orig_lookup = wm._pid_for_wm_class
wm._run = lambda cmd, timeout=4: (
    _NOPID if cmd[:2] == ["wmctrl", "-lxp"] else "")
wm._alive = lambda pid: True
wm._pid_for_wm_class = lambda cls: 4242 if "genesicode" in cls.lower() else 0
_recovered = wm.X11Backend().windows()
check("a window with no _NET_WM_PID is recovered, not dropped",
      [w.pid for w in _recovered], [4242])

# ...but if the process genuinely cannot be found there is nothing to act on.
wm._pid_for_wm_class = lambda cls: 0
check("an unresolvable window is dropped (every lever is process-level)",
      wm.X11Backend().windows(), [])
wm._run, wm._alive = _orig_run, _orig_alive
wm._pid_for_wm_class = _orig_lookup


print("\nbackend demotion — an empty window list must NOT strand the session")
# The daemon starts at login, BEFORE any application window exists. An earlier
# version treated three consecutive empty polls as proof the backend was broken
# and demoted the session to procfs permanently, so every session ran on procfs
# (daemons instead of windows, no focus tracking) until the daemon was manually
# restarted. Empty is a legitimate answer; the preferred backend must survive it.


class FlakyBackend(wm._Backend):
    name = "x11"                      # pretend to be the real X11 backend

    def __init__(self):
        self.result = []              # starts empty, like a fresh login

    def available(self):
        return True

    def windows(self):
        return self.result


_flaky = FlakyBackend()
_saved_cached, _saved_last = wm._cached, wm._last_backend
_saved_proc = wm.ProcBackend.windows
wm._cached = _flaky
wm._last_backend = None
wm._env_ok = True                     # skip the harvest path
wm.ProcBackend.windows = lambda self: []   # nothing in procfs either

for _ in range(6):                    # twice the old three-strike limit
    wm.list_windows()
check("an empty backend is still the active one after 6 empty polls",
      wm.active_backend().name, "x11")

# Windows finally appear — the session must pick them up, not stay on procfs.
_flaky.result = [wm.Window(pid=42, app_id="code", backend="x11")]
check("windows are returned once they exist",
      [w.pid for w in wm.list_windows()], [42])
check("and the backend is still x11", wm.active_backend().name, "x11")

# The case the guard was really for: the backend is broken (always empty) but
# procfs can see apps. Fall back for that call, without making it permanent.
_flaky.result = []
wm.ProcBackend.windows = lambda self: [
    wm.Window(pid=7, app_id="firefox", backend="procfs")]
check("procfs answers when the real backend has nothing",
      [w.pid for w in wm.list_windows()], [7])
check("the fallback is reported honestly", wm.active_backend().name, "procfs")
_flaky.result = [wm.Window(pid=42, app_id="code", backend="x11")]
check("and the real backend is retried on the very next poll",
      [w.pid for w in wm.list_windows()], [42])
check("recovering back to x11", wm.active_backend().name, "x11")

wm.ProcBackend.windows = _saved_proc
wm._cached, wm._last_backend = _saved_cached, _saved_last


print("\nperformance-core pinning — hybrid CPUs only, never a uniform CPU or VM")
# Pinning the focused app to a core SUBSET only helps on a real Intel P/E chip.
# On a uniform CPU or in a VM it just removes cores and makes the app slower —
# the "feels laggier with Studio on" regression. hd is loaded above.


import re as _re  # noqa: E402


def _fake_cpus(freqs):
    """Patch hd so _performance_cpu_ids sees a given per-cpu max-freq map."""
    hd.os.listdir = lambda p: [f"cpu{i}" for i in freqs]
    hd._read = lambda path: str(
        freqs[int(_re.search(r"/cpu(\d+)/", path).group(1))])


_hd_listdir, _hd_read = hd.os.listdir, hd._read
# Ryzen 5 5600: 6 uniform cores, all 4.4GHz → no pinning.
_fake_cpus({i: 4400000 for i in range(6)})
check("uniform 6-core CPU → no pinning", hd._performance_cpu_ids(), [])
# VM: identical made-up frequencies → no pinning.
_fake_cpus({i: 2000000 for i in range(4)})
check("VM uniform cores → no pinning", hd._performance_cpu_ids(), [])
# Intel 12th-gen-ish: 8 P-threads at 4.9GHz, 8 E-cores at 3.9GHz → pin to P.
hybrid = {i: 4900000 for i in range(8)}
hybrid.update({i: 3900000 for i in range(8, 16)})
_fake_cpus(hybrid)
check("hybrid P/E CPU → pins to the P-cores", hd._performance_cpu_ids(),
      list(range(8)))
# Too few cores to bother splitting.
_fake_cpus({0: 4000000, 1: 3000000})
check("2-core machine → no pinning", hd._performance_cpu_ids(), [])
hd.os.listdir, hd._read = _hd_listdir, _hd_read


print("\ncgroup levers — a share is meaningless in a cgroup shared with the session")
# cpu.weight/io.weight are shares against SIBLINGS. An app launched straight
# from the compositor lands in the shared session-N.scope next to Hyprland and
# everything else, where raising the weight raises the group against itself —
# and memory.swap.max/memory.low would rewrite the whole session's memory
# policy as a side effect. So the cgroup levers must stand down there.
import builtins as _builtins  # noqa: E402

_hd_open = _builtins.open


def _fake_cgroup(members, parents):
    """cgroup.procs holds `members`; `parents` maps pid -> ppid."""
    import io as _io

    def fake_open(path, *a, **kw):
        if path.endswith("cgroup.procs"):
            return _io.StringIO("\n".join(str(m) for m in members) + "\n")
        m = _re.search(r"/proc/(\d+)/stat$", str(path))
        if m:
            pid = int(m.group(1))
            if pid not in parents:
                raise OSError("no such pid")
            # pid (comm) state ppid …
            return _io.StringIO(f"{pid} (app) S {parents[pid]} 0 0")
        return _hd_open(path, *a, **kw)
    hd.open = fake_open


# The app alone in its own scope: the levers apply.
_fake_cgroup([500], {500: 1})
check("app alone in its scope → exclusive",
      hd._cgroup_is_exclusive("/sys/fs/cgroup/…/app-firefox.scope", 500), True)
# The app plus its own children (a game and its helper processes).
_fake_cgroup([500, 501, 502], {500: 1, 501: 500, 502: 501})
check("app plus its own children → exclusive",
      hd._cgroup_is_exclusive("/sys/fs/cgroup/…/app-firefox.scope", 500), True)
# A helper reparented to init when the launcher exited — Firefox's crashhelper
# lives in Firefox's own scope with ppid 1. Rejecting the scope over it would
# disable the levers for every app that outlives its launcher.
_fake_cgroup([500, 504], {500: 1, 504: 1})
check("orphaned helper in the app's own scope → still exclusive",
      hd._cgroup_is_exclusive("/sys/fs/cgroup/…/app-firefox.scope", 500), True)
# A launcher that dropped a second, unrelated app into the same scope.
_fake_cgroup([500, 700, 701], {500: 1, 700: 42, 701: 700})
check("an unrelated process tree in the scope → NOT exclusive",
      hd._cgroup_is_exclusive("/sys/fs/cgroup/…/app-firefox.scope", 500), False)
# The session containers are shared by construction, however empty they look.
_fake_cgroup([500], {500: 1})
for base in ("session-2.scope", "user@1000.service", "app.slice",
             "user-1000.slice", "init.scope"):
    check(f"{base} → NOT exclusive",
          hd._cgroup_is_exclusive("/sys/fs/cgroup/…/" + base, 500), False)
# An unreadable cgroup is not a licence to write to it.
hd.open = lambda *a, **kw: (_ for _ in ()).throw(OSError("nope"))
check("unreadable cgroup.procs → NOT exclusive",
      hd._cgroup_is_exclusive("/sys/fs/cgroup/…/app-firefox.scope", 500), False)
del hd.open


print("\nAI Mode ownership — per lever, never all-or-nothing")
# The first cut stood down from EVERY global knob whenever AI Mode was on, so a
# warm ollama in the background silently disabled the GPU lever — the one lever
# that matters for a game, and one genesi-aid may not even be holding.
import json as _json  # noqa: E402
import tempfile as _tf  # noqa: E402

_aid_state = hd.AID_STATE
_aid_file = os.path.join(_tf.mkdtemp(), "state.json")
hd.AID_STATE = _aid_file


def _aid(payload):
    with open(_aid_file, "w", encoding="utf-8") as fh:
        _json.dump(payload, fh)


_aid({"ai_mode_active": False, "applied": ["CPU governor: performance"]})
check("AI Mode off → nothing is held", hd._ai_mode_held_levers(), set())
_aid({"ai_mode_active": True,
      "applied": ["CPU governor: performance", "swappiness: 10",
                  "THP: madvise", "EPP: performance",
                  "NVIDIA max power+clocks (1 GPU)"]})
check("CPU knobs held, GPU lever left free",
      hd._ai_mode_held_levers(), {"governor", "epp", "swappiness"})
_aid({"ai_mode_active": True, "applied": ["AMD GPU high (1)"]})
check("AMD DPM held → Studio skips only the GPU",
      hd._ai_mode_held_levers(), {"gpu"})
_aid({"ai_mode_active": True, "applied": []})
check("AI Mode on holding nothing → Studio takes every lever",
      hd._ai_mode_held_levers(), set())
# An older genesi-aid publishes no lever list at all: assume it holds
# everything rather than racing it for a knob it may be about to take.
_aid({"ai_mode_active": True})
check("no lever list published → assume everything is held",
      hd._ai_mode_held_levers(), {"governor", "epp", "swappiness", "gpu"})
os.unlink(_aid_file)
check("no state file at all → nothing is held", hd._ai_mode_held_levers(), set())
hd.AID_STATE = _aid_state


print("\nsession env harvest — the daemon has no DISPLAY of its own")
# genesi-studiod is a systemd --user service, so DISPLAY/WAYLAND_DISPLAY/etc are
# NOT in its environment and every backend's available() check would fail,
# dropping the whole session to procfs. ensure_session_env() must borrow them
# from a session-owned GUI process. This mocks /proc to prove the priority:
# a real compositor donor beats a random fallback process.
import types as _types  # noqa: E402

_procs = {
    "1":    ("systemd",     {}),                      # no display var
    "1500": ("some-helper", {"DISPLAY": ":9",         # fallback candidate
                             "WAYLAND_DISPLAY": ""}),
    "1600": ("plasmashell", {"DISPLAY": ":0",         # the real donor
                             "WAYLAND_DISPLAY": "wayland-0",
                             "XAUTHORITY": "/home/a/.Xauthority",
                             "XDG_SESSION_TYPE": "x11"}),
}
_orig = {k: getattr(wm.os, k, None)
         for k in ("listdir", "stat", "getuid")}
_orig_comm = wm._comm
_orig_environ = wm._read_environ

wm.os.listdir = lambda p: list(_procs) if p == "/proc" else _orig["listdir"](p)
wm.os.stat = lambda p: _types.SimpleNamespace(st_uid=1000)
wm.os.getuid = lambda: 1000
wm._comm = lambda pid: _procs.get(str(pid), ("", {}))[0]
wm._read_environ = lambda pid: _procs.get(str(pid), ("", {}))[1]

# Pretend we start with no display env at all, like the real service.
for _k in ("DISPLAY", "WAYLAND_DISPLAY", "XAUTHORITY"):
    os.environ.pop(_k, None)
wm._env_ok = False
wm._env_last = 0.0

changed = wm.ensure_session_env()
check("harvest reports it changed the environment", changed, True)
check("DISPLAY taken from the plasmashell donor, not the helper",
      os.environ.get("DISPLAY"), ":0")
check("WAYLAND_DISPLAY harvested", os.environ.get("WAYLAND_DISPLAY"), "wayland-0")
check("XAUTHORITY harvested (needed for wmctrl/xprop on X11)",
      os.environ.get("XAUTHORITY"), "/home/a/.Xauthority")
check("second call is a no-op once satisfied", wm.ensure_session_env(), False)

# restore the patched os bits so nothing below is affected
wm.os.listdir, wm.os.stat, wm.os.getuid = (
    _orig["listdir"], _orig["stat"], _orig["getuid"])
wm._comm, wm._read_environ = _orig_comm, _orig_environ

print("\n" + ("ALL PASS" if not fails else f"{len(fails)} FAILURE(S):"))
for f in fails:
    print("  " + f)
sys.exit(1 if fails else 0)
