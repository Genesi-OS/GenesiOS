"""
Where each app from the old distro comes from on Genesi.

The scanner finds apps by the package that owns their .desktop file, so the
keys here are DISTRO package names (Debian/Ubuntu, Fedora, openSUSE...), and
the values say how Genesi gets the same app:

    ("pacman", name)   -- in the official/[genesi] repos
    ("aur", name)      -- AUR only (Genesi ships an AUR helper)
    ("flatpak", appid) -- no native package worth using; Flathub has it

Anything NOT in the tables falls back to "same name on pacman", flagged as
`likely` rather than `known`: most desktop apps really are named the same on
Arch, but the restore step must check with `pacman -Si` before trusting it and
fall back to a Flathub search. That check happens on Genesi, where pacman is.

Stdlib only -- this module runs on the OLD distro, inside an AppImage.
"""

# Exact package names -> Genesi source.
PKG_MAP = {
    # browsers
    "firefox": ("pacman", "firefox"),
    "firefox-esr": ("pacman", "firefox"),
    "chromium": ("pacman", "chromium"),
    "chromium-browser": ("pacman", "chromium"),
    "google-chrome-stable": ("aur", "google-chrome"),
    "brave-browser": ("aur", "brave-bin"),
    "microsoft-edge-stable": ("aur", "microsoft-edge-stable-bin"),
    "vivaldi-stable": ("pacman", "vivaldi"),
    "opera-stable": ("pacman", "opera"),
    "torbrowser-launcher": ("pacman", "torbrowser-launcher"),
    # dev
    "code": ("aur", "visual-studio-code-bin"),
    "codium": ("aur", "vscodium-bin"),
    "sublime-text": ("aur", "sublime-text-4"),
    "android-studio": ("aur", "android-studio"),
    "dbeaver-ce": ("pacman", "dbeaver"),
    "docker-ce": ("pacman", "docker"),
    "docker.io": ("pacman", "docker"),
    "moby-engine": ("pacman", "docker"),
    "golang": ("pacman", "go"),
    "golang-go": ("pacman", "go"),
    "python3-pip": ("pacman", "python-pip"),
    "build-essential": ("pacman", "base-devel"),
    "nodejs": ("pacman", "nodejs"),
    "neovim": ("pacman", "neovim"),
    "vim-gtk3": ("pacman", "gvim"),
    "vim-gtk": ("pacman", "gvim"),
    "vim-enhanced": ("pacman", "vim"),
    "emacs-gtk": ("pacman", "emacs"),
    "github-desktop": ("aur", "github-desktop-bin"),
    # communication
    "telegram-desktop": ("pacman", "telegram-desktop"),
    "discord": ("pacman", "discord"),
    "signal-desktop": ("pacman", "signal-desktop"),
    "slack-desktop": ("flatpak", "com.slack.Slack"),
    "zoom": ("flatpak", "us.zoom.Zoom"),
    "skypeforlinux": ("flatpak", "com.skype.Client"),
    "teams": ("flatpak", "com.github.IsmaelMartinez.teams_for_linux"),
    "thunderbird": ("pacman", "thunderbird"),
    "evolution": ("pacman", "evolution"),
    "element-desktop": ("pacman", "element-desktop"),
    # media
    "spotify-client": ("pacman", "spotify-launcher"),
    "vlc": ("pacman", "vlc"),
    "mpv": ("pacman", "mpv"),
    "celluloid": ("pacman", "celluloid"),
    "totem": ("pacman", "totem"),
    "rhythmbox": ("pacman", "rhythmbox"),
    "audacious": ("pacman", "audacious"),
    "strawberry": ("pacman", "strawberry"),
    "obs-studio": ("pacman", "obs-studio"),
    "kdenlive": ("pacman", "kdenlive"),
    "shotcut": ("pacman", "shotcut"),
    "openshot-qt": ("pacman", "openshot"),
    "handbrake-gtk": ("pacman", "handbrake"),
    "handbrake": ("pacman", "handbrake"),
    "audacity": ("pacman", "audacity"),
    "ardour": ("pacman", "ardour"),
    "lmms": ("pacman", "lmms"),
    # graphics / office
    "gimp": ("pacman", "gimp"),
    "inkscape": ("pacman", "inkscape"),
    "krita": ("pacman", "krita"),
    "blender": ("pacman", "blender"),
    "darktable": ("pacman", "darktable"),
    "rawtherapee": ("pacman", "rawtherapee"),
    "shotwell": ("pacman", "shotwell"),
    "digikam": ("pacman", "digikam"),
    "scribus": ("pacman", "scribus"),
    "onlyoffice-desktopeditors": ("aur", "onlyoffice-bin"),
    "wps-office": ("aur", "wps-office"),
    "calibre": ("pacman", "calibre"),
    "xournalpp": ("pacman", "xournalpp"),
    "obsidian": ("pacman", "obsidian"),
    "joplin": ("aur", "joplin-desktop"),
    # gaming
    "steam": ("pacman", "steam"),
    "steam-installer": ("pacman", "steam"),
    "steam-launcher": ("pacman", "steam"),
    "lutris": ("pacman", "lutris"),
    "heroic": ("aur", "heroic-games-launcher-bin"),
    "heroic-games-launcher": ("aur", "heroic-games-launcher-bin"),
    "minecraft-launcher": ("aur", "minecraft-launcher"),
    "prismlauncher": ("pacman", "prismlauncher"),
    "retroarch": ("pacman", "retroarch"),
    "dolphin-emu": ("pacman", "dolphin-emu"),
    "pcsx2": ("flatpak", "net.pcsx2.PCSX2"),
    "protonup-qt": ("flatpak", "net.davidotek.pupgui2"),
    # utilities
    "virtualbox": ("pacman", "virtualbox"),
    "virtualbox-qt": ("pacman", "virtualbox"),
    "virt-manager": ("pacman", "virt-manager"),
    "gnome-boxes": ("pacman", "gnome-boxes"),
    "gparted": ("pacman", "gparted"),
    "timeshift": ("pacman", "timeshift"),
    "keepassxc": ("pacman", "keepassxc"),
    "bitwarden": ("pacman", "bitwarden"),
    "qbittorrent": ("pacman", "qbittorrent"),
    "transmission-gtk": ("pacman", "transmission-gtk"),
    "transmission-qt": ("pacman", "transmission-qt"),
    "deluge": ("pacman", "deluge-gtk"),
    "filezilla": ("pacman", "filezilla"),
    "remmina": ("pacman", "remmina"),
    "flameshot": ("pacman", "flameshot"),
    "ksnip": ("pacman", "ksnip"),
    "peek": ("aur", "peek"),
    "anydesk": ("aur", "anydesk-bin"),
    "teamviewer": ("aur", "teamviewer"),
    "gnome-tweaks": ("pacman", "gnome-tweaks"),
    "gnome-tweak-tool": ("pacman", "gnome-tweaks"),
    "synaptic": None,       # apt front-end: nothing to bring over
    "gnome-software": None, # Genesi has its own store
    "plasma-discover": None,
    "software-properties-gtk": None,
    "update-manager": None,
    "mintupdate": None,
    "mintinstall": None,
    "dnfdragora": None,
    "yast2": None,
}

# Prefix rules for package families split differently across distros.
PREFIX_MAP = (
    ("libreoffice", ("pacman", "libreoffice-fresh")),
    ("openjdk-", ("pacman", "jdk-openjdk")),
    ("java-", ("pacman", "jdk-openjdk")),
    ("virtualbox-", ("pacman", "virtualbox")),
)

# Snaps -> Genesi. Snap has no Arch counterpart, so every snap needs a rule;
# the fallback for an unknown one is a Flathub search at restore time.
SNAP_MAP = {
    "firefox": ("pacman", "firefox"),
    "chromium": ("pacman", "chromium"),
    "code": ("aur", "visual-studio-code-bin"),
    "codium": ("aur", "vscodium-bin"),
    "discord": ("pacman", "discord"),
    "telegram-desktop": ("pacman", "telegram-desktop"),
    "signal-desktop": ("pacman", "signal-desktop"),
    "spotify": ("pacman", "spotify-launcher"),
    "vlc": ("pacman", "vlc"),
    "slack": ("flatpak", "com.slack.Slack"),
    "postman": ("flatpak", "com.getpostman.Postman"),
    "zoom-client": ("flatpak", "us.zoom.Zoom"),
    "skype": ("flatpak", "com.skype.Client"),
    "teams-for-linux": ("flatpak", "com.github.IsmaelMartinez.teams_for_linux"),
    "whatsapp-for-linux": ("flatpak", "com.github.eneshecan.WhatsAppForLinux"),
    "obs-studio": ("pacman", "obs-studio"),
    "gimp": ("pacman", "gimp"),
    "inkscape": ("pacman", "inkscape"),
    "krita": ("pacman", "krita"),
    "blender": ("pacman", "blender"),
    "kdenlive": ("pacman", "kdenlive"),
    "libreoffice": ("pacman", "libreoffice-fresh"),
    "thunderbird": ("pacman", "thunderbird"),
    "bitwarden": ("pacman", "bitwarden"),
    "steam": ("pacman", "steam"),
    "dbeaver-ce": ("pacman", "dbeaver"),
    "sublime-text": ("aur", "sublime-text-4"),
    "android-studio": ("aur", "android-studio"),
    "intellij-idea-community": ("pacman", "intellij-idea-community-edition"),
    "pycharm-community": ("pacman", "pycharm-community-edition"),
    "notepad-plus-plus": None,  # a wine wrapper; nothing native to bring
    "obsidian": ("pacman", "obsidian"),
    "mailspring": ("aur", "mailspring-bin"),
    "foliate": ("pacman", "foliate"),
}

# Snaps that are the snap runtime itself, never something the user picked.
SNAP_RUNTIME_PREFIXES = ("core", "snapd", "bare", "gtk-common-themes",
                         "gnome-", "kf5-", "kf6-", "mesa-", "snap-store",
                         "firmware-updater", "desktop-security-center",
                         "prompting-client", "snapd-desktop-integration",
                         "cups")

# Owners whose apps are the old desktop environment itself. Genesi installs its
# own DE, so these are counted ("comes with the desktop") but not offered.
# Exact names where a bare prefix would swallow real apps ("pix" would take
# pixelorama, "ark" arkade); prefixes only where they end in a separator.
DE_CORE_NAMES = frozenset((
    "nautilus", "gedit", "evince", "eog", "yelp", "baobab", "seahorse",
    "file-roller", "cheese", "gucharmap", "simple-scan", "orca", "totem",
    "dolphin", "konsole", "kate", "okular", "gwenview", "ark", "spectacle",
    "kinfocenter", "systemsettings", "kmenuedit", "kwrite", "khelpcenter",
    "partitionmanager", "kwin", "thunar", "mousepad", "ristretto", "parole",
    "cinnamon", "nemo", "xed", "xreader", "xviewer", "pix", "caja", "pluma",
    "atril", "eom", "engrampa", "pcmanfm", "pcmanfm-qt", "lxterminal",
    "lxappearance", "lxde", "language-selector-gnome", "im-config",
    "desktop-file-utils", "xterm", "info", "vim-common", "vim-runtime",
    "nm-connection-editor", "network-manager-gnome", "blueman", "pavucontrol",
    "deja-dup", "usb-creator-gtk", "gdebi", "apport-gtk", "zutty",
    "debian-reference-common", "anaconda", "setroubleshoot", "nvidia-settings",
    "dconf-editor", "lightdm", "gdm3", "gdm", "sddm", "firewall-config", "gufw",
    "mintupdate", "mintinstall", "mintwelcome", "mintreport", "mintstick",
    "hp-ppd", "hplip-gui", "system-config-printer", "gnome-control-center",
))
DE_CORE_PREFIXES = (
    "gnome-shell", "gnome-control", "gnome-session", "gnome-settings",
    "gnome-disk", "gnome-system", "gnome-terminal", "gnome-text-editor",
    "gnome-calculator", "gnome-calendar", "gnome-characters", "gnome-clocks",
    "gnome-contacts", "gnome-font", "gnome-logs", "gnome-maps", "gnome-music",
    "gnome-photos", "gnome-power", "gnome-screenshot", "gnome-snapshot",
    "gnome-startup", "gnome-weather", "gnome-console", "gnome-user",
    "gnome-initial", "gnome-online", "gnome-remote", "gnome-keyring",
    "plasma-", "kde-", "kdeplasma-", "xfce4-", "mate-", "budgie-", "lxqt-",
    "pantheon-", "io.elementary.", "elementary-", "cosmic-", "unity-",
    "ubuntu-", "language-selector", "xdg-", "fcitx", "ibus", "system-config-",
    "fedora-", "yast2", "opensuse-", "cachyos-", "manjaro-", "endeavouros-",
    "zorin-", "pop-", "python3-", "python-", "perl-", "openjdk-11-jre",
    "libreoffice-base-core",
)

# Command-line tools worth carrying over even though they have no menu entry.
# Detected by the binary existing, mapped to the Arch package.
CLI_TOOLS = {
    "git": "git", "vim": "vim", "docker": "docker", "podman": "podman", "nvim": "neovim",
    "tmux": "tmux", "zsh": "zsh", "fish": "fish", "btop": "btop",
    "htop": "htop", "node": "nodejs", "npm": "npm", "go": "go",
    "rustup": "rustup", "cargo": "rust", "java": "jdk-openjdk",
    "gcc": "base-devel", "cmake": "cmake", "ffmpeg": "ffmpeg",
    "yt-dlp": "yt-dlp", "kubectl": "kubectl", "terraform": "terraform",
    "ansible": "ansible", "php": "php", "ruby": "ruby", "lua": "lua",
    "pipx": "python-pipx", "distrobox": "distrobox", "fastfetch": "fastfetch",
    "neofetch": "fastfetch", "rclone": "rclone", "restic": "restic",
    "wireguard": "wireguard-tools", "wg": "wireguard-tools",
    "syncthing": "syncthing", "flatpak": "flatpak", "qemu-system-x86_64": "qemu-full",
}

# XDG_CURRENT_DESKTOP token -> Genesi desktop chooser id (packagechooser.conf).
# The closest Genesi desktop is offered for ones Genesi doesn't ship.
DE_MAP = {
    "kde": "KDE-Desktop", "plasma": "KDE-Desktop",
    "gnome": "GNOME-Desktop", "ubuntu": "GNOME-Desktop", "unity": "GNOME-Desktop",
    "pantheon": "GNOME-Desktop", "pop": "GNOME-Desktop",
    "xfce": "Xfce4",
    "x-cinnamon": "Cinnamon", "cinnamon": "Cinnamon",
    "mate": "Cinnamon",
    "budgie": "Budgie-Desktop", "budgie-desktop": "Budgie-Desktop",
    "lxde": "LXDE-Desktop", "lxqt": "LXDE-Desktop",
    "cosmic": "Cosmic",
    "niri": "Niri",
    "hyprland": "Hyprland-Desktop",
    "sway": "Hyprland-Desktop",
}

GENESI_DESKTOPS = (
    ("KDE-Desktop", "Plasma"),
    ("Hyprland-Desktop", "Hyprland + caelestia"),
    ("GNOME-Desktop", "GNOME"),
    ("Xfce4", "Xfce"),
    ("Cinnamon", "Cinnamon"),
    ("Budgie-Desktop", "Budgie"),
    ("LXDE-Desktop", "LXDE"),
    ("Cosmic", "COSMIC"),
    ("Niri", "Niri"),
)


def map_package(name, family):
    """Genesi target for a distro package, as (kind, target, confidence).

    confidence: "known" (in the tables), "same" (the old system IS Arch-based,
    so the name is already an Arch name), "likely" (guessed: same name) or
    "skip" (a package-manager front-end with no place on Genesi).
    """
    if name in PKG_MAP:
        rule = PKG_MAP[name]
        if rule is None:
            return (None, None, "skip")
        return (rule[0], rule[1], "known")
    for prefix, rule in PREFIX_MAP:
        if name.startswith(prefix):
            return (rule[0], rule[1], "known")
    if family == "arch":
        return ("pacman", name, "same")
    return ("pacman", name, "likely")


def map_snap(name):
    if name in SNAP_MAP:
        rule = SNAP_MAP[name]
        if rule is None:
            return (None, None, "skip")
        return (rule[0], rule[1], "known")
    # Unknown snap: the restore step searches Flathub by name.
    return ("flatpak-search", name, "likely")


def is_de_core(owner):
    """True when an app's owning package is part of the old desktop itself.

    A package the tables know as a real app (gnome-boxes, gnome-tweaks) is
    never core, whatever its prefix says.
    """
    if not owner or owner in PKG_MAP:
        return False
    return owner in DE_CORE_NAMES or owner.startswith(DE_CORE_PREFIXES)


def is_snap_runtime(name):
    return name.startswith(SNAP_RUNTIME_PREFIXES)


def genesi_desktop_for(xdg_current_desktop):
    """Best Genesi chooser id for the running desktop, or the Plasma default."""
    for token in (xdg_current_desktop or "").lower().replace(";", ":").split(":"):
        token = token.strip()
        if token in DE_MAP:
            return DE_MAP[token]
    return "KDE-Desktop"
