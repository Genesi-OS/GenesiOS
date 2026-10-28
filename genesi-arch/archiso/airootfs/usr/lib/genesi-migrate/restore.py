#!/usr/bin/env python3
"""
Genesi Migrate -- the first-boot half of the restore, on the INSTALLED Genesi.

  restore.py --system   (genesi-migrate-restore.service, root, every boot
                         until done): copy the chosen files from wherever they
                         waited into the new home, install the Flatpaks
  restore.py --user     (login autostart): build the AUR apps as the user in
                         a terminal, then say what came over and what didn't

State lives in /var/lib/genesi-migrate:
  manifest.json   the plan             pending       the service still has work
  user            the new login name   status.json   what happened, for --user
  install-report.json   what the installer already did with pacman

When the files wait on an external drive that is not plugged in, the service
leaves `pending` in place and tries again next boot; the login step tells the
user to plug it in. Nothing is ever deleted from the source.
"""
import json
import os
import pwd
import shutil
import subprocess
import sys
import time

STATE = "/var/lib/genesi-migrate"
SRC = "/run/genesi-migrate/source"
SKIP = {".cache", ".local/share/Trash", ".local/share/Steam", ".steam",
        ".var/app/com.valvesoftware.Steam", ".local/share/containers",
        ".local/share/flatpak", ".local/share/baloo", ".local/share/tracker",
        ".local/share/tracker3"}


def load(name, default=None):
    try:
        with open(os.path.join(STATE, name), encoding="utf-8") as f:
            return json.load(f) if name.endswith(".json") else f.read().strip()
    except (OSError, ValueError):
        return default


def save_status(st):
    with open(os.path.join(STATE, "status.json"), "w", encoding="utf-8") as f:
        json.dump(st, f, indent=2)
    os.chmod(os.path.join(STATE, "status.json"), 0o644)


def _subvol(options):
    for opt in (options or "").split(","):
        if opt.startswith("subvol="):
            sv = opt[len("subvol="):].strip("/")
            return "/" + sv if sv else ""
    return ""


def mount_uuid(uuid, fs_hint=""):
    """Mount a filesystem read-only by UUID (btrfs: the top level, so paths
    with a subvolume prefix resolve). Returns the mount point or None."""
    os.makedirs(SRC, exist_ok=True)
    if os.path.ismount(SRC):
        subprocess.run(["umount", SRC])
    opts = "ro"
    fs = subprocess.run(["blkid", "-s", "TYPE", "-o", "value", "/dev/disk/by-uuid/" + uuid],
                        capture_output=True, text=True).stdout.strip() or fs_hint
    if not fs:
        return None
    if fs == "btrfs":
        opts += ",subvolid=5"
    if subprocess.run(["mount", "-o", opts, "UUID=" + uuid, SRC]).returncode != 0:
        return None
    return SRC


def selected_rel_paths(manifest):
    """Paths relative to the old home, for every selected file row."""
    home = manifest.get("stagePlan", {}).get("homeAtScan") or ""
    out = []
    for item in manifest.get("files", []):
        if not item.get("selected"):
            continue
        if item["id"] == "other":
            out += item.get("allNames") or item.get("names") or []
        elif item.get("paths"):
            out += item["paths"]
        elif home:
            out.append(os.path.relpath(item["path"], home))
    return [p for p in out if p and not p.startswith("..")]


def copy_into(src_root, rels, dest_home, uid, gid):
    copied, errors = 0, []
    for rel in rels:
        src = os.path.join(src_root, rel)
        dst = os.path.join(dest_home, rel)
        if not os.path.lexists(src):
            continue
        try:
            if os.path.isdir(src) and not os.path.islink(src):
                for dp, dns, fns in os.walk(src):
                    dns[:] = [d for d in dns if os.path.relpath(os.path.join(dp, d), src_root) not in SKIP]
                    tgt = os.path.join(dst, os.path.relpath(dp, src))
                    os.makedirs(tgt, exist_ok=True)
                    for fn in fns:
                        s, d = os.path.join(dp, fn), os.path.join(tgt, fn)
                        try:
                            if os.path.islink(s):
                                if not os.path.lexists(d):
                                    os.symlink(os.readlink(s), d)
                            elif os.path.isfile(s):
                                shutil.copy2(s, d)
                                copied += 1
                        except OSError as e:
                            errors.append("%s: %s" % (s, e.strerror))
            else:
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copy2(src, dst, follow_symlinks=False)
                copied += 1
        except OSError as e:
            errors.append("%s: %s" % (src, e.strerror))
    # everything under the new home belongs to the new user
    for dp, dns, fns in os.walk(dest_home):
        for n in dns + fns:
            try:
                os.lchown(os.path.join(dp, n), uid, gid)
            except OSError:
                pass
    return copied, errors


def restore_files(manifest, user, status):
    ch, m = manifest["choices"], manifest["machine"]
    sp = manifest.get("stagePlan", {})
    strategy = ch["strategy"]
    try:
        pw = pwd.getpwnam(user)
    except KeyError:
        status["files"] = {"state": "error", "detail": "no user %s" % user}
        return True
    dest = pw.pw_dir
    rels = selected_rel_paths(manifest)
    if strategy == "none" or not rels:
        status["files"] = {"state": "skipped"}
        return True

    if strategy.startswith("external:"):
        mnt = mount_uuid(sp.get("uuid", ""))
        if not mnt:
            status["files"] = {"state": "waiting-drive"}
            return False                       # try again next boot
        src_root = mnt + sp.get("filesRel", "")
    elif strategy == "keep-home":
        # /home IS the old home partition. Same login name: the folder is
        # already there and only needs the new owner; another name: copy.
        old = os.path.join("/home", manifest["settings"]["user"]["name"])
        if os.path.realpath(old) == os.path.realpath(dest):
            copy_into(dest, [], dest, pw.pw_uid, pw.pw_gid)
            status["files"] = {"state": "done", "copied": 0, "errors": []}
            return True
        src_root = old
    else:  # stay: the old system's disk, untouched by the install
        uuid = m.get("homeUuid") if m.get("homeSeparate") else m.get("rootUuid")
        opts = m.get("homeOptions") if m.get("homeSeparate") else m.get("rootOptions")
        mount_target = m.get("homeMount") if m.get("homeSeparate") else "/"
        mnt = mount_uuid(uuid or "")
        if not mnt:
            status["files"] = {"state": "error", "detail": "old disk not found"}
            return True
        home = sp.get("homeAtScan") or "/home/" + manifest["settings"]["user"]["name"]
        rel = os.path.relpath(home, mount_target or "/")
        src_root = os.path.join(mnt + _subvol(opts), rel)

    copied, errors = copy_into(src_root, rels, dest, pw.pw_uid, pw.pw_gid)
    if os.path.ismount(SRC):
        subprocess.run(["umount", SRC])
    status["files"] = {"state": "done", "copied": copied, "errors": errors[:50]}
    return True


def restore_flatpaks(manifest, status):
    ids = sorted({a["target"] for a in manifest.get("apps", [])
                  if a.get("selected") and a.get("kind") == "flatpak"})
    if not ids or not shutil.which("flatpak"):
        status["flatpak"] = {"state": "skipped" if not ids else "no-flatpak", "ids": ids}
        return True
    subprocess.run(["flatpak", "remote-add", "--if-not-exists", "--system", "flathub",
                    "https://dl.flathub.org/repo/flathub.flatpakrepo"])
    failed = []
    for i in ids:
        if subprocess.run(["flatpak", "install", "-y", "--noninteractive", "--system", "flathub", i]).returncode != 0:
            failed.append(i)
    if len(failed) == len(ids):   # probably offline: try again next boot
        status["flatpak"] = {"state": "retry", "failed": failed}
        return False
    status["flatpak"] = {"state": "done", "failed": failed}
    return True


def system():
    manifest = load("manifest.json")
    user = load("user", "")
    if not manifest or not user:
        return 0
    status = load("status.json", {}) or {}
    # wait a little for the network on the first boot
    for _ in range(30):
        if subprocess.run(["nm-online", "-q", "-t", "2"]).returncode == 0:
            break
        time.sleep(1)
    done_files = status.get("files", {}).get("state") in ("done", "skipped") or restore_files(manifest, user, status)
    save_status(status)
    done_flat = status.get("flatpak", {}).get("state") in ("done", "skipped") or restore_flatpaks(manifest, status)
    save_status(status)
    if done_files and done_flat:
        try:
            os.remove(os.path.join(STATE, "pending"))
        except OSError:
            pass
        subprocess.run(["systemctl", "disable", "genesi-migrate-restore.service"])
    return 0


TERMINALS = (["konsole", "-e"], ["gnome-terminal", "--"], ["kgx", "--"], ["ptyxis", "--"],
             ["xfce4-terminal", "-x"], ["kitty"], ["foot"], ["alacritty", "-e"],
             ["cosmic-term", "-e"], ["lxterminal", "-e"], ["xterm", "-e"])


def user():
    marker = os.path.expanduser("~/.local/state/genesi-migrate-done")
    if os.path.exists(marker):
        return 0
    manifest = load("manifest.json")
    if not manifest:
        return 0
    status = load("status.json", {}) or {}
    report = load("install-report.json", {}) or {}
    aur = sorted({a["target"] for a in manifest.get("apps", []) if a.get("selected") and a.get("kind") == "aur"})
    pt = (manifest["choices"].get("language") or "").startswith("pt")

    if status.get("files", {}).get("state") == "waiting-drive":
        notify(pt, "Conecte o disco externo com seus arquivos e reinicie: o Genesi Migrate copia tudo no próximo início."
               if pt else "Plug in the external drive with your files and restart: Genesi Migrate copies them on the next boot.")
        return 0                                # come back next login

    if aur and shutil.which("paru"):
        script = ("echo; echo '%s'; echo; paru -S --needed %s; echo; read -p '%s' _" %
                  ("Genesi Migrate: instalando apps do AUR" if pt else "Genesi Migrate: installing AUR apps",
                   " ".join(aur), "Enter para fechar " if pt else "Enter to close "))
        for term in TERMINALS:
            if shutil.which(term[0]):
                subprocess.Popen(term + ["sh", "-c", script], start_new_session=True)
                break

    missing = report.get("pacmanMissing", []) + status.get("flatpak", {}).get("failed", [])
    copied = status.get("files", {}).get("copied", 0)
    msg = ("Migração concluída. %d arquivos copiados." % copied) if pt else ("Migration done. %d files copied." % copied)
    if missing:
        msg += (" Não encontrados: " if pt else " Not found: ") + ", ".join(missing[:8])
    notify(pt, msg)
    os.makedirs(os.path.dirname(marker), exist_ok=True)
    open(marker, "w").close()
    return 0


def notify(pt, text):
    if shutil.which("notify-send"):
        subprocess.run(["notify-send", "-a", "Genesi Migrate", "-i", "system-software-install",
                        "Genesi Migrate", text])


if __name__ == "__main__":
    sys.exit(system() if "--system" in sys.argv else user())
