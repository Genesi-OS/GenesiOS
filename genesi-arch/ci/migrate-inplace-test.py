"""Pure preflight tests: no disk, mount, root command or reboot."""
import copy
import contextlib
import json
import os
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

    def test_inventory_requests_tree_and_uses_parent_disk_serial(self):
        def lsblk(*args):
            # Reproduce util-linux: PATH alone produces flat JSON; NAME or
            # --tree is required to preserve disk -> partition relationships.
            columns = args[args.index("-o") + 1].split(",")
            tree = "--tree" in args or "NAME" in columns
            devices = self.devices if tree else [
                {k: v for k, v in self.devices[0].items() if k != "children"},
                *self.devices[0]["children"],
            ]
            return json.dumps({"blockdevices": devices})
        with patch.object(native, "run", side_effect=lsblk):
            result = native.validate_machine(self.manifest["machine"], native.inventory())
        self.assertEqual(result["serial"], "mint-vm-disk")
        self.assertEqual(result["partuuid"], "root-part")

    def test_flat_partition_cannot_be_mistaken_for_a_disk(self):
        with self.assertRaises(native.MigrationError):
            native.validate_machine(self.manifest["machine"], self.devices[0]["children"])

    def test_truly_missing_identity_still_blocks_migration(self):
        devices = copy.deepcopy(self.devices)
        devices[0]["serial"] = None
        with self.assertRaisesRegex(native.MigrationError, "no serial or WWN"):
            native.validate_machine(self.manifest["machine"], devices)
        devices = copy.deepcopy(self.devices)
        devices[0]["children"][1]["partuuid"] = None
        with self.assertRaisesRegex(native.MigrationError, "no PARTUUID"):
            native.validate_machine(self.manifest["machine"], devices)

    def test_real_iso_launcher_supports_native_protocol(self):
        launcher = APP.parents[1] / "archiso/airootfs/usr/local/bin/genesi-migrate-live"
        self.assertTrue(native.native_iso_supported(launcher))

    def test_legacy_iso_or_comment_only_does_not_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            launcher = Path(directory) / "launcher"
            self.assertFalse(native.native_iso_supported(launcher))
            for text in ("#!/bin/bash\n# genesi.native is planned\n", "#!/bin/bash\narg() { echo genesi.migrate; }\n"):
                launcher.write_text(text)
                self.assertFalse(native.native_iso_supported(launcher))

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


class MountLifecycle(unittest.TestCase):
    def test_nested_bind_stops_owned_runner_helpers_before_unmount(self):
        calls = []
        with tempfile.TemporaryDirectory() as directory:
            runner = Path(directory) / "runner"
            bind = runner / "genesi-native"
            with patch.object(native, "run"), \
                 patch.object(native, "stop_mount_helpers", side_effect=lambda root: calls.append(("stop", root))), \
                 patch.object(native, "unmount", side_effect=lambda path: calls.append(("unmount", path))):
                with native.mounted("fake", bind, "--bind", helper_root=runner):
                    pass
            self.assertEqual(calls, [("stop", os.path.realpath(runner)), ("unmount", bind)])

    def test_helper_scope_cannot_escape_owned_mount_tree(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(native, "run") as run:
            for scope in (Path(directory).anchor, Path(directory) / "unrelated"):
                with self.assertRaisesRegex(native.MigrationError, "owned mount tree"):
                    with native.mounted("fake", Path(directory) / "runner", helper_root=scope):
                        self.fail("unsafe cleanup scope was accepted")
            run.assert_not_called()

    def test_helper_selection_excludes_host_and_other_namespaces(self):
        with tempfile.TemporaryDirectory() as directory:
            proc, destination = Path(directory) / "proc", Path(directory) / "chroot"
            proc.mkdir()
            destination.mkdir()
            links = {"/proc/self/ns/mnt": "mnt:[migration]"}
            for pid, root, namespace in (
                (1001, str(destination / "child"), "mnt:[migration]"),
                (1002, str(destination), "mnt:[host]"),
                (1003, str(destination) + "-other", "mnt:[migration]"),
                (1004, str(Path(directory)), "mnt:[migration]"),
            ):
                folder = proc / str(pid)
                folder.mkdir()
                links[str(folder / "root")] = root
                links[str(folder / "ns/mnt")] = namespace
            real_path = Path
            real_readlink = native.os.readlink
            with patch.object(native.sys, "platform", "linux"), \
                 patch.object(native, "Path", side_effect=lambda p: proc if p == "/proc" else real_path(p)), \
                 patch.object(native.os, "readlink", side_effect=lambda p: links[str(p)] if str(p) in links else real_readlink(p)):
                self.assertEqual(native.mount_helper_pids(destination), [1001])

    def test_pid_handle_is_rechecked_before_signalling(self):
        with patch.object(native, "mount_helper_pids", side_effect=[[1234], []]), \
             patch.object(native, "open_pid_handle", return_value=77), \
             patch.object(native, "signal_pid_handle") as send, \
             patch.object(native.os, "close") as close:
            native.stop_mount_helpers("owned-chroot")
            send.assert_not_called()
            close.assert_called_once_with(77)

    def test_older_python_uses_stable_pidfd_syscalls(self):
        with patch.object(native.os, "pidfd_open", None, create=True), \
             patch.object(native.signal, "pidfd_send_signal", None, create=True), \
             patch.object(native, "pidfd_syscall", return_value=77) as syscall:
            self.assertEqual(native.open_pid_handle(1234), 77)
            native.signal_pid_handle(77, native.signal.SIGTERM)
            self.assertEqual(syscall.call_args_list[0].args, (434, 1234, 0))
            self.assertEqual(syscall.call_args_list[1].args, (424, 77, native.signal.SIGTERM, 0, 0))

    @unittest.skipUnless(sys.platform == "linux", "requires Bash on Linux")
    def test_staging_initramfs_disables_only_autodetect(self):
        with tempfile.TemporaryDirectory() as directory:
            native.staging_initramfs(directory)
            config = Path(directory) / "etc/mkinitcpio.conf.d/99-genesi-native-staging.conf"
            output = subprocess.check_output(["bash", "-c", 'HOOKS=(base systemd autodetect block filesystems); MODULES=(); source "$1"; printf "%s\\n" "${HOOKS[*]}" "${MODULES[*]}"', "test", str(config)], text=True)
            self.assertEqual(output.splitlines(), ["base systemd block filesystems", "btrfs ext4"])

    def test_embedded_loop_is_released_before_outer_iso(self):
        calls = []
        devices = iter(("/dev/loop90", "/dev/loop91"))

        def run(*args, **kwargs):
            calls.append(tuple(str(a) for a in args))
            if args[:3] == ("losetup", "--find", "--show"):
                return next(devices)
            return ""

        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            iso, squash = base / "iso.img", base / "root.sfs"
            iso.touch()
            squash.touch()
            with patch.object(native, "run", side_effect=run), patch.object(native.shutil, "which", return_value=None):
                with native.mounted_image(iso, base / "iso"):
                    with native.mounted_image(squash, base / "lower"):
                        pass
            self.assertLess(calls.index(("umount", "-R", str(base / "lower"))),
                            calls.index(("losetup", "--detach", "/dev/loop91")))
            self.assertLess(calls.index(("losetup", "--detach", "/dev/loop91")),
                            calls.index(("umount", "-R", str(base / "iso"))))
            self.assertEqual(calls[-1], ("losetup", "--detach", "/dev/loop90"))

    def test_cleanup_failure_preserves_original_error(self):
        def run(*args, **kwargs):
            if args[0] == "umount":
                raise native.MigrationError("cleanup busy")
            return ""
        with tempfile.TemporaryDirectory() as directory, patch.object(native, "run", side_effect=run), \
             patch.object(native.time, "sleep"), patch.object(native, "cleanup_warning") as warning:
            with self.assertRaisesRegex(native.MigrationError, "original package failure"):
                with native.mounted("fake", directory):
                    raise native.MigrationError("original package failure")
            warning.assert_called_once()

    def test_busy_unmount_is_retried_without_force(self):
        with patch.object(native, "run", side_effect=[native.MigrationError("busy"), ""]) as run, \
             patch.object(native.time, "sleep"):
            native.unmount("test-mount")
        self.assertEqual(run.call_count, 2)
        self.assertTrue(all(call.args == ("umount", "-R", "test-mount") for call in run.call_args_list))

    def test_loop_detaches_when_mount_fails(self):
        def run(*args, **kwargs):
            if args[0] == "mount":
                raise native.MigrationError("mount failed")
            return "/dev/loop90" if args[:3] == ("losetup", "--find", "--show") else ""
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.img"
            source.touch()
            with patch.object(native, "run", side_effect=run) as command, patch.object(native.shutil, "which", return_value=None):
                with self.assertRaisesRegex(native.MigrationError, "mount failed"):
                    with native.mounted_image(source, Path(directory) / "mount"):
                        self.fail("failed mount was entered")
            self.assertIn((("losetup", "--detach", "/dev/loop90"),), [tuple([call.args]) for call in command.call_args_list])


class Preparation(unittest.TestCase):
    def test_decimal_gb_does_not_satisfy_same_number_of_gib(self):
        with patch.object(native.shutil, "disk_usage", return_value=Mock(free=34 * 10 ** 9)):
            with self.assertRaisesRegex(native.MigrationError, r"32.00 GiB \(34.36 GB\).*31.66 GiB \(34.00 GB\)"):
                native.require_free_space("fake-root", native.MIN_PREP_FREE, "Preparation")

    def test_exact_binary_threshold_is_accepted(self):
        with patch.object(native.shutil, "disk_usage", return_value=Mock(free=32 * GIB)):
            native.require_free_space("fake-root", native.MIN_PREP_FREE, "Preparation")

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
