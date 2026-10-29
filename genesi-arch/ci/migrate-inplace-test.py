"""Pure preflight tests: no disk, mount, root command or reboot."""
import copy
import contextlib
import json
from pathlib import Path
import unittest
import sys
import io
import hashlib
import tempfile
from unittest.mock import patch
from unittest.mock import Mock
import subprocess

APP = Path(__file__).resolve().parents[1] / "genesi-migrate/app"
sys.path.insert(0, str(APP))
import stage
import native
GIB = native.GIB


class Preflight(unittest.TestCase):
    def setUp(self):
        self.manifest = {"machine": {
            "rootFs": "ext4", "rootPartType": "part", "rootUuid": "abcd-1234",
            "rootPartSize": 100 * GIB, "rootUsed": 20 * GIB,
            "firmware": "uefi", "espUuid": "EFI-1",
            "ramBytes": 16 * GIB,
        }}
        self.devices = [{"path": "/dev/sda", "type": "disk", "size": 100 * GIB,
                         "serial": "mint-vm-disk", "children": [
                             {"path": "/dev/sda1", "type": "part", "fstype": "vfat", "uuid": "EFI-1"},
                             {"path": "/dev/sda2", "type": "part", "fstype": "ext4", "uuid": "abcd-1234", "partuuid": "root-part"}]}]

    def test_identity_survives_device_rename(self):
        state = native.validate_machine(self.manifest["machine"], self.devices)
        changed = copy.deepcopy(self.devices)
        changed[0]["path"] = "/dev/sdb"
        changed[0]["children"][1]["path"] = "/dev/sdb2"
        self.assertEqual(native.identify(state, changed)[1]["path"], "/dev/sdb2")

    def test_fail_closed(self):
        for key, value in [("rootFs", "xfs"), ("rootPartType", "lvm"),
                           ("luks", True), ("firmware", "bios"),
                           ("rootUuid", "../../sda"), ("homeSeparate", True),
                           ("secureBoot", True), ("rootOptions", "rw,subvol=/@")]:
            with self.subTest(key=key):
                changed = copy.deepcopy(self.manifest)
                changed["machine"][key] = value
                with self.assertRaises(native.MigrationError):
                    native.validate_machine(changed["machine"], self.devices)

    def test_rescue_has_both_filesystems_and_explicit_recovery(self):
        state = native.validate_machine(self.manifest["machine"], self.devices)
        state.update(task="/var/lib/genesi-migrate-native/test", sourcePrefix="")
        config = native.recovery_config(state)
        self.assertIn("insmod btrfs", config)
        self.assertIn("insmod ext2", config)
        self.assertIn("genesi.native=", config)
        self.assertIn("Continue Genesi migration / recovery", config)
        self.assertNotIn("genesi.migrate=", config)


class Response(io.BytesIO):
    status = 200

    def __init__(self, data):
        super().__init__(data)
        self.headers = {"Content-Length": str(len(data))}


class Preparation(unittest.TestCase):
    def test_privileged_recheck_rejects_changed_iso_before_arming(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "manifest.json"
            manifest.write_text(json.dumps({"machine": {}, "apps": []}))
            with patch.object(native, "inventory", return_value=[]), \
                 patch.object(native, "validate_machine", return_value={"rootUuid": "root"}), \
                 patch.object(native, "run", return_value="root"), \
                 patch.object(native, "digest", return_value="changed"), \
                 patch.object(native, "arm") as arm:
                with self.assertRaises(native.MigrationError):
                    native.prepare(manifest, "unused.iso", "expected", "unused-profiles.json")
                arm.assert_not_called()

    def test_build_stops_before_exhausting_host_disk(self):
        process = Mock(pid=1234)
        process.communicate.side_effect = [subprocess.TimeoutExpired("build", 1), ("", "")]
        with patch.object(native.subprocess, "Popen", return_value=process), \
             patch.object(native.shutil, "disk_usage", return_value=Mock(free=1)), \
             patch.object(native.os, "killpg", create=True) as terminate:
            with self.assertRaises(native.MigrationError):
                native.run("fake-build", reserve_at="fake-stage")
            terminate.assert_called_once_with(1234, native.signal.SIGTERM)

    def test_bad_download_preserves_existing_artifact(self):
        with tempfile.TemporaryDirectory() as directory:
            dest = str(Path(directory) / "root.tar")
            Path(dest).write_bytes(b"previous")
            with self.assertRaises(stage.StageError):
                stage.verified_download(dest, hashlib.sha256(b"expected").hexdigest(),
                                        lambda *args: None, lambda: False,
                                        lambda *args, **kw: Response(b"bad download"))
            self.assertEqual(Path(dest).read_bytes(), b"previous")

    def test_forged_marker_cannot_bypass_verification(self):
        with tempfile.TemporaryDirectory() as directory:
            dest = str(Path(directory) / "root.tar")
            digest = hashlib.sha256(b"verified").hexdigest()
            Path(dest).write_bytes(b"tampered")
            Path(dest + ".ok").write_text(digest)
            stage.verified_download(dest, digest, lambda *args: None, lambda: False,
                                    lambda *args, **kw: Response(b"verified"))
            self.assertEqual(Path(dest).read_bytes(), b"verified")

    def test_backup_rejects_escape(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(stage.StageError):
                stage.copy_tree([("source", "../outside")], directory,
                                lambda *args: None, lambda: False)

    def test_backup_checks_contents_even_with_identical_metadata(self):
        import os
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source"
            dest = Path(directory) / "dest"
            dest.mkdir()
            source.write_bytes(b"safe")
            target = dest / "file"
            target.write_bytes(b"oops")
            os.utime(target, ns=(source.stat().st_atime_ns, source.stat().st_mtime_ns))
            self.assertEqual(stage.copy_tree([(str(source), "file")], str(dest),
                                             lambda *args: None, lambda: False), [])
            self.assertEqual(target.read_bytes(), b"safe")

    def test_state_is_durable_and_valid_json(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "state.json"
            native.save(path, {"phase": "ready"})
            native.save(path, {"phase": "armed"})
            self.assertEqual(json.loads(path.read_text()), {"phase": "armed"})
            self.assertEqual(list(Path(directory).glob(".native-*")), [])


class Offline(unittest.TestCase):
    def exercise(self, failure=None):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            top, target, ram = base / "top", base / "target", base / "ram"
            task = top / "var/lib/genesi-migrate-native/test"
            ram.mkdir()
            prepared = task / "target-root"
            prepared.mkdir(parents=True)
            (prepared / "sentinel").write_text("Genesi prepared")
            (top / "home/mint").mkdir(parents=True)
            (top / "home/mint/document.txt").write_text("Must survive")
            state = {"phase": "configured" if failure == "completed" else "armed", "sourcePrefix": "", "task": "/var/lib/genesi-migrate-native/test", "rootHash": "verified"}
            state["user"] = {"name": "mint", "uid": 1000, "gid": 1000}
            state["expandedBytes"] = 1024
            state["schema"] = "native-v1"
            (ram / "state.json").write_text(json.dumps(state))
            native.save(task / "state.json", state)
            calls = []

            def run(*args, **kwargs):
                calls.append(tuple(str(a) for a in args))
                if args[:3] == ("btrfs", "subvolume", "create"):
                    Path(args[3]).mkdir()
                if args[0] == "cp":
                    import shutil
                    shutil.copytree(top / "home", top / "@genesi-home", dirs_exist_ok=True)
                return ""

            @contextlib.contextmanager
            def mount(source, destination, *args):
                Path(destination).mkdir(parents=True, exist_ok=True)
                yield Path(destination)

            def configure(*args):
                if failure == "configure":
                    raise native.MigrationError("simulated boot configuration failure")

            source = {"path": "/dev/fake-source", "fstype": "ext4", "mountpoints": []}
            with patch.multiple(native, TOP=top, TARGET=target, LIVE_MARKER=ram), \
                 patch.object(native, "inventory", return_value=[]), \
                 patch.object(native, "identify", return_value=({}, source, {})), \
                 patch.object(native, "release_iso"), \
                 patch.object(native, "mounted", side_effect=mount), \
                 patch.object(native, "target_valid"), \
                 patch.object(native, "root_hash", return_value="corrupt" if failure == "hash" else "verified"), \
                 patch.object(native.shutil, "disk_usage", return_value=Mock(free=100 * GIB)), \
                 patch.object(native, "configure", side_effect=configure), \
                 patch.object(native, "run", side_effect=run), patch.object(native.os, "sync", create=True):
                if failure:
                    with self.assertRaises(native.MigrationError):
                        native.offline(ram)
                else:
                    native.offline(ram)
                    self.assertEqual((top / "@genesi-home/mint/document.txt").read_text(), "Must survive")
                    self.assertEqual((top / "home/mint/document.txt").read_text(), "Must survive")
                    self.assertEqual(json.loads((task / "state.json").read_text())["phase"], "configured")
            return calls

    def test_native_switch_has_no_format_or_partition_commands(self):
        calls = self.exercise()
        self.assertIn(("btrfs-convert", "--uuid", "copy", "/dev/fake-source"), calls)
        self.assertFalse(any(c[0].startswith(("mkfs", "wipefs", "sfdisk")) for c in calls))
        self.assertEqual(calls[-1], ("systemctl", "reboot"))

    def test_bad_artifact_stops_before_conversion(self):
        calls = self.exercise("hash")
        self.assertFalse(any(c[0] == "btrfs-convert" for c in calls))
        self.assertNotIn(("systemctl", "reboot"), calls)

    def test_failed_boot_configuration_never_reboots(self):
        self.assertNotIn(("systemctl", "reboot"), self.exercise("configure"))

    def test_mounted_source_is_rejected(self):
        with self.assertRaises(native.MigrationError):
            native.assert_offline({"path": "/dev/fake", "mountpoints": ["/"]})

    def test_completed_migration_is_never_replayed(self):
        calls = self.exercise("completed")
        self.assertFalse(any(c[0] in ("btrfs-convert", "cp", "rsync") for c in calls))


if __name__ == "__main__":
    unittest.main()
