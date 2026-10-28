#!/usr/bin/env python3
"""
Genesi Migrate reads other distros correctly, and its screen writes the plan
the user picked.

The scanner's whole job is reading systems that are NOT Genesi, which no CI
runner is. So each case builds a fake root -- os-release, .desktop files, a
home with folders in it -- and a fake `runner` that answers dpkg/rpm/pacman/
snap/flatpak/lsblk/nmcli the way those tools really print. Each assertion is a
mistake a first version makes:

  Ubuntu   dpkg -S "pkg:arch, other: path" lines; libreoffice's five launchers
           are ONE app; Nautilus is the old desktop, not an app; synaptic has
           no place on Genesi; NoDisplay/OnlyShowIn launchers are not apps;
           snap's runtime (core22, gtk-common-themes) is not something the
           user picked; an unknown snap is a Flathub search, not a guess; an
           nmcli name with a colon in it; an encrypted root BLOCKS; a USB disk
           is a place for files; .cache is never counted; Steam is off.
  Fedora   rpm -qf prints one line per file IN ORDER, a sentence for an
           unowned one -- which must not shift every owner after it; a
           separate /home partition is the keep-home strategy.
  Arch     pacman -Qo; an Arch-family name is already an Arch name ("same").

Then, if PySide6 is installed, the real Main.qml loads offscreen on the demo
manifest and builds the plan: deselecting every app must reach the saved
JSON, and the save must be owner-only (Wi-Fi names are in it). Any Qt warning
while that happens fails the test.
"""
import json
import os
import stat
import sys
import tempfile
import time

APP = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "genesi-migrate", "app")
sys.path.insert(0, os.path.abspath(APP))

import scanner  # noqa: E402

FAILS = []


def check(cond, what):
    if not cond:
        FAILS.append(what)
        print("  FAIL", what)


def write(root, rel, text, size=None):
    path = os.path.join(root, rel.lstrip("/"))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
        if size:
            f.write("x" * size)
    return path


def desktop(root, name, display, extra=""):
    write(root, "/usr/share/applications/%s.desktop" % name,
          "[Desktop Entry]\nType=Application\nName=%s\nExec=%s\nIcon=%s\n%s\n"
          "[Desktop Action new]\nName=Should not override\n" % (display, name, name, extra))


def make_home(home):
    write(home, ".config/user-dirs.dirs", 'XDG_DOCUMENTS_DIR="$HOME/Documentos"\nXDG_PICTURES_DIR="$HOME/Imagens"\n')
    write(home, "Documentos/tese.odt", "", size=1000)
    write(home, "Imagens/praia.jpg", "", size=3000)
    write(home, "Projetos/app/main.py", "", size=500)
    write(home, ".mozilla/firefox/profile/places.sqlite", "", size=200)
    write(home, ".ssh/id_ed25519", "", size=10)
    write(home, ".config/someapp/settings.ini", "", size=40)
    write(home, ".cache/huge.bin", "", size=50000)
    write(home, ".local/share/Steam/steamapps/game.bin", "", size=7000)


def make_runner(table):
    def run(cmd, timeout=30):
        key = cmd[0]
        if key == "du":
            return 127, ""   # exercise the Python walk; du itself isn't the thing under test
        handler = table.get(key)
        if handler is None:
            return 127, ""
        return handler(cmd)
    return run


def which_from(tools):
    return lambda t: "/usr/bin/" + t if t in tools else None


def by_id(items, key):
    return {i["id"]: i for i in items}.get(key)


# ── Ubuntu ──────────────────────────────────────────────────────────────
def ubuntu_case():
    print("ubuntu")
    with tempfile.TemporaryDirectory() as tmp:
        root, home = os.path.join(tmp, "root"), os.path.join(tmp, "home")
        write(root, "/etc/os-release", 'NAME="Ubuntu"\nID=ubuntu\nID_LIKE=debian\nPRETTY_NAME="Ubuntu 24.04 LTS"\nVERSION_ID="24.04"\n')
        write(root, "/etc/default/keyboard", 'XKBLAYOUT="br"\nXKBVARIANT="abnt2"\n')
        write(root, "/etc/timezone", "America/Sao_Paulo\n")
        write(root, "/etc/passwd", "ana:x:1000:1000:Ana Souza,,,:/home/ana:/bin/zsh\n")
        write(root, "/proc/self/mounts", "/dev/mapper/root / ext4 rw 0 0\n")
        write(root, "/usr/bin/git", "")
        write(root, "/usr/share/icons/hicolor/128x128/apps/google-chrome.png", "png")
        desktop(root, "google-chrome", "Google Chrome")
        for part in ("writer", "calc", "impress", "draw", "startcenter"):
            desktop(root, "libreoffice-" + part, "LibreOffice " + part.title())
        desktop(root, "org.gnome.Nautilus", "Files")
        desktop(root, "synaptic", "Synaptic")
        desktop(root, "mytool", "My Tool")
        desktop(root, "hidden", "Hidden", "NoDisplay=true")
        desktop(root, "kde-only", "KDE thing", "OnlyShowIn=KDE;")
        make_home(home)

        owners = {
            "google-chrome.desktop": "google-chrome-stable",
            "org.gnome.Nautilus.desktop": "nautilus",
            "synaptic.desktop": "synaptic",
            "mytool.desktop": "mytool",
        }
        for part in ("writer", "calc", "impress", "draw", "startcenter"):
            owners["libreoffice-%s.desktop" % part] = "libreoffice-" + part

        def dpkg(cmd):
            lines = []
            for path in cmd[2:]:
                name = os.path.basename(path)
                if name in owners:
                    # the arch-qualified, multi-owner form dpkg really prints
                    extra = ", libreoffice-common" if name.startswith("libreoffice") else ""
                    lines.append("%s:amd64%s: %s" % (owners[name], extra, path))
            lines.insert(0, "diversion by foo from: /usr/share/applications/x.desktop")
            return 0, "\n".join(lines) + "\n"

        lsblk = {"blockdevices": [
            {"name": "nvme0n1", "path": "/dev/nvme0n1", "type": "disk", "rm": False, "tran": "nvme", "size": 512 * 10**9,
             "children": [
                 {"name": "nvme0n1p1", "path": "/dev/nvme0n1p1", "type": "part", "fstype": "vfat", "mountpoint": "/boot/efi"},
                 {"name": "nvme0n1p2", "path": "/dev/nvme0n1p2", "type": "part", "fstype": "crypto_LUKS",
                  "children": [{"name": "root", "path": "/dev/mapper/root", "type": "crypt", "fstype": "ext4", "mountpoint": "/"}]}]},
            {"name": "sda", "path": "/dev/sda", "type": "disk", "rm": True, "tran": "usb", "model": "Expansion HDD", "size": 2 * 10**12,
             "children": [{"name": "sda1", "path": "/dev/sda1", "type": "part", "fstype": "exfat", "label": "BACKUP",
                           "mountpoint": "/media/ana/BACKUP", "size": 2 * 10**12, "fsavail": 10**12}]},
        ]}
        runner = make_runner({
            "dpkg": dpkg,
            "snap": lambda c: (0, "Name    Version  Rev  Tracking  Publisher  Notes\n"
                                  "core22  2024     1    latest    canonical  base\n"
                                  "gtk-common-themes 0.1 1 latest canonical -\n"
                                  "firefox 130 1 latest mozilla -\n"
                                  "whatsdesk 0.3 1 latest someone -\n"),
            "flatpak": lambda c: (0, "org.telegram.desktop\tTelegram\tsystem\ncom.spotify.Client\tSpotify\tuser\n"),
            "lsblk": lambda c: (0, json.dumps(lsblk)),
            "nmcli": lambda c: (0, "Casa\\:5G:802-11-wireless\nWired connection 1:802-3-ethernet\nTrabalho:802-11-wireless\n"),
            "systemd-detect-virt": lambda c: (1, ""),
        })
        s = scanner.Scanner(root=root, home=home, runner=runner,
                            which=which_from({"dpkg", "snap", "flatpak"}),
                            env={"HOME": home, "USER": "ana", "LANG": "pt_BR.UTF-8",
                                 "XDG_CURRENT_DESKTOP": "ubuntu:GNOME"})
        m = s.scan()
        apps = {a["id"]: a for a in m["apps"]}

        check(m["os"]["family"] == "debian", "ubuntu is the debian family")
        chrome = apps.get("native:google-chrome-stable")
        check(chrome and chrome["kind"] == "aur" and chrome["target"] == "google-chrome",
              "chrome maps to the AUR package")
        check(chrome and chrome["icon"].endswith("google-chrome.png"), "chrome's hicolor icon is found")
        lo = [a for a in m["apps"] if a["target"] == "libreoffice-fresh"]
        check(len(lo) == 1, "five libreoffice launchers are one app (got %d)" % len(lo))
        check(not any(a["package"] == "nautilus" for a in m["apps"]), "nautilus is the old desktop, not an app")
        check(m["desktopComponents"] >= 1, "the old desktop's apps are counted")
        check("native:synaptic" not in apps, "synaptic has no place on Genesi")
        check(apps.get("native:mytool", {}).get("confidence") == "likely", "an unknown package is a guess, flagged")
        names = {a["name"] for a in m["apps"]}
        check("Hidden" not in names and "KDE thing" not in names, "NoDisplay/OnlyShowIn launchers are not apps")
        check("Should not override" not in names, "a [Desktop Action] Name does not replace the app's")
        check("snap:core22" not in apps and "snap:gtk-common-themes" not in apps, "snap runtime is not an app")
        check(apps.get("snap:firefox", {}).get("kind") == "pacman", "the firefox snap becomes the firefox package")
        check(apps.get("snap:whatsdesk", {}).get("kind") == "flatpak-search", "an unknown snap is a Flathub search")
        check(apps.get("flatpak:com.spotify.Client", {}).get("user") is True, "a user-installation flatpak is marked")
        check("cli:git" in apps, "git is carried as a tool")

        st = m["settings"]
        check(st["wifi"] == ["Casa:5G", "Trabalho"], "nmcli names with colons, wifi only (got %r)" % st["wifi"])
        check(st["keyboard"] == {"layout": "br", "variant": "abnt2"}, "keyboard from /etc/default/keyboard")
        check(st["timezone"] == "America/Sao_Paulo", "timezone")
        check(st["user"]["fullName"] == "Ana Souza" and st["user"]["shell"] == "zsh", "user from passwd")
        check(st["genesiDesktop"] == "GNOME-Desktop", "ubuntu:GNOME picks GNOME")

        files = m["files"]
        check(by_id(files, "documents") and by_id(files, "documents")["bytes"] == 1000, "documents counted from user-dirs")
        check(by_id(files, "other") and "Projetos" in by_id(files, "other")["names"], "loose folders are 'other'")
        cfg = by_id(files, "appconfig")
        check(cfg and cfg["bytes"] < 50000, ".cache is never counted")
        check(by_id(files, "steam") and by_id(files, "steam")["selected"] is False, "steam games are off by default")
        check(by_id(files, "keys") is not None, "ssh keys are offered")

        mach = m["machine"]
        check(mach["luks"] is True, "encrypted root detected")
        check("luks" in m["plan"]["blockers"], "an encrypted root blocks the migration")
        ext = [x for x in m["plan"]["strategies"] if x["id"] == "external"]
        check(len(ext) == 1 and ext[0]["device"] == "/dev/sda1" and ext[0]["ok"], "the USB disk is a place for files")
        check(not any(x["id"] == "keep-home" for x in m["plan"]["strategies"]), "no separate /home, no keep-home")
        disks = {d["device"]: d for d in mach["disks"]}
        check(set(disks) == {"/dev/nvme0n1", "/dev/sda"}, "every disk is an install candidate (got %r)" % sorted(disks))
        check(disks.get("/dev/nvme0n1", {}).get("system") is True, "the disk holding / is the system disk")
        check(disks.get("/dev/sda", {}).get("removable") is True, "the USB disk is marked external")
        check(not disks.get("/dev/sda", {}).get("system"), "the USB disk is not the system disk")
        check(any(p["fstype"] == "exfat" for p in disks.get("/dev/sda", {}).get("partitions", [])),
              "a disk lists what is on it, for the screen to warn")


# ── Fedora ──────────────────────────────────────────────────────────────
def fedora_case():
    print("fedora")
    with tempfile.TemporaryDirectory() as tmp:
        root, home = os.path.join(tmp, "root"), os.path.join(tmp, "home")
        write(root, "/etc/os-release", 'NAME="Fedora Linux"\nID=fedora\nPRETTY_NAME="Fedora Linux 41"\n')
        write(root, "/proc/self/mounts", "/dev/nvme0n1p3 / btrfs rw 0 0\n/dev/nvme0n1p4 %s ext4 rw 0 0\n" % os.path.dirname(home))
        write(root, "/boot/grub2/grub.cfg", "")
        desktop(root, "orphan", "Orphan")
        desktop(root, "vlc", "VLC")
        desktop(root, "zz-gimp", "GIMP")
        make_home(home)

        def rpm(cmd):
            out = []
            for path in cmd[4:]:
                n = os.path.basename(path)
                out.append({"vlc.desktop": "vlc", "zz-gimp.desktop": "gimp"}.get(
                    n, "file %s is not owned by any package" % path))
            return 0, "\n".join(out) + "\n"

        runner = make_runner({"rpm": rpm, "lsblk": lambda c: (0, '{"blockdevices": []}'),
                              "systemd-detect-virt": lambda c: (0, "")})
        s = scanner.Scanner(root=root, home=home, runner=runner, which=which_from({"rpm"}),
                            env={"HOME": home, "USER": "bob", "XDG_CURRENT_DESKTOP": "KDE"})
        m = s.scan()
        pk = {a["name"]: a for a in m["apps"]}
        check(m["os"]["family"] == "fedora", "fedora family")
        check(pk.get("VLC", {}).get("package") == "vlc", "rpm owner after an unowned file is not shifted")
        check(pk.get("GIMP", {}).get("package") == "gimp", "rpm owner, last in order")
        check(pk.get("Orphan", {}).get("package") == "", "an unowned launcher keeps no owner")
        if os.name == "posix":  # the fake mount table holds a POSIX path
            check(m["machine"]["homeSeparate"] is True, "separate /home partition detected")
            check(any(x["id"] == "keep-home" for x in m["plan"]["strategies"]), "separate /home is the keep-home strategy")
        check(m["machine"]["bootloader"] == "grub" and "bootloader" not in m["plan"]["warnings"], "grub2 is GRUB")
        check(m["settings"]["genesiDesktop"] == "KDE-Desktop", "KDE picks Plasma")


# ── Arch ────────────────────────────────────────────────────────────────
def arch_case():
    print("arch")
    with tempfile.TemporaryDirectory() as tmp:
        root, home = os.path.join(tmp, "root"), os.path.join(tmp, "home")
        write(root, "/etc/os-release", 'NAME="EndeavourOS"\nID=endeavouros\nID_LIKE=arch\n')
        desktop(root, "kitty", "kitty")
        os.makedirs(home)
        runner = make_runner({
            "pacman": lambda c: (0, "%s is owned by kitty 0.36-1\n" % c[2]),
            "lsblk": lambda c: (0, '{"blockdevices": []}'),
        })
        m = scanner.Scanner(root=root, home=home, runner=runner, which=which_from({"pacman"}),
                            env={"HOME": home, "USER": "c"}).scan()
        k = [a for a in m["apps"] if a["package"] == "kitty"]
        check(m["os"]["family"] == "arch", "endeavouros is the arch family")
        check(k and k[0]["confidence"] == "same", "an Arch package name is already an Arch name")


# ── the screen ──────────────────────────────────────────────────────────
def ui_case():
    try:
        from PySide6.QtCore import QCoreApplication, QtMsgType, qInstallMessageHandler  # noqa: F401
    except ImportError:
        print("ui: PySide6 not installed, skipped")
        return
    print("ui")
    os.environ["QT_QPA_PLATFORM"] = "offscreen"
    os.environ["QT_QUICK_BACKEND"] = "software"
    data = tempfile.mkdtemp()
    os.environ["XDG_DATA_HOME"] = data

    warnings = []

    def handler(mode, ctx, msg):
        # OpenThemeData / QFontDatabase: Qt offscreen on a Windows dev box
        # (theme probing, no bundled fonts) -- never seen on the Linux runner.
        if mode != QtMsgType.QtDebugMsg and "propagateSizeHints" not in msg \
                and "OpenThemeData" not in msg and "QFontDatabase" not in msg:
            warnings.append(msg)
    qInstallMessageHandler(handler)

    from PySide6.QtCore import QMetaObject, Q_ARG, Q_RETURN_ARG, QUrl  # noqa: F401
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtQml import QQmlApplicationEngine
    import genesi_migrate

    app = QGuiApplication.instance() or QGuiApplication([])
    backend = genesi_migrate.Backend(demo=True)
    engine = QQmlApplicationEngine()
    ctx = engine.rootContext()
    ctx.setContextProperty("backend", backend)
    ctx.setContextProperty("startPage", 6)
    ctx.setContextProperty("forcedLang", "pt")
    engine.load(QUrl.fromLocalFile(os.path.join(os.path.abspath(APP), "Main.qml")))
    roots = engine.rootObjects()
    check(bool(roots), "Main.qml loads")
    if not roots:
        print("\n".join(warnings))
        return
    win = roots[0]

    deadline = time.monotonic() + 15
    while time.monotonic() < deadline and win.property("page") != 6:
        app.processEvents()
        time.sleep(0.02)
    check(win.property("page") == 6, "the demo scan lands on the ready page")

    saved = []
    backend.saved.connect(lambda ok, msg: saved.append((ok, msg)))

    def call(name, *args):
        ret = QMetaObject.invokeMethod(win, name, Q_RETURN_ARG("QVariant"),
                                       *[Q_ARG("QVariant", a) for a in args])
        return ret

    # Disk step: Genesi on the second internal SSD.
    win.setProperty("page", 3)
    call("chooseTarget", "disk:/dev/sdb")
    app.processEvents()
    check(call("canAdvance") is False, "a whole-disk target can't continue before 'I understand'")
    win.setProperty("wipeConfirmed", True)
    check(call("canAdvance") is True, "confirmed, the disk step continues")
    check(win.property("strategy") == "stay", "Genesi on another disk: files stay where they are")
    # Genesi on the external disk: that disk can't also be where files wait.
    call("chooseTarget", "disk:/dev/sda")
    check(win.property("wipeConfirmed") is False, "a new target asks again")
    strategies = call("strategies")
    strategies = strategies.toVariant() if hasattr(strategies, "toVariant") else strategies
    ids = [x["device"] for x in strategies if x["id"] == "external"]
    check("/dev/sda1" not in ids, "the install disk is not offered as the backup disk")
    call("chooseTarget", "replace")
    check(win.property("strategy").startswith("external:"), "replacing the system falls back to the USB backup")
    call("chooseTarget", "disk:/dev/sdb")
    win.setProperty("wipeConfirmed", True)
    win.setProperty("page", 6)

    call("setAllApps", False)
    plan = json.loads(call("buildManifest"))
    check(not any(a["selected"] for a in plan["apps"]), "deselecting every app reaches the plan")
    check(plan["choices"]["strategy"] == "stay", "the plan keeps the files in place")
    check(plan["choices"]["install"] == {"mode": "disk", "disk": "/dev/sdb"}, "the install disk is in the plan")
    check(plan["choices"]["desktop"] == "GNOME-Desktop", "the suggested desktop is in the plan")
    backend.saveManifest(json.dumps(plan))
    for _ in range(50):
        app.processEvents()
        if saved:
            break
        time.sleep(0.02)
    check(saved and saved[0][0], "the plan is saved")
    if saved and saved[0][0]:
        path = saved[0][1]
        check(path.startswith(data), "saved under XDG_DATA_HOME")
        if os.name == "posix":
            check(stat.S_IMODE(os.stat(path).st_mode) == 0o600, "the plan is owner-only")
    for p in range(7):
        win.setProperty("page", p)
        app.processEvents()
    win.setProperty("pt", False)
    app.processEvents()
    check(not warnings, "no Qt warnings:\n    " + "\n    ".join(warnings))
    del engine


if __name__ == "__main__":
    ubuntu_case()
    fedora_case()
    arch_case()
    ui_case()
    if FAILS:
        print("\n%d failure(s)" % len(FAILS))
        sys.exit(1)
    print("\nall good")
