#!/usr/bin/env bash
# genesi-snapshots-setup — one-shot, idempotent first-boot bootstrap for the
# "indestructible OS" snapshot system. Runs as root from
# genesi-snapshots-setup.service after install/upgrade.
#
# What it guarantees on a Btrfs root:
#   1. a snapper "root" config exists (creates the /.snapshots subvolume);
#   2. that config is tuned ENXUTO — no periodic timeline snapshots, only the
#      snap-pac update snapshots + manual ones, with aggressive number cleanup
#      so the disk footprint stays tiny;
#   3. snapper's cleanup timer is on (prunes old snapshots);
#   4. grub-btrfs' watcher is on (keeps the GRUB "go back" submenu in sync);
#   5. a first "Genesi baseline" snapshot exists.
#
# Every step is guarded and non-fatal: on a non-Btrfs install (or any error) it
# exits 0 so it never blocks boot. Safe to re-run any number of times.
set -u

log() { echo "genesi-snapshots-setup: $*"; }

# ---- 0. only meaningful on a Btrfs root -------------------------------------
if [ "$(findmnt -no FSTYPE / 2>/dev/null || true)" != btrfs ]; then
    log "root is not Btrfs — snapshots disabled, nothing to do"
    exit 0
fi
command -v snapper >/dev/null 2>&1 || { log "snapper missing — skip"; exit 0; }

CONFIG=root
DONE_MARKER=/var/lib/genesi/snapshots-setup.done
# Bump to force the config-tuning steps to re-run on existing systems (the fast
# path below otherwise short-circuits). v3: NUMBER_LIMIT 2 -> 5. v4: GRUB snapshot
# titles lead with date + type (readable auto-snapshot names).
SETUP_VERSION=4

# Post-restore GRUB regen (runs BEFORE the fast-path short-circuit). A restore
# activates a copy of a snapshot as the new @, and because /boot lives inside @
# that @ carries the grub.cfg frozen when the snapshot was taken — it lists
# snapshots that were since deleted and omits newer ones. restore_into drops this
# flag into the new @ so the very first boot after a restore rebuilds the menu.
REGEN_FLAG=/var/lib/genesi/regen-grub
if [ -e "$REGEN_FLAG" ]; then
    if command -v grub-mkconfig >/dev/null 2>&1 && [ -d /boot/grub ]; then
        log "post-restore: regenerating the GRUB snapshot menu"
        grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 || true
    fi
    rm -f "$REGEN_FLAG" 2>/dev/null || true
fi

# Fast path: fully set up already (config present AND, if GRUB is in use, the
# watcher is enabled). Re-runs cheaply otherwise so a later grub-btrfs install
# still gets wired. grub-mkconfig is the only heavy step; the marker gates it.
if [ "$(cat "$DONE_MARKER" 2>/dev/null || true)" = "$SETUP_VERSION" ] \
   && snapper list-configs 2>/dev/null | awk 'NR>2{print $1}' | grep -qx "$CONFIG"; then
    exit 0
fi

# Track whether every applicable step succeeded so we only write the marker
# (and stop re-running grub-mkconfig each boot) once truly complete.
fully_ok=1

# ---- 1. ensure a snapper root config ----------------------------------------
if ! snapper list-configs 2>/dev/null | awk 'NR>2{print $1}' | grep -qx "$CONFIG"; then
    log "creating snapper config '$CONFIG' (+ /.snapshots subvolume)"
    # If a bare /.snapshots dir exists (some layouts pre-create it) snapper
    # refuses; move it aside so create-config can make the managed subvolume.
    if [ -e /.snapshots ] && ! btrfs subvolume show /.snapshots >/dev/null 2>&1; then
        mv /.snapshots "/.snapshots.pre-genesi.$$" 2>/dev/null || rm -rf /.snapshots 2>/dev/null || true
    fi
    if ! snapper -c "$CONFIG" create-config /; then
        log "create-config failed — leaving system unprotected but not blocking boot"
        exit 0
    fi
fi

# ---- 2. tune the config ENXUTO (light) --------------------------------------
# TIMELINE_CREATE=no  -> no hourly/daily periodic snapshots (leanest profile).
# snap-pac still snapshots around every pacman transaction.
# NUMBER_LIMIT=5      -> keep a small recovery buffer (a few before/after update
#                        pairs). 2 was too aggressive: if the snapshot you need
#                        to boot was already pruned, recovery is impossible. CoW
#                        keeps 5 nearly free on disk. Still no periodic timeline.
# Manual snapshots have no cleanup algorithm and are never counted here.
log "applying ENXUTO (light) snapshot policy"
snapper -c "$CONFIG" set-config \
    TIMELINE_CREATE=no \
    TIMELINE_CLEANUP=yes \
    NUMBER_CLEANUP=yes \
    NUMBER_MIN_AGE=0 \
    NUMBER_LIMIT=5 \
    NUMBER_LIMIT_IMPORTANT=5 \
    EMPTY_PRE_POST_CLEANUP=yes 2>/dev/null || log "set-config partial (older snapper?)"

# Let the 'users' see/manage snapshots without sudo for read-only ops: allow the
# wheel group so the GUI's list/status work unprivileged (mutations still pkexec).
if getent group wheel >/dev/null 2>&1; then
    snapper -c "$CONFIG" set-config ALLOW_GROUPS=wheel SYNC_ACL=yes 2>/dev/null || true
fi

# ---- 3. cleanup timer -------------------------------------------------------
# Prunes snapshots per the NUMBER limits above so nothing grows unbounded.
systemctl enable --now snapper-cleanup.timer 2>/dev/null \
    || log "could not enable snapper-cleanup.timer"
# Deliberately DO NOT enable snapper-timeline.timer (ENXUTO = no periodic snaps).
systemctl disable --now snapper-timeline.timer 2>/dev/null || true

# ---- 4. grub-btrfs boot menu ("go back to yesterday") -----------------------
# grub-btrfsd watches /.snapshots and regenerates the GRUB submenu on change so
# a broken boot always has selectable snapshots. Only meaningful with GRUB.
if command -v grub-mkconfig >/dev/null 2>&1 && [ -d /boot/grub ]; then
    # Make recovery visible and understandable to non-technical users. The
    # grub-btrfs submenu is otherwise named after the distro and snapshot rows
    # lead with implementation details instead of their useful description.
    GRUB_BTRFS_CONFIG=/etc/default/grub-btrfs/config
    set_config_value() {
        local file="$1" key="$2" value="$3"
        [ -f "$file" ] || return 0
        if grep -q "^[#[:space:]]*${key}=" "$file" 2>/dev/null; then
            sed -i "s|^[#[:space:]]*${key}=.*|${key}=${value}|" "$file"
        else
            printf '%s=%s\n' "$key" "$value" >> "$file"
        fi
    }
    set_config_value "$GRUB_BTRFS_CONFIG" GRUB_BTRFS_SUBMENUNAME \
        '"Genesi Recovery - My system broke"'
    # Lead with date + type so the auto snapshots are scannable in the menu: a
    # layperson sees "2026-07-10 10:59  post  …" instead of the raw pacman command
    # line first. (grub-btrfs cannot translate pre/post, but date+type already
    # tells them which is newest and whether it is before/after an update.)
    set_config_value "$GRUB_BTRFS_CONFIG" GRUB_BTRFS_TITLE_FORMAT \
        '("date" "type" "description")'
    set_config_value "$GRUB_BTRFS_CONFIG" GRUB_BTRFS_LIMIT '"12"'

    # A recovery entry is useless if the boot menu is hidden. Keep a short
    # eight-second window: normal boots remain quick, but a layperson has time
    # to choose the plainly named recovery option.
    GRUB_DEFAULTS=/etc/default/grub
    set_config_value "$GRUB_DEFAULTS" GRUB_TIMEOUT_STYLE 'menu'
    set_config_value "$GRUB_DEFAULTS" GRUB_TIMEOUT '8'

    if systemctl enable --now grub-btrfsd.service 2>/dev/null; then
        # Seed the submenu once so the entries exist before the first new snapshot.
        grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 || true
    else
        log "grub-btrfsd not available yet (install grub-btrfs) — will retry next boot"
        fully_ok=0
    fi
else
    # Not a GRUB system (e.g. systemd-boot): nothing to wire, still "complete".
    log "GRUB not detected — skipping grub-btrfs boot entries"
fi

# ---- 5. baseline snapshot ---------------------------------------------------
if [ "$(snapper -c "$CONFIG" list 2>/dev/null | awk 'NR>2 && $1 ~ /^[0-9]+$/' | wc -l)" -eq 0 ]; then
    log "creating Genesi baseline snapshot"
    snapper -c "$CONFIG" create --description "Genesi baseline" \
        --userdata "genesi=baseline" 2>/dev/null || true
fi

# Only mark complete when every applicable step worked, so a missing piece
# (e.g. grub-btrfs installed later) gets picked up on a subsequent boot.
if [ "$fully_ok" -eq 1 ]; then
    install -d "$(dirname "$DONE_MARKER")" 2>/dev/null || true
    printf '%s\n' "$SETUP_VERSION" > "$DONE_MARKER" 2>/dev/null || true
    log "done — system is protected (ENXUTO profile)"
else
    log "partial setup — will finish wiring on the next boot"
fi
exit 0
