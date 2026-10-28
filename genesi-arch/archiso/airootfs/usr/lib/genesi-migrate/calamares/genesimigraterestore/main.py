#!/usr/bin/env python3
"""
genesimigraterestore -- the part of a Genesi Migrate install that brings the
old system's things into the new one. Runs in the exec phase after the
bootloader, before `umount`, with the target still mounted.

Done HERE, while the installer is online and the target is mounted:
  * the migration plan goes to /var/lib/genesi-migrate (root-only);
  * Wi-Fi networks go to NetworkManager, so Genesi is online at first login;
  * every chosen app that the official/[genesi] repos have is installed with
    pacman now, in the target -- one transaction, missing names filtered out
    first so one unknown name can't fail the lot;
  * dual boot / shared disk: os-prober on, GRUB regenerated, so the old
    system (and Windows) are in Genesi's boot menu.

Left for the FIRST BOOT (restore.py, a oneshot service + a login step):
copying files (the source may be a disk the installer never mounted, and
the user's account must exist), Flatpaks (need a running system bus), and
AUR packages (built as the user, never as root).
"""
import json
import os
import shutil
import subprocess

STAGE = "/run/genesi-migrate/stage"
LIB = "/usr/lib/genesi-migrate"


def pretty_name():
    return "Bringing your apps and settings over"


def wanted_pacman(manifest):
    names = []
    for a in manifest.get("apps", []):
        if a.get("selected") and a.get("kind") == "pacman" and a.get("target"):
            names.append(a["target"])
    return sorted(set(names))


def split_available(names, repo_list_output):
    """Names `pacman -Sl` knows (repo packages), and the rest."""
    known = set()
    for line in repo_list_output.splitlines():
        cols = line.split()
        if len(cols) >= 2:
            known.add(cols[1])
    return [n for n in names if n in known], [n for n in names if n not in known]


def unit_text():
    return """[Unit]
Description=Genesi Migrate: finish bringing your files and apps over
Wants=network-online.target
After=network-online.target local-fs.target
ConditionPathExists=/var/lib/genesi-migrate/pending

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /usr/lib/genesi-migrate/restore.py --system
TimeoutStartSec=infinity

[Install]
WantedBy=multi-user.target
"""


def autostart_text():
    return """[Desktop Entry]
Type=Application
Name=Genesi Migrate
Comment=Finish the migration
Exec=/usr/bin/python3 /usr/lib/genesi-migrate/restore.py --user
NoDisplay=true
X-GNOME-Autostart-Phase=Applications
"""


def run():
    import libcalamares
    # Attributes, not `from libcalamares.utils import`: libcalamares is a
    # built-in module and .utils is not guaranteed to import as a submodule.
    u = libcalamares.utils
    target_env_call, target_env_process_output = u.target_env_call, u.target_env_process_output
    debug, warning = u.debug, u.warning
    gs = libcalamares.globalstorage
    root = gs.value("rootMountPoint")
    user = gs.value("username") or ""
    try:
        with open(os.path.join(STAGE, "manifest.json"), encoding="utf-8") as f:
            manifest = json.load(f)
    except OSError as e:
        return ("Genesi Migrate", "The migration plan is gone: %s" % e)

    state = os.path.join(root, "var/lib/genesi-migrate")
    os.makedirs(state, mode=0o700, exist_ok=True)
    shutil.copy2(os.path.join(STAGE, "manifest.json"), os.path.join(state, "manifest.json"))
    os.chmod(os.path.join(state, "manifest.json"), 0o600)
    with open(os.path.join(state, "user"), "w") as f:
        f.write(user + "\n")

    # Wi-Fi
    wifi = os.path.join(STAGE, "wifi")
    if manifest["choices"].get("wifi") and os.path.isdir(wifi):
        dest = os.path.join(root, "etc/NetworkManager/system-connections")
        os.makedirs(dest, mode=0o700, exist_ok=True)
        for name in os.listdir(wifi):
            shutil.copy2(os.path.join(wifi, name), os.path.join(dest, name))
            os.chmod(os.path.join(dest, name), 0o600)
        debug("genesimigraterestore: %d Wi-Fi networks" % len(os.listdir(wifi)))

    # Apps from the repos, now.
    libcalamares.job.setprogress(0.1)
    names = wanted_pacman(manifest)
    if any(a.get("selected") and a.get("kind") in ("flatpak", "flatpak-search") for a in manifest.get("apps", [])):
        names.append("flatpak")
    if any(a.get("selected") and a.get("kind") == "aur" for a in manifest.get("apps", [])):
        names.append("paru")
    report = {"pacmanInstalled": [], "pacmanMissing": [], "pacmanFailed": False}
    if names:
        try:
            listing = target_env_process_output(["pacman", "-Sl"])
        except subprocess.CalledProcessError:
            listing = ""
        have, missing = split_available(sorted(set(names)), listing)
        report["pacmanMissing"] = missing
        if have:
            rc = target_env_call(["pacman", "-S", "--needed", "--noconfirm"] + have)
            if rc != 0:
                # One transaction failed (a conflict, a download): try them one
                # by one so the rest still land.
                report["pacmanFailed"] = True
                for n in have:
                    if target_env_call(["pacman", "-S", "--needed", "--noconfirm", n]) == 0:
                        report["pacmanInstalled"].append(n)
            else:
                report["pacmanInstalled"] = have
    libcalamares.job.setprogress(0.7)

    # Another system on this disk: put it in Genesi's GRUB menu.
    if gs.value("genesiMigrateOsProber"):
        if target_env_call(["pacman", "-S", "--needed", "--noconfirm", "os-prober"]) == 0:
            grub = os.path.join(root, "etc/default/grub")
            try:
                with open(grub, encoding="utf-8") as f:
                    lines = [l for l in f.read().splitlines() if not l.startswith("GRUB_DISABLE_OS_PROBER=")]
                lines.append("GRUB_DISABLE_OS_PROBER=false")
                with open(grub, "w", encoding="utf-8") as f:
                    f.write("\n".join(lines) + "\n")
                target_env_call(["grub-mkconfig", "-o", "/boot/grub/grub.cfg"])
            except OSError as e:
                warning("genesimigraterestore: os-prober: %s" % e)

    # The first-boot half.
    os.makedirs(os.path.join(root, LIB.lstrip("/")), exist_ok=True)
    shutil.copy2(os.path.join(LIB, "restore.py"), os.path.join(root, LIB.lstrip("/"), "restore.py"))
    unit = os.path.join(root, "etc/systemd/system/genesi-migrate-restore.service")
    with open(unit, "w") as f:
        f.write(unit_text())
    wants = os.path.join(root, "etc/systemd/system/multi-user.target.wants")
    os.makedirs(wants, exist_ok=True)
    link = os.path.join(wants, "genesi-migrate-restore.service")
    if not os.path.lexists(link):
        os.symlink("/etc/systemd/system/genesi-migrate-restore.service", link)
    auto = os.path.join(root, "etc/xdg/autostart/genesi-migrate-finish.desktop")
    os.makedirs(os.path.dirname(auto), exist_ok=True)
    with open(auto, "w") as f:
        f.write(autostart_text())
    with open(os.path.join(state, "install-report.json"), "w") as f:
        json.dump(report, f, indent=2)
    open(os.path.join(state, "pending"), "w").close()
    libcalamares.job.setprogress(1.0)
    return None
