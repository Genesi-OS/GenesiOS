# Genesi OS Repository Setup

## Overview

Genesi OS uses a custom pacman repository hosted on GitHub Releases for automatic updates.

## How it Works

1. **Build packages** → Create `.pkg.tar.zst` files
2. **Upload to GitHub Releases** → Host packages publicly
3. **Users add repo** → `/etc/pacman.conf` points to GitHub
4. **Automatic updates** → `pacman -Syu` or Discover GUI

## Repository Structure

```
GitHub Releases:
└── packages/
    ├── x86_64/
    │   ├── genesi-settings-1.0.0-1-any.pkg.tar.zst
    │   ├── genesi-kde-settings-1.0.0-1-any.pkg.tar.zst
    │   ├── genesi-ai-mode-1.0.0-1-any.pkg.tar.zst
    │   └── genesi.db.tar.gz (repository database)
    └── genesi.files.tar.gz (file list)
```

## Setup for Maintainers

### 1. Build Packages

```bash
cd genesi-arch/packages
bash build-packages.sh
```

This creates `repo/` with all packages and database.

### 2. Upload to GitHub Releases

#### Manual Method
1. Go to https://github.com/Genesi-OS/GenesiOS/releases
2. Create new release (e.g., `packages-v1.0.0`)
3. Upload all files from `repo/`:
   - `genesi-settings-*.pkg.tar.zst`
   - `genesi-kde-settings-*.pkg.tar.zst`
   - `genesi-ai-mode-*.pkg.tar.zst`
   - `genesi.db.tar.gz`
   - `genesi.files.tar.gz`

#### Automated Method (GitHub Actions)
Create `.github/workflows/build-packages.yml`:

```yaml
name: Build and Release Packages

on:
  push:
    paths:
      - 'genesi-arch/packages/**'
    branches:
      - arch-base

jobs:
  build:
    runs-on: ubuntu-latest
    container:
      image: cachyos/cachyos:latest
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Build packages
        run: |
          cd genesi-arch/packages
          bash build-packages.sh
      
      - name: Create Release
        uses: softprops/action-gh-release@v1
        with:
          tag_name: packages-${{ github.sha }}
          files: genesi-arch/packages/repo/*
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### 3. Update Repository Database

When you update a package:

```bash
# 1. Update PKGBUILD (bump pkgver or pkgrel)
cd genesi-arch/packages/genesi-settings
nano PKGBUILD  # pkgrel=2

# 2. Rebuild
makepkg -sf

# 3. Update repo database
cd ../repo
repo-add genesi.db.tar.gz genesi-settings-*.pkg.tar.zst

# 4. Upload to GitHub Releases
# (manual or via GitHub Actions)
```

## Setup for Users

### During Installation (ISO)

The ISO already includes the Genesi repository in `/etc/pacman.conf`:

```ini
[genesi]
SigLevel = Optional TrustAll
Server = https://github.com/Genesi-OS/GenesiOS/releases/download/packages/x86_64
```

### Manual Setup (Existing Arch/CachyOS)

Users can add Genesi OS to their existing system:

```bash
# 1. Add repository
sudo tee -a /etc/pacman.conf << 'EOF'

[genesi]
SigLevel = Optional TrustAll
Server = https://github.com/Genesi-OS/GenesiOS/releases/download/packages/x86_64
EOF

# 2. Update database
sudo pacman -Sy

# 3. Install Genesi packages
sudo pacman -S genesi-settings genesi-kde-settings genesi-ai-mode
```

## How Users Get Updates

### Method 1: Terminal (Traditional)

```bash
# Check for updates
sudo pacman -Sy

# Update all packages
sudo pacman -Syu
```

### Method 2: Discover (GUI)

1. **Automatic notification**: KDE shows update icon in systray
2. **Click icon**: Opens Discover with available updates
3. **Click "Update All"**: Installs all updates

### Method 3: Octopi (Alternative GUI)

```bash
# Install Octopi (if not installed)
sudo pacman -S octopi

# Launch and check for updates
octopi
```

## Update Notifications

### KDE Plasma (Default)

Genesi OS uses `plasma-pk-updates` for notifications:

- **Icon in systray**: Shows when updates available
- **Number badge**: Shows how many updates
- **Click to update**: Opens Discover

### Enable Notifications

Already enabled by default in `genesi-kde-settings`, but users can check:

```bash
# System Settings → Notifications → Configure
# Enable "Software Updates"
```

## Repository Mirrors (Future)

For better performance, add mirrors:

```ini
[genesi]
SigLevel = Optional TrustAll
Server = https://github.com/Genesi-OS/GenesiOS/releases/download/packages/x86_64
Server = https://mirror1.genesios.org/$arch
Server = https://mirror2.genesios.org/$arch
```

## Package Signing (Future - More Secure)

Currently using `SigLevel = Optional TrustAll` for simplicity.

For production, use GPG signing:

```bash
# 1. Generate GPG key
gpg --full-generate-key

# 2. Sign packages
gpg --detach-sign genesi-settings-*.pkg.tar.zst

# 3. Update pacman.conf
[genesi]
SigLevel = Required DatabaseOptional
Server = https://...
```

## Troubleshooting

### Updates not showing

```bash
# Force refresh database
sudo pacman -Syy

# Check if repo is accessible
curl -I https://github.com/Genesi-OS/GenesiOS/releases/download/packages/x86_64/genesi.db.tar.gz
```

### Repository not found

```bash
# Check pacman.conf
cat /etc/pacman.conf | grep -A 2 "\[genesi\]"

# Should show:
# [genesi]
# SigLevel = Optional TrustAll
# Server = https://...
```

### Package conflicts

```bash
# Remove conflicting CachyOS packages
sudo pacman -R cachyos-settings cachyos-kde-settings

# Install Genesi packages
sudo pacman -S genesi-settings genesi-kde-settings
```

## Bandwidth and Costs

### GitHub Releases
- **Free**: Unlimited bandwidth for public repos
- **Limit**: 2GB per file (our packages are <100MB)
- **Reliability**: GitHub's CDN (very fast)

### Alternative: Own Server
- **Cost**: ~$5-10/month (VPS)
- **Control**: Full control over updates
- **Setup**: nginx + rsync

## Example: Publishing Update

```bash
# 1. User reports bug in AI Mode
# 2. Fix bug in genesi-aid daemon
# 3. Update PKGBUILD
cd genesi-arch/packages/genesi-ai-mode
nano PKGBUILD  # pkgrel=2

# 4. Rebuild
makepkg -sf

# 5. Update repo
cd ../repo
repo-add genesi.db.tar.gz genesi-ai-mode-*.pkg.tar.zst

# 6. Upload to GitHub Releases
# (via web UI or GitHub CLI)
gh release upload packages genesi-ai-mode-*.pkg.tar.zst genesi.db.tar.gz --clobber

# 7. Users get notification
# "1 update available: genesi-ai-mode"
# Click "Update" → Done!
```

## Benefits

✅ **Automatic**: Users don't need to rebuild ISO
✅ **Fast**: GitHub CDN is worldwide
✅ **Free**: No hosting costs
✅ **Integrated**: Works with KDE Discover
✅ **Familiar**: Same as Arch/CachyOS workflow

## Next Steps

1. [ ] Create first GitHub Release with packages
2. [ ] Test repository URL accessibility
3. [ ] Add repo to ISO's pacman.conf
4. [ ] Test updates in VM
5. [ ] Setup GitHub Actions for automation
6. [ ] Document for users

---

**Status**: Ready to implement

**See also**: `PHASE3-PACKAGES.md` for package building
