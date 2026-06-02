# genesi-ai-mode

Automatic, **reversible** AI optimization daemon + Plasma widget for Genesi OS.

When a local-AI inference process is detected, the system is tuned for it; when
the workload stops (and there's no manual override) every tweak is restored.

## Components

- `genesi-aid` — Python daemon that detects AI processes and applies tuning
- `genesi-ai-mode` — CLI to force/inspect the mode (`on`/`off`/`auto`/`toggle`/`status`)
- `genesi-aid.service` — systemd service (root)
- `genesi-ai-mode.tmpfiles.conf` — creates `/run/genesi-ai-mode` for IPC
- `99-genesi-ai.conf` — static sysctl tuning (no permanent resource reservation)
- `plasmoid-aimode/` — Plasma widget: status + manual toggle

## Detected frameworks

Ollama, llama.cpp (`llama-server`/`llama-cli`), vLLM, LocalAI,
text-generation-webui, KoboldCPP, Oobabooga.

## Optimizations (only while AI Mode is ON)

| Knob | AI Mode | Restored on exit |
|------|---------|------------------|
| CPU governor | `performance` | yes (to captured original) |
| `vm.swappiness` | 10 | yes |
| Transparent huge pages | `always` | yes |
| AI process priority | `nice -5` | reset to 0 |

CPU affinity pinning was intentionally removed — CPU inference scales with all
cores, so limiting affinity hurt the main use case.

## Manual control

```bash
genesi-ai-mode on       # force ON (even with no AI running)
genesi-ai-mode off      # force OFF (even while AI runs)
genesi-ai-mode auto     # follow automatic detection (default)
genesi-ai-mode toggle   # flip forced-ON / automatic
genesi-ai-mode status   # print daemon state (JSON)
```

The override is a file in the daemon's world-writable runtime dir, so no sudo is
needed. The panel launcher and the widget button use the same mechanism.

## How it talks to the UI

| Path | Writer | Readers |
|------|--------|---------|
| `/run/genesi-ai-mode/force` | user / CLI / panel / widget | daemon |
| `/run/genesi-ai-mode/state.json` | daemon | widget, `genesi-ai-mode status` |
| `/run/genesi-aid-originals.json` | daemon (0600) | daemon (restart recovery) |

`/run` is tmpfs: a daemon restart keeps the saved originals (so restore is
correct), but a reboot starts clean. The service keeps `PrivateTmp=true`
hardening because none of this uses `/tmp`.

## Build

```bash
makepkg -f
```

## Usage

```bash
sudo systemctl status genesi-aid     # service state
sudo journalctl -u genesi-aid -f     # logs (journal only, no unbounded file)
genesi-ai-mode status                # current state as JSON
```
