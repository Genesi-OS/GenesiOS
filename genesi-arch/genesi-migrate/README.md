# Genesi Migrate

The default current-system action now prepares an installed Genesi tree and
switches through an automatic offline worker. It does not launch Calamares or
format the source partition. This first native implementation is experimental:
validate it in a disposable Mint VM before using it on real data.

## Native Flow

1. Download the build-source ISO resumably and verify SHA-256. It is used only
   during preparation, never as the boot environment for native migration.
2. Under administrator authorization, build the selected Genesi desktop using
   the ISO's Arch userspace in a private mount namespace. The host's package
   manager is untouched. Prepare packages, account, kernel and initramfs.
3. Build a dedicated mkinitcpio maintenance image from the prepared kernel,
   Python worker, disk tools and storage drivers (no live desktop). The image
   is limited to 192 MiB compressed and its required tools are checked.
   Before arming boot, extract it into private staging and execute its Python
   interpreter and arch-chroot against the prepared tree. This catches missing
   libraries and incompatible BusyBox replacements while the old OS still runs.
   The private duplicate ISO is removed after a successful build; the cached
   verified download remains available for retries.
   Verify the target tree and remaining space. Build a standalone EFI rescue
   loader with ext4/Btrfs support. Record the original EFI boot order; the Later
   button restores it. Mint/Windows EFI files are not overwritten.
4. The user restarts once. GRUB loads only the kernel and dedicated initramfs.
   It reads the small migration state from the source read-only, unmounts it,
   and performs the offline switch. No ISO copy-to-RAM or live session runs.
5. Identify the disk by serial/WWN, size, PARTUUID and filesystem UUID. Require
   an unmounted source and verify the prepared tree again before conversion.
6. Check ext4 read-only, then run btrfs-convert --uuid copy. Supported existing
   Btrfs roots skip conversion. Create Genesi's @ and @genesi-home, copy the
   prepared system and reflink the entire original home with ownership intact.
7. Generate fstab/initramfs and validate GRUB before publishing boot-ready.
   mkinitcpio mounts the new root and switches directly into Genesi during
   this same boot. There is no second restart.
8. Snapshots initializes at first boot. The existing restoration worker finishes
   optional Flatpak/AUR work and reports unavailable applications.

Original directories and conversion metadata remain on disk; they are not
automatically deleted. ext2_saved/image is conversion rollback metadata, not an
independent backup or a promise that the old OS remains bootable. Do not remove
it or balance/defragment while rollback matters.
See [btrfs-convert documentation](https://btrfs.readthedocs.io/en/latest/btrfs-convert.html).

## Initial Supported Layout

- Installed x86_64 Linux, UEFI, Secure Boot disabled.
- Plain ext4/Btrfs root with stable disk identity and PARTUUID.
- Home, var and boot on that root; an existing FAT ESP on the same disk.
- At least 2 GB installed RAM and 32 GiB free before privileged preparation.
  32 GiB means 34.36 decimal GB; a disk utility displaying 34 GB may be below
  this threshold. Space errors report required, available and missing bytes in
  both units. Pending downloads/backups on the same filesystem are budgeted
  before downloading, so they do not consume the preparation reserve.
  After building the target, its second tree plus 8 GiB reserve must still fit.
- Existing Btrfs roots named @ are blocked pending subvolume-exchange support.
  Mint's normal ext4 installation is the first test target.

BIOS, LUKS/LVM, separate home/boot/var, other filesystem types and ambiguous
identities are refused before arming boot. They never silently fall back to
formatting. Alongside and another-disk choices remain separate legacy flows.

## Failure Handling

Interrupted downloads keep a resumable partial file. SHA-256 and verified
temporary backups are mandatory; marker files and size/mtime cannot bypass
verification. Copy errors prevent arming the reboot.

State uses atomic rename and fsync under root-owned staging. Artifact, source,
copy or GRUB failures stop in maintenance instead of rebooting to an incomplete
target. A completed migration cannot be replayed over the new user's files.
A source still mounted cannot be converted. The native boot has no ISO holders.
Preparation also uses a private PID namespace. Before unmounting a chroot,
only helpers rooted inside that mount and belonging to its private namespace
are stopped using stable PID handles. Loop devices for the ISO and its embedded
SquashFS are explicitly detached in child-before-parent order. Cleanup failures
are logged without replacing an earlier package/build error.
Package installation and large offline copies are supervised to retain an
8 GiB free-space reserve. Space is checked again after restarting, before
conversion, in case the user created more files after preparation.

Recovery remains selectable in the independent EFI menu. In-place conversion
cannot guarantee survival of power loss or hardware failure; use a VM clone
for destructive failure testing. No automatic filesystem repair or original
data cleanup is performed.

Preparation logs: /var/lib/genesi-migrate-native/<task>/prepare.log.
Offline errors appear in the maintenance terminal. Keep staging for diagnosis.

## Mint VM Test

Use a disposable installed Mint VM with EFI enabled, Secure Boot off, 2+ GB
RAM and an 80+ GB virtual disk with at least 40 GB free. Snapshot/clone it first,
create a document in home and record its SHA-256.

The native boot does not depend on an ISO live hook. The standalone AppImage
builds its own maintenance initramfs; changing Migrate does not rebuild the ISO.

After the AppImage publishing workflow succeeds:

```bash
curl -fL --retry 3 -o Genesi-Migrate-x86_64.AppImage \
  https://github.com/Genesi-OS/GenesiOS/releases/download/migrate-latest/Genesi-Migrate-x86_64.AppImage
chmod +x Genesi-Migrate-x86_64.AppImage
./Genesi-Migrate-x86_64.AppImage
```

Choose the current system, prepare and restart when ready. In Genesi verify:

```bash
findmnt -no FSTYPE,FSROOT /
findmnt -no FSTYPE,FSROOT /home
sha256sum ~/your-test-document
systemctl status genesi-migrate-health.service genesi-snapshots-setup.service
sudo cat /var/lib/genesi-migrate/healthy.json
```

Expected mounts are Btrfs /@ and Btrfs /@genesi-home. Also test interrupted
downloads, Later cancellation, and selecting maintenance after installation.
The real Mint conversion and UEFI boot have not been validated by unit tests.

## Development

```bash
python genesi-arch/ci/migrate-test.py
python genesi-arch/ci/migrate-flow-test.py
python genesi-arch/ci/migrate-inplace-test.py
python genesi-arch/genesi-migrate/app/genesi_migrate.py --demo
```

Tests mock every conversion/mount/reboot command, covering native UI routing,
device identity, integrity failures, source-home preservation and same-boot handoff.
They do not perform disk operations.

The separate integration test uses disposable image files, real read-only
ISO/SquashFS mounts and a background chroot helper. It verifies ordinary and
error cleanup without touching physical partitions or running conversion:

```bash
sudo unshare --mount --pid --fork --kill-child=KILL --mount-proc --propagation private python3 genesi-arch/ci/migrate-mount-test.py
```

An opt-in end-to-end QEMU test builds the real maintenance initramfs from an
official Arch bootstrap verified against its published SHA-256. It uses a new
24 GiB sparse file, a 2 GiB guest, real ext4-to-Btrfs conversion and a prepared
system with a preserved home sentinel. No physical disks are passed to QEMU:

```bash
sudo unshare --mount --pid --fork --kill-child=KILL --mount-proc --propagation private \
  python3 genesi-arch/ci/migrate-boot-test.py /path/to/archlinux-bootstrap-x86_64.tar.zst SHA256
```

This slow, network-dependent test is not run on each AppImage publication.
It complements, rather than replaces, a full Mint-to-Genesi desktop/UEFI test.

Manual QEMU validation exercised real conversion, exact home-file preservation,
successful GRUB/initramfs generation and a same-boot handoff into systemd with
2 GiB guest RAM and no attached ISO. A separate installed-root boot reached the
success service. The initial minimal fixture needed first-boot configuration;
the fixture now uses the same machine-ID initialization as production. This
does not certify every desktop, firmware or source-distro layout.

Preparation temporarily disables initramfs autodetect and explicitly includes
ext4/Btrfs drivers. Offline configuration removes that staging override and
rebuilds the image with normal autodetect on the mounted destination root.

app/native-profiles.json is generated from the installer's package lists.
After changing those lists, regenerate it with PyYAML installed:

```bash
python genesi-arch/genesi-migrate/build-profiles.py
```
