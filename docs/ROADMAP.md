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
| **Phase 4 — IDE & Dev Tools** (Genesi Code, fork of Warp; Genesi Hermes, fork of Hermes Desktop) | 🟦 In progress — Genesi Code shipping (local AI agent + LSP); Hermes pending |
| **Phase 5 — Polish & Distribution** | ⬜ Pending |
| **Phase 6 — Welcome & Control Center** (app installer + tweaks) | ⬜ Pending |

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
4. **Phase 4** — IDE & Dev Tools (Genesi Code, fork of Warp; Genesi Hermes, fork of Hermes Desktop) 🟦 **In progress** (Genesi Code shipping)
5. **Phase 5** — Polish & Distribution ⬜ Pending
6. **Phase 6** — Genesi Welcome & Control Center ⬜ Pending

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

> **★ Core design principle — weak hardware is a first-class target.**
> Every AI Mode / Turbo feature must **help low-end machines too**, even if with
> smaller models. The litmus test: a **4 GB-RAM laptop with a dedicated GPU**
> should run models its system RAM alone never could — by living **100% in
> VRAM** — and be **faster with Turbo than without it**. Concretely this means:
> nothing may assume lots of RAM; every optimizer is **RAM/VRAM-gated** and
> degrades gracefully (it does nothing rather than OOM); the advisor picks the
> **biggest model that fits the VRAM** (small quants by default on 2–4 GB); and
> heavy knobs that need spare memory are skipped, not forced, on tight boxes.
> "Runs great on a potato" is a feature, not an afterthought.

### 2.1 "Genesi AI Optimizer" daemon (`genesi-aid`)
A systemd service that monitors AI processes and tunes the system automatically.

- [x] Detect when Ollama / llama.cpp / vLLM / LocalAI is running
- [x] Automatically enable optimizations when AI is in use
- [x] Disable optimizations when AI stops (**fully reversible** — captures and
      restores every knob; survives a daemon restart via `/run` snapshot)
- [x] Reliable user↔daemon IPC over `/run/genesi-ai-mode` (works under the
      service's `PrivateTmp` hardening)
- [x] `genesi-ai-mode` CLI — `on` / `off` / `auto` / `toggle` / `status`
- [x] Plasma widget showing status (AI Mode ON/OFF, detected processes)

### 2.2 VRAM/RAM management
- [x] Set `vm.swappiness=10` when AI Mode is active (restored on exit)
- [x] Detect available VRAM per GPU — NVIDIA `nvidia-smi`, AMD/Intel/NVIDIA DRM
      sysfs, plus a vendor-agnostic Vulkan probe (`llama-server --list-devices`)
      that works under nouveau/NVK where `nvidia-smi` can't talk to the driver
- [x] Configure optimal GPU/CPU split for the model (partial offloading)
      _(genesi-ai-turbo: `-ngl 999` when the model fits VRAM, `-ngl auto` to fit
      as many layers as the VRAM holds when it doesn't — never a blind offload
      that OOMs a small card; see 2.8.11 Tier 0)_
- [x] Use `mlock`/`vmtouch` to keep model weights in RAM without swap
      _(opt-in `GENESI_TURBO_MLOCK=1` → `llama-server --mlock`; default off, as
      it's risky on low-RAM boxes and the RAM-backed live ISO)_
- [x] Free VRAM by trimming compositor effects **from the user session** (the
      old root-side `qdbus` call could never reach the user's KWin — removed)
      _(done: `genesi-ai-kwin-helper`, a user-session autostart that unloads
      blur/contrast while AI Mode is on and reloads exactly those on off)_

### 2.3 Huge pages for models
- [x] Toggle Transparent Huge Pages to `always` while AI runs (restored on exit)
- [x] Slim sysctl (`vm.max_map_count`, `vm.vfs_cache_pressure`) — **dropped the
      permanent `vm.nr_hugepages=512`** that reserved ~1 GB even with no AI running
- [x] Allocate explicit huge pages **on demand** at enable, free them at disable
      _(done as an opt-in tradeoff — `/etc/genesi-ai-mode/advanced.conf`
      `hugepages = N`, reserved on enable / freed on disable, refused if it would
      eat >50% of free RAM; see 2.8.9)_

### 2.4 CPU governor and scheduler
- [x] Switch CPU governor to `performance` when inference is running (restored)
- [x] High priority for AI processes (`nice -5`, idempotent — also catches
      processes that spawn after AI Mode is already on)
- [x] **Removed** the naive "pin to first half of cores" heuristic — it halved
      CPU-inference throughput. Replaced by hybrid-core awareness in 2.8
- [x] amd-pstate / EPP → `performance` while AI Mode is on (AC/forced), restored

### 2.5 Optimized I/O for models
- [x] Optimize kernel readahead for large GGUF files (sysctl)
- [x] Pre-cache the active model in RAM (page cache via `posix_fadvise`, see 2.8.3)
- [x] I/O scheduler tuned for large sequential reads on the model NVMe (see 2.8.7)

### 2.6 "AI Mode" widget in Plasma
- [x] Taskbar widget showing AI Mode status
- [x] Display detected AI processes with PIDs
- [x] Show applied optimizations (governor, swappiness, huge pages, priority)
- [x] Auto-refresh every 5 seconds + pulsing animation when active
- [x] Manual ON/OFF toggle (force AI Mode) — wired to the `genesi-ai-mode` CLI
- [x] Live VRAM / GPU / tokens-per-second metrics (see 2.8)
- [x] Rewrite for Plasma 6 API (PlasmoidItem / Kirigami / plasma5support)
- [x] **Smart workload auto-detection** — AI Mode no longer latches ON forever
      because `ollama serve` is always running. `genesi-aid` now classifies the
      live workload as **active** (GPU/CPU crunching, or a one-shot CLI) → full
      `max`; **warm** (a model is resident via ollama keep_alive / a Turbo
      server, but idle) → eases to `balanced` (governor stays, GPU clock/power
      locks released); **idle** (server listening, nothing loaded) → powers
      down. Hysteresis avoids flapping between chat turns: instant promote on
      activity, a 30s hold before `max`→`balanced`, and an `ai_idle_timeout`
      grace (advanced.conf, default 90s) before standing down. New `activity`
      field in `state.json`; the Monitor shows generating / warm·idle /
      standing-by. Pure detection change — the reversible-restore machinery is
      untouched.

### 2.7 Integrated MemPalace
[MemPalace](https://github.com/MemPalace/mempalace) is a local-first AI memory
system — it stores conversations and context locally with semantic search,
nothing leaves the machine. License MIT (compatible with Genesi OS's GPL-3.0).
**Official sources only**: the GitHub repo, the PyPI package `mempalace`, and
mempalaceofficial.com — other domains (`.tech`, `.net`, …) are impostors that
may ship malware, so Genesi provisions strictly from the PyPI package.

MemPalace is fundamentally a **per-user** tool (the "palace" lives in `$HOME`),
its MCP server runs **on demand over stdio** (MCP clients spawn it), and its
"background service" role is really a **periodic indexer**. The Genesi
integration is shaped around those three facts.

- [x] **Package `genesi-mempalace`** — ships the user systemd service, the
      `genesi-mempalace` launcher (wraps mine/sweep/status/mcp), config, and the
      Monitor integration. The `mempalace` CLI itself is provisioned per-user
      into an isolated `uv tool` env (upstream's recommended install), guided
      from the Monitor — same pattern as the Turbo backend installer.
- [x] **Configure as a background service** — a per-user `genesi-mempalace.service`
      runs `genesi-mempalace watch`: a low-priority loop that periodically mines
      configured project paths + sweeps the local AI transcript dirs, then writes
      `mempalace-state.json` for the Monitor. Idempotent and resume-safe.
- [x] **Local AIs (Ollama, etc.) can use MemPalace for persistent memory** — via
      the prompt-cache bridge (2.7.1) and the MCP server for MCP-aware clients.
- [x] Developer project context is automatically indexed (the watch loop)
- [ ] Semantic search: "why did we switch to GraphQL?" returns the exact conversation
- [ ] Integrate with the IDE (VS Code/Zed) via MemPalace MCP tools (mcp.json
      pointing at `genesi-mempalace mcp`)
- [ ] Plasma widget / Monitor card showing MemPalace status (indexed memories,
      last sync) — `mempalace-state.json` is published; card pending

Benefit: local AI on Genesi OS gains long-term memory. The dev talks to the AI,
closes everything, and next time the AI still remembers the context.

#### 2.7.1 Prompt caching with MemPalace (memory + KV reuse) 🧠⚡
> Make recalled memory **also** kill the prompt cold-start, by combining
> MemPalace's text recall with the KV-cache machinery `genesi-ai-turbo` already
> drives (`--cache-reuse` in-session prefix reuse + `--slot-save-path` runtime
> slot save/restore). Design doc: [`docs/MEMPALACE-PROMPT-CACHE.md`].

The insight: MemPalace stores *text*, not KV tensors, so it is not a KV cache by
itself. But if recalled memory is injected as a **stable, deterministic prefix**,
the inference engine reuses the KV computed for that prefix instead of
re-prefilling it every turn — and the per-conversation KV slot can be persisted
to disk keyed by MemPalace **wing**, so reopening a chat restores both the *text
memory* and the *computed KV state* = a warm resume even after reboot.

- [x] Design: two-tier prompt (stable "core memory" prefix that is cacheable +
      small dynamic retrieved snippets that are not), KV slot keyed per wing
- [x] `genesi-mempalace bridge` — local proxy in front of `llama-server` that
      builds the stable-prefix prompt and drives `/slots?action=save|restore`
      (stdlib-only, opt-in; per-user `genesi-mempalace-bridge.service`)
- [ ] Tune MemPalace recall calls to the installed CLI's real output (on target)
- [ ] Validate TTFT win on multi-turn + resumed conversations (`bench`)

> **Non-breaking guarantee:** the bridge is an additive, opt-in layer in front of
> the existing Turbo server. It changes only *how the prompt is assembled* and
> *which KV slot is loaded* — it does **not** alter `genesi-aid`'s optimizer or
> the `llama-server` flags that already ship. With MemPalace absent, Turbo runs
> exactly as today. **Decode speed (tokens/s) is unchanged** (that's the model/
> GPU, handled by speculative decoding); the win is **TTFT / prompt cold-start**.

---

### 2.8 AI Mode 2.0 — Universal Hardware Optimizer 🚀
> Turn AI Mode from a fixed CPU/RAM tweak into an **adaptive optimizer that
> profiles the machine and applies only what that hardware can benefit from** —
> bare-metal desktop, gaming laptop, NVIDIA/AMD/Intel GPU, hybrid CPU, low-RAM
> box, or a VM. Every change stays **fully reversible**.

#### 2.8.0 Foundation — hardware detection & architecture
The brain that makes "optimize for ANY PC" real. The daemon profiles the host
once and gates every optimizer on detected capabilities.

- [x] `HardwareProfile`: CPU (vendor, physical cores, virtualized?), GPU
      (NVIDIA/AMD/Intel + VRAM), total RAM, chassis (laptop/desktop), power
      source (AC/battery). _(hybrid P/E split still pending — see 2.8.4)_
- [x] Capability-gated optimizer plugins — each captures original → applies →
      restores, and is skipped when the hardware can't use it
- [x] **VM awareness**: report "virtualized — limited gains" and skip no-op knobs
      (e.g. CPU governor doesn't exist under VirtualBox)
- [x] Profiles: **Max Performance / Battery-aware** (don't nuke power on battery
      unless the user forces it; aggressive knobs are AC/forced-gated)
- [x] Enrich `state.json` with the hardware profile + exactly-what-changed list

#### 2.8.1 🔥 GPU performance mode (biggest missing win)
- [x] **NVIDIA**: persistence mode (`nvidia-smi -pm 1`), power limit to max
      (`-pl`), graphics+memory clock lock at max (`-lgc`/`-lmc`, reset on
      disable), report VRAM use
- [x] **AMD**: `power_dpm_force_performance_level=high` (restored). Compute
      power profile via `pp_power_profile_mode` still optional.
- [x] **Intel Arc/iGPU**: lift the i915 GT frequency cap (`gt_max_freq_mhz`) to
      the hardware ceiling (`gt_RP0_freq_mhz`); restored on disable
- [x] Restore each GPU to its prior power/clock state on disable

#### 2.8.2 🔥 Power / platform profile
- [x] `powerprofilesctl set performance` while AI runs (restore prior profile)
- [x] `/sys/firmware/acpi/platform_profile` → `performance` where available
- [x] On laptops this unlocks the full CPU+GPU power/thermal budget

#### 2.8.3 🔥 Model in RAM (load fast, never stall)
- [x] Preload the active weights into the page cache (`posix_fadvise WILLNEED`
      on the GGUF/blob files the engine has mmapped) — RAM-gated, skipped on a
      RAM-backed fs (live ISO). No `vmtouch` dependency, nothing to restore.
- [ ] `mlock` the model so it can't be evicted mid-inference (opt-in; risky on
      low-RAM / live-ISO where weights are already in RAM)
- [x] Optionally pre-cache the most-recently-used models
      _(pkgrel 66: the predictive-preload MRU now warms the most-recently-used
      models — plural — at idle, accumulating their weight files newest-first
      while the total stays under ~40% of free RAM; an 8 GB+ box keeps a couple
      of recent models instant, a tight box warms one or none)_

#### 2.8.4 🔥 Smart CPU threads & core placement
- [x] Detect **physical** cores and P-core/E-core topology (`/sys` cpufreq) —
      `_performance_cores()` dedups HT siblings and counts only top-clock cores
- [x] Set inference thread count to physical P-cores; avoid SMT/E-core contention
      (Turbo `--threads`, env-overridable via `GENESI_TURBO_THREADS`)
- [x] `cpuset`/cgroup the AI process onto performance cores (system keeps the
      rest) — genesi-aid pins AI processes' CPU affinity to the P-cores on hybrid
      Intel CPUs (live, restored on disable); no-op on uniform CPUs / VMs

#### 2.8.5 ⚡ Quiet the background during inference
- [x] Pause file indexers (`baloo`, `tracker`) with SIGSTOP while AI runs, resume
      with SIGCONT on disable (safe + saves power; package managers untouched)
- [x] Also pause other CPU/RAM/IO hogs on demand (opt-in list at
      `/etc/genesi-ai-mode/hogs.conf`, read live, SIGSTOP/SIGCONT)
- [x] Compositor effect trimming done **in the user session** (helper reads
      `state.json` and unloads/reloads KWin blur + contrast via qdbus; KDE
      autostart, fully guarded on non-KWin sessions)

#### 2.8.6 ⚡ Inference-engine auto-tuning
- [x] Ollama defaults via systemd drop-in: `OLLAMA_FLASH_ATTENTION=1`,
      `OLLAMA_KV_CACHE_TYPE=q8_0`, `OLLAMA_KEEP_ALIVE=15m`
- [x] `OLLAMA_NUM_PARALLEL` / `OLLAMA_MAX_LOADED_MODELS` tuned to RAM/VRAM
      (daemon writes an EnvironmentFile the ollama unit reads at start)
- [~] Auto-pick `num_gpu` (offload layers) from detected VRAM vs model size —
      _intentionally NOT forcing a global `num_gpu`: ollama's scheduler already
      auto-offloads from VRAM, and overriding it regresses common cases. The
      llama-server path instead uses `-ngl 999` (full offload) gated by the
      advisor's VRAM-fit math._
- [x] Equivalent flags for llama.cpp / llama-server — `genesi-ai-turbo` drives
      `llama-server` with `-fa -ngl 999 -b 2048 -ub <n> --cache-reuse 256`
      (see 2.8.10 #3)

#### 2.8.7 ⚡ I/O, NUMA & scheduler
- [x] I/O scheduler → `none`/`mq-deadline` on the disk backing the weights
      (resolved from the mmapped files), captured & restored; AC/forced only
- [ ] NUMA pinning (`numactl`) on multi-socket / Threadripper
- [x] Integrate CachyOS `sched-ext` throughput schedulers while AI Mode is on
      _(pkgrel 66: opt-in `/etc/genesi-ai-mode/advanced.conf` `sched_ext = on`
      (or a scheduler name) loads a BPF sched_ext scheduler in throughput
      "server" mode via `scxctl` on the aggressive path, and switches back to
      whatever ran before on disable. Capability-gated on a sched_ext kernel +
      `scxctl` (CachyOS scx-scheds), silent no-op otherwise)_

#### 2.8.8 🧠 Intelligence, metrics & UX
- [x] **Live metrics** in `state.json` + `genesi-ai-mode info`: CPU% +
      temperature, RAM, and (while AI Mode is on) GPU utilization / VRAM /
      temperature (NVIDIA + AMD)
- [x] Ollama awareness via `/api/ps`: loaded model name, size, CPU/GPU split
- [x] Live tokens/s (best-effort scrape of the ollama journal) in `state.json`,
      the widget, the Monitor app, and `genesi-ai-mode info`
- [x] Before/after summary of exactly what AI Mode changed — structured
      `changes` list (`{lever, from, to}`) in `state.json`, derived from the
      persisted originals snapshot (survives a daemon restart), surfaced in
      `genesi-ai-mode info` as a before→after table
- [x] **Thermal guard**: if the CPU/GPU runs too hot under AI Mode, ease the
      governor (hysteresis) so "max perf" never becomes net-slower; restore when
      it cools. No-op on machines without temp sensors (e.g. a VM)
- [x] **`genesi-ai-mode bench`**: run an identical prompt with AI Mode OFF then
      ON and print the tokens/s delta (with VM caveat)
- [x] **Model advisor**: `genesi-ai-mode advise` (+ Monitor page) — given VRAM/RAM,
      shows which models/quants stay 100% on the GPU vs spill to CPU, recommends
      the biggest that fits, with the exact `ollama pull` command
- [x] Rewrite the widget for the Plasma 6 API with a richer dashboard
      (status, live CPU/RAM/GPU, loaded models, tokens/s, applied tweaks,
      on/auto/off controls)

#### 2.8.9 ✨ Advanced / opt-in (with tradeoffs)
- [x] Explicit huge pages allocated on enable, freed on disable — opt-in via
      `/etc/genesi-ai-mode/advanced.conf` (`hugepages = N`), reversible, refuses
      if it would exceed 50% of free RAM, AC/forced-gated. Default OFF.
- [~] Disable CPU security mitigations (opt-in, clearly flagged) for max
      throughput — _documented in `advanced.conf` but NOT auto-applied: it's a
      boot-time kernel cmdline (`mitigations=off`) that can't toggle live and
      weakens security, so the user opts in via GRUB themselves._
- [x] Disable PCIe ASPM / USB autosuspend for the inference GPU — PCIe ASPM →
      `performance` is opt-in (`pcie_aspm = on`), reversible, AC/forced-gated,
      default OFF. _USB-autosuspend left to udev rules (too broad to toggle
      globally; see `advanced.conf`)._

#### 2.8.10 🏎️ Beat-any-OS inference speed
> System tweaks only *match* the hardware ceiling — every OS hits the same wall
> at the same model+backend. To be genuinely **faster than any other OS**, Genesi
> must run an inference *method* others don't ship by default. Two phases:
> **prefill** (reading the prompt, compute-bound) and **decode** (writing the
> answer, memory-bandwidth-bound).
>
> - [x] **🥇 Speculative decoding ("Genesi Turbo")** — a small same-family draft
>       model proposes tokens, the big model verifies several at once. **1.5–3×
>       faster decode, identical output.** No mainstream OS does this by default.
>       ollama doesn't expose it → run `llama-server`/`llama-cli` (llama.cpp)
>       directly with `-md draft`, reusing the GGUFs ollama already pulled.
>       _**← chosen first.**_ **DONE:** `genesi-ai-turbo` (`bench`/`serve`) + a
>       one-click ⚡ switch in the Monitor chat, backed by the shipped
>       `genesi-llama-cpp` (Vulkan `llama-server`). On-HW bench still pending.
>
> - [x] **Speculative decoding is a user-toggleable option (not a default).**
>       `serve` and the Monitor default to **plain full GPU offload** (the
>       reliable, proven win); speculative decoding is **opt-in** via the
>       `--spec`/`--speculative` flag on `genesi-ai-turbo` (or `GENESI_TURBO_SPEC
>       =1`) and the "offload total ⇄ ⚡ speculative" toggle on the Monitor's
>       Turbo card (the toggle now also bundles dynamic draft length + persistent
>       KV — labelled explicitly in the UI). We deliberately **do NOT enable spec
>       by default**: on the live ISO / NVK (open nouveau Vulkan, the only thing
>       tested so far) it REGRESSED real speed — plain offload gave ~21 t/s, spec
>       dropped to ~baseline, because the draft + verification cost more than it
>       saves without a mature driver. (The 2.3× once measured was **GPU-vs-CPU**:
>       Turbo offloads via Vulkan while ollama on nouveau has no CUDA and stays on
>       CPU — not speculative decoding.) Since it's now a switch the user owns,
>       this is no longer a blocker — anyone can flip it on and compare with
>       `genesi-ai-turbo bench`. _Optional future polish: auto-default spec ON
>       only where it's proven to help (e.g. a mature CUDA driver), keeping plain
>       offload on Vulkan/NVK._
>       _**Validar sem instalar no disco:** a ISO tem uma entrada de boot
>       "Genesi OS [DEV/TESTE] NVIDIA + CUDA" (overlay 20G, nouveau bloqueado) +
>       o helper `genesi-dev-cuda-setup` (atalho "Genesi DEV: NVIDIA + CUDA") que
>       instala driver NVIDIA aberto + CUDA + ollama-cuda + o backend CUDA do
>       Turbo na sessão live (em RAM, some no reboot). Tudo DEV/TEST, fora do
>       sistema instalado._
> - ~~**Faster backend per GPU** (EXL2 / TensorRT-LLM)~~ — **dropped, not a fit.**
>       It's a subproject, not a feature: a different model format ollama doesn't
>       provide (separate downloads + acervo), a separate CUDA-only serving stack,
>       NVIDIA-only, and unvalidatable without NVIDIA hardware. If ever revisited,
>       a CUDA build of llama.cpp (same GGUF + same `llama-server` API, ~1.5–2×
>       over Vulkan on NVIDIA) is the low-risk path — not EXL2.
> - [x] **🥈 Prefill speedups (read the prompt faster)** — larger prefill batch
>       (`n_ubatch`) + KV-cache reuse so a repeated system prompt is near-instant.
>       Needs engine-level control (llama-server). (Flash attention ✅ already.)
>       **DONE:** `genesi-ai-turbo` now passes `-b 2048 -ub <1024 GPU/512 CPU>`
>       and `--cache-reuse 256`; all env-tunable (`GENESI_TURBO_UBATCH`, …).
> - [ ] **🥉 Marginal opt-in tweaks** — explicit huge pages + `mlock` for CPU
>       inference, mitigations-off (boot param). A few %, not a real differentiator
>       vs a well-tuned Linux. (See 2.8.9.) _`mlock` is wired as an opt-in Turbo
>       knob (`GENESI_TURBO_MLOCK=1`, default off); huge pages + mitigations-off
>       deferred (risky, marginal, better validated on real hardware)._

#### 2.8.11 🚀 Genesi Turbo 2.0 — warm daemon, memory coordination & predictive speed
> The decode engine (llama.cpp) is the SAME on every OS, so "2× faster decode
> than Ubuntu on the same model+quant+hardware" is not an honest claim. Genesi's
> real, defensible edge is **perceived latency** (the model is already warm so it
> answers instantly, instead of paying the load every time), a **microarch-optimal
> binary** out of the box, **hardware auto-tuning** nobody sets by hand, and a
> **system-wide shared cache**. These are the levers an OS — not an app — owns.

**Tier 0 — make it work on weak hardware (the litmus test: 4 GB RAM + a dGPU)**
> The model's weights live in **VRAM**, separate from the 4 GB system RAM, so a
> laptop that could never run a model on CPU can run it on the GPU. This already
> works in llama.cpp/ollama — the OS's job is to detect VRAM, fit the model, and
> never OOM. Bounded by VRAM size: ~2 GB → 1–3B, 4 GB → 3B (7B Q4 tight), 6 GB+
> → 7B. Already feasible today; these tasks make it automatic and safe.
- [x] **VRAM-fit full offload.** Run the model 100% in VRAM (`-ngl 999`) when the
      advisor's fit math says it fits; when it doesn't, fall back to `-ngl auto`
      so llama.cpp fits as many layers as the VRAM holds instead of a blind 999
      that OOMs a small card — so a 4 GB-RAM + dGPU laptop runs models its RAM
      never could, without crashing tight cards.
- [x] **Advisor → biggest model that fits 100% in VRAM**, defaulting to small
      quants (1B/3B Q4) on 2–4 GB cards, with the exact `ollama pull`. (The
      advisor already does the VRAM-fit math — wire it to Turbo's model pick.)
      _**DONE (pkgrel 65):** `genesi-ai-turbo recommend` prints the biggest
      model whose Q4_K_M fits 100% in VRAM (Vulkan/nvidia-smi VRAM probe + fit
      math); the Monitor's Turbo card shows it as a one-click "Recomendado p/ sua
      GPU" chip that sets the served model. Pick logic validatable now; the
      VRAM-dependent result needs a real GPU._
- [x] **Turbo draft fallback on tight VRAM.** Speculative needs target+draft
      resident; if both don't fit, Turbo drops the draft and runs plain GPU
      offload (still far faster than CPU); on CPU-only it drops the draft too
      (a CPU draft is a net loss). Never OOMs the GPU.
- [ ] **Guard CPU+GPU split on low system RAM.** On 4 GB RAM, don't spill big
      layers to CPU (it OOMs) — prefer a smaller model that fits VRAM fully.
- [x] q8/q4 KV cache + modest context keep more in VRAM (Turbo ships q8 KV +
      `GENESI_TURBO_CTX`). Memory coordination (Turbo unloads Ollama) already
      avoids double-loading on tight boxes.

**Tier 1 — kill the cold-start (the biggest *felt* win)**
- [x] **Memory coordination (Turbo ⇄ Ollama).** Turbo serves via `llama-server`,
      so Ollama doesn't need the model resident meanwhile. On low-RAM boxes (e.g.
      a 6 GB VM) two ~3 GB copies don't fit → `llama-server` OOM'd/swapped and
      "Turbo never came up". Now the Monitor **unloads Ollama's keep-alive model
      (`keep_alive=0`) before** starting Turbo, and **Force OFF releases it too**
      so RAM returns to baseline instead of lingering ~15 min. _(shipped)_
- [ ] **Always-warm shared inference daemon.** One persistent `llama-server`
      (the Turbo `:11435`, already OpenAI-compatible) that **every app uses** —
      no per-app reload, and a **shared prefix/KV cache** across apps. An app
      can't assume a system daemon; an OS can. Managed by `genesi-aid` as a
      socket-activated/long-lived unit.
- [ ] **Predictive preload at login/idle.** `genesi-aid` warms the user's
      most-used model at low priority when the machine is idle, so the first
      prompt is instant (vs ~2 min cold load today). RAM-gated; integrates with
      the existing usage signals.
      _**DONE (pkgrel 64):** `maybe_warm_idle` formalized into true predictive
      preload. genesi-aid persists an MRU of the weight files the user actually
      loaded to `/var/lib/genesi-ai-mode/warm.json` (StateDirectory, survives
      reboot); on a fresh boot it seeds `_warm_files` from that MRU and warms the
      last-used model into the page cache while idle — so the FIRST prompt after
      login reads from RAM, not disk. Conservative: throttled, skipped on a
      RAM-backed fs, gated to <50% of available RAM (no-op on tight boxes)._
- [x] **🌟 Ideia 2: Persistent prompt/KV cache to disk (Zero Cold-Start).** Use `llama-server` slot
      save/restore (`--slot-save-path`) so a long system-prompt's KV survives
      restarts — first reply of a new chat stays fast even after a reboot.
      (The server already enables an 8 GiB prompt cache; persist + reuse it.)
      _**DONE (pkgrel 65):** Turbo passes `--slot-save-path` (per-user cache dir,
      gated on `--help`, disable with `GENESI_TURBO_NO_SLOT_CACHE=1`), enabling
      the runtime slot save/restore API. Harmless when unused. Next step =
      client orchestration (save after a prompt, restore on start) to realize the
      felt zero-cold-start win._

**Tier 2 — real throughput the OS uniquely controls**
- [ ] **Microarch-optimal `llama.cpp` build + auto-dispatch.** CachyOS is already
      x86-64-v3/v4; ship the best ISA (AVX-512/VNNI, Intel **AMX** where present)
      and auto-select per detected CPU. A real, measurable prefill/decode gain an
      app can't assume.
- [ ] **Hardware auto-tune for Turbo.** Auto-set `--threads` = physical cores,
      pin with `--cpu-mask`/cpuset, NUMA placement, auto `-ngl` from VRAM, plus
      governor/power already done by AI Mode. (Builds on 2.8.4 + 2.8.7.)

**Tier 3 — Algorithmic decode wins (Revolutionary)**
- [x] **N-gram / prompt-lookup speculation** (no draft model needed) — great for
      code, quotes and repetitive text; Turbo enables `--spec-type ngram-simple`
      on CPU-only machines (when the binary supports it), so GPU-less laptops get
      a speculative speedup with no second model and no extra RAM.
- [x] **Dynamic draft length** — tune how many tokens the draft proposes from the
      live acceptance rate (`--draft-max/--draft-min/--draft-p-min`): speculate
      more on easy spans, back off on hard ones. Beats today's fixed N.
      _**DONE (pkgrel 65):** when speculative decoding is on (a draft model is
      used), Turbo adds a draft-length floor + acceptance-probability threshold
      so llama.cpp adapts N to the live acceptance rate. Each flag is gated on
      the installed binary's `--help` (names vary by version) and env-tunable
      (`GENESI_TURBO_DRAFT_MAX/MIN/P`). Active ONLY in ⚡ speculative mode — the
      Monitor's toggle says so explicitly. Real gain needs CUDA validation._
- [ ] **🌟 Ideia 1: Native Medusa / EAGLE Integration** — Em vez de 2 modelos (principal + draft),
      carrega um **único modelo** com múltiplas "cabeças extras" de especulação. Gera ganhos
      massivos (3x a 4x) de velocidade de resposta sem dobrar o consumo de VRAM.

**Tier 4 — Memory & ZRAM OS-Pinning (Revolutionary)**
- [ ] **🌟 Ideia 3: ZRAM AI Pinning (`mlock` + ZRAM)** — Para PCs de 8GB ou sem placa dedicada:
      criar um bloco de ZRAM (RAM comprimida pelo Kernel) e "pinar" (`mlock`) o modelo de IA
      lá dentro. A IA fica hiper-comprimida e nunca vai pro SSD (swap), garantindo trocas
      instantâneas entre navegador e IA sem o clássico "congelamento" do Windows.
- [ ] Smart partial offload when VRAM can't hold the whole model.

> **Honest framing for marketing:** lead with *"local AI answers instantly and
> tunes itself — no setup"* (warm daemon + preload + auto-tune + microarch build),
> not "2× faster than Windows". The first is true and defensible; the second isn't.

### 2.9 Genesi AI Mode Monitor (dedicated app) 📊
> A standalone GUI app (beyond the panel widget) to watch and control AI Mode —
> the visual front-end for everything `genesi-aid` already exposes in
> `state.json`.

- [x] Live dashboard: AI Mode state, CPU/RAM/GPU utilization, VRAM, temperatures
- [x] Detected AI processes + loaded Ollama models (name, size, CPU/GPU split)
- [x] Tokens/s history graph (Canvas sparkline of the live rate)
- [x] Shows exactly which optimizations are applied, with on/auto/off control
- [x] Profile switch (Máximo / Equilíbrio / Bateria / Auto) — `genesi-ai-mode
      profile <p>`, a `/run/genesi-ai-mode/profile` file the daemon reads live
      (re-applies on change), and a segmented control in the Monitor top bar
- [x] One-click benchmark (wraps `genesi-ai-mode bench`) with a results chart
      _(pkgrel 63: "Benchmark de desempenho" card in the Painel — streams each
      step live and draws an OFF-vs-ON tokens/s bar graph with the % gain)_
- [x] Backend install offers **CUDA vs Vulkan** with a hardware-based pick
      _(pkgrel 67: the "Instalar Backend" prompt opens a dialog explaining both
      and recommends one — CUDA when nvidia-smi works (NVIDIA + proprietary
      driver, ~1.5–2× faster), Vulkan otherwise (universal, shipped). Vulkan →
      genesi-llama-cpp via pkexec; CUDA → llama.cpp-cuda via the AUR helper,
      best-effort)_
- [ ] **MemPalace integration**: surface AI memory/usage stats
- [x] Reads `state.json` for display; control via the `genesi-ai-mode` CLI
      (PySide6 + Kirigami app, `genesi-ai-monitor`)

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

## PHASE 4: IDE & Dev Tools 🟦 IN PROGRESS
> Developer-focused tools and integrations (secondary differentiator).
>
> Phase 4 ships **two AI-native front-ends** — **Genesi Code** (the dev tool, a
> fork of Warp) and **Genesi Hermes** (the AI-agent desktop app, a fork of Hermes
> Desktop). Neither is an isolated app: both are **first-class clients of the same
> local-AI stack** Phase 2 already built, and they talk to **each other**. See
> [4.0 Shared AI Mode integration](#40-shared-ai-mode-integration-the-glue) for
> the contract that ties them into AI Mode, Turbo, and speculative decoding.

### 4.0 Shared AI Mode integration (the glue)
> **Design rule: any Genesi app that runs a local model is automatically a citizen
> of AI Mode.** The moment Genesi Code or Genesi Hermes drives a local inference
> backend, the whole Phase 2 machinery must light up for it — with **zero extra
> setup from the user**.

- [ ] **Auto-detection already exists, reuse it.** `genesi-aid` already detects
      Ollama / llama.cpp / llama-server / vLLM / LocalAI running (see 2.1). When
      Genesi Code or Genesi Hermes spawns or connects to one of those, AI Mode
      switches on by itself — governor, VRAM/clock locks, thread placement,
      background quieting, the works — and stands down when inference goes idle
      (the warm/active/idle classifier in 2.6). No app-specific hook needed; it
      falls out of the existing process detection.
- [ ] **Point both apps at Genesi Turbo, not a private server.** Both Hermes and
      Code speak the **OpenAI-compatible** API. The cleanest integration is to aim
      them at the **always-warm shared Turbo daemon** (`llama-server` on `:11435`,
      see 2.8.11 Tier 1) instead of each spawning its own — so they inherit full
      GPU offload, the **q8 KV cache**, **prompt/KV reuse**, **speculative
      decoding**, and the **persistent slot cache** for free, and they **share one
      warm model + one KV cache** across apps (no per-app reload, no double-loading
      on tight boxes).
- [ ] **Surface the link in the UI.** When AI Mode / Turbo is active for a model an
      app is using, the app shows it (a small "⚡ Turbo / AI Mode ON" indicator
      reading `state.json`), so the user sees that Genesi is tuning the machine for
      them. The AI Mode Monitor, conversely, lists Genesi Code / Hermes among the
      detected AI clients.
- [ ] **One install path for models.** Models installed/configured from the AI Mode
      Monitor (the advisor's "biggest model that fits your VRAM", the `ollama pull`
      one-click, the Turbo backend installer) are the **same models** Code and
      Hermes then use — one catalog, one place to manage local AI for the whole OS.
- [ ] **One shared memory — every conversation is remembered, forever.** Both apps
      back their memory onto the **same MemPalace** wing (see 2.7), so the AI never
      starts from a blank slate: a chat in Genesi Code and an agent run in Genesi
      Hermes write to and recall from **one on-device memory layer**. Close
      everything, reboot — next time the model still remembers every past
      conversation and the project context. Nothing leaves the machine. Combined
      with the prompt-cache bridge (2.7.1), recalled memory also rides the shared
      KV cache, so remembering the past is **instant**, not just possible.

### 4.1 Genesi Code — AI-native dev tool (fork of Warp)
> Direction: fork **Warp** (Rust, AI-native terminal/dev tool) instead of
> VS Code/Zed, so the AI workflow is first-class.
>
> **Feasibility CONFIRMED (2026-04):** Warp open-sourced its full terminal client
> on GitHub — dual-licensed **AGPL-3.0** (core) + **MIT** (the `warpui`/`warpui_core`
> UI crates). It's a Rust/Cargo app, buildable from source (`./script/bootstrap`
> → `./script/run`). The fork lives at **[zFreshy/genesi-code](https://github.com/zFreshy/genesi-code)**
> (fork of `warpdotdev/warp`, keeps the upstream link for pulling updates).
>
> **License note:** genesi-code inherits **AGPL-3.0** — it cannot be relicensed to
> the OS's GPL-3.0, but the two are compatible and an AGPL package ships fine in a
> GPL distro (a distro is an aggregate). Published modifications stay AGPL-3.0.
>
> **Delivery:** genesi-code is **installable via the Genesi Package Installer**, not
> baked into the live ISO (keeps the ISO light; same plan for Genesi Hermes). A
> Welcome-app pointer to install it is deferred to the polish phase.

**Status: 🟦 a working build ships today** (`v0.0.29`), installable via the Genesi
Package Installer. The fork builds in CI → GitHub Release → the `genesi-code` package
in the Genesi pacman repo. What works now vs. what's left for a 1.0:

#### Shipping today
- [x] **Fork rebranded "Genesi Code"** — welcome/onboarding strings, tagline, app_id,
      Genesi-green leaf logo; sign-in UI hidden, premium upsells removed; runs **fully
      logged-out** (no account, no cloud gate — Warp's cloud agent is left inert)
- [x] **Build & delivery pipeline** — `genesi-build.yml` builds the Rust app in a
      `cachyos-v3` container → GitHub Release `v0.0.X` → the `genesi-code` PKGBUILD
      ships the prebuilt binary into the Genesi repo, with a VM-aware launcher
      (software GL where a VM can't present hardware GL)
- [x] **Classic LSP autocomplete (no AI)** for JS/TS, Python, Rust, Go, C/C++, HTML,
      CSS, JSON — deterministic local language servers, install-on-demand from the
      footer, with a generic file-extension→server mapping so more languages plug in
- [x] **Login-free local AI panel** (Ctrl+Shift+G or the ⚡ button) — talks **directly**
      to on-device Ollama (native `/api/chat`, **streaming**) or Genesi Turbo
      (`:11435`, OpenAI SSE), no account; shows the live **AI Mode** badge (tokens/s)
      and can force AI Mode on/off right from the panel
- [x] **Workspace context (📎)** — auto-attaches the focused file / selection to the
      prompt, like a normal AI IDE (toggleable)
- [x] **Codebase agent** — the model can read the project (`read_file` / `list_files`
      / `grep`), **run shell commands**, and **edit files** (SEARCH/REPLACE), each
      gated by a per-action **Allow / Deny** prompt with an **AUTO** mode to skip it;
      all bounded and path-safe to the project root
- [x] **Polished agent transcript** — assistant replies render as **markdown**
      (headings, lists, **bold**, `code`, fenced blocks) instead of raw markup; the
      model's tool calls no longer flash as raw `<tool:…>` XML — each step is a clean,
      collapsible **💭 Thought** / tool step, and `run_command` is shown as a
      **terminal block** (`$ cmd` + captured output) rather than ugly inline text
- [x] **Stop / interrupt** a running generation or agent loop — a ⏹ Stop control
      (shown while in flight) bumps a turn-id so the detached stream callbacks no-op
- [x] **Auto-default to the shared Turbo daemon** (`:11435`) when it's healthy and the
      user hasn't picked an endpoint — Code then inherits GPU offload + the shared warm
      KV cache for free (see [4.0](#40-shared-ai-mode-integration-the-glue)); a manual
      endpoint choice still wins

#### Remaining for a 1.0 ("100%")
- [ ] **A capable local model on capable hardware — the real gate.** The agent code
      works, but a model that reliably drives tools needs ~3B+ (a *coder* model) and
      the RAM/VRAM to run it. On a weak box a 7B OOMs — Ollama drops the connection
      mid-reply — while a 0.5B is too small to follow the tool protocol. This is
      **Phase 2's job**: the advisor picks the **biggest model that fits the VRAM**
      (2.8.8), the **AI bundle** (6.2) installs a sensible default coder model, and
      Turbo keeps it warm. Genesi Code itself works the moment a fitting model is
      selected — nothing more to build app-side here.
- [ ] **Live edit integration** — edits currently write to **disk**; route them
      through the open editor buffer so they appear live and are undoable, plus a real
      multi-file diff review before apply
- [ ] **Run commands in a real integrated-terminal pane** — `run_command` now renders
      as a terminal block in the chat (and feeds the model the captured output); the
      next step is dispatching it into an actual terminal tab/block so the user can
      interact with long-running commands, with output streamed back to the agent
- [x] **IDE-style AI panel — click-to-open model picker + cleaner controls.** The side
      panel now reads like a real IDE assistant: the AI selector is a click-to-open
      popup (on-device models + the Turbo endpoint, with a disabled "Cloud — coming
      soon" slot), a dedicated ⚡ Turbo on/off toggle sits beside it, and the agent
      toggles (🤖 Agent / AUTO / 📎) moved into a clean control strip above the compose
      box. The old blind "cycle through chips" controls are gone. _First step of the
      broader "evolve our Warp fork toward a full IDE look" direction — more to come._
- [ ] **Bring-your-own AI key (optional cloud models).** Let the panel use a **cloud**
      model as an *option* beside the local-first default. The Warp fork already ships
      the BYOK plumbing (`ApiKeys` + custom endpoints, already unlocked for logged-out
      use); this is mostly wiring the UI to it. **Planned UX (in the new picker):**
      choosing the "Cloud" slot reveals a provider chooser — **Gemini / OpenAI /
      Claude / HuggingFace / OpenRouter** (or any OpenAI-compatible custom endpoint);
      picking one opens a small inline popup for the **API key**, and for HuggingFace a
      **model** field — all in the panel, no separate settings screen. **Local stays
      the default** — the key is purely opt-in, for when the user wants a bigger/faster
      model than the machine can run, or a frontier model for hard tasks. Keys are
      stored in the OS keyring (Secret Service) with the existing encrypted-file
      fallback — still on-device.
- [ ] **MemPalace integration — remembers every conversation.** Persist & recall every
      chat onto the shared MemPalace wing (see [4.0](#40-shared-ai-mode-integration-the-glue)
      and 2.7); deferred until the agent UX is solid
- [ ] **Generate-a-review with the local AI** — wire the existing code-review view to
      the local model
- [ ] **Genesi Hermes bridge** — hand a task to / from a Hermes agent over the same
      local backend, and watch it via Hermes' Office (Claw3d) view (see 4.2)
- [x] Desktop + menu shortcut — `.desktop` + leaf icon ship in the `genesi-code`
      package _(KRunner/menu launch still flaky under `setsid`; runs fine from a
      terminal / click — minor, deferred)_

### 4.2 Genesi Hermes — AI-agent desktop app (fork of Hermes Desktop)
> Fork of [Hermes Desktop](https://github.com/fathah/hermes-desktop) (Electron +
> React/TypeScript, **MIT** — compatible with Genesi OS's GPL-3.0): a native
> front-end for installing, configuring and talking to a self-improving AI agent
> with tool use, memory, multi-platform messaging and a closed learning loop.
>
> **Why it's a perfect fit for Genesi OS:** Hermes already runs models **both
> ways** — locally via OpenAI-compatible endpoints (Ollama, llama.cpp, vLLM,
> LM Studio) **and** through API providers including **Hugging Face**, OpenRouter,
> Anthropic, OpenAI, Gemini, Groq, etc. Genesi already owns the local side (AI
> Mode, Turbo, the Monitor's model installer/advisor). Bolting Hermes on top means
> the user **configures and installs the AI once, from the AI Mode Monitor**, and
> then has a full agent desktop driving that exact local model — tuned by the OS.

- [ ] Fork of Hermes Desktop with Genesi branding + theme (Plasma-native look)
- [ ] **Default to the local Genesi stack** — pre-configure Hermes' local
      OpenAI-compatible endpoint to the **Genesi Turbo daemon** (`:11435`) so out
      of the box the agent runs on the machine's own GPU-offloaded, speculative,
      warm model; Hugging Face / cloud providers remain available as opt-in
- [ ] **AI Mode / Turbo aware** — running a local agent model auto-triggers AI Mode
      and Turbo via the existing detection, same contract as Code
      (see [4.0](#40-shared-ai-mode-integration-the-glue))
- [ ] **Model install unified with the Monitor** — the models Hermes can run are
      provisioned/recommended from the AI Mode Monitor (advisor + one-click pull),
      not a separate downloader; one place to manage local AI for the OS
- [ ] **MemPalace integration — the agent never forgets.** Hermes' memory system
      backs onto MemPalace, so every conversation and agent run is persisted and
      recalled across sessions and reboots, sharing the same on-device memory layer
      as Code and the rest of Genesi (see
      [4.0](#40-shared-ai-mode-integration-the-glue))
- [ ] **Genesi Code bridge** — the agents/models running in Hermes are usable from
      Genesi Code and vice-versa (shared local backend). The **Office (Claw3d) 3D
      view** can be embedded/launched from Code so the developer watches the agent
      work on the project live (see 4.1)
- [ ] Desktop + menu shortcut; ship as the `genesi-hermes` package
- [ ] License/feasibility check of the Hermes Desktop fork (MIT base is fine;
      confirm bundled toolsets/providers don't drag incompatible deps)

### 4.3 Container widget in Plasma ✅ (package `genesi-containers`)
> Plasma 6 applet + a thin `genesi-containers` CLI; engine auto-detected
> (Docker daemon if up, else rootless Podman). Ships on the live ISO too.
- [x] Taskbar widget showing running Docker (and Podman) containers
- [x] Start/Stop/Restart with one click
- [x] View container logs (in a terminal) and mapped ports; + one-click shell
- [~] CPU/RAM usage per container — deferred (live `docker stats` streaming)

### 4.4 Project sandboxes (isolated workspaces) ✅ (package `genesi-sandboxes`)
> PySide6/Kirigami GUI + `genesi-sandboxes` CLI on top of Distrobox.
- [x] Based on Distrobox
- [x] GUI to create/manage workspaces (create from template, open terminal, delete)
- [x] Templates: Java + Spring Boot, React + Vite, Python + FastAPI, Go, Rust,
      C/C++, plain Arch
- [x] Each workspace has its own isolated dependencies (a Distrobox container)
- [~] Integration with Genesi IDE — deferred (open a workspace in Genesi Code)

### 4.5 Network inspection ✅ (package `genesi-netinspect`)
> **Genesi API Inspector** — a full HTTP/HTTPS interception workbench (the free,
> scriptable Burp-Suite equivalent on Linux) built on mitmproxy/mitmweb. Plus
> `genesi-proxy on|off|toggle`, which flips both the KDE/KIO and env-var proxy
> to 127.0.0.1:8080 (reversible).
- [x] mitmproxy pre-installed and configured
- [x] Burp-style interception UI — live flow list, **intercept/pause + edit** a
      request before it's sent, inspect request/response, and **replay/resend**
      (Burp's "Repeater"); Python addons cover the "extensions" role. Launches
      mitmweb and routes the desktop through it, flipping the proxy off on exit.
- [x] **HTTPS/API decryption** — `genesi-netinspect cert` trusts the mitmproxy
      CA system-wide (+ a "Trust certificate" desktop action); `untrust` reverses
      it. Without it HTTPS can't be decrypted.
- [x] Quick shortcut to enable/disable a debug proxy — `genesi-proxy toggle`
      CLI + a "Genesi Debug Proxy (toggle)" menu entry
- [~] Per-app trust stores (Firefox/Java keep their own) + per-container traffic
      integration with the container widget — deferred
- [ ] Optional native Genesi UI over mitmproxy's addon API (Scanner/Intruder-
      style helpers) if we ever outgrow mitmweb — mitmproxy stays the engine

### 4.6 Database explorer ✅ (package `genesi-db-explorer`)
> `genesi-db` launcher + Dolphin service menu. DB Browser for SQLite ships by
> default (in the repos); a full multi-engine client (DBeaver/Beekeeper) is a
> one-click install from the Genesi Package Installer and the launcher prefers it.
- [x] Beekeeper Studio or DBeaver pre-installed — DB Browser for SQLite by
      default; DBeaver/Beekeeper installable on demand, auto-preferred when present
- [x] Dolphin plugin to connect to databases — "Open in Genesi DB Explorer"
      service menu for .sqlite/.db files
- [~] Support for PostgreSQL, MySQL, SQLite, MongoDB — SQLite out of the box;
      PostgreSQL/MySQL via DBeaver; MongoDB needs a DBeaver driver (deferred)
- [x] Quick table and data visualization — via the launched client

---

## PHASE 5: Polish & Distribution ⬜ PENDING
> Final polish and public release.

- [x] Custom Calamares slideshow & imagery — Genesi leaf logo/icon, three
      branded slides, and a Genesi welcome image. Branding now has a **single
      source of truth** (`genesi-calamares-config`): the `genesi-calamares-branding`
      package and the live ISO read the exact same dir, so an installed system
      can no longer fall back to CachyOS art; `customize_airootfs.sh` copies it
      authoritatively (no fragile CachyOS overlay).
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

## PHASE 6: Genesi Welcome & Control Center (installed system) 🎛️
> A post-install hub — the **same app as the live-ISO welcome**, minus the
> "install system" action, plus a lot more. Modeled on CachyOS Hello (Docs /
> Support / Project links) but built around a one-click **App Installer** and a
> **Tweaks/Settings** center. The everyday front door of Genesi OS.

### 6.1 Welcome hub (Hello-style) 🟦 (package `genesi-welcome`, pkgrel 4)
> Reworked from the 4-button stub into a CachyOS-Hello-style hub. **One app, two
> modes**, detected at runtime via `is_live()` (`/run/archiso` or `archiso`/
> `copytoram` on the kernel cmdline).
- [x] Shared codebase, live vs installed: the **"Install Genesi OS" button shows
      ONLY on the live ISO**; the installed system hides it and is the everyday
      hub. (Live also gets a "Repair installed system" tool — see 6.3.)
- [x] Documentation / Support / Project sections — Read me, Wiki, Release info,
      Forum/Issues, Software (→ App Installer), Get involved, Development, Donate
      (currently point at the GitHub repo/wiki/issues until the docs site exists)
- [x] Language selector (pt-BR / English, rebuilds the UI live) + "launch at
      start" toggle (manages a per-user `~/.config/autostart` override)
- [ ] Fuller i18n (more languages) and a real docs site to point the doc buttons at

### 6.2 App Installer (one-click) ⭐ flagship 🟦
- [~] Curated catalog — the "Install Apps" button launches the **Genesi Package
      Installer** (`genesi-packageinstaller`); a Genesi-curated, one-click
      catalog with progress/rollback on top of it is still pending
- [~] **Gaming bundle** — the Maintenance page's "Install Gaming Packages" pulls
      the CachyOS gaming set (`cachyos-gaming-meta` + `cachyos-gaming-applications`);
      per-GPU driver auto-pick + a dedicated one-click card still pending
- [ ] **AI bundle (Genesi differentiator)** — one click installs Ollama + pulls a
      default model so local AI + AI Mode work instantly (pending)

### 6.3 Tweaks / Maintenance center 🟦
> A second page in the Welcome app (✕ back ↔ hub), modeled on CachyOS Hello's
> fixes/tweaks screen. Each fix runs in a terminal (visible output + the sudo
> prompt); service toggles reflect `systemctl is-enabled` and flip via pkexec.
- [x] **Fixes**: Update System, Reinstall All Packages, Reset Keyrings,
      `pacman-key --init`, Remove Pacman DB Lock, Clean Package Cache, Remove
      Orphan Packages, Install Gaming Packages, Install Snapper Support, Refresh
      Mirrors, Change DNS (systemd-resolved drop-in, reversible), Install SpoofDPI
- [x] **Service toggles**: Profile-sync-daemon (user), Systemd-oomd, Bpftune,
      Ananicy Cpp, Bluetooth
- [x] **Applications**: launch the Package Installer and the Kernel Manager
- [x] **🛟 Repair installed system (live ISO only)** — for when an install is too
      out-of-date to boot: the user picks the root partition, and it mounts +
      `arch-chroot`s in to `pacman-key --init/populate` + a full `pacman -Syu`,
      then unmounts. (Interactive + guarded; the user confirms the partition.)
- [ ] Genesi performance presets / AI Mode profile toggle surfaced here (the AI
      Mode Monitor owns profiles today — link it in)
- [ ] Move destructive fixes behind a confirm step + a richer settings UI
      (drivers, kernel, shell) like a full control center

### 6.4 Integration
- [ ] Launches the AI Mode Monitor (2.9), Genesi Code (4.1) and Genesi Hermes (4.2)
- [ ] MemPalace status surfaced here too

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
