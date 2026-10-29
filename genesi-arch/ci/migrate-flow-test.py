#!/usr/bin/env python3
"""
The Genesi Migrate pipeline after the screen: the restart, the installer, the
restore. None of it can run on a CI runner for real -- it formats disks and
reboots machines -- so every piece is built as a pure planning function and
this test plays each against the situations that break it:

  stage     the ISO goes where it SURVIVES the install; when only the old
            system partition is left, the ISO must be loaded into RAM, and a
            machine without the RAM is refused before anything is downloaded;
            GRUB/archiso paths are relative to the FILESYSTEM (a partition
            mounted at /home, a btrfs subvolume), not to this system's view
  download  a cut download resumes with a Range request; a server that
            ignores the Range starts over instead of appending garbage
  copy      files reach the external drive with their tree; a resumed copy
            skips what is already there; symlinks stay links
  calamares the migration setup is generated from Genesi's REAL Calamares
            files (no partition page, our jobs in, one desktop only), and a
            failure halfway leaves nothing rewritten
  disk      every install mode's commands; the disk is found by serial even
            when the live system calls it by another name; nothing is
            formatted when the chosen disk is busy; BIOS+GPT without a BIOS
            boot partition is refused; the shrink math keeps the old system
            its size and starts Genesi on a MiB boundary after it
  restore   only names the repos have go to pacman; the first-boot copy finds
            every selected row
"""
import importlib.util
import io
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
APP = os.path.join(ROOT, "genesi-migrate", "app")
LIVE = os.path.join(ROOT, "archiso", "airootfs", "usr", "lib", "genesi-migrate")
CALA = os.path.join(ROOT, "..", "genesi-calamares-config-full", "etc", "calamares")
sys.path.insert(0, APP)

import stage  # noqa: E402

FAILS = []
GIB = 1024 ** 3


def check(cond, what):
    if not cond:
        FAILS.append(what)
        print("  FAIL", what)


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def manifest(mode="replace", strategy="none", ram=16 * GIB, home_sep=False, root_fs="ext4",
             root_opts="rw,relatime"):
    sysdisk = {"device": "/dev/nvme0n1", "system": True, "home": not home_sep, "serial": "S1", "size": 500 * GIB,
               "partitions": [{"device": "/dev/nvme0n1p1", "uuid": "ESP-1", "fstype": "vfat"},
                              {"device": "/dev/nvme0n1p2", "uuid": "root-uuid", "fstype": root_fs}]
               + ([{"device": "/dev/nvme0n1p3", "uuid": "home-uuid", "fstype": "ext4"}] if home_sep else [])}
    other = {"device": "/dev/sdb", "system": False, "home": False, "serial": "S2", "size": 1000 * GIB,
             "partitions": [{"device": "/dev/sdb1", "uuid": "data-uuid", "fstype": "ntfs"}]}
    usb = {"device": "/dev/sda", "system": False, "home": False, "serial": "S3", "size": 2000 * GIB,
           "partitions": [{"device": "/dev/sda1", "uuid": "usb-uuid", "fstype": "exfat"}]}
    disk = {"replace": "/dev/nvme0n1", "alongside": "/dev/nvme0n1", "disk": "/dev/sdb"}[mode]
    return {
        "machine": {"disks": [sysdisk, other, usb], "rootDevice": "/dev/nvme0n1p2", "rootUuid": "root-uuid",
                    "rootFs": root_fs, "rootOptions": root_opts, "ramBytes": ram,
                    "homeSeparate": home_sep, "homeUuid": "home-uuid" if home_sep else "",
                    "homeDevice": "/dev/nvme0n1p3" if home_sep else "/dev/nvme0n1p2",
                    "homeFs": "ext4", "homeMount": "/home" if home_sep else "/", "homeOptions": "rw",
                    "externals": [{"device": "/dev/sda1", "mountpoint": "/media/ana/USB", "free": 900 * GIB}]},
        "choices": {"strategy": strategy, "install": {"mode": mode, "disk": disk}, "selectedBytes": 10 * GIB},
    }


def stage_cases():
    print("stage")
    p = stage.plan(manifest("replace", "external:/dev/sda1"), "/home/ana")
    check(p["uuid"] == "usb-uuid" and not p["copytoram"] and not p["needsRoot"],
          "external drive: the ISO waits there, no RAM needed")
    check(p["isoRel"] == "/genesi-migrate/genesi.iso", "path is relative to the drive (got %s)" % p["isoRel"])
    check(p["filesRel"] == "/genesi-migrate/home", "the files' path is relative to the drive too")

    p = stage.plan(manifest("replace", "keep-home", home_sep=True), "/home/ana")
    check(p["uuid"] == "home-uuid" and not p["copytoram"], "keep-home: the ISO waits on the /home partition")
    check(p["isoRel"] == "/ana/.genesi-migrate/genesi.iso",
          "a partition mounted at /home: GRUB sees /ana/..., not /home/ana/... (got %s)" % p["isoRel"])

    p = stage.plan(manifest("replace", "none"), "/home/ana")
    check(p["copytoram"] and p["needsRoot"] and p["uuid"] == "root-uuid",
          "replace with nothing kept: the ISO sits on the partition being formatted -> RAM")
    try:
        stage.plan(manifest("replace", "none", ram=4 * GIB), "/home/ana")
        check(False, "4 GB of RAM cannot hold the ISO: refused before downloading")
    except stage.StageError as e:
        check(e.key == "st.ram", "the refusal says why (got %s)" % e.key)

    p = stage.plan(manifest("disk", "stay"), "/home/ana")
    check(not p["copytoram"] and p["uuid"] == "root-uuid", "Genesi on another disk: the old system partition survives")

    p = stage.plan(manifest("alongside", "stay"), "/home/ana")
    check(p["copytoram"], "alongside: the old partition is SHRUNK while the ISO would sit on it -> RAM")

    p = stage.plan(manifest("disk", "stay", root_fs="btrfs", root_opts="rw,subvol=/@"), "/home/ana")
    check(p["isoRel"] == "/@/var/lib/genesi-migrate/genesi.iso",
          "btrfs: the subvolume is part of the path GRUB sees (got %s)" % p["isoRel"])

    try:
        stage.plan(manifest("replace", "none", root_fs="zfs"), "/home/ana")
        check(False, "a filesystem GRUB can't read can't hold the ISO")
    except stage.StageError as e:
        check(e.key == "st.fs", "... and says which filesystem")

    entry = stage.grub_entry(stage.plan(manifest("replace", "none"), "/home/ana"))
    check("search --no-floppy --fs-uuid --set=root root-uuid" in entry, "GRUB finds the filesystem by UUID")
    check("copytoram=y" in entry and "img_dev=UUID=root-uuid" in entry, "archiso gets img_dev + copytoram")
    check("genesi.migrate=UUID=root-uuid:/var/lib/genesi-migrate/stage" in entry, "the live system is told where the stage is")
    check("--id genesi-migrate" in entry, "the entry has the id grub-reboot picks")
    check("insmod all_video" in entry and "gfxpayload=" in entry
          and entry.index("gfxpayload=") < entry.index("    linux "),
          "the kernel gets a framebuffer (black screen on BIOS VMs without it)")
    check(" quiet" not in entry, "boot messages stay visible: the entry runs once and its text is the only clue")
    import shutil
    import subprocess
    if shutil.which("grub-script-check"):
        with tempfile.NamedTemporaryFile("w", suffix=".cfg", delete=False, newline="\n") as f:
            f.write(entry)
        r = subprocess.run(["grub-script-check", f.name], capture_output=True, text=True)
        os.unlink(f.name)
        check(r.returncode == 0, "GRUB parses the entry (%s)" % (r.stderr or r.stdout).strip())
    else:
        print("  grub-script-check not installed, GRUB syntax not checked")
    check(stage.KERNEL in entry and stage.INITRD in entry, "kernel and initramfs paths are the ISO's")
    iso_cfg = open(os.path.join(ROOT, "archiso", "grub", "loopback.cfg"), encoding="utf-8").read()
    check("vmlinuz-linux-cachyos-lts" in iso_cfg and "initramfs-linux-cachyos-lts.img" in iso_cfg,
          "the ISO still boots the kernel stage.py names")


class FakeResp(io.BytesIO):
    def __init__(self, data, status, length):
        super().__init__(data)
        self.status = status
        self.headers = {"Content-Length": str(length)}

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


def download_cases():
    print("download")
    data = bytes(range(256)) * 4096          # 1 MiB
    with tempfile.TemporaryDirectory() as tmp:
        dest = os.path.join(tmp, "g.iso")
        with open(dest + ".part", "wb") as f:
            f.write(data[:300000])
        seen = []

        def opener(req, timeout=0):
            rng = req.headers.get("Range")
            seen.append(rng)
            start = int(rng.split("=")[1].rstrip("-")) if rng else 0
            response = FakeResp(data[start:], 206 if rng else 200, len(data) - start)
            if rng:
                response.headers["Content-Range"] = "bytes %d-%d/%d" % (start, len(data) - 1, len(data))
            return response
        stage.download(dest, lambda *a: None, lambda: False, opener)
        check(seen == ["bytes=300000-"], "a cut download resumes with Range (got %r)" % seen)
        check(open(dest, "rb").read() == data, "the resumed file is byte-identical")

        with open(dest + ".part", "wb") as f:
            f.write(b"junk" * 1000)
        stage.download(dest, lambda *a: None, lambda: False,
                       lambda req, timeout=0: FakeResp(data, 200, len(data)))
        check(open(dest, "rb").read() == data, "a server ignoring Range restarts instead of appending")
        check(stage.sha256_of(dest) == __import__("hashlib").sha256(data).hexdigest(), "sha256_of")


def network_cases():
    print("network")
    # The AppImage's manylinux Python looks for CA certificates where its own
    # build put them: CERTIFICATE_VERIFY_FAILED on Mint. The distro's bundle
    # must be found instead.
    picked = []

    def exists(path):
        picked.append(path)
        return path == "/etc/pki/tls/certs/ca-bundle.crt"
    try:
        stage.ssl_context(exists)
    except (OSError, Exception):
        pass   # the file isn't really there on the runner; which one was tried is the point
    check(picked[:2] == ["/etc/ssl/certs/ca-certificates.crt", "/etc/pki/tls/certs/ca-bundle.crt"],
          "Debian/Ubuntu/Mint's bundle first, then Fedora's (got %r)" % picked[:2])
    # Cloudflare (R2) answers Python's default user agent with 403.
    sent = {}

    class Fake:
        @staticmethod
        def urlopen(req, timeout=0, context=None):
            sent["ua"] = req.get_header("User-agent")
            sent["ctx"] = context
            return None
    real = stage.urllib.request.urlopen
    stage.urllib.request.urlopen = Fake.urlopen
    try:
        stage.urlopen(stage.SHA_URL)
    finally:
        stage.urllib.request.urlopen = real
    check((sent.get("ua") or "").startswith("GenesiMigrate/"), "requests carry our user agent, not Python-urllib")
    check(sent.get("ctx") is not None, "requests use the distro-aware SSL context")


def copy_cases():
    print("copy")
    with tempfile.TemporaryDirectory() as tmp:
        home, dest = os.path.join(tmp, "home"), os.path.join(tmp, "usb")
        os.makedirs(os.path.join(home, "Documentos", "sub"))
        open(os.path.join(home, "Documentos", "sub", "a.txt"), "w").write("hello")
        os.makedirs(os.path.join(home, ".ssh"))
        open(os.path.join(home, ".ssh", "id"), "w").write("key")
        open(os.path.join(home, "loose.txt"), "w").write("x")
        if hasattr(os, "symlink"):
            try:
                os.symlink("sub/a.txt", os.path.join(home, "Documentos", "link"))
            except OSError:
                pass
        m = {"files": [
            {"id": "documents", "path": os.path.join(home, "Documentos"), "selected": True},
            {"id": "keys", "path": home, "paths": [".ssh"], "selected": True},
            {"id": "other", "path": home, "names": ["loose.txt"], "allNames": ["loose.txt"], "selected": True},
            {"id": "music", "path": os.path.join(home, "Music"), "selected": True},
            {"id": "steam", "path": home, "paths": [".local/share/Steam"], "selected": False},
        ]}
        pairs = stage.sources(m, home)
        rels = sorted(r for _, r in pairs)
        check(rels == sorted(["Documentos", ".ssh", "loose.txt"]), "every selected row that exists (got %r)" % rels)
        errs = stage.copy_tree(pairs, dest, lambda *a: None, lambda: False)
        check(not errs, "no copy errors (%r)" % errs)
        check(open(os.path.join(dest, "Documentos", "sub", "a.txt")).read() == "hello", "the tree arrives")
        if os.path.lexists(os.path.join(home, "Documentos", "link")):
            check(os.path.islink(os.path.join(dest, "Documentos", "link")), "a symlink stays a link")
        calls = []
        stage.copy_tree(pairs, dest, lambda d, t: calls.append((d, t)), lambda: False)
        check(calls and calls[-1][0] == calls[-1][1], "a second run counts everything as done (resume)")


def calamares_cases():
    print("calamares")
    cc = load("calamares_config", os.path.join(LIVE, "calamares_config.py"))
    if not os.path.isdir(CALA):
        print("  genesi-calamares-config-full not checked out, skipped")
        return
    with tempfile.TemporaryDirectory() as tmp:
        import shutil
        shutil.copytree(CALA, os.path.join(tmp, "cal"))
        d = os.path.join(tmp, "cal")
        m = {"settings": {"user": {"name": "ana", "fullName": "Ana Souza"}, "timezone": "America/Sao_Paulo"},
             "choices": {"desktop": "GNOME-Desktop"}}
        cc.apply(m, d)
        s = open(os.path.join(d, "settings.conf"), encoding="utf-8").read()
        show = s.split("- exec:")[0]
        execp = s.split("- exec:")[1]
        check("- partition" not in show, "no partitioning page")
        check("- genesimigratedisk" in execp and "- partition\n" not in execp, "our disk job replaces `partition`")
        check(execp.index("genesimigraterestore") < execp.index("- umount"), "restore runs before umount")
        check(execp.index("genesimigratedisk") < execp.index("- mount"), "the disk is ready before mount")
        check("/usr/lib/genesi-migrate/calamares" in s, "Calamares looks for our modules")
        pc = open(os.path.join(d, "modules", "packagechooser.conf"), encoding="utf-8").read()
        ids = [l for l in pc.splitlines() if l.strip().startswith("- id:")]
        check(ids == ["    - id: GNOME-Desktop"], "ONE desktop offered, so none can leak in (got %r)" % ids)
        check('default: "GNOME-Desktop"' in pc, "... and it is the default")
        u = open(os.path.join(d, "modules", "users.conf"), encoding="utf-8").read()
        check('value: "Ana Souza"' in u and 'value: "ana"' in u, "name and login pre-filled")
        loc = open(os.path.join(d, "modules", "locale.conf"), encoding="utf-8").read()
        check('zone: "Sao_Paulo"' in loc, "time zone from the old system")

        shutil.rmtree(d)
        shutil.copytree(CALA, d)
        before = open(os.path.join(d, "settings.conf"), encoding="utf-8").read()
        try:
            cc.apply(dict(m, choices={"desktop": "NotADesktop"}), d)
            check(False, "an unknown desktop is an error")
        except ValueError:
            pass
        check(open(os.path.join(d, "settings.conf"), encoding="utf-8").read() == before,
              "a failure halfway rewrites nothing")
    for mod in ("genesimigratedisk", "genesimigraterestore"):
        desc = open(os.path.join(LIVE, "calamares", mod, "module.desc"), encoding="utf-8").read()
        check('name:       "%s"' % mod in desc and 'interface:  "python"' in desc, "%s module.desc" % mod)


def lsblk(renamed=False):
    """The live system's view. renamed: the NVMe/SATA order swapped names."""
    # On the old system the SATA disk was sdb and the USB disk sda.
    a, b = ("sda", "sdb") if renamed else ("sdb", "sda")
    return [
        {"name": "nvme0n1", "path": "/dev/nvme0n1", "type": "disk", "size": 500 * GIB, "serial": "S1",
         "pttype": "gpt", "children": [
             {"name": "nvme0n1p1", "path": "/dev/nvme0n1p1", "type": "part", "uuid": "ESP-1",
              "parttype": "C12A7328-F81F-11D2-BA4B-00A0C93EC93B", "fstype": "vfat"},
             {"name": "nvme0n1p2", "path": "/dev/nvme0n1p2", "type": "part", "uuid": "root-uuid",
              "fstype": "ext4"},
             {"name": "nvme0n1p3", "path": "/dev/nvme0n1p3", "type": "part", "uuid": "home-uuid",
              "fstype": "ext4"}]},
        {"name": a, "path": "/dev/" + a, "type": "disk", "size": 1000 * GIB, "serial": "S2", "pttype": "gpt",
         "children": [{"name": a + "1", "path": "/dev/%s1" % a, "type": "part", "uuid": "data-uuid", "fstype": "ntfs"}]},
        {"name": b, "path": "/dev/" + b, "type": "disk", "size": 2000 * GIB, "serial": "S3", "pttype": "gpt",
         "children": [{"name": b + "1", "path": "/dev/%s1" % b, "type": "part", "uuid": "usb-uuid", "fstype": "exfat",
                       "mountpoints": ["/run/archiso/img_dev"]}]},
    ]


def flat(cmds):
    return [" ".join(c["cmd"] if isinstance(c, dict) and "cmd" in c else c) for c in cmds
            if not (isinstance(c, dict) and c.get("newPartition"))]


def disk_cases():
    print("disk")
    dm = load("genesimigratedisk", os.path.join(LIVE, "calamares", "genesimigratedisk", "main.py"))
    inst = {"mode": "disk", "disk": "/dev/sdb", "diskSerial": "S2", "diskSize": 1000 * GIB}
    p = dm.plan(inst, "efi", lsblk(renamed=True))
    c = flat(p["commands"])
    check(p["disk"] == "/dev/sda", "found by serial although the live system renamed it sdb -> sda")
    check(any(x.startswith("wipefs --all --force /dev/sda") for x in c), "the whole disk is wiped")
    check("mkfs.vfat -F 32 -n EFI /dev/sda1" in c and "mkfs.btrfs -f -L genesi /dev/sda2" in c, "EFI + btrfs")
    check([x["mountPoint"] for x in p["partitions"]] == ["/", "/boot/efi"], "root and ESP roles")
    check(not any("nvme0n1" in x for x in c), "nothing touches the system disk")

    p = dm.plan(inst, "bios", lsblk())
    layout = next(x["input"] for x in p["commands"] if isinstance(x, dict) and "input" in x)
    check(dm.BIOS_BOOT_GUID in layout, "BIOS: a BIOS boot partition for GRUB")
    check(all(x["mountPoint"] != "/boot/efi" for x in p["partitions"]), "BIOS: no ESP")

    try:
        dm.plan({"mode": "disk", "diskSerial": "S3", "diskSize": 2000 * GIB}, "efi", lsblk())
        check(False, "a disk holding the mounted ISO is refused")
    except dm.PlanError:
        pass
    try:
        dm.plan({"mode": "disk", "diskSerial": "NOPE", "diskSize": 123}, "efi", lsblk())
        check(False, "an unknown disk is refused")
    except dm.PlanError:
        pass

    rep = {"mode": "replace", "diskSerial": "S1", "diskSize": 500 * GIB, "rootUuid": "root-uuid",
           "espUuid": "ESP-1", "homeUuid": "home-uuid"}
    p = dm.plan(rep, "efi", lsblk())
    c = flat(p["commands"])
    check("mkfs.btrfs -f -L genesi /dev/nvme0n1p2" in c, "replace formats the old system partition")
    check(not any("nvme0n1p1" in x or "nvme0n1p3" in x for x in c), "... and nothing else")
    roles = {x["mountPoint"]: x for x in p["partitions"]}
    check(roles["/boot/efi"]["claimed"] is False and roles["/home"]["claimed"] is False,
          "the ESP and the kept /home are mounted, not formatted")
    check(p["osProber"], "replace keeps other systems in the boot menu")

    bios_gpt = lsblk()
    try:
        dm.plan(dict(rep, homeUuid=""), "bios", bios_gpt)
        check(False, "BIOS + GPT without a BIOS boot partition is refused")
    except dm.PlanError:
        pass

    table = {"label": "gpt", "partitions": [
        {"node": "/dev/nvme0n1p1", "start": 2048, "size": 1048576},
        {"node": "/dev/nvme0n1p2", "start": 1050624, "size": 400 * GIB // 512}]}
    al = {"mode": "alongside", "diskSerial": "S1", "diskSize": 500 * GIB, "rootUuid": "root-uuid",
          "espUuid": "ESP-1", "genesiBytes": 150 * GIB}
    p = dm.plan(al, "efi", lsblk(), table)
    shrink = next(x for x in p["commands"] if isinstance(x, dict) and x.get("cmd", [""])[0] == "sfdisk" and "-N" in x["cmd"])
    start, keep = (int(v) for v in shrink["input"].strip().split(","))
    check(start == 1050624, "the old partition keeps its start")
    check(keep * 512 == 250 * GIB, "the old system keeps 400-150 = 250 GiB (got %.1f)" % (keep * 512 / GIB))
    new = next(x for x in p["commands"] if isinstance(x, dict) and x.get("newPartition"))
    check(new["start"] % 2048 == 0 and new["start"] >= start + keep, "Genesi starts on a MiB boundary after it")
    c = flat(p["commands"])
    rz = [x for x in c if x.startswith("resize2fs /dev/nvme0n1p2 ")]
    check(rz and int(rz[0].split()[-1].rstrip("K")) * 1024 < keep * 512,
          "the filesystem is shrunk BELOW the new partition size before the partition is cut")
    check(c.index(rz[0]) < next(i for i, x in enumerate(c) if "-N" in x), "shrink fs, then partition")
    check("e2fsck -f -y /dev/nvme0n1p2" in c, "a forced fsck before resize2fs")
    try:
        dm.plan(dict(al, genesiBytes=395 * GIB), "efi", lsblk(), table)
        check(False, "leaving the old system 5 GiB is refused")
    except dm.PlanError:
        pass


def restore_cases():
    print("restore")
    rm = load("genesimigraterestore", os.path.join(LIVE, "calamares", "genesimigraterestore", "main.py"))
    names = rm.wanted_pacman({"apps": [
        {"selected": True, "kind": "pacman", "target": "gimp"},
        {"selected": True, "kind": "pacman", "target": "not-a-package"},
        {"selected": False, "kind": "pacman", "target": "vlc"},
        {"selected": True, "kind": "aur", "target": "google-chrome"}]})
    check(names == ["gimp", "not-a-package"], "selected pacman apps only")
    have, missing = rm.split_available(names, "extra gimp 3.0-1\ncore bash 5.2-1\n")
    check(have == ["gimp"] and missing == ["not-a-package"], "unknown names never reach pacman")
    unit = rm.unit_text()
    check("ConditionPathExists=/var/lib/genesi-migrate/pending" in unit, "the service stops once done")

    try:
        rs = load("restore", os.path.join(LIVE, "restore.py"))
    except ModuleNotFoundError as e:   # pwd: the first-boot script is Linux-only
        print("  restore.py skipped here (%s)" % e)
        return
    rels = rs.selected_rel_paths({"stagePlan": {"homeAtScan": "/home/ana"}, "files": [
        {"id": "documents", "path": "/home/ana/Documentos", "selected": True},
        {"id": "other", "names": ["a"], "allNames": ["a", "b"], "selected": True},
        {"id": "keys", "paths": [".ssh"], "selected": True},
        {"id": "steam", "paths": [".local/share/Steam"], "selected": False}]})
    check(sorted(rels) == sorted(["Documentos", "a", "b", ".ssh"]), "every selected row, all loose folders (got %r)" % rels)


if __name__ == "__main__":
    stage_cases()
    download_cases()
    network_cases()
    copy_cases()
    calamares_cases()
    disk_cases()
    restore_cases()
    if FAILS:
        print("\n%d failure(s)" % len(FAILS))
        sys.exit(1)
    print("\nall good")
