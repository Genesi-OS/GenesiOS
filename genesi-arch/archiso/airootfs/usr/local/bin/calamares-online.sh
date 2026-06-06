#!/bin/bash

main() {
    # Remove current keyring first, to complete initiate it
    sudo rm -rf /etc/pacman.d/gnupg
    # We are using this, because archlinux is signing the keyring often with a newly created keyring
    # This results into a failed installation for the user.
    # Installing archlinux-keyring fails due not being correctly signed
    # Mitigate this by installing the latest archlinux-keyring on the ISO, before starting the installation
    # The issue could also happen, when the installation does rank the mirrors and then a "faulty" mirror gets used
    sudo pacman -Sy --noconfirm archlinux-keyring cachyos-keyring
    # Also populate the keys, before starting the Installer, to avoid above issue
    sudo pacman-key --init
    sudo pacman-key --populate archlinux cachyos
    # Also use timedatectl to sync the time with the hardware clock
    # There has been a bunch of reports, that the keyring was created in the future
    # Syncing appears to fix it
    timedatectl set-ntp true

    local progname="$(basename "$0")"
    local log="/home/liveuser/cachy-install.log"
    local mode="online"  # TODO: keep this line for now

    local SYSTEM=""

    if [ -d /sys/firmware/efi ]; then
        SYSTEM="UEFI SYSTEM"
    else
        SYSTEM="BIOS/MBR SYSTEM"
    fi

    local ISO_VERSION="$(cat /etc/version-tag)"
    echo "USING ISO VERSION: ${ISO_VERSION}"

    sudo pacman -Sy --noconfirm cachyos-calamares-next

    # Copy Genesi OS Calamares configuration (overwrite CachyOS defaults)
    echo ">>> Applying Genesi OS Calamares configuration..."
    if [ -d /root/genesi-calamares-config-full ]; then
        sudo mkdir -p /etc/calamares/modules
        sudo mkdir -p /usr/share/calamares/modules
        
        # Copy module configs
        if [ -d /root/genesi-calamares-config-full/etc/calamares/modules ]; then
            sudo cp -rf /root/genesi-calamares-config-full/etc/calamares/modules/* /etc/calamares/modules/
            sudo cp -rf /root/genesi-calamares-config-full/etc/calamares/modules/* /usr/share/calamares/modules/
            echo ">>> Genesi Calamares modules copied"
        fi
        
        # Copy settings.conf
        if [ -f /root/genesi-calamares-config-full/etc/calamares/settings.conf ]; then
            sudo cp -f /root/genesi-calamares-config-full/etc/calamares/settings.conf /etc/calamares/
            sudo cp -f /root/genesi-calamares-config-full/etc/calamares/settings.conf /usr/share/calamares/
            echo ">>> Genesi Calamares settings copied"
        fi
        
        # Copy branding
        if [ -d /root/genesi-calamares-config-full/etc/calamares/branding ]; then
            sudo cp -rf /root/genesi-calamares-config-full/etc/calamares/branding /etc/calamares/
            sudo cp -rf /root/genesi-calamares-config-full/etc/calamares/branding /usr/share/calamares/
            echo ">>> Genesi Calamares branding copied"
        fi
        
        # Copy scripts
        if [ -d /root/genesi-calamares-config-full/etc/calamares/scripts ]; then
            sudo cp -rf /root/genesi-calamares-config-full/etc/calamares/scripts /etc/calamares/
            sudo chmod +x /etc/calamares/scripts/* 2>/dev/null || true
            echo ">>> Genesi Calamares scripts copied"
        fi
    else
        echo ">>> WARNING: genesi-calamares-config-full not found at /root/"
    fi

    # Rebrand Calamares from CachyOS to Genesi OS
    if [ -d /usr/share/calamares/branding/cachyos ]; then
        # Copy cachyos branding to genesi folder as text fallback, then patch
        sudo mkdir -p /usr/share/calamares/branding/genesi
        sudo cp -rf /usr/share/calamares/branding/cachyos/* /usr/share/calamares/branding/genesi/

        sudo sed -i \
            -e 's/productName:.*CachyOS/productName:       Genesi OS/' \
            -e 's/shortProductName:.*CachyOS/shortProductName:  Genesi OS/' \
            -e 's/versionedName:.*CachyOS/versionedName:     Genesi OS/' \
            -e 's/shortVersionedName:.*CachyOS/shortVersionedName: Genesi OS/' \
            -e 's/bootLoaderEntryName:.*CachyOS/bootLoaderEntryName: Genesi OS/' \
            -e 's/componentName:.*cachyos/componentName:     genesi/' \
            -e 's|https://cachyos.org|https://github.com/zFreshy/GenesiOS|g' \
            /usr/share/calamares/branding/genesi/branding.desc
    fi
    # Also copy to /etc path
    sudo mkdir -p /etc/calamares/branding/genesi
    if [ -f /usr/share/calamares/branding/genesi/branding.desc ]; then
        sudo cp -rf /usr/share/calamares/branding/genesi/* /etc/calamares/branding/genesi/
    fi

    # NOW re-overlay OUR branding so our slides/logo/icon/show.qml win
    if [ -d /root/genesi-calamares-config-full/etc/calamares/branding/genesi ]; then
        sudo cp -rf /root/genesi-calamares-config-full/etc/calamares/branding/genesi/* \
            /etc/calamares/branding/genesi/
        sudo cp -rf /root/genesi-calamares-config-full/etc/calamares/branding/genesi/* \
            /usr/share/calamares/branding/genesi/ 2>/dev/null || true
        echo ">>> Genesi branding re-overlaid AFTER CachyOS fallback (our images/QML win)"
    fi

    # Update settings to use genesi branding
    sudo find /usr/share/calamares /etc/calamares -type f -name "settings*.conf" -exec sed -i \
        -e 's/branding:.*cachyos/branding: genesi/' \
        -e 's/CachyOS/Genesi OS/g' \
        {} + 2>/dev/null || true
    # Patch all Calamares text files
    sudo find /usr/share/calamares /etc/calamares -type f \( -name "*.conf" -o -name "*.yml" -o -name "*.yaml" -o -name "*.desc" \) \
        -exec sed -i -e 's/CachyOS/Genesi OS/g' {} + 2>/dev/null || true

    # Get Hardware Informations
    inxi -F > "$log"

    cat <<EOF >> "$log"
########## $log by $progname
########## Started (UTC): $(date -u "+%x %X")
########## ISO version: $ISO_VERSION
########## System: $SYSTEM
EOF

    # Genesi: prefer the Genesi settings.conf when present. It schedules
    # shellprocess@copy_genesi (branding/wallpapers/theme into the target)
    # which the upstream settings_${mode}.conf does NOT. If Genesi's wasn't
    # deployed (defensive), fall back to upstream.
    if [ -f /usr/share/calamares/settings.conf ] \
       && grep -q 'shellprocess@copy_genesi' /usr/share/calamares/settings.conf; then
        sudo cp /usr/share/calamares/settings.conf /etc/calamares/settings.conf
        echo ">>> Using Genesi settings.conf (with copy_genesi)"
    else
        sudo cp "/usr/share/calamares/settings_${mode}.conf" /etc/calamares/settings.conf
        echo ">>> Fell back to upstream settings_${mode}.conf"
    fi
    # Genesi: neutralize shellprocess@btrfs_snapshot before Calamares starts.
    # See /usr/local/bin/genesi-btrfs-cleanup.sh for rationale.
    sudo /usr/local/bin/genesi-btrfs-cleanup.sh
    exec pkexec-wrapper calamares -D6 >> $log
}

main "$@"
