# Genesi Migrate

Move from any Linux to Genesi: apps, files and settings, one restart, no USB
stick. The app runs **on the distro being left** (Ubuntu, Fedora, Mint,
openSUSE, Arch...) as a single AppImage.

Download: <https://genesios.org/migrate>, built by
`.github/workflows/publish-migrate.yml` into the rolling `migrate-latest` release.

## The whole flow

```
OLD SYSTEM (the AppImage)                 LIVE ISO                         INSTALLED GENESI
scan -> choose -> Prepare:                boot from the one-time entry     first boot:
  where the ISO can wait (stage.py)        genesi-migrate-live stage:        genesi-migrate-restore.service
  download + SHA-256 (resumable)             stage -> RAM, Wi-Fi up            copy the files back
  copy files to the external drive         calamares-online.sh:              Flatpaks
  pkexec helper.sh arm:                      calamares_config.py rewrites   first login:
    Wi-Fi -> stage                           the setup (no partition page,     AUR apps (paru, in a terminal)
    /etc/grub.d/42_genesi_migrate            one desktop, name pre-filled)     "what came over" notification
    grub-reboot genesi-migrate             exec: genesimigratedisk
-> Restart and migrate                             (partitions from the plan)
                                                 ... normal Genesi install ...
                                                 genesimigraterestore
                                                   (Wi-Fi, repo apps, os-prober)
```

| Piece | Where |
|---|---|
| Scanner, screen, prepare | `app/` (`scanner.py`, `Main.qml`, `genesi_migrate.py`, `stage.py`, `helper.sh`) |
| Live launcher | `genesi-arch/archiso/airootfs/usr/local/bin/genesi-migrate-live` (+ autostart, + hook in `calamares-online.sh`) |
| Calamares setup | `.../usr/lib/genesi-migrate/calamares_config.py` |
| Calamares jobs | `.../usr/lib/genesi-migrate/calamares/genesimigratedisk`, `genesimigraterestore` |
| First boot | `.../usr/lib/genesi-migrate/restore.py` |

The live-side pieces ship in the ISO, so they reach users with the **next ISO
build**. The ISO boots from a file on disk through archiso's own
`archiso_loop_mnt` (`img_dev=UUID=... img_loop=...`, the same mechanism as its
`loopback.cfg`); when that file sits on a partition the install formats or
shrinks, `copytoram=y` loads it into RAM first (7 GB of RAM required, checked
before anything is downloaded).

## Where Genesi goes

* **Replace**: only the old system partition is formatted. The EFI partition
  (Windows' boot manager included) and a separate `/home` are kept.
* **Alongside (dual boot, v2)**: the old ext4/btrfs system partition is
  shrunk (`e2fsck` + `resize2fs` / `btrfs filesystem resize`, filesystem cut
  *below* the new partition size first), Genesi goes in the freed space,
  os-prober puts the old system in Genesi's GRUB.
* **Another disk**: used whole, behind an explicit "I understand". Files stay
  where they are and are copied after the install.

Disks are found again in the live system by WWN/serial + size, partitions by
filesystem UUID: device names can change order between the two systems.

## What stops it (before anything is changed)

Secure Boot on (the old GRUB won't load Genesi's unsigned kernel), an
encrypted or LVM system partition for replace/alongside, BIOS + GPT without a
BIOS boot partition, not enough RAM for `copytoram`, no GRUB on the old
system, a disk in use.

## Try it

```bash
python app/genesi_migrate.py --demo                 # synthetic data; Prepare is simulated
python app/genesi_migrate.py                        # scan this machine (Linux)
python app/scanner.py > scan.json                   # the raw scan
python app/genesi_migrate.py --manifest scan.json   # replay someone's scan
```

## Testing in a VM

**The ISO in the VM must be built after these changes**: the live-side pieces
are part of the ISO.

1. VMs of Ubuntu 24.04, Fedora 41, Mint 22, **UEFI with Secure Boot off**,
   GRUB as bootloader (the default on all three).
2. Run the AppImage (from the `migrate-latest` release, or build it with
   `appimage/build-appimage.sh`).
3. Cover each mode: replace + external USB disk; replace + keep-home (a VM
   installed with a separate `/home`); alongside; a second virtual disk.
4. Things to look at: `~/genesi-migrate.log` in the live session,
   `/var/log/installer` / Calamares' log, `/var/lib/genesi-migrate/` and
   `journalctl -u genesi-migrate-restore` on the installed system. The
   manifest replays exactly with `--manifest`.

## Tests

* `ci/migrate-test.py`: the scanner against fake Ubuntu/Fedora/Arch roots,
  and the screen offscreen (disk step, the plan it builds).
* `ci/migrate-flow-test.py`: everything that formats, shrinks or reboots,
  as pure plans: where the ISO waits and when it needs RAM, the GRUB entry,
  resumable download, the file copy, the Calamares setup generated from the
  real config, every partitioning mode (renamed disks, busy disks, BIOS+GPT,
  the shrink math), the restore.

Both run in `hygiene-check.yml`; `publish-migrate.yml` runs them again, builds
the AppImage and starts it offscreen before publishing.
