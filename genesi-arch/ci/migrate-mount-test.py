"""Opt-in root integration test using only disposable regular-file images.

Run in a PRIVATE mount namespace, never against a disk:
sudo unshare --mount --propagation private python3 genesi-arch/ci/migrate-mount-test.py
With xorriso+squashfs-tools this exercises the exact ISO -> SFS nesting; the
fallback uses two ext4 image files to test the same loop-holder lifetime.
"""
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "genesi-migrate/app"))
import native


def command(*args):
    subprocess.run([str(arg) for arg in args], check=True, stdout=subprocess.DEVNULL)


def ext4_image(path, tree, megabytes):
    # mkfs receives only a fresh regular file inside our own temporary directory.
    with path.open("xb") as stream:
        stream.truncate(megabytes * 1024 ** 2)
    command("mkfs.ext4", "-F", "-q", "-d", tree, path)


def check_detached(*images):
    for image in images:
        loops = subprocess.check_output(["losetup", "-j", str(image)], text=True)
        if loops.strip():
            raise AssertionError("Image still attached: " + loops)


def check_runner_bind_lifecycle(base, outer, inner):
    task = base / "task"
    target = task / "target-root"
    target.mkdir(parents=True)
    (target / "sentinel").write_text("preserve staged system\n")
    runner, upper, work = (task / name for name in ("runner", "upper", "work"))
    upper.mkdir()
    work.mkdir()
    helper = None
    try:
        with native.mounted_image(outer, task / "iso") as iso:
            with native.mounted_image(iso / inner.name, task / "lower") as lower:
                with native.mounted("overlay", runner, "-t", "overlay", "-o",
                                    "lowerdir=%s,upperdir=%s,workdir=%s" % (lower, upper, work)):
                    with native.mounted(task, runner / "genesi-native", "--bind", helper_root=runner):
                        bound_target = runner / "genesi-native/target-root"
                        command("mount", "--bind", bound_target, bound_target)
                        # pacstrap -K starts pacman-key outside the target
                        # chroot. Its agent can hold the target through its cwd.
                        helper = subprocess.Popen([
                            "chroot", str(runner), "/bin/sh", "-c",
                            "cd /genesi-native/target-root && exec /bin/sleep 60",
                        ])
                        for _ in range(100):
                            if helper.poll() is not None:
                                raise AssertionError("Runner helper did not start")
                            if (os.readlink("/proc/%d/root" % helper.pid) == str(runner)
                                    and os.readlink("/proc/%d/cwd" % helper.pid) == str(bound_target)):
                                break
                            time.sleep(0.01)
                        else:
                            raise AssertionError("Helper did not enter the runner and target bind")
                        if helper.pid in native.mount_helper_pids(bound_target):
                            raise AssertionError("Fixture must reproduce the old cleanup scope mismatch")
                        if helper.pid not in native.mount_helper_pids(runner):
                            raise AssertionError("Owned runner helper was not found")
                    if helper.poll() is None:
                        raise AssertionError("Inner bind cleanup did not stop the runner helper")
    finally:
        if helper is not None:
            if helper.poll() is None:
                helper.kill()
            helper.wait()
    if (target / "sentinel").read_text() != "preserve staged system\n":
        raise AssertionError("Bind cleanup modified staged files")
    check_detached(outer, task / "iso" / inner.name)
    print("runner helper holding nested target-root bind lifecycle passed")


def check_machine_id_setup(base, payload):
    root = base / "identity-root"
    shutil.copytree(payload, root)
    (root / "etc").mkdir()
    (root / "etc/machine-id").touch()
    # Enforce the proc-fd requirement even on older CI systemd versions,
    # then exercise the real systemd utility with its dynamic dependencies.
    wrapper = root / "bin/systemd-machine-id-setup"
    wrapper.write_text(
        '#!/bin/sh\nset -eu\nexec 3</etc/machine-id\n'
        'test -r /proc/self/fd/3\ntest -c /dev/urandom\n'
        'exec /usr/libexec/real-machine-id-setup\n'
    )
    wrapper.chmod(0o755)
    host_identity = Path("/etc/machine-id").read_bytes()
    native.setup_machine_id(root)
    first_identity = (root / "etc/machine-id").read_text()
    native.setup_machine_id(root)
    if (root / "etc/machine-id").read_text() != first_identity:
        raise AssertionError("Machine ID changed on retry")
    if Path("/etc/machine-id").read_bytes() != host_identity:
        raise AssertionError("Host machine ID was modified")
    if any(os.path.ismount(root / name) for name in ("proc", "dev")):
        raise AssertionError("Machine ID runtime mounts leaked")
    print("machine ID initialized and retained with temporary proc/dev mounts")


def main():
    if sys.platform != "linux" or os.geteuid() != 0:
        raise SystemExit("This test requires Linux root in a private mount namespace")
    if os.getpid() != 1 and os.readlink("/proc/self/ns/mnt") == os.readlink("/proc/1/ns/mnt"):
        raise SystemExit("Use unshare --mount --propagation private before this test")
    with tempfile.TemporaryDirectory(prefix="genesi-mount-test-") as directory:
        base = Path(directory)
        payload, tree = base / "payload", base / "tree"
        payload.mkdir()
        tree.mkdir()
        (payload / "sentinel").write_text("nested image test\n")
        # Include dynamically-linked helpers for real chroot lifetime checks.
        for binary, target in (("sleep", "bin/sleep"), ("sh", "bin/sh"),
                               ("systemd-machine-id-setup", "usr/libexec/real-machine-id-setup")):
            executable = shutil.which(binary)
            if not executable:
                raise AssertionError("Integration fixture requires " + binary)
            dependencies = subprocess.check_output(["ldd", executable], text=True)
            for source, relative in [(executable, target)] + [(p, p.lstrip("/")) for p in re.findall(r"(/[^\s()]+)", dependencies)]:
                destination = payload / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, destination)
                destination.chmod(0o755)
        exact = shutil.which("mksquashfs") and shutil.which("xorriso")
        if exact:
            inner = tree / "root.sfs"
            outer = base / "outer.iso"
            command("mksquashfs", payload, inner, "-noappend", "-quiet", "-processors", "1")
            command("xorriso", "-as", "mkisofs", "-quiet", "-o", outer, tree)
        else:
            inner = tree / "root.img"
            outer = base / "outer.img"
            ext4_image(inner, payload, 16)
            ext4_image(outer, tree, 48)
        for fail in (False, True):
            helper = None
            try:
                with native.mounted_image(outer, base / "outer") as parent:
                    with native.mounted_image(parent / inner.name, base / "inner") as child:
                        if (child / "sentinel").read_text() != "nested image test\n":
                            raise AssertionError("Nested image content mismatch")
                        if fail:
                            raise native.MigrationError("injected preparation failure")
                        helper = subprocess.Popen(["chroot", str(child), "/bin/sleep", "60"])
                        for _ in range(100):
                            if helper.poll() is not None:
                                raise AssertionError("Fixture helper did not start")
                            if os.readlink("/proc/%d/root" % helper.pid) == str(child):
                                break
                            time.sleep(0.01)
                        else:
                            raise AssertionError("Helper did not enter the image chroot")
            except native.MigrationError as error:
                if not fail or str(error) != "injected preparation failure":
                    raise
            finally:
                if helper is not None:
                    if helper.poll() is None:
                        helper.kill()
                        helper.wait()
                        raise AssertionError("Mount teardown did not stop its chroot helper")
                    helper.wait()
            check_detached(outer)
            # The inner backing file is addressed through the parent mount.
            check_detached(base / "outer" / inner.name)
        print("nested image lifecycle passed (" + ("ISO/SquashFS" if exact else "ext4 image fallback") + ")")
        check_runner_bind_lifecycle(base, outer, inner)
        check_machine_id_setup(base, payload)


if __name__ == "__main__":
    main()
