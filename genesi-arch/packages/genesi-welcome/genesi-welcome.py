#!/usr/bin/env python3
"""
Genesi OS Welcome — the front door of Genesi OS.

One app, two modes (like CachyOS Hello):
  * LIVE ISO   → shows "Install Genesi OS" + a live-only "Repair installed
                 system" tool, so the user can install or rescue from the medium.
  * INSTALLED  → hides the installer; it's the everyday hub (docs, support,
                 project links, app installer, and a maintenance page).

The maintenance page mirrors CachyOS Hello's fixes/tweaks: update, reinstall
all packages, reset keyrings, pacman-key --init, clear the pacman db lock, clean
the cache, remove orphans, install the gaming bundle, Snapper support, refresh
mirrors, switch DNS, install SpoofDPI, plus service toggles.
"""
import os
import sys
import shlex
import shutil
import subprocess

from PyQt5.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout, QPushButton,
    QLabel, QGridLayout, QFrame, QStackedWidget, QComboBox, QCheckBox,
    QScrollArea, QSizePolicy,
)
from PyQt5.QtCore import Qt
from PyQt5.QtGui import QFont, QPixmap

AUTOSTART = os.path.expanduser("~/.config/autostart/genesi-welcome.desktop")
REPO = "https://github.com/Genesi-OS/GenesiOS"


def is_live():
    """True when running from the live ISO (archiso medium), not an install."""
    if os.path.exists("/run/archiso"):
        return True
    try:
        with open("/proc/cmdline") as f:
            cmd = f.read()
        return "archiso" in cmd or "copytoram" in cmd
    except OSError:
        return False


# ── i18n (lean: pt-BR default + English) ─────────────────────────────────────
STR = {
    "pt-BR": {
        "title": "Genesi OS",
        "tagline": "Evolua. Conecte-se. Crie.",
        "intro": "Bem-vindo à nova era da computação inteligente. O Genesi OS foi "
                 "projetado para extrair o máximo de desempenho com IA local e "
                 "ferramentas para desenvolvedores.",
        "docs": "Documentação", "support": "Suporte", "project": "Projeto",
        "readme": "Leia-me", "release": "Notas de versão", "wiki": "Wiki",
        "forums": "Fórum / Issues", "software": "Programas", "involved": "Participe",
        "development": "Desenvolvimento", "donate": "Doar",
        "install": "Instalar Genesi OS", "install_d": "Instale o sistema no seu disco",
        "settings": "Configurações", "settings_d": "Personalize o Genesi OS",
        "aimode": "Modo IA", "aimode_d": "Gerencie o otimizador de IA",
        "apps": "Instalar Apps", "apps_d": "Catálogo de aplicativos",
        "tweaks": "Apps / Ajustes", "tweaks_d": "Manutenção e ajustes do sistema",
        "community": "Comunidade", "community_d": "Junte-se a nós no GitHub",
        "launch_start": "Abrir ao iniciar", "language": "Idioma", "back": "Voltar",
        "maint_title": "Manutenção e Ajustes",
        "fixes": "Correções", "tweaks_h": "Ajustes", "apps_h": "Aplicações",
        "update": "Atualizar Sistema",
        "reinstall": "Reinstalar Todos os Pacotes",
        "keyrings": "Reset Keyrings",
        "keyinit": "pacman-key --init",
        "dblock": "Remover Trava do BD Pacman (db lock)",
        "cache": "Limpar Cache de Pacotes",
        "orphans": "Remover Pacotes Órfãos",
        "gaming": "Instalar Pacotes de Jogos",
        "snapper": "Instalar Suporte a Snapper",
        "mirrors": "Atualizar Espelhos",
        "dns": "Trocar Servidor DNS",
        "spoofdpi": "Instalar SpoofDPI",
        "repair": "Reparar Sistema Instalado",
        "pkginstaller": "Genesi Package Installer",
        "kernelmgr": "Gerenciador de Kernel",
        "svc_psd": "Profile-sync-daemon", "svc_oomd": "Systemd-oomd",
        "svc_bpftune": "Bpftune", "svc_ananicy": "Ananicy Cpp",
        "svc_bt": "Bluetooth",
    },
    "English": {
        "title": "Genesi OS",
        "tagline": "Evolve. Connect. Create.",
        "intro": "Welcome to the new era of intelligent computing. Genesi OS is "
                 "built to squeeze the most out of local AI and developer tools.",
        "docs": "Documentation", "support": "Support", "project": "Project",
        "readme": "Read me", "release": "Release info", "wiki": "Wiki",
        "forums": "Forum / Issues", "software": "Software", "involved": "Get involved",
        "development": "Development", "donate": "Donate",
        "install": "Install Genesi OS", "install_d": "Install the system to disk",
        "settings": "Settings", "settings_d": "Personalize Genesi OS",
        "aimode": "AI Mode", "aimode_d": "Manage the AI optimizer",
        "apps": "Install Apps", "apps_d": "Application catalog",
        "tweaks": "Apps / Tweaks", "tweaks_d": "System maintenance and tweaks",
        "community": "Community", "community_d": "Join us on GitHub",
        "launch_start": "Launch at start", "language": "Language", "back": "Back",
        "maint_title": "Maintenance & Tweaks",
        "fixes": "Fixes", "tweaks_h": "Tweaks", "apps_h": "Applications",
        "update": "Update System",
        "reinstall": "Reinstall All Packages",
        "keyrings": "Reset Keyrings",
        "keyinit": "pacman-key --init",
        "dblock": "Remove Pacman DB Lock",
        "cache": "Clean Package Cache",
        "orphans": "Remove Orphan Packages",
        "gaming": "Install Gaming Packages",
        "snapper": "Install Snapper Support",
        "mirrors": "Refresh Mirrors",
        "dns": "Change DNS Server",
        "spoofdpi": "Install SpoofDPI",
        "repair": "Repair Installed System",
        "pkginstaller": "Genesi Package Installer",
        "kernelmgr": "Kernel Manager",
        "svc_psd": "Profile-sync-daemon", "svc_oomd": "Systemd-oomd",
        "svc_bpftune": "Bpftune", "svc_ananicy": "Ananicy Cpp",
        "svc_bt": "Bluetooth",
    },
}

STYLE = """
/* Use the Genesi *system* window colour (the same dark blue every native app
   gets from the Genesi color scheme), not a bespoke green panel — so Welcome
   matches Dolphin/Konsole instead of standing out. KWin's compositor applies
   the same glass/blur to this opaque surface as to every other window. */
QWidget#root { background-color: #0D2030; }
QLabel { color: #E6F1EE; }
QLabel#title { color: #1D9E75; }
QLabel#subtitle { color: #A0C0B0; }
QLabel#section { color: #7FD9BD; font-weight: bold; }
QPushButton {
    background-color: #0F6E56; color: white; border-radius: 10px;
    padding: 10px; font-size: 13px; font-weight: bold;
}
QPushButton:hover { background-color: #1D9E75; }
QPushButton#link {
    background-color: rgba(15,110,86,0.25); font-weight: normal; padding: 8px;
}
QPushButton#link:hover { background-color: rgba(29,158,117,0.45); }
QPushButton#danger { background-color: #7A2E2E; }
QPushButton#danger:hover { background-color: #A53E3E; }
QFrame#card {
    background-color: rgba(20,49,69,0.55);
    border: 1px solid rgba(29,158,117,0.4); border-radius: 15px;
}
QCheckBox { color: #E6F1EE; }
/* The combo needs an explicit dark background: on the GTK desktops
   (GNOME/Xfce/Cinnamon/MATE) the widget otherwise inherits the system's light
   palette, giving unreadable light text on a white field/popup. */
QComboBox {
    color: #E6F1EE; background-color: #143145;
    border: 1px solid rgba(29,158,117,0.4); border-radius: 6px; padding: 3px 8px;
}
QComboBox:hover { border-color: #1D9E75; }
QComboBox QAbstractItemView {
    color: #E6F1EE; background-color: #0D2030;
    selection-background-color: #1D9E75; selection-color: #06121A;
    border: 1px solid rgba(29,158,117,0.4); outline: none;
}
QScrollArea { border: none; }
"""

# Interactive DNS switcher: prefers systemd-resolved (a drop-in, reversible),
# falls back to /etc/resolv.conf. Offers a few well-known resolvers.
DNS_CMD = (
    "echo 'DNS: 1) Cloudflare 1.1.1.1  2) Google 8.8.8.8  3) Quad9 9.9.9.9'; "
    "read -rp 'Choice [1-3]: ' n; "
    "case \"$n\" in 1) D=1.1.1.1;; 2) D=8.8.8.8;; 3) D=9.9.9.9;; "
    "*) echo cancelled; exit 0;; esac; "
    "if systemctl is-active systemd-resolved >/dev/null 2>&1; then "
    "mkdir -p /etc/systemd/resolved.conf.d; "
    "printf '[Resolve]\\nDNS=%s\\n' \"$D\" > /etc/systemd/resolved.conf.d/genesi-dns.conf; "
    "systemctl restart systemd-resolved; "
    "else printf 'nameserver %s\\n' \"$D\" > /etc/resolv.conf; fi; "
    "echo \"DNS set to $D\""
)

# Maintenance actions: (string-key, object-name, root-shell-command)
# guard helpers keep destructive ops from erroring on a no-op (e.g. no orphans).
MAINT_ACTIONS = [
    ("update",    "",       "pacman -Syu"),
    ("reinstall", "",       "pacman -Qqn | pacman -S --noconfirm -"),
    ("keyrings",  "",       "rm -rf /etc/pacman.d/gnupg && pacman-key --init && "
                            "pacman-key --populate"),
    ("keyinit",   "",       "pacman-key --init"),
    ("dblock",    "",       "rm -f /var/lib/pacman/db.lck && echo 'db.lck removed'"),
    ("cache",     "",       "pacman -Sc"),
    ("orphans",   "",       "o=$(pacman -Qtdq || true); "
                            "[ -n \"$o\" ] && pacman -Rns $o || echo 'No orphans.'"),
    ("gaming",    "",       "pacman -S --needed cachyos-gaming-meta "
                            "cachyos-gaming-applications"),
    ("snapper",   "",       "pacman -S --needed snapper snap-pac"),
    ("mirrors",   "",       "command -v cachyos-rate-mirrors >/dev/null && "
                            "cachyos-rate-mirrors || reflector --latest 20 "
                            "--sort rate --save /etc/pacman.d/mirrorlist"),
    ("dns",       "",       DNS_CMD),
    ("spoofdpi",  "",       "pacman -S --needed spoofdpi || echo "
                            "'spoofdpi: try the Genesi Package Installer / AUR.'"),
]

# Service toggles: (string-key, unit, user-scope?)
SERVICES = [
    ("svc_psd",     "psd.service",         True),
    ("svc_oomd",    "systemd-oomd.service", False),
    ("svc_bpftune", "bpftune.service",     False),
    ("svc_ananicy", "ananicy-cpp.service", False),
    ("svc_bt",      "bluetooth.service",   False),
]

# Interactive chroot repair (live ISO only). The user picks the root partition;
# we mount it, refresh keys, and run a full upgrade inside arch-chroot.
REPAIR_SCRIPT = r"""
set -e
echo '=== Genesi: repair an installed system (from the live ISO) ==='
echo 'Disks / partitions:'; lsblk -f
echo
read -rp 'Root partition of the installed system (e.g. /dev/nvme0n1p2): ' ROOT
[ -b "$ROOT" ] || { echo "Not a block device: $ROOT"; exit 1; }

# 1) Filesystem check/repair FIRST. A root corrupted by an unclean shutdown
#    won't mount ("Structure needs cleaning") — which used to abort the whole
#    repair before it did anything. Repair the fs for its type up front.
FSTYPE=$(sudo blkid -o value -s TYPE "$ROOT" 2>/dev/null || true)
echo ">>> Filesystem on $ROOT: ${FSTYPE:-unknown}"
case "$FSTYPE" in
  xfs)
    echo ">>> Repairing XFS (xfs_repair)…"
    if ! sudo xfs_repair "$ROOT"; then
        echo ">>> The XFS log is dirty and cannot be replayed from the live ISO."
        echo ">>> Zeroing the log (xfs_repair -L) — recovers the fs, but may drop"
        echo ">>> the most recent unsynced writes."
        sudo xfs_repair -L "$ROOT"
    fi
    ;;
  ext2|ext3|ext4)
    echo ">>> Checking the ext filesystem (e2fsck -fy)…"
    sudo e2fsck -fy "$ROOT" || true
    ;;
  btrfs)
    echo ">>> Checking btrfs…"
    sudo btrfs check "$ROOT" || true
    ;;
  *)
    echo ">>> Unrecognised filesystem; skipping the fsck step." ;;
esac

# 2) Mount, then optionally refresh keys + upgrade packages.
M=/mnt/genesi-repair
sudo mkdir -p "$M"
echo ">>> Mounting $ROOT …"
sudo mount "$ROOT" "$M"
echo ">>> Mounted OK."
read -rp 'Also run a full package upgrade inside the install? [y/N]: ' DOUP
if [ "$DOUP" = y ] || [ "$DOUP" = Y ]; then
    echo ">>> Refreshing keyrings and upgrading inside the install…"
    sudo arch-chroot "$M" bash -c 'pacman-key --init; pacman-key --populate; pacman -Syu'
fi
sudo umount -R "$M"
echo '>>> Done. You can reboot into the installed system.'
"""


class GenesiWelcome(QMainWindow):
    def __init__(self):
        super().__init__()
        self.lang = "pt-BR"
        self.live = is_live()
        self.setWindowTitle("Genesi OS")
        self.setMinimumSize(820, 640)
        self.setStyleSheet(STYLE)
        self.stack = QStackedWidget()
        self.setCentralWidget(self.stack)
        self._build()

    def tr(self, key):
        return STR[self.lang].get(key, key)

    # ── (re)build both pages (called on language change) ────────────────────
    def _build(self):
        while self.stack.count():
            w = self.stack.widget(0)
            self.stack.removeWidget(w)
            w.deleteLater()
        self.stack.addWidget(self._welcome_page())
        self.stack.addWidget(self._maintenance_page())
        self.stack.setCurrentIndex(0)

    # ── header (shared) ─────────────────────────────────────────────────────
    def _header(self):
        row = QHBoxLayout()
        logo = QLabel()
        pix = QPixmap("/usr/share/pixmaps/genesi-logo.png")
        if not pix.isNull():
            logo.setPixmap(pix.scaled(72, 72, Qt.KeepAspectRatio,
                                      Qt.SmoothTransformation))
        col = QVBoxLayout()
        t = QLabel(self.tr("title")); t.setObjectName("title")
        t.setFont(QFont("Segoe UI", 26, QFont.Bold))
        s = QLabel(self.tr("tagline")); s.setObjectName("subtitle")
        s.setFont(QFont("Segoe UI", 13))
        col.addWidget(t); col.addWidget(s)
        row.addWidget(logo); row.addLayout(col); row.addStretch()
        return row

    # ── page 0: welcome / hub ───────────────────────────────────────────────
    def _welcome_page(self):
        page = QWidget(); page.setObjectName("root")
        lay = QVBoxLayout(page)
        lay.setContentsMargins(36, 28, 36, 24); lay.setSpacing(16)
        lay.addLayout(self._header())

        intro = QLabel(self.tr("intro")); intro.setWordWrap(True)
        intro.setFont(QFont("Segoe UI", 11))
        lay.addWidget(intro)

        # link sections (Documentation / Support / Project)
        sections = QHBoxLayout(); sections.setSpacing(14)
        sections.addLayout(self._link_section("docs", [
            ("readme", REPO + "#readme"),
            ("wiki", REPO + "/wiki"),
            ("release", REPO + "/releases"),
        ]))
        sections.addLayout(self._link_section("support", [
            ("forums", REPO + "/issues"),
            ("software", "pkginstaller"),  # special: launches the installer
        ]))
        sections.addLayout(self._link_section("project", [
            ("involved", REPO + "/blob/main/CONTRIBUTING.md"),
            ("development", REPO),
            ("donate", REPO),
        ]))
        lay.addLayout(sections)
        lay.addStretch()

        # primary actions
        grid = QGridLayout(); grid.setSpacing(16)
        actions = []
        if self.live:
            actions.append(("install", "install_d", self.launch_installer, False))
        actions += [
            ("settings", "settings_d", self.launch_settings, False),
            ("aimode", "aimode_d", self.launch_ai_mode, False),
            ("apps", "apps_d", self.launch_pkginstaller, False),
            ("tweaks", "tweaks_d", lambda: self.stack.setCurrentIndex(1), False),
            ("community", "community_d", lambda: self.open_url(REPO), False),
        ]
        for i, (tkey, dkey, cb, _) in enumerate(actions):
            grid.addWidget(self._card(self.tr(tkey), self.tr(dkey), cb), i // 2, i % 2)
        lay.addLayout(grid)

        # footer: language + launch-at-start
        footer = QHBoxLayout()
        footer.addWidget(QLabel(self.tr("language") + ":"))
        combo = QComboBox(); combo.addItems(list(STR.keys()))
        combo.setCurrentText(self.lang)
        combo.currentTextChanged.connect(self._set_lang)
        footer.addWidget(combo); footer.addStretch()
        chk = QCheckBox(self.tr("launch_start"))
        chk.setChecked(not self._autostart_disabled())
        chk.toggled.connect(self._set_autostart)
        footer.addWidget(chk)
        lay.addLayout(footer)
        return page

    def _link_section(self, header_key, items):
        col = QVBoxLayout(); col.setSpacing(6)
        h = QLabel(self.tr(header_key)); h.setObjectName("section")
        col.addWidget(h)
        for tkey, target in items:
            b = QPushButton(self.tr(tkey)); b.setObjectName("link")
            b.setCursor(Qt.PointingHandCursor)
            if target == "pkginstaller":
                b.clicked.connect(self.launch_pkginstaller)
            else:
                b.clicked.connect(lambda _, u=target: self.open_url(u))
            col.addWidget(b)
        col.addStretch()
        return col

    def _card(self, title, desc, cb):
        card = QFrame(); card.setObjectName("card")
        cl = QVBoxLayout(card)
        btn = QPushButton(title); btn.setCursor(Qt.PointingHandCursor)
        btn.clicked.connect(cb)
        d = QLabel(desc); d.setAlignment(Qt.AlignCenter)
        d.setStyleSheet("color:#A0C0B0; font-size:11px;")
        cl.addWidget(btn); cl.addWidget(d)
        return card

    # ── page 1: maintenance ─────────────────────────────────────────────────
    def _maintenance_page(self):
        page = QWidget(); page.setObjectName("root")
        outer = QVBoxLayout(page)
        outer.setContentsMargins(36, 20, 36, 20); outer.setSpacing(12)

        top = QHBoxLayout()
        back = QPushButton("← " + self.tr("back"))
        back.setObjectName("link"); back.setMaximumWidth(140)
        back.clicked.connect(lambda: self.stack.setCurrentIndex(0))
        title = QLabel(self.tr("maint_title")); title.setObjectName("title")
        title.setFont(QFont("Segoe UI", 18, QFont.Bold))
        top.addWidget(back); top.addStretch(); top.addWidget(title); top.addStretch()
        spacer = QWidget(); spacer.setFixedWidth(140); top.addWidget(spacer)
        outer.addLayout(top)

        scroll = QScrollArea(); scroll.setWidgetResizable(True)
        inner = QWidget(); inner.setObjectName("root")
        lay = QVBoxLayout(inner); lay.setSpacing(10)

        # Fixes grid
        lay.addWidget(self._h(self.tr("fixes")))
        fixes = QGridLayout(); fixes.setSpacing(10)
        for i, (key, oname, cmd) in enumerate(MAINT_ACTIONS):
            b = QPushButton(self.tr(key)); b.setCursor(Qt.PointingHandCursor)
            if oname:
                b.setObjectName(oname)
            b.clicked.connect(lambda _, t=self.tr(key), c=cmd: self.run_root(t, c))
            fixes.addWidget(b, i // 3, i % 3)
        # live-only: repair an installed system
        if self.live:
            rb = QPushButton(self.tr("repair")); rb.setObjectName("danger")
            rb.setCursor(Qt.PointingHandCursor)
            rb.clicked.connect(self.repair_system)
            fixes.addWidget(rb, len(MAINT_ACTIONS) // 3, len(MAINT_ACTIONS) % 3)
        lay.addLayout(fixes)

        # Service toggles
        lay.addWidget(self._h(self.tr("tweaks_h")))
        toggles = QGridLayout(); toggles.setSpacing(8)
        for i, (key, unit, user) in enumerate(SERVICES):
            chk = QCheckBox(self.tr(key))
            chk.setChecked(self._svc_enabled(unit, user))
            chk.toggled.connect(
                lambda on, u=unit, us=user, c=None: self._svc_toggle(u, us, on))
            toggles.addWidget(chk, i // 3, i % 3)
        lay.addLayout(toggles)

        # Applications
        lay.addWidget(self._h(self.tr("apps_h")))
        apps = QHBoxLayout(); apps.setSpacing(10)
        pi = QPushButton(self.tr("pkginstaller")); pi.setCursor(Qt.PointingHandCursor)
        pi.clicked.connect(self.launch_pkginstaller)
        km = QPushButton(self.tr("kernelmgr")); km.setCursor(Qt.PointingHandCursor)
        km.clicked.connect(self.launch_kernel_manager)
        apps.addWidget(pi); apps.addWidget(km)
        lay.addLayout(apps)
        lay.addStretch()

        scroll.setWidget(inner)
        outer.addWidget(scroll)
        return page

    def _h(self, text):
        lbl = QLabel(text); lbl.setObjectName("section")
        lbl.setFont(QFont("Segoe UI", 12, QFont.Bold))
        return lbl

    # ── language / autostart ────────────────────────────────────────────────
    def _set_lang(self, lang):
        if lang in STR and lang != self.lang:
            self.lang = lang
            self._build()

    def _autostart_disabled(self):
        try:
            with open(AUTOSTART) as f:
                return "Hidden=true" in f.read()
        except OSError:
            return False

    def _set_autostart(self, on):
        try:
            if on:
                if os.path.exists(AUTOSTART):
                    os.remove(AUTOSTART)
            else:
                os.makedirs(os.path.dirname(AUTOSTART), exist_ok=True)
                with open(AUTOSTART, "w") as f:
                    f.write("[Desktop Entry]\nType=Application\n"
                            "Name=Genesi OS Welcome\nHidden=true\n")
        except OSError:
            pass

    # ── services ────────────────────────────────────────────────────────────
    def _svc_enabled(self, unit, user):
        cmd = ["systemctl", "is-enabled", unit]
        if user:
            cmd.insert(1, "--user")
        try:
            out = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
            return out.stdout.strip() == "enabled"
        except Exception:
            return False

    def _svc_toggle(self, unit, user, on):
        verb = "enable" if on else "disable"
        if user:
            self.run_user(["systemctl", "--user", verb, "--now", unit])
        else:
            self.run_user(["pkexec", "systemctl", verb, "--now", unit])

    # ── command runners ─────────────────────────────────────────────────────
    def _terminal(self):
        for term in ("konsole", "alacritty", "kitty", "xterm",
                     "x-terminal-emulator"):
            if shutil.which(term):
                return term
        return None

    def run_root(self, title, cmd):
        """Run a privileged maintenance command in a terminal so the user sees
        the output and the sudo prompt."""
        term = self._terminal()
        inner = ("echo '=== %s ==='; sudo bash -c %s; "
                 "echo; read -p 'Enter…' _" % (title, shlex.quote(cmd)))
        if term:
            subprocess.Popen([term, "-e", "bash", "-lc", inner])
        else:
            subprocess.Popen(["sudo", "bash", "-c", cmd])

    def run_user(self, argv):
        try:
            subprocess.Popen(argv)
        except FileNotFoundError:
            pass

    def repair_system(self):
        term = self._terminal()
        inner = "bash -lc %s; echo; read -p 'Enter…' _" % shlex.quote(REPAIR_SCRIPT)
        if term:
            subprocess.Popen([term, "-e", "bash", "-lc", inner])

    # ── launchers ───────────────────────────────────────────────────────────
    def launch_installer(self):
        self.run_user(["pkexec", "calamares"])

    def launch_settings(self):
        self.run_user(["systemsettings"])

    def launch_ai_mode(self):
        if shutil.which("genesi-ai-monitor"):
            self.run_user(["genesi-ai-monitor"]); return
        term = self._terminal()
        if term:
            subprocess.Popen([term, "-e", "bash", "-lc",
                              "genesi-ai-mode info; read -p 'Enter…' _"])
        else:
            self.run_user(["genesi-ai-mode", "on"])

    def launch_pkginstaller(self):
        # The Genesi Package Installer binary is `cachyos-pi` (fork's internal
        # name kept to avoid breaking its build); try the friendly names too.
        for b in ("cachyos-pi", "genesi-packageinstaller", "cachyos-packageinstaller"):
            if shutil.which(b):
                self.run_user([b]); return
        self.open_url(REPO)

    def launch_kernel_manager(self):
        for b in ("cachyos-kernel-manager", "genesi-kernel-manager"):
            if shutil.which(b):
                self.run_user([b]); return

    def open_url(self, url):
        self.run_user(["xdg-open", url])


if __name__ == "__main__":
    app = QApplication(sys.argv)
    win = GenesiWelcome()
    win.show()
    sys.exit(app.exec_())
