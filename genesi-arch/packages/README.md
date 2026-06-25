# Genesi OS Packages

This directory contains PKGBUILDs for Genesi OS packages, based on CachyOS packages.

## Package List

### genesi-settings
**Based on**: [cachyos-settings](https://github.com/CachyOS/CachyOS-PKGBUILDS/tree/master/cachyos-settings)
**Purpose**: System branding (os-release, hostname, etc.)
**Provides**: `cachyos-settings`
**Conflicts**: `cachyos-settings`

### genesi-kde-settings
**Based on**: [cachyos-kde-settings](https://github.com/CachyOS/CachyOS-PKGBUILDS/tree/master/cachyos-kde-settings)
**Purpose**: KDE Plasma theme, wallpapers, configs
**Provides**: `cachyos-kde-settings`, `cachyos-desktop-settings`
**Conflicts**: `cachyos-kde-settings`, `cachyos-desktop-settings`

### genesi-ai-mode
**Based on**: Original Genesi OS package
**Purpose**: AI Mode daemon, widget, and optimizations
**Provides**: N/A (new package)
**Conflicts**: N/A

## Building Packages

### Prerequisites
```bash
# Install build tools
sudo pacman -S base-devel

# Navigate to packages directory
cd genesi-arch/packages
```

### Build all packages
```bash
./build-packages.sh
```

This will:
1. Build each package in order
2. Create `repo/` directory with built packages
3. Generate repository database (`genesi.db.tar.gz`)

### Build individual package
```bash
cd genesi-settings
makepkg -sf
```

## Using the Local Repository

Add to `/etc/pacman.conf`:
```ini
[genesi]
SigLevel = Optional TrustAll
Server = file:///path/to/genesi-arch/packages/repo
```

Then:
```bash
sudo pacman -Sy
sudo pacman -S genesi-settings genesi-kde-settings genesi-ai-mode
```

## Integration with ISO Build

The `buildiso.sh` script will:
1. Build packages before building ISO
2. Add local repository to ISO's `pacman.conf`
3. Install `genesi-*` packages during ISO creation
4. Remove `cachyos-*` packages (replaced by `genesi-*`)

## Source Files

Package source files come from `../archiso/airootfs/`:
- `genesi-settings`: System files from `/etc/`
- `genesi-kde-settings`: KDE configs, themes, wallpapers
- `genesi-ai-mode`: AI Mode daemon and widget

## Updating Packages

When updating files in `airootfs/`, remember to:
1. Copy updated files to package directories
2. Bump `pkgver` or `pkgrel` in PKGBUILD
3. Rebuild packages
4. Update repository database

## Repository Hosting (Future)

For public release, packages will be hosted on:
- GitHub Releases (primary)
- Own server (mirror)

Users will add:
```ini
[genesi]
SigLevel = Optional TrustAll
Server = https://github.com/Genesi-OS/GenesiOS/releases/download/packages/$arch
```

## Credits

Based on [CachyOS PKGBUILDs](https://github.com/CachyOS/CachyOS-PKGBUILDS) by the CachyOS team.
