"""
genesi_palette — make a Genesi Qt app follow the desktop's colour scheme.

Two lines in an app's main() and it follows, or keeps the Genesi look, exactly
as Genesi Center and Forge already do -- one switch, in one place, governing
all of them.

    from genesi_palette import install
    ...
    app = QApplication(sys.argv)
    palette = install(app, engine)

── Why both halves are needed ──────────────────────────────────────────────

A Genesi app paints two kinds of pixel and they come from different places.

The ones it draws itself -- cards, separators, the sidebar -- come from the
UI kit's Theme.qml, and that is what `install` hands to QML.

The ones Qt draws -- a ComboBox popup, a ScrollBar, a Fusion button, a
context menu -- come from the application's QPalette, which the app never
set. Under a platform theme that is not being applied they arrive as Fusion's
default LIGHT palette. That is the "dark blue window with a few white buttons
in it" state: not an app half-following the scheme, an app following nothing
while Qt fills the gaps with its own default.

So `install` does both: it applies a QPalette built from the same scheme, and
it exposes the colours to QML. Following or not, the two agree afterwards --
which is the actual requirement. An app that keeps the Genesi navy still has
to hand Qt a DARK palette, or the popups are white on a black window.

── One switch, and it is Genesi Center's ───────────────────────────────────

~/.config/genesi/center/settings.json, key followSystemTheme. The same file
Forge reads. Two switches, one per app, is two places to look when only one of
them followed.

Read once at startup, because Qt resolves a palette once at startup: an app
that re-read this every second would still not repaint what Qt has already
drawn, and would only be lying more often.
"""
import json
import os

SCHEME = os.path.expanduser("~/.local/state/caelestia/scheme.json")
CENTER_SETTINGS = os.path.expanduser(
    "~/.config/genesi/center/settings.json")

# The Genesi look, as the kit pins it. Used when there is no scheme to follow,
# and when following is off -- the app still needs a coherent DARK palette to
# hand to Qt, and these are the colours it is actually painted in.
GENESI = {
    "surface": "#040b17",
    "surfaceContainerLowest": "#040b17",
    "surfaceContainerLow": "#0a1220",
    "surfaceContainer": "#0d1623",
    "surfaceContainerHigh": "#16223a",
    "surfaceContainerHighest": "#1b2740",
    "onSurface": "#e8f0f8",
    "onSurfaceVariant": "#9fb0c4",
    "outline": "#27374f",
    "primary": "#1FBE6A",
    "onPrimary": "#04180d",
    "secondary": "#34D989",
    "tertiary": "#3AAFE0",
    "error": "#E74C3C",
}


def read_scheme():
    """caelestia's active colours as '#rrggbb', or {} when there is none."""
    try:
        with open(SCHEME, encoding="utf-8") as fh:
            raw = (json.load(fh).get("colours") or {})
    except (OSError, ValueError):
        return {}
    return {k: "#" + v.lstrip("#") for k, v in raw.items()
            if isinstance(v, str) and len(v.lstrip("#")) == 6}


def read_follow():
    """Whether Genesi Center's one switch says to follow the desktop."""
    try:
        with open(CENTER_SETTINGS, encoding="utf-8") as fh:
            return bool(json.load(fh).get("followSystemTheme", False))
    except (OSError, ValueError):
        return False


def resolve():
    """
    (colours, following) -- what to paint with, and whether it came from the
    desktop.

    Falling back to the Genesi palette rather than to {} is the point: every
    caller wants a complete set of colours, and a caller that has to handle
    "half of them are missing" is a caller that will get it wrong somewhere.
    """
    scheme = read_scheme()
    following = bool(scheme) and read_follow()
    if not following:
        return dict(GENESI), False
    out = dict(GENESI)
    out.update(scheme)
    return out, True


def qpalette(colours):
    """A QPalette for the whole application, from those colours."""
    from PySide6.QtGui import QColor, QPalette

    def c(key, fallback="#101010"):
        return QColor(colours.get(key) or fallback)

    p = QPalette()
    text = c("onSurface", "#e6e6e6")
    dim = c("onSurfaceVariant", "#8a8a8a")
    window = c("surface", "#101010")
    base = c("surfaceContainerLowest", "#0a0a0a")
    button = c("surfaceContainer", "#1a1a1a")
    primary = c("primary", "#1FBE6A")

    for group in (QPalette.ColorGroup.Active, QPalette.ColorGroup.Inactive):
        p.setColor(group, QPalette.ColorRole.Window, window)
        p.setColor(group, QPalette.ColorRole.WindowText, text)
        p.setColor(group, QPalette.ColorRole.Base, base)
        p.setColor(group, QPalette.ColorRole.AlternateBase,
                   c("surfaceContainerLow", "#141414"))
        p.setColor(group, QPalette.ColorRole.Text, text)
        p.setColor(group, QPalette.ColorRole.Button, button)
        p.setColor(group, QPalette.ColorRole.ButtonText, text)
        p.setColor(group, QPalette.ColorRole.BrightText,
                   c("onPrimary", "#ffffff"))
        p.setColor(group, QPalette.ColorRole.Highlight, primary)
        p.setColor(group, QPalette.ColorRole.HighlightedText,
                   c("onPrimary", "#ffffff"))
        p.setColor(group, QPalette.ColorRole.ToolTipBase,
                   c("surfaceContainerHigh", "#202020"))
        p.setColor(group, QPalette.ColorRole.ToolTipText, text)
        p.setColor(group, QPalette.ColorRole.PlaceholderText,
                   c("outline", "#6a6a6a"))
        p.setColor(group, QPalette.ColorRole.Link, primary)
        p.setColor(group, QPalette.ColorRole.LinkVisited,
                   c("secondary", "#8888aa"))

    # Disabled is not "the same but the app decides": Qt draws greyed-out text
    # in whatever this says, and leaving it at the default gives dark grey on a
    # dark window -- text that is not disabled-looking, just gone.
    d = QPalette.ColorGroup.Disabled
    p.setColor(d, QPalette.ColorRole.Window, window)
    p.setColor(d, QPalette.ColorRole.Base, base)
    p.setColor(d, QPalette.ColorRole.Button, button)
    for role in (QPalette.ColorRole.WindowText, QPalette.ColorRole.Text,
                 QPalette.ColorRole.ButtonText,
                 QPalette.ColorRole.PlaceholderText):
        p.setColor(d, role, dim)
    p.setColor(d, QPalette.ColorRole.Highlight,
               c("surfaceContainerHigh", "#202020"))
    p.setColor(d, QPalette.ColorRole.HighlightedText, dim)
    return p


def install(app, engine=None):
    """
    Apply the palette to `app`, and expose the colours to `engine`'s QML.

    Returns the dict it used, so a caller that wants to paint something in
    Python does not have to resolve it a second time.
    """
    colours, following = resolve()
    try:
        app.setPalette(qpalette(colours))
    except Exception:
        # A palette that could not be built is not a reason for the app not to
        # start. It falls back to whatever Qt would have done, which is exactly
        # where it was before this file existed.
        pass
    if engine is not None:
        ctx = engine.rootContext()
        ctx.setContextProperty("genesiPalette", colours)
        ctx.setContextProperty("genesiFollowing", following)
    return colours
