# Genesi Migrate

Move from any Linux to Genesi: apps, files and settings. This is the window
someone opens **on the distro they are leaving** (Ubuntu, Fedora, Mint,
openSUSE, Arch...). It ships as a single AppImage, so it needs nothing
installed.

```
app/
  scanner.py        reads the old system (stdlib only, read-only, no root)
  appmap.py         distro package / snap  ->  pacman / AUR / Flathub
  genesi_migrate.py PySide6 backend + entry point
  Main.qml          the screen (self-contained: no Kirigami, no shared kit)
  icons.js          inline feather icons, coloured without shaders
  demo-manifest.json synthetic scan for --demo
appimage/
  build-appimage.sh builds Genesi-Migrate-x86_64.AppImage
  AppRun            AppImage entry point
```

## Status: v1, the screen

| Step | Status |
|---|---|
| Scan apps (dpkg/rpm/pacman/xbps + flatpak + snap + CLI tools), files, disks, settings | done |
| Choose apps, files, **install disk**, where files wait, desktop, Wi-Fi | done |
| Save the migration plan (`~/.local/share/genesi-migrate/manifest.json`, mode 600) | done |
| Download the ISO, check its signature, boot it from GRUB (archiso `img_dev`/`img_loop`) | next |
| Calamares "migration mode": read the plan, pre-fill everything | next |
| Post-install: reinstall the apps, copy files back | next |

The screen says the last three are coming, rather than pretending they work.

### The install disk

* **The system disk** = *replace*: only the partition holding `/` is
  formatted. Windows, `/home` on its own partition and anything else on that
  disk stay as they are.
* **Any other disk** (internal or external) = used **whole**, erased. The
  screen draws what is on it today and demands an explicit "I understand"
  before it continues.
* When Genesi goes to another disk and `/home` is not on that disk, the files
  simply **stay where they are** and are copied over after the install. No
  backup drive needed.
* An encrypted (LUKS) root blocks only *replace*; installing to another disk
  is fine.

## Try it

On any machine with PySide6 (even Windows, for UI work):

```bash
python app/genesi_migrate.py --demo          # synthetic data, nothing scanned
python app/genesi_migrate.py                 # scan this machine (Linux)
python app/scanner.py > scan.json            # the raw scan, no window
python app/genesi_migrate.py --manifest scan.json   # replay someone's scan
```

## Testing in a VM (before the external SSD)

1. Build the AppImage on any Linux with network: `appimage/build-appimage.sh`
   (output in `appimage/out/`). It downloads a manylinux Python and the
   PySide6-Essentials wheel.
2. In VMs of **Ubuntu 24.04**, **Fedora 41** and **Linux Mint 22**: copy the
   AppImage in, `chmod +x`, run it. Try both a Wayland and an X11 session.
3. Give one VM a **second virtual disk** and attach a **virtual USB disk**,
   so the Disk step has something to choose between.
4. Check per VM: the apps you installed are listed with the right Genesi
   target; folder sizes look right; the disk list matches `lsblk`; the plan
   saves. Attach `~/.local/share/genesi-migrate/manifest.json` to any report:
   `--manifest` replays it exactly.

Nothing in v1 writes outside `~/.local/share/genesi-migrate/`, so the VMs are
for confidence, not for safety.

## Tests

`ci/migrate-test.py` plays the scanner against fake Ubuntu/Fedora/Arch roots
(answering like dpkg, rpm, pacman, snap, lsblk and nmcli really do), then
loads `Main.qml` offscreen and checks the plan it saves, including the
whole-disk confirmation. Run it with `python genesi-arch/ci/migrate-test.py`.
