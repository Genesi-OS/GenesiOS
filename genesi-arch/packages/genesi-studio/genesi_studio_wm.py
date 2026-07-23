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


def _norm_key(s):
    """Canonical match key: lowercase, and '_' folded to '-'.

    Qt derives an app's WM_CLASS from its binary name, so the AI Mode Monitor
    presents as "Genesi_ai_monitor" while its desktop entry is
    genesi-ai-monitor. Without folding the separator those never met, and every
    Genesi Python/QML app resolved to a generic icon and a raw class name.
    """
    return (s or "").strip().lower().replace("_", "-")


def _build_desktop_index():
    index, hidden = {}, set()

    def put(key, icon, name):
        key = _norm_key(key)
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
                        hidden.add(_norm_key(key))
                if execline:
                    for tok in execline.split():
                        if not tok.startswith("%") and "=" not in tok:
                            hidden.add(_norm_key(os.path.basename(tok)))
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
                    if base.lower() in _EXEC_NOT_IDENTITY:
                        # This entry only BORROWS the binary (a launcher that
                        # opens a terminal, or an interpreter). Indexing it
                        # would hand that binary's identity to the launcher —
                        # which is how a plain Konsole window ended up labelled
                        # "Genesi DEV: NVIDIA + CUDA (test)", the name of a
                        # .desktop that merely runs `konsole -e ...`.
                        break
                    put(base, icon, name)
                    break
    return index, hidden


# Binaries a .desktop may invoke without BEING that binary: terminals it opens
# a command in, and interpreters it runs a script with.
_EXEC_NOT_IDENTITY = {
    "env", "sh", "bash", "zsh", "fish", "sudo", "pkexec", "flatpak",
    "konsole", "gnome-terminal", "xfce4-terminal", "xterm", "uxterm",
    "alacritty", "kitty", "foot", "wezterm", "terminator", "tilix",
    "x-terminal-emulator", "lxterminal", "mate-terminal", "ptyxis",
    "python", "python3", "node", "electron", "java", "ruby", "perl",
    "wine", "steam", "gamescope", "mangohud",
}


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
        # exe basename / comm / launched command — see _app_names(). This is
        # what lets an app whose window class says nothing useful still find
        # its icon via the binary the user actually started.
        tried.extend(_app_names(pid))
    for key in tried:
        hit = index.get(_norm_key(key))
        if hit:
            icon, name = hit
            return icon or "application-x-executable", name or app_id or key
    # No desktop entry: still give the UI something to render and to label.
    fallback = app_id or (_exe_name(pid) or _comm(pid) if pid else "") or "?"
    return "application-x-executable", fallback


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


def _pid_for_wm_class(wm_class):
    """Best-effort PID for a window that never advertised _NET_WM_PID.

    That property is a convention, not a guarantee: some toolkits and some
    Electron builds never set it, and wmctrl then prints 0 or -1 for the pid.
    Dropping those windows would silently hide real applications — the exact
    failure mode this backend has already been bitten by twice — so fall back
    to matching the window class against the user's own processes.

    Returns 0 when nothing matches, and the caller drops the window then: every
    lever Studio Mode has is process-level, so a window with no resolvable
    process genuinely cannot be acted on.
    """
    if not wm_class or wm_class == "N/A":
        return 0
    want = {_norm_key(wm_class),
            _norm_key(wm_class.split(".")[-1]),
            _norm_key(wm_class.split(".")[0])}
    want.discard("")
    uid = os.getuid()
    best = 0
    try:
        entries = os.listdir("/proc")
    except OSError:
        return 0
    for entry in entries:
        if not entry.isdigit():
            continue
        pid = int(entry)
        try:
            if os.stat(f"/proc/{pid}").st_uid != uid:
                continue
        except OSError:
            continue
        if any(_norm_key(n) in want for n in _app_names(pid)):
            # Lowest pid wins: for a multi-process app (Electron spawns a tree)
            # that is the main process, which is the one worth boosting.
            if not best or pid < best:
                best = pid
    return best


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
        # `wmctrl -lxp` columns are:
        #     <id> <desktop> <pid> <wm_class> <host> <title>
        # PID comes BEFORE WM_CLASS. Getting this backwards made int() raise on
        # every line, so the backend returned an empty list forever and the
        # session fell through to procfs — the "it only ever finds Firefox"
        # bug. Verified against real output:
        #     0x01600012 -1 926 plasmashell.plasmashell host Área de trabalho
        #
        # WM_CLASS ("instance.Class") is the real X11 app identity and matches a
        # .desktop StartupWMClass, so an app whose comm is generic or truncated
        # (python3 for the Qt apps, a wrapper for the editor) still resolves to
        # the right name and icon.
        for line in _run(["wmctrl", "-lxp"]).splitlines():
            parts = line.split(None, 5)
            # A window with an EMPTY title yields only 5 fields, so requiring 6
            # silently dropped those windows entirely. Accept 5 and treat the
            # title as blank.
            if len(parts) < 5:
                continue
            try:
                wid, pid = int(parts[0], 16), int(parts[2])
            except ValueError:
                continue
            wm_class = parts[3]
            if pid <= 0:
                # No _NET_WM_PID on this window — recover the process from its
                # class rather than dropping a real app from the list.
                pid = _pid_for_wm_class(wm_class)
            if pid <= 0 or not _alive(pid):
                continue
            # "navigator.Firefox" → prefer the Class half for app_id; Window
            # resolves the icon/name from it plus the pid's exe as a fallback.
            app_id = wm_class.split(".")[-1] if wm_class and wm_class != "N/A" \
                else _comm(pid)
            title = parts[5] if len(parts) > 5 else ""
            out.append(Window(pid=pid, app_id=app_id, title=title,
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


def _exe_name(pid):
    """Basename of the real executable, or "" .

    Preferred over /proc/PID/comm because comm is truncated to 15 characters
    (TASK_COMM_LEN) — an app called "genesi-code-helper" arrives as
    "genesi-code-hel" and matches no desktop entry at all. It is also stable
    for apps that rewrite their own comm (Electron, Steam games).
    """
    try:
        return os.path.basename(os.readlink(f"/proc/{pid}/exe"))
    except OSError:
        return ""


def _app_names(pid):
    """Every plausible identity for a process, best first.

    comm is truncated and can be rewritten; the exe basename is exact but is a
    wrapper for interpreted apps (electron, python3); the first cmdline token
    is what the user actually launched. Trying all three is what makes an
    Electron app, a Python app and a plain binary all resolve to one entry.
    """
    names = []
    exe = _exe_name(pid)
    if exe:
        names.append(exe)
    comm = _comm(pid)
    if comm and comm not in names:
        names.append(comm)
    cmd = _cmdline(pid).split()
    if cmd:
        first = os.path.basename(cmd[0])
        if first and first not in names:
            names.append(first)
        # `electron /opt/genesi-code/app` — the script path names the app.
        if len(cmd) > 1 and first in ("electron", "python3", "python", "node",
                                      "sh", "bash", "env"):
            arg = os.path.basename(cmd[1].rstrip("/"))
            if arg and not arg.startswith("-") and arg not in names:
                names.append(arg)
    return names


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
        # Identify a GUI app by a VISIBLE desktop entry (NoDisplay entries are
        # background agents and are vetoed). This is a heuristic — it misses
        # apps with no .desktop (Steam games, AppImages) — but it is the honest
        # ceiling on a desktop that exposes no window list, and it is far better
        # than the alternatives: matching process names alone lets daemons
        # through, and an earlier attempt to require an open display-socket fd
        # was worse still (a client's socket fd has a different inode from the
        # server's listening socket, so nothing ever matched → an empty list).
        known = _desktop_index_get()
        agents = _desktop_index_get(want_hidden=True)
        out, seen = [], set()
        for entry in sorted(os.listdir("/proc"), key=lambda e: int(e)
                            if e.isdigit() else 0):
            if not entry.isdigit():
                continue
            pid = int(entry)
            try:
                if os.stat(f"/proc/{pid}").st_uid != uid:
                    continue
            except Exception:
                continue
            names = _app_names(pid)
            if not names:
                continue
            # Group by the real executable, not by comm: comm is truncated to
            # 15 chars and Electron/Chromium apps rewrite it per child process,
            # so deduping on it both split one app into several rows and hid
            # apps whose name is longer than the limit. The lowest pid for an
            # executable is its main process, and /proc is walked in pid order,
            # so the first hit is the one to keep.
            key = _exe_name(pid) or names[0]
            if key in seen:
                continue
            # Same separator folding the index uses, or a process named with
            # underscores would never match its hyphenated desktop entry.
            lowered = [_norm_key(n) for n in names]
            if any(n in agents for n in lowered):
                continue                     # NoDisplay: a background agent
            if not any(n in known for n in lowered):
                continue                     # no visible desktop entry
            seen.add(key)
            out.append(Window(pid=pid, app_id=names[0],
                              title=_cmdline(pid)[:120],
                              handle=None, focused=False, backend=self.name))
        return out


_BACKENDS = [HyprlandBackend, NiriBackend, SwayBackend, KWinBackend,
             X11Backend, ProcBackend]

_cached = None

# ── session environment harvest ──────────────────────────────────────────────
# Every backend's available() reads a session env var: X11 wants DISPLAY,
# Hyprland wants HYPRLAND_INSTANCE_SIGNATURE, Wayland wants WAYLAND_DISPLAY, and
# so on. But genesi-studiod runs as a systemd --user service, which does NOT
# inherit those from the graphical session — so without help EVERY real backend
# fails its check and detection falls all the way through to procfs. That is
# exactly the "Backend: procfs, nothing found" symptom on a normal desktop.
#
# So before detecting, borrow the session env from a GUI process the user
# already owns (a compositor or panel is guaranteed to have the full set) and
# splice the display vars into our own environ. This is DE-agnostic and works
# regardless of whether the service was wired to graphical-session.target.
_SESSION_ENV_KEYS = (
    "DISPLAY", "WAYLAND_DISPLAY", "XAUTHORITY",
    "XDG_CURRENT_DESKTOP", "XDG_SESSION_TYPE", "XDG_SESSION_DESKTOP",
    "HYPRLAND_INSTANCE_SIGNATURE", "NIRI_SOCKET", "SWAYSOCK",
    "DBUS_SESSION_BUS_ADDRESS",
)
# A session-owned GUI process guaranteed to carry the full env. Harvesting from
# one of these (rather than the first random match) avoids picking up a stray
# short-lived helper with a partial environment.
_ENV_DONORS = ("plasmashell", "kwin_wayland", "kwin_x11", "Hyprland",
               "gnome-shell", "cosmic-comp", "niri", "sway", "xfwm4",
               "cinnamon", "marco", "kwin", "quickshell", "waybar")
_env_ok = False
_env_last = 0.0


def _read_environ(pid):
    try:
        with open(f"/proc/{pid}/environ", "rb") as fh:
            raw = fh.read()
    except OSError:
        return {}
    env = {}
    for chunk in raw.split(b"\0"):
        if b"=" in chunk:
            k, _, v = chunk.partition(b"=")
            env[k.decode(errors="replace")] = v.decode(errors="replace")
    return env


def ensure_session_env():
    """Splice the session's display env into this process. Returns True if it
    just changed the environment (so callers can invalidate a cached backend)."""
    global _env_ok, _env_last
    if _env_ok:
        return False
    # Already have a display connection? (interactive run, or systemd imported
    # the graphical environment for us.)
    if os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY"):
        _env_ok = True
        return False
    # The daemon polls a few times a second; a full /proc environ scan that
    # often is wasteful, and early in login the donors may not be up yet.
    now = time.time()
    if now - _env_last < 3.0:
        return False
    _env_last = now

    uid = os.getuid()
    donor_env = None
    fallback_env = None
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        try:
            if os.stat(f"/proc/{pid}").st_uid != uid:
                continue
        except OSError:
            continue
        comm = _comm(pid)
        if comm in _ENV_DONORS:
            env = _read_environ(pid)
            if env.get("WAYLAND_DISPLAY") or env.get("DISPLAY"):
                donor_env = env
                break
        elif fallback_env is None:
            # Any owned process with a display var, as a backstop for a DE whose
            # compositor comm is not in the donor list.
            env = _read_environ(pid)
            if env.get("WAYLAND_DISPLAY") or env.get("DISPLAY"):
                fallback_env = env
    env = donor_env or fallback_env
    if not env:
        return False
    for k in _SESSION_ENV_KEYS:
        if env.get(k) and not os.environ.get(k):
            os.environ[k] = env[k]
    _env_ok = True
    return True


def detect_backend(force=None):
    """Pick the best backend for this session (cached; pass force to re-pick).

    Ordering matters: the Wayland-native IPCs come first because they are both
    cheaper and richer than the KWin script, and procfs is last because it is
    always `available()`.
    """
    global _cached
    # Borrow the session's display env if we don't have it yet. If it just
    # appeared, drop any cached pick (it would be a stale procfs chosen before
    # the env was available) and re-detect.
    if ensure_session_env():
        _cached = None
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


_last_backend = None       # whichever backend produced the most recent result


def list_windows():
    """Windows from the best available backend, with a PER-CALL fallback.

    An earlier version demoted the session to procfs permanently after three
    consecutive empty polls, on the assumption that "a real session always has
    at least one window". That assumption is false at exactly the moment it
    mattered: the daemon starts at login, BEFORE any application window exists,
    so every session burned its three strikes in the first six seconds and then
    ran on procfs — listing daemons instead of windows and losing focus
    tracking — until the daemon was restarted by hand. An empty window list is
    a legitimate answer, not evidence of a broken backend.

    So nothing is demoted permanently. If the preferred backend yields nothing,
    procfs is consulted for THIS CALL only (which still covers the case it was
    meant for: a KWin whose script sandbox swallows the dump), and the
    preferred backend is retried on the very next poll.
    """
    global _last_backend
    b = detect_backend()
    try:
        wins = b.windows()
    except Exception:
        wins = []
    if wins:
        _last_backend = b
        return wins
    if b.name != ProcBackend.name:
        try:
            alt = ProcBackend().windows()
        except Exception:
            alt = []
        if alt:
            _last_backend = ProcBackend()
            return alt
    _last_backend = b
    return wins


def active_backend():
    """The backend that produced the most recent list_windows() result.

    What the UI should report: detect_backend() alone can disagree with what
    actually answered (the per-call procfs fallback above), and a widget that
    claims focus tracking it does not have is worse than one that admits it.
    """
    return _last_backend or detect_backend()


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
