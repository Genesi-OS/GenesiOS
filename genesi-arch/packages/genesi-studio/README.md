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

## Frozen, not closed

Closing background apps would be the crude way to free a machine, and it loses
unsaved work: "restore" could only ever relaunch the app, never its open
documents. Studio Mode freezes instead — cgroup v2 `cgroup.freeze`, with
SIGSTOP on the process tree as a fallback. A frozen process is not scheduled at
all (the same CPU and GPU relief as closing it) but keeps its memory and its
state. Thawing puts you back mid-sentence.

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

Machine-wide: the CPU governor and EPP go to `performance` — but **only if AI
Mode is not already holding them**. `genesi-aid` owns the same sysfs knobs and
restores them from its own captured baseline; two daemons writing the same file
would fight and the loser's restore would write a stale value. The helper checks
and stands down, reporting `ai-mode-owns-cpu`.

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

The `/proc` backend identifies applications by requiring an **open connection to
the display server** (an fd onto the Wayland or X11 socket), then vetoes anything
whose desktop entry is `NoDisplay`. The connection test is what separates apps
from daemons; the veto is what removes the background agents that legitimately
connect anyway (`kded6`, `kaccess`, portals). Name matching alone listed those
agents as if they were the user's apps.

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

## Status

Shipped **unvalidated on hardware** — every backend, the freeze path and the
privileged levers need a real session to prove out. The safety logic
(`test-studio-safety.py`) is tested and green.
