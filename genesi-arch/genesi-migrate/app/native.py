"""Native migration: prepare an installed tree, then switch offline.

No action runs on import. The root helper invokes prepare in a private mount
namespace. The live medium invokes offline after copying this file to RAM.
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
LIVE_MARKER = Path("/run/archiso/bootmnt")
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
    if int(machine.get("ramBytes") or 0) < 7 * GIB:
        raise MigrationError("Native maintenance requires at least 8 GB of installed RAM")
    if machine.get("firmware") not in ("uefi", "efi") or machine.get("secureBoot"):
        raise MigrationError("Native migration requires UEFI with Secure Boot disabled")
    if machine.get("luks") or machine.get("rootPartType") != "part" or machine.get("homeSeparate"):
        raise MigrationError("Encrypted/LVM roots and separate /home are not supported by native migration yet")
    if machine.get("rootFs") not in ("ext4", "btrfs"):
        raise MigrationError("This filesystem cannot be converted safely; supported roots: ext4, Btrfs")
    if re.search(r"(?:^|,)subvol=/?@(?:,|$)", machine.get("rootOptions", "")):
        raise MigrationError("Existing @ roots require subvolume exchange and are not enabled yet")
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
def mounted(source, destination, *options):
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    run("mount", *options, source, destination)
    primary_error = None
    try:
        yield destination
    except BaseException as exc:
        primary_error = exc
        raise
    finally:
        try:
            stop_mount_helpers(destination)
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
    # require both this namespace and a root beneath the exact owned mount.
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


def native_iso_supported(launcher):
    """Recognize the shipped v1 launcher, whose cmdline regex escapes dots.

    Check both argument handling and the offline dispatch, not an unescaped
    keyword that might only be present in a comment.
    """
    launcher = Path(launcher)
    if not launcher.is_file():
        return False
    text = launcher.read_text()
    return all(token in text for token in (
        "native_arg()", r"genesi\.native=", "\nnative-offline)",
        '"$RUN/native/native.py" offline',
    ))


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
        "-G", "wheel", "-s", "/bin/bash", "-d", user.pw_dir, "-c", user.pw_gecos, name)
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
    for app in manifest.get("apps", []):
        if app.get("selected") and app.get("target") and not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9@+_.:-]*", app["target"]):
            raise MigrationError("Unsafe application package name")
    if digest(iso_path) != checksum:
        raise MigrationError("ISO checksum changed before privileged preparation")
    for tool in ("mount", "losetup", "unshare", "chroot", "efibootmgr"):
        if not shutil.which(tool):
            raise MigrationError("Install required host tool before retrying: " + tool)
    # Root-owned private directory: the old user's writable download stage is
    # never executed by the maintenance environment.
    if BASE.exists() and (BASE.is_symlink() or BASE.stat().st_uid != 0):
        raise MigrationError("Native staging directory is not root-owned")
    BASE.mkdir(mode=0o700, parents=True, exist_ok=True)
    BASE.chmod(0o700)
    task = BASE / str(uuid.uuid4())
    task.mkdir(mode=0o700)
    LOG = task / "prepare.log"
    state["task"] = str(task)
    state["sourcePrefix"] = run("findmnt", "-n", "-o", "FSROOT", "/").rstrip("/")
    if not re.fullmatch(r"[/a-zA-Z0-9_.@-]*", state["sourcePrefix"]):
        raise MigrationError("Unsupported source subvolume path")
    if state["sourcePrefix"] == "/@":
        raise MigrationError("Existing @ root requires a subvolume exchange; this layout is not enabled yet")
    require_free_space(BASE, MIN_PREP_FREE, "Preparation and conversion reserve")
    shutil.copyfile(iso_path, task / "genesi.iso")
    if digest(task / "genesi.iso") != checksum:
        raise MigrationError("ISO changed during staging; migration was not armed")
    shutil.copyfile(__file__, task / "native.py")
    save(task / "manifest.json", manifest)
    save(task / "state.json", state)
    profiles = json.loads(Path(profile_path).read_text())
    packages = profiles.get(manifest["choices"]["desktop"])
    if not packages:
        raise MigrationError("No native package profile exists for the selected desktop")
    packages = [p.replace("$LOCALE", "en-us") for p in packages]
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
            launcher = lower / "usr/local/bin/genesi-migrate-live"
            if not native_iso_supported(launcher):
                raise MigrationError("This ISO predates native migration. Wait for the updated ISO and retry")
            for name in ("upper", "work", "runner"):
                (task / name).mkdir()
            options = "lowerdir=%s,upperdir=%s,workdir=%s" % (lower, task / "upper", task / "work")
            with mounted("overlay", task / "runner", "-t", "overlay", "-o", options) as runner:
                # Use archiso's Arch userspace, not Mint's package manager.
                resolver = runner / "etc/resolv.conf"
                if resolver.is_symlink():
                    resolver.unlink()
                shutil.copyfile("/etc/resolv.conf", resolver)
                with mounted(task, runner / "genesi-native", "--bind"):
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
                    with mounted("/dev", runner / "host-dev", "--rbind"):
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
                with mounted(task, runner / "genesi-native", "--bind"):
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
                # Build a standalone rescue loader with embedded filesystem
                # modules. It keeps working after ext4 becomes Btrfs.
                recovery = recovery_config(state)
                finish = lower / "usr/lib/genesi-migrate/restore.py"
                if not finish.is_file():
                    raise MigrationError("ISO has no migration app-restoration worker")
                dest = root / "usr/lib/genesi-migrate"
                dest.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(finish, dest / "restore.py")
                (task / "recovery.cfg").write_text(recovery)
                with mounted(task, runner / "genesi-native", "--bind"):
                    run("chroot", runner, "grub-mkstandalone", "-O", "x86_64-efi",
                        "--modules=part_gpt part_msdos fat ext2 btrfs search_fs_uuid loopback iso9660 linux normal configfile",
                        "-o", "/genesi-native/rescue.efi", "boot/grub/grub.cfg=/genesi-native/recovery.cfg")
    root.joinpath("etc/hostname").write_text("genesi\n")
    release = root / "etc/os-release"
    if release.is_symlink():
        release.unlink()
    release.write_text('NAME="Genesi OS"\nPRETTY_NAME="Genesi OS"\nID=genesi\nID_LIKE="cachyos arch"\nBUILD_ID=rolling\nHOME_URL="https://genesios.org"\nDOCUMENTATION_URL="https://wiki.genesios.org"\nLOGO=genesi\n')
    root.joinpath("etc/lsb-release").write_text('DISTRIB_ID="Genesi OS"\nDISTRIB_RELEASE="rolling"\nDISTRIB_DESCRIPTION="Genesi OS"\n')
    root.joinpath("etc/locale.gen").write_text("en_US.UTF-8 UTF-8\npt_BR.UTF-8 UTF-8\n")
    root.joinpath("etc/locale.conf").write_text("LANG=" + ("pt_BR.UTF-8" if manifest["choices"].get("language") == "pt_BR" else "en_US.UTF-8") + "\n")
    run("chroot", root, "locale-gen")
    run("systemctl", "--root", root, "enable", "NetworkManager.service")
    managers = [n for n in ("sddm", "gdm", "lightdm", "lxdm", "cosmic-greeter") if (root / ("usr/lib/systemd/system/" + n + ".service")).exists()]
    if not managers:
        raise MigrationError("Selected desktop has no supported display manager")
    run("systemctl", "--root", root, "enable", managers[0] + ".service")
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
    run("chroot", root, "systemd-machine-id-setup")
    install_finish(root, manifest, state)
    target_valid(root)
    expanded = sum(p.stat().st_size for p in root.rglob("*") if p.is_file() and not p.is_symlink())
    require_free_space(BASE, expanded + 8 * GIB, "Conversion and final Genesi tree")
    state.update(phase="ready", rootHash=root_hash(root), isoHash=checksum, expandedBytes=expanded)
    save(task / "state.json", state)
    # Arming is the last write, after all downloads, packages and validation.
    arm(state, task)
    print(json.dumps({"ready": True, "task": str(task)}), flush=True)


def recovery_config(state):
    prefix = state["sourcePrefix"]
    task = prefix + state["task"]
    root_id = state["rootUuid"]
    if not re.fullmatch(r"[a-zA-Z0-9-]+", root_id) or not re.fullmatch(r"[/a-zA-Z0-9_.@-]+", task):
        raise MigrationError("Unsafe GRUB path")
    return """set timeout=8
insmod all_video
set gfxmode=1024x768,auto
insmod gfxterm
terminal_output gfxterm
set gfxpayload=keep
insmod btrfs
insmod ext2
search --no-floppy --fs-uuid --set=root %s
if [ -f ($root)/@/var/lib/genesi-migrate/boot-ready ]; then
  menuentry 'Genesi OS' {
    configfile ($root)/@/boot/grub/grub.cfg
  }
fi
menuentry 'Continue Genesi migration / recovery' {
  search --no-floppy --fs-uuid --set=root %s
  loopback loop %s/genesi.iso
  linux (loop)/arch/boot/x86_64/vmlinuz-linux-cachyos-lts archisobasedir=arch img_dev=UUID=%s img_loop=%s/genesi.iso copytoram=y genesi.native=UUID=%s:%s module_blacklist=pcspkr
  initrd (loop)/arch/boot/x86_64/initramfs-linux-cachyos-lts.img
}
menuentry 'Original boot menu (before conversion only)' {
  configfile ($root)%s/boot/grub/grub.cfg
}
""" % (root_id, root_id, task, root_id, task, root_id, task, prefix)


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


def release_iso(state, device):
    """Release only archiso's source ISO after copytoram, never other mounts."""
    copies = Path("/run/archiso/copytoram")
    if not copies.exists() or not any(copies.rglob("airootfs.sfs")):
        raise MigrationError("Maintenance root was not copied to RAM")
    # archiso keeps the backing ISO and img_dev mounted in some versions even
    # after copying the SFS. Unmounting must succeed; a live dependency stops us.
    boot = "/run/archiso/bootmnt"
    if subprocess.run(["mountpoint", "-q", boot]).returncode == 0:
        run("umount", boot)
    loops = json.loads(run("losetup", "--json", "--output", "NAME,BACK-FILE")).get("loopdevices", [])
    for loop in loops:
        backing = loop.get("back-file", "")
        if backing.endswith(state["task"] + "/genesi.iso"):
            run("losetup", "--detach", loop["name"])
    image_mount = "/run/archiso/img_dev"
    if subprocess.run(["mountpoint", "-q", image_mount]).returncode == 0:
        mounted_source = run("findmnt", "-n", "-o", "SOURCE", image_mount)
        if os.path.realpath(mounted_source) != os.path.realpath(device):
            raise MigrationError("archiso source disk differs from migration disk")
        run("umount", image_mount)


def offline(task_path):
    if not LIVE_MARKER.exists():
        raise MigrationError("Offline migration may only run from the archiso maintenance environment")
    # The ISO and manifest must already be in RAM; conversion must see no
    # source mounts, loop-device holders or writable filesystem users.
    state = json.loads((Path(task_path) / "state.json").read_text())
    if state.get("schema") != "native-v1" or PurePosixPath(state.get("task", "")).parent != PurePosixPath("/var/lib/genesi-migrate-native"):
        raise MigrationError("Unsupported or invalid migration state")
    if not re.fullmatch(r"[/A-Za-z0-9_.@-]*", state.get("sourcePrefix", "")) or ".." in state.get("sourcePrefix", ""):
        raise MigrationError("Invalid source subvolume path")
    if not re.fullmatch(r"[a-z_][a-z0-9_-]{0,30}", state.get("user", {}).get("name", "")):
        raise MigrationError("Invalid preserved account")
    _, root, _ = identify(state, inventory())
    release_iso(state, root["path"])
    _, root, _ = identify(state, inventory())
    assert_offline(root)
    if state["phase"] not in ("armed", "converted"):
        raise MigrationError("Migration phase requires manual recovery: " + state["phase"])
    device = root["path"]
    readonly_options = "ro,nologreplay,subvolid=5" if root.get("fstype") == "btrfs" else "ro,noload"
    with mounted(device, TOP, "-o", readonly_options):
        if (TOP / "@/var/lib/genesi-migrate/boot-ready").exists():
            raise MigrationError("Genesi was already configured; choose its normal boot entry. Home will not be overwritten")
        source_task = TOP / state["sourcePrefix"].lstrip("/") / state["task"].lstrip("/")
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
    with mounted(device, TOP, "-o", "subvolid=5"):
        task = TOP / state["sourcePrefix"].lstrip("/") / state["task"].lstrip("/")
        prepared = task / "target-root"
        target_valid(prepared)
        if root_hash(prepared) != state["rootHash"]:
            raise MigrationError("Prepared root changed; refusing to switch")
        if state["phase"] == "armed":
            if (TOP / "@").exists() or (TOP / "@genesi-home").exists():
                raise MigrationError("Reserved Genesi subvolumes already exist")
            state["phase"] = "converted"
            save(task / "state.json", state)
        if not (TOP / "@").exists():
            run("btrfs", "subvolume", "create", TOP / "@")
        if not (TOP / "@genesi-home").exists():
            run("btrfs", "subvolume", "create", TOP / "@genesi-home")
        run("rsync", "-aHAX", "--numeric-ids", "--one-file-system", str(prepared) + "/", str(TOP / "@") + "/", reserve_at=TOP)
        source_home = TOP / state["sourcePrefix"].lstrip("/") / "home"
        run("cp", "-a", "--reflink=always", str(source_home) + "/.", TOP / "@genesi-home", reserve_at=TOP)
        new_home = TOP / "@genesi-home" / state["user"]["name"]
        new_home.mkdir(exist_ok=True)
        run("rsync", "-a", "--ignore-existing", "--chown=%s:%s" % (state["user"]["uid"], state["user"]["gid"]),
            str(prepared / "etc/skel") + "/", str(new_home) + "/")
        with mounted(device, TARGET, "-o", "subvol=@"):
            (TARGET / "home").mkdir(exist_ok=True)
            with mounted(device, TARGET / "home", "-o", "subvol=@genesi-home"):
                configure(state, task, device)
        state["phase"] = "configured"
        save(task / "state.json", state)
    os.sync()
    print("Migration configured. Reboot to enter Genesi.", flush=True)
    run("systemctl", "reboot")


def configure(state, task, device):
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
    save(marker, {"phase": "boot-ready", "schema": "native-v1"})


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
    parser.add_argument("mode", choices=("prepare", "offline", "health", "disarm"))
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
