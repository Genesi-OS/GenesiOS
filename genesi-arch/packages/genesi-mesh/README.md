# Genesi Mesh

Pool the GPU memory of several machines on your LAN so a model that fits on
none of them individually still runs accelerated.

> Your old PC becomes extra VRAM.

## What it actually does

llama.cpp can already treat a remote GPU as an extra device through its **RPC
backend**:

```
machine A (client)                      machine B (worker)
llama-server --rpc B:50052   ───────►   rpc-server -H 0.0.0.0 -p 50052
  holds the model, serves the API         contributes its GPU
```

What it does *not* do is find machines, prove they are yours, keep the worker
alive, or decide whether pooling is a good idea. That is this package.

Genesi Mesh never touches inference itself and is never in the data path — a
`genesi-meshd` restart cannot interrupt a running generation.

## Honest expectations

**Pooling is not a speed-up.** Every token's activations cross the network, so
spreading a model that already fits your GPU makes it *slower*. The payoff is
binary: a model that could not run at all, runs.

`genesi-ai-turbo` encodes exactly that rule — it pools only when the model does
not fit locally but does fit across the mesh, and tells you why either way:

```
$ genesi-mesh plan qwen3-30b-a3b-Q4_K_M.gguf
Model 17.3 GB
  local VRAM budget:  6.8 GB
  pooled across mesh: 13.6 GB

  → run locally
    too big even pooled (17.3 GB needed, 13.6 GB across the mesh)
```

Gigabit Ethernet is the realistic floor. Wi-Fi works but hurts. MoE models
(`qwen3:30b-a3b`, `gpt-oss:20b`) suit pooling best: only a few experts fire per
token, so far less crosses the wire than for a dense model of the same size.

## Requirements

A llama.cpp built with `GGML_RPC=ON`:

```bash
sudo pacman -Syu genesi-llama-cpp        # Vulkan, any GPU  (>= r0-4)
sudo pacman -Syu genesi-llama-cpp-cuda   # NVIDIA + CUDA    (>= r0-2)
```

`genesi-mesh doctor` tells you plainly if anything is missing.

## Setup

**First machine:**

```bash
sudo systemctl enable --now genesi-meshd
sudo genesi-mesh init          # creates the mesh secret, prints it
sudo genesi-mesh worker on     # offer this machine's GPU
```

**Every other machine:**

```bash
sudo systemctl enable --now genesi-meshd
sudo genesi-mesh join <secret>
sudo genesi-mesh worker on
```

**Check it:**

```bash
genesi-mesh status
genesi-mesh peers
```

From then on `genesi-ai-turbo serve` uses the mesh by itself when a model needs
it. Nothing else to configure.

## Only have one machine?

`selftest` runs the identical code path against your own GPU over loopback — a
real `rpc-server`, a real client connection, no mocks:

```bash
genesi-mesh selftest
```

If that passes, the only thing a second machine adds is the network hop.

## Security

`rpc-server` upstream performs **no authentication and no validation** of what
it receives. Treat it as you would an unauthenticated database port.

- Worker mode is **off by default**; a machine never offers its GPU on its own.
- `rpc_bind` defaults to `127.0.0.1`. `genesi-mesh worker on` moves it to
  `0.0.0.0` and warns while doing it.
- Discovery beacons are **HMAC-SHA256 signed** with a shared secret, so only
  your machines see each other. That authenticates *discovery*, not the RPC
  port — it is not a substitute for running this on a network you control.
- Beacons carry a timestamp and are rejected outside a ±180 s window, so a
  captured beacon cannot resurrect a machine that is gone.

Do not enable worker mode on a public, café, or campus network.

## Files

| Path | Purpose |
|---|---|
| `/etc/genesi-mesh/mesh.conf` | node configuration |
| `/etc/genesi-mesh/secret` | shared mesh secret (0600, created by `init`/`join`) |
| `/run/genesi-mesh/peers.json` | live peer table (read by Turbo) |
| `/run/genesi-mesh/state.json` | this node's status |

## Environment overrides (Turbo)

| Variable | Effect |
|---|---|
| `GENESI_TURBO_NO_MESH=1` | never use the mesh |
| `GENESI_MESH_ENDPOINTS=host:port,...` | force these endpoints (skips discovery) |

Useful when peers are on another subnet or reachable only over a VPN.
