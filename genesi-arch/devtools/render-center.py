"""
render-center.py — draw Genesi Center to a PNG, with no desktop.

    python genesi-arch/devtools/render-center.py out.png

Why this exists: the app is judged on whether it looks right, and "looks right"
cannot be checked by reading QML. Rendering it offscreen and looking at the
result caught, in one pass, a telemetry grid sized for three rows while holding
four -- the eighth tile drew straight through the heading below it -- and
sparklines that stayed blank until the second tick.

It feeds one realistic payload, the same shape `genesi-center-data` prints,
because a dashboard full of em-dashes says nothing about whether the layout
works.

On a machine with no fontconfig (a bare offscreen Qt) every glyph renders as a
box and the output tells you nothing about type. Point Qt at a font directory
first if that happens:

    QT_QPA_FONTDIR=/usr/share/fonts python genesi-arch/devtools/render-center.py out.png
"""
import io
import json
import os
import sys

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from PySide6.QtCore import QUrl, QTimer, QEventLoop, QObject, Signal, Slot, Qt
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.join(HERE, "..", "packages", "genesi-center", "app")
OUT = sys.argv[1] if len(sys.argv) > 1 else "center.png"

SAMPLE = {
    "telemetry": {
        "cpu_percent": 15,
        "memory": {"used_mb": 6246, "total_mb": 16384, "percent": 38},
        "disk": {"used_gb": 118, "total_gb": 256, "percent": 42},
        "temperature_c": 47,
        "network": {"rx_bps": 3481, "tx_bps": 2764},
        "uptime": {"seconds": 225120, "text": "2d 14h 32m"},
        "processes": 189,
        "users": {"count": 1, "names": ["matheus"]},
    },
    "core": {"kernel": "6.8.7-genesi", "arch": "x86_64", "build": "2025.05.20",
             "session": "Genesi Shell", "name": "Genesi OS", "version": "0.8.3"},
    "storage": {"total_gb": 256, "used_gb": 180, "percent": 70,
                "slices": [{"label": "system", "gb": 68},
                           {"label": "data", "gb": 118},
                           {"label": "other", "gb": 70}]},
    # The same wording genesi-center-data actually prints, so the render is not
    # kinder to the layout than reality is.
    "activity": {"items": [
        {"kind": "package", "text": "upgraded genesi-caelestia-shell", "when": "2026-09-05 00:41"},
        {"kind": "package", "text": "upgraded genesi-center", "when": "2026-09-05 00:41"},
        {"kind": "package", "text": "installed genesi-audio", "when": "2026-09-04 20:58"},
        {"kind": "boot", "text": "system started", "when": "2026-09-04 19:12:14"},
    ]},
}


MONITORS = [
    {"name": "HDMI-A-1", "description": "Samsung", "width": 1920, "height": 1080,
     "refresh": 60.0, "x": 0, "y": 0, "scale": 1.0, "transform": 0, "rotation": 0,
     "focused": False, "disabled": False, "mode": "1920x1080@60.0",
     "modes": [{"width": 1920, "height": 1080, "refresh": 60.0, "id": "1920x1080@60.0"},
               {"width": 1920, "height": 1080, "refresh": 100.0, "id": "1920x1080@100.0"},
               {"width": 1600, "height": 900, "refresh": 60.0, "id": "1600x900@60.0"}]},
    {"name": "DP-1", "description": "AOC", "width": 1920, "height": 1080,
     "refresh": 143.98, "x": 1920, "y": 0, "scale": 1.0, "transform": 0, "rotation": 0,
     "focused": True, "disabled": False, "mode": "1920x1080@143.98",
     "modes": [{"width": 2560, "height": 1440, "refresh": 74.97, "id": "2560x1440@74.97"},
               {"width": 1920, "height": 1080, "refresh": 143.98, "id": "1920x1080@143.98"},
               {"width": 1920, "height": 1080, "refresh": 119.98, "id": "1920x1080@119.98"},
               {"width": 1920, "height": 1080, "refresh": 60.0, "id": "1920x1080@60.0"}]},
]


def bar_fixture():
    """
    The bar payload, read from the REAL presets and the REAL shell list.

    Not hand-written. The previous fixture was, and it went stale the moment
    the presets became looks: this harness kept drawing ten arrangements that
    no longer existed, so the page could have been reviewed against a shape it
    would never be given. Reading the shipped files is the same trick the page
    itself uses -- it draws each look from the JSON the shell reads, so the
    sketch cannot drift from what applying it does.

    This is what `genesi-bar json` prints, assembled here because that command
    needs a config file this machine does not have.
    """
    import importlib.machinery
    import importlib.util

    pkg = os.path.join(HERE, "..", "packages", "genesi-caelestia-settings")
    cli = os.path.join(pkg, "genesi-bar")
    loader = importlib.machinery.SourceFileLoader("genesi_bar", cli)
    spec = importlib.util.spec_from_loader("genesi_bar", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)          # guarded by __main__; nothing runs

    presets = []
    d = os.path.join(pkg, "bar-presets")
    for fn in sorted(f for f in os.listdir(d) if f.endswith(".json")):
        with io.open(os.path.join(d, fn), encoding="utf-8") as fh:
            p = json.load(fh)
        presets.append({
            "id": fn[:-5],
            "name": p.get("name", fn[:-5]),
            "description": p.get("description", ""),
            "entries": (p.get("bar") or {}).get("entries", []),
            "width": (p.get("bar") or {}).get("width", 0),
            "border": p.get("border", {}),
        })
    return {
        "shell": "caelestia",
        "shells": [{"id": k, "name": v["name"], "description": v["desc"]}
                   for k, v in mod.SHELLS.items()],
        "current": presets[1]["id"] if len(presets) > 1 else "",
        "presets": presets,
    }


BAR = bar_fixture()


# One realistic payload per page, the shape genesi-center-data prints. A page
# reviewed against an empty object tells you nothing: every layout bug this
# harness has caught was a layout that held the sample and not the real thing.
SECTIONS = {
    "system": {
        "name": "Genesi OS", "version": "0.8.3", "build": "rolling",
        "kernel": "6.16.4-2-cachyos", "arch": "x86_64",
        "host": "MS-7C95", "vendor": "Micro-Star International Co., Ltd.",
        "cpu": "AMD Ryzen 5 5600G with Radeon Graphics", "cores": 12,
        "gpus": ["NVIDIA Corporation GA107 [GeForce RTX 3050]",
                 "Advanced Micro Devices, Inc. [AMD/ATI] Cezanne"],
        "memory_total_mb": 16384, "packages": 1487,
        "last_update": "2026-09-04T22:11:03+0300",
        "boot": "2026-09-05 08:42:11",
        "uptime": {"seconds": 20361, "text": "5h 39m"},
        "shell": "fish", "session": "Hyprland", "session_type": "wayland",
    },
    "console": {
        "available": True, "current": "fish",
        "store": "/home/mk/.config/genesi/console.json",
        "commands": [
            {"name": "up", "command": "sudo pacman -Syu",
             "description": "update everything"},
            {"name": "gs", "command": "git status --short", "description": ""},
            {"name": "mkcd", "command": "mkdir -p \"$1\" && cd \"$1\"",
             "description": "make a directory and enter it"},
            {"name": "serve", "command": "python -m http.server 8000",
             "description": ""},
        ],
        "shells": [{"name": "bash", "wired": True},
                   {"name": "zsh", "wired": False},
                   {"name": "fish", "wired": True}],
    },
    "audio": {
        "available": True, "mixer": True,
        "sinks": [
            {"id": 49, "name": "Family 17h/19h HD Audio Controller Analog Stereo",
             "default": True, "volume": 54, "muted": False},
            {"id": 61, "name": "GA107 High Definition Audio Controller HDMI",
             "default": False, "volume": 100, "muted": True},
        ],
        "sources": [
            {"id": 50, "name": "Blue Snowball Mono", "default": True,
             "volume": 72, "muted": False},
            {"id": 52, "name": "Family 17h/19h HD Audio Controller Analog Stereo",
             "default": False, "volume": 40, "muted": False},
        ],
    },
    "appearance": {
        "available": True,
        "border": {"thickness": 10, "rounding": 25, "smoothing": 20,
                   "opacity": 82},
        "wallpaper": "/home/mk/Pictures/wallpapers/emerald-drift.png",
        "schemes": ["dynamic", "genesi", "catppuccin", "gruvbox", "nord",
                    "rosepine", "everforest", "tokyonight"],
        "shaders": ["blue-light-filter", "color-blindness", "grayscale",
                    "invert-colors", "pixelate", "vibrance"],
        "shader_on": "blue-light-filter",
    },
    "launcher": {
        "available": True, "actions_top": 25,
        "options": {"position": "centre", "width": 720,
                    "maxShown": 8, "maxWallpapers": 9, "actionPrefix": ">",
                    "enableDangerousActions": False, "showOnHover": False,
                    "vimKeybinds": True},
        "groups": [{"name": "bar", "count": 15}, {"name": "shader", "count": 16}],
    },
    "shortcuts": {
        "available": True,
        "binds": [
            {"mods": ["SUPER"], "key": "Return", "dispatcher": "exec",
             "arg": "kitty", "description": ""},
            {"mods": ["SUPER"], "key": "Q", "dispatcher": "killactive",
             "arg": "", "description": ""},
            {"mods": ["SUPER"], "key": "V", "dispatcher": "togglefloating",
             "arg": "", "description": ""},
            {"mods": ["SUPER"], "key": "F", "dispatcher": "fullscreen",
             "arg": "0", "description": ""},
            {"mods": ["SUPER", "SHIFT"], "key": "R", "dispatcher": "exec",
             "arg": "genesi-display rotate - cycle", "description": ""},
            {"mods": ["SUPER"], "key": "equal", "dispatcher": "exec",
             "arg": "genesi-display scale - up", "description": ""},
            {"mods": ["SUPER"], "key": "1", "dispatcher": "workspace",
             "arg": "1", "description": ""},
            {"mods": ["SUPER", "SHIFT"], "key": "1",
             "dispatcher": "movetoworkspace", "arg": "1", "description": ""},
            {"mods": ["SUPER"], "key": "left", "dispatcher": "movefocus",
             "arg": "l", "description": ""},
            {"mods": ["SUPER", "CTRL"], "key": "S", "dispatcher": "exec",
             "arg": "genesi-snapshots create", "description": "take a snapshot"},
        ],
        "overrides": [
            {"original": {"mods": ["SUPER"], "key": "V"},
             "bound": {"mods": ["SUPER", "SHIFT"], "key": "F",
                       "dispatcher": "togglefloating", "arg": ""}},
        ],
    },
    "ai": {
        "available": True, "kokoro": False, "api_key": False, "turbo": True,
        "voice_supported": False, "cloud_supported": False,
        "state": {"active": True, "profile": "max", "force": "auto"},
        "models": [{"name": "qwen2.5-coder-7b-instruct-q4_k_m", "size_gb": 4.4},
                   {"name": "llama-3.2-3b-instruct-q5_k_m", "size_gb": 2.3},
                   {"name": "nomic-embed-text-v1.5", "size_gb": 0.3}],
    },
    "snapshots": {
        "available": True, "configured": True,
        "status": {"configured": True},
        "snapshots": [
            {"number": 412, "description": "pacman -Syu", "date": "2026-09-05 09:14:02",
             "type": "pre"},
            {"number": 411, "description": "Genesi Center", "date": "2026-09-04 22:40:11",
             "type": "single"},
            {"number": 410, "description": "pacman -S genesi-topbar",
             "date": "2026-09-04 19:02:55", "type": "pre"},
            {"number": 409, "description": "timeline", "date": "2026-09-04 12:00:00",
             "type": "timeline"},
        ],
    },
    "input": {
        "available": True,
        "keyboards": [{"name": "at-translated-set-2-keyboard", "layout": "us",
                       "main": True},
                      {"name": "keychron-k2-pro", "layout": "us,br",
                       "main": False}],
        "mice": [{"name": "logitech-g403-hero"},
                 {"name": "synps/2-synaptics-touchpad"}],
        "has_touchpad": True,
        "options": {"kb_layout": "us,br", "repeat_rate": 32, "repeat_delay": 380,
                    "sensitivity": 0.15, "accel_profile": "flat",
                    "natural_scroll": 0, "follow_mouse": 1,
                    "tp_natural_scroll": 1, "tp_tap": 1, "tp_dwt": 1,
                    "tp_scroll_factor": 1.2},
    },
    "windows": {
        "available": True, "open_windows": 7, "workspaces": 4,
        "options": {"gaps_in": 5, "gaps_out": 20, "border_size": 2,
                    "layout": "dwindle", "rounding": 12,
                    "active_opacity": 1.0, "inactive_opacity": 0.92,
                    "blur": 1, "blur_size": 8, "blur_passes": 2,
                    "animations": 1, "vfr": 1},
    },
    "resources": {
        "per_core": [7, 92, 3, 11, 4, 2, 38, 5, 1, 0, 14, 6],
        "memory": {"used_mb": 6246, "total_mb": 16384, "percent": 38},
        "swap_total_mb": 8192, "swap_used_mb": 412,
        "load": [1.42, 0.98, 0.71],
        "processes": [
            {"pid": 2211, "name": "llama-server", "cpu": 91.4, "mem": 18.2,
             "rss_mb": 3050},
            {"pid": 1877, "name": "firefox", "cpu": 22.7, "mem": 9.8, "rss_mb": 1640},
            {"pid": 1204, "name": "Hyprland", "cpu": 8.1, "mem": 2.4, "rss_mb": 402},
            {"pid": 2440, "name": "quickshell", "cpu": 4.6, "mem": 1.9, "rss_mb": 318},
            {"pid": 3019, "name": "genesi-code", "cpu": 3.2, "mem": 6.1, "rss_mb": 1020},
            {"pid": 1990, "name": "kitty", "cpu": 1.1, "mem": 0.9, "rss_mb": 152},
            {"pid": 1102, "name": "systemd", "cpu": 0.4, "mem": 0.2, "rss_mb": 38},
            {"pid": 2601, "name": "genesi-aid", "cpu": 0.3, "mem": 0.4, "rss_mb": 66},
            {"pid": 1444, "name": "pipewire", "cpu": 0.2, "mem": 0.2, "rss_mb": 30},
            {"pid": 1450, "name": "wireplumber", "cpu": 0.2, "mem": 0.2, "rss_mb": 34},
        ],
        "mounts": [
            {"path": "/", "total_gb": 465.8, "used_gb": 212.4, "percent": 46},
            {"path": "/home", "total_gb": 465.8, "used_gb": 212.4, "percent": 46},
            {"path": "/boot", "total_gb": 1.0, "used_gb": 0.3, "percent": 31},
        ],
        "network": {"rx_bps": 918000, "tx_bps": 122000},
    },
}


class Backend(QObject):
    dataReady = Signal(str)
    displaysReady = Signal(str)
    barPresetsReady = Signal(str)
    sectionReady = Signal(str, str)

    @Slot(str)
    def ask(self, what):
        self.sectionReady.emit(what, json.dumps(SECTIONS.get(what, {})))

    @Slot(list, str)
    def act(self, argv, then):
        if then:
            self.sectionReady.emit(then, json.dumps(SECTIONS.get(then, {})))

    @Slot(str)
    def barShell(self, which):
        BAR["shell"] = which
        self.barPresetsReady.emit(json.dumps(BAR))

    @Slot()
    def displays(self):
        self.displaysReady.emit(json.dumps(MONITORS))

    @Slot(list)
    def displayCmd(self, args):
        pass

    @Slot()
    def barPresets(self):
        self.barPresetsReady.emit(json.dumps(BAR))

    @Slot(str)
    def barApply(self, preset):
        pass

    @Slot(list)
    def launch(self, argv):
        pass


app = QGuiApplication(sys.argv)
engine = QQmlApplicationEngine()
engine.addImportPath(APP)
backend = Backend()
# Resolve the artwork exactly as genesi_center.py does, so this renders the
# page a user gets rather than one without its art.
tree = ""
for cand in (os.path.expanduser("~/.config/genesi/center/tree.png"),
             os.path.join(APP, "art", "tree.png")):
    if os.path.exists(cand):
        tree = "file:///" + os.path.abspath(cand).replace("\\", "/")
        break
# A fifth argument names the session to pretend to be ("plasma" or
# "hyprland"), so the rail can be reviewed as each desktop actually sees it.
CAPS = {"hyprland": True, "caelestia": True, "plasma": False}
if len(sys.argv) > 5 and sys.argv[5] == "plasma":
    CAPS = {"hyprland": False, "caelestia": False, "plasma": True}

engine.setInitialProperties({"backend": backend, "treeArt": tree, "caps": CAPS})
print("session:", "plasma" if not CAPS["hyprland"] else "hyprland")
print("artwork:", tree or "(none -- the page draws its own glow)")

warnings = []
engine.warnings.connect(lambda ws: warnings.extend(w.toString() for w in ws))
engine.load(QUrl.fromLocalFile(os.path.join(APP, "Main.qml")))

roots = engine.rootObjects()
if not roots:
    print("LOAD FAILED")
    for w in warnings:
        print("  ", w)
    sys.exit(1)

win = roots[0]


def settle(ms):
    loop = QEventLoop()
    QTimer.singleShot(ms, loop.quit)
    loop.exec()


# A second argument is a capture time in ms, measured from the moment the data
# arrives. The default waits for everything to finish; a smaller number catches
# the page mid-assembly, which is the only way to see whether the motion is
# actually there rather than trusting that a NumberAnimation ran.
AT = int(sys.argv[2]) if len(sys.argv) > 2 else 1800

# A third argument resizes the window ("1100x720"). Layouts that were fitted by
# eye at one size come apart at another, and the smallest size the window
# allows is where that shows first.
if len(sys.argv) > 3:
    w, _, h = sys.argv[3].partition("x")
    win.setWidth(int(w))
    win.setHeight(int(h))
    settle(120)

if len(sys.argv) > 4:
    win.setProperty("section", sys.argv[4])

settle(300)
backend.dataReady.emit(json.dumps(SAMPLE))
settle(AT)
print(f"captured {AT}ms after the first reading")

img = win.grabWindow()
img.save(OUT)
print(f"saved {OUT}  {img.width()}x{img.height()}")

real = [w for w in warnings if "TypeError" in w or "is not a" in w
        or "Unable to assign" in w or "Cannot assign" in w or "ReferenceError" in w]
print(f"warnings: {len(warnings)}  (structural: {len(real)})")
for w in real[:14]:
    print("  ", w)
