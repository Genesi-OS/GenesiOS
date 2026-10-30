#!/usr/bin/env bash
# genesi-grub-theme's scriptlet must turn off GRUB 2.16's EFI BootNext entries.
#
# GRUB 2.16 added 31_efi_bootnext: one "EFI BootNext" menu entry per firmware
# boot record. A user's menu filled with them after the grub update. The
# scriptlet is run for real against a scratch /etc/default/grub, so this checks
# the value it writes, not text in the file.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scriptlet="$REPO_ROOT/genesi-arch/packages/genesi-grub-theme/genesi-grub-theme.install"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
defaults="$work/grub"
fails=0

run() {
    sed "s|/etc/default/grub|$defaults|g" "$scriptlet" > "$work/install.sh"
    # shellcheck disable=SC1091
    ( . "$work/install.sh"; "$1" )
}

value() { sed -n "s/^$1=//p" "$defaults"; }

check() {
    if [ "$2" = "$3" ]; then
        echo "  PASS  $1"
    else
        echo "  FAIL  $1 (got '$2', want '$3')"
        fails=$((fails + 1))
    fi
}

# Fresh file.
: > "$defaults"
run post_install
check "fresh install disables BootNext" "$(value GRUB_DISABLE_BOOTNEXT)" true

# Arch's file with the option commented out, and one with it set to false.
printf 'GRUB_TIMEOUT=5\n#GRUB_DISABLE_BOOTNEXT=false\n' > "$defaults"
run post_upgrade
check "commented default is replaced" "$(value GRUB_DISABLE_BOOTNEXT)" true
check "exactly one line" "$(grep -c 'GRUB_DISABLE_BOOTNEXT' "$defaults")" 1

printf 'GRUB_DISABLE_BOOTNEXT=false\n' > "$defaults"
run post_upgrade
check "explicit false is replaced" "$(value GRUB_DISABLE_BOOTNEXT)" true

# Running twice must not duplicate anything.
run post_upgrade
check "idempotent" "$(grep -c 'GRUB_DISABLE_BOOTNEXT' "$defaults")" 1

[ "$fails" -eq 0 ] && echo "grub defaults: OK" || { echo "grub defaults: $fails failure(s)"; exit 1; }
