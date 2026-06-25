#!/bin/bash
# Genesi OS Runtime Branding Script
# Runs on every boot via systemd service AND XDG autostart.
# Ensures Genesi OS branding is applied even if customize_airootfs.sh
# didn't run during the build.

OVERRIDE_DIR="/usr/share/genesi/skel-override"

# ============================================================
# 1. Apply desktop config overrides to liveuser
# ============================================================
if [ -d "$OVERRIDE_DIR" ]; then
    # Apply to liveuser home
    if [ -d /home/liveuser ]; then
        cp -rf "$OVERRIDE_DIR"/. /home/liveuser/
        # Make desktop shortcuts executable
        chmod +x /home/liveuser/Desktop/*.desktop 2>/dev/null || true
        chown -R liveuser:liveuser /home/liveuser/ 2>/dev/null || true
    fi
    # Apply to /etc/skel for new users (installed system)
    cp -rf "$OVERRIDE_DIR"/. /etc/skel/
    chmod +x /etc/skel/Desktop/*.desktop 2>/dev/null || true
fi

# ============================================================
# 2. System identity
# ============================================================
echo "genesi" > /etc/hostname

cat > /etc/os-release << 'OSRELEASE'
NAME="Genesi OS"
PRETTY_NAME="Genesi OS"
ID=genesi
ID_LIKE=arch
BUILD_ID=rolling
ANSI_COLOR="38;2;29;158;117"
HOME_URL="https://github.com/Genesi-OS/GenesiOS"
SUPPORT_URL="https://github.com/Genesi-OS/GenesiOS/issues"
BUG_REPORT_URL="https://github.com/Genesi-OS/GenesiOS/issues"
LOGO=genesi
OSRELEASE

cat > /etc/lsb-release << 'LSB'
LSB_VERSION=2.0
DISTRIB_ID=GenesiOS
DISTRIB_RELEASE=rolling
DISTRIB_DESCRIPTION="Genesi OS Linux"
LSB

# ============================================================
# 3. Rebrand CachyOS Hello
# ============================================================
if [ -f /usr/share/applications/cachyos-hello.desktop ]; then
    sed -i 's/CachyOS Hello/Genesi OS Welcome/g' /usr/share/applications/cachyos-hello.desktop
    sed -i 's/Name=CachyOS/Name=Genesi OS/g' /usr/share/applications/cachyos-hello.desktop
    sed -i 's/Comment=.*CachyOS.*/Comment=Welcome to Genesi OS/g' /usr/share/applications/cachyos-hello.desktop
fi
if [ -f /etc/cachyos-hello.conf ]; then
    sed -i 's/CachyOS/Genesi OS/g' /etc/cachyos-hello.conf
fi
# Remove cachyos-hello autostart (we'll have our own welcome app)
rm -f /etc/xdg/autostart/cachyos-hello.desktop 2>/dev/null || true

# ============================================================
# 4. Rebrand Calamares
# ============================================================
# Copy CachyOS branding to genesi folder and patch it
if [ -d /usr/share/calamares/branding/cachyos ]; then
    mkdir -p /usr/share/calamares/branding/genesi
    cp -rf /usr/share/calamares/branding/cachyos/* /usr/share/calamares/branding/genesi/ 2>/dev/null || true

    # Copy our custom images over (if they exist)
    for img in logo.png icon.png welcome.png; do
        if [ -f /usr/share/calamares/branding/genesi/$img ]; then
            : # Our images are already there from airootfs
        fi
    done

    # Patch branding.desc
    if [ -f /usr/share/calamares/branding/genesi/branding.desc ]; then
        sed -i \
            -e 's/productName:.*CachyOS/productName:       Genesi OS/' \
            -e 's/shortProductName:.*CachyOS/shortProductName:  Genesi OS/' \
            -e 's/versionedName:.*CachyOS/versionedName:     Genesi OS/' \
            -e 's/shortVersionedName:.*CachyOS/shortVersionedName: Genesi OS/' \
            -e 's/bootLoaderEntryName:.*CachyOS/bootLoaderEntryName: Genesi OS/' \
            -e 's/componentName:.*cachyos/componentName:     genesi/' \
            -e 's|https://cachyos.org|https://github.com/Genesi-OS/GenesiOS|g' \
            /usr/share/calamares/branding/genesi/branding.desc
    fi

    # Also copy to /etc/calamares
    mkdir -p /etc/calamares/branding/genesi
    cp -rf /usr/share/calamares/branding/genesi/* /etc/calamares/branding/genesi/ 2>/dev/null || true
fi

# Update Calamares settings to use genesi branding
find /usr/share/calamares /etc/calamares -type f -name "settings*.conf" \
    -exec sed -i -e 's/branding:.*cachyos/branding: genesi/' {} + 2>/dev/null || true

# Patch all Calamares text files
for dir in /etc/calamares /usr/share/calamares; do
    if [ -d "$dir" ]; then
        find "$dir" -type f \( -name "*.conf" -o -name "*.qml" -o -name "*.yml" -o -name "*.yaml" -o -name "*.desc" \) \
            -exec sed -i -e 's/CachyOS/Genesi OS/g' {} + 2>/dev/null || true
    fi
done

# ============================================================
# 5. Replace in autostart and SDDM configs
# ============================================================
find /etc/xdg/autostart -name "*.desktop" -exec sed -i 's/CachyOS/Genesi OS/g' {} + 2>/dev/null || true
find /etc -name "*.conf" -path "*/sddm*" -exec sed -i 's/CachyOS/Genesi OS/g' {} + 2>/dev/null || true

echo "Genesi OS branding applied."
