"""Native migration: prepare an installed tree, then switch offline.

No action runs on import. The root helper invokes prepare in a private mount
namespace. A small, dedicated initramfs performs the offline switch during
the next boot, then mkinitcpio switches directly into the prepared Genesi.
The initial supported layout is x86_64 UEFI, plain ext4 or Btrfs root, /home
on that root, and an ESP on the same disk. Unsupported layouts fail closed.
"""
import argparse
import contextlib
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import select
import signal
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

BASE = Path("/var/lib/genesi-migrate-native")
TOP = Path("/run/genesi-native-top")
TARGET = Path("/run/genesi-native-target")
RAM_STATE = Path("/run/genesi-native-state")
MAINTENANCE_MARKER = Path("/etc/genesi-native-initramfs")
MAINTENANCE_VERSION = "genesi-native-initramfs-v1"
MAX_MAINTENANCE_IMAGE = 192 * 1024 ** 2
GIB = 1024 ** 3
MIN_PREP_FREE = 32 * GIB
LOG = None


class MigrationError(RuntimeError):
    pass


def format_space(value):
    return "%.2f GiB (%.2f GB)" % (value / GIB, value / 10 ** 9)


def require_free_space(path, required, purpose):
    available = shutil.disk_usage(path).free
    if available < required:
        raise MigrationError("%s requires %s free on %s; available: %s; missing: %s" %
                             (purpose, format_space(required), path, format_space(available),
                              format_space(required - available)))


def run(*args, input=None, allowed=(0,), reserve_at=None):
    print("native:", args[0], " ".join(str(x) for x in args[1:]) if args[0] not in ("chpasswd",) else "", flush=True)
    if reserve_at is None:
        result = subprocess.run([str(x) for x in args], input=input, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    else:
        process = subprocess.Popen([str(x) for x in args], text=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        while True:
            try:
                output, _ = process.communicate(timeout=1)
                result = subprocess.CompletedProcess(args, process.returncode, output)
                break
            except subprocess.TimeoutExpired:
                if shutil.disk_usage(reserve_at).free < 8 * GIB:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.communicate(timeout=10)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.communicate()
                    raise MigrationError("Preparation stopped to preserve 8 GiB free for the running system")
    if LOG is not None:
        with LOG.open("a") as stream:
            stream.write("$ " + " ".join(str(x) for x in args) + "\n" + result.stdout + "\n")
    if result.returncode not in allowed:
        raise MigrationError("%s failed (%d): %s" % (args[0], result.returncode, result.stdout[-6000:]))
    return result.stdout.strip()


def digest(path):
    result = hashlib.sha256()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def save(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(prefix=".native-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(data, stream, indent=2)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        if os.name == "posix":
            fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(fd)
            finally:
                os.close(fd)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def walk(nodes):
    for node in nodes:
        yield node
        yield from walk(node.get("children", []))


def inventory():
    # lsblk only includes children[] when NAME or --tree is requested. Without
    # that, a partition appears at the top level and has no hardware serial.
    return json.loads(run("lsblk", "--tree", "-J", "-b", "-o",
                          "NAME,PATH,TYPE,SIZE,FSTYPE,UUID,PARTUUID,SERIAL,WWN,MOUNTPOINTS"))["blockdevices"]


def identify(state, devices):
    disks = [d for d in devices if d.get("type") == "disk" and
             int(d.get("size", 0)) == state["diskSize"] and
             ((state.get("wwn") and d.get("wwn") == state["wwn"]) or
              (state.get("serial") and d.get("serial") == state["serial"]))]
    if len(disks) != 1:
        raise MigrationError("Source disk identity changed or is ambiguous")
    parts = [p for p in walk(disks) if p.get("partuuid") == state["partuuid"]]
    esp = [p for p in walk(disks) if p.get("uuid") == state["espUuid"]]
    if len(parts) != 1 or len(esp) != 1 or parts[0].get("uuid") != state["rootUuid"]:
        raise MigrationError("Source root or EFI identity changed")
    return disks[0], parts[0], esp[0]


def validate_machine(machine, devices):
    if int(machine.get("ramBytes") or 0) < 1800 * 1024 ** 2:
        raise MigrationError("Native migration requires at least 2 GB of installed RAM")
    if machine.get("firmware") not in ("uefi", "efi") or machine.get("secureBoot"):
        raise MigrationError("Native migration requires UEFI with Secure Boot disabled")
    same_btrfs_home = (machine.get("rootFs") == "btrfs" and machine.get("homeFs") == "btrfs"
                       and machine.get("homeUuid") == machine.get("rootUuid"))
    if machine.get("luks") or machine.get("rootPartType") != "part" or (machine.get("homeSeparate") and not same_btrfs_home):
        raise MigrationError("Encrypted/LVM roots and /home on a different filesystem are not supported by native migration yet")
    if machine.get("rootFs") not in ("ext4", "btrfs"):
        raise MigrationError("This filesystem cannot be converted safely; supported roots: ext4, Btrfs")
    roots = [(d, p) for d in devices if d.get("type") == "disk"
             for p in walk(d.get("children", [])) if p.get("uuid") == machine.get("rootUuid")]
    if len(roots) != 1:
        raise MigrationError("Root UUID is not unique")
    disk, root = roots[0]
    if root.get("fstype") != machine["rootFs"]:
        raise MigrationError("Root filesystem changed since the scan")
    if not (disk.get("wwn") or disk.get("serial")):
        raise MigrationError("The physical/virtual disk exposes no serial or WWN; a stable disk identity is required")
    if not root.get("partuuid"):
        raise MigrationError("The root partition exposes no PARTUUID; refresh disk detection before retrying")
    esp = [p for p in walk([disk]) if p.get("uuid") == machine.get("espUuid") and p.get("fstype") == "vfat"]
    if len(esp) != 1:
        raise MigrationError("The EFI partition must be on the source disk")
    return {"schema": "native-v1", "diskSize": int(disk["size"]), "serial": disk.get("serial"), "wwn": disk.get("wwn"),
            "partuuid": root["partuuid"], "rootUuid": root["uuid"], "espUuid": esp[0]["uuid"],
            "originalFs": machine["rootFs"], "phase": "preparing"}


@contextlib.contextmanager
def mounted(source, destination, *options, helper_root=None):
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    helper_scope = os.path.realpath(helper_root or destination)
    if (Path(helper_scope).parent == Path(helper_scope)
            or os.path.commonpath((helper_scope, os.path.realpath(destination))) != helper_scope):
        raise MigrationError("Chroot helper cleanup must stay within its owned mount tree")
    run("mount", *options, source, destination)
    primary_error = None
    try:
        yield destination
    except BaseException as exc:
        primary_error = exc
        raise
    finally:
        try:
            stop_mount_helpers(helper_scope)
            unmount(destination)
        except Exception as cleanup_error:
            if primary_error is None:
                raise
            cleanup_warning(cleanup_error)


def cleanup_warning(error):
    message = "Additional cleanup failure: " + str(error)
    print(message, file=sys.stderr, flush=True)
    if LOG is not None:
        try:
            with LOG.open("a") as stream:
                stream.write(message + "\n")
        except OSError:
            pass


def mount_helper_pids(destination):
    """Only processes chrooted below this mount in our private namespace."""
    if sys.platform != "linux":
        return []
    namespace = os.readlink("/proc/self/ns/mnt")
    destination = os.path.realpath(destination)
    result = []
    for process in Path("/proc").iterdir():
        if not process.name.isdecimal() or int(process.name) in (1, os.getpid()):
            continue
        try:
            if os.readlink(process / "ns/mnt") != namespace:
                continue
            root = os.readlink(process / "root")
            if root.endswith(" (deleted)") or os.path.commonpath((destination, root)) != destination:
                continue
            result.append(int(process.name))
        except (OSError, ValueError):
            continue
    return result


def stop_mount_helpers(destination):
    # pacman-key leaves gpg-agent/dirmngr running after pacstrap returns. Their
    # chroot root and /dev handles prevent unmount. Never signal host processes:
    # require both this namespace and a root beneath the owned runner/mount.
    for pid in mount_helper_pids(destination):
        try:
            descriptor = open_pid_handle(pid)
        except ProcessLookupError:
            continue
        try:
            # Recheck after opening the stable PID handle.
            if pid not in mount_helper_pids(destination):
                continue
            signal_pid_handle(descriptor, signal.SIGTERM)
            if not select.select([descriptor], [], [], 2)[0]:
                signal_pid_handle(descriptor, signal.SIGKILL)
                if not select.select([descriptor], [], [], 2)[0]:
                    raise MigrationError("A migration chroot helper did not exit: %d" % pid)
        except ProcessLookupError:
            pass
        finally:
            os.close(descriptor)


def pidfd_syscall(number, *arguments):
    # Older host Pythons (e.g. Ubuntu 20.04's 3.8) lack the wrappers even when
    # their kernel supports pidfds. Native migration targets x86_64; these ABI
    # numbers are fixed in asm/unistd_64.h. Never fall back to a racy kill(pid).
    import ctypes
    import platform
    if platform.machine().lower() not in ("x86_64", "amd64"):
        raise MigrationError("Stable process handles are unavailable on this architecture")
    libc = ctypes.CDLL(None, use_errno=True)
    libc.syscall.restype = ctypes.c_long
    result = libc.syscall(ctypes.c_long(number), *(ctypes.c_long(value) for value in arguments))
    if result < 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))
    return result


def open_pid_handle(pid):
    wrapper = getattr(os, "pidfd_open", None)
    return wrapper(pid) if wrapper else pidfd_syscall(434, pid, 0)


def signal_pid_handle(descriptor, sig):
    wrapper = getattr(signal, "pidfd_send_signal", None)
    return wrapper(descriptor, sig) if wrapper else pidfd_syscall(424, descriptor, sig, 0, 0)


def unmount(destination):
    # Kernel/udev references can briefly outlive an overlay or loop unmount.
    # Retry ordinary unmounts only; never force/lazy-unmount a source filesystem.
    for attempt in range(6):
        try:
            run("umount", "-R", destination)
            return
        except MigrationError:
            if attempt == 5:
                raise
            time.sleep(0.2)


@contextlib.contextmanager
def mounted_image(source, destination):
    """Own the loop lifetime, releasing child images before their parent ISO.

    mount -o loop relies on autoclear, whose delayed release can keep an ISO
    busy after its embedded squashfs was unmounted. Explicitly detach our loop
    and wait for udev before the outer image context is cleaned up.
    """
    if not Path(source).is_file():
        raise MigrationError("Image is not a regular file: " + str(source))
    loop = run("losetup", "--find", "--show", "--read-only", source)
    if not re.fullmatch(r"/dev/loop[0-9]+", loop):
        raise MigrationError("Unexpected loop device: " + loop)
    primary_error = None
    try:
        with mounted(loop, destination, "-o", "ro") as mount:
            yield mount
    except BaseException as exc:
        primary_error = exc
        raise
    finally:
        try:
            run("losetup", "--detach", loop)
            if shutil.which("udevadm"):
                run("udevadm", "settle", "--timeout=3", allowed=(0, 1))
        except Exception as cleanup_error:
            if primary_error is None:
                raise
            cleanup_warning(cleanup_error)


def setup_machine_id(root):
    root = Path(root)
    # Recent systemd opens pinned file descriptors through /proc/self/fd.
    # Package installation's runtime mounts have already been torn down here.
    with mounted("/proc", root / "proc", "--bind", helper_root=root), \
         mounted("/dev", root / "dev", "--rbind", helper_root=root):
        run("chroot", root, "systemd-machine-id-setup")
    identity = root / "etc/machine-id"
    if not identity.is_file() or not re.fullmatch(r"[0-9a-f]{32}", identity.read_text().strip()):
        raise MigrationError("Prepared system has no valid machine ID")


def target_valid(root):
    root = Path(root)
    for name in ("etc/os-release", "usr/bin/pacman", "usr/bin/mkinitcpio", "usr/bin/grub-mkconfig"):
        if not (root / name).is_file():
            raise MigrationError("Prepared system is incomplete: " + name)
    if not list((root / "boot").glob("vmlinuz-*")) or not list((root / "boot").glob("initramfs-*.img")):
        raise MigrationError("Prepared system has no kernel/initramfs")
    if not (root / "var/lib/pacman/local").is_dir():
        raise MigrationError("Prepared system has no package database")
    if not re.search(r'^ID=["\']?genesi["\']?$', (root / "etc/os-release").read_text(), re.M):
        raise MigrationError("Prepared system is not branded as Genesi")


def root_hash(root):
    # Bind all regular-file content and symlink targets to the prepared artifact.
    result = hashlib.sha256()
    for base, dirs, files in os.walk(root, followlinks=False):
        dirs.sort()
        for name in sorted(files + [n for n in dirs if os.path.islink(os.path.join(base, n))]):
            path = Path(base) / name
            result.update(str(path.relative_to(root)).encode() + b"\0")
            if path.is_symlink():
                result.update(os.readlink(path).encode())
            elif path.is_file():
                result.update(digest(path).encode())
            result.update(b"\0")
    return result.hexdigest()


def account(root, name):
    import pwd
    if not re.fullmatch(r"[a-z_][a-z0-9_-]{0,30}", name):
        raise MigrationError("Invalid login name")
    user = pwd.getpwnam(name)
    if user.pw_uid < 1000 or user.pw_dir != "/home/" + name:
        raise MigrationError("Only a regular /home/<login> account can be migrated")
    shadow = [line.split(":")[1] for line in Path("/etc/shadow").read_text().splitlines() if line.split(":")[0] == name]
    password = shadow[0] if len(shadow) == 1 else ""
    if not password.startswith(("$6$", "$y$", "$5$", "$2")):
        raise MigrationError("The account must have a supported local password")
    run("arch-chroot", root, "groupadd", "-g", str(user.pw_gid), name)
    run("arch-chroot", root, "useradd", "-M", "-u", str(user.pw_uid), "-g", str(user.pw_gid),
        "-G", "wheel", "-s", "/usr/bin/fish" if (root / "usr/bin/fish").is_file() else "/bin/bash",
        "-d", user.pw_dir, "-c", user.pw_gecos, name)
    run("arch-chroot", root, "chpasswd", "-e", input=name + ":" + password + "\n")
    sudoers = root / "etc/sudoers.d/10-genesi-wheel"
    sudoers.write_text("%wheel ALL=(ALL:ALL) ALL\n")
    sudoers.chmod(0o440)
    return {"name": name, "uid": user.pw_uid, "gid": user.pw_gid}


def prepare(manifest_path, iso_path, checksum, profile_path):
    global LOG
    manifest = json.loads(Path(manifest_path).read_text())
    state = validate_machine(manifest["machine"], inventory())
    for path in ("/", "/home", "/var", "/boot"):
        if run("findmnt", "-n", "-o", "UUID", "-T", path) != state["rootUuid"]:
            raise MigrationError("Native migration requires /home, /var and /boot on the root filesystem")
    for path in ("/var", "/boot"):
        if run("findmnt", "-n", "-o", "TARGET", "-T", path) != "/":
            raise MigrationError("Separate /var or /boot mounts are not supported by native migration")
    for app in manifest.get("apps", []):
        if app.get("selected") and app.get("target") and not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9@+_.:-]*", app["target"]):
            raise MigrationError("Unsafe application package name")
    if digest(iso_path) != checksum:
        raise MigrationError("ISO checksum changed before privileged preparation")
    tools = ["mount", "losetup", "unshare", "chroot", "efibootmgr"]
    if state["originalFs"] == "btrfs":
        tools.append("btrfs")
    for tool in tools:
        if not shutil.which(tool):
            raise MigrationError("Install required host tool before retrying: " + tool)
    # Root-owned private directory: the old user's writable download stage is
    # never executed by the maintenance environment.
    if BASE.exists() and (BASE.is_symlink() or BASE.stat().st_uid != 0):
        raise MigrationError("Native staging directory is not root-owned")
    BASE.mkdir(mode=0o700, parents=True, exist_ok=True)
    BASE.chmod(0o700)
    retire_previous_boot_tasks(state)
    task = BASE / str(uuid.uuid4())
    task.mkdir(mode=0o700)
    LOG = task / "prepare.log"
    state["task"] = str(task)
    state["sourcePrefix"] = run("findmnt", "-n", "-o", "FSROOT", "/").rstrip("/")
    if not re.fullmatch(r"[/a-zA-Z0-9_.@-]*", state["sourcePrefix"]):
        raise MigrationError("Unsupported source subvolume path")
    state["homePrefix"] = filesystem_path("/home")
    if state["originalFs"] == "btrfs" and state["sourcePrefix"] == "/@":
        # Capture IDs while the source is still running. Offline exchange only
        # renames the exact subvolumes observed here, never an unrelated @.
        state["exchange"] = {"rootId": subvolume_id("/"), "homeSourceId": subvolume_id("/home"),
                             "rootBackup": "@genesi-previous-" + task.name,
                             "rootNext": "@genesi-next-root-" + task.name,
                             "homeNext": "@genesi-next-home-" + task.name}
        if state["homePrefix"] == "/@genesi-home":
            state["exchange"].update(homeId=subvolume_id("/home"),
                                     homeBackup="@genesi-previous-home-" + task.name)
        validate_exchange(state)
        with mounted(identify(state, inventory())[1]["path"], task / "layout-check", "-t", "btrfs",
                     "-o", "ro,rescue=nologreplay,subvolid=5") as layout:
            exchange = state["exchange"]
            if subvolume_id(layout / "@") != exchange["rootId"]:
                raise MigrationError("Running root does not match the top-level @ subvolume")
            for key in ("rootBackup", "rootNext", "homeNext", "homeBackup"):
                if key in exchange and (layout / exchange[key]).exists():
                    raise MigrationError("Reserved migration backup/temporary name is already occupied")
            if (layout / "@genesi-home").exists() and "homeBackup" not in exchange:
                raise MigrationError("An unrelated @genesi-home already exists")
    require_free_space(BASE, MIN_PREP_FREE, "Preparation and conversion reserve")
    shutil.copyfile(iso_path, task / "genesi.iso")
    if digest(task / "genesi.iso") != checksum:
        raise MigrationError("ISO changed during staging; migration was not armed")
    shutil.copyfile(__file__, task / "native.py")
    save(task / "manifest.json", manifest)
    save(task / "state.json", state)
    state["desktop"] = manifest["choices"]["desktop"]
    profiles = json.loads(Path(profile_path).read_text())
    packages = profiles.get(manifest["choices"]["desktop"])
    if not packages:
        raise MigrationError("No native package profile exists for the selected desktop")
    packages = [p.replace("$LOCALE", "en-us") for p in packages]
    packages = sorted(set(packages) | {"python", "mkinitcpio", "btrfs-progs", "e2fsprogs",
                                       "rsync", "arch-install-scripts", "grub", "dosfstools"})
    if any(not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9@+_.:-]*", p) for p in packages):
        raise MigrationError("Package profile contains an unsupported token")
    root = task / "target-root"
    root.mkdir()
    staging_initramfs(root)
    with mounted_image(task / "genesi.iso", task / "iso") as iso:
        images = list(iso.glob("arch/x86_64/airootfs.sfs"))
        if len(images) != 1:
            raise MigrationError("ISO has no supported archiso root image")
        with mounted_image(images[0], task / "lower") as lower:
            for name in ("upper", "work", "runner"):
                (task / name).mkdir()
            options = "lowerdir=%s,upperdir=%s,workdir=%s" % (lower, task / "upper", task / "work")
            with mounted("overlay", task / "runner", "-t", "overlay", "-o", options) as runner:
                # Use archiso's Arch userspace, not Mint's package manager.
                resolver = runner / "etc/resolv.conf"
                if resolver.is_symlink():
                    resolver.unlink()
                shutil.copyfile("/etc/resolv.conf", resolver)
                with mounted(task, runner / "genesi-native", "--bind", helper_root=runner):
                    command = ["chroot", str(runner), "/usr/bin/bash", "-euc"]
                    script = """
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount --rbind /host-dev /dev
mount --bind /genesi-native/target-root /genesi-native/target-root
pacman-key --init
pacman-key --populate
pacman -Sy --noconfirm archlinux-keyring cachyos-keyring genesi-keyring
"""
                    with mounted("/dev", runner / "host-dev", "--rbind", helper_root=runner):
                        run(*command, script)
                        available = set(run("chroot", runner, "pacman", "-Slq").splitlines())
                        wanted = {a.get("target") for a in manifest.get("apps", []) if a.get("selected") and a.get("kind") == "pacman" and a.get("target")}
                        for kind, package in (("aur", "paru"), ("flatpak", "flatpak"), ("flatpak-search", "flatpak")):
                            if any(a.get("selected") and a.get("kind") == kind for a in manifest.get("apps", [])):
                                wanted.add(package)
                        state["apps"] = {"pacmanInstalled": sorted(wanted & available), "pacmanMissing": sorted(wanted - available)}
                        run("chroot", runner, "pacstrap", "-K", "/genesi-native/target-root", *sorted(set(packages) | (wanted & available)), reserve_at=BASE)
                # Export arch-chroot from the ISO for the remaining target ops.
                # These commands run inside the ISO userspace with the prepared
                # root bind-mounted at the same stable path.
                with mounted(task, runner / "genesi-native", "--bind", helper_root=runner):
                    run("chroot", runner, "mount", "--bind", "/genesi-native/target-root", "/genesi-native/target-root")
                    shutil.copyfile(runner / "etc/pacman.conf", root / "etc/pacman.conf")
                    run("chroot", runner, "arch-chroot", "/genesi-native/target-root", "pacman-key", "--init")
                    run("chroot", runner, "arch-chroot", "/genesi-native/target-root", "pacman-key", "--populate")
                    run("chroot", runner, "arch-chroot", "/genesi-native/target-root", "mkinitcpio", "-P")
                    run("chroot", runner, "arch-chroot", "/genesi-native/target-root", "pacman", "-Scc", "--noconfirm")
                # Account creation needs host shadow access, using target tools.
                with mounted("/proc", root / "proc", "--bind"), mounted("/dev", root / "dev", "--rbind"), mounted("/sys", root / "sys", "--rbind"):
                    # A tiny host wrapper uses chroot; never install Arch tools on Mint.
                    wrapper = task / "bin"
                    wrapper.mkdir()
                    (wrapper / "arch-chroot").write_text('#!/bin/sh\nexec chroot "$@"\n')
                    (wrapper / "arch-chroot").chmod(0o700)
                    old_path = os.environ["PATH"]
                    os.environ["PATH"] = str(wrapper) + ":" + old_path
                    try:
                        state["user"] = account(root, manifest["settings"]["user"]["name"])
                    finally:
                        os.environ["PATH"] = old_path
                # Carry app restoration from the build source, not its live boot.
                finish = lower / "usr/lib/genesi-migrate/restore.py"
                if not finish.is_file():
                    raise MigrationError("ISO has no migration app-restoration worker")
                dest = root / "usr/lib/genesi-migrate"
                dest.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(finish, dest / "restore.py")
                prepare_desktop(root, runner, state["desktop"], state["user"]["name"])
    root.joinpath("etc/hostname").write_text("genesi\n")
    release = root / "etc/os-release"
    if release.is_symlink():
        release.unlink()
    release.write_text('NAME="Genesi OS"\nPRETTY_NAME="Genesi OS"\nID=genesi\nID_LIKE="cachyos arch"\nBUILD_ID=rolling\nHOME_URL="https://genesios.org"\nDOCUMENTATION_URL="https://wiki.genesios.org"\nLOGO=genesi\n')
    root.joinpath("etc/lsb-release").write_text('DISTRIB_ID="Genesi OS"\nDISTRIB_RELEASE="rolling"\nDISTRIB_DESCRIPTION="Genesi OS"\n')
    root.joinpath("etc/locale.gen").write_text("en_US.UTF-8 UTF-8\npt_BR.UTF-8 UTF-8\n")
    root.joinpath("etc/locale.conf").write_text("LANG=" + ("pt_BR.UTF-8" if manifest["choices"].get("language") == "pt_BR" else "en_US.UTF-8") + "\n")
    run("chroot", root, "locale-gen")
    for service in ("NetworkManager", "systemd-resolved", "systemd-timesyncd", "cups",
                    "avahi-daemon", "power-profiles-daemon", "vboxservice", "vmtoolsd", "firewalld", "fstrim.timer"):
        unit = service if service.endswith(".timer") else service + ".service"
        if (root / "usr/lib/systemd/system" / unit).is_file():
            run("systemctl", "--root", root, "enable", unit)
    default_target = root / "etc/systemd/system/default.target"
    if default_target.exists() or default_target.is_symlink():
        default_target.unlink()
    default_target.symlink_to("/usr/lib/systemd/system/graphical.target")
    wifi = Path("/etc/NetworkManager/system-connections")
    if manifest["choices"].get("wifi") and wifi.is_dir():
        shutil.copytree(wifi, root / "etc/NetworkManager/system-connections", dirs_exist_ok=True)
    timezone = manifest["settings"].get("timezone", "UTC")
    if ".." in timezone or not re.fullmatch(r"[A-Za-z0-9_+/-]+", timezone) or not (root / "usr/share/zoneinfo" / timezone).is_file():
        raise MigrationError("Unsupported time zone")
    localtime = root / "etc/localtime"
    if localtime.exists() or localtime.is_symlink():
        localtime.unlink()
    localtime.symlink_to("/usr/share/zoneinfo/" + timezone)
    keyboard = manifest["settings"].get("keyboard", {})
    layout, variant = keyboard.get("layout") or "us", keyboard.get("variant") or ""
    if any(not re.fullmatch(r"[A-Za-z0-9_,+-]*", value) for value in (layout, variant)):
        raise MigrationError("Unsupported keyboard layout")
    keyboard_file = root / "etc/X11/xorg.conf.d/00-keyboard.conf"
    keyboard_file.parent.mkdir(parents=True, exist_ok=True)
    keyboard_file.write_text('Section "InputClass"\n Identifier "genesi-keyboard"\n MatchIsKeyboard "on"\n Option "XkbLayout" "%s"\n Option "XkbVariant" "%s"\nEndSection\n' % (layout, variant))
    console_map = {"br": "br-abnt2", "pt": "pt-latin1", "us": "us"}.get(layout, "us")
    (root / "etc/vconsole.conf").write_text("KEYMAP=" + console_map + "\n")
    setup_machine_id(root)
    install_finish(root, manifest, state)
    target_valid(root)
    build_maintenance(root, task)
    # Boot uses only the dedicated kernel/initramfs. Keep the resumable source
    # download, but release this no-longer-mounted private duplicate.
    (task / "genesi.iso").unlink()
    expanded = sum(p.stat().st_size for p in root.rglob("*") if p.is_file() and not p.is_symlink())
    require_free_space(BASE, expanded + 8 * GIB, "Conversion and final Genesi tree")
    state.update(phase="ready", rootHash=root_hash(root), isoHash=checksum, expandedBytes=expanded)
    save(task / "state.json", state)
    # Arming is the last write, after all downloads, packages and validation.
    arm(state, task)
    print(json.dumps({"ready": True, "task": str(task)}), flush=True)


DESKTOP_SESSIONS = {
    "KDE-Desktop": ("sddm", ("xsessions/plasmax11.desktop", "wayland-sessions/plasma.desktop")),
    "Hyprland-Desktop": ("sddm", ("wayland-sessions/hyprland.desktop", "wayland-sessions/hyprland-uwsm.desktop")),
    "GNOME-Desktop": ("gdm", ("wayland-sessions/gnome.desktop", "xsessions/gnome.desktop")),
    "Xfce4": ("lightdm", ("xsessions/xfce.desktop",)),
    "Cinnamon": ("lightdm", ("xsessions/cinnamon.desktop",)),
    "Budgie-Desktop": ("lightdm", ("xsessions/budgie-desktop.desktop",)),
    "LXDE-Desktop": ("lightdm", ("xsessions/LXDE.desktop",)),
    "Cosmic": ("cosmic-greeter", ("wayland-sessions/cosmic.desktop",)),
    "Niri": ("sddm", ("wayland-sessions/niri.desktop",)),
}


def prepare_desktop(root, source, desktop, user):
    """Import installer artwork, but use the selected desktop's packaged defaults."""
    root, source = Path(root), Path(source)
    if desktop not in DESKTOP_SESSIONS:
        raise MigrationError("No desktop integration exists for " + desktop)
    # The live image also contains build-time artwork not owned by a package.
    # Never replace newer packaged assets with the older source ISO version.
    assets = ["usr/share/genesi", "usr/share/wallpapers/genesi", "usr/share/plymouth/themes/genesi"]
    if desktop == "KDE-Desktop":
        assets += ["usr/share/plasma/desktoptheme/genesi-plasma", "usr/share/plasma/desktoptheme/Ant-Dark",
                   "usr/share/plasma/look-and-feel/Ant-Dark", "usr/share/Kvantum/Genesi"]
        assets += [str(p.relative_to(source)) for pattern in ("usr/share/color-schemes/Genesi*", "usr/share/icons/Tela-circle*")
                   for p in source.glob(pattern)]
    for relative in assets:
        origin, target = source / relative, root / relative
        if origin.is_dir():
            target.mkdir(parents=True, exist_ok=True)
            run("rsync", "-a", "--ignore-existing", str(origin) + "/", str(target) + "/")
        elif origin.is_file() and not target.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(origin, target)
    override = root / "usr/share/genesi/skel-override"
    skel = root / "etc/skel"
    skel.mkdir(parents=True, exist_ok=True)
    if desktop == "KDE-Desktop":
        if not (override / ".config/kdeglobals").is_file():
            raise MigrationError("Genesi Plasma defaults are missing; migration was not armed")
        run("rsync", "-a", "--exclude=/Desktop/calamares.desktop", str(override) + "/", str(skel) + "/")
    else:
        # genesi-settings' override is Plasma-specific. Hyprland/Caelestia and
        # the other WMs already ship their own /etc/skel via their packages.
        fish = override / ".config/fish"
        if fish.is_dir():
            destination = skel / ".config/fish"
            destination.mkdir(parents=True, exist_ok=True)
            run("rsync", "-a", str(fish) + "/", str(destination) + "/")
    if not (root / "usr/share/wallpapers/genesi/wallpaper.png").is_file():
        raise MigrationError("Genesi wallpaper is missing; migration was not armed")
    if desktop == "KDE-Desktop":
        for relative in ("etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc", "etc/skel/.config/kwinrc",
                         "etc/skel/.config/klassyrc", "etc/skel/.config/darklyrc",
                         "etc/skel/.config/autostart/genesi-apply-theme.desktop",
                         "usr/bin/genesi-apply-theme.sh", "usr/share/color-schemes/Genesi.colors",
                         "usr/share/plasma/desktoptheme/Ant-Dark", "usr/share/icons/Tela-circle-green-dark"):
            if not (root / relative).exists():
                raise MigrationError("Genesi Plasma integration is missing: " + relative)
    if desktop == "Hyprland-Desktop":
        for relative in ("etc/skel/.config/hypr/hyprland.conf", "etc/skel/.config/caelestia/shell.json",
                         "usr/bin/Hyprland", "usr/bin/caelestia"):
            if not (root / relative).is_file():
                raise MigrationError("Genesi Hyprland/Caelestia integration is missing: " + relative)
    if desktop not in ("KDE-Desktop", "Hyprland-Desktop"):
        for relative in ("usr/bin/genesi-de-apply", "etc/xdg/autostart/genesi-de-branding.desktop"):
            if not (root / relative).is_file():
                raise MigrationError("Genesi desktop login integration is missing: " + relative)
    # A preserved per-user Hidden=true entry would shadow the packaged helper.
    # Seed only installed Genesi autostarts, retaining their DE restrictions.
    for entry in (root / "etc/xdg/autostart").glob("genesi-*.desktop"):
        if entry.name in ("genesi-migrate-live.desktop", "genesi-branding.desktop"):
            continue
        destination = skel / ".config/autostart" / entry.name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(entry, destination)
    # Use installed per-DE login helpers, not liveuser's dconf database or the
    # live branding re-seeder. Neither live autologin nor live services are copied.
    manager, candidates = DESKTOP_SESSIONS[desktop]
    session = next((p for p in candidates if (root / "usr/share" / p).is_file()), None)
    if not session or not (root / "usr/lib/systemd/system" / (manager + ".service")).is_file():
        raise MigrationError("Selected desktop session/display manager is missing: " + desktop)
    run("systemctl", "--root", root, "enable", "--force", manager + ".service")
    accounts = root / "var/lib/AccountsService/users"
    accounts.mkdir(parents=True, exist_ok=True)
    contents = "[User]\nSession=" + Path(session).name + "\nSystemAccount=false\n"
    if session.startswith("xsessions/"):
        contents += "XSession=" + Path(session).stem + "\n"
        (skel / ".dmrc").write_text("[Desktop]\nSession=" + Path(session).stem + "\n")
    (accounts / user).write_text(contents)
    (accounts / user).chmod(0o600)
    if (root / "usr/bin/plymouth-set-default-theme").is_file() and (root / "usr/share/plymouth/themes/genesi").is_dir():
        run("chroot", root, "plymouth-set-default-theme", "genesi")
    save(root / "var/lib/genesi-migrate/desktop.json", {"desktop": desktop, "session": session, "manager": manager})


def apply_desktop_home(prepared, home, state, task):
    home = Path(home)
    if home.is_symlink() or any((home / name).is_symlink() for name in (".config", ".local")):
        raise MigrationError("Desktop configuration directory is a symlink; refusing to overwrite its target")
    # Only template paths are replaced, never delete unrelated files. Keep a
    # separate backup per retry; the original source home is also untouched.
    backup = Path(task) / "desktop-backups" / str(uuid.uuid4())
    backup.mkdir(parents=True, mode=0o700)
    run("rsync", "-a", "--backup", "--backup-dir=" + str(backup),
        "--exclude=/Desktop/calamares.desktop",
        "--chown=%s:%s" % (state["user"]["uid"], state["user"]["gid"]),
        str(Path(prepared) / "etc/skel") + "/", str(home) + "/")
    for relative in (".config/.genesi-theme-applied", ".config/genesi/de-branding.applied"):
        marker = home / relative
        try:
            marker.parent.resolve().relative_to(home.resolve())
        except ValueError:
            raise MigrationError("Desktop marker escapes the migrated home")
        if marker.is_file() or marker.is_symlink():
            destination = backup / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(marker, destination, follow_symlinks=False)
            marker.unlink()


def ready_marker(state):
    return "var/lib/genesi-migrate/boot-ready-" + PurePosixPath(state["task"]).name


def filesystem_path(path):
    info = json.loads(run("findmnt", "--json", "-T", path, "-o", "FSROOT,TARGET"))["filesystems"][0]
    relative = PurePosixPath(path).relative_to(info["target"])
    result = str(PurePosixPath(info["fsroot"]) / relative)
    if not re.fullmatch(r"/[A-Za-z0-9_./@-]*", result) or ".." in PurePosixPath(result).parts:
        raise MigrationError("Unsupported filesystem-relative source path")
    return result.rstrip("/")


def subvolume_id(path):
    value = run("btrfs", "inspect-internal", "rootid", path)
    if not value.isdecimal() or int(value) < 256:
        raise MigrationError("Source is not a supported Btrfs subvolume")
    return int(value)


def validate_exchange(state):
    exchange = state.get("exchange")
    if exchange is None:
        return
    suffix = PurePosixPath(state["task"]).name
    if state.get("originalFs") != "btrfs" or state.get("sourcePrefix") != "/@" or not isinstance(exchange, dict):
        raise MigrationError("Invalid Btrfs exchange state")
    names = {"rootBackup": "@genesi-previous-", "rootNext": "@genesi-next-root-", "homeNext": "@genesi-next-home-"}
    if "homeBackup" in exchange:
        names["homeBackup"] = "@genesi-previous-home-"
        if state.get("homePrefix") != "/@genesi-home":
            raise MigrationError("Unexpected source home exchange")
    if any(exchange.get(key) != prefix + suffix for key, prefix in names.items()):
        raise MigrationError("Unsafe Btrfs exchange path")
    for key in ("rootId", "homeId", "homeSourceId", "targetRootId", "targetHomeId"):
        if key in exchange and (type(exchange[key]) is not int or exchange[key] < 256):
            raise MigrationError("Invalid Btrfs subvolume ID")
    identities = [exchange[key] for key in ("rootId", "homeId", "targetRootId", "targetHomeId") if key in exchange]
    if len(identities) != len(set(identities)):
        raise MigrationError("Btrfs exchange subvolumes must have distinct IDs")
    if "rootId" not in exchange or ("homeBackup" in exchange and "homeId" not in exchange):
        raise MigrationError("Missing original Btrfs subvolume identity")


def source_home(state):
    prefix = state.get("homePrefix", state["sourcePrefix"] + "/home")
    exchange = state.get("exchange")
    if exchange:
        if "homeBackup" in exchange and (TOP / exchange["homeBackup"]).exists():
            home = TOP / exchange["homeBackup"]
            if home.is_symlink() or subvolume_id(home) != exchange["homeId"]:
                raise MigrationError("Preserved home subvolume identity changed")
            return home
        if prefix.startswith(state["sourcePrefix"] + "/"):
            prefix = source_prefix(state) + prefix[len(state["sourcePrefix"]):]
    path = TOP / prefix.lstrip("/")
    if not path.is_dir() or path.is_symlink() or not path.resolve().is_relative_to(TOP.resolve()):
        raise MigrationError("Preserved home is missing or escapes the source filesystem")
    if exchange and "homeSourceId" in exchange and subvolume_id(path) != exchange["homeSourceId"]:
        raise MigrationError("Original home subvolume identity changed")
    return path


def source_prefix(state):
    exchange = state.get("exchange")
    if not exchange:
        return state["sourcePrefix"]
    backup = TOP / exchange["rootBackup"]
    source = backup if backup.exists() else TOP / "@"
    if source.is_symlink() or subvolume_id(source) != exchange["rootId"]:
        raise MigrationError("Original Btrfs root subvolume identity changed")
    return "/" + source.name


def exchange_subvolumes(state):
    """Resumable source-preserving renames, with IDs persisted before exchange."""
    validate_exchange(state)
    source_prefix(state)
    source_home(state)
    exchange = state["exchange"]

    def task_path():
        return TOP / source_prefix(state).lstrip("/") / state["task"].lstrip("/")

    # Reject existing destinations before creating or renaming anything.
    if "homeBackup" not in exchange and (TOP / "@genesi-home").exists() and "targetHomeId" not in exchange:
        raise MigrationError("An unrelated @genesi-home already exists")
    for key, name in (("Root", "rootNext"), ("Home", "homeNext")):
        temporary = TOP / exchange[name]
        destination = TOP / ("@" if key == "Root" else "@genesi-home")
        identity = "target" + key + "Id"
        if identity not in exchange:
            if temporary.exists():
                raise MigrationError("Unrecorded migration subvolume exists; keep staging for recovery")
            run("btrfs", "subvolume", "create", temporary)
            exchange[identity] = subvolume_id(temporary)
            save(task_path() / "state.json", state)
        elif temporary.exists():
            if temporary.is_symlink() or subvolume_id(temporary) != exchange[identity]:
                raise MigrationError("Migration temporary subvolume identity changed")
        elif not destination.exists() or destination.is_symlink() or subvolume_id(destination) != exchange[identity]:
            raise MigrationError("Migration target subvolume is missing or changed")
    state["phase"] = "converted"
    save(task_path() / "state.json", state)
    # The rescue loader knows both paths, including the power-loss interval
    # after the old @ was moved but before its replacement is published.
    if not (TOP / exchange["rootBackup"]).exists():
        source_prefix(state)
        os.rename(TOP / "@", TOP / exchange["rootBackup"])
        os.sync()
    if "homeBackup" in exchange and not (TOP / exchange["homeBackup"]).exists():
        old_home = TOP / "@genesi-home"
        if old_home.is_symlink() or subvolume_id(old_home) != exchange["homeId"]:
            raise MigrationError("Original home subvolume identity changed")
        os.rename(old_home, TOP / exchange["homeBackup"])
        os.sync()
    for name, destination in (("rootNext", "@"), ("homeNext", "@genesi-home")):
        temporary = TOP / exchange[name]
        if temporary.exists():
            if (TOP / destination).exists():
                raise MigrationError("Refusing to replace an occupied Btrfs destination")
            os.rename(temporary, TOP / destination)
            os.sync()
    return task_path()


def recovery_config(state):
    prefix = state["sourcePrefix"]
    task = prefix + state["task"]
    root_id = state["rootUuid"]
    if not re.fullmatch(r"[a-zA-Z0-9-]+", root_id) or not re.fullmatch(r"[/a-zA-Z0-9_.@-]+", task):
        raise MigrationError("Unsafe GRUB path")
    task_selector = "set genesi_task=" + task + "\n"
    if state.get("exchange"):
        fallback = "/" + state["exchange"]["rootBackup"] + state["task"]
        task_selector += "if [ -f ($root)%s/migrate-vmlinuz ]; then\n  set genesi_task=%s\nfi\n" % (fallback, fallback)
    return """set timeout=8
insmod all_video
set gfxmode=1024x768,auto
insmod gfxterm
terminal_output gfxterm
set gfxpayload=keep
insmod btrfs
insmod ext2
search --no-floppy --fs-uuid --set=root %s
if [ -f ($root)/@/%s ]; then
  configfile ($root)/@/boot/grub/grub.cfg
fi
menuentry 'Continue Genesi migration / recovery' {
  search --no-floppy --fs-uuid --set=root %s
%s  linux ($root)$genesi_task/migrate-vmlinuz root=UUID=%s rw rootflags=subvol=@ fsck.mode=skip genesi.migrate=UUID=%s:$genesi_task
  initrd ($root)$genesi_task/migrate-initramfs.img
}
menuentry 'Original boot menu (before migration only)' {
  configfile ($root)%s/boot/grub/grub.cfg
}
""" % (root_id, ready_marker(state), root_id, task_selector, root_id, root_id, prefix)


def maintenance_hooks():
    install = r'''#!/bin/bash
build() {
    local tool stdlib file
    for tool in bash python3 btrfs btrfs-convert e2fsck lsblk findmnt mount umount swapon rsync cp chroot arch-chroot unshare udevadm sync blkid realpath readlink mountpoint; do
        add_binary "$tool" || return 1
    done
    stdlib=$(python3 -c 'import sysconfig; print(sysconfig.get_path("stdlib"))') || return 1
    while IFS= read -r -d '' file; do
        case "$file" in
            */site-packages/*|*/__pycache__/*|*/test/*|*/tests/*|*.pyc|*/tkinter/*|*/idlelib/*|*/turtledemo/*|*/_tkinter*.so|*/_test*.so) continue ;;
            *.so) add_binary "$file" || return 1 ;;
            *) add_file "$file" || return 1 ;;
        esac
    done < <(find "$stdlib" -type f -print0)
    add_file /usr/lib/genesi-migrate/native.py
    add_file /etc/genesi-native-initramfs
    add_runscript
}
help() { echo 'Offline Genesi migration before the real root is mounted.'; }
'''
    runtime = r'''#!/usr/bin/ash
run_hook() {
    mount_handler=genesi_native_mount
}
genesi_native_stop() {
    err 'Genesi migration stopped. No desktop or installer will be started.'
    err 'Keep this screen and the migration files for diagnosis.'
    while :; do launch_interactive_shell; done
}
genesi_native_mount() {
    local locator
    locator=$(getarg genesi.migrate)
    [ -n "$locator" ] || { genesi_native_stop; return 1; }
    mkdir -p /dev/pts /dev/shm || { genesi_native_stop; return 1; }
    chmod 1777 /dev/shm || { genesi_native_stop; return 1; }
    msg 'Genesi: finishing migration. Do not turn off the computer.'
    /usr/bin/python3 -B /usr/lib/genesi-migrate/native.py boot-offline "$locator" || { genesi_native_stop; return 1; }
    mount -t btrfs -o rw,noatime,compress=zstd,subvol=@ "$root" "$1" || { genesi_native_stop; return 1; }
    msg 'Genesi is ready. Starting your system...'
}
'''
    return install, runtime


def build_maintenance(root, task):
    """Build only an initramfs, never an archiso or a live desktop."""
    root, task = Path(root), Path(task)
    kernels = sorted((root / "boot").glob("vmlinuz-*"))
    if not kernels:
        raise MigrationError("Prepared system has no maintenance kernel")
    kernel = kernels[0]
    install, runtime = maintenance_hooks()
    files = {
        root / "etc/genesi-native-initramfs": MAINTENANCE_VERSION + "\n",
        root / "etc/genesi-native-mkinitcpio.conf":
            'MODULES=(btrfs ext4)\nBINARIES=()\nFILES=()\n'
            'HOOKS=(base udev modconf block keyboard filesystems genesi_native)\n'
            'COMPRESSION="zstd"\n',
        root / "usr/lib/initcpio/install/genesi_native": install,
        root / "usr/lib/initcpio/hooks/genesi_native": runtime,
    }
    if any(path.exists() or path.is_symlink() for path in files):
        raise MigrationError("Maintenance build paths already exist")
    image = root / "boot/genesi-migrate-initramfs.img"
    try:
        for path, content in files.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        with mounted("/proc", root / "proc", "--bind", helper_root=root), \
             mounted("/dev", root / "dev", "--rbind", helper_root=root), \
             mounted("/sys", root / "sys", "--rbind", helper_root=root):
            run("chroot", root, "mkinitcpio", "-c", "/etc/genesi-native-mkinitcpio.conf",
                "-k", "/boot/" + kernel.name, "-g", "/boot/genesi-migrate-initramfs.img", reserve_at=BASE)
        if not image.is_file() or not 0 < image.stat().st_size <= MAX_MAINTENANCE_IMAGE:
            raise MigrationError("Maintenance initramfs is missing or exceeds the 192 MiB size limit")
        listing = set(run("chroot", root, "lsinitcpio", "/boot/genesi-migrate-initramfs.img").splitlines())
        required = {"init", "hooks/genesi_native", "usr/bin/python3", "usr/bin/btrfs-convert",
                    "usr/bin/e2fsck", "usr/bin/rsync", "usr/bin/arch-chroot", "usr/bin/realpath",
                    "usr/lib/genesi-migrate/native.py", "etc/genesi-native-initramfs"}
        if not required <= {name.lstrip("/") for name in listing}:
            raise MigrationError("Maintenance initramfs is missing required tools")
        shutil.copyfile(image, task / "migrate-initramfs.img")
        shutil.copyfile(kernel, task / "migrate-vmlinuz")
        (task / "recovery.cfg").write_text(recovery_config(json.loads((task / "state.json").read_text())))
        with mounted("/proc", root / "proc", "--bind", helper_root=root), \
             mounted("/dev", root / "dev", "--rbind", helper_root=root), \
             mounted(task, root / "genesi-native", "--bind", helper_root=root):
            verify_maintenance(root, task)
            run("chroot", root, "grub-script-check", "/genesi-native/recovery.cfg")
            run("chroot", root, "grub-mkstandalone", "-O", "x86_64-efi",
                "--modules=part_gpt part_msdos fat ext2 btrfs search_fs_uuid linux normal configfile",
                "-o", "/genesi-native/rescue.efi", "boot/grub/grub.cfg=/genesi-native/recovery.cfg")
    finally:
        for path in files:
            path.unlink(missing_ok=True)
        image.unlink(missing_ok=True)


def verify_maintenance(root, task):
    """Exercise the packed interpreter and chroot tools before arming boot."""
    check = task / "maintenance-check"
    check.mkdir(mode=0o700)
    run("chroot", root, "bash", "-euc",
        "cd /genesi-native/maintenance-check; lsinitcpio -x /boot/genesi-migrate-initramfs.img")
    for name in ("proc", "sys", "dev", "run", "target-root"):
        (check / name).mkdir(parents=True, exist_ok=True)
    with mounted("/proc", check / "proc", "--bind", helper_root=check), \
         mounted("/sys", check / "sys", "--rbind", helper_root=check), \
         mounted("/dev", check / "dev", "--rbind", helper_root=check), \
         mounted(root, check / "target-root", "--bind", helper_root=check):
        run("chroot", check, "python3", "-B", "/usr/lib/genesi-migrate/native.py", "--help")
        run("chroot", check, "arch-chroot", "/target-root", "/usr/bin/true")
    mounts = json.loads(run("findmnt", "--json", "--list", "--output", "TARGET"))["filesystems"]
    if any(m["target"] == str(check) or m["target"].startswith(str(check) + "/") for m in mounts):
        raise MigrationError("Maintenance self-check still has mounted filesystems; retained for diagnosis")
    shutil.rmtree(check)


def arm(state, task):
    disk, _, esp = identify(state, inventory())
    with mounted(esp["path"], task / "esp") as mount:
        destination = mount / "EFI/GenesiMigrate"
        if destination.exists():
            raise MigrationError("An earlier migration EFI loader exists; inspect it before retrying")
        require_free_space(mount, (task / "rescue.efi").stat().st_size + 8 * 1024 ** 2, "EFI recovery loader")
        destination.mkdir()
        shutil.copyfile(task / "rescue.efi", destination / "grubx64.efi")
        os.sync()
    # Save the old order for an operator to restore, never remove old entries.
    state["efiBefore"] = run("efibootmgr", "-v")
    save(task / "state.json", state)
    partition = run("lsblk", "-n", "-o", "PARTN", esp["path"])
    state["phase"] = "armed"
    save(task / "state.json", state)
    run("efibootmgr", "-c", "-d", disk["path"], "-p", partition,
        "-L", "Genesi Migrate Recovery", "-l", "\\EFI\\GenesiMigrate\\grubx64.efi")
    current = run("efibootmgr", "-v")
    old = set(re.findall(r"^Boot([0-9A-Fa-f]{4})\*? ", state["efiBefore"], re.M))
    added = set(re.findall(r"^Boot([0-9A-Fa-f]{4})\*? ", current, re.M)) - old
    if len(added) != 1:
        raise MigrationError("EFI entry was added but could not be identified; inspect firmware before reboot")
    state["efiEntry"] = added.pop()
    previous_order = re.search(r"^BootOrder: ([0-9A-Fa-f,]+)$", state["efiBefore"], re.M)
    if not previous_order:
        raise MigrationError("EFI boot order could not be recorded")
    run("efibootmgr", "-o", state["efiEntry"] + "," + previous_order[1])
    state["rescueHash"] = digest(task / "rescue.efi")
    save(task / "state.json", state)


def retire_previous_boot_tasks(current):
    # Retrying after a failed pre-conversion boot must not leave the old ISO
    # loader active. Retire only our verified tasks on this exact source disk.
    for task in sorted(BASE.iterdir()):
        if task.is_symlink() or not task.is_dir():
            continue
        try:
            previous = json.loads((task / "state.json").read_text())
        except (OSError, ValueError):
            continue
        if (previous.get("schema") == "native-v1" and previous.get("phase") == "armed"
                and previous.get("rootUuid") == current["rootUuid"]):
            identify(previous, inventory())
            disarm(task)


def disarm(task_path):
    task = Path(task_path).resolve()
    if task.parent != BASE or task.is_symlink():
        raise MigrationError("Invalid native task path")
    state = json.loads((task / "state.json").read_text())
    if state["phase"] != "armed":
        raise MigrationError("Migration can only be cancelled before offline conversion")
    _, root, esp = identify(state, inventory())
    if root.get("fstype") != state["originalFs"]:
        raise MigrationError("Source filesystem changed; cancellation requires recovery")
    order = re.search(r"^BootOrder: ([0-9A-Fa-f,]+)$", state["efiBefore"], re.M)
    entry = state.get("efiEntry", "")
    if not order or not re.fullmatch(r"[0-9A-Fa-f]{4}", entry):
        raise MigrationError("Original EFI order is unavailable")
    with mounted(esp["path"], task / "esp") as mount:
        path = mount / "EFI/GenesiMigrate/grubx64.efi"
        if not path.is_file() or digest(path) != state.get("rescueHash"):
            raise MigrationError("Previous migration EFI loader changed; refusing to remove it")
    run("efibootmgr", "-o", order[1])
    run("efibootmgr", "-b", entry, "-B")
    with mounted(esp["path"], task / "esp") as mount:
        path = mount / "EFI/GenesiMigrate/grubx64.efi"
        if path.is_file() and digest(path) == state["rescueHash"]:
            path.unlink()
            path.parent.rmdir()
    state["phase"] = "cancelled"
    save(task / "state.json", state)


def assert_offline(root):
    if root.get("mountpoints") and any(root["mountpoints"]):
        raise MigrationError("Root partition is still mounted; refusing conversion")
    swaps = run("swapon", "--show", "--noheadings", "--raw", "--output", "NAME")
    if root["path"] in swaps.splitlines():
        raise MigrationError("Root partition is active swap")


def assert_maintenance():
    if not MAINTENANCE_MARKER.is_file() or MAINTENANCE_MARKER.read_text().strip() != MAINTENANCE_VERSION:
        raise MigrationError("Offline migration requires the dedicated Genesi migration initramfs")
    if run("findmnt", "-n", "-o", "FSTYPE", "/") not in ("rootfs", "tmpfs", "ramfs"):
        raise MigrationError("Maintenance root must be independent of all disks")


def boot_offline(locator):
    """Read only the state into RAM, release the source, then convert offline."""
    assert_maintenance()
    match = re.fullmatch(r"UUID=([A-Za-z0-9-]+):(/[A-Za-z0-9_./@-]+)", locator)
    if not match or ".." in match[2].split("/"):
        raise MigrationError("Invalid migration boot locator")
    root_uuid, location = match.groups()
    sources = [p for p in walk(inventory()) if p.get("type") == "part" and p.get("uuid") == root_uuid]
    if len(sources) != 1 or sources[0].get("fstype") not in ("ext4", "btrfs"):
        raise MigrationError("Migration source partition is missing or ambiguous")
    source = sources[0]
    assert_offline(source)
    options = "ro,rescue=nologreplay,subvolid=5" if source["fstype"] == "btrfs" else "ro,noload"
    with mounted(source["path"], TOP, "-o", options):
        source_task = TOP / location.lstrip("/")
        if not source_task.resolve().is_relative_to(TOP.resolve()):
            raise MigrationError("Migration state escapes the source root")
        state = json.loads((source_task / "state.json").read_text())
        validate_exchange(state)
        locations = [state.get("sourcePrefix", "") + state.get("task", "")]
        if state.get("exchange"):
            locations.append("/" + state["exchange"]["rootBackup"] + state["task"])
        if (state.get("rootUuid") != root_uuid
                or location not in locations):
            raise MigrationError("Migration boot locator differs from verified state")
        ram = RAM_STATE
        ram.mkdir(mode=0o700, exist_ok=True)
        save(ram / "state.json", state)
    offline(ram)


def offline(task_path):
    assert_maintenance()
    # Only this small worker and state live in initramfs. The prepared system
    # remains on disk; there is no ISO, loopback live root or desktop in RAM.
    state = json.loads((Path(task_path) / "state.json").read_text())
    if state.get("schema") != "native-v1" or PurePosixPath(state.get("task", "")).parent != PurePosixPath("/var/lib/genesi-migrate-native"):
        raise MigrationError("Unsupported or invalid migration state")
    if not re.fullmatch(r"[/A-Za-z0-9_.@-]*", state.get("sourcePrefix", "")) or ".." in state.get("sourcePrefix", ""):
        raise MigrationError("Invalid source subvolume path")
    if not re.fullmatch(r"[a-z_][a-z0-9_-]{0,30}", state.get("user", {}).get("name", "")):
        raise MigrationError("Invalid preserved account")
    validate_exchange(state)
    home_prefix = state.get("homePrefix", state["sourcePrefix"] + "/home")
    if not re.fullmatch(r"/[A-Za-z0-9_./@-]+", home_prefix) or ".." in PurePosixPath(home_prefix).parts:
        raise MigrationError("Invalid preserved home path")
    _, root, _ = identify(state, inventory())
    assert_offline(root)
    if state["phase"] not in ("armed", "converted"):
        raise MigrationError("Migration phase requires manual recovery: " + state["phase"])
    device = root["path"]
    readonly_options = "ro,rescue=nologreplay,subvolid=5" if root.get("fstype") == "btrfs" else "ro,noload"
    with mounted(device, TOP, "-o", readonly_options):
        legacy_marker = TOP / "@/var/lib/genesi-migrate/boot-ready"
        completed = (TOP / "@" / ready_marker(state)).exists()
        if legacy_marker.is_file():
            completed = completed or not state.get("exchange") or json.loads(legacy_marker.read_text()).get("task") == state["task"]
        if completed:
            raise MigrationError("Genesi was already configured; choose its normal boot entry. Home will not be overwritten")
        source_task = TOP / source_prefix(state).lstrip("/") / state["task"].lstrip("/")
        source_home(state)
        target_valid(source_task / "target-root")
        if root_hash(source_task / "target-root") != state["rootHash"]:
            raise MigrationError("Prepared artifact failed verification before conversion")
        if state["phase"] == "armed":
            require_free_space(TOP, state["expandedBytes"] + 8 * GIB, "Offline conversion reserve")
    if root.get("fstype") == "ext4":
        # Read-only check. Repairs are not silently accepted on a user's root.
        run("e2fsck", "-f", "-n", device)
        # Record the intent in RAM; conversion rollback metadata stays on disk.
        run("btrfs-convert", "--uuid", "copy", device)
    elif root.get("fstype") != "btrfs":
        raise MigrationError("Source filesystem is neither clean ext4 nor Btrfs")
    run("btrfs", "check", "--readonly", device)
    with mounted(device, TOP, "-t", "btrfs", "-o", "subvolid=5"):
        task = TOP / source_prefix(state).lstrip("/") / state["task"].lstrip("/")
        prepared = task / "target-root"
        target_valid(prepared)
        if root_hash(prepared) != state["rootHash"]:
            raise MigrationError("Prepared root changed; refusing to switch")
        if state.get("exchange"):
            task = exchange_subvolumes(state)
            prepared = task / "target-root"
        elif state["phase"] == "armed":
            if (TOP / "@").exists() or (TOP / "@genesi-home").exists():
                raise MigrationError("Reserved Genesi subvolumes already exist")
            state["phase"] = "converted"
            save(task / "state.json", state)
        if not (TOP / "@").exists():
            run("btrfs", "subvolume", "create", TOP / "@")
        if not (TOP / "@genesi-home").exists():
            run("btrfs", "subvolume", "create", TOP / "@genesi-home")
        run("rsync", "-aHAX", "--numeric-ids", "--one-file-system", str(prepared) + "/", str(TOP / "@") + "/", reserve_at=TOP)
        run("cp", "-a", "--reflink=always", str(source_home(state)) + "/.", TOP / "@genesi-home", reserve_at=TOP)
        new_home = TOP / "@genesi-home" / state["user"]["name"]
        new_home.mkdir(exist_ok=True)
        apply_desktop_home(prepared, new_home, state, task)
        with mounted(device, TARGET, "-t", "btrfs", "-o", "subvol=@"):
            (TARGET / "home").mkdir(exist_ok=True)
            with mounted(device, TARGET / "home", "-t", "btrfs", "-o", "subvol=@genesi-home"):
                configure(state, task, device)
        state["phase"] = "configured"
        save(task / "state.json", state)
    os.sync()
    print("Migration configured. Continuing this boot into Genesi.", flush=True)


def refresh_converted_filesystem(device):
    # udev can still advertise ext4 after btrfs-convert. libmount consumers
    # such as grub-btrfs must see the new type, not just our explicit -t mounts.
    if run("blkid", "-p", "-s", "TYPE", "-o", "value", device) != "btrfs":
        raise MigrationError("Converted root does not probe as Btrfs")
    run("udevadm", "trigger", "--action=change", "--sysname-match=" + Path(device).name)
    run("udevadm", "settle", "--timeout=30")
    properties = run("udevadm", "info", "--query=property", "--name", device)
    if "ID_FS_TYPE=btrfs" not in properties.splitlines():
        raise MigrationError("udev still has an outdated root filesystem type; refusing to generate GRUB")
    if run("arch-chroot", TARGET, "blkid", "-c", "/dev/null", "-s", "TYPE", "-o", "value", device) != "btrfs":
        raise MigrationError("Installed system does not identify its root as Btrfs")


def configure(state, task, device):
    refresh_converted_filesystem(device)
    _, _, esp = identify(state, inventory())
    fstab = ("UUID=%s / btrfs defaults,noatime,compress=zstd,subvol=@ 0 0\n"
             "UUID=%s /home btrfs defaults,noatime,compress=zstd,subvol=@genesi-home 0 0\n"
             "UUID=%s /boot/efi vfat umask=0077 0 2\n") % (state["rootUuid"], state["rootUuid"], state["espUuid"])
    (TARGET / "etc/fstab").write_text(fstab)
    (TARGET / "etc/mkinitcpio.conf.d/99-genesi-native-staging.conf").unlink(missing_ok=True)
    with mounted(esp["path"], TARGET / "boot/efi"):
        run("arch-chroot", TARGET, "mkinitcpio", "-P")
        run("arch-chroot", TARGET, "grub-install", "--target=x86_64-efi", "--efi-directory=/boot/efi",
            "--bootloader-id=GenesiOS", "--no-nvram", "--modules=btrfs")
        run("arch-chroot", TARGET, "grub-mkconfig", "-o", "/boot/grub/grub.cfg.native-new")
        run("arch-chroot", TARGET, "grub-script-check", "/boot/grub/grub.cfg.native-new")
        menu = TARGET / "boot/grub/grub.cfg.native-new"
        text = menu.read_text()
        if "vmlinuz" not in text or "subvol=@" not in text:
            raise MigrationError("Generated GRUB menu has no Genesi kernel/subvolume")
        with menu.open("rb") as stream:
            os.fsync(stream.fileno())
        os.replace(menu, TARGET / "boot/grub/grub.cfg")
    marker = TARGET / "var/lib/genesi-migrate/boot-ready"
    marker.parent.mkdir(parents=True, exist_ok=True)
    os.sync()
    save(marker, {"phase": "boot-ready", "schema": "native-v1", "task": state["task"]})
    save(TARGET / ready_marker(state), {"phase": "boot-ready", "task": state["task"]})


def staging_initramfs(root):
    # autodetect cannot resolve the future root through nested preparation
    # chroots. Build a portable image now; offline configure removes this
    # drop-in and restores normal autodetect on the real mounted Btrfs root.
    config = Path(root) / "etc/mkinitcpio.conf.d/99-genesi-native-staging.conf"
    config.parent.mkdir(parents=True, exist_ok=True)
    config.write_text('''_genesi_hooks=()
for _genesi_hook in "${HOOKS[@]}"; do
    [[ "$_genesi_hook" == autodetect ]] || _genesi_hooks+=("$_genesi_hook")
done
HOOKS=("${_genesi_hooks[@]}")
MODULES+=(btrfs ext4)
unset _genesi_hook _genesi_hooks
''')
    (Path(root) / "etc/vconsole.conf").write_text("KEYMAP=us\n")


def install_finish(root, manifest, state):
    directory = root / "var/lib/genesi-migrate"
    directory.mkdir(parents=True, exist_ok=True)
    save(directory / "manifest.json", manifest)
    save(directory / "install-report.json", state.get("apps", {}))
    save(directory / "status.json", {"files": {"state": "done", "copied": 0}})
    (directory / "user").write_text(state["user"]["name"])
    (directory / "pending").touch()
    # The selected user may read their own migration report at login.
    for path in directory.iterdir():
        os.chown(path, 0, state["user"]["gid"])
        path.chmod(0o640)
    directory.chmod(0o750)
    os.chown(directory, 0, state["user"]["gid"])
    shutil.copyfile(__file__, root / "usr/lib/genesi-migrate/native.py")
    units = root / "etc/systemd/system"
    (units / "genesi-migrate-restore.service").write_text("""[Unit]
Description=Finish Genesi migration apps
Wants=network-online.target
After=network-online.target
ConditionPathExists=/var/lib/genesi-migrate/pending
[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /usr/lib/genesi-migrate/restore.py --system
TimeoutStartSec=infinity
[Install]
WantedBy=multi-user.target
""")
    (units / "genesi-migrate-health.service").write_text("""[Unit]
Description=Confirm native Genesi migration boot
After=local-fs.target display-manager.service
ConditionPathExists=/var/lib/genesi-migrate/boot-ready
[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /usr/lib/genesi-migrate/native.py health /var/lib/genesi-migrate
[Install]
WantedBy=graphical.target
""")
    run("systemctl", "--root", root, "enable", "genesi-migrate-restore.service", "genesi-migrate-health.service", "genesi-snapshots-setup.service")
    auto = root / "etc/xdg/autostart/genesi-migrate-finish.desktop"
    auto.parent.mkdir(parents=True, exist_ok=True)
    auto.write_text("[Desktop Entry]\nType=Application\nName=Genesi Migrate\nExec=/usr/bin/python3 /usr/lib/genesi-migrate/restore.py --user\nNoDisplay=true\n")


def health(path):
    if run("findmnt", "-n", "-o", "FSTYPE", "/") != "btrfs" or run("findmnt", "-n", "-o", "FSROOT", "/") != "/@":
        raise MigrationError("Genesi is not running from its expected Btrfs root")
    if run("findmnt", "-n", "-o", "FSTYPE", "/home") != "btrfs":
        raise MigrationError("Preserved home is not mounted")
    run("systemctl", "is-active", "display-manager.service")
    save(Path(path) / "healthy.json", {"healthy": True, "root": "@", "home": "@genesi-home"})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("prepare", "offline", "boot-offline", "health", "disarm"))
    parser.add_argument("paths", nargs="+")
    args = parser.parse_args()
    if sys.platform != "linux" or os.geteuid() != 0:
        parser.exit(2, "Native migration requires Linux root inside a private mount namespace\n")
    import fcntl
    with open("/run/genesi-native.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        try:
            if args.mode == "prepare":
                prepare(*args.paths)
            elif args.mode == "offline":
                offline(*args.paths)
            elif args.mode == "boot-offline":
                boot_offline(*args.paths)
            elif args.mode == "disarm":
                disarm(*args.paths)
            else:
                health(*args.paths)
        except Exception as exc:
            print("Genesi migration stopped. Keep staging for diagnosis. Error:", exc, file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
