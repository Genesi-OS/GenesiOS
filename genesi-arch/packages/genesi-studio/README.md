# Genesi Studio Mode

Give the whole machine to one app.

Studio Mode takes the app you are working in — a game, Genesi Code, Blender, a
DAW — and makes the rest of the system get out of its way: the focused app gets
priority, the fastest cores and the largest share of CPU and I/O, while every
other open application is **frozen**. Turn it off and everything comes back
exactly as it was.

```
genesi-studio on                 # the focused window gets the machine
genesi-studio on blender         # …or name the app
genesi-studio on genesi-code firefox   # …or several at once
genesi-studio off                # thaw everything, restore every lever
genesi-studio info               # what it is doing right now
genesi-studio list               # what is open, and what is focused
```

## Held back, not closed

Closing background apps would be the crude way to free a machine, and it loses
unsaved work: "restore" could only ever relaunch the app, never its open
documents. So Studio Mode never closes anything.

By default it **throttles**: each background app is reniced to +19 with its I/O
in the idle class, so it keeps running but sits at the very bottom of the queue
while the focused app takes the machine. Throttling (rather than a true freeze)
is deliberate — a frozen Wayland client cannot answer the compositor's ping, so
Hyprland, KWin and Mutter mark it "not responding" and pop a wait/force-quit
dialog over every paused window.

A literal zero-CPU freeze (cgroup `cgroup.freeze` / SIGSTOP) is still available
for X11 users who want it and do not mind those dialogs:

```bash
genesi-studio set suspend_method=freeze   # default is "throttle"
```

Either way the app keeps its memory and its state, and returns to full speed
exactly where it was.

Apps you launch **after** switching Studio Mode on are never frozen. The freeze
set is a snapshot taken at activation, because silently freezing a window the
moment it appears would be indistinguishable from a hang.

## What is never frozen

Freezing the compositor would freeze the desktop — including the widget you
would use to turn Studio Mode off. So freezing is restricted twice:

* only processes that **own a window** are candidates, never background daemons;
* and a protected set is excluded even if it has a window: compositors and
  shells (`plasmashell`, `kwin`, `Hyprland`, `gnome-shell`, `xfwm4`, `cinnamon`,
  `budgie-panel`, `lxqt-panel`, `cosmic-comp`, `niri`, `quickshell`), session
  infrastructure (systemd, dbus, pipewire, portals, polkit, keyring), the
  display manager, and Genesi's own daemons.

Add your own exceptions — a music player, a chat client, a running build:

```
genesi-studio set never_freeze=spotify,discord,element
```

These rules are covered by `test-studio-safety.py`, which runs at package build
time, because getting them wrong is the difference between "background apps
pause" and "the desktop locks up".

## The levers

Per focused process, applied by the root helper:

| Lever | Effect |
| --- | --- |
| `nice -10` | wins the run queue under contention |
| `ionice` best-effort 0 | I/O ahead of background work |
| CPU affinity | pinned to the fastest cores (P-cores on a hybrid CPU) |
| `cpu.weight` / `io.weight` = 400 | 4x share of a saturated machine |
| `oom_score_adj -500` | the last thing the kernel kills |

The first three are applied to **every thread**, not to the process. nice,
ionice and affinity are per-thread on Linux, so setting them on the tgid moved
the main thread and nothing else — and a game does its real work off the main
thread (Minecraft renders and builds chunks on other threads), which made the
whole per-process boost close to a no-op. The thread list is a snapshot: threads
the app spawns afterwards run at their inherited priority.

The cgroup levers apply **only when the app has a cgroup to itself**. `cpu.weight`
and `io.weight` are shares against siblings inside the same parent, so an app
launched straight from the compositor — which lands in the shared
`session-N.scope` next to the compositor and everything else the session started
— gains nothing from them, and `memory.swap.max`/`memory.low` there would rewrite
the memory policy of the whole session as a side effect. In that case the helper
logs the skip instead of applying a lever that does nothing. "Its own" is a
question about the cgroup, not about the boosted process's place in it — the
window's pid is usually a leaf, several levels under the launcher script that
roots the scope.

Machine-wide: the CPU governor, EPP, `swappiness` and the GPU's performance
state — but **per lever, standing down from whichever ones AI Mode is holding**.
`genesi-aid` writes the same sysfs knobs and restores them from its own captured
baseline; two daemons writing one file would fight and the loser's restore would
write a stale value. So the helper reads `genesi-aid`'s published lever list and
skips exactly those, reporting `ai-mode-owns:<levers>`.

Ownership used to be all-or-nothing, and that was a real bug: a warm `ollama` in
the background made Studio Mode stand down from **every** global knob including
the GPU — the one lever that matters to a game, and one `genesi-aid` may not
even be holding. NVIDIA never collides at all: `genesi-aid` drives `nvidia-smi`
(persistence, power limit, locked clocks) while Studio Mode drives
`nvidia-settings` (PowerMizer mode).

I/O priority is deliberately best-effort and **not** realtime: an RT I/O class
can starve journald and systemd and wedge the desktop — exactly the outcome
Studio Mode exists to prevent.

## Desktop coverage

The window list is per-compositor, so `genesi_studio_wm.py` carries a backend
for each, best-first:

| Desktop | Backend | Window list | Focus tracking |
| --- | --- | --- | --- |
| Hyprland + caelestia | `hyprctl -j` | yes | yes (+ green window border) |
| Niri | `niri msg -j` | yes | yes |
| Sway / wlroots | `swaymsg` | yes | yes |
| KDE Plasma (Wayland) | KWin script over DBus | yes | yes |
| KDE / Xfce / Cinnamon / Budgie / LXDE / MATE (X11) | EWMH via `wmctrl` | yes | yes |
| GNOME (Wayland) | `/proc` scan **+ the Shell extension** | apps only | yes, via the extension |
| Cosmic | `/proc` scan | apps only | no |

The `/proc` backend identifies applications by matching a process against a
**visible desktop entry** (its executable, `comm`, or launched command line),
and vetoes anything whose entry is `NoDisplay` — that veto is what keeps the
background agents (`kded6`, `kaccess`, portals) out of the picker. It is a
heuristic and misses apps with no `.desktop` (Steam games, AppImages); that is
the honest ceiling on a desktop with no window list.

Crucially, this fallback should almost never be what you actually run: the
session daemon has no `DISPLAY`/`WAYLAND_DISPLAY` of its own (it is a
`systemd --user` service, which does not inherit the graphical environment), so
on startup it **harvests those variables from a session-owned compositor
process** and splices them in. Without that step every real backend fails its
`available()` check and the session drops to `procfs` — which was the original
"Backend: procfs, nothing found" bug on KDE.

Full focus-following on COSMIC would need a Wayland toplevel client. Note that
neither `ext-foreign-toplevel-list-v1` nor `cosmic-toplevel-info-v1` exposes a
**PID** — they carry title, app_id and (for the COSMIC one) activated state — so
such a client would still have to bridge app_id back to a process. Everything
Studio Mode does is process-level, so that bridge, not the protocol, is the real
work. The tray widget already runs on COSMIC via `cosmic-panel`'s status area,
which implements the StatusNotifierItem host.

GNOME on Wayland exposes no window list to third parties at all, which is why
the GNOME Shell extension matters: running inside the shell, it can read the
real focused window and hand its PID to the CLI. Without it, Studio Mode on
GNOME degrades to picking an app from a list.

If a backend claims to be available but returns nothing three polls in a row —
the realistic case being a future KWin that tightens its script sandbox — the
session is demoted to the `/proc` backend rather than going blind.

## Architecture

```
genesi-studio        CLI — the one control path every widget uses
genesi-studiod       per-user daemon: windows, freezing, restore, state.json
genesi-studio-helperd  root helper: the privileged levers, and nothing else
```

The split exists for security. Freezing your own processes needs no privilege,
so the session daemon never runs as root. The levers that do need root live in
a helper whose entire control surface is one unix socket, where every request
is authenticated with `SO_PEERCRED` — a kernel-supplied credential the caller
cannot forge — and a non-root caller may only name PIDs it owns. (Contrast
`genesi-ai-mode`, whose world-writable flag file is fine because the only thing
you can write is on/off for the whole machine; Studio Mode's surface takes
PIDs, which an unauthenticated file would let anyone aim at anyone.)

## Crash safety

Frozen processes outlive the daemon — freeze state lives in the kernel. So:

* the undo record is written to `~/.local/state/genesi-studio/session.json`
  **before** anything is frozen;
* a starting daemon that finds a stale session file thaws everything first;
* the systemd unit thaws on stop (`ExecStopPost`), and the daemon thaws on
  SIGTERM;
* the root helper restores its baselines on shutdown, and unwinds stale ones
  from a previous run before taking new ones.

A user should never end up with a permanently paused app because a Python
process died.

## Widgets

All three read the same `state.json` and drive the same CLI, so they cannot
disagree about what Studio Mode is doing:

* **KDE** — Plasma 6 widget, "Genesi Studio Mode" (add it to a panel)
* **GNOME** — Shell extension `genesi-studio@genesios.org`
* **everything else** — `genesi-studio-tray`, a libayatana-appindicator tray,
  autostarted on every desktop except KDE and GNOME. Cosmic is covered here too,
  via `cosmic-panel`'s status area (SNI). A native libcosmic applet is possible
  later but is not needed for the feature to work.

The tray is appindicator and not Qt for the reason `genesi-ai-tray` documents:
Qt 6.11's StatusNotifierItem never serves its properties to the caelestia
(Quickshell) bar, so the icon simply never appears.

## What Studio Mode cannot do

Every lever here is CPU, I/O and memory. They pay off on a **contended** machine
— many apps fighting for a saturated CPU. They do nothing for a machine that has
CPU to spare and is waiting on its GPU: `cpu.weight` is a share of a queue that
is empty, and `nice` reorders a run queue nobody is waiting in. On a desktop
already running Genesi's `ananicy-cpp` (which classifies games and reapplies its
own nice) and already sitting on the `performance` governor, the CPU levers are
close to a no-op by the time Studio Mode gets there.

If a game drops frames with plenty of CPU idle, look at the GPU first — and
note that a **model loaded in VRAM** by AI Mode is not something Studio Mode
touches: `ollama` and `llama-server` are daemons with no window, so they are
never freeze or throttle candidates, and their VRAM is not a lever this daemon
owns.

## Status

Shipped **unvalidated on hardware** — every backend, the freeze path and the
privileged levers need a real session to prove out. The safety logic
(`test-studio-safety.py`) is tested and green.
