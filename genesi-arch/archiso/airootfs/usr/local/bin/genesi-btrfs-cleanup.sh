#!/bin/bash
# Genesi OS: neutraliza o shellprocess@btrfs_snapshot do cachyos-calamares-next
# antes do Calamares subir. O wrapper calamares-online.sh roda
# `pacman -Sy cachyos-calamares-next` e em seguida `cp /usr/share/calamares/
# settings_${mode}.conf /etc/calamares/settings.conf`, o que restaura o
# agendamento upstream do passo "Creating Btrfs installation snapshot" e o
# shellprocess_btrfs_snapshot.conf que aponta para
# /etc/calamares/scripts/btrfs-installation-snapshot dentro do CHROOT do
# target. O target nao tem o script -> exit 127 -> install aborta no job
# 45/46 (paste.cachyos.org/p/3d9e2d1.log, 2026-05-18).
#
# Chamado pelos wrappers calamares-online.sh / calamares-offline.sh logo
# antes do `exec pkexec-wrapper calamares`.

for s in /etc/calamares/settings.conf /etc/calamares/settings_online.conf /etc/calamares/settings_offline.conf; do
    [ -f "$s" ] && sed -i '/shellprocess@btrfs_snapshot/d' "$s" 2>/dev/null || true
done

for d in /etc/calamares/modules /usr/share/calamares/modules; do
    [ -d "$d" ] || continue
    cat > "$d/shellprocess_btrfs_snapshot.conf" <<'INLINE'
---
dontChroot: false
timeout: 60
script:
    - command: "exit 0"
i18n:
    name: "Creating Btrfs installation snapshot"
INLINE
done

exit 0
