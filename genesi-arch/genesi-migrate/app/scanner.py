"""
Genesi Migrate -- the scan of the OLD system.

Reads what someone has on the Linux they are leaving: which distro, the apps
they actually open (by .desktop file, not the thousand libraries under them),
flatpaks and snaps, their files, and the settings an installer would otherwise
ask again (language, keyboard, timezone, Wi-Fi, desktop). The result is the
migration manifest the rest of the migration works from.

NOTHING HERE CHANGES THE SYSTEM, and nothing needs root. Everything is read.

Stdlib only: this runs on whatever distro the user has today, from inside an
AppImage, so it cannot count on anything beyond Python itself. Every outside
command goes through `runner` and every path through `root`/`home`, so the CI
test can play a Fedora or an Ubuntu without being one.
"""
import json
import os
import re
import shutil
import subprocess
import time

import appmap

MANIFEST_VERSION = 2

ESP_GUID = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
GIB = 1024 ** 3
# v2 "alongside": Genesi gets at least this much, the old system keeps its
# used space plus this much breathing room.
ALONGSIDE_MIN_GENESI = 30 * GIB
ALONGSIDE_OLD_MARGIN = 10 * GIB

# Debian/Ubuntu, Fedora/RHEL, openSUSE, Arch, Void, Gentoo, Solus, Alpine...
# Read from ID first, then ID_LIKE, the way os-release says to.
FAMILIES = {
    "debian": "debian", "ubuntu": "debian", "linuxmint": "debian",
    "pop": "debian", "elementary": "debian", "zorin": "debian",
    "kali": "debian", "neon": "debian", "deepin": "debian", "mx": "debian",
    "fedora": "fedora", "rhel": "fedora", "centos": "fedora", "rocky": "fedora",
    "almalinux": "fedora", "nobara": "fedora", "ultramarine": "fedora",
    "opensuse": "suse", "opensuse-tumbleweed": "suse", "opensuse-leap": "suse",
    "suse": "suse", "sles": "suse",
    "arch": "arch", "manjaro": "arch", "endeavouros": "arch", "cachyos": "arch",
    "garuda": "arch", "artix": "arch", "arcolinux": "arch", "genesi": "arch",
    "void": "void", "gentoo": "gentoo", "solus": "solus", "alpine": "alpine",
    "nixos": "nixos",
}

# Home folders worth naming on the files screen, by their XDG key. The label is
# a translation key the QML resolves; the fallback path is the English default.
XDG_DIRS = (
    ("DOCUMENTS", "documents", "Documents"),
    ("PICTURES", "pictures", "Pictures"),
    ("MUSIC", "music", "Music"),
    ("VIDEOS", "videos", "Videos"),
    ("DOWNLOAD", "downloads", "Downloads"),
    ("DESKTOP", "desktop", "Desktop"),
)

# Hidden things worth carrying, grouped so the screen offers four switches
# instead of a hundred dotfiles.
BROWSER_DIRS = (".mozilla", ".config/google-chrome", ".config/chromium",
                ".config/BraveSoftware", ".config/microsoft-edge",
                ".config/vivaldi", ".config/opera", ".librewolf",
                ".var/app/org.mozilla.firefox", ".var/app/com.google.Chrome",
                ".var/app/com.brave.Browser")
KEY_DIRS = (".ssh", ".gnupg", ".local/share/keyrings", ".password-store")
CONFIG_DIRS = (".config", ".local/share", ".var/app")
# Never carried: caches regrow, the trash is meant to be thrown away, the game
# libraries are a separate (huge) choice below, and the rest rebuilds itself on
# Genesi -- container images re-pull, user flatpaks reinstall from the app list,
# search indexes re-index.
SKIP_IN_HOME = {".cache", ".local/share/Trash", ".local/share/Steam",
                ".steam", ".var/app/com.valvesoftware.Steam",
                ".local/share/containers", ".local/share/flatpak",
                ".local/share/baloo", ".local/share/tracker", ".local/share/tracker3"}
STEAM_DIRS = (".local/share/Steam", ".var/app/com.valvesoftware.Steam/.local/share/Steam")


def default_runner(cmd, timeout=30):
    """Run a command, return (returncode, stdout). Never raises."""
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                           env=dict(os.environ, LC_ALL="C"))
        return p.returncode, p.stdout
    except (OSError, subprocess.SubprocessError):
        return 127, ""


class Scanner:
    def __init__(self, root="/", home=None, env=None, runner=None, which=None,
                 progress=None):
        self.root = root
        self.env = dict(os.environ if env is None else env)
        self.home = home or self.env.get("HOME") or os.path.expanduser("~")
        self.run = runner or default_runner
        self.which = which or shutil.which
        self.progress = progress or (lambda stage, frac: None)

    # ── paths ──────────────────────────────────────────────────────────
    def p(self, path):
        """A system path under the scan root."""
        return os.path.join(self.root, path.lstrip("/"))

    def h(self, rel=""):
        return os.path.join(self.home, rel) if rel else self.home

    def read(self, path, default=""):
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                return f.read()
        except OSError:
            return default

    # ── the distro ─────────────────────────────────────────────────────
    def detect_os(self):
        info = {}
        text = self.read(self.p("/etc/os-release")) or self.read(self.p("/usr/lib/os-release"))
        for line in text.splitlines():
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.split("=", 1)
                info[k.strip()] = v.strip().strip('"').strip("'")
        os_id = info.get("ID", "linux").lower()
        like = info.get("ID_LIKE", "").lower().split()
        family = "other"
        for candidate in [os_id] + like:
            if candidate in FAMILIES:
                family = FAMILIES[candidate]
                break
        return {
            "id": os_id,
            "name": info.get("NAME", "Linux"),
            "pretty": info.get("PRETTY_NAME") or info.get("NAME", "Linux"),
            "version": info.get("VERSION_ID", ""),
            "family": family,
            "logo": info.get("LOGO", ""),
        }

    def package_managers(self):
        found = []
        for tool in ("dpkg", "rpm", "pacman", "xbps-query", "eopkg", "apk",
                     "flatpak", "snap", "nix-env"):
            if self.which(tool):
                found.append(tool)
        return found

    # ── apps ───────────────────────────────────────────────────────────
    def parse_desktop(self, path):
        """The [Desktop Entry] keys of a .desktop file (localised Name kept)."""
        entry, in_main = {}, False
        for line in self.read(path).splitlines():
            line = line.strip()
            if line.startswith("["):
                in_main = line == "[Desktop Entry]"
                continue
            if in_main and "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                entry.setdefault(k.strip(), v.strip())
        return entry

    def desktop_files(self):
        """Visible application launchers installed by the system."""
        out = []
        base = self.p("/usr/share/applications")
        try:
            names = sorted(os.listdir(base))
        except OSError:
            return out
        for name in names:
            if not name.endswith(".desktop"):
                continue
            path = os.path.join(base, name)
            e = self.parse_desktop(path)
            if e.get("Type", "Application") != "Application":
                continue
            if e.get("NoDisplay", "").lower() == "true" or e.get("Hidden", "").lower() == "true":
                continue
            # OnlyShowIn=KDE / GNOME etc.: a piece of one desktop, not an app.
            if e.get("OnlyShowIn"):
                continue
            if not e.get("Exec"):
                continue
            out.append({
                "file": name,
                "path": path,
                "sysPath": "/usr/share/applications/" + name,
                "name": e.get("Name", name[:-8]),
                "namePt": e.get("Name[pt_BR]") or e.get("Name[pt]") or "",
                "icon": e.get("Icon", ""),
                "comment": e.get("Comment", ""),
                "categories": [c for c in e.get("Categories", "").split(";") if c],
            })
        return out

    def owners(self, managers, sys_paths):
        """Map system .desktop paths -> owning package name (or missing)."""
        owners = {}
        if not sys_paths:
            return owners
        chunks = [sys_paths[i:i + 200] for i in range(0, len(sys_paths), 200)]
        if "dpkg" in managers:
            for chunk in chunks:
                _, out = self.run(["dpkg", "-S"] + chunk, timeout=60)
                for line in out.splitlines():
                    # "pkg:amd64, other: /usr/share/applications/x.desktop"
                    if line.startswith("diversion by") or ": " not in line:
                        continue
                    pkgs, path = line.rsplit(": ", 1)
                    first = pkgs.split(",")[0].strip().split(":")[0]
                    owners[path.strip()] = first
        elif "rpm" in managers:
            for chunk in chunks:
                _, out = self.run(["rpm", "-qf", "--qf", "%{NAME}\n"] + chunk, timeout=60)
                # One line per argument, in order; unowned files print a sentence.
                for path, line in zip(chunk, out.splitlines()):
                    line = line.strip()
                    if line and " " not in line:
                        owners[path] = line
        elif "pacman" in managers:
            for chunk in chunks:
                _, out = self.run(["pacman", "-Qo"] + chunk, timeout=60)
                for line in out.splitlines():
                    m = re.match(r"^(\S+) is owned by (\S+) ", line)
                    if m:
                        owners[m.group(1)] = m.group(2)
        elif "xbps-query" in managers:
            for path in sys_paths:
                _, out = self.run(["xbps-query", "-o", path], timeout=20)
                m = re.match(r"^(\S+?)-\d[^:]*:", out.strip())
                if m:
                    owners[path] = m.group(1)
        return owners

    def resolve_icon(self, icon):
        """A file path for an icon name, from the old system's own theme dirs.

        Only the cheap places: an absolute path, hicolor at the usual sizes, and
        pixmaps. A miss shows a letter avatar, which is fine.
        """
        if not icon:
            return ""
        if icon.startswith("/"):
            full = self.p(icon)
            return full if os.path.isfile(full) else ""
        for size in ("128x128", "96x96", "64x64", "48x48", "256x256", "scalable"):
            for ext in (".png", ".svg"):
                cand = self.p("/usr/share/icons/hicolor/%s/apps/%s%s" % (size, icon, ext))
                if os.path.isfile(cand):
                    return cand
        for ext in (".png", ".svg", ".xpm"):
            cand = self.p("/usr/share/pixmaps/" + icon + ext)
            if os.path.isfile(cand) and ext != ".xpm":
                return cand
        return ""

    def native_apps(self, os_info, managers):
        desktops = self.desktop_files()
        owners = self.owners(managers, [d["sysPath"] for d in desktops])
        apps, core, seen = [], 0, set()
        for d in desktops:
            owner = owners.get(d["sysPath"], "")
            if appmap.is_de_core(owner) or (not owner and appmap.is_de_core(d["file"][:-8])):
                core += 1
                continue
            key = owner or d["file"][:-8]
            kind, target, conf = appmap.map_package(key, os_info["family"])
            if conf == "skip":
                continue
            # One package can ship several launchers (libreoffice-*): one row.
            dedupe = (kind, target)
            if dedupe in seen:
                continue
            seen.add(dedupe)
            apps.append({
                "id": "native:" + key,
                "name": d["name"],
                "namePt": d["namePt"],
                "comment": d["comment"],
                "icon": self.resolve_icon(d["icon"]),
                "source": next((m for m in managers if m in ("dpkg", "rpm", "pacman", "xbps-query")), "system"),
                "package": owner,
                "kind": kind,
                "target": target,
                "confidence": conf,
                "selected": True,
            })
        return apps, core

    def flatpak_apps(self):
        if not self.which("flatpak"):
            return []
        _, out = self.run(["flatpak", "list", "--app", "--columns=application,name,installation"])
        apps, seen = [], set()
        for line in out.splitlines():
            cols = line.split("\t")
            if not cols or not cols[0] or cols[0] in seen or cols[0] == "Application ID":
                continue
            seen.add(cols[0])
            appid = cols[0]
            icon = ""
            for base in ("/var/lib/flatpak/exports/share/icons/hicolor",):
                for size in ("128x128", "64x64", "scalable"):
                    for ext in (".png", ".svg"):
                        c = self.p("%s/%s/apps/%s%s" % (base, size, appid, ext))
                        if not icon and os.path.isfile(c):
                            icon = c
            apps.append({
                "id": "flatpak:" + appid,
                "name": cols[1] if len(cols) > 1 and cols[1] else appid.split(".")[-1],
                "namePt": "",
                "comment": "",
                "icon": icon,
                "source": "flatpak",
                "package": appid,
                "kind": "flatpak",
                "target": appid,
                # Flathub is Flathub: the same app id installs on Genesi.
                "confidence": "known",
                "selected": True,
                "user": len(cols) > 2 and cols[2].strip() == "user",
            })
        return apps

    def snap_apps(self):
        if not self.which("snap"):
            return []
        _, out = self.run(["snap", "list"])
        apps = []
        for line in out.splitlines()[1:]:
            cols = line.split()
            if not cols:
                continue
            name = cols[0]
            if appmap.is_snap_runtime(name):
                continue
            kind, target, conf = appmap.map_snap(name)
            if conf == "skip":
                continue
            # snapd exports each snap's launcher here, with its real name and
            # an absolute icon path inside /snap.
            entry = {}
            snap_desk = self.p("/var/lib/snapd/desktop/applications")
            try:
                for f in sorted(os.listdir(snap_desk)):
                    if f.startswith(name + "_") and f.endswith(".desktop"):
                        entry = self.parse_desktop(os.path.join(snap_desk, f))
                        break
            except OSError:
                pass
            apps.append({
                "id": "snap:" + name,
                "name": entry.get("Name") or name.replace("-", " ").title(),
                "namePt": entry.get("Name[pt_BR]", ""),
                "comment": entry.get("Comment", ""),
                "icon": self.resolve_icon(entry.get("Icon", "")),
                "source": "snap",
                "package": name,
                "kind": kind,
                "target": target,
                "confidence": conf,
                "selected": True,
            })
        return apps

    def cli_tools(self, taken):
        """Command-line tools present on the old system, minus ones already
        covered by an app row (`taken` = set of pacman targets)."""
        tools, seen = [], set()
        for cmd, pkg in appmap.CLI_TOOLS.items():
            if pkg in taken or pkg in seen:
                continue
            if os.path.exists(self.p("/usr/bin/" + cmd)) or os.path.exists(self.p("/usr/local/bin/" + cmd)) \
                    or os.path.exists(self.h(".cargo/bin/" + cmd) if cmd in ("rustup", "cargo") else ""):
                seen.add(pkg)
                tools.append({
                    "id": "cli:" + pkg,
                    "name": cmd,
                    "namePt": "",
                    "comment": "",
                    "icon": "",
                    "source": "cli",
                    "package": cmd,
                    "kind": "pacman",
                    "target": pkg,
                    "confidence": "known",
                    "selected": True,
                })
        return tools

    # ── files ──────────────────────────────────────────────────────────
    def du(self, path, budget):
        """Bytes under `path` via du(1), which is far faster than walking in
        Python. None when du is missing, fails or runs out of time."""
        rc, out = self.run(["du", "-s", "-B1", "-x", "--", path], timeout=budget)
        if rc not in (0, 1):  # 1 = some unreadable subdir; the total still counts
            return None
        try:
            return int(out.split()[0])
        except (IndexError, ValueError):
            return None

    def size_of(self, path, budget, skip=()):
        """(bytes, estimate) for one item. Each item gets its OWN budget: one
        shared deadline let a single huge folder starve every row after it."""
        if not skip:
            size = self.du(path, budget)
            if size is not None:
                return size, False
        return self.dir_size(path, time.monotonic() + min(budget, 8.0), skip)

    def dir_size(self, path, deadline, skip=()):
        """Bytes under `path`, not following symlinks. Stops at `deadline`
        (returns what it counted plus True for 'estimate')."""
        total, partial = 0, False
        stack = [path]
        while stack:
            if time.monotonic() > deadline:
                partial = True
                break
            cur = stack.pop()
            try:
                with os.scandir(cur) as it:
                    for e in it:
                        try:
                            if e.is_symlink():
                                continue
                            if e.is_dir(follow_symlinks=False):
                                if os.path.relpath(e.path, self.home) not in skip:
                                    stack.append(e.path)
                            elif e.is_file(follow_symlinks=False):
                                total += e.stat(follow_symlinks=False).st_size
                        except OSError:
                            continue
            except OSError:
                continue
        return total, partial

    def xdg_user_dirs(self):
        conf = self.read(self.h(".config/user-dirs.dirs"))
        dirs = {}
        for key, _, default in XDG_DIRS:
            m = re.search(r'^XDG_%s_DIR="?([^"\n]+)"?' % key, conf, re.M)
            val = m.group(1) if m else "$HOME/" + default
            val = val.replace("$HOME", self.home)
            dirs[key] = val
        return dirs

    def home_items(self, budget=20.0):
        """The files screen: one row per thing a person recognises.
        `budget` is seconds PER ITEM, not for the whole screen."""
        items, named = [], set()
        dirs = self.xdg_user_dirs()
        for key, label, _ in XDG_DIRS:
            path = dirs[key]
            if not os.path.isdir(path) or os.path.realpath(path) == os.path.realpath(self.home):
                continue
            size, partial = self.size_of(path, budget)
            named.add(os.path.realpath(path))
            items.append({"id": label, "label": label, "path": path, "bytes": size,
                          "estimate": partial, "selected": True, "group": "files"})

        # Everything else visible in ~ (projects, Games, a stray folder...).
        other_bytes, other_partial, other_names = 0, False, []
        try:
            entries = sorted(os.scandir(self.home), key=lambda e: e.name)
        except OSError:
            entries = []
        for e in entries:
            if e.name.startswith(".") or e.is_symlink():
                continue
            if os.path.realpath(e.path) in named:
                continue
            if e.is_dir(follow_symlinks=False):
                size, partial = self.size_of(e.path, budget)
            elif e.is_file(follow_symlinks=False):
                size, partial = e.stat(follow_symlinks=False).st_size, False
            else:
                continue
            other_bytes += size
            other_partial = other_partial or partial
            other_names.append(e.name)
        if other_names:
            items.append({"id": "other", "label": "other", "path": self.home,
                          "bytes": other_bytes, "estimate": other_partial,
                          "selected": True, "group": "files",
                          "names": other_names[:12], "allNames": other_names,
                          "count": len(other_names)})

        def group(gid, rels, skip=()):
            total, partial, present = 0, False, []
            for rel in rels:
                full = self.h(rel)
                if os.path.isdir(full):
                    size, part = self.size_of(full, budget, skip)
                    total += size
                    partial = partial or part
                    present.append(rel)
            if present:
                items.append({"id": gid, "label": gid, "path": self.home, "bytes": total,
                              "estimate": partial, "selected": True, "group": "hidden",
                              "paths": present})

        group("browsers", BROWSER_DIRS)
        group("keys", KEY_DIRS)
        # App settings, minus what the other groups and the skip list cover.
        group("appconfig", CONFIG_DIRS,
              skip=set(SKIP_IN_HOME) | set(BROWSER_DIRS) | set(KEY_DIRS))
        steam = [r for r in STEAM_DIRS if os.path.isdir(self.h(r))]
        if steam:
            size, partial = 0, False
            for r in steam:
                s, part = self.size_of(self.h(r), budget)
                size += s
                partial = partial or part
            # Off by default: often hundreds of GB, and Steam re-downloads.
            items.append({"id": "steam", "label": "steam", "path": self.h(steam[0]),
                          "bytes": size, "estimate": partial, "selected": False,
                          "group": "hidden", "paths": steam})
        return items

    # ── the machine ────────────────────────────────────────────────────
    def mounts(self):
        rows = []
        for line in self.read(self.p("/proc/self/mounts")).splitlines():
            cols = line.split()
            if len(cols) >= 3:
                rows.append({"source": cols[0],
                             "target": cols[1].replace("\\040", " "),
                             "fstype": cols[2],
                             "options": cols[3] if len(cols) > 3 else ""})
        return rows

    def mount_for(self, path, mounts):
        best = None
        for m in mounts:
            t = m["target"].rstrip("/") or "/"
            if path == t or path.startswith(t.rstrip("/") + "/") or t == "/":
                if best is None or len(t) > len(best["target"].rstrip("/") or "/"):
                    best = m
        return best

    def block_devices(self):
        rc, out = self.run(["lsblk", "-J", "-b", "-o",
                            "NAME,PATH,TYPE,FSTYPE,MOUNTPOINT,SIZE,FSAVAIL,FSUSED,RM,TRAN,LABEL,"
                            "MODEL,PKNAME,UUID,PARTUUID,PARTTYPE,SERIAL,WWN,PTTYPE"])
        if rc != 0 or not out.strip():
            return []
        try:
            return json.loads(out).get("blockdevices", [])
        except ValueError:
            return []

    def machine(self):
        mounts = self.mounts()
        root_m = self.mount_for("/", mounts) or {}
        home_m = self.mount_for(self.home, mounts) or {}
        devices = self.block_devices()

        firmware = "uefi" if os.path.isdir(self.p("/sys/firmware/efi")) else "bios"
        secure_boot = False
        efivars = self.p("/sys/firmware/efi/efivars")
        try:
            for name in os.listdir(efivars):
                if name.startswith("SecureBoot-"):
                    with open(os.path.join(efivars, name), "rb") as f:
                        data = f.read()
                    secure_boot = len(data) >= 5 and data[4] == 1
        except OSError:
            pass

        luks, windows, externals = False, False, []
        root_disk = home_disk = None
        home_target = home_m.get("target")
        windows_disks = set()

        def walk(nodes, chain):
            nonlocal luks, windows, root_disk, home_disk
            for n in nodes:
                here = chain + [n]
                mp = n.get("mountpoint")
                if mp == "/":
                    root_disk = here[0].get("name")
                    if any(x.get("type") == "crypt" or x.get("fstype") == "crypto_LUKS" for x in here):
                        luks = True
                if mp and mp == home_target:
                    home_disk = here[0].get("name")
                # Windows = its boot manager on an ESP we can see, or a volume
                # labelled like it. A bare NTFS partition is usually just data.
                on_esp = (mp in ("/boot/efi", "/efi", "/boot") and n.get("fstype") == "vfat"
                          and os.path.isdir(self.p(mp + "/EFI/Microsoft")))
                if on_esp or (n.get("label") or "").lower().startswith("windows"):
                    windows = True
                    windows_disks.add(here[0].get("name"))
                walk(n.get("children") or [], here)

        walk(devices, [])

        # Every disk Genesi could be installed on. The one holding today's
        # system can be REPLACED (only its system partition is formatted);
        # any other one is used WHOLE, erasing it -- so the screen has to say
        # what is on it now.
        def flat_parts(node):
            out = []
            for ch in node.get("children") or []:
                out.append(ch)
                out.extend(flat_parts(ch))
            return out

        disks = []
        for d in devices:
            if d.get("type") != "disk" or (d.get("name") or "").startswith(("zram", "loop", "sr", "ram")):
                continue
            parts = flat_parts(d)
            disks.append({
                "device": d.get("path") or "/dev/" + d.get("name", ""),
                "name": d.get("name"),
                # The live system may name disks in another order (sda <-> sdb):
                # the installer finds this one again by serial/WWN and size.
                "serial": (d.get("serial") or "").strip(),
                "wwn": (d.get("wwn") or "").strip(),
                "ptType": d.get("pttype") or "",
                "model": (d.get("model") or "").strip() or d.get("name"),
                "size": int(d.get("size") or 0),
                "removable": d.get("rm") in (True, "1", 1) or d.get("tran") == "usb",
                "tran": d.get("tran") or "",
                "system": d.get("name") == root_disk,
                "home": d.get("name") == home_disk,
                "windows": d.get("name") in windows_disks,
                "partitions": [{
                    "device": p.get("path") or "/dev/" + p.get("name", ""),
                    "type": p.get("type"),
                    "fstype": p.get("fstype") or "",
                    "label": p.get("label") or "",
                    "size": int(p.get("size") or 0),
                    "mountpoint": p.get("mountpoint") or "",
                    "uuid": p.get("uuid") or "",
                    "partuuid": p.get("partuuid") or "",
                    "parttype": (p.get("parttype") or "").lower(),
                    "used": int(p.get("fsused") or 0) if p.get("fsused") else None,
                } for p in parts if p.get("type") in ("part", "crypt", "lvm")],
            })

        for d in devices:
            removable = d.get("rm") in (True, "1", 1) or d.get("tran") == "usb"
            if not removable or d.get("name") == root_disk or d.get("type") != "disk":
                continue
            parts = d.get("children") or [d]
            for part in parts:
                if part.get("fstype") in (None, "", "swap", "crypto_LUKS"):
                    continue
                externals.append({
                    "device": part.get("path") or "/dev/" + part.get("name", ""),
                    "label": part.get("label") or d.get("model") or part.get("name"),
                    "model": (d.get("model") or "").strip(),
                    "fstype": part.get("fstype"),
                    "size": int(part.get("size") or 0),
                    "free": int(part.get("fsavail") or 0) if part.get("fsavail") else None,
                    "mountpoint": part.get("mountpoint"),
                })

        bootloader = "unknown"
        if os.path.isfile(self.p("/boot/grub/grub.cfg")) or os.path.isfile(self.p("/boot/grub2/grub.cfg")):
            bootloader = "grub"
        elif os.path.isdir(self.p("/boot/loader/entries")) or os.path.isdir(self.p("/boot/efi/loader/entries")):
            bootloader = "systemd-boot"
        elif os.path.isfile(self.p("/boot/limine.conf")) or os.path.isfile(self.p("/boot/limine/limine.conf")):
            bootloader = "limine"

        try:
            st = os.statvfs(self.home)
            home_free = st.f_bavail * st.f_frsize
        except (OSError, AttributeError):
            home_free = 0

        # The partitions the installer has to find again from the live system,
        # by UUID: the system partition, /home, and the EFI partition.
        all_parts = {}
        for d in disks:
            for prt in d["partitions"]:
                all_parts[prt["device"]] = dict(prt, disk=d["device"])
        root_part = all_parts.get(root_m.get("source", ""), {})
        home_part = all_parts.get(home_m.get("source", ""), {}) if home_m.get("source") != root_m.get("source") else {}
        esp = {}
        sys_disk = next((d for d in disks if d["system"]), None)
        if sys_disk:
            for prt in sys_disk["partitions"]:
                if prt["parttype"] == ESP_GUID or (prt["fstype"] == "vfat" and prt["mountpoint"] in ("/boot/efi", "/efi", "/boot")):
                    esp = prt
                    break
        esp_free = None
        if esp.get("mountpoint"):
            try:
                st = os.statvfs(self.p(esp["mountpoint"]))
                esp_free = st.f_bavail * st.f_frsize
            except (OSError, AttributeError):
                pass

        ram = 0
        m = re.search(r"^MemTotal:\s+(\d+)\s+kB", self.read(self.p("/proc/meminfo")), re.M)
        if m:
            ram = int(m.group(1)) * 1024

        return {
            "firmware": firmware,
            "secureBoot": secure_boot,
            "rootFs": root_m.get("fstype", ""),
            "rootDevice": root_m.get("source", ""),
            "homeFs": home_m.get("fstype", ""),
            "homeDevice": home_m.get("source", ""),
            "homeSeparate": bool(home_m) and home_m.get("target") not in ("/", None)
                            and home_m.get("source") != root_m.get("source"),
            "homeFree": home_free,
            "rootUuid": root_part.get("uuid", ""),
            "rootPartType": root_part.get("type", ""),
            "rootPartSize": root_part.get("size", 0),
            "rootUsed": root_part.get("used"),
            "rootOptions": root_m.get("options", ""),
            "homeUuid": home_part.get("uuid", ""),
            "homeOptions": home_m.get("options", ""),
            "homeMount": home_m.get("target", ""),
            "espDevice": esp.get("device", ""),
            "espUuid": esp.get("uuid", ""),
            "espFree": esp_free,
            "ramBytes": ram,
            "luks": luks,
            "windows": windows,
            "bootloader": bootloader,
            "externals": externals,
            "disks": disks,
            "virtual": self.run(["systemd-detect-virt", "--quiet"], timeout=5)[0] == 0,
        }

    # ── settings ───────────────────────────────────────────────────────
    def settings(self):
        lang = ""
        for f, key in (("/etc/locale.conf", "LANG"), ("/etc/default/locale", "LANG"),
                       ("/etc/sysconfig/language", "RC_LANG")):
            m = re.search(r'^%s="?([^"\n]+)"?' % key, self.read(self.p(f)), re.M)
            if m:
                lang = m.group(1)
                break
        lang = self.env.get("LANG") or lang or "en_US.UTF-8"

        tz = ""
        try:
            link = os.readlink(self.p("/etc/localtime"))
            if "zoneinfo/" in link:
                tz = link.split("zoneinfo/", 1)[1]
        except OSError:
            pass
        tz = tz or self.read(self.p("/etc/timezone")).strip() or "UTC"

        layout, variant = "", ""
        kb = self.read(self.p("/etc/default/keyboard"))
        m = re.search(r'^XKBLAYOUT="?([^"\n]*)"?', kb, re.M)
        if m:
            layout = m.group(1)
            m2 = re.search(r'^XKBVARIANT="?([^"\n]*)"?', kb, re.M)
            variant = m2.group(1) if m2 else ""
        if not layout:
            x11 = self.read(self.p("/etc/X11/xorg.conf.d/00-keyboard.conf"))
            m = re.search(r'"XkbLayout"\s+"([^"]+)"', x11)
            if m:
                layout = m.group(1)
                m2 = re.search(r'"XkbVariant"\s+"([^"]+)"', x11)
                variant = m2.group(1) if m2 else ""
        if not layout:
            _, out = self.run(["localectl", "status"], timeout=10)
            m = re.search(r"X11 Layout:\s*(\S+)", out)
            layout = m.group(1) if m else "us"
            m = re.search(r"X11 Variant:\s*(\S+)", out)
            variant = m.group(1) if m else ""

        wifi = []
        rc, out = self.run(["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"], timeout=10)
        if rc == 0:
            for line in out.splitlines():
                # nmcli -t escapes ':' inside names as '\:'
                parts = re.split(r"(?<!\\):", line)
                if len(parts) >= 2 and parts[-1] == "802-11-wireless":
                    wifi.append(parts[0].replace("\\:", ":"))

        user = self.env.get("USER") or os.path.basename(self.home)
        full_name, shell = "", "/bin/bash"
        for line in self.read(self.p("/etc/passwd")).splitlines():
            cols = line.split(":")
            if len(cols) >= 7 and cols[0] == user:
                full_name = cols[4].split(",")[0]
                shell = cols[6]
                break

        desktop = self.env.get("XDG_CURRENT_DESKTOP") or self.env.get("DESKTOP_SESSION") or ""
        return {
            "locale": lang,
            "timezone": tz,
            "keyboard": {"layout": layout or "us", "variant": variant},
            "wifi": wifi,
            "user": {"name": user, "fullName": full_name, "shell": os.path.basename(shell)},
            "desktop": desktop,
            "genesiDesktop": appmap.genesi_desktop_for(desktop),
        }

    # ── everything ─────────────────────────────────────────────────────
    def scan(self):
        self.progress("system", 0.05)
        os_info = self.detect_os()
        managers = self.package_managers()
        self.progress("apps", 0.15)
        apps, core = self.native_apps(os_info, managers)
        self.progress("flatpak", 0.35)
        apps += self.flatpak_apps()
        apps += self.snap_apps()
        taken = {a["target"] for a in apps if a["kind"] == "pacman"}
        apps += self.cli_tools(taken)
        self.progress("files", 0.45)
        items = self.home_items()
        self.progress("machine", 0.85)
        machine = self.machine()
        self.progress("settings", 0.93)
        settings = self.settings()
        self.progress("done", 1.0)
        return {
            "version": MANIFEST_VERSION,
            "created": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "os": os_info,
            "managers": managers,
            "apps": apps,
            "desktopComponents": core,
            "files": items,
            "machine": machine,
            "settings": settings,
            "plan": plan(machine, items),
        }


def plan(machine, items):
    """What the migration can do on this machine, and what stops it.

    blockers stop the migration outright; warnings are shown but allowed.
    strategies are the ways the user's files can survive the reinstall.
    """
    blockers, warnings = [], []
    if machine.get("luks"):
        # The install would have to unlock, keep and re-wrap the disk. Not in v1.
        blockers.append("luks")
    if machine.get("secureBoot"):
        # The restart goes through this system's own signed GRUB, which will
        # not load Genesi's (unsigned) kernel while Secure Boot is on.
        blockers.append("secureBoot")
    if machine.get("windows"):
        warnings.append("windows")
    if machine.get("bootloader") not in ("grub",):
        warnings.append("bootloader")

    wanted = sum(i["bytes"] for i in items if i.get("selected"))
    strategies = []
    if machine.get("homeSeparate") and not machine.get("luks"):
        # The cheap, safe case: Genesi formats only the system partition and
        # mounts this one as /home.
        strategies.append({"id": "keep-home", "device": machine.get("homeDevice"),
                           "fstype": machine.get("homeFs"), "ok": True})
    for ext in machine.get("externals", []):
        free = ext.get("free")
        strategies.append({
            "id": "external",
            "device": ext["device"],
            "label": ext["label"],
            "free": free,
            "size": ext["size"],
            "mounted": bool(ext.get("mountpoint")),
            # 5% headroom; an unmounted drive's free space is unknown until it is.
            "ok": free is not None and free >= wanted * 1.05,
        })
    return {"blockers": blockers, "warnings": warnings,
            "strategies": strategies, "wantedBytes": wanted,
            "alongside": alongside(machine)}


def alongside(machine):
    """Can Genesi go NEXT TO today's system (shrink it), and how big?

    Only a plain ext4/btrfs partition can be shrunk safely from the live
    system: not LVM, not LUKS, not xfs (cannot shrink at all).
    """
    size, used = machine.get("rootPartSize") or 0, machine.get("rootUsed")
    why = ""
    if machine.get("rootFs") not in ("ext4", "btrfs"):
        why = "fs"
    elif machine.get("luks") or machine.get("rootPartType") != "part":
        why = "layout"
    elif used is None or not size:
        why = "unknown"
    room = size - (used or 0) - ALONGSIDE_OLD_MARGIN if not why else 0
    if not why and room < ALONGSIDE_MIN_GENESI:
        why = "space"
    return {"ok": not why, "why": why, "min": ALONGSIDE_MIN_GENESI,
            "max": max(0, room), "partSize": size, "used": used or 0}


if __name__ == "__main__":
    import sys
    print(json.dumps(Scanner(progress=lambda s, f: sys.stderr.write("%s %.0f%%\n" % (s, f * 100))).scan(),
                     indent=2, ensure_ascii=False))
