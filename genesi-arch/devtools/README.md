# devtools — running Genesi's Qt apps off Genesi

Not shipped. Nothing in `packages/` imports any of this.

## Why

The AI Mode Monitor is PySide6 + QML and imports `org.kde.kirigami`, which
exists only on a Plasma desktop. That meant every visual change to it was
written blind and verified by building a package and installing it on the
target machine — a terrible loop for design work, and the reason a few UI
regressions shipped (pkgrel 135's blank Monitor being the worst).

## What

`kirigami-stub/` provides the **nine** Kirigami types the Monitor actually
uses — `Units`, `Theme`, `Icon`, `Page`, `ApplicationWindow`, `InlineMessage`,
`PromptDialog`, `Dialog`, `MessageType`. `Units` carries Kirigami's own
defaults (`gridUnit: 18`, `smallSpacing: 4`, `largeSpacing: 8`), so the layout
rhythm on screen is the rhythm the app will have on the desktop.

`preview.py` stages the app the way the package installs it (the shared
`genesi-ui-kit` components sit *next to* the app's QML, because QML resolves a
bare `Theme { }` from the same directory), points the QML engine at the stub,
and hands it the **real** `genesi_ai_monitor.Backend`. Its OS calls — systemctl,
ollama, the automation daemon's socket — simply fail on a non-Genesi box and
return empty, which is a state the shipped app has to survive anyway.

## Use

```bash
pip install PySide6
python devtools/preview.py                    # open the window
python devtools/preview.py --demo             # ...populated with content
python devtools/preview.py --demo --tab 1     # ...on the AI Chat tab
python devtools/preview.py --shot out.png --demo --size 1280x800
```

`--tab` indexes the Monitor's own `currentTab` (0 Dashboard, 1 AI Chat,
2 Models, 3 Automations, 4 Mesh). `--size` is how you check responsiveness
without dragging a window.

## Limits — read these before trusting a screenshot

- **It is not Kirigami.** The stubs are faithful for layout and colour, not for
  behaviour. A `Kirigami.Icon` given a freedesktop icon *name* renders as a
  tinted rounded square, because Windows has no icon theme; icons loaded from
  the app's own `icons/*.svg` render for real.
- **`--shot` opens a real window briefly.** Qt's `offscreen` platform on
  Windows has no font database, so every glyph comes out as a missing-glyph
  box and the shot is useless for judging type.
- **Rubik is substituted.** The app asks for Rubik (shipped by
  `genesi-ttf-rubik-vf`); the preview falls back to Segoe UI / DejaVu Sans.
  Metrics differ slightly, so treat tight text fits as approximate.
- On Windows the backend logs `AttributeError: module 'socket' has no attribute
  'AF_UNIX'` from the thread that pings the automation daemon. Harmless here,
  and not worth guarding in shipped code for a dev harness.
