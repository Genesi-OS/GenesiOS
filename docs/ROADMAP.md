# Genesi OS - Feature Roadmap

## Current Status
- ✅ Bootable ISO based on CachyOS
- ✅ KDE Plasma working
- ✅ Complete build system
- ✅ Phase 1 complete (visual identity)
- ✅ Phase 2 core complete (AI Mode - 90%)
- ⬜ Phase 3-5 pending

---

## Phase Order (Updated)

1. **Phase 1**: Visual Identity ✅ COMPLETE
2. **Phase 2**: AI Mode (Local AI Optimizations) ✅ 90% COMPLETE
3. **Phase 3**: Own Packages and Repository (Infrastructure) ⬜ NEXT
4. **Phase 4**: IDE and Dev Tools ⬜ PENDING
5. **Phase 5**: Polish and Distribution ⬜ PENDING

---

## PHASE 1: Visual Identity (High Priority)
> Give Genesi OS its own look and feel

- [x] Custom KDE Plasma theme (colors, icons, fonts)
- [x] Genesi OS wallpapers
- [x] Login screen (SDDM) with Genesi branding
- [x] Boot splash screen with Genesi logo (Plymouth theme created, activates if plymouth is installed)
- [x] "Genesi Welcome" app replacing "CachyOS Hello"
- [x] Genesi OS icons and logo (hicolor 48/64/256px)
- [x] All text and links pointing to Genesi (not CachyOS)
- [x] Custom color scheme (GenesiOS.colors) - dark green/teal palette
- [x] Konsole theme with Genesi colors
- [x] Desktop icons (This PC, Home, Settings, Trash, Terminal, Install)
- [x] Desktop widgets (clock, CPU monitor, RAM monitor, notes)
- [x] Custom GenesiOS logo Plasmoid widget in taskbar
- [x] Wallpaper applied automatically on boot
- [x] Hostname, os-release, lsb-release all branded "Genesi OS"
- [x] Boot message (MOTD) shows "Welcome to Genesi OS"
- [x] GRUB/Syslinux/EFI boot menus show "Genesi OS"
- [x] Calamares installer rebranded to "Instalador Genesi OS"
- [x] KWin blur and translucency enabled (glassmorphism)
- [x] Floating panel with app icons
- [ ] Rounded window corners (needs Klassy or kwin-effect-rounded-corners - Phase 5)

---

## PHASE 2: AI Mode - Local AI Optimizations (Main Differentiator)
> Make Genesi OS run local AI better than any other OS

### 2.1 "Genesi AI Optimizer" Daemon (genesi-aid)
A systemd service that monitors AI processes and optimizes the system automatically.

- [x] Detect when Ollama/llama.cpp/vLLM/LocalAI is running
- [x] Automatically enable optimizations when AI is in use
- [x] Disable optimizations when AI stops (return to normal)
- [x] Plasma widget showing status (AI Mode ON/OFF, detected processes)

### 2.2 VRAM/RAM Management
- [x] Free VRAM from non-essential processes when AI runs (reduce compositor visual effects)
- [x] Set `vm.swappiness=10` when AI Mode is active
- [ ] Automatically detect available VRAM (requires GPU detection logic)
- [ ] Configure optimal GPU/CPU split for the model (partial offloading)
- [ ] Use `mlock` to keep model weights in RAM without swap

### 2.3 Huge Pages for Models
- [x] Configure Transparent Huge Pages (THP) of 2MB for inference
- [x] Pre-allocate huge pages when AI Mode is activated
- [x] Optimized sysctl configs: `vm.nr_hugepages`, `vm.hugetlb_shm_group`

### 2.4 CPU Governor and Scheduler
- [x] Switch CPU governor to `performance` when inference is running
- [x] Use CachyOS BORE scheduler with high priority for AI processes (nice -5)
- [x] CPU pinning: pin inference threads to performance cores (basic heuristic)
- [ ] Disable power saving on cores used by AI (requires deeper kernel integration)

### 2.5 Optimized I/O for Models
- [x] Optimize kernel readahead for large GGUF files (sysctl configs)
- [ ] Pre-cache frequently used models in RAM with `vmtouch`
- [ ] Configure I/O scheduler to prioritize large sequential reads

### 2.6 "AI Mode" Widget in Plasma
- [x] Taskbar widget showing AI Mode status
- [x] Display detected AI processes with PIDs
- [x] Show optimizations applied (CPU governor, swappiness, huge pages, priority)
- [x] Auto-refresh every 5 seconds
- [x] Pulsing animation when AI Mode is active
- [x] Auto-add widget to panel on first boot
- [x] Manual ON/OFF toggle (force AI Mode)
- [ ] Display VRAM usage and tokens/second metrics (requires GPU integration)

### 2.7 Integrated MemPalace
MemPalace (https://github.com/MemPalace/mempalace) is a local-first AI memory system.
It stores conversations and context locally with semantic search, without sending anything to the cloud.

Integration with Genesi OS:
- [ ] Pre-install MemPalace on the system
- [ ] Configure as a background service
- [ ] Local AIs (Ollama, etc.) can use MemPalace for persistent memory
- [ ] Developer project context is automatically indexed
- [ ] Semantic search: "why did we switch to GraphQL?" returns the exact conversation
- [ ] Integrate with IDE (VS Code/Zed) via MemPalace MCP tools
- [ ] Plasma widget showing MemPalace status (indexed memories, last sync)

Benefit: Local AI on Genesi OS has long-term memory. The dev talks to the AI,
closes everything, and next time the AI remembers the context. No other OS offers this natively.

---

## PHASE 3: Own Packages and Repository (Infrastructure)
> Create Genesi OS package repository and custom packages

Currently, Genesi OS uses CachyOS packages (`cachyos-calamares-next`, `cachyos-kde-settings`,
`cachyos-settings`, etc.) and rebrands them at build time via `customize_airootfs.sh`.
This works but has limitations:

- The `cachyos-hello` app has hardcoded text in the binary (can't rebrand without forking)
- Calamares branding is patched via sed after package install (fragile, may break on updates)
- Some CachyOS text may appear briefly or in edge cases
- **Branding doesn't persist after installing to disk** (reverts to CachyOS)

**Solution**: Create a Genesi OS package repository with forked/custom packages:
- [ ] `genesi-welcome` - Custom welcome app replacing `cachyos-hello`
- [ ] `genesi-calamares` - Forked Calamares with native Genesi OS branding
- [ ] `genesi-kde-settings` - KDE configs with Genesi OS theme built-in
- [ ] `genesi-settings` - System settings (hostname, os-release, etc.)
- [ ] `genesi-ai-mode` - AI Mode daemon, service, and widget
- [ ] `klassy` - Compile from AUR for configurable window corner radius (12px+)
- [ ] `kwin-effect-rounded-corners` - Compile from AUR for rounded corners on all windows
- [ ] Custom taskbar icon selection style - rounded pill-shaped highlight instead of ugly square, smooth hover animation with Genesi green accent
- [ ] Centered taskbar icons (Windows 11 style) - icons grouped in the center of the panel with logo on the left and systray on the right
- [ ] Custom app launcher (Kickoff replacement) - glassmorphic popup matching the mockup design with: search bar at top, pinned apps grid with rounded icons, recent files section, user profile at bottom, "Ver mais" links, all with Genesi green accent colors and blur background
- [ ] Own package repository hosted on GitHub/server
- [ ] Remove dependency on `customize_airootfs.sh` for branding
- [ ] Branding persists after installation to disk

---

## PHASE 4: IDE and Dev Tools (Secondary Differentiator)
> Developer-focused tools and integrations

### 3.1 Genesi IDE (based on VS Code or Zed)
- [ ] Fork of VS Code or Zed with Genesi branding
- [ ] Pre-installed Genesi theme
- [ ] Pre-configured extensions (Git, Docker, AI, popular languages)
- [ ] Native integration with local AI daemon
- [ ] Integration with MemPalace (project context)
- [ ] Desktop and menu shortcut

### 3.2 Container Widget in Plasma
- [ ] Taskbar widget showing running Docker containers
- [ ] Start/Stop/Restart with one click
- [ ] View container logs
- [ ] View mapped ports
- [ ] CPU/RAM usage status per container

### 3.3 Project Sandboxes (Isolated Workspaces)
- [ ] Based on Distrobox/Toolbox
- [ ] GUI to create/manage workspaces
- [ ] Templates: "Java + Spring Boot", "React + Vite", "Python + FastAPI", etc.
- [ ] Each workspace has its own isolated dependencies
- [ ] Integration with Genesi IDE

### 3.4 Network Inspection
- [ ] mitmproxy pre-installed and configured
- [ ] Simple GUI to intercept HTTP/HTTPS requests
- [ ] Quick shortcut to enable/disable debug proxy
- [ ] Integration with container widget (view traffic per container)

### 3.5 Database Explorer
- [ ] Beekeeper Studio or DBeaver pre-installed
- [ ] Dolphin (file manager) plugin to connect to databases
- [ ] Support for PostgreSQL, MySQL, SQLite, MongoDB
- [ ] Quick table and data visualization

---

## PHASE 5: Polish and Distribution
> Final polish and public release

- [ ] Custom Calamares installer with Genesi branding (images, slideshow, icon)
- [ ] Official Genesi OS website
- [ ] Complete documentation
- [ ] Download page with ISOs
- [ ] Community (Discord/Forum)
- [ ] Automatic updates (own repository)

### 5.1 Desktop Environment Selector in Installer (Calamares)
> Like CachyOS's installer — let the user pick their DE at install time

- [ ] Add a "Choose your desktop" step to Calamares (similar to CachyOS's
      `packagechooser` module that lists DEs with screenshots + descriptions)
- [ ] **Option 1: KDE Plasma 6 (default)** — current Genesi setup: Klassy
      14px rounded windows, Darkly glassmorphism, Ant-Dark popups, Kickoff
      menu, all the existing visual identity
- [ ] **Option 2: Hyprland + caelestia-shell** — Wayland tiling compositor
      with the [caelestia-dots/shell](https://github.com/caelestia-dots/shell)
      design (Quickshell QML widgets, no waybar, modern AI-era aesthetic).
      Needs to pull `hyprland`, `caelestia-shell` (AUR), `caelestia-cli`,
      `quickshell-git`, `ddcutil`, `brightnessctl` into a netinstall group
      that only installs when this option is picked
- [ ] (Future) Additional options: GNOME, COSMIC, Sway, etc.
- [ ] SDDM session entries auto-registered for whatever the user picked
      (Plasma X11 / Plasma Wayland / Hyprland / etc.)
- [ ] Wallpapers + branding consistent across all DE choices (Genesi logo,
      green/teal palette, Tela-circle-green-dark icons where applicable)
- [ ] genesi-x11-detect.sh logic extended to handle the chosen DE — e.g.
      Hyprland needs different SDDM session forcing than Plasma
- [ ] Update `genesi-welcome` to detect the running DE and adjust its
      "open settings" buttons to the correct app per-DE
- [ ] Doc page explaining the DE choice + when each one shines (Plasma for
      KDE-native experience and ricing, Hyprland+caelestia for tiling +
      modern aesthetics + lower RAM footprint)

---

## PHASE 3: IDE and Dev Tools (Secondary Differentiator)

### 3.1 Genesi IDE (based on VS Code or Zed)
- [ ] Fork of VS Code or Zed with Genesi branding
- [ ] Pre-installed Genesi theme
- [ ] Pre-configured extensions (Git, Docker, AI, popular languages)
- [ ] Native integration with local AI daemon
- [ ] Integration with MemPalace (project context)
- [ ] Desktop and menu shortcut

### 3.2 Container Widget in Plasma
- [ ] Taskbar widget showing running Docker containers
- [ ] Start/Stop/Restart with one click
- [ ] View container logs
- [ ] View mapped ports
- [ ] CPU/RAM usage status per container

### 3.3 Project Sandboxes (Isolated Workspaces)
- [ ] Based on Distrobox/Toolbox
- [ ] GUI to create/manage workspaces
- [ ] Templates: "Java + Spring Boot", "React + Vite", "Python + FastAPI", etc.
- [ ] Each workspace has its own isolated dependencies
- [ ] Integration with Genesi IDE

### 3.4 Network Inspection
- [ ] mitmproxy pre-installed and configured
- [ ] Simple GUI to intercept HTTP/HTTPS requests
- [ ] Quick shortcut to enable/disable debug proxy
- [ ] Integration with container widget (view traffic per container)

### 3.5 Database Explorer
- [ ] Beekeeper Studio or DBeaver pre-installed
- [ ] Dolphin (file manager) plugin to connect to databases
- [ ] Support for PostgreSQL, MySQL, SQLite, MongoDB
- [ ] Quick table and data visualization

---

## How to Download and Test Local AI on Genesi OS

### Method 1: Ollama (easiest)
```bash
# Install Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# Download a model
ollama pull llama3.2        # 2GB, lightweight
ollama pull codellama       # 4GB, good for code
ollama pull deepseek-coder  # 1.3GB, lightweight and good for code

# Run
ollama run llama3.2

# Use via API (to integrate with apps)
curl http://localhost:11434/api/generate -d '{"model":"llama3.2","prompt":"Hello"}'
```

### Method 2: llama.cpp (more control)
```bash
# Install
sudo pacman -S llama.cpp

# Download GGUF model from HuggingFace
wget https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf

# Run
llama-cli -m llama-2-7b-chat.Q4_K_M.gguf -p "Hello, how are you?"

# Run as server (OpenAI-compatible API)
llama-server -m llama-2-7b-chat.Q4_K_M.gguf --port 8080
```

### Method 3: LocalAI (OpenAI-compatible API)
```bash
# Via Docker
docker run -p 8080:8080 localai/localai
```

### Performance Testing (for documentation)
```bash
# With Ollama - measure tokens per second
ollama run llama3.2 "Explain quantum computing" --verbose

# With llama.cpp - benchmark
llama-bench -m model.gguf

# Monitor resource usage during inference
# Terminal 1: run AI
# Terminal 2:
watch -n 1 nvidia-smi          # GPU (if NVIDIA)
htop                            # CPU and RAM
```

### Comparison for Documentation
Run the same prompt on Genesi OS (with AI Mode ON) and on a standard Ubuntu/Fedora.
Measure:
- Tokens per second
- RAM usage
- Model loading time
- VRAM usage

---

## About MemPalace

MemPalace is a local-first AI memory system that:
- Stores conversations as verbatim text (no summarizing/altering)
- Organizes into "wings" (projects), "rooms" (topics), "drawers" (content)
- Local semantic search (96.6% recall without LLM, 98.4% with heuristics)
- Everything local, nothing leaves the machine
- 29 MCP tools to integrate with any AI

How it helps Genesi OS:
1. **Persistent memory for local AI**: Dev talks to Ollama, closes, next time the AI remembers
2. **Project context**: MemPalace indexes project code and the AI understands the context
3. **Zero cloud**: Everything runs locally, aligned with Genesi OS philosophy
4. **IDE integration**: Via MCP tools, the IDE can search context in MemPalace

License: MIT (compatible with Genesi OS GPL-3.0)
