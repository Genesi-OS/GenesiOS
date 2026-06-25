# Package Testing Guide

## Prerequisites

On your CachyOS VM:
```bash
sudo pacman -S base-devel git
```

## Step 1: Clone and Build

```bash
# Clone repository
git clone https://github.com/Genesi-OS/GenesiOS
cd GenesiOS/genesi-arch/packages

# Build all packages
bash build-packages.sh
```

Expected output:
```
=== Building Genesi OS Packages ===
>>> Preparing sources...
>>> Building genesi-settings...
✓ genesi-settings built successfully
>>> Building genesi-kde-settings...
✓ genesi-kde-settings built successfully
>>> Building genesi-ai-mode...
✓ genesi-ai-mode built successfully
>>> Creating repository database...
=== Build Complete ===
```

## Step 2: Add Local Repository

Edit `/etc/pacman.conf` and add:
```ini
[genesi]
SigLevel = Optional TrustAll
Server = file:///path/to/GenesiOS/genesi-arch/packages/repo
```

Update package database:
```bash
sudo pacman -Sy
```

## Step 3: Install Packages

```bash
sudo pacman -S genesi-settings genesi-kde-settings genesi-ai-mode
```

## Step 4: Verify Installation

### genesi-settings
```bash
# Check system identity
cat /etc/os-release
# Should show: NAME="Genesi OS"

cat /etc/hostname
# Should show: genesi
```

### genesi-kde-settings
```bash
# Check color scheme
ls /usr/share/color-schemes/GenesiOS.colors

# Check wallpapers
ls /usr/share/wallpapers/genesi/

# Check SDDM theme
ls /usr/share/sddm/themes/genesi/

# Check plasmoids
ls /usr/share/plasma/plasmoids/org.genesi.logo/
```

### genesi-ai-mode
```bash
# Check daemon
sudo systemctl status genesi-aid
# Should show: active (running)

# Check widget
ls /usr/share/plasma/plasmoids/org.genesi.aimode/

# Test AI Mode
ollama run llama3.2
# In another terminal:
sudo journalctl -u genesi-aid -f
# Should show: "Enabling AI Mode..."
```

## Step 5: Test Branding Persistence

### Create new user
```bash
sudo useradd -m testuser
sudo passwd testuser
```

### Login as testuser
- Logout from current session
- Login as `testuser`
- Check if Genesi branding appears:
  - Wallpaper should be Genesi
  - Color scheme should be dark green
  - Desktop icons should be present
  - Widgets should be on the right

### Test after reboot
```bash
sudo reboot
```

After reboot:
- Check if AI Mode daemon is running
- Check if branding persists
- Check if widgets are still there

## Step 6: Test Package Updates

```bash
# Simulate update
cd genesi-arch/packages/genesi-settings
# Edit pkgrel in PKGBUILD (increment by 1)
makepkg -sf
sudo pacman -U genesi-settings-*.pkg.tar.zst

# Verify update
pacman -Q genesi-settings
```

## Step 7: Test Package Removal

```bash
# Remove AI Mode
sudo pacman -R genesi-ai-mode

# Verify daemon stopped
sudo systemctl status genesi-aid
# Should show: inactive (dead)

# Reinstall
sudo pacman -S genesi-ai-mode

# Verify daemon started
sudo systemctl status genesi-aid
# Should show: active (running)
```

## Expected Results

✅ All packages build successfully
✅ Packages install without errors
✅ System shows "Genesi OS" branding
✅ KDE theme is dark green/teal
✅ AI Mode daemon runs automatically
✅ Widgets appear in panel
✅ Branding persists for new users
✅ Branding persists after reboot
✅ Packages can be updated
✅ Packages can be removed/reinstalled

## Troubleshooting

### Build fails
```bash
# Check dependencies
pacman -Q base-devel

# Check PKGBUILD syntax
cd package-name
bash -n PKGBUILD
```

### Package conflicts
```bash
# Remove conflicting packages first
sudo pacman -R cachyos-settings cachyos-kde-settings

# Then install Genesi packages
sudo pacman -S genesi-settings genesi-kde-settings
```

### Daemon not starting
```bash
# Check logs
sudo journalctl -u genesi-aid -n 50

# Check if python-psutil is installed
pacman -Q python-psutil

# Manually start
sudo systemctl start genesi-aid
```

### Widget not appearing
```bash
# Restart Plasma
kquitapp5 plasmashell && kstart5 plasmashell

# Or run auto-add script manually
/usr/local/bin/genesi-add-aimode-widget.sh
```

## Next Steps

After successful testing:
1. Build ISO with packages integrated
2. Test ISO in VM
3. Install to disk
4. Verify branding persists after installation
5. Test updates via pacman

See `../docs/PHASE3-PACKAGES.md` for integration with buildiso.sh.
