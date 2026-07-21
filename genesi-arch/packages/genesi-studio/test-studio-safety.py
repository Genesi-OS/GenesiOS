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

print("\n" + ("ALL PASS" if not fails else f"{len(fails)} FAILURE(S):"))
for f in fails:
    print("  " + f)
sys.exit(1 if fails else 0)
