# Genesi OS — Feature Roadmap

> Genesi OS is a CachyOS-based (Arch under the hood) Linux distribution built
> around one idea: **the system should optimize itself for local AI** while
> staying beautiful, fast, and effortless to maintain.

## Current Status

| Area | Status |
|------|--------|
| Bootable ISO based on CachyOS | ✅ Complete |
| KDE Plasma 6 desktop | ✅ Complete |
| Reproducible build system (archiso + Calamares) | ✅ Complete |
| **Phase 1 — Visual Identity** | ✅ Complete |
| **Phase 2 — AI Mode (local AI optimizations)** | 🟩 ~90% (core shipping) |
| **Phase 3 — Own Packages & Repository** | ✅ Operational (8 packages shipping) |
| **Phase 4 — IDE & Dev Tools** | ⬜ Pending |
| **Phase 5 — Polish & Distribution** | ⬜ Pending |

### Two production CI pipelines

Genesi OS ships through **two independent GitHub Actions pipelines**:

1. **Package / Update pipeline** (`.github/workflows/publish-packages.yml`) —
   builds the eight Genesi packages inside a `cachyos-v3` container, runs
   `repo-add`, and commits the resulting pacman repository to
   `genesi-arch/repo/x86_64`. Installed systems pull from this repo, so a
   normal `pacman -Syu` (or the in-OS update notifier) delivers updates in near
   real time. `main` = **stable** channel, `develop` = **testing** channel.
2. **ISO pipeline** (`.github/workflows/iso-pipeline.yml`) — a two-stage build
   that first **validates the install** (dependency dry-run + a real `pacstrap`
   into a throwaway root) and only then runs `mkarchiso` to produce a fresh
   `.iso`. Artifacts are uploaded per run; pushing a `v*` tag cuts a GitHub
   Release. It only fires on ISO inputs (docs-only commits are skipped).

See [Build & Release Infrastructure](#build--release-infrastructure) for details.

---

## Phase Order

1. **Phase 1** — Visual Identity ✅ **Complete**
2. **Phase 2** — AI Mode (local AI optimizations) 🟩 **~90%**
3. **Phase 3** — Own Packages & Repository (infrastructure) ✅ **Operational**
4. **Phase 4** — IDE & Dev Tools ⬜ Pending
5. **Phase 5** — Polish & Distribution ⬜ Pending

---

## PHASE 1: Visual Identity ✅ COMPLETE
> Give Genesi OS its own look and feel.

- [x] Custom KDE Plasma theme (colors, icons, fonts)
- [x] Genesi OS wallpapers
- [x] Login screen (SDDM) with Genesi branding
- [x] Boot splash (Plymouth theme — activates when Plymouth is installed)
- [x] "Genesi Welcome" app replacing "CachyOS Hello"
- [x] Genesi OS icons and logo (hicolor 48/64/256px)
- [x] All text and links pointing to Genesi (not CachyOS)
- [x] Custom color scheme (`GenesiOS.colors`) — dark green/teal palette
- [x] Konsole theme with Genesi colors
- [x] Desktop icons (This PC, Home, Settings, Trash, Terminal, Install)
- [x] Desktop widgets (clock, CPU monitor, RAM monitor, notes)
- [x] Custom GenesiOS logo plasmoid in the taskbar
- [x] Wallpaper applied automatically on boot
- [x] Hostname, `os-release`, `lsb-release` all branded "Genesi OS"
- [x] Boot message (MOTD) shows "Welcome to Genesi OS"
- [x] GRUB / Syslinux / EFI boot menus show "Genesi OS"
- [x] Calamares installer rebranded to "Genesi OS Installer"
- [x] KWin blur and translucency (glassmorphism)
- [x] Floating panel with app icons
- [x] **Rounded window corners** — 14px via Klassy (shipped in `genesi-settings`)

---

## PHASE 2: AI Mode — Local AI Optimizations 🟩 ~90%
> Make Genesi OS run local AI better than any other desktop OS.

### 2.1 "Genesi AI Optimizer" daemon (`genesi-aid`)
A systemd service that monitors AI processes and tunes the system automatically.

- [x] Detect when Ollama / llama.cpp / vLLM / LocalAI is running
- [x] Automatically enable optimizations when AI is in use
- [x] Disable optimizations when AI stops (return to normal)
- [x] Plasma widget showing status (AI Mode ON/OFF, detected processes)

### 2.2 VRAM/RAM management
- [x] Free VRAM from non-essential processes when AI runs (reduce compositor effects)
- [x] Set `vm.swappiness=10` when AI Mode is active
- [ ] Automatically detect available VRAM (requires GPU detection logic)
- [ ] Configure optimal GPU/CPU split for the model (partial offloading)
- [ ] Use `mlock` to keep model weights in RAM without swap

### 2.3 Huge pages for models
- [x] Configure Transparent Huge Pages (THP) of 2MB for inference
- [x] Pre-allocate huge pages when AI Mode is activated
- [x] Optimized sysctl configs: `vm.nr_hugepages`, `vm.hugetlb_shm_group`

### 2.4 CPU governor and scheduler
- [x] Switch CPU governor to `performance` when inference is running
- [x] Use CachyOS BORE scheduler with high priority for AI processes (`nice -5`)
- [x] CPU pinning: pin inference threads to performance cores (basic heuristic)
- [ ] Disable power saving on cores used by AI (requires deeper kernel integration)

### 2.5 Optimized I/O for models
- [x] Optimize kernel readahead for large GGUF files (sysctl configs)
- [ ] Pre-cache frequently used models in RAM with `vmtouch`
- [ ] Configure I/O scheduler to prioritize large sequential reads

### 2.6 "AI Mode" widget in Plasma
- [x] Taskbar widget showing AI Mode status
- [x] Display detected AI processes with PIDs
- [x] Show applied optimizations (governor, swappiness, huge pages, priority)
- [x] Auto-refresh every 5 seconds
- [x] Pulsing animation when AI Mode is active
- [x] Auto-add widget to panel on first boot
- [x] Manual ON/OFF toggle (force AI Mode)
- [ ] Display VRAM usage and tokens/second metrics (requires GPU integration)

### 2.7 Integrated MemPalace
[MemPalace](https://github.com/MemPalace/mempalace) is a local-first AI memory
system — it stores conversations and context locally with semantic search,
nothing leaves the machine.

- [ ] Pre-install MemPalace on the system
- [ ] Configure as a background service
- [ ] Local AIs (Ollama, etc.) can use MemPalace for persistent memory
- [ ] Developer project context is automatically indexed
- [ ] Semantic search: "why did we switch to GraphQL?" returns the exact conversation
- [ ] Integrate with the IDE (VS Code/Zed) via MemPalace MCP tools
- [ ] Plasma widget showing MemPalace status (indexed memories, last sync)

Benefit: local AI on Genesi OS gains long-term memory. The dev talks to the AI,
closes everything, and next time the AI still remembers the context.

---

## PHASE 3: Own Packages & Repository ✅ OPERATIONAL
> Native Genesi packages and a self-hosted pacman repository, so branding and
> features persist **after installation to disk** — not just on the live ISO.

Early Genesi OS rebranded CachyOS packages at build time via
`customize_airootfs.sh`. That worked on the live medium but reverted to CachyOS
once installed. Phase 3 replaces that with **real, conflicting/`provides`
packages** built and published by CI.

### Shipping packages (built by `publish-packages.yml`)
- [x] `genesi-settings` — system branding (`os-release`, hostname, MOTD, sysctl)
- [x] `genesi-kde-settings` — KDE Plasma theme, wallpapers, Klassy 14px corners,
      Darkly glassmorphism, Kickoff sizing, panel layout
- [x] `genesi-ai-mode` — AI Mode daemon (`genesi-aid`), systemd service, plasmoid
- [x] `genesi-update` — interactive update notifier + systray applet
      (fork of CachyOS `cachy-update`)
- [x] `genesi-channel` — switch between **stable** and **testing** update channels
- [x] `genesi-calamares` — Calamares installer build
- [x] `genesi-calamares-branding` — native installer branding (logo, slideshow, colors)
- [x] `genesi-welcome` — first-run welcome app replacing `cachyos-hello`

### Repository & delivery
- [x] In-repo pacman registry at `genesi-arch/repo/x86_64`, generated with `repo-add`
- [x] Stable/testing channels by branch (`main` / `develop`)
- [x] Branding and features **persist after install** (packages, not sed patches)
- [x] Installed systems update via plain `pacman -Syu` or the in-OS notifier
- [x] Reproducible CI build inside a `cachyos-v3` container with CachyOS repos

### Desktop polish (in progress)
- [x] Klassy compiled/configured for rounded window corners (14px)
- [ ] Custom taskbar icon selection style — rounded pill highlight + hover animation
- [ ] Centered taskbar icons (Windows 11 style) — logo left, systray right
- [ ] Custom app launcher (Kickoff replacement) — glassmorphic popup with search,
      pinned grid, recent files, user profile, Genesi green accents

---

## PHASE 4: IDE & Dev Tools ⬜ PENDING
> Developer-focused tools and integrations (secondary differentiator).

### 4.1 Genesi IDE (based on VS Code or Zed)
- [ ] Fork of VS Code or Zed with Genesi branding
- [ ] Pre-installed Genesi theme
- [ ] Pre-configured extensions (Git, Docker, AI, popular languages)
- [ ] Native integration with the local AI daemon
- [ ] Integration with MemPalace (project context)
- [ ] Desktop and menu shortcut

### 4.2 Container widget in Plasma
- [ ] Taskbar widget showing running Docker containers
- [ ] Start/Stop/Restart with one click
- [ ] View container logs and mapped ports
- [ ] CPU/RAM usage per container

### 4.3 Project sandboxes (isolated workspaces)
- [ ] Based on Distrobox/Toolbox
- [ ] GUI to create/manage workspaces
- [ ] Templates: "Java + Spring Boot", "React + Vite", "Python + FastAPI", etc.
- [ ] Each workspace has its own isolated dependencies
- [ ] Integration with Genesi IDE

### 4.4 Network inspection
- [ ] mitmproxy pre-installed and configured
- [ ] Simple GUI to intercept HTTP/HTTPS requests
- [ ] Quick shortcut to enable/disable a debug proxy
- [ ] Integration with the container widget (per-container traffic)

### 4.5 Database explorer
- [ ] Beekeeper Studio or DBeaver pre-installed
- [ ] Dolphin plugin to connect to databases
- [ ] Support for PostgreSQL, MySQL, SQLite, MongoDB
- [ ] Quick table and data visualization

---

## PHASE 5: Polish & Distribution ⬜ PENDING
> Final polish and public release.

- [ ] Custom Calamares slideshow & imagery (branding package already in place)
- [ ] Official Genesi OS website
- [ ] Complete end-user documentation
- [ ] Download page with ISOs
- [ ] Community (Discord/Forum)
- [x] Automatic updates via the self-hosted repository *(delivered in Phase 3)*

### 5.1 Desktop Environment selector in the installer (Calamares)
> Like CachyOS's installer — let the user pick their DE at install time.

- [ ] Add a "Choose your desktop" step to Calamares (similar to the CachyOS
      `packagechooser` module with screenshots + descriptions)
- [ ] **Option 1: KDE Plasma 6 (default)** — current Genesi setup: Klassy 14px
      rounded windows, Darkly glassmorphism, Ant-Dark popups, Kickoff menu
- [ ] **Option 2: Hyprland + caelestia-shell** — Wayland tiling compositor with
      the [caelestia-dots/shell](https://github.com/caelestia-dots/shell) design
      (Quickshell QML widgets, no waybar). Pulls `hyprland`, `caelestia-shell`
      (AUR), `caelestia-cli`, `quickshell-git`, `ddcutil`, `brightnessctl` into a
      netinstall group that installs only when this option is picked
- [ ] (Future) Additional options: GNOME, COSMIC, Sway, etc.
- [ ] SDDM session entries auto-registered for whatever the user picked
- [ ] Wallpapers + branding consistent across all DE choices
- [ ] `genesi-x11-detect.sh` extended to handle the chosen DE (Hyprland needs
      different SDDM session forcing than Plasma)
- [ ] `genesi-welcome` detects the running DE and adjusts its buttons per-DE
- [ ] Doc page explaining the DE choice and when each one shines

---

## Build & Release Infrastructure

Genesi OS keeps **two strictly separate** pipelines so that fixing the live ISO
can never break updates for installed users, and vice-versa.

### 1. Package / Update pipeline — `publish-packages.yml`
- **Trigger:** pushes to `main`/`develop` touching `genesi-arch/packages/**` or
  any package submodule pointer (each package sources `HEAD` of its submodule).
- **Runner:** `cachyos/cachyos-v3` container (CachyOS repos + keyring trusted),
  required because several packages depend on CachyOS-only packages.
- **Flow:** collect all PKGBUILD deps → pre-install them → `makepkg` each package
  as an unprivileged `builder` user → `repo-add` → commit the repo to
  `genesi-arch/repo/x86_64` on the same branch.
- **Result:** installed systems receive updates via `pacman -Syu` / the in-OS
  notifier. `main` → stable, `develop` → testing (selectable with `genesi-channel`).

### 2. ISO pipeline — `iso-pipeline.yml`
- **Trigger:** pushes to `main` touching ISO inputs (`genesi-arch/**`, the
  Calamares config submodule, the workflow) and `v*` tags. Docs-only commits are
  skipped.
- **Job 1 — validate-install:** dependency dry-run + a real `pacstrap` into a
  throwaway root, reproducing the Calamares package set. A broken package set
  fails here, before any 30-minute build.
- **Job 2 — build-iso:** runs only if Job 1 passes; `mkarchiso` → `.iso`,
  uploaded as an artifact (and attached to a GitHub Release on `v*` tags).

### Build/install internals worth knowing
- **ISO build:** `genesi-arch/prepare-and-build.sh` → `buildiso.sh -p desktop` →
  `mkarchiso`. The scripts refuse to run as root, so CI uses a passwordless-sudo
  `builder` user.
- **Calamares config deploy:** `genesi-calamares-config-full/` (submodule) reaches
  the ISO via `customize_airootfs.sh` at build time and is re-copied at install
  launch by `calamares-online.sh`.
- **NVIDIA gotcha:** the netinstall "NVIDIA Drivers" group must use
  `nvidia-open-dkms` (Turing+), **not** `nvidia-dkms` — the only `nvidia-dkms`
  provider hard-pins a `nvidia-utils` version that is unsatisfiable whenever
  CachyOS lags Arch.

---

## Appendix: Running Local AI on Genesi OS

### Method 1 — Ollama (easiest)
```bash
curl -fsSL https://ollama.ai/install.sh | sh   # install
ollama pull llama3.2                            # 2GB, lightweight
ollama pull deepseek-coder                      # 1.3GB, good for code
ollama run llama3.2                             # run (AI Mode activates automatically)
curl http://localhost:11434/api/generate -d '{"model":"llama3.2","prompt":"Hello"}'
```

### Method 2 — llama.cpp (more control)
```bash
sudo pacman -S llama.cpp
wget https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf
llama-cli   -m llama-2-7b-chat.Q4_K_M.gguf -p "Hello, how are you?"
llama-server -m llama-2-7b-chat.Q4_K_M.gguf --port 8080   # OpenAI-compatible API
```

### Method 3 — LocalAI (OpenAI-compatible API)
```bash
docker run -p 8080:8080 localai/localai
```

### Benchmarking (for documentation)
```bash
ollama run llama3.2 "Explain quantum computing" --verbose   # tokens/sec
llama-bench -m model.gguf                                    # llama.cpp benchmark
watch -n 1 nvidia-smi   # GPU (if NVIDIA)
htop                    # CPU and RAM
```

Run the same prompt on Genesi OS (AI Mode ON) vs. a stock Ubuntu/Fedora and
compare tokens/second, RAM usage, model load time, and VRAM usage.

---

## About MemPalace

[MemPalace](https://github.com/MemPalace/mempalace) is a local-first AI memory
system that:
- Stores conversations verbatim (no summarizing/altering)
- Organizes into "wings" (projects), "rooms" (topics), "drawers" (content)
- Provides local semantic search (96.6% recall without an LLM, 98.4% with heuristics)
- Keeps everything on-device — nothing leaves the machine
- Exposes 29 MCP tools to integrate with any AI

Why it fits Genesi OS: persistent memory for local AI, automatic project-context
indexing, zero cloud, and IDE integration via MCP. License: MIT (compatible with
Genesi OS's GPL-3.0).
