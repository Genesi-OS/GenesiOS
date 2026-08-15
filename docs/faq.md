# Frequently Asked Questions (FAQ)

## General

### What is Genesi OS?

Genesi OS is an Arch-based Linux distribution optimized for local AI development. It automatically detects when you're running AI models (Ollama, llama.cpp, etc.) and optimizes your system for maximum performance.

### Is Genesi OS free?

Yes! Genesi OS is completely free and open source (AGPL-3.0 license).

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

## Installing apps

### How do I install an app that isn't in the Genesi Package Installer?

You already have three tools for this — every Genesi install ships them, and
none of them require compiling anything by hand.

**1. Pamac (graphical, easiest).** A full app store with AUR search built in.
Open it from the menu ("Add/Remove Software"), search, click Install. If you are
coming from Windows and just want a button, use this.

**2. `paru` (terminal).** Installs from both the official repos and the AUR:

```bash
paru -S nome-do-pacote
```

**3. `pacman` (terminal, official repos only).**

```bash
sudo pacman -S nome-do-pacote
```

You should almost never need to clone a repo and run `makepkg` yourself — that
is what `paru` does for you, including keeping the package updated afterwards.

### Example: the Minecraft launcher

```bash
paru -S minecraft-launcher
```

Search first if you are unsure of the exact name:

```bash
paru -Ss minecraft
```

### Minecraft Forge fails to install with a checksum mismatch

Symptom, during the Forge installer:

```
Expected: 7bd7f36bd766bec3edf78c230b792f2f4aa6b401
Actual:   05453ce3dab0940380fc804bba55ed0e81a9160d
There was an error during installation
```

This is a Forge/ForgeWrapper issue, not a Genesi one: the wrapper verifies a
hash that does not match what recent Forge builds actually ship. Two steps:

1. Install the 32-bit compression libraries the Minecraft native launcher needs
   (a missing `lib32-zlib` shows up later as native-library crashes):

   ```bash
   sudo pacman -S zlib lib32-zlib
   ```

2. Add this JVM argument to the launcher profile so ForgeWrapper skips the
   broken check:

   ```
   -Dforgewrapper.skipHashCheck=true
   ```

   In the official launcher: Installations → your Forge profile → Edit → More
   Options → JVM Arguments, and append it to the existing line.

---

## Genesi Mesh

### Can I use Genesi Mesh over the internet, not just my LAN?

Yes, but **never by forwarding the port**. `rpc-server` (the llama.cpp component
Mesh drives) performs no authentication and no validation of what it receives —
exposing it to the open internet hands anyone who finds it your machine. Treat
it exactly like an unauthenticated database port.

The correct way is a private network overlay, which makes the remote machine
behave as if it were on your LAN:

**Tailscale (easiest):**

```bash
sudo pacman -S tailscale
sudo systemctl enable --now tailscaled
sudo tailscale up
```

Run that on both machines, on the same account. Each gets a stable `100.x.y.z`
address. Then, on the worker:

```bash
sudo genesi-mesh worker on
```

and on the client, point at the worker's Tailscale address directly, since
multicast discovery does not cross the internet:

```bash
GENESI_MESH_ENDPOINTS=100.x.y.z:50052 genesi-ai-turbo serve
```

**WireGuard** works identically if you prefer to run your own.

### Should I expect it to be fast over the internet?

No — and this is worth being blunt about. Pooling sends layer activations across
the link **on every single token**. On gigabit Ethernet that is already the
limiting factor; over a home internet connection (tens of megabits, tens of
milliseconds of latency) it will be *much* slower than the same model running on
CPU locally.

Remote Mesh is worth it for one situation: a model that your local machine
genuinely cannot run at all, and where a slow answer beats no answer. If the
model fits locally, `genesi-ai-turbo` will refuse to use the mesh on purpose.

If what you actually want is "use my powerful desktop from my laptop", do not
pool — run Genesi Turbo on the desktop and point the laptop at its OpenAI-
compatible endpoint (`:11435`) over Tailscale. Only the text crosses the
network, so it stays fast.

---

## Still have questions?

- [GitHub Discussions](https://github.com/Genesi-OS/GenesiOS/discussions)
- [GitHub Issues](https://github.com/Genesi-OS/GenesiOS/issues)
- [Documentation](../README.md)
