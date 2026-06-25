# Phase 3: Own Packages and Repository

## Goal

Create Genesi OS packages to replace CachyOS packages, ensuring branding persists after installation to disk.

## Problem

Currently, Genesi OS uses `customize_airootfs.sh` to rebrand CachyOS packages during ISO build. This works for the Live ISO but:
- ❌ Branding doesn't persist after installing to disk
- ❌ System reverts to CachyOS after installation
- ❌ Updates may break branding (sed patches are fragile)

## Solution

Create our own packages that:
- ✅ Replace CachyOS packages (`provides=` and `conflicts=`)
- ✅ Install Genesi branding natively
- ✅ Persist after installation
- ✅ Can be updated via pacman

## Package Structure

### 1. genesi-settings
**Replaces**: System files (os-release, hostname, etc.)
**Files**:
- `/etc/os-release` - System identity
- `/etc/lsb-release` - LSB info
- `/etc/issue` - Login banner
- `/etc/hostname` - Default hostname

### 2. genesi-kde-settings
**Replaces**: `cachyos-kde-settings`
**Files**:
- `/usr/share/color-schemes/GenesiOS.colors` - KDE color scheme
- `/usr/share/wallpapers/genesi/` - Wallpapers
- `/usr/share/konsole/Genesi.colorscheme` - Konsole theme
- `/usr/share/sddm/themes/genesi/` - Login screen
- `/usr/share/plymouth/themes/genesi/` - Boot splash
- `/usr/share/plasma/plasmoids/org.genesi.logo/` - Logo widget
- `/etc/skel/.config/` - Default KDE configs
- `/etc/skel/Desktop/` - Desktop icons

### 3. genesi-ai-mode
**New package** (doesn't replace anything)
**Files**:
- `/usr/local/bin/genesi-aid` - AI Mode daemon
- `/usr/lib/systemd/system/genesi-aid.service` - Systemd service
- `/etc/sysctl.d/99-genesi-ai.conf` - Kernel optimizations
- `/usr/share/plasma/plasmoids/org.genesi.aimode/` - AI Mode widget
- `/usr/local/bin/genesi-add-aimode-widget.sh` - Widget auto-add script

### 4. genesi-welcome (Future)
**Replaces**: `cachyos-hello`
**Files**:
- `/usr/bin/genesi-welcome` - Welcome app
- `/usr/share/applications/genesi-welcome.desktop` - Desktop entry
- `/etc/xdg/autostart/genesi-welcome.desktop` - Autostart

## Build Process

### Step 1: Prepare source files

Each package needs source files from `airootfs/`:

```bash
# genesi-settings
cp airootfs/etc/os-release packages/genesi-settings/
cp airootfs/etc/lsb-release packages/genesi-settings/
# ... etc

# genesi-kde-settings  
cp airootfs/usr/share/color-schemes/GenesiOS.colors packages/genesi-kde-settings/
cp -r airootfs/usr/share/wallpapers/genesi packages/genesi-kde-settings/
# ... etc

# genesi-ai-mode
cp airootfs/usr/local/bin/genesi-aid packages/genesi-ai-mode/
cp airootfs/usr/lib/systemd/system/genesi-aid.service packages/genesi-ai-mode/
# ... etc
```

### Step 2: Build packages

```bash
cd packages
./build-packages.sh
```

This creates:
- `packages/repo/*.pkg.tar.zst` - Built packages
- `packages/repo/genesi.db.tar.gz` - Repository database

### Step 3: Add to ISO build

Modify `buildiso.sh` to:
1. Build packages before building ISO
2. Add local repository to `pacman.conf`
3. Install `genesi-*` packages instead of `cachyos-*`

### Step 4: Test

1. Build ISO with new packages
2. Boot Live ISO - should have Genesi branding
3. Install to disk
4. Reboot - **branding should persist!**

## Repository Hosting (Future)

For public release, host packages on:
- **GitHub Releases** - Simple, free
- **Own server** - More control
- **Cloudflare R2** - CDN, fast

Example pacman.conf:
```ini
[genesi]
SigLevel = Optional TrustAll
Server = https://github.com/Genesi-OS/GenesiOS/releases/download/packages/$arch
```

## Migration Path

### Current (Phase 1-2):
```
CachyOS packages → customize_airootfs.sh → Genesi branding (Live ISO only)
```

### Phase 3:
```
Genesi packages → Native branding → Persists after installation
```

### Benefits:
- ✅ Branding persists after installation
- ✅ Updates via pacman (no rebuild needed)
- ✅ Can distribute updates independently
- ✅ Users can install on existing Arch/CachyOS
- ✅ Cleaner, more maintainable

## Next Steps

1. [ ] Copy source files from `airootfs/` to package directories
2. [ ] Build packages locally
3. [ ] Test packages in VM
4. [ ] Integrate into `buildiso.sh`
5. [ ] Build ISO with new packages
6. [ ] Test installation persistence
7. [ ] Setup GitHub Releases for hosting
8. [ ] Update documentation

## Files to Create

- [x] `packages/genesi-settings/PKGBUILD`
- [x] `packages/genesi-ai-mode/PKGBUILD`
- [x] `packages/genesi-kde-settings/PKGBUILD`
- [x] `packages/build-packages.sh`
- [ ] `packages/genesi-welcome/PKGBUILD` (future)
- [ ] Copy all source files from airootfs
- [ ] Modify `buildiso.sh` to use packages
- [ ] Create pacman.conf with genesi repo

## Testing Checklist

- [ ] Build packages successfully
- [ ] Install packages in clean VM
- [ ] Verify branding appears
- [ ] Build ISO with packages
- [ ] Boot Live ISO - check branding
- [ ] Install to disk
- [ ] Reboot - **verify branding persists**
- [ ] Run `pacman -Syu` - verify updates work
- [ ] Check AI Mode daemon works
- [ ] Check widgets appear

---

**Status**: 🚧 IN PROGRESS

**Next**: Copy source files and build first packages
