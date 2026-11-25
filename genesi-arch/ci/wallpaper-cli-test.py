#!/usr/bin/env python3
"""
wallpaper-cli-test.py -- genesi-wallpaper, played with fake screens, a fake
caelestia and a fake Steam library.

What it holds to:
  * a picture for every screen goes through caelestia (which derives the
    colours) and leaves no per-screen entries behind;
  * a picture or video for ONE screen is that screen's entry only, and does
    not touch caelestia;
  * a GIF or video for every screen is laid over a still of itself, and the
    still is what caelestia gets;
  * Wallpaper Engine items are found in every Steam library (libraryfolders.vdf),
    video items play, scene items are refused by name;
  * the map the shell reads is written whole.
"""
import importlib.machinery
import importlib.util
import io
import json
import os
import shutil
import sys
import tempfile

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except (AttributeError, OSError):
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.normpath(os.path.join(HERE, "..", "packages", "genesi-caelestia-shell", "genesi-wallpaper"))
fails = []


def check(name, cond, detail=""):
    print(("  ok   " if cond else "  FAIL ") + name + ("" if cond else "\n         " + str(detail)))
    if not cond:
        fails.append(name)


print("== genesi-wallpaper ==")
tmp = tempfile.mkdtemp(prefix="wall-")
os.environ["XDG_STATE_HOME"] = os.path.join(tmp, "state")
os.environ["HOME"] = os.path.join(tmp, "home")
os.environ["GENESI_WALLPAPER_MONITORS"] = json.dumps([
    {"name": "DP-1", "width": 2560, "height": 1440, "focused": True},
    {"name": "HDMI-A-1", "width": 1920, "height": 1080, "focused": False}])
log = os.path.join(tmp, "caelestia.log")
fake = os.path.join(tmp, "fake_caelestia.py")
io.open(fake, "w").write("import sys\nopen(%r, 'a').write(sys.argv[-1] + '\\n')\n" % log)
os.environ["GENESI_WALLPAPER_CAELESTIA"] = json.dumps([sys.executable, fake])

loader = importlib.machinery.SourceFileLoader("genesi_wallpaper", TOOL)
spec = importlib.util.spec_from_loader("genesi_wallpaper", loader)
gw = importlib.util.module_from_spec(spec)
loader.exec_module(gw)


def calls():
    return io.open(log).read().split() if os.path.exists(log) else []


def shell_map():
    return json.load(io.open(gw.map_path(), encoding="utf-8"))["screens"]


pics = os.path.join(tmp, "pics")
os.makedirs(pics)
img = os.path.join(pics, "mountain.jpg")
open(img, "wb").write(b"\xff\xd8\xff" + b"0" * 100)
img2 = os.path.join(pics, "sea.png")
open(img2, "wb").write(b"\x89PNG" + b"0" * 100)

r = gw.set_wallpaper(img, "all")
check("a picture for every screen goes through caelestia", calls() == [img], calls())
check("...and leaves no per-screen entry behind", shell_map() == {})

r = gw.set_wallpaper(img2, "HDMI-A-1")
check("a picture for one screen is that screen's entry", shell_map() == {"HDMI-A-1": {"path": img2, "kind": "image"}},
      shell_map())
check("...and does not change caelestia's (or the colours)", calls() == [img], calls())

try:
    gw.set_wallpaper(img2, "DP-9")
    check("a screen that does not exist is refused", False)
except gw.Fail as e:
    check("a screen that does not exist is refused, naming the real ones", e.code == "no-monitor" and "DP-1" in e.text, e.text)
try:
    gw.set_wallpaper(os.path.join(pics, "notes.txt"), "all")
    check("a missing file is refused", False)
except gw.Fail as e:
    check("a missing file is refused", e.code == "not-found")
txt = os.path.join(pics, "notes.txt")
open(txt, "w").write("x")
try:
    gw.set_wallpaper(txt, "all")
    check("a file that is not a picture is refused", False)
except gw.Fail as e:
    check("a file that is not a picture is refused", e.code == "unsupported")

have_ffmpeg = bool(shutil.which("ffmpeg"))
vid = os.path.join(pics, "rain.mp4")
if have_ffmpeg:
    import subprocess
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc=size=320x180:rate=10",
                    "-t", "3", "-pix_fmt", "yuv420p", vid], check=True)
else:
    open(vid, "wb").write(b"\x00\x00\x00\x18ftypmp42" + b"0" * 100)

gw.set_wallpaper(vid, "DP-1")
m = shell_map()
check("a video for one screen is that screen's entry, beside the other's picture",
      m.get("DP-1", {}).get("kind") == "video" and m.get("HDMI-A-1", {}).get("kind") == "image", m)
check("...and still does not touch caelestia", calls() == [img], calls())

gw.set_wallpaper(vid, "all")
m = shell_map()
check("a video for every screen is one '*' entry", list(m) == ["*"] and m["*"]["kind"] == "video", m)
if have_ffmpeg:
    still = m["*"].get("still", "")
    check("...laid over a still of itself, which is what caelestia gets (and the colours)",
          still and os.path.isfile(still) and calls()[-1] == still, (still, calls()))
else:
    print("  skip the still frame: no ffmpeg here")

gw.clear("all")
check("clear empties the map", shell_map() == {})
gw.set_wallpaper(img2, "DP-1")
gw.set_wallpaper(img, "HDMI-A-1")
gw.clear("DP-1")
check("clearing one screen keeps the other", list(shell_map()) == ["HDMI-A-1"], shell_map())

# ── The launcher's >wallpaper, on the screen it is open on ──
gw.clear("all")
os.makedirs(os.path.join(gw.state_dir(), "wallpaper"), exist_ok=True)
io.open(os.path.join(gw.state_dir(), "wallpaper", "path.txt"), "w").write(img)
before = len(calls())
gw.pick(img2, "HDMI-A-1")
check("picking on the second screen changes only that screen",
      shell_map() == {"HDMI-A-1": {"path": img2, "kind": "image"}} and len(calls()) == before, (shell_map(), calls()))
gw.clear("all")
before = len(calls())
gw.pick(img2, "DP-1")
check("picking on the first screen goes through caelestia (its colours)...",
      calls()[before:] == [img2], calls()[before:])
check("...after pinning the other screen to the picture it was showing, so it does not change",
      shell_map() == {"HDMI-A-1": {"path": img, "kind": "image"}}, shell_map())
gw.pick(vid, "HDMI-A-1")
gw.pick(img, "DP-1")
check("a screen with its own wallpaper keeps it when the first screen changes",
      shell_map().get("HDMI-A-1", {}).get("kind") == "video" and "DP-1" not in shell_map(), shell_map())
os.environ["GENESI_WALLPAPER_MONITORS"] = json.dumps([{"name": "DP-1", "width": 2560, "height": 1440, "focused": True}])
gw.clear("all")
before = len(calls())
gw.pick(img2, "DP-1")
check("with one screen it is exactly caelestia's own pick", calls()[before:] == [img2] and shell_map() == {})
os.environ["GENESI_WALLPAPER_MONITORS"] = json.dumps([
    {"name": "DP-1", "width": 2560, "height": 1440, "focused": True},
    {"name": "HDMI-A-1", "width": 1920, "height": 1080, "focused": False}])
before = len(calls())
gw.pick(img, "")
check("a launcher that cannot say its screen falls back to every screen", calls()[before:] == [img])

# ── Wallpaper Engine ────────────────────────────────────────────────────────
steam = os.path.join(tmp, "home", ".local", "share", "Steam")
games = os.path.join(tmp, "GamesDisk", "SteamLibrary")
for lib in (steam, games):
    os.makedirs(os.path.join(lib, "steamapps", "workshop", "content", "431960"), exist_ok=True)
io.open(os.path.join(steam, "steamapps", "libraryfolders.vdf"), "w").write(
    '"libraryfolders"\n{\n "0"\n {\n  "path"\t\t"%s"\n }\n "1"\n {\n  "path"\t\t"%s"\n }\n}\n'
    % (steam.replace("\\", "\\\\"), games.replace("\\", "\\\\")))


def item(lib, wid, project, files=()):
    d = os.path.join(lib, "steamapps", "workshop", "content", "431960", wid)
    os.makedirs(d, exist_ok=True)
    io.open(os.path.join(d, "project.json"), "w", encoding="utf-8").write(json.dumps(project))
    for f in files:
        shutil.copy(vid if f.endswith(".mp4") else img, os.path.join(d, f))


item(steam, "1001", {"title": "Chuva na janela", "type": "video", "file": "rain.mp4", "preview": "preview.jpg"},
     ("rain.mp4", "preview.jpg"))
item(games, "2002", {"title": "Cyber city", "type": "scene", "file": "scene.json", "preview": "preview.jpg"},
     ("preview.jpg",))
item(games, "3003", {"title": "Broken", "type": "video", "file": "gone.mp4"})
os.makedirs(os.path.join(steam, "steamapps", "workshop", "content", "431960", "4004"), exist_ok=True)

items = {i["id"]: i for i in gw.we_items()}
check("items are found in every Steam library, a games disk included",
      set(items) == {"1001", "2002", "3003"}, sorted(items))
check("a video item plays; a scene item and a video with no file do not",
      items["1001"]["playable"] and not items["2002"]["playable"] and not items["3003"]["playable"])
check("titles and previews come from project.json",
      items["2002"]["title"] == "Cyber city" and items["2002"]["preview"].endswith("preview.jpg"))
r = gw.we_set("1001", "HDMI-A-1")
check("setting a video item puts its file on that screen",
      shell_map().get("HDMI-A-1", {}).get("path", "").endswith("rain.mp4"), shell_map())
try:
    gw.we_set("2002", "all")
    check("a scene item is refused", False)
except gw.Fail as e:
    check("a scene item is refused, saying why", e.code == "needs-scene-engine" and "scene" in e.text, e.text)

s = gw.status()
check("status has the screens, the map and the items",
      len(s["monitors"]) == 2 and "HDMI-A-1" in s["screens"] and len(s["we"]) == 3 and s["steam"])
check("the map is written whole: no temporary file left beside it",
      [n for n in os.listdir(gw.state_dir()) if n.startswith(".genesi-wallpapers.")] == [])

print()
if fails:
    print(f"wallpaper cli: {len(fails)} FAILURE(S)")
    sys.exit(1)
print("wallpaper cli: OK")
