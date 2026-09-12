#!/usr/bin/env python3
"""
Genesi Center — QML engine plus the thread that feeds it.

Pure front-end, the same contract every Genesi app follows: this process draws
and delegates, and every fact on screen comes from `genesi-center-data`. It
never reads /proc itself, so the numbers in the window and the numbers in a
terminal cannot disagree.

The tick runs on a worker thread. `genesi-center-data telemetry` deliberately
sleeps ~120ms twice, sampling /proc/stat and /proc/net/dev, because a rate needs
two readings -- and a quarter second on the UI thread is a visible stutter every
tick. Nothing about the reading is urgent, so it belongs off the main loop.
"""
import json
import os
import shlex
import shutil
import subprocess
import sys
import threading

try:
    from PySide6.QtCore import QObject, QUrl, Signal, Slot, QTimer
    from PySide6.QtGui import QGuiApplication, QIcon
    from PySide6.QtQml import QQmlApplicationEngine
except ImportError:
    sys.stderr.write(
        "Genesi Center needs PySide6.\n"
        "  Install it with:  sudo pacman -S pyside6\n")
    sys.exit(1)

DATA = "genesi-center-data"
APPDIR = os.path.dirname(os.path.abspath(__file__))
TICK_MS = 5000


# Tools a page is allowed to run.
#
# Not a security boundary against the user -- they own the machine and can run
# anything. It is a boundary against THIS code: `act` takes a list from QML,
# and a page that is one typo away from running an arbitrary name is a page
# that will one day be handed one from a config file or a translated string.
# Naming the binaries that exist keeps the blast radius at zero, and a
# refusal is printed rather than swallowed so a new page fails loudly on the
# desk of whoever wrote it.
ALLOWED = {
    "genesi-center-set", "genesi-console", "genesi-display", "genesi-bar",
    "genesi-snapshots", "genesi-snapshots-gui", "genesi-channel-gui",
    "genesi-ai-mode", "genesi-ai-turbo", "genesi-ai-monitor",
    "genesi-ai-voice", "genesi-ai-key",
    "genesi-open-usb-mixer",
    "caelestia", "hyprctl", "hyprshade", "wpctl",
}
# ...and the terminal is no longer one of these. A page asks for a COMMAND to
# be run in a terminal now (inTerminal), and this list is what a command may
# be; which terminal wraps it is not the page's business, and naming `foot`
# outright meant a session without foot got a button that did nothing.


class Backend(QObject):
    dataReady = Signal(str)
    displaysReady = Signal(str)
    barPresetsReady = Signal(str)
    # (section, json). One signal for every page added from here on, rather
    # than a signal each: a page filters by name, and the alternative is this
    # class growing a pair of members per page forever.
    sectionReady = Signal(str, str)

    def __init__(self):
        super().__init__()
        # One tick at a time. The reader takes a moment by design, and a slow
        # machine could otherwise stack ticks until every one of them is late.
        self._busy = threading.Lock()

    def _read(self, what):
        try:
            p = subprocess.run([DATA, what], capture_output=True, text=True,
                               timeout=40, encoding="utf-8", errors="replace")
            return p.stdout.strip()
        except (OSError, subprocess.SubprocessError):
            return ""

    def _tick_body(self, sections):
        try:
            out = {}
            for s in sections:
                raw = self._read(s)
                if raw:
                    try:
                        out[s] = json.loads(raw)
                    except json.JSONDecodeError:
                        pass
            if out:
                self.dataReady.emit(json.dumps(out))
        finally:
            self._busy.release()

    def _tick(self, sections):
        if not self._busy.acquire(blocking=False):
            return
        threading.Thread(target=self._tick_body, args=(sections,),
                         daemon=True).start()

    @Slot()
    def refresh(self):
        # Storage walks the filesystem with du, so it is not on the fast tick.
        self._tick(["telemetry", "core", "storage", "activity"])

    @Slot()
    def poll(self):
        self._tick(["telemetry"])

    @Slot()
    def displays(self):
        """The monitors, as genesi-display reports them."""
        def body():
            try:
                p = subprocess.run(["genesi-display", "list"],
                                   capture_output=True, text=True, timeout=15,
                                   encoding="utf-8", errors="replace")
                self.displaysReady.emit(p.stdout.strip() or "[]")
            except (OSError, subprocess.SubprocessError):
                self.displaysReady.emit("[]")
        threading.Thread(target=body, daemon=True).start()

    @Slot(list)
    def displayCmd(self, args):
        """
        Run one genesi-display subcommand and re-read afterwards.

        Every argument is a fixed word or a monitor name the compositor
        reported, never a string a user typed, and it is never handed to a
        shell. The re-read is the point: the tool re-packs the other screens
        when one changes, so the page must be told what the desk looks like
        NOW rather than assuming its own edit was the only effect.
        """
        def body():
            try:
                subprocess.run(["genesi-display"] + [str(a) for a in args],
                               capture_output=True, text=True, timeout=25,
                               encoding="utf-8", errors="replace")
            except (OSError, subprocess.SubprocessError):
                pass
            self.displays()
        threading.Thread(target=body, daemon=True).start()

    @Slot()
    def barPresets(self):
        """Every bar preset and the one in use, from genesi-bar."""
        def body():
            try:
                p = subprocess.run(["genesi-bar", "json"], capture_output=True,
                                   text=True, timeout=15, encoding="utf-8",
                                   errors="replace")
                self.barPresetsReady.emit(p.stdout.strip() or "{}")
            except (OSError, subprocess.SubprocessError):
                self.barPresetsReady.emit("{}")
        threading.Thread(target=body, daemon=True).start()

    @Slot(str)
    def barApply(self, preset):
        """
        Switch the bar, then re-read.

        The re-read is not decoration: `genesi-bar` refuses a preset it does
        not have, and the page must show what IS applied rather than what was
        clicked.
        """
        def body():
            try:
                subprocess.run(["genesi-bar", "apply", str(preset)],
                               capture_output=True, text=True, timeout=15,
                               encoding="utf-8", errors="replace")
            except (OSError, subprocess.SubprocessError):
                pass
            self.barPresets()
        threading.Thread(target=body, daemon=True).start()

    @Slot(str)
    def ask(self, what):
        """
        Read one data section and hand it to whoever asked.

        These are the expensive sections -- system() runs pacman -Q,
        resources() sleeps to sample every core, snapshots() walks btrfs -- so
        they are deliberately NOT on the tick. A page asks when it opens and
        after it changes something, and nothing else pays for it.
        """
        def body():
            self.sectionReady.emit(str(what), self._read(str(what)) or "{}")
        threading.Thread(target=body, daemon=True).start()

    @Slot(list, str)
    def act(self, argv, then):
        """
        Run one tool, then re-read a section.

        The re-read is the whole contract, and the reason no page is allowed
        to assume its own edit worked: `hyprctl keyword` silently ignores an
        option it does not know, `wpctl` can be overruled by a hardware mixer,
        and genesi-bar refuses a preset it does not have. The page shows what
        IS, never what was clicked -- which is the difference between this and
        the settings pages this project has had to apologise for.
        """
        if not argv:
            return
        cmd = [str(a) for a in argv]
        if cmd[0] not in ALLOWED:
            sys.stderr.write(
                f"genesi-center: refusing to run {cmd[0]!r}; add it to ALLOWED "
                "if a page really needs it\n")
            return

        def body():
            try:
                subprocess.run(cmd, capture_output=True, text=True, timeout=40,
                               encoding="utf-8", errors="replace")
            except (OSError, subprocess.SubprocessError):
                pass
            if then:
                self.sectionReady.emit(str(then), self._read(str(then)) or "{}")
        threading.Thread(target=body, daemon=True).start()

    @Slot(str)
    def barShell(self, which):
        """
        Switch which bar runs: caelestia's side rail or Genesi's top bar.

        Two different bars, not one rotated -- caelestia's is a vertical layout
        all the way down to how each module stacks inside itself -- so the CLI
        stops one and starts the other, and remembers the choice for the next
        login. Re-read afterwards for the same reason as barApply: the page
        must show what IS running, not what was clicked.
        """
        def body():
            try:
                subprocess.run(["genesi-bar", "shell", str(which)],
                               capture_output=True, text=True, timeout=20,
                               encoding="utf-8", errors="replace")
            except (OSError, subprocess.SubprocessError):
                pass
            self.barPresets()
        threading.Thread(target=body, daemon=True).start()

    cloudTested = Signal(str, bool)

    @Slot()
    def testCloudKey(self):
        """One real request, and the answer on the page.

        This used to open a terminal, on the reasoning that the useful part of
        a failed test is WHICH failure -- 401 is a wrong key, 404 a wrong
        model -- and that is a sentence rather than a light. The sentence was
        right; the terminal was not. `foot genesi-ai-key test` runs, prints,
        and exits, and the window closes with it: what the user sees is a
        terminal flashing open and nothing else. Reported as "the test button
        opens an empty terminal and does nothing".

        A sentence can go on the page. So it does.
        """
        def body():
            try:
                r = subprocess.run(["genesi-ai-key", "test"],
                                   capture_output=True, text=True, timeout=40,
                                   encoding="utf-8", errors="replace")
            except (OSError, subprocess.SubprocessError) as e:
                self.cloudTested.emit(str(e), False)
                return
            out = (r.stdout or "").strip()
            err = (r.stderr or "").strip()
            # genesi-ai-key writes the diagnosis to stderr and the answer to
            # stdout, and prefixes its errors with its own name -- which the
            # page does not need to repeat.
            msg = out if r.returncode == 0 else err
            msg = msg.replace("genesi-ai-key: ", "").replace("\n", " ")
            self.cloudTested.emit(msg or "no answer", r.returncode == 0)
            # A test is a real request, so the count moved: re-read.
            self.sectionReady.emit("ai", self._read("ai") or "{}")
        threading.Thread(target=body, daemon=True).start()

    @Slot(str, str, str, str)
    def setCloudKey(self, provider, model, use_for, key):
        """
        Store an API key, without it ever appearing in argv.

        `genesi-ai-key set` reads the key from stdin precisely so that it stays
        out of shell history and out of `ps`, where every user on the machine
        can read it. A settings window that ran `genesi-ai-key set sk-...`
        would undo that in one line, so this pipes it the same way the shell
        does -- which is also why it cannot go through act(): that builds a
        command line, and this must not.

        Everything else about it IS on the command line, because none of it is
        secret: which provider, which model, and whether the helpers that fire
        on their own may use it.
        """
        key = (key or "").strip()
        if not key:
            return
        argv = ["genesi-ai-key", "set", "--provider", str(provider),
                "--for", str(use_for or "manual")]
        if model:
            argv += ["--model", str(model)]

        def body():
            try:
                subprocess.run(argv, input=key, capture_output=True, text=True,
                               timeout=20, encoding="utf-8", errors="replace")
            except (OSError, subprocess.SubprocessError):
                pass
            # Re-read, so the page shows what was actually stored -- including
            # nothing at all, if the tool refused it.
            self.sectionReady.emit("ai", self._read("ai") or "{}")
        threading.Thread(target=body, daemon=True).start()

    # Terminals, in the order we would rather have them. foot is what the
    # Hyprland session ships and what every one of these calls used to name
    # outright -- on a machine without it the button did nothing at all, with
    # one line on the app's own stderr that nobody is reading.
    TERMINALS = (
        (["foot"], "-e"),
        (["ghostty"], "-e"),
        (["kitty"], None),
        (["alacritty"], "-e"),
        (["wezterm"], "start", ),
        (["konsole"], "-e"),
        (["gnome-terminal"], "--"),
        (["xterm"], "-e"),
    )

    @Slot(list)
    def inTerminal(self, argv):
        """Run something in a terminal window that STAYS OPEN when it ends.

        Two bugs in one, both reported as "it opens an empty terminal and does
        nothing":

        `foot <cmd>` exits when <cmd> exits. For a command whose whole purpose
        is to print something -- a key test, a failed install -- the window
        appears and vanishes before anything can be read. So the command is
        wrapped: run it, then wait for a keypress.

        And `foot` was named literally in every call site, so a session
        without foot got nothing but a line on this app's stderr. Whichever
        terminal is installed is used instead.
        """
        if not argv:
            return
        cmd = [str(a) for a in argv]
        if cmd[0] not in ALLOWED:
            sys.stderr.write(
                f"genesi-center: refusing to run {cmd[0]!r} in a terminal\n")
            return
        # Quoted one at a time: a wallpaper path or a model name with a space
        # in it is a command line that means something else.
        inner = " ".join(shlex.quote(c) for c in cmd)
        script = (inner + '; printf "\\n[done — press enter to close] ";'
                  " read _")
        for exe, flag in self.TERMINALS:
            if not shutil.which(exe[0]):
                continue
            line = list(exe)
            if flag:
                line.append(flag)
            line += ["sh", "-c", script]
            try:
                subprocess.Popen(line, stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL,
                                 start_new_session=True)
                return
            except OSError:
                continue
        sys.stderr.write(
            "genesi-center: no terminal emulator found; tried "
            + ", ".join(t[0][0] for t in self.TERMINALS) + "\n")

    @Slot(list)
    def launch(self, argv):
        """
        Start a tool and forget it.

        argv is a fixed list from the page, never a string a user typed, and it
        is never handed to a shell -- so nothing here can be turned into an
        injection by a filename or a locale.
        """
        if not argv:
            return
        try:
            subprocess.Popen([str(a) for a in argv],
                             stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL,
                             start_new_session=True)
        except OSError as e:
            sys.stderr.write(f"genesi-center: cannot start {argv[0]}: {e}\n")


def capabilities():
    """
    What this session can be asked to configure.

    Read once at start-up, not per tick: a person does not change desktop while
    the window is open, and the rail is built from it.

    It matters because Genesi Center runs on Plasma AND on Hyprland, and half
    of what it configures exists on only one of them. A page offering a control
    the session cannot honour is worse than a missing page: the control appears
    to work and changes nothing, which is the exact failure this project has
    met over and over.
    """
    try:
        p = subprocess.run([DATA, "session"], capture_output=True, text=True,
                           timeout=10, encoding="utf-8", errors="replace")
        return json.loads(p.stdout.strip() or "{}")
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
        # Unknown is not the same as absent. Assuming nothing is available
        # would leave a person on Hyprland with an app that hides the pages
        # they need, so an unreadable session shows everything and lets the
        # individual pages fail honestly instead.
        return {"hyprland": True, "caelestia": True, "plasma": True}


def tree_art():
    """
    Where the Overview's artwork comes from.

    A user drop-in wins over the packaged file, so the art can be replaced and
    seen by reopening the window -- no rebuild, no root, no package. That is
    the whole reason this is resolved here rather than hardcoded in QML: an
    Image cannot try one path and fall back to another, and deciding it in
    Python costs four lines.

    Returns "" when neither exists, and the page then draws its procedural glow
    instead of an empty rectangle.
    """
    for p in (os.path.expanduser("~/.config/genesi/center/tree.png"),
              os.path.expanduser("~/.config/genesi/center/tree.svg"),
              os.path.join(APPDIR, "art", "tree.png")):
        if os.path.exists(p):
            return "file://" + p
    return ""


def main():
    QGuiApplication.setApplicationName("Genesi Center")
    QGuiApplication.setDesktopFileName("org.genesi.center")
    app = QGuiApplication(sys.argv)

    icon = "/usr/share/icons/hicolor/scalable/apps/genesi-center.svg"
    if os.path.exists(icon):
        app.setWindowIcon(QIcon(icon))

    backend = Backend()
    engine = QQmlApplicationEngine()
    engine.addImportPath(APPDIR)
    engine.setInitialProperties({"backend": backend, "treeArt": tree_art(),
                                 "caps": capabilities()})
    engine.load(QUrl.fromLocalFile(os.path.join(APPDIR, "Main.qml")))
    if not engine.rootObjects():
        sys.stderr.write("genesi-center: the interface failed to load\n")
        return 1

    backend.refresh()
    fast = QTimer()
    fast.timeout.connect(backend.poll)
    fast.start(TICK_MS)
    # The slow half -- disk usage and the activity log -- every minute.
    slow = QTimer()
    slow.timeout.connect(backend.refresh)
    slow.start(TICK_MS * 12)

    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
