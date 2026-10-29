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
        # Include one dynamically-linked helper so teardown is exercised with
        # a real background process holding its chroot root inside the image.
        executable = shutil.which("sleep")
        dependencies = subprocess.check_output(["ldd", executable], text=True)
        for source, relative in [(executable, "bin/sleep")] + [(p, p.lstrip("/")) for p in re.findall(r"(/[^\s()]+)", dependencies)]:
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


if __name__ == "__main__":
    main()
