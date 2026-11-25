"""Desktop migration integration on temporary directories, never the host home."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "genesi-migrate/app"))
import native


@unittest.skipUnless(shutil.which("rsync"), "Integration requires rsync")
class DesktopMigration(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root, self.source = self.base / "root", self.base / "source"
        self.commands = []

    def write(self, root, relative, text="fixture"):
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def execute(self, *args, **kwargs):
        self.commands.append(tuple(str(a) for a in args))
        if args[0] == "rsync":
            return subprocess.check_output([str(a) for a in args], text=True).strip()
        return ""

    def fixture(self, desktop):
        self.write(self.source, "usr/share/wallpapers/genesi/wallpaper.png")
        self.write(self.source, "usr/share/genesi/skel-override/.config/kdeglobals", "Plasma Genesi")
        self.write(self.source, "usr/share/genesi/skel-override/.config/fish/config.fish", "Genesi fish")
        self.write(self.source, "usr/share/genesi/skel-override/.config/plasma-org.kde.plasma.desktop-appletsrc", "Genesi panel")
        self.write(self.source, "usr/share/genesi/skel-override/Desktop/calamares.desktop", "live installer")
        self.write(self.source, "etc/skel/.config/kdeglobals", "live Plasma")
        self.write(self.source, "etc/sddm.conf.d/01-autologin.conf", "liveuser")
        self.write(self.source, "etc/xdg/autostart/genesi-migrate-live.desktop")
        manager, sessions = native.DESKTOP_SESSIONS[desktop]
        self.write(self.root, "usr/lib/systemd/system/" + manager + ".service")
        self.write(self.root, "usr/share/" + sessions[-1])
        self.write(self.root, "etc/skel/.config/desktop-specific", desktop)
        if desktop == "KDE-Desktop":
            for relative in ("usr/share/genesi/skel-override/.config/kwinrc",
                             "usr/share/genesi/skel-override/.config/klassyrc",
                             "usr/share/genesi/skel-override/.config/darklyrc",
                             "usr/share/genesi/skel-override/.config/autostart/genesi-apply-theme.desktop",
                             "usr/bin/genesi-apply-theme.sh", "usr/share/color-schemes/Genesi.colors",
                             "usr/share/plasma/desktoptheme/Ant-Dark/metadata.json",
                             "usr/share/icons/Tela-circle-green-dark/index.theme"):
                self.write(self.root, relative)
        if desktop == "Hyprland-Desktop":
            for relative in ("etc/skel/.config/hypr/hyprland.conf", "etc/skel/.config/caelestia/shell.json",
                             "usr/bin/Hyprland", "usr/bin/caelestia"):
                self.write(self.root, relative)
            self.write(self.root, "etc/skel/.config/kdeglobals", "Caelestia Qt palette")
        if desktop not in ("KDE-Desktop", "Hyprland-Desktop"):
            self.write(self.root, "usr/bin/genesi-de-apply")
            self.write(self.root, "etc/xdg/autostart/genesi-de-branding.desktop")

    def test_every_installer_profile_has_session_integration(self):
        profiles = json.loads((Path(native.__file__).parent / "native-profiles.json").read_text())
        self.assertEqual(set(profiles), set(native.DESKTOP_SESSIONS))

    def test_all_desktops_keep_their_own_defaults_and_have_a_valid_session(self):
        for desktop in native.DESKTOP_SESSIONS:
            with self.subTest(desktop=desktop):
                self.root = self.base / desktop
                self.fixture(desktop)
                with patch.object(native, "run", side_effect=self.execute):
                    native.prepare_desktop(self.root, self.source, desktop, "mint")
                config = self.root / "etc/skel/.config"
                self.assertEqual((config / "desktop-specific").read_text(), desktop)
                self.assertEqual((config / "fish/config.fish").read_text(), "Genesi fish")
                if desktop == "KDE-Desktop":
                    self.assertEqual((config / "kdeglobals").read_text(), "Plasma Genesi")
                    self.assertTrue((config / "plasma-org.kde.plasma.desktop-appletsrc").exists())
                else:
                    self.assertFalse((config / "plasma-org.kde.plasma.desktop-appletsrc").exists())
                if desktop == "Hyprland-Desktop":
                    self.assertEqual((config / "kdeglobals").read_text(), "Caelestia Qt palette")
                if desktop not in ("KDE-Desktop", "Hyprland-Desktop"):
                    self.assertTrue((config / "autostart/genesi-de-branding.desktop").is_file())
                report = json.loads((self.root / "var/lib/genesi-migrate/desktop.json").read_text())
                self.assertTrue((self.root / "usr/share" / report["session"]).exists())
                self.assertIn("Session=", (self.root / "var/lib/AccountsService/users/mint").read_text())
                self.assertIn(("systemctl", "--root", str(self.root), "enable", "--force", report["manager"] + ".service"), self.commands)
                self.assertFalse((self.root / "etc/skel/Desktop/calamares.desktop").exists())
                self.assertFalse((self.root / "etc/sddm.conf.d/01-autologin.conf").exists())
                self.assertFalse((self.root / "etc/xdg/autostart/genesi-migrate-live.desktop").exists())

    def test_newer_packaged_assets_are_not_overwritten_by_iso(self):
        self.fixture("KDE-Desktop")
        target = self.write(self.root, "usr/share/genesi/skel-override/.config/kdeglobals", "new package")
        with patch.object(native, "run", side_effect=self.execute):
            native.prepare_desktop(self.root, self.source, "KDE-Desktop", "mint")
        self.assertEqual(target.read_text(), "new package")
        self.assertEqual((self.root / "etc/skel/.config/kdeglobals").read_text(), "new package")

    def test_missing_session_or_branding_blocks_preparation(self):
        for missing in ("usr/share/wayland-sessions/plasma.desktop", "usr/share/wallpapers/genesi/wallpaper.png"):
            self.root = self.base / missing.replace("/", "_")
            self.fixture("KDE-Desktop")
            (self.root / missing).unlink(missing_ok=True)
            if "wallpaper" in missing:
                (self.source / missing).unlink()
            with patch.object(native, "run", side_effect=self.execute), self.assertRaises(native.MigrationError):
                native.prepare_desktop(self.root, self.source, "KDE-Desktop", "mint")

    def test_missing_caelestia_configuration_is_not_silently_accepted(self):
        self.fixture("Hyprland-Desktop")
        (self.root / "etc/skel/.config/caelestia/shell.json").unlink()
        with patch.object(native, "run", side_effect=self.execute), self.assertRaises(native.MigrationError):
            native.prepare_desktop(self.root, self.source, "Hyprland-Desktop", "mint")

    def test_live_autostarts_in_source_are_never_seeded(self):
        self.fixture("KDE-Desktop")
        for name in ("genesi-migrate-live.desktop", "genesi-branding.desktop"):
            self.write(self.root, "etc/xdg/autostart/" + name)
        with patch.object(native, "run", side_effect=self.execute):
            native.prepare_desktop(self.root, self.source, "KDE-Desktop", "mint")
        for name in ("genesi-migrate-live.desktop", "genesi-branding.desktop"):
            self.assertFalse((self.root / "etc/skel/.config/autostart" / name).exists())

    def test_home_replaces_only_template_paths_and_backs_up_old_config(self):
        home, task = self.base / "home", self.base / "task"
        self.write(self.root, "etc/skel/.config/kdeglobals", "Genesi palette")
        self.write(self.root, "etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc", "Genesi panel")
        self.write(self.root, "etc/skel/Desktop/calamares.desktop", "must not install")
        self.write(home, ".config/kdeglobals", "Mint palette")
        self.write(home, ".config/unrelated-app/settings", "personal settings")
        self.write(home, "Documents/project.txt", "personal document")
        self.write(home, ".config/.genesi-theme-applied", "old marker")
        state = {"user": {"uid": os.getuid(), "gid": os.getgid()}}
        with patch.object(native, "run", side_effect=self.execute):
            native.apply_desktop_home(self.root, home, state, task)
        self.assertEqual((home / ".config/kdeglobals").read_text(), "Genesi palette")
        self.assertEqual((home / "Documents/project.txt").read_text(), "personal document")
        self.assertEqual((home / ".config/unrelated-app/settings").read_text(), "personal settings")
        self.assertFalse((home / "Desktop/calamares.desktop").exists())
        self.assertFalse((home / ".config/.genesi-theme-applied").exists())
        backups = list((task / "desktop-backups").iterdir())
        self.assertEqual((backups[0] / ".config/kdeglobals").read_text(), "Mint palette")
        with patch.object(native, "run", side_effect=self.execute):
            native.apply_desktop_home(self.root, home, state, task)
        self.assertEqual((backups[0] / ".config/kdeglobals").read_text(), "Mint palette")
        self.assertEqual(len(list((task / "desktop-backups").iterdir())), 2)

    def test_home_symlink_cannot_redirect_writes_outside_migrated_home(self):
        home, outside = self.base / "home", self.base / "outside"
        home.mkdir()
        outside.mkdir()
        (home / ".config").symlink_to(outside, target_is_directory=True)
        with patch.object(native, "run") as run, self.assertRaises(native.MigrationError):
            native.apply_desktop_home(self.root, home, {"user": {}}, self.base / "task")
        run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
