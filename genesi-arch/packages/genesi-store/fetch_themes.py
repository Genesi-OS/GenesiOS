"""
The Fastfetch shelf's picture cards: one theme per emblem in fetch-art/.

One module, read by two programs -- build-catalog.py writes each theme's
config into the catalogue, plugin-style fetch-previews.py draws the card's
picture -- so the picture on the card and the config the button writes are
made from the same table and cannot drift apart.

The layout is the one people build by hand and post: the picture on the
left, then a name line, a tagline behind a coloured square, and the machine
in three sections -- VITALS, SYSTEM, SESSION -- each under a rule in the
theme's colour, with the keys aligned in that colour too, and the terminal's
palette as a row of dots at the end. Two lines no stock fetch has: CHANNEL,
which Genesi channel this machine follows, and AGE, how long ago it was
installed.
"""
import json

ART_DIR = "/usr/share/genesi-store/fetch-art"

SCHEMA = "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json"

# id, name (pt), blurb (pt), tags (pt), picture, key colour, rule colour,
# tagline -- the tagline is in the config, so it is written in English, the
# language a terminal already speaks.
THEMES = [
    ("sol", "Sol Nascente",
     "Um torii contra o sol vermelho, com o selo 創 -- \"criar\", o primeiro "
     "caractere de gênese. Chaves em vermelho.",
     ["japão", "vermelho"], "sol", (224, 68, 62), (96, 46, 42), "創 · the first light"),
    ("folha", "Folha",
     "A folha do Genesi em órbita, sobre um campo de pólen. Chaves no verde "
     "da casa.",
     ["verde", "genesi"], "folha", (57, 217, 138), (30, 92, 64), "grown, not built"),
    ("synthwave", "Synthwave",
     "Sol fatiado, montanhas em neon e a grade até o horizonte. Chaves em "
     "rosa, réguas em ciano.",
     ["neon", "retro"], "synthwave", (255, 94, 168), (0, 150, 170), "neon never sleeps"),
    ("lua", "Lua",
     "Lua crescente sobre três serras e um pinheiral. Chaves em azul.",
     ["noite", "azul"], "lua", (122, 162, 247), (52, 72, 120), "quiet hours"),
    ("onda", "A Onda",
     "A grande onda quebrando sob um sol pequeno. Chaves em azul-mar.",
     ["japão", "azul"], "onda", (98, 164, 214), (44, 80, 110), "ride the next one"),
    ("cyber", "Cyber",
     "Um núcleo hexagonal com trilhas de circuito saindo dele. Chaves em "
     "ciano, detalhes em magenta.",
     ["neon", "escuro"], "cyber", (0, 229, 255), (150, 50, 140), "wired and awake"),
    ("sakura", "Sakura",
     "Um galho de cerejeira em flor diante de uma lua rosada. Chaves em rosa.",
     ["rosa", "japão"], "sakura", (255, 143, 177), (110, 60, 80), "bloom where you boot"),
]

# How long ago this machine was installed: the root filesystem's birth time,
# which btrfs records, falling back to machine-id for a filesystem that does
# not.
AGE_COMMAND = ('b=$(stat -c %W / 2>/dev/null); [ "${b:-0}" -gt 0 ] || '
               'b=$(stat -c %Y /etc/machine-id); '
               'echo "$(( ($(date +%s) - b) / 86400 )) days"')

# Which channel -- see beta-channel: testing is an extra repository in
# pacman.conf, and the machine is on stable without it.
CHANNEL_COMMAND = ("grep -qs '^\\[genesi-testing\\]' /etc/pacman.conf "
                   "&& echo testing || echo stable")


def _sgr(rgb):
    return "38;2;%d;%d;%d" % rgb


def config(theme, logo=None):
    """The fastfetch config for one theme, as a JSON string.

    `logo` replaces the picture -- the same layout with the Genesi leaf in
    ASCII, or with no logo at all, is the same card without the image."""
    ident, _, _, _, art, key, rule, tagline = theme
    k, r = _sgr(key), _sgr(rule)

    def section(label):
        return {"type": "custom",
                "format": "{#1;%s}── %s {#0;%s}%s{#}" % (k, label, r, "─" * (30 - len(label)))}

    if logo is None:
        logo = {"type": "sixel", "source": "%s/%s.png" % (ART_DIR, art),
                "width": 28, "padding": {"top": 1, "left": 1, "right": 4}}
    data = {
        "$schema": SCHEMA,
        "logo": logo,
        "display": {
            "separator": "  ",
            "key": {"width": 8},
            "color": {"keys": "1;" + k, "title": "1;" + k},
        },
        "modules": [
            {"type": "title", "format": "{user-name} @ {host-name}"},
            {"type": "custom", "format": "{#%s}■{#} GENESI · %s" % (k, tagline)},
            "break",
            section("VITALS"),
            {"type": "cpu", "key": "CPU"},
            {"type": "gpu", "key": "GPU"},
            {"type": "memory", "key": "MEMORY"},
            {"type": "disk", "key": "DISK", "folders": "/"},
            "break",
            section("SYSTEM"),
            {"type": "os", "key": "OS"},
            {"type": "command", "key": "CHANNEL", "text": CHANNEL_COMMAND},
            {"type": "kernel", "key": "KERNEL"},
            {"type": "wm", "key": "WM"},
            {"type": "shell", "key": "SHELL"},
            {"type": "packages", "key": "PKGS"},
            "break",
            section("SESSION"),
            {"type": "uptime", "key": "UPTIME"},
            {"type": "command", "key": "AGE", "text": AGE_COMMAND},
            {"type": "terminal", "key": "TERM"},
            "break",
            {"type": "colors", "symbol": "circle"},
        ],
    }
    return json.dumps(data, indent=2, ensure_ascii=False) + "\n"


# What a real machine prints for each line, for the card's picture.
SAMPLE = [
    ("title", "genesi @ genesi"),
    ("tagline", None),
    ("break", None),
    ("rule", "VITALS"),
    ("CPU", "AMD Ryzen 7 5700X (16) @ 4.66 GHz"),
    ("GPU", "NVIDIA GeForce RTX 3050 [Discrete]"),
    ("MEMORY", "6.42 GiB / 31.26 GiB (21%)"),
    ("DISK", "212.40 GiB / 931.51 GiB (23%) - btrfs"),
    ("break", None),
    ("rule", "SYSTEM"),
    ("OS", "Genesi OS x86_64"),
    ("CHANNEL", "stable"),
    ("KERNEL", "Linux 6.16.8-2-cachyos"),
    ("WM", "Hyprland 0.51.1 (Wayland)"),
    ("SHELL", "fish 4.0.8"),
    ("PKGS", "1402 (pacman)"),
    ("break", None),
    ("rule", "SESSION"),
    ("UPTIME", "3 hours, 12 mins"),
    ("AGE", "41 days"),
    ("TERM", "foot 1.24.0"),
    ("break", None),
    ("colors", None),
]
