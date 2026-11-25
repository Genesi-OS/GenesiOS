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
import shutil

APP = Path(__file__).resolve().parents[1] / "genesi-migrate/app"
sys.path.insert(0, str(APP))
import stage
import native
GIB = native.GIB


class Preflight(unittest.TestCase):
    def test_refresh_filesystem_updates_udev_before_chroot_probe(self):
        with patch.object(native, "run", side_effect=["btrfs", "", "", "ID_FS_TYPE=btrfs\nID_FS_UUID=test", "btrfs"]) as run:
            native.refresh_converted_filesystem("/dev/sda3")
        self.assertEqual(run.call_args_list[1].args,
                         ("udevadm", "trigger", "--action=change", "--sysname-match=sda3"))
        self.assertEqual(run.call_args_list[2].args,
                         ("udevadm", "settle", "--timeout=30"))
        self.assertEqual(run.call_args_list[-1].args,
                         ("arch-chroot", native.TARGET, "blkid", "-c", "/dev/null", "-s", "TYPE", "-o", "value", "/dev/sda3"))

    def test_refresh_filesystem_rejects_stale_udev_or_wrong_disk(self):
        for responses in (["ext4"], ["btrfs", "", "", "ID_FS_TYPE=ext4"],
                          ["btrfs", "", "", "ID_FS_TYPE=btrfs", "ext4"]):
            with patch.object(native, "run", side_effect=responses), self.assertRaises(native.MigrationError):
                native.refresh_converted_filesystem("/dev/sda3")

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

    def test_native_plan_does_not_require_iso_in_ram(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["machine"]["ramBytes"] = 1900 * 1024 ** 2
        native.validate_machine(manifest["machine"], self.devices)
        manifest["choices"] = {"install": {"mode": "native"}, "strategy": "stay"}
        plan = stage.plan(manifest, "/home/mint")
        self.assertFalse(plan["copytoram"])

    def test_fail_closed(self):
        for key, value in [("rootFs", "xfs"), ("rootPartType", "lvm"),
                           ("luks", True), ("firmware", "bios"),
                           ("rootUuid", "../../sda"), ("homeSeparate", True),
                           ("secureBoot", True)]:
            with self.subTest(key=key):
                changed = copy.deepcopy(self.manifest)
                changed["machine"][key] = value
                with self.assertRaises(native.MigrationError):
                    native.validate_machine(changed["machine"], self.devices)

    def test_existing_btrfs_at_root_and_same_volume_home_are_supported(self):
        machine = dict(self.manifest["machine"], rootFs="btrfs", rootOptions="rw,subvol=/@",
                       homeSeparate=True, homeFs="btrfs", homeUuid="abcd-1234")
        devices = copy.deepcopy(self.devices)
        devices[0]["children"][1]["fstype"] = "btrfs"
        self.assertEqual(native.validate_machine(machine, devices)["originalFs"], "btrfs")
        machine["homeUuid"] = "another-volume"
        with self.assertRaises(native.MigrationError):
            native.validate_machine(machine, devices)

    def test_recovery_loader_uses_task_marker_and_both_source_locations(self):
        state = {"rootUuid": "disk", "task": "/var/lib/genesi-migrate-native/test", "sourcePrefix": "/@",
                 "exchange": {"rootBackup": "@genesi-previous-test"}}
        text = native.recovery_config(state)
        self.assertIn("/@/var/lib/genesi-migrate/boot-ready-test", text)
        self.assertIn("/@genesi-previous-test/var/lib/genesi-migrate-native/test/migrate-vmlinuz", text)
        self.assertIn("genesi.migrate=UUID=disk:$genesi_task", text)
        if sys.platform == "linux" and shutil.which("grub-script-check"):
            subprocess.run(["grub-script-check"], input=text, text=True, capture_output=True, check=True)

    def test_filesystem_path_handles_home_subvolume_and_root_directory(self):
        for fsroot, target, expected in (("/@", "/", "/@/home"), ("/@home", "/home", "/@home")):
            with patch.object(native, "run", return_value=json.dumps({"filesystems": [{"fsroot": fsroot, "target": target}]})):
                self.assertEqual(native.filesystem_path("/home"), expected)

    def test_exchange_state_rejects_path_injection_and_reused_ids(self):
        state = {"task": "/var/lib/genesi-migrate-native/test", "sourcePrefix": "/@", "originalFs": "btrfs",
                 "exchange": {"rootId": 256, "rootBackup": "@genesi-previous-test",
                              "rootNext": "@genesi-next-root-test", "homeNext": "@genesi-next-home-test"}}
        native.validate_exchange(state)
        for key, value in (("rootBackup", "../../outside"), ("rootId", True), ("targetRootId", 256)):
            changed = copy.deepcopy(state)
            changed["exchange"][key] = value
            with self.assertRaises(native.MigrationError):
                native.validate_exchange(changed)

    def test_boot_locator_can_resume_from_renamed_original_root(self):
        with tempfile.TemporaryDirectory() as directory:
            top, ram = Path(directory) / "top", Path(directory) / "ram"
            state = {"rootUuid": "source", "task": "/var/lib/genesi-migrate-native/test",
                     "sourcePrefix": "/@", "originalFs": "btrfs",
                     "exchange": {"rootId": 256, "rootBackup": "@genesi-previous-test",
                                  "rootNext": "@genesi-next-root-test", "homeNext": "@genesi-next-home-test"}}
            location = "/@genesi-previous-test" + state["task"]
            native.save(top / location.lstrip("/") / "state.json", state)
            with patch.multiple(native, TOP=top, RAM_STATE=ram), patch.object(native, "assert_maintenance"), \
                 patch.object(native, "assert_offline"), \
                 patch.object(native, "inventory", return_value=[{"type": "part", "fstype": "btrfs", "uuid": "source", "path": "/dev/fake"}]), \
                 patch.object(native, "mounted", side_effect=lambda *a: contextlib.nullcontext(top)), \
                 patch.object(native, "offline") as offline:
                native.boot_offline("UUID=source:" + location)
            offline.assert_called_once_with(ram)
            self.assertEqual(json.loads((ram / "state.json").read_text())["sourcePrefix"], "/@")

    def test_rescue_has_both_filesystems_and_explicit_recovery(self):
        state = native.validate_machine(self.manifest["machine"], self.devices)
        state.update(task="/var/lib/genesi-migrate-native/test", sourcePrefix="")
        config = native.recovery_config(state)
        self.assertIn("insmod btrfs", config)
        self.assertIn("insmod ext2", config)
        self.assertIn("genesi.migrate=UUID=", config)
        self.assertIn("Continue Genesi migration / recovery", config)
        self.assertIn("/migrate-vmlinuz", config)
        self.assertIn("/migrate-initramfs.img", config)
        self.assertNotIn("copytoram", config)
        self.assertNotIn("genesi.iso", config)
        self.assertNotIn("loopback", config)
        self.assertIn("  configfile ($root)/@/boot/grub/grub.cfg\nfi", config)

    @unittest.skipUnless(sys.platform == "linux" and native.shutil.which("grub-script-check"), "requires GRUB syntax checker")
    def test_rescue_configuration_has_valid_grub_syntax(self):
        state = native.validate_machine(self.manifest["machine"], self.devices)
        state.update(task="/var/lib/genesi-migrate-native/test", sourcePrefix="")
        subprocess.run(["grub-script-check"], input=native.recovery_config(state), text=True, capture_output=True, check=True)


class Response(io.BytesIO):
    status = 200

    def __init__(self, data):
        super().__init__(data)
        self.headers = {"Content-Length": str(len(data))}


class MountLifecycle(unittest.TestCase):
    def test_packed_runtime_is_exercised_before_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            task, root = Path(directory) / "task", Path(directory) / "root"
            task.mkdir()
            calls = []

            def run(*args):
                calls.append(args)
                return '{"filesystems": []}' if args[0] == "findmnt" else ""

            with patch.object(native, "run", side_effect=run), \
                 patch.object(native, "mounted", side_effect=lambda *a, **k: contextlib.nullcontext()):
                native.verify_maintenance(root, task)
            self.assertTrue(any("python3" in call and "--help" in call for call in calls))
            self.assertTrue(any("arch-chroot" in call and "/usr/bin/true" in call for call in calls))
            self.assertFalse((task / "maintenance-check").exists())

    def test_retry_only_retires_armed_tasks_on_the_same_source(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            for name, phase, root in (("old", "armed", "source"), ("other", "armed", "other"),
                                      ("failed", "preparing", "source"), ("done", "configured", "source")):
                task = base / name
                task.mkdir()
                native.save(task / "state.json", {"schema": "native-v1", "phase": phase, "rootUuid": root})
            with patch.object(native, "BASE", base), patch.object(native, "inventory", return_value=[]), \
                 patch.object(native, "identify"), patch.object(native, "disarm") as disarm:
                native.retire_previous_boot_tasks({"rootUuid": "source"})
            disarm.assert_called_once_with(base / "old")

    @unittest.skipUnless(sys.platform == "linux", "requires Bash on Linux")
    def test_maintenance_hook_hands_off_without_reboot(self):
        install, runtime = native.maintenance_hooks()
        subprocess.run(["bash", "-n"], input=install, text=True, check=True)
        subprocess.run(["bash", "-n"], input=runtime, text=True, check=True)
        harness = runtime.replace("/usr/bin/python3", "fixture_python") + '''
getarg() { echo UUID=test:/var/lib/genesi-migrate-native/test; }
fixture_python() { echo "WORKER:$*"; }
mount() { echo "MOUNT:$*"; }
mkdir() { echo "LAYOUT:$*"; }
chmod() { echo "MODE:$*"; }
msg() { :; }
root=UUID=test
run_hook
"$mount_handler" /sysroot
'''
        output = subprocess.check_output(["bash", "-c", harness], text=True)
        self.assertIn("boot-offline UUID=test:", output)
        self.assertIn("LAYOUT:-p /dev/pts /dev/shm", output)
        self.assertIn("MODE:1777 /dev/shm", output)
        self.assertIn("MOUNT:-t btrfs", output)
        self.assertNotIn("reboot", output)
        failure = harness.replace('echo "WORKER:$*";', 'return 1;').replace(
            'root=UUID=test', 'genesi_native_stop() { echo STOPPED; }; root=UUID=test')
        result = subprocess.run(["bash", "-c", failure], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("STOPPED", result.stdout)
        self.assertNotIn("MOUNT:", result.stdout)

    def test_offline_environment_rejects_regular_disk_root(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "marker"
            marker.write_text(native.MAINTENANCE_VERSION)
            with patch.object(native, "MAINTENANCE_MARKER", marker), patch.object(native, "run", return_value="ext4"):
                with self.assertRaisesRegex(native.MigrationError, "independent of all disks"):
                    native.assert_maintenance()

    def test_maintenance_builder_bounds_image_and_cleans_build_hooks(self):
        for oversized in (False, True):
            with self.subTest(oversized=oversized), tempfile.TemporaryDirectory() as directory:
                base = Path(directory)
                root, task = base / "root", base / "task"
                (root / "boot").mkdir(parents=True)
                (root / "boot/vmlinuz-linux").write_bytes(b"test kernel")
                task.mkdir()
                native.save(task / "state.json", {"rootUuid": "test", "task": "/var/lib/genesi-migrate-native/test", "sourcePrefix": ""})

                def run(*args, **kwargs):
                    if "mkinitcpio" in args:
                        image = root / "boot/genesi-migrate-initramfs.img"
                        with image.open("wb") as stream:
                            stream.truncate(native.MAX_MAINTENANCE_IMAGE + 1 if oversized else 1024)
                    if "lsinitcpio" in args:
                        return "\n".join(("init", "hooks/genesi_native", "usr/bin/python3", "usr/bin/btrfs-convert",
                                          "usr/bin/e2fsck", "usr/bin/rsync", "usr/bin/arch-chroot", "usr/bin/realpath",
                                          "usr/lib/genesi-migrate/native.py", "etc/genesi-native-initramfs"))
                    return ""

                with patch.object(native, "run", side_effect=run), \
                     patch.object(native, "verify_maintenance"), \
                     patch.object(native, "mounted", side_effect=lambda *a, **k: contextlib.nullcontext()):
                    if oversized:
                        with self.assertRaisesRegex(native.MigrationError, "192 MiB"):
                            native.build_maintenance(root, task)
                    else:
                        native.build_maintenance(root, task)
                        self.assertEqual((task / "migrate-vmlinuz").read_bytes(), b"test kernel")
                self.assertFalse((root / "usr/lib/initcpio/hooks/genesi_native").exists())
                self.assertFalse((root / "etc/genesi-native-initramfs").exists())

    def test_machine_id_has_runtime_mounts_until_command_finishes(self):
        calls = []

        @contextlib.contextmanager
        def mounted(source, destination, *options, **kwargs):
            calls.append(("mount", source, destination, options, kwargs))
            yield destination
            calls.append(("unmount", destination))

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "etc").mkdir()

            def run(*args):
                self.assertEqual(args, ("chroot", root, "systemd-machine-id-setup"))
                self.assertEqual([entry[1] for entry in calls], ["/proc", "/dev"])
                calls.append(("setup",))
                (root / "etc/machine-id").write_text("a" * 32 + "\n")

            with patch.object(native, "mounted", side_effect=mounted), patch.object(native, "run", side_effect=run):
                native.setup_machine_id(root)
            self.assertEqual([entry[0] for entry in calls], ["mount", "mount", "setup", "unmount", "unmount"])
            self.assertEqual(calls[0][4], {"helper_root": root})
            self.assertEqual(calls[-2:], [("unmount", root / "dev"), ("unmount", root / "proc")])

    def test_machine_id_failure_is_not_ignored(self):
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(native, "mounted", side_effect=lambda *a, **k: contextlib.nullcontext()), \
             patch.object(native, "run") as run:
            with self.assertRaisesRegex(native.MigrationError, "no valid machine ID"):
                native.setup_machine_id(directory)
            run.side_effect = native.MigrationError("systemd setup failed")
            with self.assertRaisesRegex(native.MigrationError, "systemd setup failed"):
                native.setup_machine_id(directory)

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
    def test_btrfs_boot_uses_supported_no_replay_rescue_option(self):
        with tempfile.TemporaryDirectory() as directory:
            top = Path(directory)
            with patch.object(native, "TOP", top), patch.object(native, "assert_maintenance"), \
                 patch.object(native, "assert_offline"), \
                 patch.object(native, "inventory", return_value=[{"type": "part", "fstype": "btrfs", "uuid": "source", "path": "/dev/fake"}]), \
                 patch.object(native, "mounted", side_effect=lambda *a, **k: contextlib.nullcontext()) as mount:
                with self.assertRaises(FileNotFoundError):
                    native.boot_offline("UUID=source:/var/lib/genesi-migrate-native/missing")
            mount.assert_called_once_with("/dev/fake", top, "-o", "ro,rescue=nologreplay,subvolid=5")

    def test_boot_reads_state_readonly_and_releases_source_before_worker(self):
        with tempfile.TemporaryDirectory() as directory:
            top, ram = Path(directory) / "top", Path(directory) / "ram"
            task = top / "var/lib/genesi-migrate-native/test"
            task.mkdir(parents=True)
            native.save(task / "state.json", {"rootUuid": "source", "sourcePrefix": "", "task": "/var/lib/genesi-migrate-native/test"})
            active = []

            @contextlib.contextmanager
            def mounted(source, destination, *options):
                self.assertEqual(options, ("-o", "ro,noload"))
                active.append(source)
                yield destination
                active.clear()

            def offline(path):
                self.assertFalse(active)
                self.assertEqual(path, ram)
                self.assertEqual(json.loads((ram / "state.json").read_text())["rootUuid"], "source")

            with patch.multiple(native, TOP=top, RAM_STATE=ram), \
                 patch.object(native, "assert_maintenance"), patch.object(native, "assert_offline"), \
                 patch.object(native, "inventory", return_value=[{"type": "part", "fstype": "ext4", "uuid": "source", "path": "/dev/fake"}]), \
                 patch.object(native, "mounted", side_effect=mounted), patch.object(native, "offline", side_effect=offline):
                native.boot_offline("UUID=source:/var/lib/genesi-migrate-native/test")

    def test_bad_boot_locator_is_rejected_before_mounting(self):
        with patch.object(native, "assert_maintenance"), patch.object(native, "mounted") as mount:
            for locator in ("UUID=x:/../state", "UUID=x:/safe/../../state", "arbitrary", "UUID=x:relative"):
                with self.assertRaises(native.MigrationError):
                    native.boot_offline(locator)
            mount.assert_not_called()

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
            with patch.multiple(native, TOP=top, TARGET=target), \
                 patch.object(native, "assert_maintenance"), \
                 patch.object(native, "inventory", return_value=[]), \
                 patch.object(native, "identify", return_value=({}, source, {})), \
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
        self.assertFalse(any(c[0] == "systemctl" for c in calls))

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
