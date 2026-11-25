"""
Whole looks for Genesi's top bar, for the Bars shelf.

The bar has some forty settings, and the one people actually want is "make it
look like that screenshot". Each look here is those settings as one set,
applied through genesi-center-set -- the writer that validates every key --
by the store's `config` action, which also remembers what was there so
Revert puts it back.

Read by build-catalog.py for the cards and by topbar-previews.py for their
pictures, so a card cannot show one bar and apply another.
"""

# id, name (pt), blurb (pt), tags (pt), settings
LOOKS = [
    ("moldura", "Moldura",
     "A barra É a borda do caelestia: cantos arredondados onde ela encontra a "
     "tela, workspaces numerados, anéis de CPU e memória, o que está tocando, "
     "volume, brilho e a bateria numa pílula.",
     ["barra de cima", "completo"],
     {
         "topbar.enabled": "true", "topbar.form": "frame", "topbar.height": "40",
         "topbar.position": "top",
         "topbar.windowPlace": "left", "topbar.windowStacked": "true",
         "topbar.showActiveWindow": "true",
         "topbar.resourceStyle": "rings", "topbar.resourcePlace": "left",
         "topbar.showResources": "true",
         "topbar.showMedia": "true", "topbar.mediaPlace": "left",
         "topbar.workspaceStyle": "numbers", "topbar.workspaceCount": "10",
         "topbar.showWorkspaces": "true", "topbar.showSidebarButton": "false",
         "topbar.showVolume": "true", "topbar.showBrightness": "true",
         "topbar.showBluetooth": "true", "topbar.batteryStyle": "pill",
         "topbar.dateStyle": "numbers", "topbar.showDate": "true",
         "topbar.showClock": "true", "topbar.accent": "primary",
     }),
    ("ilhas", "Ilhas com fluxo",
     "Três ilhas flutuando, uma luz correndo entre elas, o que está tocando no "
     "meio e sombra embaixo.",
     ["barra de cima", "flutuante"],
     {
         "topbar.enabled": "true", "topbar.form": "islands", "topbar.height": "36",
         "topbar.position": "top", "topbar.flow": "true", "topbar.shadow": "true",
         "topbar.windowPlace": "centre", "topbar.windowStacked": "false",
         "topbar.resourceStyle": "text", "topbar.resourcePlace": "right",
         "topbar.showMedia": "true", "topbar.mediaPlace": "centre",
         "topbar.workspaceStyle": "dots", "topbar.showSidebarButton": "true",
         "topbar.showVolume": "true", "topbar.showBrightness": "false",
         "topbar.showBluetooth": "false", "topbar.batteryStyle": "icon",
         "topbar.dateStyle": "words", "topbar.accent": "tertiary",
     }),
    ("entalhe", "Entalhe",
     "Só o meio tem fundo, colado na borda com ombros curvos; os lados ficam "
     "soltos. Workspaces numerados e anéis à direita.",
     ["barra de cima", "minimalista"],
     {
         "topbar.enabled": "true", "topbar.form": "notch", "topbar.height": "34",
         "topbar.position": "top",
         "topbar.windowPlace": "left", "topbar.windowStacked": "true",
         "topbar.resourceStyle": "rings", "topbar.resourcePlace": "right",
         "topbar.showMedia": "false",
         "topbar.workspaceStyle": "numbers", "topbar.workspaceCount": "5",
         "topbar.showSidebarButton": "false",
         "topbar.showVolume": "false", "topbar.showBrightness": "false",
         "topbar.showBluetooth": "false", "topbar.batteryStyle": "pill",
         "topbar.dateStyle": "long", "topbar.accent": "secondary",
     }),
]
