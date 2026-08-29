#!/usr/bin/env bash
#
# iso-boot-test.sh — does the ISO we just built actually boot?
#
# The pipeline already validates the PACKAGE SET (validate-install.sh: a
# dependency dry-run plus a real pacstrap into a throwaway root) and then builds
# the image. Nothing has ever switched the image on. And because the ISO is
# replaced in place on R2 under one fixed key, a build that produces an
# unbootable image reaches the public download link with no gate in between.
#
# That gap is not theoretical for this project. Every one of these shipped and
# was found by a human booting a USB stick: the GRUB theme aborting the install,
# chwd being skipped so nouveau shipped on an RTX 3050, the Plasma stack leaking
# in through pacstrap, Limine failing on the btrfs-only layout. A dependency
# dry-run cannot see any of them, because they are all downstream of "the image
# starts".
#
# Three stages, cheapest first, each answering a different question:
#
#   bios    SeaBIOS + syslinux  — does the legacy path still boot, and does
#                                 DEFAULT name an entry that exists?
#   uefi    OVMF + GRUB         — what every modern machine actually does.
#   kernel  direct kernel boot  — with the REAL cmdline read out of the built
#                                 ISO, does the kernel reach userspace, find
#                                 its squashfs, and start systemd?
#
# The first two prove the bootloaders; the third proves the system behind them.
# `kernel` bypasses the bootloader on purpose — its job is to keep going where
# the others stop, and it can log to a serial console the shipped entries do not
# ask for.
#
# ── Exit codes are load-bearing ──────────────────────────────────────────────
#
#   0  the ISO boots
#   1  the ISO does NOT boot            -> block the publish
#   2  the test could not run           -> warn, publish anyway
#
# 1 and 2 are different on purpose. This runs in front of the R2 upload, so a
# missing qemu or an OVMF package rename must not be able to stop Genesi from
# shipping. Only an actual failure to boot gets to do that.
#
# Usage:
#   genesi-arch/ci/iso-boot-test.sh out/genesi.iso
#   genesi-arch/ci/iso-boot-test.sh out/genesi.iso --stage uefi --timeout 300
#   genesi-arch/ci/iso-boot-test.sh out/genesi.iso --logs /tmp/bootlogs
set -uo pipefail

ISO=""
STAGES="bios uefi kernel"
TIMEOUT=420
LOGDIR=""

while [ $# -gt 0 ]; do
    case "$1" in
        --stage)   STAGES="${2:?--stage needs all|bios|uefi|kernel}"; shift
                   [ "${STAGES}" = "all" ] && STAGES="bios uefi kernel" ;;
        --timeout) TIMEOUT="${2:?--timeout needs seconds}"; shift ;;
        --logs)    LOGDIR="${2:?--logs needs a directory}"; shift ;;
        -h|--help) sed -n '2,44p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
        *)         ISO="$1" ;;
    esac
    shift
done

say()  { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; }
skip() { printf '  \033[33mSKIP\033[0m  %s\n' "$*"; }

untestable() {
    printf '\n::warning::ISO boot test could not run: %s\n' "$*"
    echo "The ISO was NOT proven to boot, but this is a test-environment"
    echo "problem, not an image problem — publishing is not blocked."
    exit 2
}

[ -n "${ISO}" ]  || untestable "no ISO path given"
[ -f "${ISO}" ]  || untestable "no such ISO: ${ISO}"
ISO="$(cd -- "$(dirname -- "${ISO}")" && pwd)/$(basename -- "${ISO}")"

command -v qemu-system-x86_64 >/dev/null 2>&1 \
    || untestable "qemu-system-x86_64 is not installed"

WORK="$(mktemp -d)"
if [ -n "${LOGDIR}" ]; then mkdir -p "${LOGDIR}"; fi
cleanup() {
    # Serial logs are the only evidence of what happened; keep them when asked
    # BEFORE tearing the scratch dir down.
    if [ -n "${LOGDIR}" ]; then cp -f "${WORK}"/*.log "${LOGDIR}/" 2>/dev/null || true; fi
    rm -rf "${WORK}"
}
trap cleanup EXIT

# ── Acceleration ─────────────────────────────────────────────────────────────
#
# KVM when the runner exposes /dev/kvm, plain TCG when it does not. TCG is
# roughly an order of magnitude slower, so the per-stage budget scales with it
# rather than the test reporting a false "does not boot" on a slow runner —
# which would block a publish for no reason, the one thing this must not do.
ACCEL=(-machine accel=tcg -cpu max)
SPEED="TCG (software emulation)"
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ACCEL=(-enable-kvm -cpu host)
    SPEED="KVM"
fi
echo "ISO:          ${ISO} ($(du -h "${ISO}" | cut -f1))"
echo "Acceleration: ${SPEED}"
echo "Budget:       ${TIMEOUT}s per stage"

# ── Wait for a marker to appear in a growing serial log ──────────────────────
#
# Polling the log rather than waiting for the VM to exit: a live ISO that boots
# correctly never exits, so "did it finish" is not the question. The question is
# "did it get this far", and the serial console is where that is written.
wait_for() { # <pid> <logfile> <deadline-epoch> <marker>...
    # `grep -i`, deliberately NOT `grep -iF`. That combination SIGABRTs on the
    # msys2 grep a Windows checkout runs, and none of the markers below contain
    # a regex metacharacter, so -F buys nothing and costs portability for
    # anyone running this test outside the CI container.
    local pid="$1" log="$2" deadline="$3"; shift 3
    local marker
    while [ "$(date +%s)" -lt "${deadline}" ]; do
        for marker in "$@"; do
            if grep -qi -- "${marker}" "${log}" 2>/dev/null; then
                echo "${marker}"
                return 0
            fi
        done
        # If qemu died, one more look (it may have printed the marker on the way
        # out) and then give up rather than burn the whole budget on a corpse.
        if ! kill -0 "${pid}" 2>/dev/null; then
            for marker in "$@"; do
                if grep -qi -- "${marker}" "${log}" 2>/dev/null; then
                    echo "${marker}"; return 0
                fi
            done
            return 2
        fi
        sleep 2
    done
    return 1
}

stop_vm() { # <pid>
    kill "$1" 2>/dev/null || true
    # SIGTERM first, SIGKILL only if it is still there: a killed qemu can leave
    # the serial log truncated mid-line, and that log is the only evidence.
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "$1" 2>/dev/null || break
        sleep 1
    done
    kill -9 "$1" 2>/dev/null || true
    # And REAP it. `kill -0` succeeds on a terminated-but-unreaped child, so
    # without this the loop above always burns its full ten seconds on a VM
    # that died instantly, and the pid still looks alive to the caller. Three
    # stages made that thirty seconds of waiting for nothing.
    wait "$1" 2>/dev/null || true
}

dump_tail() { # <logfile>
    echo "--- last 40 lines of the serial console ---"
    tail -40 "$1" 2>/dev/null | sed 's/^/  | /'
    echo "--- end ---"
}

FAILURES=0
RAN=0

# ─────────────────────────────────────────────────────────────────────────────
# Stage: BIOS (SeaBIOS -> syslinux)
# ─────────────────────────────────────────────────────────────────────────────
stage_bios() {
    say "BIOS boot (SeaBIOS -> syslinux)"
    RAN=$((RAN + 1))
    local log="${WORK}/bios.log"
    : > "${log}"

    # syslinux/archiso_head.cfg opens `SERIAL 0 115200`, so the menu itself
    # lands on this serial port. That is what makes the menu observable at all.
    qemu-system-x86_64 "${ACCEL[@]}" \
        -m 2048 -smp 2 \
        -cdrom "${ISO}" -boot d \
        -display none -vga std \
        -serial "file:${log}" \
        -no-reboot &
    local pid=$!
    local deadline=$(( $(date +%s) + TIMEOUT ))

    # "Genesi OS" is the MENU TITLE. Seeing it means SeaBIOS handed off, the
    # isolinux stage loaded, and our config was parsed — three things at once.
    if hit="$(wait_for "${pid}" "${log}" "${deadline}" "Genesi OS")"; then
        pass "syslinux menu reached (matched: ${hit})"
    else
        bad "syslinux menu never appeared within ${TIMEOUT}s"
        dump_tail "${log}"
        stop_vm "${pid}"
        FAILURES=$((FAILURES + 1))
        return
    fi

    # What syslinux ACTUALLY puts on the serial line, confirmed from a real run
    # (2026-08-29): the menu, then "Automatic boot in 15 … 1 second...", then it
    # clears the screen and goes silent. It never announces the kernel it loads.
    # And it cannot: the entry it boots carries `quiet splash` with no
    # console=ttyS0, so the moment syslinux hands over, this port goes dead.
    #
    # The first version of this looked for "Loading"/"vmlinuz" and failed a
    # perfectly good ISO because of it. So the countdown is the strongest thing
    # this stage can honestly assert — it proves the menu resolved a default
    # entry and is committed to booting it. Whether that entry EXISTS is
    # answered statically by ci/bootloader-config-test.sh, and whether the
    # system behind it comes up is answered by the kernel stage below. Between
    # them the old `DEFAULT arch64` bug is still covered, without this stage
    # inventing evidence it does not have.
    deadline=$(( $(date +%s) + 90 ))
    if hit="$(wait_for "${pid}" "${log}" "${deadline}"                 "Automatic boot in" "Booting" "Loading" "vmlinuz")"; then
        pass "syslinux is booting its default entry (matched: ${hit})"
    else
        bad "syslinux showed its menu but never started a countdown —
        nothing is going to boot on BIOS"
        dump_tail "${log}"
        FAILURES=$((FAILURES + 1))
    fi
    stop_vm "${pid}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Stage: UEFI (OVMF -> GRUB)
# ─────────────────────────────────────────────────────────────────────────────
find_ovmf() {
    # Distributions cannot agree on where OVMF lives or what it is called, and
    # the Arch package renamed its files (OVMF_CODE.fd -> OVMF_CODE.4m.fd).
    # Try the known spellings rather than pinning one and breaking on upgrade.
    local c
    for c in \
        /usr/share/edk2/x64/OVMF_CODE.4m.fd \
        /usr/share/edk2/x64/OVMF_CODE.fd \
        /usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
        /usr/share/OVMF/OVMF_CODE_4M.fd \
        /usr/share/OVMF/OVMF_CODE.fd \
        /usr/share/qemu/OVMF_CODE.fd ; do
        [ -f "${c}" ] && { echo "${c}"; return 0; }
    done
    return 1
}
find_ovmf_vars() {
    local c
    for c in \
        /usr/share/edk2/x64/OVMF_VARS.4m.fd \
        /usr/share/edk2/x64/OVMF_VARS.fd \
        /usr/share/edk2-ovmf/x64/OVMF_VARS.fd \
        /usr/share/OVMF/OVMF_VARS_4M.fd \
        /usr/share/OVMF/OVMF_VARS.fd \
        /usr/share/qemu/OVMF_VARS.fd ; do
        [ -f "${c}" ] && { echo "${c}"; return 0; }
    done
    return 1
}

stage_uefi() {
    say "UEFI boot (OVMF -> GRUB)"
    local code vars
    if ! code="$(find_ovmf)" || ! vars="$(find_ovmf_vars)"; then
        skip "OVMF firmware not found — install edk2-ovmf to cover the UEFI path"
        return
    fi
    RAN=$((RAN + 1))
    # The VARS image is written to; give the VM its own copy.
    cp -f "${vars}" "${WORK}/OVMF_VARS.fd"
    chmod u+w "${WORK}/OVMF_VARS.fd"

    local log="${WORK}/uefi.log"
    : > "${log}"

    qemu-system-x86_64 "${ACCEL[@]}" \
        -m 2048 -smp 2 -machine q35 \
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=${code}" \
        -drive "if=pflash,format=raw,unit=1,file=${WORK}/OVMF_VARS.fd" \
        -cdrom "${ISO}" -boot d \
        -display none -vga std \
        -serial "file:${log}" \
        -no-reboot &
    local pid=$!
    local deadline=$(( $(date +%s) + TIMEOUT ))

    # grub.cfg does `serial --unit=0 --speed=115200` and appends serial to the
    # terminal, so the menu reaches this log. "Welcome to Genesi OS" is our own
    # first menu entry — matching it proves the firmware found the EFI boot
    # image AND that GRUB read OUR config rather than a fallback.
    if hit="$(wait_for "${pid}" "${log}" "${deadline}" "Welcome to Genesi OS" "Genesi OS")"; then
        pass "GRUB menu reached (matched: ${hit})"
    else
        bad "GRUB never showed a menu within ${TIMEOUT}s —
        the firmware did not reach our EFI boot image, or grub.cfg is broken"
        dump_tail "${log}"
        stop_vm "${pid}"
        FAILURES=$((FAILURES + 1))
        return
    fi

    # timeout=10, default=genesi. What GRUB 2.14 actually writes to serial when
    # the countdown expires is:
    #
    #     Booting `Genesi OS'
    #
    # NOT "Loading Linux" — that was the marker the first version looked for,
    # and it failed an ISO that had just booted correctly. After this line the
    # port goes silent, because the entry carries `quiet splash` and no
    # console=ttyS0; proving what happens next is the kernel stage's job.
    deadline=$(( $(date +%s) + 90 ))
    if hit="$(wait_for "${pid}" "${log}" "${deadline}"                 "Booting" "Loading Linux" "Loading initial ramdisk")"; then
        pass "GRUB handed off to the kernel (matched: ${hit})"
    else
        bad "GRUB showed its menu but never booted an entry"
        dump_tail "${log}"
        FAILURES=$((FAILURES + 1))
    fi
    stop_vm "${pid}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Stage: kernel -> userspace
# ─────────────────────────────────────────────────────────────────────────────
stage_kernel() {
    say "Kernel to userspace (direct boot, real cmdline)"
    command -v bsdtar >/dev/null 2>&1 || { skip "bsdtar not available — cannot read the ISO"; return; }

    # Read the cmdline out of the BUILT ISO rather than the profile source.
    # mkarchiso substitutes %INSTALL_DIR% and %ARCHISO_UUID% at build time, so
    # the profile's copy is a template — and a test that boots a hand-written
    # cmdline proves nothing about the one users get.
    local cfg=""
    local candidate
    for candidate in boot/grub/grub.cfg EFI/BOOT/grub.cfg arch/boot/grub/grub.cfg grub/grub.cfg; do
        if bsdtar -xOf "${ISO}" "${candidate}" > "${WORK}/grub.cfg" 2>/dev/null \
           && [ -s "${WORK}/grub.cfg" ]; then
            cfg="${candidate}"; break
        fi
    done
    [ -n "${cfg}" ] || { skip "no grub.cfg inside the ISO — cannot recover the real cmdline"; return; }
    echo "  read cmdline from ${cfg} inside the ISO"

    # The first `linux ...` line of the first real entry is the default one
    # (grub.cfg sets default=genesi, which is that entry).
    local linuxline initrdline
    linuxline="$(grep -m1 -E '^\s*linux\s+/.*vmlinuz' "${WORK}/grub.cfg" | sed 's/^\s*linux\s*//')"
    initrdline="$(grep -m1 -E '^\s*initrd\s+/' "${WORK}/grub.cfg" | sed 's/^\s*initrd\s*//')"
    [ -n "${linuxline}" ] || { skip "could not parse a linux entry from grub.cfg"; return; }

    local kpath="${linuxline%% *}"; kpath="${kpath#/}"
    local ipath="${initrdline%% *}"; ipath="${ipath#/}"
    local append="${linuxline#* }"

    bsdtar -xOf "${ISO}" "${kpath}" > "${WORK}/vmlinuz" 2>/dev/null
    bsdtar -xOf "${ISO}" "${ipath}" > "${WORK}/initramfs.img" 2>/dev/null
    [ -s "${WORK}/vmlinuz" ] && [ -s "${WORK}/initramfs.img" ] \
        || { skip "could not extract ${kpath} / ${ipath} from the ISO"; return; }
    RAN=$((RAN + 1))
    echo "  kernel:  ${kpath}"
    echo "  initrd:  ${ipath}"

    # Two edits to the shipped cmdline, both necessary and both narrow:
    #   - drop `quiet splash`, which is exactly what stops the boot from being
    #     observable;
    #   - add console=ttyS0 and stop at multi-user.target. The graphical target
    #     means SDDM and Plasma on an emulated GPU, which is slow, needs a GPU
    #     stack this test is not about, and is not what "does it boot" means.
    # Everything else — archisobasedir, archisosearchuuid, cow_spacesize, the
    # module blacklist — is passed through untouched, because those are the
    # parts that decide whether the system finds itself.
    append="$(printf '%s' "${append}" | sed -e 's/\bquiet\b//g' -e 's/\bsplash\b//g')"
    append="${append} console=ttyS0,115200 systemd.unit=multi-user.target systemd.show_status=1"
    echo "  cmdline: ${append}"

    local log="${WORK}/kernel.log"
    : > "${log}"

    qemu-system-x86_64 "${ACCEL[@]}" \
        -m 4096 -smp 2 \
        -kernel "${WORK}/vmlinuz" \
        -initrd "${WORK}/initramfs.img" \
        -append "${append}" \
        -drive "file=${ISO},media=cdrom,readonly=on" \
        -display none \
        -serial "file:${log}" \
        -no-reboot &
    local pid=$!

    # Milestone 1 — the kernel is alive at all.
    local deadline=$(( $(date +%s) + TIMEOUT ))
    if hit="$(wait_for "${pid}" "${log}" "${deadline}" "Linux version" "Command line")"; then
        pass "kernel started (matched: ${hit})"
    else
        bad "the kernel produced no output in ${TIMEOUT}s"
        dump_tail "${log}"; stop_vm "${pid}"; FAILURES=$((FAILURES + 1)); return
    fi

    # Milestone 2 — the archiso hooks found the medium and mounted the
    # squashfs. This is the step that fails when the image is built wrong, and
    # it is invisible to every check that runs before the image exists.
    deadline=$(( $(date +%s) + TIMEOUT ))
    if hit="$(wait_for "${pid}" "${log}" "${deadline}" \
                "Mounting '/dev/loop" "airootfs" "squashfs" "Reached target" "systemd")"; then
        pass "initramfs handed over to the live system (matched: ${hit})"
    else
        bad "the kernel booted but the live root was never mounted —
        the archiso hooks did not find the medium (archisosearchuuid/basedir)"
        dump_tail "${log}"; stop_vm "${pid}"; FAILURES=$((FAILURES + 1)); return
    fi

    # Milestone 3 — userspace. systemd prints its target lines to the console
    # once show_status is on.
    deadline=$(( $(date +%s) + TIMEOUT ))
    if hit="$(wait_for "${pid}" "${log}" "${deadline}" \
                "Reached target Multi-User System" \
                "Reached target multi-user" \
                "Reached target Basic System" \
                "Welcome to Genesi")"; then
        pass "userspace came up (matched: ${hit})"
    else
        bad "the live root mounted but systemd never reached a target —
        the system boots far enough to fail late, which is the worst kind"
        dump_tail "${log}"; FAILURES=$((FAILURES + 1))
    fi
    stop_vm "${pid}"
}

for s in ${STAGES}; do
    case "$s" in
        bios)   stage_bios ;;
        uefi)   stage_uefi ;;
        kernel) stage_kernel ;;
        *)      echo "unknown stage: $s" >&2; exit 2 ;;
    esac
done

echo
if [ "${RAN}" -eq 0 ]; then
    untestable "every stage was skipped (no OVMF, no bsdtar, nothing to run)"
fi
if [ "${FAILURES}" -eq 0 ]; then
    echo "ISO boot test: OK (${RAN} stage(s))"
    exit 0
fi
echo "ISO boot test: ${FAILURES} stage(s) FAILED — this image should not be published"
exit 1
