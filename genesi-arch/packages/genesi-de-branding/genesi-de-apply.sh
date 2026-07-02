#!/bin/bash
# Genesi OS — per-DE "coat of paint" applied at LOGIN for the current user.
#
# WHY a login-time script (not /etc/skel): skel only seeds NEW users, so an
# existing account (created during install) would never get the Genesi look —
# the same gap that bit the KDE panel migration. Running from
# /etc/xdg/autostart for EVERY user means this also retrofits systems updated
# via `genesi update` (install the package once, log out/in — no reinstall).
#
# KDE Plasma and Hyprland+caelestia ship their OWN dedicated branding
# (genesi-kde-settings / genesi-caelestia-settings), so this no-ops there and
# only touches the GTK DEs imported from CachyOS (GNOME/Xfce/Cinnamon/MATE).
#
# Everything is best-effort and guarded: a missing tool or schema must never
# break the user's login. Re-applies only when VERSION changes, so it doesn't
# fight the user's own tweaks on every single login.
set -u

VERSION=1
WALL="/usr/share/wallpapers/genesi/wallpaper.png"
ACCENT="#1D9E75"          # Genesi brand green
GTK_THEME="adw-gtk3-dark" # from adw-gtk-theme
ICON_THEME="Papirus-Dark" # from papirus-icon-theme
MARK="${XDG_CONFIG_HOME:-$HOME/.config}/genesi/de-branding.applied"

# ── only run on the GTK desktops we brand ──────────────────────────────────
de="$(printf '%s' "${XDG_CURRENT_DESKTOP:-}" | tr '[:upper:]' '[:lower:]')"
case "$de" in
    *xfce*|*gnome*|*cinnamon*|*mate*) : ;;
    *) exit 0 ;;   # KDE / Hyprland / anything else: leave it alone
esac

# ── idempotency: skip if this VERSION was already applied ──────────────────
[ -f "$MARK" ] && [ "$(cat "$MARK" 2>/dev/null)" = "$VERSION" ] && exit 0
mkdir -p "$(dirname "$MARK")" 2>/dev/null || true

[ -r "$WALL" ] || WALL=""   # don't point a DE at a wallpaper that isn't there

# ── helpers ────────────────────────────────────────────────────────────────
have() { command -v "$1" >/dev/null 2>&1; }

# append a .desktop to a gsettings string-array key without dropping existing
# entries (used for GNOME dash / Cinnamon+MATE favorites)
_append_fav() {
    local schema="$1" key="$2" item="$3" cur
    have gsettings || return 0
    cur="$(gsettings get "$schema" "$key" 2>/dev/null)" || return 0
    case "$cur" in
        *"'$item'"*) return 0 ;;                      # already present
    esac
    case "$cur" in
        "@as []"|"[]") gsettings set "$schema" "$key" "['$item']" 2>/dev/null || true ;;
        "["*)          gsettings set "$schema" "$key" "${cur%]}, '$item']" 2>/dev/null || true ;;
    esac
}

apply_gnome() {
    have gsettings || return 0
    [ -n "$WALL" ] && {
        gsettings set org.gnome.desktop.background picture-uri "file://$WALL" 2>/dev/null || true
        gsettings set org.gnome.desktop.background picture-uri-dark "file://$WALL" 2>/dev/null || true
        gsettings set org.gnome.desktop.screensaver picture-uri "file://$WALL" 2>/dev/null || true
    }
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface accent-color 'green' 2>/dev/null || true  # GNOME 47+
    _append_fav org.gnome.shell favorite-apps genesi-code.desktop
}

apply_cinnamon() {
    have gsettings || return 0
    [ -n "$WALL" ] && gsettings set org.cinnamon.desktop.background picture-uri "file://$WALL" 2>/dev/null || true
    gsettings set org.cinnamon.desktop.interface gtk-theme "$GTK_THEME" 2>/dev/null || true
    gsettings set org.cinnamon.desktop.interface icon-theme "$ICON_THEME" 2>/dev/null || true
    gsettings set org.cinnamon.theme name "$GTK_THEME" 2>/dev/null || true
    gsettings set org.cinnamon.desktop.wm.preferences theme "$GTK_THEME" 2>/dev/null || true
    _append_fav org.cinnamon favorite-apps genesi-code.desktop
}

apply_mate() {
    have gsettings || return 0
    [ -n "$WALL" ] && {
        gsettings set org.mate.background picture-filename "$WALL" 2>/dev/null || true
    }
    gsettings set org.mate.interface gtk-theme "$GTK_THEME" 2>/dev/null || true
    gsettings set org.mate.interface icon-theme "$ICON_THEME" 2>/dev/null || true
    gsettings set org.mate.Marco.general theme "$GTK_THEME" 2>/dev/null || true
}

apply_xfce() {
    have xfconf-query || return 0
    # GTK theme + icons + window-manager theme
    xfconf-query -c xsettings   -p /Net/ThemeName      -s "$GTK_THEME"  2>/dev/null || true
    xfconf-query -c xsettings   -p /Net/IconThemeName  -s "$ICON_THEME" 2>/dev/null || true
    xfconf-query -c xfwm4       -p /general/theme      -s "Default"     2>/dev/null || true
    # Wallpaper: set it on every connected monitor/workspace property Xfce exposes
    if [ -n "$WALL" ] && have xfconf-query; then
        xfconf-query -c xfce4-desktop -l 2>/dev/null | grep -E '/last-image$' | while read -r prop; do
            xfconf-query -c xfce4-desktop -p "$prop" -s "$WALL" 2>/dev/null || true
        done
        # first-boot fallback: the property tree may not exist yet
        xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/last-image \
            -n -t string -s "$WALL" 2>/dev/null || true
    fi
    # Rounded corners + blur via picom — but NOT inside a VM, where compositing
    # over software rendering (VirtualBox/VMSVGA) tears or stalls. Real hardware
    # only. Genesi's "glass" is otherwise a KWin feature and can't be replicated
    # on xfwm4 beyond what picom gives.
    if have picom && have systemd-detect-virt && [ "$(systemd-detect-virt 2>/dev/null)" = "none" ]; then
        xfconf-query -c xfwm4 -p /general/use_compositing -s false 2>/dev/null || true
        pgrep -x picom >/dev/null 2>&1 || setsid picom -b --config /etc/genesi/picom-genesi.conf >/dev/null 2>&1 || true
    fi
}

case "$de" in
    *gnome*)    apply_gnome ;;
    *cinnamon*) apply_cinnamon ;;
    *mate*)     apply_mate ;;
    *xfce*)     apply_xfce ;;
esac

echo "$VERSION" > "$MARK" 2>/dev/null || true
exit 0
