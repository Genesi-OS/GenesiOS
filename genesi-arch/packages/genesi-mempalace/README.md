# genesi-mempalace

Integrates [MemPalace](https://github.com/MemPalace/mempalace) — a local-first,
verbatim AI memory system (PyPI `mempalace`, MIT) — as Genesi OS's long-term
memory layer for the on-device AI. Roadmap [2.7](../../../docs/ROADMAP.md).

Nothing leaves the machine: MemPalace stores conversations and project context
locally and retrieves them with semantic search (no API key, no cloud).

> **Supply chain:** MemPalace's only official sources are its GitHub repo, the
> PyPI package `mempalace`, and mempalaceofficial.com. Other domains (`.tech`,
> `.net`, …) are impostors that may ship malware. This package provisions
> **strictly from PyPI**.

## What it ships

| File | Installs to | Role |
|---|---|---|
| `genesi-mempalace` | `/usr/local/bin/` | launcher: `watch`, `mine`, `sweep`, `status`, `mcp`, `install`, `doctor` |
| `genesi-mempalace.service` | `/usr/lib/systemd/user/` | **per-user** background indexer (`watch`) |
| `genesi-mempalace.conf` | `/etc/genesi-mempalace/` | system-default config (all opt-in) |

## Why per-user

The MemPalace "palace" lives in `$HOME` (`~/.mempalace`), its MCP server runs on
demand over stdio, and its "service" role is really a periodic indexer. So:

- The `mempalace` CLI is provisioned **per-user** into an isolated `uv tool`
  env (`genesi-mempalace install`) — not as a root pacman dep.
- The systemd unit is a **user** service (`systemctl --user`).
- The indexer runs at `nice 10` + idle IO so it never competes with active
  inference (AI Mode is about performance).

## Setup (as your normal user, not sudo)

```bash
genesi-mempalace install                      # provision the CLI (uv tool, from PyPI)
# edit ~/.config/genesi-mempalace/config.conf # set index_paths / transcript_dirs
systemctl --user enable --now genesi-mempalace.service
genesi-mempalace doctor                       # verify wiring
```

The AI Mode Monitor can do the install + enable steps with one click.

## MCP clients (IDE / agents)

Point any MCP client at the launcher so the isolated env + palace path are
guaranteed set:

```json
{ "mcpServers": { "mempalace": { "command": "genesi-mempalace", "args": ["mcp"] } } }
```

## Prompt caching with MemPalace (roadmap 2.7.1)

The recalled memory can **also** kill the prompt cold-start by combining
MemPalace's text recall with the KV-cache machinery `genesi-ai-turbo` already
drives. See the design: [`docs/MEMPALACE-PROMPT-CACHE.md`](../../../docs/MEMPALACE-PROMPT-CACHE.md).

## State for the Monitor

`watch` publishes `mempalace-state.json` under `$XDG_RUNTIME_DIR` (or
`~/.cache/genesi-mempalace/`): install status, palace stats (wings/drawers),
last sync, and any error — for the Monitor's MemPalace card.
