<div align="center">

# Genesi OS

**The Linux distribution that optimizes itself for local AI.**

A CachyOS-based, KDE Plasma desktop that automatically tunes the system the
moment you start running models locally — and stays beautiful, fast, and
effortless to keep updated.

[![License](https://img.shields.io/badge/License-GPL--3.0-1D9E75.svg)](LICENSE)
[![Based on](https://img.shields.io/badge/Based%20on-CachyOS-blue.svg)](https://cachyos.org)
[![Desktop](https://img.shields.io/badge/Desktop-KDE%20Plasma%206-1d99f3.svg)](https://kde.org/plasma-desktop/)
[![ISO Pipeline](https://img.shields.io/github/actions/workflow/status/zFreshy/GenesiOS/iso-pipeline.yml?label=ISO%20build&branch=main)](https://github.com/zFreshy/GenesiOS/actions/workflows/iso-pipeline.yml)
[![Packages](https://img.shields.io/github/actions/workflow/status/zFreshy/GenesiOS/publish-packages.yml?label=packages&branch=main)](https://github.com/zFreshy/GenesiOS/actions/workflows/publish-packages.yml)

[Download](#-download) • [Features](#-features) • [How it works](#-how-it-works) • [Build](#-building-from-source) • [Roadmap](docs/ROADMAP.md) • [Contributing](#-contributing)

<img src="wallpapers/wallpaper.png" alt="Genesi OS" width="760">

</div>

---

## 🌟 What is Genesi OS?

Genesi OS is an **Arch-based Linux distribution** (built on top of
[CachyOS](https://cachyos.org)) with one defining idea: **the operating system
should optimize itself for local AI inference**. When it detects that you're
running Ollama, llama.cpp, vLLM, or LocalAI, a background daemon retunes the CPU
governor, memory, huge pages, and process priorities for inference — then puts
everything back to normal when you're done. No flags, no config files.

On top of that it ships a polished, dark-green KDE Plasma 6 desktop with
glassmorphism, its own welcome app, its own installer branding, and a
**self-hosted package repository** so the whole experience persists after you
install to disk and keeps updating like any rolling distro.

### Why Genesi OS?

- 🤖 **AI Mode** — automatic optimization when local AI is running
- ⚡ **Tuned for inference** — performance governor, huge pages, swappiness, core pinning
- 🎨 **Beautiful by default** — custom dark-green Plasma theme with glassmorphism
- 📦 **Native packages** — branding & features survive installation (not live-ISO-only hacks)
- 🔄 **Real rolling updates** — stable & testing channels via a self-hosted pacman repo
- 🆓 **Free & open source** — GPL-3.0

---

## ✨ Features

### 🤖 AI Mode — the differentiator

A systemd daemon (`genesi-aid`) watches for AI workloads and reconfigures the
system on the fly:

| When AI is running | Genesi OS does |
|--------------------|----------------|
| **CPU** | Switches the governor to `performance` |
| **Memory** | Drops `vm.swappiness` to 10 |
| **Huge pages** | Enables 2MB Transparent Huge Pages, pre-allocates for inference |
| **Scheduling** | Raises priority (`nice -5`) on CachyOS BORE, pins threads to performance cores |
| **I/O** | Tunes readahead for large GGUF files |
| **Desktop** | Trims compositor effects to free resources |

When inference stops, every change is reverted. A **Plasma widget** shows AI Mode
status, the detected processes (with PIDs), the optimizations currently applied,
and includes a manual ON/OFF toggle — with a pulsing animation while active.

### 🎨 Visual identity

- **Dark-green theme** — `GenesiOS.colors` (Genesi `#1D9E75`, Forest `#04342C`, Mint `#E1F5EE`)
- **Glassmorphism** — KWin blur + translucency, Darkly window decorations
- **Rounded windows** — 14px corners via Klassy
- **Custom desktop** — floating panel, desktop widgets (clock, CPU, RAM, notes), branded icons
- **Branded login & boot** — SDDM theme + Plymouth splash
- **Genesi Welcome** — first-run app replacing CachyOS Hello

### 📦 Native packages & self-hosted repository

Genesi OS no longer relies on rebranding CachyOS packages at build time. It ships
**eight real packages** through its own pacman repo, so everything persists after
installation:

| Package | Purpose |
|---------|---------|
| `genesi-settings` | System branding (`os-release`, hostname, MOTD, sysctl) |
| `genesi-kde-settings` | Plasma theme, wallpapers, Klassy corners, panel layout |
| `genesi-ai-mode` | AI Mode daemon, systemd service, plasmoid |
| `genesi-update` | Interactive update notifier + systray applet |
| `genesi-channel` | Switch between **stable** and **testing** channels |
| `genesi-calamares` | Calamares installer |
| `genesi-calamares-branding` | Native installer branding (logo, slideshow, colors) |
| `genesi-welcome` | First-run welcome app |

### ⚙️ Under the hood

- **Base:** CachyOS (Arch Linux with optimized kernel)
- **Kernel:** `linux-cachyos` with the BORE scheduler
- **Desktop:** KDE Plasma 6
- **Display server:** Wayland (X11 available)
- **Package manager:** `pacman` + the Genesi repository
- **Init:** systemd

---

## 📥 Download

> **Status:** active development. ISOs are produced by the
> [ISO pipeline](https://github.com/zFreshy/GenesiOS/actions/workflows/iso-pipeline.yml)
> on every qualifying push (as build artifacts) and attached to a GitHub Release
> on each `v*` tag.

- **Tagged releases:** [github.com/zFreshy/GenesiOS/releases](https://github.com/zFreshy/GenesiOS/releases)
- **Latest CI build:** open the most recent successful **Genesi ISO Pipeline** run and download the `genesi-os-iso` artifact.

### System requirements

| | Minimum | Recommended |
|---|---|---|
| **CPU** | x86_64 (64-bit) | Modern multi-core |
| **RAM** | 4 GB | 8 GB+ (16 GB+ for larger models) |
| **Storage** | 30 GB | 50 GB+ |
| **GPU** | Any (AI Mode works CPU-only) | NVIDIA Turing+ / modern AMD |

### Verify your download

```bash
sha256sum -c genesi-*.iso.sha256
```

---

## 🚀 Installation

**1. Write the ISO to a USB drive**

```bash
# Linux / macOS
sudo dd if=genesi-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```
On Windows use [Rufus](https://rufus.ie/) or [Ventoy](https://www.ventoy.net/).

**2. Boot from USB** — enter your BIOS/UEFI boot menu (often F2, F12, or Del) and select the drive.

**3. Install** — click **Install Genesi OS** on the live desktop and follow the Calamares installer. Reboot when done.

Full guide: [docs/installation.md](docs/installation.md).

---

## 🧠 How it works

Genesi OS is delivered through **two strictly separate CI pipelines** so that
fixing the live ISO can never break updates for installed users — and vice-versa.

### 1. Package / Update pipeline — `publish-packages.yml`
Builds all eight packages inside a `cachyos-v3` container, runs `repo-add`, and
commits the resulting pacman repository to `genesi-arch/repo/x86_64`. Installed
systems pull from it via plain `pacman -Syu` or the in-OS update notifier.

- `main` → **stable** channel
- `develop` → **testing** channel

### 2. ISO pipeline — `iso-pipeline.yml`
A two-stage build:

1. **validate-install** — dependency dry-run **plus a real `pacstrap`** into a
   throwaway root, reproducing the Calamares package set. A broken set fails here,
   *before* a ~30-minute build.
2. **build-iso** — runs only if validation passed; `mkarchiso` → `.iso`, uploaded
   as an artifact (and attached to a Release on `v*` tags).

It only fires on ISO inputs — docs-only commits don't trigger a build.

### Switching update channels

```bash
genesi-channel            # show current channel
sudo genesi-channel testing   # opt into testing
sudo genesi-channel stable    # back to stable
```

---

## 🎯 Quick start: test AI Mode

```bash
# Install Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# Pull a model and run it — AI Mode activates automatically
ollama pull llama3.2
ollama run llama3.2

# Watch AI Mode kick in
systemctl status genesi-aid
```

The AI Mode widget in your panel will light up and list the detected process and
the optimizations it applied.

---

## 🔧 Building from source

Genesi OS builds with archiso inside a CachyOS environment (the build scripts
refuse to run as root and use `sudo`).

```bash
cd genesi-arch
bash prepare-and-build.sh     # -> buildiso.sh -p desktop -> mkarchiso
# The ISO lands in genesi-arch/out/
```

Build just the packages locally:

```bash
cd genesi-arch/packages
./build-packages.sh           # builds each package + generates the repo db
```

More detail:
- [genesi-arch/README.md](genesi-arch/README.md) — build system overview
- [genesi-arch/packages/README.md](genesi-arch/packages/README.md) — package development
- [docs/ROADMAP.md](docs/ROADMAP.md) — full roadmap + infrastructure notes

---

## 🗺️ Roadmap

| Phase | Scope | Status |
|-------|-------|--------|
| **1** | Visual Identity | ✅ Complete |
| **2** | AI Mode (local AI optimizations) | 🟩 ~90% — core shipping |
| **3** | Own Packages & Repository | ✅ Operational — 8 packages, dual channels |
| **4** | IDE & Dev Tools | ⬜ Pending |
| **5** | Polish & Distribution | ⬜ Pending (incl. in-installer DE selector) |

See [docs/ROADMAP.md](docs/ROADMAP.md) for the detailed, per-feature breakdown.

---

## 📚 Documentation

- [Installation Guide](docs/installation.md)
- [FAQ](docs/faq.md)
- [Roadmap & Infrastructure](docs/ROADMAP.md)
- [AI Mode (build system docs)](genesi-arch/README.md)
- [Contributing Guide](CONTRIBUTING.md)
- [Changelog](CHANGELOG.md)

---

## 🤝 Contributing

Contributions are welcome:

- 🐛 **Report bugs** — [open an issue](https://github.com/zFreshy/GenesiOS/issues/new)
- 💡 **Suggest features** — [open an issue](https://github.com/zFreshy/GenesiOS/issues/new)
- 🔧 **Submit PRs** — see [CONTRIBUTING.md](CONTRIBUTING.md)
- ⭐ **Star the repo** — it genuinely helps

---

## 🙏 Credits

Genesi OS stands on the shoulders of:

- [**CachyOS**](https://cachyos.org/) — optimized Arch Linux base and packages
- [**Arch Linux**](https://archlinux.org/) — the foundation
- [**KDE Plasma**](https://kde.org/plasma-desktop/) — the desktop environment
- [**Ollama**](https://ollama.ai/) & [**llama.cpp**](https://github.com/ggerganov/llama.cpp) — local AI made practical

Special thanks to the CachyOS team and the Arch community.

---

## 📜 License

Genesi OS is licensed under the [GNU General Public License v3.0](LICENSE)
(GPL-3.0-or-later), the same license as CachyOS.

---

<div align="center">

**Built for people who run AI on their own machines.**

[⬆ Back to top](#genesi-os)

</div>
