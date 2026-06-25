# Frequently Asked Questions (FAQ)

## General

### What is Genesi OS?

Genesi OS is an Arch-based Linux distribution optimized for local AI development. It automatically detects when you're running AI models (Ollama, llama.cpp, etc.) and optimizes your system for maximum performance.

### Is Genesi OS free?

Yes! Genesi OS is completely free and open source (GPL-3.0 license).

### What makes Genesi OS different?

- **AI Mode**: Automatic system optimization for AI workloads (unique!)
- **Performance**: 15-25% faster AI inference on CPU-only systems
- **Beautiful**: Custom dark green theme with glassmorphism
- **Based on CachyOS**: Optimized Arch Linux with BORE scheduler

### Who is Genesi OS for?

- AI developers and enthusiasts
- People running local AI models (Ollama, llama.cpp, etc.)
- Anyone who wants a beautiful, fast Arch-based system
- Developers who value performance and aesthetics

## Installation

### What are the system requirements?

- **CPU**: x86_64 (64-bit) processor
- **RAM**: 4GB minimum, 8GB+ recommended
- **Storage**: 30GB minimum, 50GB+ recommended
- **GPU**: Any (AI Mode works on CPU-only)

### Can I dual boot with Windows?

Yes! During installation, choose "Install alongside" and the installer will handle partitioning.

### Does Genesi OS support Secure Boot?

Currently no. Disable Secure Boot in BIOS/UEFI before installing.

### Can I install Genesi OS on a VM?

Yes! Works great on VirtualBox, VMware, and QEMU/KVM. Allocate at least 8GB RAM and 4 CPU cores for best experience.

## AI Mode

### What is AI Mode?

AI Mode is a daemon (`genesi-aid`) that automatically detects when you're running AI models and optimizes your system:
- CPU governor → performance
- Swappiness → 10
- Huge pages → enabled
- Process priority → high
- CPU pinning → performance cores

### Which AI frameworks are supported?

- Ollama
- llama.cpp (llama-server, llama-cli)
- vLLM
- LocalAI
- text-generation-webui
- KoboldCPP
- Oobabooga

### How much faster is AI Mode?

On CPU-only systems: **15-25% faster** inference (tokens/second).

With GPU: Improvements are smaller but still noticeable (better CPU utilization, less swap).

### Can I disable AI Mode?

Yes:
```bash
sudo systemctl stop genesi-aid
sudo systemctl disable genesi-aid
```

### Does AI Mode work with GPU?

Yes! AI Mode optimizes CPU and memory even when using GPU. Future versions will add GPU-specific optimizations.

## Updates

### How do I update Genesi OS?

```bash
# Terminal
sudo pacman -Syu

# Or use Discover (GUI)
# Click update icon in systray
```

### How often are updates released?

- **System packages**: Rolling release (daily updates from Arch/CachyOS)
- **Genesi packages**: As needed (bug fixes, new features)

### Will updates break my system?

Unlikely, but possible (it's Arch!). Best practices:
- Read update notes
- Backup important data
- Don't update before important work

## Packages

### What package manager does Genesi OS use?

`pacman` (same as Arch Linux).

### Can I install AUR packages?

Yes! Use `paru` (pre-installed):
```bash
paru -S package-name
```

### Where are Genesi-specific packages?

Genesi repository on GitHub Releases. Already configured in `/etc/pacman.conf`.

## Desktop Environment

### What desktop environment does Genesi OS use?

KDE Plasma 6 (Wayland by default, X11 available).

### Can I use a different desktop?

Yes, but you'll lose Genesi-specific features (AI Mode widget, custom theme). Install with:
```bash
sudo pacman -S gnome  # or xfce4, i3, etc.
```

### How do I customize the theme?

System Settings → Appearance → Colors → Select "GenesiOS"

### Can I change the wallpaper?

Yes! Right-click desktop → Configure Desktop and Wallpaper

## Performance

### Is Genesi OS faster than Ubuntu/Fedora?

For AI workloads: **Yes** (AI Mode optimizations).

For general use: Similar, but CachyOS kernel is optimized for performance.

### Does Genesi OS use more RAM?

No. Similar to other KDE-based distros (~1.5GB idle).

### Can I run Genesi OS on old hardware?

Minimum: 4GB RAM, dual-core CPU. Older hardware may struggle with KDE Plasma.

## Troubleshooting

### WiFi not working

```bash
# Check drivers
lspci -k | grep -A 3 Network

# Install firmware
sudo pacman -S linux-firmware
sudo reboot
```

### NVIDIA drivers not working

```bash
# Install NVIDIA drivers
sudo pacman -S nvidia nvidia-utils
sudo reboot
```

### AI Mode not activating

```bash
# Check daemon status
sudo systemctl status genesi-aid

# Check logs
sudo journalctl -u genesi-aid -f

# Restart daemon
sudo systemctl restart genesi-aid
```

### System won't boot

Boot from USB → chroot → fix bootloader:
```bash
sudo mount /dev/sdXY /mnt
sudo arch-chroot /mnt
grub-install /dev/sdX
grub-mkconfig -o /boot/grub/grub.cfg
exit
sudo reboot
```

## Development

### Can I contribute to Genesi OS?

Yes! See [CONTRIBUTING.md](../CONTRIBUTING.md).

### Where is the source code?

[GitHub: Genesi-OS/GenesiOS](https://github.com/Genesi-OS/GenesiOS)

### How do I build Genesi OS from source?

See [Building from Source](../genesi-arch/README.md).

## Comparison

### Genesi OS vs CachyOS?

- **Base**: Both use CachyOS kernel
- **Unique**: Genesi has AI Mode (CachyOS doesn't)
- **Theme**: Genesi has custom dark green theme
- **Target**: Genesi targets AI developers

### Genesi OS vs Arch Linux?

- **Base**: Genesi is Arch-based
- **Ease**: Genesi is easier to install (GUI installer)
- **Optimizations**: Genesi has AI Mode and CachyOS kernel
- **Theme**: Genesi has custom theme out-of-the-box

### Genesi OS vs Ubuntu?

- **Base**: Different (Arch vs Debian)
- **Updates**: Genesi is rolling release
- **Performance**: Genesi is faster for AI workloads
- **Stability**: Ubuntu is more stable, Genesi is more cutting-edge

## Miscellaneous

### What does "Genesi" mean?

Genesis in Portuguese/Italian. Represents a new beginning for AI-optimized Linux.

### Who develops Genesi OS?

Open source project by the Genesi OS Team. See [Contributors](https://github.com/Genesi-OS/GenesiOS/graphs/contributors).

### Is there a Discord/Forum?

Coming soon! For now, use [GitHub Discussions](https://github.com/Genesi-OS/GenesiOS/discussions).

### Can I donate?

Not yet, but we appreciate stars on GitHub! ⭐

---

## Still have questions?

- [GitHub Discussions](https://github.com/Genesi-OS/GenesiOS/discussions)
- [GitHub Issues](https://github.com/Genesi-OS/GenesiOS/issues)
- [Documentation](../README.md)
