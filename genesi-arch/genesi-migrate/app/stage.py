"""
Genesi Migrate -- getting the machine ready to restart into the installer.

"Prepare migration" does four things, in this order, and only the last one
touches anything outside the user's own folders:

  1. decide WHERE the Genesi ISO and the migration "stage" (the plan, the
     Wi-Fi networks) live until the installer has read them;
  2. download the ISO there, resuming if interrupted, and check it against
     the SHA-256 the ISO pipeline publishes next to it;
  3. copy the chosen files to the external drive, when that is where they
     wait;
  4. (root, one pkexec prompt) save the Wi-Fi networks into the stage, add a
     one-time "Genesi Migrate" entry to this system's GRUB, and pick it for
     the next boot only.

The ISO boots straight from that file: archiso's archiso_loop_mnt hook takes
img_dev=UUID=<fs> img_loop=<path>, the same way the ISO's own loopback.cfg
boots from Ventoy. When the file sits on a partition the install is about to
format or shrink, copytoram=y loads the ISO into RAM first and lets go of the
disk -- which needs the RAM, so that case is checked here, not discovered in
the live system.

Stdlib only (runs on the old distro).
"""
import hashlib
import json
import os
import shutil
import ssl
import time
import urllib.request

ISO_URL = "https://pub-917a3befc9e640f0acf8eb3d52633fe2.r2.dev/genesi-os-latest.iso"
SHA_URL = ISO_URL + ".sha256"
ISO_NAME = "genesi.iso"
STAGE_NAME = "stage"
# Paths inside the ISO (archiso profile: install_dir="arch", see grub/loopback.cfg).
KERNEL = "/arch/boot/x86_64/vmlinuz-linux-cachyos-lts"
INITRD = "/arch/boot/x86_64/initramfs-linux-cachyos-lts.img"
GRUB_ID = "genesi-migrate"
GIB = 1024 ** 3
# What copytoram needs: the squashfs (~3.3 GB) in RAM plus a live desktop and
# an installer. The ISO's own menu says "needs 8GB+"; an 8 GB machine reports
# ~7.6 GiB of MemTotal, hence 7.
COPYTORAM_RAM = 7 * GIB
# A little over the current ISO, so a growing ISO doesn't fail the copy halfway.
ISO_ROOM = int(3.8 * GIB)
# GRUB can read these; anything else can't hold the ISO.
GRUB_FS = {"ext2", "ext3", "ext4", "btrfs", "vfat", "exfat", "ntfs", "xfs", "f2fs"}
GRUB_MODS = {"ext2": "ext2", "ext3": "ext2", "ext4": "ext2", "btrfs": "btrfs", "vfat": "fat",
             "exfat": "exfat", "ntfs": "ntfs", "xfs": "xfs", "f2fs": "f2fs"}


class StageError(Exception):
    """A reason the migration cannot be prepared, as a translation key + args."""

    def __init__(self, key, *args):
        super().__init__(key)
        self.key = key
        self.args_ = args


def _subvol(options):
    for opt in (options or "").split(","):
        if opt.startswith("subvol="):
            sv = opt[len("subvol="):]
            return "" if sv in ("/", "") else "/" + sv.strip("/")
    return ""


def fs_relative(path, mount_target, options):
    """Path as GRUB and archiso see it on the raw filesystem.

    Both open the filesystem itself, not this system's view of it: a file at
    /home/ana/x on a partition mounted at /home is /ana/x there, and on btrfs
    mounted with subvol=/@home it is /@home/ana/x.
    """
    rel = os.path.relpath(path, mount_target)
    rel = "/" if rel == "." else "/" + rel.replace(os.sep, "/")
    rel = _subvol(options) + rel
    return rel.replace("//", "/")


def _find_part(machine, device):
    for d in machine.get("disks", []):
        for p in d.get("partitions", []):
            if p["device"] == device:
                return d, p
    return None, None


def target_disk(manifest):
    inst = manifest["choices"]["install"]
    for d in manifest["machine"].get("disks", []):
        if (inst["mode"] in ("replace", "alongside") and d.get("system")) or d["device"] == inst.get("disk"):
            return d
    return None


def plan(manifest, home):
    """Where the ISO and the stage go. Raises StageError when nowhere works."""
    m = manifest["machine"]
    ch = manifest["choices"]
    mode = ch["install"]["mode"]            # replace | alongside | disk
    strategy = ch["strategy"]               # stay | keep-home | external:/dev/x | none
    tdisk = target_disk(manifest)
    # What the install destroys: a whole disk in "disk" mode, but only the old
    # system partition in replace (formatted) and alongside (shrunk) -- the
    # /home partition next to it survives and is a fine place to wait.
    if mode == "disk":
        on_target = {p["device"] for p in (tdisk or {}).get("partitions", [])}
    else:
        on_target = {m.get("rootDevice")}

    loc = None
    if strategy.startswith("external:"):
        dev = strategy.split(":", 1)[1]
        d, p = _find_part(m, dev)
        ext = next((e for e in m.get("externals", []) if e["device"] == dev), None)
        if not p or not ext or not ext.get("mountpoint"):
            raise StageError("st.extGone")
        loc = {"dir": os.path.join(ext["mountpoint"], "genesi-migrate"), "uuid": p["uuid"],
               "fs": p["fstype"], "mount": ext["mountpoint"], "options": "", "root": False,
               "device": dev, "survives": dev not in on_target}
    elif m.get("homeSeparate") and m.get("homeUuid") and m.get("homeDevice") not in on_target:
        # keep-home, or Genesi on another disk while /home has its own partition
        loc = {"dir": os.path.join(home, ".genesi-migrate"), "uuid": m["homeUuid"], "fs": m.get("homeFs"),
               "mount": m.get("homeMount") or "/home", "options": m.get("homeOptions", ""), "root": False,
               "device": m.get("homeDevice"), "survives": True}
    else:
        # The old system partition. It survives only when Genesi goes to
        # another disk; otherwise it is formatted (replace) or shrunk
        # (alongside), and the ISO has to be in RAM by then.
        survives = mode == "disk" and m.get("rootDevice") not in on_target
        loc = {"dir": "/var/lib/genesi-migrate", "uuid": m.get("rootUuid", ""), "fs": m.get("rootFs"),
               "mount": "/", "options": m.get("rootOptions", ""), "root": True,
               "device": m.get("rootDevice"), "survives": survives}

    if not loc["uuid"]:
        raise StageError("st.noUuid")
    if loc["fs"] not in GRUB_FS:
        raise StageError("st.fs", loc["fs"] or "?")
    copytoram = not loc["survives"]
    if copytoram and (m.get("ramBytes") or 0) < COPYTORAM_RAM:
        raise StageError("st.ram", round((m.get("ramBytes") or 0) / GIB, 1), round(COPYTORAM_RAM / GIB))

    iso = os.path.join(loc["dir"], ISO_NAME)
    stage = os.path.join(loc["dir"], STAGE_NAME)
    return {
        "dir": loc["dir"], "iso": iso, "stage": stage, "needsRoot": loc["root"],
        "uuid": loc["uuid"], "fs": loc["fs"], "copytoram": copytoram,
        "isoRel": fs_relative(iso, loc["mount"], loc["options"]),
        "stageRel": fs_relative(stage, loc["mount"], loc["options"]),
        "filesDir": os.path.join(loc["dir"], "home") if strategy.startswith("external:") else "",
        "filesRel": fs_relative(os.path.join(loc["dir"], "home"), loc["mount"], loc["options"])
                    if strategy.startswith("external:") else "",
    }


def grub_entry(p):
    """The one-time GRUB menu entry. Plain GRUB script, no distro helpers."""
    mods = ["part_gpt", "part_msdos", "lvm", "loopback", "iso9660", "search_fs_uuid",
            GRUB_MODS.get(p["fs"], "ext2")]
    lines = ["menuentry 'Genesi Migrate' --id %s {" % GRUB_ID]
    lines += ["    insmod %s" % mod for mod in mods]
    lines += [
        "    search --no-floppy --fs-uuid --set=root %s" % p["uuid"],
        "    set isofile='%s'" % p["isoRel"],
        '    loopback loop "$isofile"',
        "    linux (loop)%s archisobasedir=arch img_dev=UUID=%s img_loop=\"$isofile\" "
        "cow_spacesize=10G copytoram=%s genesi.migrate=UUID=%s:%s "
        "quiet splash module_blacklist=pcspkr,vmwgfx nvme_load=yes"
        % (KERNEL, p["uuid"], "y" if p["copytoram"] else "n", p["uuid"], p["stageRel"]),
        "    initrd (loop)%s" % INITRD,
        "}",
    ]
    return "\n".join(lines) + "\n"


# ── the download ────────────────────────────────────────────────────────
# Where each distro keeps its CA bundle. The AppImage's Python was built on
# manylinux, and its OpenSSL looks for certificates where THAT build put them
# -- a path that exists on no user's machine -- so every HTTPS request failed
# with CERTIFICATE_VERIFY_FAILED (first seen on Linux Mint 22.3). The system's
# own bundle is used instead; certifi, bundled in the AppImage, is the last resort.
CA_BUNDLES = (
    "/etc/ssl/certs/ca-certificates.crt",                 # Debian, Ubuntu, Mint, Arch, Gentoo
    "/etc/pki/tls/certs/ca-bundle.crt",                   # Fedora, RHEL
    "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem",  # Fedora, RHEL (newer)
    "/etc/ssl/ca-bundle.pem",                             # openSUSE
    "/var/lib/ca-certificates/ca-bundle.pem",             # openSUSE
    "/etc/ssl/cert.pem",                                  # Alpine, Void, macOS-likes
)


def ssl_context(exists=os.path.isfile):
    for path in CA_BUNDLES:
        if exists(path):
            return ssl.create_default_context(cafile=path)
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        return ssl.create_default_context()


# Cloudflare (R2's public endpoint) answers Python's default
# "Python-urllib/3.x" user agent with 403 Forbidden, while curl and browsers
# get the file. Say who we are.
USER_AGENT = "GenesiMigrate/2 (+https://genesios.org/migrate)"


def urlopen(req, timeout=60):
    if isinstance(req, str):
        req = urllib.request.Request(req)
    req.add_header("User-Agent", USER_AGENT)
    return urllib.request.urlopen(req, timeout=timeout, context=ssl_context())


def expected_sha(opener=urlopen):
    with opener(SHA_URL, timeout=30) as r:
        return r.read().decode("ascii", "replace").split()[0].strip().lower()


def remote_size(opener=urlopen):
    req = urllib.request.Request(ISO_URL, method="HEAD")
    with opener(req, timeout=30) as r:
        return int(r.headers.get("Content-Length") or 0)


def download(dest, progress, cancelled, opener=urlopen):
    """Download to dest (resuming a .part). progress(done, total, bytes_per_s)."""
    part = dest + ".part"
    done = os.path.getsize(part) if os.path.exists(part) else 0
    req = urllib.request.Request(ISO_URL)
    if done:
        req.add_header("Range", "bytes=%d-" % done)
    with opener(req, timeout=60) as r:
        status = getattr(r, "status", 200)
        if done and status != 206:   # server ignored the range: start over
            done = 0
        total = done + int(r.headers.get("Content-Length") or 0)
        mode = "ab" if done else "wb"
        t0, d0 = time.monotonic(), done
        with open(part, mode) as f:
            while True:
                if cancelled():
                    raise StageError("st.cancelled")
                chunk = r.read(1 << 20)
                if not chunk:
                    break
                f.write(chunk)
                done += len(chunk)
                dt = time.monotonic() - t0
                progress(done, total, (done - d0) / dt if dt > 0.5 else 0)
    if total and done != total:
        raise StageError("st.short")
    os.replace(part, dest)


def sha256_of(path, progress=lambda d, t: None, cancelled=lambda: False):
    h, total, done = hashlib.sha256(), os.path.getsize(path), 0
    with open(path, "rb") as f:
        while True:
            if cancelled():
                raise StageError("st.cancelled")
            b = f.read(4 << 20)
            if not b:
                break
            h.update(b)
            done += len(b)
            progress(done, total)
    return h.hexdigest()


# ── the files, when they wait on an external drive ──────────────────────
def sources(manifest, home):
    """(absolute path, path relative to home) for every selected file row."""
    out = []
    for item in manifest["files"]:
        if not item.get("selected"):
            continue
        if item["id"] == "other":
            for name in item.get("allNames") or item.get("names") or []:
                out.append(os.path.join(home, name))
        elif item.get("paths"):
            out += [os.path.join(home, rel) for rel in item["paths"]]
        else:
            out.append(item["path"])
    return [(p, os.path.relpath(p, home)) for p in out if os.path.lexists(p)]


def copy_tree(pairs, dest_root, progress, cancelled, skip=()):
    """Copy, keeping symlinks as links and times as they were. Returns errors."""
    total = 0
    for src, _ in pairs:
        if os.path.isdir(src) and not os.path.islink(src):
            for dp, dns, fns in os.walk(src):
                dns[:] = [d for d in dns if os.path.join(dp, d) not in skip]
                for fn in fns:
                    try:
                        total += os.lstat(os.path.join(dp, fn)).st_size
                    except OSError:
                        pass
        else:
            try:
                total += os.lstat(src).st_size
            except OSError:
                pass
    done, errors = 0, []

    def one(s, d):
        nonlocal done
        if cancelled():
            raise StageError("st.cancelled")
        try:
            if os.path.islink(s):
                if not os.path.lexists(d):
                    os.symlink(os.readlink(s), d)
                done += os.lstat(s).st_size      # counted in the total too
            elif os.path.isfile(s):
                # same size + mtime already there: a resumed copy, skip it
                if os.path.exists(d):
                    a, b = os.stat(s), os.stat(d)
                    if a.st_size == b.st_size and int(a.st_mtime) == int(b.st_mtime):
                        done += a.st_size
                        progress(done, total)
                        return
                shutil.copy2(s, d)
                done += os.path.getsize(s)
        except OSError as e:
            errors.append("%s: %s" % (s, e.strerror or e))
        progress(done, total)

    for src, rel in pairs:
        dst = os.path.join(dest_root, rel)
        if os.path.isdir(src) and not os.path.islink(src):
            for dp, dns, fns in os.walk(src):
                dns[:] = [d for d in dns if os.path.join(dp, d) not in skip]
                tgt = os.path.join(dst, os.path.relpath(dp, src))
                os.makedirs(tgt, exist_ok=True)
                for fn in fns:
                    one(os.path.join(dp, fn), os.path.join(tgt, fn))
        else:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            one(src, dst)
    return errors


def write_stage(manifest, p, home):
    os.makedirs(p["stage"], exist_ok=True)
    data = dict(manifest)
    data["stagePlan"] = dict(p, homeAtScan=home)
    path = os.path.join(p["stage"], "manifest.json")
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)
    return path
