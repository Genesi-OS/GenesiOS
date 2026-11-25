#!/bin/sh
# Genesi Migrate root helper. Run through ONE pkexec prompt by the app:
#
#   helper.sh mkdir  <dir> <user>          create a root-owned-path stage dir for <user>
#   helper.sh arm    <stage> <entry-file>  save Wi-Fi into the stage, add the GRUB
#                                          entry, pick it for the NEXT boot only
#   helper.sh disarm                       remove the GRUB entry again
#
# POSIX sh on purpose: this runs on whatever the old distro is (dash on
# Debian/Ubuntu). Every step says what it did on stdout; the app shows it.
set -eu

ENTRY_SCRIPT=/etc/grub.d/42_genesi_migrate

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

grub_cfg() {
    for f in /boot/grub/grub.cfg /boot/grub2/grub.cfg; do
        [ -f "$f" ] && { printf '%s' "$f"; return; }
    done
    return 1
}

regen() {
    cfg="$(grub_cfg)" || die "no GRUB configuration found"
    if command -v update-grub >/dev/null 2>&1; then
        update-grub
    elif command -v grub2-mkconfig >/dev/null 2>&1; then
        grub2-mkconfig -o "$cfg"
    elif command -v grub-mkconfig >/dev/null 2>&1; then
        grub-mkconfig -o "$cfg"
    else
        die "no grub-mkconfig on this system"
    fi
    grep -q "genesi-migrate" "$cfg" || [ "${1:-}" = disarm ] || die "the GRUB entry did not make it into $cfg"
}

case "${1:-}" in
native-disarm)
    exec unshare --mount --propagation private /usr/bin/python3 "$2" disarm "$3"
    ;;
native)
    # All mounts belong to a private namespace. Neither the source root nor
    # any host package/service is replaced while building the target tree.
    exec unshare --mount --pid --fork --kill-child=KILL --mount-proc --propagation private /usr/bin/python3 "$2" prepare "$3" "$4" "$5" "$6"
    ;;
mkdir)
    dir="$2"; user="$3"
    case "$dir" in /var/lib/genesi-migrate) ;; *) die "refusing to create $dir" ;; esac
    mkdir -p "$dir"
    chown "$user" "$dir"
    chmod 700 "$dir"
    say "stage directory $dir ready"
    ;;
arm)
    stage="$2"; entry="$3"
    [ -f "$stage/manifest.json" ] || die "no manifest in $stage"
    # Wi-Fi: NetworkManager keyfiles, readable by root only. They go into the
    # stage (mode 600) so the live system is online before the installer
    # starts, and the installed Genesi knows the same networks.
    mkdir -p "$stage/wifi"
    chmod 700 "$stage/wifi"
    n=0
    for f in /etc/NetworkManager/system-connections/*; do
        [ -f "$f" ] || continue
        grep -q '^type=\(wifi\|802-11-wireless\)' "$f" || continue
        cp "$f" "$stage/wifi/"
        n=$((n + 1))
    done
    chmod 600 "$stage"/wifi/* 2>/dev/null || true
    say "saved $n Wi-Fi network(s)"

    # The entry, as a grub.d script that prints it. grub-mkconfig (every
    # distro's wrapper around it) runs everything in /etc/grub.d.
    {
        printf '#!/bin/sh\n# Added by Genesi Migrate. Safe to delete.\ncat <<'"'"'GENESI_EOF'"'"'\n'
        cat "$entry"
        printf 'GENESI_EOF\n'
    } > "$ENTRY_SCRIPT"
    chmod 755 "$ENTRY_SCRIPT"
    regen
    # One boot only: grub-reboot sets next_entry, which GRUB's own header
    # consumes and clears on the next start, whatever GRUB_DEFAULT says.
    if command -v grub-reboot >/dev/null 2>&1; then
        grub-reboot genesi-migrate
    elif command -v grub2-reboot >/dev/null 2>&1; then
        grub2-reboot genesi-migrate
    else
        die "no grub-reboot on this system"
    fi
    say "next boot: Genesi Migrate"
    ;;
disarm)
    rm -f "$ENTRY_SCRIPT"
    regen disarm
    say "GRUB entry removed"
    ;;
*)
    die "usage: helper.sh mkdir|arm|disarm ..."
    ;;
esac
