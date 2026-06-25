# Genesi OS Installation Guide

This guide will walk you through installing Genesi OS on your computer.

## 📋 Prerequisites

### System Requirements

- **CPU**: x86_64 (64-bit) processor
- **RAM**: 4GB minimum, 8GB+ recommended
- **Storage**: 30GB minimum, 50GB+ recommended
- **GPU**: Any (AI Mode works on CPU-only)
- **UEFI**: Recommended (BIOS also supported)

### What You'll Need

- USB drive (8GB+)
- Genesi OS ISO file
- 30-60 minutes of time

## 📥 Step 1: Download Genesi OS

1. Go to [Releases](https://github.com/Genesi-OS/GenesiOS/releases/latest)
2. Download `genesi-*.iso` (latest version)
3. Download `genesi-*.iso.sha256` (checksum)

### Verify Download (Optional but Recommended)

**Linux/macOS:**
```bash
sha256sum -c genesi-*.iso.sha256
```

**Windows (PowerShell):**
```powershell
Get-FileHash genesi-*.iso -Algorithm SHA256
```

## 💾 Step 2: Create Bootable USB

### Linux

```bash
# Find your USB device
lsblk

# Create bootable USB (replace /dev/sdX with your USB)
sudo dd if=genesi-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

### macOS

```bash
# Find your USB device
diskutil list

# Unmount USB
diskutil unmountDisk /dev/diskX

# Create bootable USB
sudo dd if=genesi-*.iso of=/dev/rdiskX bs=1m
```

### Windows

**Option 1: Rufus (Recommended)**
1. Download [Rufus](https://rufus.ie/)
2. Select Genesi OS ISO
3. Select USB drive
4. Click "Start"

**Option 2: Ventoy**
1. Download [Ventoy](https://www.ventoy.net/)
2. Install Ventoy on USB
3. Copy ISO to USB drive

## 🚀 Step 3: Boot from USB

1. **Insert USB** into computer
2. **Restart** computer
3. **Enter Boot Menu**:
   - Common keys: F2, F12, Del, Esc
   - Check your motherboard manual
4. **Select USB drive** from boot menu
5. **Boot Genesi OS Live**

### UEFI vs BIOS

- **UEFI**: Recommended, supports Secure Boot (if disabled)
- **BIOS**: Legacy mode, works but less features

## 🖥️ Step 4: Try Live Environment (Optional)

Before installing, you can test Genesi OS:

- Desktop works?
- WiFi connects?
- Hardware detected?
- AI Mode works? (install Ollama and test)

## 📦 Step 5: Install Genesi OS

### Launch Installer

1. Double-click **"Install Genesi OS"** on desktop
2. Or run: `sudo calamares`

### Installation Steps

#### 1. Welcome
- Select language
- Click "Next"

#### 2. Location
- Select timezone
- Click "Next"

#### 3. Keyboard
- Select keyboard layout
- Test in text box
- Click "Next"

#### 4. Partitions

**Option A: Erase Disk (Easiest)**
- Select "Erase disk"
- Choose disk
- Select filesystem (ext4 or btrfs)
- Click "Next"

**Option B: Manual Partitioning (Advanced)**

Recommended layout:
- `/boot/efi`: 512MB, FAT32 (UEFI only)
- `/`: 30GB+, ext4 or btrfs
- `swap`: 4-8GB (optional, for hibernation)
- `/home`: Remaining space, ext4 or btrfs

**Option C: Dual Boot**
- Shrink existing partition (Windows/Linux)
- Create new partitions for Genesi OS
- Install bootloader to EFI partition

#### 5. Users
- Full name
- Username
- Password (strong!)
- Hostname (default: genesi)
- Auto-login? (not recommended)
- Click "Next"

#### 6. Summary
- Review settings
- Click "Install"

#### 7. Installation
- Wait 10-20 minutes
- Don't interrupt!

#### 8. Finish
- Click "Restart now"
- Remove USB when prompted

## 🎉 Step 6: First Boot

### Login
- Enter username and password
- KDE Plasma loads

### First Steps

1. **Check for updates**:
   ```bash
   sudo pacman -Syu
   ```

2. **Install AI tools** (optional):
   ```bash
   curl -fsSL https://ollama.ai/install.sh | sh
   ollama pull llama3.2
   ```

3. **Explore desktop**:
   - Widgets on the right
   - Desktop icons on the left
   - Floating panel at bottom

4. **Test AI Mode**:
   ```bash
   ollama run llama3.2
   # Check widget - should show "AI Mode: ON"
   ```

## 🔧 Post-Installation

### Install Additional Software

```bash
# Development tools
sudo pacman -S code docker git

# Media
sudo pacman -S vlc gimp inkscape

# Office
sudo pacman -S libreoffice

# Gaming
sudo pacman -S steam lutris
```

### Enable Services

```bash
# Docker
sudo systemctl enable --now docker
sudo usermod -aG docker $USER

# Bluetooth
sudo systemctl enable --now bluetooth
```

### Configure System

- **System Settings** → Appearance → Theme
- **System Settings** → Power Management
- **System Settings** → Display

## 🐛 Troubleshooting

### Boot Issues

**Black screen after boot**
- Try: `nomodeset` kernel parameter
- Edit GRUB: press `e`, add `nomodeset` to linux line

**WiFi not working**
```bash
# Check drivers
lspci -k | grep -A 3 Network

# Install firmware
sudo pacman -S linux-firmware
```

**NVIDIA issues**
```bash
# Install NVIDIA drivers
sudo pacman -S nvidia nvidia-utils
```

### Installation Issues

**Installer crashes**
- Check logs: `journalctl -b`
- Try: Boot with `nomodeset`

**Disk not detected**
- Check BIOS: AHCI mode enabled?
- Try: Different USB port

**Bootloader not installed**
- Check: UEFI vs BIOS mode
- Reinstall: Boot from USB, chroot, reinstall GRUB

## 📚 Next Steps

- [Features Overview](features.md)
- [AI Mode Documentation](../genesi-arch/docs/PHASE2-AI-MODE.md)
- [FAQ](faq.md)
- [Troubleshooting](troubleshooting.md)

## 💬 Need Help?

- [GitHub Issues](https://github.com/Genesi-OS/GenesiOS/issues)
- [Discussions](https://github.com/Genesi-OS/GenesiOS/discussions)
- [Arch Wiki](https://wiki.archlinux.org/) (for general Arch questions)

---

**Welcome to Genesi OS! 🎉**
