# Prompt caching with MemPalace (memory + KV reuse)

> Roadmap [2.7.1](./ROADMAP.md). Status: **bridge built (skeleton), pending
> on-device validation**. Detection/packaging shipped; the `genesi-mempalace
> bridge` proxy is implemented and needs tuning against the real MemPalace recall
> output + `llama-server` `/slots` API on the target.

## The idea in one paragraph

MemPalace gives the local AI long-term memory by recalling past conversations and
project context as **text**. On its own that text is *re-read by the model every
turn* — an expensive prefill (the prompt cold-start). But `genesi-ai-turbo`
already drives the two llama.cpp mechanisms that can reuse that work:
`--cache-reuse` (in-session prefix KV reuse) and `--slot-save-path` +
`/slots?action=save|restore` (persist a slot's KV state to disk). If we inject
recalled memory as a **stable, deterministic prefix** and key the persisted KV
slot to the MemPalace **wing**, then recalled memory *also* becomes a warm prompt
cache: the model reuses the KV computed for the memory instead of re-prefilling
it, and reopening a chat restores both the *text memory* and the *computed KV
state* — a warm resume even after a reboot.

## What this is and is not

- **It is** a way to make recalled memory cheap to keep in-context (lower TTFT,
  killed prompt cold-start on resume).
- **It is not** a speedup of token generation. Decode rate (tokens/s) is bound by
  the model and GPU and is handled separately by speculative decoding. MemPalace
  does not touch decode.
- **It is not** a new KV format. MemPalace stores text; the KV cache stays the
  engine's. We only make the *content* stable enough that the engine's existing
  cache actually hits.

## Why the prefix must be stable (the one hard rule)

llama.cpp reuses KV only for the **longest matching prefix** of tokens it already
processed. If the recalled memory placed at the start of the prompt changes from
turn to turn (because the semantic query changed), the prefix diverges, the cache
invalidates from the first differing token onward, and there is **no win**.

So the prompt is built in two tiers:

```
┌─────────────────────────────────────────────┐
│ [1] CORE MEMORY  — stable, deterministic      │  ← cacheable prefix
│     • system prompt                           │     (KV reused every turn,
│     • the wing's pinned "core" memories       │      persisted per wing)
│       (sorted, fixed wording, append-only)    │
├─────────────────────────────────────────────┤
│ [2] RECALLED SNIPPETS — dynamic, small         │  ← not cacheable, but cheap
│     • top-k semantic hits for THIS prompt     │     (few hundred tokens)
├─────────────────────────────────────────────┤
│ [3] CONVERSATION TURNS + the new user message │  ← in-session --cache-reuse
└─────────────────────────────────────────────┘
```

Tier 1 is the high-value cache target: it is large (the persistent memory) and
identical across turns, so its KV is computed once and reused/persisted. Tier 2
is deliberately kept small and placed *after* the stable prefix, so a changing
retrieval set only invalidates a few hundred tokens, not the whole memory block.

## Slot keying (the cold-start kill on resume)

`llama-server` exposes runtime slot save/restore (already enabled by Turbo via
`--slot-save-path`, gated on the binary supporting it; disable with
`GENESI_TURBO_NO_SLOT_CACHE=1`). The bridge maps **one KV slot file per MemPalace
wing**:

```
~/.cache/genesi-turbo/slots/wing-<wing-id>.bin
```

- On opening/continuing a conversation in a wing: `/slots?action=restore` that
  wing's file → the core-memory KV is live without any prefill.
- After a turn (or periodically): `/slots?action=save` so the warm state
  survives a server restart / reboot.
- If the core memory for a wing changes (append-only edits), the bridge
  invalidates that wing's slot and lets the next turn rebuild + re-save it.

## Component: `genesi-mempalace bridge` (to build)

A small local proxy in front of the Turbo `llama-server` (`:11435`), exposing the
same OpenAI-style `/v1/chat/completions` the Monitor already uses. Per request it:

1. Resolves the **wing** (project / conversation id) from the request metadata.
2. Pulls the wing's **core memory** (stable, sorted) + **top-k recall** for the
   user message from MemPalace (via the CLI/MCP, local only).
3. Assembles the two-tier prompt above.
4. Restores the wing's KV slot if present, sets `cache_prompt: true`, forwards to
   `llama-server`, then saves the slot.
5. Streams the response back unchanged.

```
client ─▶ genesi-mempalace bridge ─▶ llama-server (Turbo :11435)
              │      ▲                     │
              ▼      │ recall/core         │ /slots save|restore
          MemPalace (local)            KV slots on disk (per wing)
```

The bridge is **additive and opt-in**. It does not modify `genesi-aid`'s
optimizer, the daemon's reversible-restore snapshot, or any `llama-server`
startup flag that ships today. With the bridge off (or MemPalace absent), Turbo
serves exactly as it does now.

## Expected effect (honest)

| Scenario | Effect |
|---|---|
| First prompt of a fresh conversation | No change (nothing cached yet) |
| 2nd+ turn of the same conversation | Lower TTFT — stable prefix KV reused (`--cache-reuse`) |
| Reopening a conversation after closing the app / reboot | **Prompt cold-start killed** — wing slot restored instead of re-prefilling the whole memory |
| Tokens/second (decode) | Unchanged (that's speculative decoding's job) |

The win is real but conditional on prefix stability — hence the two-tier design.
Validate with `genesi-ai-mode bench` on multi-turn and resumed conversations once
the bridge lands.

## Build checklist

- [x] `genesi-mempalace bridge` proxy (`/v1/chat/completions` → Turbo, stdlib-only)
- [x] Two-tier prompt assembly (stable core-memory prefix + small recall tail)
- [x] Per-wing KV slot save/restore via `/slots`
- [x] Core-memory change detection → slot invalidation (content hash + TTL)
- [ ] Tune the MemPalace recall calls to the installed CLI's real output
- [ ] Monitor toggle + TTFT-on-resume benchmark
