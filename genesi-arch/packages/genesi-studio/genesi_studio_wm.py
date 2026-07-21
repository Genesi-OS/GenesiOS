#!/usr/bin/env python3
"""
genesi_studio_wm — window/app enumeration across every desktop Genesi ships.

Studio Mode needs to answer two questions on any of the nine desktops the
Calamares chooser offers (KDE, Hyprland+caelestia, GNOME, Xfce4, Cinnamon,
Budgie, LXDE, Cosmic, Niri):

    1. what applications are running right now, and which PID is each one?
    2. which one does the user have focused?

There is NO portable answer. Every compositor exposes this differently, and one
of them (GNOME on Wayland) deliberately exposes nothing at all to third parties.
So this module is a set of per-DE backends behind one interface, ordered
best-first, with a /proc fallback that always works but reports *applications*
rather than *windows*.

    Backend        How                                   Windows?  Focus?
    ------------   -----------------------------------   --------  ------
    Hyprland       hyprctl -j clients / activewindow     yes       yes
    Niri           niri msg -j windows / focused-window  yes       yes
    Sway/wlroots   swaymsg -t get_tree                   yes       yes
    KWin (Plasma)  KWin script loaded over DBus          yes       yes
    X11 (EWMH)     wmctrl -lp + _NET_ACTIVE_WINDOW       yes       yes
    procfs         /proc scan matched to .desktop files  no (apps) no

The procfs fallback is what GNOME-Wayland and Cosmic land on today. It is
honestly weaker: it lists apps, cannot tell two windows of the same app apart,
and cannot report focus. Studio Mode degrades to "pick your app from a list"
there instead of "follow my focused window", which is why the UI never promises
focus-following unless `supports_focus()` is true.

Stdlib only — this runs inside a per-user daemon that must start on a bare
"No Desktop" install without dragging in Qt or python-xlib.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
import time

__all__ = ["Window", "detect_backend", "backend_for", "list_windows",
           "focused_window", "highlight_window", "clear_highlight"]


# ── data ─────────────────────────────────────────────────────────────────────
class Window:
    """One focusable thing. `handle` is backend-specific and opaque to callers.

    `pid` is what Studio Mode actually optimizes — everything downstream (nice,
    affinity, cgroup, freezing) is process-level, so a window with no resolvable
    pid is useless to us and gets dropped by the backends.

    `icon` and `name` are resolved from the desktop-entry index, so every UI can
    show the app's real icon and human name ("Firefox") instead of its raw
    window class ("firefox-esr"). They are best-effort: an app with no .desktop
    entry falls back to its app_id and a generic icon.
    """

    __slots__ = ("pid", "app_id", "title", "handle", "focused", "backend",
                 "icon", "name")

    def __init__(self, pid, app_id="", title="", handle=None, focused=False,
                 backend=""):
        self.pid = int(pid)
        self.app_id = app_id or ""
        self.title = title or ""
        self.handle = handle
        self.focused = bool(focused)
        self.backend = backend
        self.icon, self.name = desktop_lookup(self.app_id, self.pid)

    def as_dict(self):
        return {"pid": self.pid, "app_id": self.app_id, "title": self.title,
                "handle": self.handle, "focused": self.focused,
                "backend": self.backend, "icon": self.icon, "name": self.name}

    def __repr__(self):
        return f"<Window {self.app_id}:{self.pid} {self.title!r}>"


# ── desktop-entry index (icons + human names) ────────────────────────────────
_DESKTOP_DIRS = ("/usr/share/applications",
                 "/usr/local/share/applications",
                 os.path.expanduser("~/.local/share/applications"),
                 "/var/lib/flatpak/exports/share/applications",
                 os.path.expanduser(
                     "~/.local/share/flatpak/exports/share/applications"))

_desktop_index = None          # {match key -> (icon, name)}
_desktop_hidden = None         # {match key} for NoDisplay entries (agents)
_desktop_index_at = 0.0
_DESKTOP_TTL = 60.0            # apps get installed while the session runs


def _parse_desktop(path):
    """Pull Icon/Name/StartupWMClass/Exec out of a .desktop [Desktop Entry].

    Hand-parsed rather than via configparser: desktop files legitimately
    contain duplicate keys and '%' format codes that configparser rejects, and
    one bad file must not take the whole index down.
    """
    icon = name = wmclass = execline = ""
    nodisplay = False
    # Returned even for NoDisplay entries: the caller keeps their names in a
    # separate veto set, which is how background agents that legitimately talk
    # to the compositor (kded6, kaccess, xdg-desktop-portal) are kept out of
    # the app picker without resorting to name heuristics.
    try:
        with open(path, "r", errors="replace") as fh:
            in_entry = False
            for line in fh:
                line = line.strip()
                if line.startswith("["):
                    # Only the main group; action groups have their own names.
                    in_entry = line == "[Desktop Entry]"
                    continue
                if not in_entry or "=" not in line:
                    continue
                key, _, val = line.partition("=")
                key = key.strip()
                val = val.strip()
                if key == "Icon" and not icon:
                    icon = val
                elif key == "Name" and not name:      # plain Name, not Name[xx]
                    name = val
                elif key == "StartupWMClass" and not wmclass:
                    wmclass = val
                elif key == "Exec" and not execline:
                    execline = val
                elif key == "NoDisplay" and val.lower() == "true":
                    nodisplay = True
    except OSError:
        return None
    return icon, name, wmclass, execline, nodisplay


def _build_desktop_index():
    index, hidden = {}, set()

    def put(key, icon, name):
        key = (key or "").strip().lower()
        # First writer wins: /usr/share is scanned before ~/.local, but a more
        # specific match key (StartupWMClass) is registered before the looser
        # ones for the same file, so precision beats scan order.
        if key and key not in index:
            index[key] = (icon, name)

    for d in _DESKTOP_DIRS:
        try:
            entries = sorted(os.listdir(d))
        except OSError:
            continue
        for fn in entries:
            if not fn.endswith(".desktop"):
                continue
            parsed = _parse_desktop(os.path.join(d, fn))
            if not parsed:
                continue
            icon, name, wmclass, execline, nodisplay = parsed
            stem = fn[:-8]
            if nodisplay:
                # Not a user-facing app: record every name it could be matched
                # by, so the /proc backend can veto it, and index nothing.
                for key in (wmclass, stem, stem.split(".")[-1]):
                    if key:
                        hidden.add(key.strip().lower())
                if execline:
                    for tok in execline.split():
                        if not tok.startswith("%") and "=" not in tok:
                            hidden.add(os.path.basename(tok).strip().lower())
                            break
                continue
            if not icon and not name:
                continue
            # Most precise first: the app itself declares its window class.
            put(wmclass, icon, name)
            put(stem, icon, name)                    # org.kde.konsole
            put(stem.split(".")[-1], icon, name)     # konsole
            if execline:
                # The binary actually launched, minus wrappers and %-codes.
                for tok in execline.split():
                    if tok.startswith("%") or "=" in tok:
                        continue
                    base = os.path.basename(tok)
                    if base not in ("env", "sh", "bash", "flatpak", "sudo"):
                        put(base, icon, name)
                        break
    return index, hidden


def _desktop_index_get(want_hidden=False):
    global _desktop_index, _desktop_hidden, _desktop_index_at
    now = time.time()
    if _desktop_index is None or (now - _desktop_index_at) > _DESKTOP_TTL:
        try:
            _desktop_index, _desktop_hidden = _build_desktop_index()
        except Exception:
            _desktop_index = _desktop_index or {}
            _desktop_hidden = _desktop_hidden or set()
        _desktop_index_at = now
    return _desktop_hidden if want_hidden else _desktop_index


def desktop_lookup(app_id, pid=None):
    """(icon, display name) for a window class, falling back sensibly.

    Tries the window class, then its last dotted component, then the process
    name — a Wayland app_id like "org.mozilla.firefox", an X11 class like
    "Navigator" and a bare comm like "firefox" should all land on Firefox.
    """
    index = _desktop_index_get()
    tried = []
    if app_id:
        tried.append(app_id)
        if "." in app_id:
            tried.append(app_id.split(".")[-1])
        tried.append(app_id.replace(" ", "-"))
    if pid:
        comm = _comm(pid)
        if comm:
            tried.append(comm)
    for key in tried:
        hit = index.get(key.strip().lower())
        if hit:
            icon, name = hit
            return icon or "application-x-executable", name or app_id or key
    # No desktop entry: still give the UI something to render and to label.
    return "application-x-executable", app_id or (_comm(pid) if pid else "") or "?"


def _run(cmd, timeout=4):
    """Run a command, return stdout or "" — never raise into the daemon loop."""
    try:
        out = subprocess.run(cmd, capture_output=True, text=True,
                             timeout=timeout, check=False)
        return out.stdout if out.returncode == 0 else ""
    except Exception:
        return ""


def _jrun(cmd, timeout=4):
    """_run + JSON parse, or None."""
    txt = _run(cmd, timeout)
    if not txt.strip():
        return None
    try:
        return json.loads(txt)
    except Exception:
        return None


def _alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except Exception:
        return False


# ── backends ─────────────────────────────────────────────────────────────────
class _Backend:
    name = "none"

    def available(self):
        return False

    def supports_focus(self):
        return True

    def windows(self):
        return []

    def focused(self):
        for w in self.windows():
            if w.focused:
                return w
        return None

    # Compositor-native "this window is in Studio Mode" affordance. Only the
    # wlroots-family compositors let a third party recolor someone else's
    # window border, so the base implementation is a no-op and the UI falls
    # back to the panel widget as the only indicator.
    def highlight(self, win, color="1D9E75"):
        return False

    def unhighlight(self, win):
        return False


class HyprlandBackend(_Backend):
    """Hyprland (the caelestia session). Richest of the lot: hyprctl gives us
    windows, focus, AND per-window border colors for the Studio Mode outline."""

    name = "hyprland"

    def available(self):
        return bool(os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")) and \
            bool(shutil.which("hyprctl"))

    def windows(self):
        data = _jrun(["hyprctl", "-j", "clients"]) or []
        active = _jrun(["hyprctl", "-j", "activewindow"]) or {}
        active_addr = active.get("address")
        out = []
        for c in data:
            pid = c.get("pid") or 0
            if pid <= 0 or not _alive(pid):
                continue
            out.append(Window(
                pid=pid,
                app_id=c.get("class") or c.get("initialClass") or "",
                title=c.get("title") or "",
                handle=c.get("address"),
                focused=bool(active_addr and c.get("address") == active_addr),
                backend=self.name))
        return out

    def highlight(self, win, color="1D9E75"):
        if not win.handle:
            return False
        # activebordercolor takes rgba(RRGGBBAA); a solid Genesi green reads as
        # a deliberate outline rather than a theme glitch.
        _run(["hyprctl", "setprop", f"address:{win.handle}",
              "activebordercolor", f"rgba({color}ff)"])
        _run(["hyprctl", "setprop", f"address:{win.handle}",
              "inactivebordercolor", f"rgba({color}aa)"])
        _run(["hyprctl", "setprop", f"address:{win.handle}", "bordersize", "3"])
        return True

    def unhighlight(self, win):
        if not win.handle:
            return False
        for prop in ("activebordercolor", "inactivebordercolor", "bordersize"):
            _run(["hyprctl", "setprop", f"address:{win.handle}", prop, "unset"])
        return True


class NiriBackend(_Backend):
    """Niri (scrollable-tiling Wayland). `niri msg -j` is a stable JSON IPC."""

    name = "niri"

    def available(self):
        return bool(shutil.which("niri")) and (
            os.environ.get("NIRI_SOCKET") or
            os.environ.get("XDG_CURRENT_DESKTOP", "").lower().find("niri") >= 0)

    def windows(self):
        data = _jrun(["niri", "msg", "-j", "windows"]) or []
        out = []
        for w in data:
            pid = w.get("pid") or 0
            if pid <= 0 or not _alive(pid):
                continue
            out.append(Window(
                pid=pid,
                app_id=w.get("app_id") or "",
                title=w.get("title") or "",
                handle=w.get("id"),
                focused=bool(w.get("is_focused")),
                backend=self.name))
        return out


class SwayBackend(_Backend):
    """Generic wlroots/i3-compatible tree. Not a Genesi default DE, but it costs
    ~15 lines and makes the module useful on any sway-protocol compositor."""

    name = "sway"

    def available(self):
        return bool(shutil.which("swaymsg")) and bool(
            os.environ.get("SWAYSOCK"))

    def _walk(self, node, out):
        if node.get("pid") and node.get("type") in ("con", "floating_con") \
                and not node.get("nodes"):
            pid = node.get("pid")
            if pid > 0 and _alive(pid):
                out.append(Window(
                    pid=pid,
                    app_id=node.get("app_id") or
                    (node.get("window_properties") or {}).get("class", ""),
                    title=node.get("name") or "",
                    handle=node.get("id"),
                    focused=bool(node.get("focused")),
                    backend=self.name))
        for child in (node.get("nodes") or []) + (node.get("floating_nodes") or []):
            self._walk(child, out)

    def windows(self):
        tree = _jrun(["swaymsg", "-t", "get_tree"])
        out = []
        if tree:
            self._walk(tree, out)
        return out


# KWin has no window-list CLI. It DOES have org.kde.KWin.Scripting, which loads
# a JS snippet into the compositor — that script can see every window and write
# a JSON dump we then read back.
#
# The dump goes through XMLHttpRequest PUT to a file:// path rather than
# callDBus, because collecting a callDBus reply would mean owning a DBus service
# name, and this daemon is deliberately stdlib-only (no dbus-python / GLib).
# If a future KWin tightens the script sandbox and the PUT stops landing,
# windows() returns [] and detect_backend()'s caller degrades to procfs — the
# same place GNOME-Wayland already sits — rather than breaking Studio Mode.
_KWIN_SCRIPT = r"""
// Genesi Studio Mode — dump the window list for the session daemon.
var out = [];
var wins = (typeof workspace.windowList === "function")
    ? workspace.windowList()            // Plasma 6
    : workspace.clientList();           // Plasma 5 fallback
var active = workspace.activeWindow || workspace.activeClient;
for (var i = 0; i < wins.length; i++) {
    var w = wins[i];
    if (!w || !w.normalWindow) continue;
    out.push({
        pid: w.pid,
        app_id: w.resourceClass ? String(w.resourceClass) : "",
        title: w.caption ? String(w.caption) : "",
        handle: w.internalId ? String(w.internalId) : "",
        focused: (active && w.internalId && active.internalId)
                 ? String(active.internalId) === String(w.internalId) : false
    });
}
var req = new XMLHttpRequest();
req.open("PUT", "file://__DUMP__", false);
req.send(JSON.stringify(out));
"""


class KWinBackend(_Backend):
    """Plasma 6 Wayland. Loads a throwaway KWin script over DBus, reads its dump.

    Costs a DBus round-trip plus a script load per poll, so the daemon caches
    aggressively and polls slowly. On KDE-on-X11 the X11 backend is both cheaper
    and more reliable — but this class is checked first only when the session is
    Wayland (see available()).
    """

    name = "kwin"

    def available(self):
        if "KDE" not in os.environ.get("XDG_CURRENT_DESKTOP", "").upper():
            return False
        # On X11 let the EWMH backend win: it needs no compositor scripting.
        if os.environ.get("XDG_SESSION_TYPE", "").lower() != "wayland":
            return False
        return bool(self._qdbus())

    def _qdbus(self):
        return shutil.which("qdbus6") or shutil.which("qdbus")

    def windows(self):
        qdbus = self._qdbus()
        if not qdbus:
            return []
        dump = os.path.join(tempfile.gettempdir(),
                            f"genesi-studio-kwin-{os.getuid()}.json")
        script = _KWIN_SCRIPT.replace("__DUMP__", dump)
        path = os.path.join(tempfile.gettempdir(),
                            f"genesi-studio-kwin-{os.getuid()}.js")
        try:
            with open(path, "w") as fh:
                fh.write(script)
            sid = _run([qdbus, "org.kde.KWin", "/Scripting",
                        "org.kde.kwin.Scripting.loadScript", path]).strip()
            if sid:
                _run([qdbus, "org.kde.KWin", f"/Scripting/Script{sid}",
                      "org.kde.kwin.Script.run"])
                _run([qdbus, "org.kde.KWin", f"/Scripting/Script{sid}",
                      "org.kde.kwin.Script.stop"])
            with open(dump) as fh:
                data = json.load(fh)
        except Exception:
            return []
        finally:
            for p in (path, dump):
                try:
                    os.unlink(p)
                except Exception:
                    pass
        out = []
        for w in data or []:
            pid = w.get("pid") or 0
            if pid <= 0 or not _alive(pid):
                continue
            out.append(Window(pid=pid, app_id=w.get("app_id", ""),
                              title=w.get("title", ""), handle=w.get("handle"),
                              focused=bool(w.get("focused")),
                              backend=self.name))
        return out


class X11Backend(_Backend):
    """EWMH via wmctrl/xprop — covers Xfce4, Cinnamon, Budgie, LXDE, MATE and
    any X11 session including KDE-on-X11 (where it beats the KWin script)."""

    name = "x11"

    def available(self):
        return bool(os.environ.get("DISPLAY")) and bool(shutil.which("wmctrl")) \
            and bool(shutil.which("xprop"))

    def _active_id(self):
        txt = _run(["xprop", "-root", "_NET_ACTIVE_WINDOW"])
        m = re.search(r"(0x[0-9a-fA-F]+)", txt)
        return int(m.group(1), 16) if m else None

    def windows(self):
        active = self._active_id()
        out = []
        for line in _run(["wmctrl", "-lp"]).splitlines():
            # <id> <desktop> <pid> <host> <title...>
            parts = line.split(None, 4)
            if len(parts) < 5:
                continue
            try:
                wid, pid = int(parts[0], 16), int(parts[2])
            except ValueError:
                continue
            if pid <= 0 or not _alive(pid):
                continue
            out.append(Window(pid=pid, app_id=_comm(pid), title=parts[4],
                              handle=wid, focused=(active == wid),
                              backend=self.name))
        return out


def _comm(pid):
    try:
        with open(f"/proc/{pid}/comm") as fh:
            return fh.read().strip()
    except Exception:
        return ""


def _cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as fh:
            return fh.read().replace(b"\0", b" ").decode(errors="replace").strip()
    except Exception:
        return ""


def _display_socket_inodes():
    """Inodes of the compositor's listening sockets (Wayland and/or X11).

    A process with a window necessarily holds an open connection to the display
    server. That is a far better "is this a GUI app" test than matching process
    names against .desktop files, and it is the only signal available on the
    desktops that expose no window list at all (COSMIC, GNOME Wayland).

    Returns an empty set when /proc/net/unix is unreadable, in which case the
    caller keeps its name-matching behaviour rather than listing nothing.
    """
    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    wayland = os.environ.get("WAYLAND_DISPLAY") or "wayland-0"
    wanted = set()
    wl_path = wayland if wayland.startswith("/") \
        else os.path.join(runtime, wayland)
    try:
        with open("/proc/net/unix") as fh:
            next(fh, None)                    # header
            for line in fh:
                parts = line.split()
                if len(parts) < 8:
                    continue
                inode, path = parts[6], parts[7]
                # The Wayland socket, plus the X11 sockets that back XWayland
                # and every X11 session.
                if path == wl_path or path.startswith("/tmp/.X11-unix/X") \
                        or path.startswith("@/tmp/.X11-unix/X"):
                    wanted.add(inode)
    except Exception:
        return set()
    return wanted


def _has_display_connection(pid, display_inodes):
    """True when this process holds an open fd to the display server."""
    if not display_inodes:
        return False
    fddir = f"/proc/{pid}/fd"
    try:
        names = os.listdir(fddir)
    except OSError:
        return False                          # not ours / already gone
    for fd in names:
        try:
            target = os.readlink(os.path.join(fddir, fd))
        except OSError:
            continue
        if target.startswith("socket:["):
            if target[8:-1] in display_inodes:
                return True
    return False


class ProcBackend(_Backend):
    """Last resort: GNOME-Wayland and Cosmic, where no window list is exposed.

    Lists *applications*, inferred from the user's own processes that look like
    GUI apps: they are session children with a .desktop entry matching their
    binary name. It cannot report focus, so Studio Mode switches to explicit
    "pick the app" selection on these desktops.
    """

    name = "procfs"

    def available(self):
        return True

    def supports_focus(self):
        return False

    def windows(self):
        uid = os.getuid()
        # Two independent signals, because neither alone is good enough:
        #
        #   display connection — the process holds an fd to the Wayland/X11
        #     socket. Strong evidence it has a window, and the ONLY signal that
        #     works for an app with no .desktop entry. This is what stops the
        #     list being full of daemons.
        #   desktop entry      — gives the icon and the human name, and its
        #     NoDisplay flag excludes background agents that DO connect to the
        #     display (kded6, kaccess, portals) but are not user applications.
        #
        # Require the connection; use the entry to name and to veto.
        known = _desktop_index_get()
        agents = _desktop_index_get(want_hidden=True)
        display_inodes = _display_socket_inodes()
        out, seen = [], set()
        for entry in os.listdir("/proc"):
            if not entry.isdigit():
                continue
            pid = int(entry)
            try:
                if os.stat(f"/proc/{pid}").st_uid != uid:
                    continue
                comm = _comm(pid)
            except Exception:
                continue
            if not comm or comm in seen:
                continue
            connected = _has_display_connection(pid, display_inodes)
            indexed = comm.lower() in known
            if display_inodes:
                # A real GUI app talks to the compositor. Anything that also
                # has a visible desktop entry is certainly one; anything with
                # no entry at all is still listed (unpackaged binaries, AppImages
                # and games launched straight from Steam have no .desktop we can
                # match), but a process whose entry says NoDisplay is dropped.
                if not connected:
                    continue
                if comm.lower() in agents:
                    continue
            elif not indexed:
                # No /proc/net/unix (hardened kernel): fall back to the old
                # name-matching behaviour rather than listing nothing at all.
                continue
            seen.add(comm)
            out.append(Window(pid=pid, app_id=comm, title=_cmdline(pid)[:120],
                              handle=None, focused=False, backend=self.name))
        return out


_BACKENDS = [HyprlandBackend, NiriBackend, SwayBackend, KWinBackend,
             X11Backend, ProcBackend]

_cached = None


def detect_backend(force=None):
    """Pick the best backend for this session (cached; pass force to re-pick).

    Ordering matters: the Wayland-native IPCs come first because they are both
    cheaper and richer than the KWin script, and procfs is last because it is
    always `available()`.
    """
    global _cached
    if _cached is not None and not force:
        return _cached
    for cls in _BACKENDS:
        b = cls()
        try:
            if b.available():
                _cached = b
                return b
        except Exception:
            continue
    _cached = ProcBackend()
    return _cached


def backend_for(name):
    """Explicit backend by name — used by the CLI's --backend escape hatch."""
    for cls in _BACKENDS:
        if cls.name == name:
            return cls()
    return None


_empty_polls = 0
_EMPTY_LIMIT = 3


def list_windows():
    """Windows from the active backend, with a demotion guard.

    A backend can be `available()` yet return nothing forever — the KWin script
    path is the realistic case (a tightened script sandbox swallows the dump).
    Rather than leaving Studio Mode blind, three consecutive empty polls demote
    the session to procfs, which lists apps instead of windows but always works.
    A real session always has at least one window, so this cannot misfire on a
    healthy backend.
    """
    global _cached, _empty_polls
    b = detect_backend()
    try:
        wins = b.windows()
    except Exception:
        wins = []
    if wins:
        _empty_polls = 0
        return wins
    if b.name != ProcBackend.name:
        _empty_polls += 1
        if _empty_polls >= _EMPTY_LIMIT:
            _cached = ProcBackend()
            _empty_polls = 0
            try:
                return _cached.windows()
            except Exception:
                return []
    return []


def focused_window():
    b = detect_backend()
    if not b.supports_focus():
        return None
    try:
        return b.focused()
    except Exception:
        return None


def highlight_window(win, color="1D9E75"):
    try:
        return detect_backend().highlight(win, color)
    except Exception:
        return False


def clear_highlight(win):
    try:
        return detect_backend().unhighlight(win)
    except Exception:
        return False


if __name__ == "__main__":
    b = detect_backend()
    print(f"backend: {b.name} (focus={'yes' if b.supports_focus() else 'no'})")
    for w in list_windows():
        print(f"  {'*' if w.focused else ' '} {w.pid:>7}  {w.app_id:<24} {w.title[:60]}")
