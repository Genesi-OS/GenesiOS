"""Opt-in QEMU smoke test. Uses only a new sparse disk in a temporary folder.

sudo unshare --mount --pid --fork --kill-child=KILL --mount-proc \
  --propagation private python3 genesi-arch/ci/migrate-boot-test.py \
  /path/to/official-archlinux-bootstrap-x86_64.tar.zst SHA256

Downloads packages into a disposable Arch chroot, not into the host OS.
Requires qemu-system-x86_64, sfdisk, mkfs.ext4, mkfs.vfat, rsync and zstd.
"""
import argparse
import contextlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "genesi-migrate/app"))
import native


def cleanup_test_directory(base):
    if base.is_symlink() or base.parent != Path("/var/tmp") or not base.name.startswith("genesi-qemu-migrate-"):
        raise AssertionError("Refusing cleanup outside the disposable test directory")
    mounts = json.loads(subprocess.check_output(
        ["findmnt", "--json", "--list", "--output", "TARGET"], text=True))["filesystems"]
    if any(m["target"] == str(base) or m["target"].startswith(str(base) + "/") for m in mounts):
        print("Mounted test directory retained for diagnosis:", base, flush=True)
        return
    shutil.rmtree(base)


def owned_test_image(path):
    image = path.resolve()
    if (path.is_symlink() or image.name != "source.raw"
            or not image.parent.name.startswith("genesi-qemu-migrate-")
            or image.parent.parent != Path("/var/tmp") or not image.is_file()
            or image.stat().st_uid != 0 or image.stat().st_size != 24 * native.GIB):
        raise AssertionError("Only a previous disposable test image may be reused")
    return image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bootstrap", type=Path)
    parser.add_argument("sha256")
    parser.add_argument("--zstd", default="zstd", help="Optional unpacked zstd executable (no host install needed)")
    parser.add_argument("--reuse-build", type=Path, help="Reuse only a previous disposable test chroot")
    parser.add_argument("--reuse-image", type=Path, help="Resume only a previous unconverted disposable test disk")
    parser.add_argument("--rebuild-only", action="store_true", help="Rebuild only the maintenance image using --reuse-build")
    parser.add_argument("--inspect-only", action="store_true", help="Read-only validation of a stopped converted --reuse-image guest")
    parser.add_argument("--keep", action="store_true", help="Keep disposable artifacts for diagnosis")
    parser.add_argument("--timeout", type=int, default=3600, help="Guest timeout; software CPU emulation can be slow")
    args = parser.parse_args()
    if sys.platform != "linux" or os.geteuid() != 0 or os.getpid() != 1:
        parser.error("Run as root in the private mount/PID namespace shown above")
    if native.digest(args.bootstrap) != args.sha256:
        parser.error("Bootstrap SHA-256 mismatch")
    with contextlib.ExitStack() as stack:
        directory = tempfile.mkdtemp(prefix="genesi-qemu-migrate-", dir="/var/tmp")
        base = Path(directory)
        if not args.keep:
            stack.callback(cleanup_test_directory, base)
        print("Disposable QEMU test directory:", base, flush=True)
        native.BASE = base
        native.LOG = base / "build.log"
        if args.inspect_only:
            if not args.reuse_image:
                parser.error("--inspect-only requires --reuse-image")
            image = owned_test_image(args.reuse_image)
            loop = native.run("losetup", "--find", "--show", "--read-only", "--partscan", image)
            if not re.fullmatch(r"/dev/loop[0-9]+", loop):
                raise AssertionError("Not a disposable loop device")
            try:
                native.run("udevadm", "settle")
                with native.mounted(loop + "p2", base / "root", "-t", "btrfs", "-o", "ro,rescue=nologreplay,subvol=@") as root:
                    if not (root / "var/lib/genesi-migrate/boot-ready").is_file():
                        raise AssertionError("No boot-ready marker")
                    shutil.copyfile(root / "boot/initramfs-linux.img", base / "installed-initramfs.img")
                    shutil.copyfile(root / "boot/vmlinuz-linux", base / "installed-vmlinuz")
                with native.mounted(loop + "p2", base / "home", "-t", "btrfs", "-o", "ro,rescue=nologreplay,subvol=@genesi-home") as home:
                    if (home / "mint/keep.txt").read_text() != "preserved by native migration\n":
                        raise AssertionError("Preserved home content differs")
            finally:
                native.run("losetup", "--detach", loop)
            print("PASS: boot-ready root and exact preserved home contents; installed boot images:", base, flush=True)
            return
        if args.reuse_build:
            build = args.reuse_build.resolve()
            if build.name != "root.x86_64" or not build.parent.name.startswith("genesi-qemu-migrate-") or build.parent.parent != Path("/var/tmp"):
                raise AssertionError("Only a previous disposable test chroot may be reused")
        else:
            native.run("tar", "--use-compress-program=" + args.zstd, "-xf", args.bootstrap, "-C", base)
            build = base / "root.x86_64"
        resolver = build / "etc/resolv.conf"
        if resolver.is_symlink():
            resolver.unlink()
        shutil.copyfile("/etc/resolv.conf", resolver)
        (build / "etc/pacman.d/mirrorlist").write_text("Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n")
        native.staging_initramfs(build)
        if args.rebuild_only:
            if not args.reuse_build:
                parser.error("--rebuild-only requires --reuse-build")
            task = base / "maintenance"
            task.mkdir()
            (build / "usr/lib/genesi-migrate").mkdir(parents=True, exist_ok=True)
            shutil.copyfile(native.__file__, build / "usr/lib/genesi-migrate/native.py")
            native.save(task / "state.json", {"rootUuid": "test", "sourcePrefix": "",
                                              "task": "/var/lib/genesi-migrate-native/qemu-test"})
            native.build_maintenance(build, task)
            print("Rebuilt maintenance artifacts:", task, flush=True)
            return
        with native.mounted(build, build, "--bind"), \
             native.mounted("/proc", build / "proc", "--bind", helper_root=build), \
             native.mounted("/dev", build / "dev", "--rbind", helper_root=build), \
             native.mounted("/sys", build / "sys", "--rbind", helper_root=build):
            if not args.reuse_build:
                native.run("chroot", build, "pacman-key", "--init")
                native.run("chroot", build, "pacman-key", "--populate", "archlinux")
            native.run("chroot", build, "pacman", "-Syu", "--noconfirm", "--needed",
                       "linux", "mkinitcpio", "python", "btrfs-progs", "e2fsprogs", "dosfstools",
                       "arch-install-scripts", "rsync", "grub", "systemd-sysvcompat")
            native.run("chroot", build, "pacman", "-Scc", "--noconfirm")
        image = base / "source.raw"
        if args.reuse_image:
            image = owned_test_image(args.reuse_image)
        else:
            with image.open("xb") as stream:
                stream.truncate(24 * native.GIB)
            native.run("sfdisk", image, input="label: gpt\n,512M,U\n,,L\n")
        loop = native.run("losetup", "--find", "--show", "--partscan", image)
        if not re.fullmatch(r"/dev/loop[0-9]+", loop):
            raise AssertionError("Not a disposable loop device")
        try:
            native.run("udevadm", "settle")
            esp, source = loop + "p1", loop + "p2"
            if str(image) not in native.run("losetup", "--list", "--noheadings", "--output", "BACK-FILE", loop):
                raise AssertionError("Refusing filesystem creation on an unowned device")
            if not args.reuse_image:
                with native.mounted("/dev", build / "dev", "--rbind", helper_root=build):
                    native.run("chroot", build, "mkfs.vfat", "-F", "32", esp)
                native.run("mkfs.ext4", "-F", "-q", source)
            elif native.run("blkid", "-s", "TYPE", "-o", "value", source) != "ext4":
                raise AssertionError("Converted test disks must not be replayed")
            root_uuid = native.run("blkid", "-s", "UUID", "-o", "value", source)
            state = {"schema": "native-v1", "phase": "armed", "sourcePrefix": "",
                     "task": "/var/lib/genesi-migrate-native/qemu-test", "originalFs": "ext4",
                     "rootUuid": root_uuid, "espUuid": native.run("blkid", "-s", "UUID", "-o", "value", esp),
                     "partuuid": native.run("blkid", "-s", "PARTUUID", "-o", "value", source),
                     "serial": "genesi-test-disk", "wwn": None, "diskSize": image.stat().st_size,
                     "user": {"name": "mint", "uid": 1000, "gid": 1000}}
            with native.mounted(source, base / "source") as mount:
                task = mount / state["task"].lstrip("/")
                task.mkdir(parents=True, exist_ok=True)
                root = task / "target-root"
                root.mkdir(exist_ok=True)
                native.run("rsync", "-aHAX", "--numeric-ids", str(build) + "/", str(root) + "/")
                (root / "etc/os-release").unlink(missing_ok=True)
                (root / "etc/os-release").write_text("ID=genesi\nNAME=Genesi\n")
                (root / "etc/hostname").write_text("genesi-test\n")
                (root / "etc/locale.conf").write_text("LANG=C.UTF-8\n")
                (root / "etc/localtime").unlink(missing_ok=True)
                (root / "etc/localtime").symlink_to("/usr/share/zoneinfo/UTC")
                native.setup_machine_id(root)
                (root / "usr/lib/genesi-migrate").mkdir(parents=True, exist_ok=True)
                shutil.copyfile(native.__file__, root / "usr/lib/genesi-migrate/native.py")
                (root / "etc/default/grub").write_text('GRUB_TIMEOUT=0\nGRUB_CMDLINE_LINUX="console=ttyS0"\n')
                (root / "boot/efi").mkdir(parents=True, exist_ok=True)
                (mount / "home/mint").mkdir(parents=True, exist_ok=True)
                (mount / "home/mint/keep.txt").write_text("preserved by native migration\n")
                os.chown(mount / "home/mint", 1000, 1000)
                os.chown(mount / "home/mint/keep.txt", 1000, 1000)
                success_script = root / "usr/lib/genesi-migrate/qemu-success.sh"
                success_script.write_text(
                    '#!/bin/sh\nset -eu\n'
                    'test "$(cat /home/mint/keep.txt)" = "preserved by native migration"\n'
                    'test "$(stat -c %u /home/mint/keep.txt)" = 1000\n'
                    'test "$(findmnt -n -o FSROOT /)" = /@\n'
                    'test "$(findmnt -n -o FSROOT /home)" = /@genesi-home\n'
                    'echo GENESI_NATIVE_BOOT_OK > /dev/ttyS0\n'
                    'systemctl poweroff\n')
                success_script.chmod(0o755)
                units = root / "etc/systemd/system"
                (units / "genesi-qemu-success.service").write_text(
                    '[Unit]\nAfter=local-fs.target\n[Service]\nType=oneshot\n'
                    'ExecStart=/usr/lib/genesi-migrate/qemu-success.sh\n'
                    '[Install]\nWantedBy=multi-user.target\n')
                (units / "multi-user.target.wants").mkdir(exist_ok=True)
                success_link = units / "multi-user.target.wants/genesi-qemu-success.service"
                success_link.unlink(missing_ok=True)
                success_link.symlink_to("../genesi-qemu-success.service")
                (units / "default.target").unlink(missing_ok=True)
                (units / "default.target").symlink_to("/usr/lib/systemd/system/multi-user.target")
                native.save(task / "state.json", state)
                native.build_maintenance(root, task)
                shutil.copyfile(task / "migrate-vmlinuz", base / "vmlinuz")
                shutil.copyfile(task / "migrate-initramfs.img", base / "initramfs.img")
                state.update(rootHash=native.root_hash(root), expandedBytes=sum(
                    p.stat().st_size for p in root.rglob("*") if p.is_file() and not p.is_symlink()))
                native.save(task / "state.json", state)
        finally:
            native.run("losetup", "--detach", loop)
        command = ["qemu-system-x86_64", "-m", "2048", "-smp", "2", "-cpu", "max", "-nographic", "-no-reboot", "-nic", "none",
                   "-accel", "tcg",
                   "-drive", "file=%s,format=raw,if=none,id=source" % image,
                   "-device", "virtio-blk-pci,drive=source,serial=genesi-test-disk",
                   "-kernel", str(base / "vmlinuz"), "-initrd", str(base / "initramfs.img"),
                   "-append", "console=ttyS0 root=UUID=%s rw fsck.mode=skip genesi.migrate=UUID=%s:%s" % (
                       root_uuid, root_uuid, state["task"])]
        print("Booting disposable 2 GiB QEMU guest without ISO", flush=True)
        with (base / "serial.log").open("w") as log:
            subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=args.timeout, check=True)
        serial = (base / "serial.log").read_text(errors="replace")
        if "GENESI_NATIVE_BOOT_OK" not in serial:
            raise AssertionError("Guest did not reach the prepared root; see " + str(base / "serial.log"))
        print("PASS: ext4 -> Btrfs, preserved home, direct Genesi boot on 2 GiB RAM; no ISO or second reboot")


if __name__ == "__main__":
    main()
