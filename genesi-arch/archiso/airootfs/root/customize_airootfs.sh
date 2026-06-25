#!/usr/bin/env bash
# Genesi OS - customize_airootfs.sh
# Runs inside chroot AFTER packages are installed, BEFORE squashfs creation.
# Overrides all CachyOS branding with Genesi OS.

# Enable detailed logging
set -x  # Print each command before executing
exec 1> >(tee -a /var/log/genesi-customize.log)
exec 2>&1

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Genesi OS: Starting customization at $(date)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Don't use set -e - we want to continue even if some commands fail
echo ">>> Genesi OS: Applying branding..."

# ============================================================
# 0. Copy Genesi Calamares configuration (from submodule)
# ============================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ">>> Copying Calamares configuration from genesi-calamares-config..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -d /root/genesi-calamares-config-full ]; then
    # Copy all Calamares configuration (OVERWRITE existing files from cachyos-calamares-next)
    mkdir -p /etc/calamares
    mkdir -p /usr/lib/calamares
    
    # Copy branding (overwrite)
    if [ -d /root/genesi-calamares-config-full/etc/calamares/branding ]; then
        cp -rf /root/genesi-calamares-config-full/etc/calamares/branding /etc/calamares/
        echo ">>> Calamares branding copied (overwritten)"
    fi
    
    # Copy scripts (overwrite)
    if [ -d /root/genesi-calamares-config-full/etc/calamares/scripts ]; then
        cp -rf /root/genesi-calamares-config-full/etc/calamares/scripts /etc/calamares/
        chmod +x /etc/calamares/scripts/* 2>/dev/null || true
        echo ">>> Calamares scripts copied (overwritten)"

        # Defense in depth: guarantee enable-ufw exists even if the submodule
        # bump was skipped. Upstream cachyos-calamares hardcodes
        # shellprocess@enable_ufw -> /etc/calamares/scripts/enable-ufw and the
        # install aborts at job 44/46 with exit 127 if the file is missing.
        if [ ! -f /etc/calamares/scripts/enable-ufw ]; then
            mkdir -p /etc/calamares/scripts
            cat > /etc/calamares/scripts/enable-ufw <<'UFWEOF'
#!/bin/bash
set -e
if command -v ufw >/dev/null 2>&1; then
    ufw default deny incoming  || true
    ufw default allow outgoing || true
    ufw --force enable          || true
    systemctl enable ufw.service || true
else
    echo "ufw not installed, skipping"
fi
exit 0
UFWEOF
            chmod +x /etc/calamares/scripts/enable-ufw
            echo ">>> Wrote fallback /etc/calamares/scripts/enable-ufw"
        fi

        # cachyos-calamares-next ships shellprocess@btrfs_snapshot with
        # dontChroot: false, so /etc/calamares/scripts/btrfs-installation-snapshot
        # is resolved INSIDE the target chroot, not on the live ISO. The target
        # is pacstrapped without calamares, so the script is never there -> exit
        # 127 -> install aborts at job 45/46 (seen 2026-05-14 and 2026-05-16).
        # Fix: override the shellprocess config to inline the logic. Same
        # pattern as the upstream enable_ufw fix in the submodule. No external
        # script file is needed in the target chroot.
        for caldir in /etc/calamares/modules /usr/share/calamares/modules; do
            [ -d "$caldir" ] || continue
            cat > "$caldir/shellprocess_btrfs_snapshot.conf" <<'BTRFSCONF'
---
# Genesi OS: inlined override of cachyos-calamares-next's shellprocess.
# Best-effort btrfs snapshot inside the target chroot; never aborts the install.
dontChroot: false
timeout: 60
script:
    - command: |
        set -u
        ROOT_FS="$(findmnt -no FSTYPE / 2>/dev/null || true)"
        if [ "${ROOT_FS:-}" = "btrfs" ] && command -v btrfs >/dev/null 2>&1; then
            btrfs subvolume snapshot -r / /.snapshots/@initial-install 2>/dev/null || true
        fi
        exit 0

i18n:
    name: "Creating Btrfs installation snapshot"
BTRFSCONF
            echo ">>> Overrode $caldir/shellprocess_btrfs_snapshot.conf (inlined, no file dep)"
        done

        # genesi-prepare-pacman.sh upstream strips the [genesi] repo from
        # /etc/pacman.conf (live ISO) AND from the target's pacman.conf right
        # before pacstrap runs. That makes packages@online fail later with
        # "target not found: genesi-settings / genesi-calamares-branding".
        # Drop those sed lines so [genesi] survives into the target chroot.
        if [ -f /etc/calamares/scripts/genesi-prepare-pacman.sh ]; then
            sed -i '/sed -i .*genesi.*pacman\.conf/d' \
                /etc/calamares/scripts/genesi-prepare-pacman.sh
            echo ">>> Patched genesi-prepare-pacman.sh: keep [genesi] repo"
        fi

        # 2026-05-29: dropped the Xorg-noglx write from genesi-x11-detect.sh.
        # Disabling GLX kept Xorg from segfaulting in VMs but also killed
        # KWin's OpenGL compositing - so Plasma rendered without rounded
        # corners, without blur, without transparency. User confirmed
        # WindowCornerRadius=14 was correctly in ~/.config/klassyrc but
        # the windows were still square. With this revert, we trust the
        # natural Xorg fallback path (mesa llvmpipe when no real GPU
        # exists) and let KWin compose properly.
        #
        # genesi-x11-detect.sh's role is now just: force SDDM
        # DisplayServer=x11 when the target lacks a healthy KMS driver
        # (Wayland sessions are flaky on hypervisors without GPU accel,
        # X11 with software rendering is reliable). No more xorg.conf.d
        # writes from this script.
        if [ -f /etc/calamares/scripts/genesi-x11-detect.sh ]; then
            cat > /etc/calamares/scripts/genesi-x11-detect.sh <<'X11DETECTEOF'
#!/bin/bash
# Force SDDM DisplayServer=x11 in the target when the live ISO ran on a
# guest that lacks a healthy KMS driver. Wayland sessions need working
# GBM/EGL on top of DRM, which most VMs don't provide reliably; X11
# falls back to software rendering and always paints.
# Called from shellprocess@copy_genesi (dontChroot: true). Calamares
# passes the target rootMountPoint as $ROOT.
set -u
ROOT="${ROOT:-/mnt}"

mkdir -p "$ROOT/etc/sddm.conf.d"

need_x11=0
if lsmod 2>/dev/null | grep -Ewq '^(vmwgfx|vboxvideo)'; then
    need_x11=1
elif ! ls /sys/class/drm/card?/device/driver 2>/dev/null \
       | xargs -r -n1 readlink 2>/dev/null \
       | grep -Eq 'amdgpu|i915|nouveau|nvidia|radeon|virtio'; then
    need_x11=1
fi

if [ "$need_x11" = 1 ]; then
    printf '[General]\nDisplayServer=x11\n' \
        > "$ROOT/etc/sddm.conf.d/00-display-server.conf"
    echo "[x11-detect] forced SDDM DisplayServer=x11 (no healthy KMS driver detected)"
else
    echo "[x11-detect] keeping SDDM Wayland default (KMS driver detected)"
fi
exit 0
X11DETECTEOF
            chmod +x /etc/calamares/scripts/genesi-x11-detect.sh
            echo ">>> Rewrote genesi-x11-detect.sh (SDDM x11 fallback only, no GLX disable)"
        fi
    fi

    # Belt-and-suspenders: pre-seed [genesi] into the LIVE ISO's
    # /etc/pacman.conf at build time. genesi-prepare-pacman.sh copies this
    # file into the target before pacstrap, so the target inherits [genesi]
    # from boot. shellprocess-before-online.conf re-asserts it after pacstrap
    # using @@ROOT@@ in case the target's pacman.conf was clobbered.
    if ! grep -q '^\[genesi\]' /etc/pacman.conf 2>/dev/null; then
        printf '\n[genesi]\nSigLevel = Optional TrustAll\nServer = https://raw.githubusercontent.com/Genesi-OS/GenesiOS/main/genesi-arch/repo/x86_64\n' >> /etc/pacman.conf
        echo ">>> Pre-seeded [genesi] repo into live ISO /etc/pacman.conf"
    fi

    # Same for [genesi-apps] — the release-hosted repo for large app packages
    # (genesi-code) that can't live in the git tree (GitHub's 100 MB limit).
    if ! grep -q '^\[genesi-apps\]' /etc/pacman.conf 2>/dev/null; then
        printf '\n[genesi-apps]\nSigLevel = Optional TrustAll\nServer = https://github.com/Genesi-OS/GenesiOS/releases/download/apps-repo\n' >> /etc/pacman.conf
        echo ">>> Pre-seeded [genesi-apps] repo into live ISO /etc/pacman.conf"
    fi

    # genesi-calamares-branding ships /usr/share/calamares/branding/genesi/*,
    # the EXACT same files that the genesi-calamares package already installs.
    # Listing both in netinstall.yaml makes packages@online die with
    # "exists in both 'genesi-calamares' and 'genesi-calamares-branding'".
    # Drop the redundant entry from the netinstall list everywhere it
    # might be picked up.
    for nf in \
        /etc/calamares/modules/netinstall.yaml \
        /usr/share/calamares/modules/netinstall.yaml; do
        if [ -f "$nf" ]; then
            sed -i '/^[[:space:]]*-[[:space:]]*genesi-calamares-branding[[:space:]]*$/d' "$nf"
            echo ">>> Removed redundant genesi-calamares-branding from $nf"
        fi
    done
    
    # Copy module configs to BOTH locations (OVERWRITE)
    if [ -d /root/genesi-calamares-config-full/etc/calamares/modules ]; then
        mkdir -p /etc/calamares/modules
        mkdir -p /usr/share/calamares/modules
        cp -rf /root/genesi-calamares-config-full/etc/calamares/modules/* /etc/calamares/modules/
        cp -rf /root/genesi-calamares-config-full/etc/calamares/modules/* /usr/share/calamares/modules/
        echo ">>> Calamares modules copied to /etc and /usr/share (overwritten)"
    fi
    
    # Copy settings.conf to BOTH locations (OVERWRITE)
    if [ -f /root/genesi-calamares-config-full/etc/calamares/settings.conf ]; then
        cp -f /root/genesi-calamares-config-full/etc/calamares/settings.conf /etc/calamares/
        cp -f /root/genesi-calamares-config-full/etc/calamares/settings.conf /etc/calamares/settings_online.conf
        mkdir -p /usr/share/calamares
        cp -f /root/genesi-calamares-config-full/etc/calamares/settings.conf /usr/share/calamares/
        cp -f /root/genesi-calamares-config-full/etc/calamares/settings.conf /usr/share/calamares/settings_online.conf
        echo ">>> Calamares settings.conf copied to /etc and /usr/share (overwritten)"
    fi

    # Defense in depth: strip every shellprocess@btrfs_snapshot reference from
    # *any* settings*.conf the system might still load. Genesi's settings.conf
    # never schedules that step, but if the cp above is silently no-op'd (race,
    # missing dir, etc.) and cachyos-calamares-next's bundled settings.conf
    # wins the lookup, we'd still run shellprocess@btrfs_snapshot -> dontChroot
    # false -> call /etc/calamares/scripts/btrfs-installation-snapshot inside a
    # chroot that doesn't ship it -> exit 127 -> install aborts at job 45/46
    # (paste.cachyos.org/p/4bf3a85.log, 2026-05-17 12:12:36).
    find /etc/calamares /usr/share/calamares -maxdepth 2 -type f -name 'settings*.conf' \
        -exec sed -i '/shellprocess@btrfs_snapshot/d' {} + 2>/dev/null || true
    echo ">>> Stripped any lingering shellprocess@btrfs_snapshot from settings*.conf"

    # Also re-inline any shellprocess_btrfs_snapshot.conf that still points at
    # the external script. The override block above writes the inline version
    # to the two known module dirs, but if a future cachyos-calamares-next
    # update drops the same conf at a third path (e.g. /usr/lib/calamares/...),
    # find every copy and re-write it with the no-op-friendly inline command.
    find / -xdev -type f -name 'shellprocess_btrfs_snapshot.conf' 2>/dev/null \
        | while read -r f; do
        if grep -q '/etc/calamares/scripts/btrfs-installation-snapshot' "$f" 2>/dev/null; then
            cat > "$f" <<'BTRFSCONFDEFENSE'
---
# Genesi OS defense-in-depth re-inline (customize_airootfs.sh).
dontChroot: false
timeout: 60
script:
    - command: |
        set -u
        ROOT_FS="$(findmnt -no FSTYPE / 2>/dev/null || true)"
        if [ "${ROOT_FS:-}" = "btrfs" ] && command -v btrfs >/dev/null 2>&1; then
            btrfs subvolume snapshot -r / /.snapshots/@initial-install 2>/dev/null || true
        fi
        exit 0

i18n:
    name: "Creating Btrfs installation snapshot"
BTRFSCONFDEFENSE
            echo ">>> Re-inlined $f (was still referencing the external script)"
        fi
    done
    
    # Copy Python modules (overwrite)
    if [ -d /root/genesi-calamares-config-full/usr/lib/calamares ]; then
        cp -rf /root/genesi-calamares-config-full/usr/lib/calamares /usr/lib/
        echo ">>> Calamares Python modules copied (overwritten)"
    fi
    
    # Copy dummy scripts to /usr/local/bin (overwrite)
    if [ -d /root/genesi-calamares-config-full/usr/local/bin ]; then
        mkdir -p /usr/local/bin
        cp -rf /root/genesi-calamares-config-full/usr/local/bin/* /usr/local/bin/
        chmod +x /usr/local/bin/* 2>/dev/null || true
        echo ">>> Calamares dummy scripts copied to /usr/local/bin (overwritten)"
    fi
    
    echo ">>> Genesi Calamares configuration installed successfully (all files overwritten)"
else
    echo ">>> WARNING: genesi-calamares-config-full not found!"
fi

# Patch Calamares packages module to always pass --overwrite=* to pacman.
# Upstream module ignores any 'overwrite' YAML key, so files copied into the
# chroot by shellprocess (skel-override etc.) trip "exists in filesystem"
# when packages@online installs genesi-settings. Inject the flag directly into
# the install() command builder, then nuke .pyc so the patched source is used.
for PKG_MAIN in /usr/lib/calamares/modules/packages/main.py \
                /usr/share/calamares/modules/packages/main.py; do
    [ -f "$PKG_MAIN" ] || continue
    if grep -q -- '--overwrite=\*' "$PKG_MAIN"; then
        echo ">>> $PKG_MAIN already patched with --overwrite=*"
        continue
    fi
    python3 - "$PKG_MAIN" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
new = s.replace(
    'command.append("--noconfirm")',
    'command.append("--noconfirm")\n        command.append("--overwrite=*")',
    1)
if new == s:
    print(f">>> WARNING: pattern not found in {p}, packages module NOT patched")
    sys.exit(1)
open(p, 'w').write(new)
print(f">>> Patched {p} with --overwrite=*")
PYEOF
done
find /usr/lib/calamares /usr/share/calamares -name '*.pyc' -delete 2>/dev/null || true
find /usr/lib/calamares /usr/share/calamares -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
echo ""

# ============================================================
# 1. Install Genesi packages
# ============================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 CHECKING GENESI PACKAGES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "🔍 Checking if genesi-settings is installed..."
if pacman -Q genesi-settings &>/dev/null; then
    echo "✅ genesi-settings is INSTALLED"
    pacman -Qi genesi-settings
else
    echo "❌ genesi-settings is NOT INSTALLED"
    echo "🔍 Searching in repositories..."
    pacman -Ss genesi-settings || echo "Not found in repositories"
fi

echo ""
echo "🔍 Checking if genesi-calamares-branding is installed..."
if pacman -Q genesi-calamares-branding &>/dev/null; then
    echo "✅ genesi-calamares-branding is INSTALLED"
    pacman -Qi genesi-calamares-branding
else
    echo "❌ genesi-calamares-branding is NOT INSTALLED"
    echo "🔍 Searching in repositories..."
    pacman -Ss genesi-calamares-branding || echo "Not found in repositories"
fi

echo ""
echo "📋 All installed Genesi packages:"
pacman -Q | grep genesi || echo "⚠️  No Genesi packages found"

echo ""
echo "📂 Checking /opt/genesi-packages directory..."
if [ -d /opt/genesi-packages ]; then
    echo "✅ Directory exists"
    ls -lah /opt/genesi-packages/
    echo ""
    echo "📋 Database files:"
    ls -lah /opt/genesi-packages/*.db* /opt/genesi-packages/*.files* 2>/dev/null || echo "No database files found"
else
    echo "❌ Directory does NOT exist"
fi

echo ""
echo "📋 Pacman repositories configured:"
grep -A 2 "^\[.*\]" /etc/pacman.conf | grep -E "^\[|^Server"

echo ""
if [ -f /root/customize_airootfs_genesi.sh ]; then
    echo ">>> Running customize_airootfs_genesi.sh..."
    bash /root/customize_airootfs_genesi.sh
else
    echo "⚠️  customize_airootfs_genesi.sh not found"
fi

# ============================================================
# 1. Generate Plymouth progress bar images (if convert is available)
# ============================================================
if command -v convert &>/dev/null; then
    echo ">>> Generating Plymouth progress bar images..."
    convert -size 300x6 xc:'#0A1E1A' -fill '#0F6E56' -draw 'roundrectangle 0,0 299,5 3,3' \
        /usr/share/plymouth/themes/genesi/progress-bg.png 2>/dev/null || true
    convert -size 296x4 xc:'#1D9E75' -fill '#1D9E75' -draw 'roundrectangle 0,0 295,3 2,2' \
        /usr/share/plymouth/themes/genesi/progress-bar.png 2>/dev/null || true
fi

# Set Plymouth theme if plymouth is installed
if command -v plymouth-set-default-theme &>/dev/null; then
    echo ">>> Setting Plymouth theme to genesi..."
    plymouth-set-default-theme genesi 2>/dev/null || true
fi

# ============================================================
# 1. System identity files
# ============================================================

echo "genesi" > /etc/hostname

cat > /etc/hosts << 'HOSTS'
127.0.0.1   localhost
::1         localhost
127.0.1.1   genesi.localdomain genesi
185.199.108.133 raw.githubusercontent.com
HOSTS

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
# 2. Apply Genesi OS desktop config overrides
# ============================================================

if [ -d /usr/share/genesi/skel-override ]; then
    echo ">>> Copying skel-override to /etc/skel and /home/liveuser..."
    
    # Copy to /etc/skel first
    cp -rf /usr/share/genesi/skel-override/. /etc/skel/
    echo ">>> Copied to /etc/skel"
    
    # Create liveuser home if it doesn't exist
    if [ ! -d /home/liveuser ]; then
        mkdir -p /home/liveuser
        echo ">>> Created /home/liveuser"
    fi
    
    # Copy to liveuser home
    cp -rf /usr/share/genesi/skel-override/. /home/liveuser/
    
    # Make desktop files executable
    chmod +x /home/liveuser/Desktop/*.desktop 2>/dev/null || true
    chmod +x /etc/skel/Desktop/*.desktop 2>/dev/null || true
    
    # Trust desktop files (Plasma 5/6 requirement for live ISO)
    for f in /home/liveuser/Desktop/*.desktop; do
        [ -f "$f" ] && gio set "$f" metadata::trusted true 2>/dev/null || true
    done
    for f in /etc/skel/Desktop/*.desktop; do
        [ -f "$f" ] && gio set "$f" metadata::trusted true 2>/dev/null || true
    done
    
    # Make theme applicator executable
    chmod +x /usr/bin/genesi-apply-theme.sh 2>/dev/null || true
    chmod +x /home/liveuser/.config/autostart/genesi-apply-theme.desktop 2>/dev/null || true
    
    # Set correct ownership
    chown -R 1000:1000 /home/liveuser/ 2>/dev/null || true
    
    echo ">>> Copied to /home/liveuser and set permissions"
    
    # Debug: List what was copied
    echo ">>> Files in /home/liveuser/.config:"
    ls -la /home/liveuser/.config/ 2>/dev/null || echo "No .config directory"
    
    echo ">>> KDE config files:"
    ls -la /home/liveuser/.config/kwin* /home/liveuser/.config/kdeglobals /home/liveuser/.config/plasma* 2>/dev/null || echo "No KDE config files found"
    
    echo ">>> Wallpaper location:"
    ls -la /usr/share/wallpapers/genesi/wallpaper.png 2>/dev/null || echo "Wallpaper not found!"
    
else
    echo ">>> WARNING: /usr/share/genesi/skel-override NOT FOUND!"
    echo ">>> Checking if genesi-settings package is installed..."
    pacman -Q genesi-settings || echo "genesi-settings NOT INSTALLED!"
fi

# ============================================================
# 3. Rebrand CachyOS Hello (if still installed as dependency)
# ============================================================

# Patch the desktop file
if [ -f /usr/share/applications/cachyos-hello.desktop ]; then
    sed -i 's/CachyOS Hello/Genesi OS Welcome/g' /usr/share/applications/cachyos-hello.desktop
    sed -i 's/Name=CachyOS/Name=Genesi OS/g' /usr/share/applications/cachyos-hello.desktop
    sed -i 's/Comment=.*CachyOS.*/Comment=Welcome to Genesi OS/g' /usr/share/applications/cachyos-hello.desktop
fi

# Patch the cachyos-hello config if it exists
if [ -f /etc/cachyos-hello.conf ]; then
    sed -i 's/CachyOS/Genesi OS/g' /etc/cachyos-hello.conf
    sed -i 's/cachyos\.org/github.com\/Genesi-OS\/GenesiOS/g' /etc/cachyos-hello.conf
    sed -i 's/discuss\.cachyos\.org/github.com\/Genesi-OS\/GenesiOS\/issues/g' /etc/cachyos-hello.conf
fi

# Remove cachyos-hello binary (it has hardcoded CachyOS text that can't be changed)
# We'll replace it with our own Genesi Welcome app later
if [ -f /usr/bin/cachyos-hello ]; then
    rm -f /usr/bin/cachyos-hello
fi
# Remove its autostart
rm -f /etc/xdg/autostart/cachyos-hello.desktop 2>/dev/null || true

# ============================================================
# 4. Rebrand Calamares (installed by cachyos-calamares-next)
# ============================================================

# Single source of truth: the genesi-calamares-config submodule is authoritative
# for ALL Calamares branding (logo, icon, welcome, slides, show.qml, stylesheet,
# branding.desc). It is also exactly what the genesi-calamares-branding package
# ships, so the live ISO and an installed system can never drift apart.
#
# We copy it cleanly into BOTH dirs Calamares may read (/etc takes precedence
# over /usr/share), wiping each first so no stale CachyOS art (e.g. extra
# slideN.png the slideshow would still cycle) can leak through.
GENESI_BRANDING_SRC=/root/genesi-calamares-config-full/etc/calamares/branding/genesi
if [ -d "$GENESI_BRANDING_SRC" ]; then
    for dest in /etc/calamares/branding/genesi /usr/share/calamares/branding/genesi; do
        rm -rf "$dest"
        mkdir -p "$dest"
        cp -rf "$GENESI_BRANDING_SRC/"* "$dest/"
    done
    echo ">>> Genesi branding installed authoritatively (no CachyOS fallback)"
else
    echo ">>> WARNING: Genesi branding source not found at $GENESI_BRANDING_SRC"
fi

# Drop the upstream CachyOS branding component entirely so nothing can ever fall
# back to it (settings.conf already selects 'genesi').
rm -rf /usr/share/calamares/branding/cachyos /etc/calamares/branding/cachyos 2>/dev/null || true

# Force copy our packages.conf (overwrite any existing one)
if [ -f /etc/calamares/modules/packages.conf.genesi ]; then
    echo ">>> Copying Genesi packages.conf to Calamares..."
    cp -f /etc/calamares/modules/packages.conf.genesi /etc/calamares/modules/packages.conf
    echo ">>> Genesi packages.conf installed"
fi

# Update Calamares settings to use genesi branding
find /usr/share/calamares /etc/calamares -type f -name "settings*.conf" -exec sed -i \
    -e 's/branding:.*cachyos/branding: genesi/' \
    -e 's/CachyOS/Genesi OS/g' \
    {} + 2>/dev/null || true

# Patch all other Calamares config files
if [ -d /etc/calamares ]; then
    find /etc/calamares -type f \( -name "*.conf" -o -name "*.qml" -o -name "*.yml" -o -name "*.yaml" -o -name "*.desc" \) -exec sed -i \
        -e 's/CachyOS/Genesi OS/g' \
        -e 's|https://cachyos.org|https://github.com/Genesi-OS/GenesiOS|g' \
        {} + 2>/dev/null || true
fi
if [ -d /usr/share/calamares ]; then
    find /usr/share/calamares -type f \( -name "*.conf" -o -name "*.qml" -o -name "*.yml" -o -name "*.yaml" -o -name "*.desc" \) -exec sed -i \
        -e 's/CachyOS/Genesi OS/g' \
        -e 's|https://cachyos.org|https://github.com/Genesi-OS/GenesiOS|g' \
        {} + 2>/dev/null || true
fi

# ============================================================
# 5. Enable services with REAL symlinks
# ============================================================

mkdir -p /etc/systemd/system/multi-user.target.wants

# NetworkManager (fix: was not starting because symlink was a text file)
ln -sf /usr/lib/systemd/system/NetworkManager.service /etc/systemd/system/multi-user.target.wants/NetworkManager.service
ln -sf /usr/lib/systemd/system/NetworkManager-dispatcher.service /etc/systemd/system/dbus-org.freedesktop.nm-dispatcher.service

# Genesi branding service
if [ -f /etc/systemd/system/genesi-branding.service ]; then
    ln -sf /etc/systemd/system/genesi-branding.service /etc/systemd/system/multi-user.target.wants/genesi-branding.service
fi

# Genesi AI Daemon
if [ -f /usr/lib/systemd/system/genesi-aid.service ]; then
    ln -sf /usr/lib/systemd/system/genesi-aid.service /etc/systemd/system/multi-user.target.wants/genesi-aid.service
    echo ">>> Enabled genesi-aid.service"
fi

# Bluetooth
mkdir -p /etc/systemd/system/bluetooth.target.wants
ln -sf /usr/lib/systemd/system/bluetooth.service /etc/systemd/system/bluetooth.target.wants/bluetooth.service

# SSH
ln -sf /usr/lib/systemd/system/sshd.service /etc/systemd/system/multi-user.target.wants/sshd.service

# VirtualBox guest
ln -sf /usr/lib/systemd/system/vboxservice.service /etc/systemd/system/multi-user.target.wants/vboxservice.service 2>/dev/null || true

# Enable SDDM explicitly + force graphical.target as default for the
# live ISO. Old comment here said SDDM was NOT enabled in the live
# ISO because "the live ISO uses autologin via systemd service" -
# that was when the package was plasma-login-manager (which self-
# enabled). With plain sddm (post 2026-05-23 swap in
# packages_desktop.x86_64), nothing enables it implicitly, so the
# live ISO booted into a text TTY1 with agetty autologin instead of
# Plasma. Reproduced 2026-05-23 - user saw "[liveuser@genesi ~]$"
# instead of the desktop.
#
# Two symlinks reproduce `systemctl enable sddm` + `systemctl
# set-default graphical.target` without needing systemctl (which
# doesn't work inside the chroot at build time).
mkdir -p /etc/systemd/system
ln -sf /usr/lib/systemd/system/sddm.service \
    /etc/systemd/system/display-manager.service
ln -sf /usr/lib/systemd/system/graphical.target \
    /etc/systemd/system/default.target
echo ">>> Enabled sddm.service via display-manager.service symlink"
echo ">>> Set graphical.target as default.target"

# Kill the getty@tty1 autologin override - it grabs TTY1 before SDDM
# can claim it, leaving the user stuck at a console prompt while SDDM
# silently exits because TTY1 is busy. SDDM picks TTY1 by default on
# Plasma 6; let it.
rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf 2>/dev/null
rmdir /etc/systemd/system/getty@tty1.service.d 2>/dev/null || true
echo ">>> Removed getty@tty1 autologin override (was preempting SDDM)"

# Strip /etc/plasmalogin.conf.d/ - dead config dir from when the live
# ISO shipped plasma-login-manager. With sddm in its place, that
# directory is unreachable noise.
rm -rf /etc/plasmalogin.conf.d 2>/dev/null
echo ">>> Removed stale /etc/plasmalogin.conf.d/"

# Run dmcheck to configure display manager for live ISO (now used as
# a defense-in-depth final pass; the symlinks above already did the
# real work).
if [ -f /usr/local/bin/dmcheck ]; then
    echo ">>> Running dmcheck to configure display manager..."
    bash /usr/local/bin/dmcheck
    echo ">>> Display manager configured"
fi

# ============================================================
# 6. Generate locales
# ============================================================

sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
sed -i 's/#pt_BR.UTF-8/pt_BR.UTF-8/' /etc/locale.gen
locale-gen

# ============================================================
# 7. Global text replacement for any remaining CachyOS references
# ============================================================

# Replace in all autostart desktop files
find /etc/xdg/autostart -name "*.desktop" -exec sed -i 's/CachyOS/Genesi OS/g' {} + 2>/dev/null || true

# Replace in SDDM/login manager configs
find /etc -name "*.conf" -path "*/sddm*" -exec sed -i 's/CachyOS/Genesi OS/g' {} + 2>/dev/null || true

# ============================================================
# 8a. (REMOVED 2026-05-29) vmwgfx kernel blacklist.
# ============================================================
# Previously we wrote /etc/modprobe.d/genesi-blacklist-vmwgfx.conf to
# force vmwgfx out, after one user reported a black screen in VBox
# VMSVGA on 2026-05-22. The blacklist worked but left VBox VMSVGA with
# NO DRM driver at all (vboxvideo doesn't bind to VMSVGA, simpledrm
# only loads on UEFI), which forced us into nomodeset + Xorg noglx
# workarounds that in turn killed KWin's OpenGL compositing - so
# Plasma rendered without rounded corners, blur, or transparency.
#
# CachyOS doesn't blacklist vmwgfx and the live ISO works there. On
# modern kernels vmwgfx's "unsupported hypervisor" message is a
# warning, not a fatal error - the driver still provides a usable
# framebuffer in most cases. If a specific user reports a regression,
# add a tailored fix (e.g. modprobe option, runtime detection) instead
# of carpet-bombing the whole graphics stack.

# ============================================================
# 8. Configure SDDM theme
# ============================================================

# Default SDDM theme: Breeze (NOT genesi) until the QML deps are pinned.
#
# 2026-05-22: a user installed Genesi inside VirtualBox and the system
# booted to a black screen with cursor. journalctl showed
#   sddm-helper exited with 127
#   Greeter session started successfully ... Greeter stopped
# Exit 127 = "command not found" - the `genesi` SDDM theme imports
# QML modules / calls a binary that exists on the live ISO chroot but
# is not pulled in by the Calamares pacstrap into the target. The
# greeter starts, tries to render, fails the import, exits, SDDM
# relaunches it, infinite loop. The user sees nothing because the
# greeter never reaches the paint phase.
#
# Breeze works because it only depends on qt6-declarative + plasma-
# workspace, both guaranteed in the target. Once we identify the
# missing piece for the genesi theme (probably plasma-framework /
# qt6-quickcontrols2 / a specific KF6 module), we can either ensure
# it's installed in netinstall.yaml or strip the import from the
# theme. Until then, ship Breeze so installs always reach login.
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/genesi-theme.conf << 'SDDMCONF'
[Theme]
Current=breeze
CursorTheme=breeze_cursors
Font=Noto Sans,10

[General]
Numlock=on
InputMethod=

[Users]
MaximumUid=60513
MinimumUid=1000
SDDMCONF

# Force X11 in the live ISO greeter. Wayland sessions on the SDDM
# greeter fail in any environment without GPU acceleration (vmwgfx
# disabled, no Intel/AMD/NVIDIA), reproducing the 2026-05-22 black
# screen even with module_blacklist=vmwgfx nomodeset added at boot.
# X11 with fbdev/vesa always paints. genesi-write-branding.sh
# already drops the same file into the installed target; this
# covers the live ISO before Calamares ever runs.
cat > /etc/sddm.conf.d/00-display-server.conf << 'X11CONF'
[General]
DisplayServer=x11
X11CONF
echo ">>> Forced SDDM DisplayServer=x11 in live ISO"

# Autologin liveuser straight into Plasma X11.
# Without autologin, the live ISO would still show the SDDM greeter,
# and if the greeter itself fails to render (e.g. its theme depends
# on a QML import that isn't installed yet), the user lands on a
# blinking-cursor black screen even though SDDM is "running" per
# systemctl. Skipping the greeter via [Autologin] is the only
# reliable way to reach the desktop on every supported guest.
cat > /etc/sddm.conf.d/01-autologin.conf << 'AUTOCONF'
[Autologin]
User=liveuser
Session=plasmax11
Relogin=true
AUTOCONF
echo ">>> Enabled SDDM autologin for liveuser -> plasmax11 in live ISO"

# ============================================================
# 9. Install Tela Circle Icon Theme (AUR package workaround)
# ============================================================
echo ">>> Installing Tela Circle Icon Theme from source..."
git clone https://github.com/vinceliuice/Tela-circle-icon-theme.git /tmp/Tela-circle-icon-theme
if [ -d /tmp/Tela-circle-icon-theme ]; then
    cd /tmp/Tela-circle-icon-theme
    # Install only green variants (green, green-light, green-dark) system-wide.
    # genesi-apply-theme.sh selects Tela-circle-green-dark at runtime.
    # Flags: -c = circular folder version, -d = system destination, "green" = color.
    # NOTE: -t was a typo — that flag does not exist in upstream install.sh and
    # caused installation to silently misbehave / land in /root/.local/share/icons.
    ./install.sh -c -d /usr/share/icons green
    cd /
    rm -rf /tmp/Tela-circle-icon-theme
    if [ -d /usr/share/icons/Tela-circle-green-dark ]; then
        echo ">>> Tela-circle-green-dark installed at /usr/share/icons/"
    else
        echo ">>> WARNING: Tela-circle-green-dark NOT found after install"
        ls /usr/share/icons | grep -i tela || echo "(no Tela-* dirs)"
    fi
else
    echo ">>> WARNING: Failed to clone Tela Circle Icon Theme repository."
fi

# ============================================================
# 10. Install Klassy window decoration (AUR workaround)
# ============================================================
# Klassy gives us native rounded corners (configurable 0-20px) on every
# window without an external compositor or custom Aurorae. Genesi's
# kwinrc sets library=org.kde.klassy by default; klassyrc in the skel
# pre-sets the Genesi profile (16px corners, no outline, blur friendly).
echo ">>> Building Klassy window decoration from source..."
# base-devel ships gcc / make / pkgconf — cmake configure aborts immediately
# with "CMAKE_C_COMPILER not set" if these aren't present. Live ISO ships
# without a compiler by default, so we must add it explicitly.
# Logging un-silenced so missing deps surface in build output.
pacman -S --noconfirm --needed \
    base-devel \
    cmake extra-cmake-modules qt6-base qt6-tools \
    kcmutils kdecoration kguiaddons ki18n kcoreaddons \
    kwidgetsaddons kwindowsystem frameworkintegration kconfigwidgets \
    2>&1 | tee -a /var/log/genesi-klassy-build.log \
    | grep -E '^(installing|error|warning|::)' || true

KLASSY_LOG=/var/log/genesi-klassy-build.log
git clone --depth 1 https://github.com/paulmcauley/klassy.git /tmp/klassy 2>&1 \
    | tee -a "$KLASSY_LOG"
if [ -d /tmp/klassy ]; then
    cd /tmp/klassy
    # Log full build output. Silencing this is why broken Klassy builds
    # used to ship in ISOs unnoticed (no rounded corners on installed
    # systems). Dump the tail of the log inline if any step fails so the
    # ISO build log surfaces the failure.
    if ! cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
              -DBUILD_QT5=OFF -DBUILD_QT6=ON >>"$KLASSY_LOG" 2>&1; then
        echo ">>> KLASSY cmake configure FAILED — tail of $KLASSY_LOG:"
        tail -30 "$KLASSY_LOG"
    elif ! cmake --build build -j"$(nproc)" >>"$KLASSY_LOG" 2>&1; then
        echo ">>> KLASSY cmake build FAILED — tail of $KLASSY_LOG:"
        tail -30 "$KLASSY_LOG"
    elif ! cmake --install build >>"$KLASSY_LOG" 2>&1; then
        echo ">>> KLASSY cmake install FAILED — tail of $KLASSY_LOG:"
        tail -30 "$KLASSY_LOG"
    fi
    cd /
    rm -rf /tmp/klassy
    if [ -f /usr/lib/qt6/plugins/org.kde.kdecoration2/klassydecoration.so ] \
       || [ -f /usr/lib/qt6/plugins/org.kde.kdecoration3/klassydecoration.so ]; then
        echo ">>> Klassy installed successfully"
        ls -la /usr/lib/qt6/plugins/org.kde.kdecoration2/klassy* 2>/dev/null
        ls -la /usr/lib/qt6/plugins/org.kde.kdecoration3/klassy* 2>/dev/null
    else
        echo ">>> WARNING: Klassy plugin not found after install"
        echo ">>> Files matching klassy* anywhere under /usr/lib:"
        find /usr/lib -name 'klassy*' 2>/dev/null | head -20
        echo ">>> Last 50 lines of $KLASSY_LOG:"
        tail -50 "$KLASSY_LOG"
    fi
else
    echo ">>> WARNING: Failed to clone Klassy repository (skipping)."
fi

# ============================================================
# 11. Build Darkly Plasma theme + Qt6 style from source
# ============================================================
# Darkly provides glass effects for Plasma popups/menu (Kickoff, system
# tray, notifications) and the Qt6 widget style for application chrome.
# It's not on official Arch repos; we build from upstream like Klassy.
# Bali10050/Darkly's install.sh handles cmake+install internally.
echo ">>> Building Darkly Plasma theme + Qt6 style from source..."
DARKLY_LOG=/var/log/genesi-darkly-build.log
# Darkly's install.sh runs cmake silently and exits 0 even when individual
# subcomponents (kstyle, plasma popup theme, decoration) fail to find Qt6/KF6
# deps. Pre-install the full set so every component builds. Missing this is
# why ISOs shipped with widgetStyle=Darkly in kdeglobals but no Darkly.so on
# disk — Qt fell back to Breeze and glassmorphism never showed.
pacman -S --noconfirm --needed \
    qt6-svg qt6-declarative qt6-5compat \
    kiconthemes kpackage kio kirigami knotifications kcolorscheme \
    breeze-icons \
    2>&1 | tee -a "$DARKLY_LOG" \
    | grep -E '^(installing|error|warning|::)' || true

git clone --depth 1 https://github.com/Bali10050/Darkly.git /tmp/Darkly 2>&1 \
    | tee -a "$DARKLY_LOG"
if [ -d /tmp/Darkly ]; then
    cd /tmp/Darkly
    # We do NOT call ./install.sh qt6 here, even though it's the upstream
    # entry point. Reason: install.sh runs `sudo cmake --install .` inside
    # the live ISO chroot, and sudo in that environment either fails
    # silently (no TTY, no PAM session) or hits PolicyKit checks that
    # exit 0 without actually installing. The 2026-05-22 ISO reproduced
    # this: install.sh "succeeded", but /usr/lib/qt6/plugins/styles
    # ended up with only breeze6.so and oxygen6.so - no darkly6.so.
    #
    # Calling cmake directly bypasses the sudo wrapper entirely. We're
    # already root in the chroot, so `cmake --install` lands files in
    # /usr without needing privilege escalation.
    #
    # Same 3-stage tail-on-fail pattern as the Klassy section above.
    if ! cmake -B build -S . \
              -DBUILD_QT5=OFF -DBUILD_QT6=ON \
              -DBUILD_TESTING=OFF \
              -DKDE_INSTALL_USE_QT_SYS_PATHS=ON \
              -DCMAKE_BUILD_TYPE=Release \
              -DCMAKE_INSTALL_PREFIX=/usr >>"$DARKLY_LOG" 2>&1; then
        echo ">>> DARKLY cmake configure FAILED — tail of $DARKLY_LOG:"
        tail -40 "$DARKLY_LOG"
    elif ! cmake --build build -j"$(nproc)" >>"$DARKLY_LOG" 2>&1; then
        echo ">>> DARKLY cmake build FAILED — tail of $DARKLY_LOG:"
        tail -40 "$DARKLY_LOG"
    elif ! cmake --install build >>"$DARKLY_LOG" 2>&1; then
        echo ">>> DARKLY cmake install FAILED — tail of $DARKLY_LOG:"
        tail -40 "$DARKLY_LOG"
    fi
    cd /
    rm -rf /tmp/Darkly
    # Verify EVERY Darkly component that kdeglobals/plasmarc references.
    # widgetStyle=Darkly without the .so means Qt falls back to Breeze.
    # plasmarc Theme=darkly without the desktoptheme means Plasma popups
    # show no glass effect. We need both.
    DARKLY_OK=1
    if [ ! -d /usr/share/plasma/desktoptheme/darkly ]; then
        echo ">>> WARNING: Darkly Plasma desktoptheme NOT installed"
        DARKLY_OK=0
    fi
    if ! find /usr/lib/qt6/plugins/styles -iname 'darkly*' 2>/dev/null | grep -q .; then
        echo ">>> WARNING: Darkly Qt6 style plugin NOT installed (widgetStyle=Darkly will fall back to Breeze)"
        DARKLY_OK=0
    fi
    if [ "$DARKLY_OK" = "1" ]; then
        echo ">>> Darkly installed successfully (desktoptheme + Qt6 style)"
        ls -la /usr/share/plasma/desktoptheme/darkly 2>/dev/null | head -5
        find /usr/lib/qt6/plugins/styles -iname 'darkly*' 2>/dev/null
    else
        echo ">>> Files matching darkly* under /usr/share/plasma:"
        find /usr/share/plasma -iname 'darkly*' 2>/dev/null | head -10
        echo ">>> Files matching darkly* under /usr/lib/qt6:"
        find /usr/lib/qt6 -iname 'darkly*' 2>/dev/null | head -10
        echo ">>> Last 60 lines of $DARKLY_LOG:"
        tail -60 "$DARKLY_LOG"
    fi
else
    echo ">>> WARNING: Failed to clone Darkly repository (skipping)."
fi

# ============================================================
# 12. Install Ant-Dark Plasma desktoptheme from source
# ============================================================
# The genesi-settings plasmarc points at desktoptheme name=Ant-Dark for
# Plasma popups (Kickoff, systray, notifications). Live ISO testing on
# 2026-05-22 confirmed Ant-Dark renders glass popups correctly inside
# VMs, where Darkly's KWin-blur-dependent look falls flat. Ant-Dark is
# not on Arch repos; we install kde/Dark/plasma/* from EliverLara/Ant
# (the same upstream the user already had locally on the live ISO).
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ">>> Installing Ant-Dark Plasma desktoptheme from EliverLara/Ant..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ANT_LOG=/var/log/genesi-ant-build.log
git clone --depth 1 https://github.com/EliverLara/Ant.git /tmp/Ant 2>&1 \
    | tee -a "$ANT_LOG"
if [ -d /tmp/Ant/kde/Dark/plasma ]; then
    # desktoptheme is what plasmarc name=Ant-Dark binds to (Plasma popups).
    # look-and-feel is the optional Global Theme bundle; install both so the
    # user can pick Ant-Dark in System Settings -> Global Theme if they want
    # to swap the whole look at once.
    mkdir -p /usr/share/plasma/desktoptheme
    mkdir -p /usr/share/plasma/look-and-feel
    if [ -d /tmp/Ant/kde/Dark/plasma/desktoptheme/Ant-Dark ]; then
        cp -rf /tmp/Ant/kde/Dark/plasma/desktoptheme/Ant-Dark /usr/share/plasma/desktoptheme/
        echo ">>> Ant-Dark desktoptheme copied"
    fi
    if [ -d /tmp/Ant/kde/Dark/plasma/look-and-feel/Ant-Dark ]; then
        cp -rf /tmp/Ant/kde/Dark/plasma/look-and-feel/Ant-Dark /usr/share/plasma/look-and-feel/
        echo ">>> Ant-Dark look-and-feel copied"
    fi
    rm -rf /tmp/Ant
    # Glassmorphism for the bottom panel:
    # Ant-Dark's panel-background.svgz is opaque dark by default, so even
    # with appletsrc panelOpacity=2 (Translucent) and KWin's blur effect
    # enabled, the panel renders as a solid black bar instead of glass.
    # The theme already ships translucentbackground.svgz (used by Kickoff
    # popups, blur-friendly with hint-compositing markers), so swap it
    # in as panel-background and the panel inherits the popup glass look.
    if [ -f /usr/share/plasma/desktoptheme/Ant-Dark/widgets/translucentbackground.svgz ] \
       && [ -f /usr/share/plasma/desktoptheme/Ant-Dark/widgets/panel-background.svgz ]; then
        # Keep the original around in case someone wants to revert (e.g.
        # they prefer the opaque panel after install).
        cp -f /usr/share/plasma/desktoptheme/Ant-Dark/widgets/panel-background.svgz \
              /usr/share/plasma/desktoptheme/Ant-Dark/widgets/panel-background-opaque.svgz.bak
        cp -f /usr/share/plasma/desktoptheme/Ant-Dark/widgets/translucentbackground.svgz \
              /usr/share/plasma/desktoptheme/Ant-Dark/widgets/panel-background.svgz
        echo ">>> Replaced Ant-Dark panel-background with translucent variant (panel glass enabled)"
    else
        echo ">>> WARNING: Ant-Dark translucentbackground.svgz missing - panel will render opaque"
    fi
    # Verification: plasmarc name=Ant-Dark will silently fall back to Breeze
    # if the desktoptheme directory is missing. We MUST surface that here so
    # the next ISO doesn't ship with Ant-Dark configured but not installed.
    if [ -d /usr/share/plasma/desktoptheme/Ant-Dark ]; then
        echo ">>> Ant-Dark installed successfully at /usr/share/plasma/desktoptheme/Ant-Dark"
        ls /usr/share/plasma/desktoptheme/Ant-Dark | head -5
    else
        echo ">>> WARNING: Ant-Dark desktoptheme NOT installed (Plasma will fall back to Breeze)"
        echo ">>> Last 30 lines of $ANT_LOG:"
        tail -30 "$ANT_LOG"
    fi
else
    echo ">>> WARNING: kde/Dark/plasma not found in EliverLara/Ant clone (upstream layout changed?)"
    tail -30 "$ANT_LOG"
fi

echo ">>> Genesi OS: Branding applied successfully!"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ CUSTOMIZATION COMPLETE at $(date)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 FINAL PACKAGE CHECK:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
pacman -Q | grep -E "(genesi|calamares)" || echo "No Genesi/Calamares packages found"
echo ""
echo "📂 SKEL OVERRIDE CHECK:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -d /usr/share/genesi/skel-override ]; then
    echo "✅ /usr/share/genesi/skel-override EXISTS"
    find /usr/share/genesi/skel-override -type f | head -20
else
    echo "❌ /usr/share/genesi/skel-override DOES NOT EXIST"
fi
echo ""
echo "📂 LIVEUSER HOME CHECK:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -d /home/liveuser ]; then
    echo "✅ /home/liveuser EXISTS"
    ls -la /home/liveuser/.config/*.* 2>/dev/null | head -20 || echo "No config files"
else
    echo "❌ /home/liveuser DOES NOT EXIST"
fi
echo ""
echo "📝 Full log saved to: /var/log/genesi-customize.log"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
