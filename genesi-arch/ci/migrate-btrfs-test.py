"""Real Btrfs exchange on fresh sparse regular-file disks, never a host disk.

sudo unshare --mount --propagation private python3 genesi-arch/ci/migrate-btrfs-test.py
Requires btrfs-progs, util-linux and rsync. No guest/host OS is installed.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "genesi-migrate/app"))
import native


class BtrfsExchange(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="genesi-btrfs-test-", dir="/var/tmp")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        image = self.base / "source.raw"
        with image.open("xb") as stream:
            stream.truncate(native.GIB)
        subprocess.run(["mkfs.btrfs", "-f", str(image)], check=True, stdout=subprocess.DEVNULL)
        self.loop = subprocess.check_output(["losetup", "--find", "--show", str(image)], text=True).strip()
        if not re.fullmatch(r"/dev/loop[0-9]+", self.loop):
            raise AssertionError("Not a disposable loop device")
        self.addCleanup(subprocess.run, ["losetup", "--detach", self.loop], check=True)
        self.top = self.base / "top"
        self.top.mkdir()
        subprocess.run(["mount", "-t", "btrfs", "-o", "subvolid=5", self.loop, str(self.top)], check=True)
        self.addCleanup(subprocess.run, ["umount", str(self.top)], check=True)
        self.top_patch = patch.object(native, "TOP", self.top)
        self.top_patch.start()
        self.addCleanup(self.top_patch.stop)
        native.run("btrfs", "subvolume", "create", self.top / "@")
        self.root = self.top / "@"
        self.task_suffix = "var/lib/genesi-migrate-native/test"
        self.task = self.root / self.task_suffix
        self.task.mkdir(parents=True)
        (self.task / "migrate-vmlinuz").write_text("recovery kernel")
        (self.root / "original-system").write_text("old OS must survive")
        self.state = {"schema": "native-v1", "originalFs": "btrfs", "sourcePrefix": "/@", "phase": "armed",
                      "task": "/" + self.task_suffix, "homePrefix": "/@/home",
                      "exchange": {"rootId": native.subvolume_id(self.root), "rootBackup": "@genesi-previous-test",
                                   "rootNext": "@genesi-next-root-test", "homeNext": "@genesi-next-home-test"}}
        (self.root / "home/mint").mkdir(parents=True)
        (self.root / "home/mint/document").write_text("precious bytes")
        self.state["exchange"]["homeSourceId"] = native.subvolume_id(self.root / "home")
        native.save(self.task / "state.json", self.state)

    def saved_state(self):
        root = self.top / "@genesi-previous-test"
        if not root.exists():
            root = self.root
        return json.loads((root / self.task_suffix / "state.json").read_text())

    def assert_preserved(self, state):
        backup = self.top / "@genesi-previous-test"
        self.assertEqual(native.subvolume_id(backup), state["exchange"]["rootId"])
        self.assertEqual((backup / "original-system").read_text(), "old OS must survive")
        self.assertEqual((backup / self.task_suffix / "migrate-vmlinuz").read_text(), "recovery kernel")
        self.assertEqual((native.source_home(state) / "mint/document").read_text(), "precious bytes")
        self.assertEqual(native.subvolume_id(self.top / "@"), state["exchange"]["targetRootId"])
        self.assertEqual(native.subvolume_id(self.top / "@genesi-home"), state["exchange"]["targetHomeId"])

    def test_existing_root_is_preserved_and_retry_uses_owned_targets(self):
        task = native.exchange_subvolumes(self.state)
        self.assertEqual(task, self.top / "@genesi-previous-test" / self.task_suffix)
        self.assert_preserved(self.state)
        native.exchange_subvolumes(self.saved_state())
        self.assert_preserved(self.state)

    def test_home_subvolume_is_preserved_on_the_same_filesystem(self):
        native.run("btrfs", "subvolume", "create", self.top / "@home")
        (self.top / "@home/mint").mkdir()
        (self.top / "@home/mint/document").write_text("precious bytes")
        self.state["homePrefix"] = "/@home"
        self.state["exchange"]["homeSourceId"] = native.subvolume_id(self.top / "@home")
        native.save(self.task / "state.json", self.state)
        native.exchange_subvolumes(self.state)
        self.assert_preserved(self.state)

    def check_existing_genesi_home(self):
        native.run("btrfs", "subvolume", "create", self.top / "@genesi-home")
        home = self.top / "@genesi-home"
        (home / "mint").mkdir()
        (home / "mint/document").write_text("precious bytes")
        self.state["homePrefix"] = "/@genesi-home"
        self.state["exchange"].update(homeId=native.subvolume_id(home), homeBackup="@genesi-previous-home-test")
        self.state["exchange"]["homeSourceId"] = native.subvolume_id(home)
        native.save(self.task / "state.json", self.state)
        return self.state

    def test_existing_genesi_home_is_renamed_not_overwritten(self):
        self.check_existing_genesi_home()
        native.exchange_subvolumes(self.state)
        self.assert_preserved(self.state)

    def test_interruptions_after_every_rename_can_resume(self):
        self.check_existing_genesi_home()
        # Interrupt after root backup, home backup, root publication, and home
        # publication in sequence. Each restart reloads only persisted state.
        rename = os.rename
        for index in range(4):
            def interrupt(source, destination):
                rename(source, destination)
                raise InterruptedError("simulated interruption after durable rename")
            with patch.object(native.os, "rename", side_effect=interrupt), self.assertRaises(InterruptedError):
                native.exchange_subvolumes(self.saved_state())
        native.exchange_subvolumes(self.saved_state())
        self.assert_preserved(self.saved_state())

    def test_unrelated_home_subvolume_is_never_replaced(self):
        native.run("btrfs", "subvolume", "create", self.top / "@genesi-home")
        with self.assertRaises(native.MigrationError):
            native.exchange_subvolumes(self.state)
        self.assertTrue((self.root / "original-system").exists())
        self.assertFalse((self.top / "@genesi-previous-test").exists())

    def test_wrong_source_identity_stops_before_any_exchange(self):
        self.state["exchange"]["rootId"] += 99
        with self.assertRaises(native.MigrationError):
            native.exchange_subvolumes(self.state)
        self.assertTrue((self.root / "original-system").exists())

    def test_wrong_home_identity_stops_before_any_exchange(self):
        self.state["exchange"]["homeSourceId"] += 99
        with self.assertRaises(native.MigrationError):
            native.exchange_subvolumes(self.state)
        self.assertFalse((self.top / "@genesi-previous-test").exists())

    def test_live_preflight_can_read_top_level_without_changing_source(self):
        with native.mounted(self.loop, self.base / "layout-check", "-t", "btrfs",
                            "-o", "ro,rescue=nologreplay,subvolid=5") as layout:
            self.assertEqual(native.subvolume_id(layout / "@"), self.state["exchange"]["rootId"])
        self.assertEqual((self.root / "original-system").read_text(), "old OS must survive")

    def test_unrecorded_creation_fails_closed_without_touching_source(self):
        def interrupt(path, state):
            raise InterruptedError("simulated interruption before ID persistence")
        with patch.object(native, "save", side_effect=interrupt), self.assertRaises(InterruptedError):
            native.exchange_subvolumes(self.state)
        with self.assertRaises(native.MigrationError):
            native.exchange_subvolumes(self.saved_state())
        self.assertTrue((self.root / "original-system").exists())

    def exercise_offline(self, separate_home=False):
        if separate_home:
            self.check_existing_genesi_home()
        # A previous Genesi boot-ready marker must not skip this new task.
        old_marker = self.root / "var/lib/genesi-migrate/boot-ready"
        old_marker.parent.mkdir(parents=True)
        old_marker.write_text('{"phase": "boot-ready", "schema": "native-v1"}')
        prepared = self.task / "target-root"
        for name in ("etc/os-release", "usr/bin/pacman", "usr/bin/mkinitcpio", "usr/bin/grub-mkconfig",
                     "boot/vmlinuz-test", "boot/initramfs-test.img", "etc/skel/.config/kdeglobals"):
            path = prepared / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("ID=genesi\n" if name == "etc/os-release" else "new Genesi content")
        (prepared / "var/lib/pacman/local").mkdir(parents=True)
        self.state.update(rootHash=native.root_hash(prepared), expandedBytes=1024,
                          user={"name": "mint", "uid": 0, "gid": 0})
        native.save(self.task / "state.json", self.state)
        ram = self.base / "ram"
        native.save(ram / "state.json", self.state)
        target = self.base / "target"

        def configure(state, task, device):
            self.assertEqual((target / "etc/os-release").read_text(), "ID=genesi\n")
            self.assertEqual((target / "home/mint/document").read_text(), "precious bytes")
            native.save(target / native.ready_marker(state), {"task": state["task"]})

        subprocess.run(["umount", str(self.top)], check=True)
        try:
            with patch.object(native, "TARGET", target), \
                 patch.object(native, "assert_maintenance"), \
                 patch.object(native, "inventory", return_value=[]), \
                 patch.object(native, "identify", return_value=({}, {"path": self.loop, "fstype": "btrfs"}, {})), \
                 patch.object(native.shutil, "disk_usage", return_value=Mock(free=100 * native.GIB)), \
                 patch.object(native, "configure", side_effect=configure):
                native.offline(ram)
        finally:
            subprocess.run(["mount", "-t", "btrfs", "-o", "subvolid=5", self.loop, str(self.top)], check=True)
        self.assert_preserved(self.saved_state())
        self.assertEqual((self.top / "@genesi-home/mint/document").read_text(), "precious bytes")
        self.assertEqual(self.saved_state()["phase"], "configured")

    def test_offline_copy_preserves_documents_and_replaces_root(self):
        self.exercise_offline()

    def test_offline_copy_supports_existing_genesi_home(self):
        self.exercise_offline(separate_home=True)


if __name__ == "__main__":
    if (sys.platform != "linux" or os.geteuid() != 0
            or os.readlink("/proc/self/ns/mnt") == os.readlink("/proc/1/ns/mnt")):
        raise SystemExit("Run as root in a private mount namespace; only fresh file disks will be used")
    unittest.main()
