#!/usr/bin/env bash
#
# bootloader-config-test.sh — the boot menus must point at entries that exist.
#
# This is the static half of the ISO boot test. iso-boot-test.sh catches these
# too, but only after a twenty-minute build, and only for the entry that happens
# to be the default. This runs in a second, on every push, over every entry.
#
# It exists because of a real one: `archiso_sys.cfg` said `DEFAULT arch64` while
# the BIOS labels were cos64/cos64ram/cos64fb/cos64devcuda — the arch64_* labels
# are PXE-only and that file does not include the PXE config. DEFAULT therefore
# named nothing at all. What actually booted on BIOS was vesamenu.c32 falling
# back to the first entry. It was the right one, so nobody ever noticed; it was
# one reordering away from silently booting a different kernel than intended.
#
# Usage: genesi-arch/ci/bootloader-config-test.sh
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
PROFILE="${ROOT}/genesi-arch/archiso"
SYSLINUX="${PROFILE}/syslinux"
GRUBCFG="${PROFILE}/grub/grub.cfg"

fails=0
pass() { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }

# ── syslinux (BIOS) ──────────────────────────────────────────────────────────
echo "== syslinux (BIOS) =="

# Follow INCLUDEs from archiso_sys.cfg, which is the file the ISO path actually
# reaches (syslinux.cfg -> whichsys.c32 -> archiso_sys.cfg). Resolving the
# includes is the entire point: the labels live in a different file than the
# DEFAULT that names them, which is exactly how the two drifted apart.
collect_sys_files() {
    local entry="$1" seen="$2" inc
    [ -f "${SYSLINUX}/${entry}" ] || return 0
    case " ${seen} " in *" ${entry} "*) return 0 ;; esac
    echo "${entry}"
    while IFS= read -r inc; do
        collect_sys_files "${inc}" "${seen} ${entry}"
    done < <(grep -E '^\s*INCLUDE\s+' "${SYSLINUX}/${entry}" | awk '{print $2}')
}

SYS_FILES="$(collect_sys_files archiso_sys.cfg "")"
if [ -z "${SYS_FILES}" ]; then
    fail "archiso_sys.cfg not found — the BIOS boot path cannot be checked"
else
    pass "BIOS config reachable through: $(echo "${SYS_FILES}" | tr '\n' ' ')"

    LABELS="$(for f in ${SYS_FILES}; do
                grep -E '^\s*LABEL\s+' "${SYSLINUX}/${f}" | awk '{print $2}'
              done)"
    DEFAULT="$(for f in ${SYS_FILES}; do
                 grep -E '^\s*DEFAULT\s+' "${SYSLINUX}/${f}" | awk '{print $2}'
               done | head -1)"

    if [ -z "${DEFAULT}" ]; then
        fail "no DEFAULT in the BIOS config — nothing boots when the menu times out"
    elif printf '%s\n' ${LABELS} | grep -qx -- "${DEFAULT}"; then
        pass "DEFAULT '${DEFAULT}' names a LABEL that exists"
    else
        fail "DEFAULT '${DEFAULT}' names no LABEL on the BIOS path.
        Known labels: $(printf '%s ' ${LABELS})
        The menu would fall back to whatever happens to be first."
    fi

    # Every entry that loads a KERNEL needs an initrd. Restricted to vmlinuz
    # on purpose: memtest86+ and hdt are standalone binaries syslinux boots
    # directly, and demanding an INITRD from them would be a false alarm the
    # next person silences by deleting the check.
    missing=""
    for f in ${SYS_FILES}; do
        while IFS= read -r line; do
            [ -n "${line}" ] && missing="${missing}${f}: ${line}"$'
'
        done < <(awk '
            /^[[:space:]]*LABEL[[:space:]]+/ {
                if (label != "" && kernel && !initrd) print label
                label = $2; kernel = 0; initrd = 0; next
            }
            /^[[:space:]]*LINUX[[:space:]]+.*vmlinuz/  { kernel = 1 }
            /^[[:space:]]*INITRD[[:space:]]+/          { initrd = 1 }
            END { if (label != "" && kernel && !initrd) print label }
        ' "${SYSLINUX}/${f}")
    done
    if [ -z "${missing}" ]; then
        pass "every kernel entry has a matching INITRD"
    else
        while IFS= read -r m; do
            [ -n "${m}" ] && fail "${m} loads a kernel with no INITRD"
        done <<< "${missing}"
    fi
fi

# ── GRUB (UEFI) ──────────────────────────────────────────────────────────────
echo
echo "== GRUB (UEFI) =="

if [ ! -f "${GRUBCFG}" ]; then
    fail "grub/grub.cfg not found — the UEFI boot path cannot be checked"
else
    GDEFAULT="$(grep -E '^\s*default=' "${GRUBCFG}" | head -1 | cut -d= -f2 | tr -d '"'"'"' ')"
    # `-e`, because grep reads a pattern starting with `--` as an option.
    IDS="$(grep -oE -e "--id +'[^']+'" "${GRUBCFG}" | sed "s/--id *//; s/'//g")"

    if [ -z "${GDEFAULT}" ]; then
        fail "no default= in grub.cfg — the menu would sit on entry 0"
    elif printf '%s\n' ${IDS} | grep -qx -- "${GDEFAULT}"; then
        pass "default='${GDEFAULT}' names a menuentry --id that exists"
    else
        fail "default='${GDEFAULT}' names no menuentry --id.
        Known ids: $(printf '%s ' ${IDS})"
    fi

    # The two decorative entries at the top ("Welcome to…", the dashed rule) are
    # menuentries with no kernel, so entry 0 is NOT bootable. That is fine while
    # default= resolves to a real id, and catastrophic if it ever stops.
    if grep -qE "^\s*menuentry\s+\"Welcome to Genesi OS" "${GRUBCFG}"; then
        if [ -n "${GDEFAULT}" ] && printf '%s\n' ${IDS} | grep -qx -- "${GDEFAULT}"; then
            pass "the decorative first entries are safe (default= points past them)"
        else
            fail "entry 0 is a decorative non-bootable entry AND default= is broken —
            a timeout would 'boot' a menuentry that only does insmod ext2"
        fi
    fi

    # Serial output is what makes any of this observable from CI at all.
    if grep -q 'terminal_output --append serial' "${GRUBCFG}"; then
        pass "GRUB mirrors its menu to the serial console (the boot test reads it)"
    else
        fail "GRUB no longer appends serial output — iso-boot-test.sh goes blind"
    fi
fi

if grep -qE '^\s*SERIAL\s+0' "${SYSLINUX}/archiso_head.cfg" 2>/dev/null; then
    pass "syslinux mirrors its menu to the serial console"
else
    fail "syslinux lost 'SERIAL 0 115200' — iso-boot-test.sh goes blind on BIOS"
fi

echo
if [ "${fails}" -eq 0 ]; then echo "bootloader configs: OK"; exit 0; fi
echo "bootloader configs: ${fails} failure(s)"
exit 1
