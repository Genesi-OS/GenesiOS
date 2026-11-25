#!/usr/bin/env python3
"""
genesimigratedisk -- the partitioning step of a Genesi Migrate install.

Replaces Calamares' `partition` module (page AND job) when the ISO was booted
by Genesi Migrate. The user already chose, on their old system, where Genesi
goes; this does it, then fills GlobalStorage exactly the way the partition
module's FillGlobalStorageJob does, so mount / fstab / bootloader / grubcfg
run unchanged after it.

Three modes, from manifest["choices"]["install"]:

  disk       erase a whole disk: GPT, a 1 GiB EFI partition (UEFI) or a 1 MiB
             bios_grub one (BIOS), the rest btrfs
  replace    format only the old system partition as btrfs; reuse the existing
             EFI partition (Windows' boot manager stays) and, for keep-home,
             mount the old /home partition WITHOUT formatting it
  alongside  (v2) shrink the old ext4/btrfs system partition, put Genesi in the
             freed space, reuse the EFI partition; the old system still boots

Device names are never trusted: the live system may call the disk sdb that
was sda. Disks are found by WWN / serial + size, partitions by filesystem UUID.

The ESP is mounted at /boot/efi here, not /boot as in a normal Genesi install:
a reused ESP can be Windows' 100 MB one, where kernels do not fit. With
/boot inside the btrfs root, GRUB reads kernels from btrfs and the ESP only
holds GRUB itself.

plan() is pure (commands + partition roles, no side effects) so CI can check
every mode; run() executes it.
"""
import json
import os
import subprocess

MANIFEST = "/run/genesi-migrate/stage/manifest.json"
ESP_GUID = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
BIOS_BOOT_GUID = "21686148-6449-6e6f-744e-656564454649"
LINUX_GUID = "0fc63daf-8483-4772-8e79-3d69d8477de4"
MIB = 1024 * 1024
GIB = 1024 * MIB
# Keep the shrunk filesystem a little smaller than its partition while
# resizing, then grow it back to fill: never cut a filesystem at its edge.
FS_MARGIN = 256 * MIB


class PlanError(Exception):
    pass


def pretty_name():
    return "Preparing the disk for Genesi"


# ── finding things again ────────────────────────────────────────────────
def walk(nodes):
    for n in nodes or []:
        yield n
        yield from walk(n.get("children"))


def find_disk(install, devices):
    disks = [d for d in devices if d.get("type") == "disk"]
    size = int(install.get("diskSize") or 0)
    for key in ("diskWwn", "diskSerial"):
        want = (install.get(key) or "").strip()
        if not want:
            continue
        field = "wwn" if key == "diskWwn" else "serial"
        hits = [d for d in disks if (d.get(field) or "").strip() == want
                and (not size or int(d.get("size") or 0) == size)]
        if len(hits) == 1:
            return hits[0]
    # No serial (some VMs, some USB bridges): the size must be unique.
    hits = [d for d in disks if size and int(d.get("size") or 0) == size]
    if len(hits) == 1:
        return hits[0]
    raise PlanError("Could not find the disk chosen in Genesi Migrate (%s). Nothing was changed." %
                    (install.get("disk") or "?"))


def find_uuid(devices, uuid, disk=None):
    if not uuid:
        return None
    pool = walk([disk]) if disk else walk(devices)
    for n in pool:
        if (n.get("uuid") or "") == uuid:
            return n
    return None


def mounted(node):
    mps = node.get("mountpoints") or [node.get("mountpoint")]
    return [m for m in mps if m]


def part_node(disk_path, number):
    """/dev/sda + 2 -> /dev/sda2 ; /dev/nvme0n1 + 2 -> /dev/nvme0n1p2."""
    return "%s%s%d" % (disk_path, "p" if disk_path[-1].isdigit() else "", number)


# ── the plan ────────────────────────────────────────────────────────────
def plan(install, firmware, devices, table=None, sector=512):
    """Commands to run and the partitions they leave, by role.

    devices: `lsblk -J -b -o NAME,PATH,TYPE,SIZE,SERIAL,WWN,UUID,PARTTYPE,FSTYPE,MOUNTPOINTS`
             blockdevices list
    table:   `sfdisk -J <disk>` partitiontable of the target disk (alongside)
    """
    mode = install.get("mode")
    efi = firmware == "efi"
    disk = find_disk(install, devices)
    dpath = disk["path"]
    cmds, parts = [], []
    busy = [m for n in walk(disk.get("children")) for m in mounted(n)]

    def esp_on_disk():
        n = find_uuid(devices, install.get("espUuid"), disk)
        if not n:
            n = next((c for c in walk(disk.get("children"))
                      if (c.get("parttype") or "").lower() == ESP_GUID), None)
        if not n:
            raise PlanError("This disk has no EFI partition to share. Install on a whole disk instead.")
        return n

    def bios_ok():
        # GRUB on a GPT disk in BIOS mode needs a BIOS boot partition to sit in.
        if efi or (disk.get("pttype") or "") != "gpt":
            return
        if not any((c.get("parttype") or "").lower() == BIOS_BOOT_GUID for c in walk(disk.get("children"))):
            raise PlanError("This disk boots in BIOS mode from a GPT table without a BIOS boot partition, "
                            "so GRUB has nowhere to go. Install on a whole disk instead.")

    if mode in ("replace", "alongside"):
        bios_ok()

    if mode == "disk":
        if busy:
            raise PlanError("The chosen disk is in use (%s). It may hold the Genesi download; "
                            "pick another disk." % ", ".join(busy))
        if efi:
            layout = "label: gpt\nsize=1GiB, type=%s, name=EFI\ntype=%s, name=genesi\n" % (ESP_GUID, LINUX_GUID)
        else:
            layout = "label: gpt\nsize=1MiB, type=%s\ntype=%s, name=genesi\n" % (BIOS_BOOT_GUID, LINUX_GUID)
        cmds += [["wipefs", "--all", "--force", dpath],
                 {"cmd": ["sfdisk", "--wipe", "always", "--wipe-partitions", "always", dpath], "input": layout},
                 ["udevadm", "settle"]]
        root = part_node(dpath, 2)
        if efi:
            cmds.append(["mkfs.vfat", "-F", "32", "-n", "EFI", part_node(dpath, 1)])
            parts.append({"device": part_node(dpath, 1), "mountPoint": "/boot/efi", "fs": "fat32", "claimed": True})
        cmds.append(["mkfs.btrfs", "-f", "-L", "genesi", root])
        parts.insert(0, {"device": root, "mountPoint": "/", "fs": "btrfs", "claimed": True})

    elif mode == "replace":
        root = find_uuid(devices, install.get("rootUuid"), disk)
        if not root:
            raise PlanError("Could not find the old system partition (UUID %s). Nothing was changed." %
                            install.get("rootUuid"))
        if mounted(root):
            raise PlanError("The old system partition is still in use (%s)." % ", ".join(mounted(root)))
        cmds += [["wipefs", "--all", "--force", root["path"]],
                 ["mkfs.btrfs", "-f", "-L", "genesi", root["path"]]]
        parts.append({"device": root["path"], "mountPoint": "/", "fs": "btrfs", "claimed": True})
        if efi:
            esp = esp_on_disk()
            parts.append({"device": esp["path"], "mountPoint": "/boot/efi", "fs": "fat32", "claimed": False})
        if install.get("homeUuid"):
            home = find_uuid(devices, install["homeUuid"])
            if not home:
                raise PlanError("Could not find your /home partition (UUID %s). Nothing was changed." %
                                install["homeUuid"])
            if home["path"] == root["path"]:
                raise PlanError("/home is on the system partition; it cannot be kept while that is formatted.")
            parts.append({"device": home["path"], "mountPoint": "/home", "fs": home.get("fstype") or "ext4",
                          "claimed": False})

    elif mode == "alongside":
        root = find_uuid(devices, install.get("rootUuid"), disk)
        if not root:
            raise PlanError("Could not find the old system partition (UUID %s)." % install.get("rootUuid"))
        if mounted(root):
            raise PlanError("The old system partition is still in use (%s)." % ", ".join(mounted(root)))
        fs = root.get("fstype")
        if fs not in ("ext4", "btrfs"):
            raise PlanError("Only ext4 or btrfs partitions can be shrunk (this one is %s)." % fs)
        if not table:
            raise PlanError("Could not read the partition table.")
        entry = next((p for p in table.get("partitions", []) if p.get("node") == root["path"]), None)
        if not entry:
            raise PlanError("The old system partition is not in the partition table.")
        number = int(entry["node"][len(dpath):].lstrip("p"))
        start, size = int(entry["start"]), int(entry["size"])
        genesi = int(install.get("genesiBytes") or 0)
        align = MIB // sector
        keep = ((size * sector - genesi) // MIB) * align          # sectors, MiB-aligned
        if genesi < 20 * GIB or keep * sector < 10 * GIB:
            raise PlanError("The sizes chosen for the shrink don't make sense (Genesi %d GiB)." % (genesi // GIB))
        new_start = ((start + keep + align - 1) // align) * align
        end = start + size                                          # first sector after the old partition
        if end - new_start < 20 * GIB // sector:
            raise PlanError("Not enough room left for Genesi after the shrink.")
        keep_bytes = keep * sector
        dev = root["path"]
        if fs == "ext4":
            cmds += [["e2fsck", "-f", "-y", dev],
                     ["resize2fs", dev, "%dK" % ((keep_bytes - FS_MARGIN) // 1024)]]
        else:
            cmds += [["mkdir", "-p", "/run/genesi-migrate/shrink"],
                     ["mount", "-o", "subvolid=5", dev, "/run/genesi-migrate/shrink"],
                     ["btrfs", "filesystem", "resize", str(keep_bytes - FS_MARGIN), "/run/genesi-migrate/shrink"],
                     ["umount", "/run/genesi-migrate/shrink"]]
        cmds += [{"cmd": ["sfdisk", "--no-reread", "-N", str(number), dpath], "input": "%d,%d\n" % (start, keep)},
                 {"cmd": ["sfdisk", "--no-reread", "--append", dpath],
                  "input": "start=%d, size=%d, type=%s\n" % (new_start, end - new_start,
                                                             LINUX_GUID if table.get("label") == "gpt" else "83")},
                 ["partx", "-u", dpath], ["udevadm", "settle"]]
        # grow the old filesystem back to fill its (smaller) partition
        if fs == "ext4":
            cmds += [["e2fsck", "-f", "-y", dev], ["resize2fs", dev]]
        else:
            cmds += [["mount", "-o", "subvolid=5", dev, "/run/genesi-migrate/shrink"],
                     ["btrfs", "filesystem", "resize", "max", "/run/genesi-migrate/shrink"],
                     ["umount", "/run/genesi-migrate/shrink"]]
        cmds.append({"newPartition": True, "disk": dpath, "start": new_start})
        parts.append({"device": "@new", "mountPoint": "/", "fs": "btrfs", "claimed": True})
        if efi:
            esp = esp_on_disk()
            parts.append({"device": esp["path"], "mountPoint": "/boot/efi", "fs": "fat32", "claimed": False})
    else:
        raise PlanError("Unknown install mode %r." % mode)

    return {"disk": dpath, "commands": cmds, "partitions": parts, "efi": efi,
            "osProber": mode in ("alongside", "replace")}


# ── running it ──────────────────────────────────────────────────────────
def _run(cmd, inp=None):
    import libcalamares
    libcalamares.utils.debug("genesimigratedisk: %s" % " ".join(cmd))
    p = subprocess.run(cmd, input=inp, capture_output=True, text=True)
    if p.returncode != 0:
        raise PlanError("%s failed: %s" % (cmd[0], (p.stderr or p.stdout).strip()[-400:]))
    return p.stdout


def _lsblk():
    out = _run(["lsblk", "-J", "-b", "-o", "NAME,PATH,TYPE,SIZE,SERIAL,WWN,UUID,PARTTYPE,FSTYPE,PTTYPE,MOUNTPOINTS"])
    return json.loads(out)["blockdevices"]


def _blkid(dev, tag):
    p = subprocess.run(["blkid", "-s", tag, "-o", "value", dev], capture_output=True, text=True)
    return p.stdout.strip()


def run():
    import libcalamares
    gs = libcalamares.globalstorage
    try:
        with open(MANIFEST, encoding="utf-8") as f:
            manifest = json.load(f)
        install = manifest["choices"]["install"]
        firmware = "efi" if os.path.isdir("/sys/firmware/efi") else "bios"
        devices = _lsblk()
        table = None
        if install.get("mode") == "alongside":
            d = find_disk(install, devices)
            table = json.loads(_run(["sfdisk", "-J", d["path"]]))["partitiontable"]
            sector = int(table.get("sectorsize") or 512)
        else:
            sector = 512
        p = plan(install, firmware, devices, table, sector)

        new_node = None
        steps = p["commands"]
        for i, c in enumerate(steps):
            libcalamares.job.setprogress(i / max(1, len(steps)))
            if isinstance(c, dict) and c.get("newPartition"):
                t = json.loads(_run(["sfdisk", "-J", c["disk"]]))["partitiontable"]
                hit = [x for x in t["partitions"] if int(x["start"]) == c["start"]]
                if len(hit) != 1:
                    raise PlanError("The new partition did not appear.")
                new_node = hit[0]["node"]
                _run(["wipefs", "--all", "--force", new_node])
                _run(["mkfs.btrfs", "-f", "-L", "genesi", new_node])
            elif isinstance(c, dict):
                _run(c["cmd"], c["input"])
            else:
                _run(c)

        # GlobalStorage, the way FillGlobalStorageJob writes it.
        gs_parts = []
        for part in p["partitions"]:
            dev = new_node if part["device"] == "@new" else part["device"]
            gs_parts.append({
                "device": dev,
                "partlabel": _blkid(dev, "PARTLABEL"),
                "partuuid": _blkid(dev, "PARTUUID"),
                "mountPoint": part["mountPoint"],
                "fsName": part["fs"],
                "fs": part["fs"],
                "parttype": "",
                "partattrs": 0,
                "features": {},
                "uuid": _blkid(dev, "UUID"),
                "claimed": part["claimed"],
            })
        gs.insert("partitions", gs_parts)
        gs.insert("firmwareType", firmware)
        gs.insert("efiSystemPartition", "/boot/efi")
        gs.insert("bootLoader", {"installPath": p["disk"]})
        gs.insert("partitionChoices", {"install": "erase", "swap": "none"})
        gs.insert("defaultFileSystemType", "btrfs")
        gs.insert("genesiMigrateOsProber", p["osProber"])
        libcalamares.job.setprogress(1.0)
    except PlanError as e:
        return ("Genesi Migrate could not prepare the disk", str(e))
    except Exception as e:
        return ("Genesi Migrate could not prepare the disk", "%s: %s" % (type(e).__name__, e))
    return None
