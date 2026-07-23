"""Exercise the freeze-safety logic of genesi-studiod without a Linux session.

The daemon's protection rules are the difference between "background apps pause"
and "the desktop locks up with no way to turn Studio Mode off", so they are
worth testing even though the rest of the daemon needs a real /proc + cgroups.
"""
import importlib.util
import sys
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


print("\n_freeze_candidates — targets, protected apps and never_freeze excluded")


class FakeStudio:
    """Just enough of Studio to drive _freeze_candidates."""
    cfg = {"never_freeze": ["spotify", "discord"]}
    _freeze_candidates = sd.Studio._freeze_candidates


def W(pid, app_id):
    return wm.Window(pid=pid, app_id=app_id, title="", backend="test")


windows = [
    W(100, "firefox"),        # background app -> freeze
    W(200, "blender"),        # the target     -> skip
    W(300, "plasmashell"),    # compositor     -> skip
    W(400, "spotify"),        # never_freeze   -> skip
    W(500, "kdenlive"),       # background app -> freeze
    W(600, "Discord"),        # never_freeze, case-insensitive -> skip
]
orig_list = wm.list_windows
wm.list_windows = lambda: windows
try:
    got = sorted(w.pid for w in FakeStudio()._freeze_candidates({200}))
finally:
    wm.list_windows = orig_list
check("only firefox + kdenlive are frozen", got, [100, 500])


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

    def __call__(self, cmd, **kw):
        self.calls.append(cmd)
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
    check(f"parse {text!r}", hd._ionice_get(1234), want)

# Restoring must rebuild the ORIGINAL class, not a hardcoded default.
for saved, want in [
    ([2, 4], ["ionice", "-c", "2", "-n", "4", "-p", "1234"]),
    ([1, 0], ["ionice", "-c", "1", "-n", "0", "-p", "1234"]),
    ([3, None], ["ionice", "-c", "3", "-p", "1234"]),   # idle carries no prio
    (None, ["ionice", "-c", "0", "-p", "1234"]),        # unknown -> kernel default
]:
    rec = FakeRun()
    hd.subprocess.run = rec
    hd._ionice_set(1234, saved)
    check(f"restore {saved}", rec.calls[-1], want)

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
