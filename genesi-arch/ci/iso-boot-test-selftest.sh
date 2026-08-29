#!/usr/bin/env bash
#
# iso-boot-test-selftest.sh — tests the test.
#
# iso-boot-test.sh decides whether an ISO gets published, and it only ever runs
# in a job that has just spent twenty minutes building a 3 GB image. That is the
# worst possible place to discover that its polling loop is wrong: a bug in
# wait_for either blocks a good release (returns "did not boot" because it gave
# up early) or waves a broken one through (returns success on a marker it should
# not have matched). Neither is visible from reading the code.
#
# So the two functions that carry all the decision logic are exercised here
# against a FAKE vm — a background process writing to a log on a schedule. No
# QEMU, no ISO, runs anywhere in about fifteen seconds, which is what lets it
# sit in the hygiene job and run on every push.
#
# Usage: genesi-arch/ci/iso-boot-test-selftest.sh
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="${ROOT}/genesi-arch/ci/iso-boot-test.sh"
[ -f "${SRC}" ] || { echo "missing ${SRC}"; exit 1; }

# Pull the REAL functions out of the real script rather than re-declaring them.
# A copy here would pass forever while the shipped code drifted away from it.
eval "$(sed -n '/^wait_for() {/,/^}/p' "${SRC}")"
eval "$(sed -n '/^stop_vm() {/,/^}/p' "${SRC}")"
type wait_for >/dev/null 2>&1 || { echo "could not extract wait_for from ${SRC}"; exit 1; }
type stop_vm  >/dev/null 2>&1 || { echo "could not extract stop_vm from ${SRC}";  exit 1; }

fails=0
ck() { # <name> <got> <want>
    if [ "$2" = "$3" ]; then printf '  PASS  %s\n' "$1"
    else printf '  FAIL  %s (got %s, want %s)\n' "$1" "$2" "$3"; fails=$((fails + 1)); fi
}

echo "== iso-boot-test polling logic =="

# ── A marker that only shows up later ────────────────────────────────────────
# The normal case: a boot takes time, and the log grows while we watch it.
log="$(mktemp)"; ( sleep 3; echo "Welcome to Genesi OS" >> "${log}"; sleep 60 ) & pid=$!
out="$(wait_for "${pid}" "${log}" $(( $(date +%s) + 20 )) "Welcome to Genesi OS")"; rc=$?
ck "finds a marker that appears later" "${rc}" "0"
ck "reports which marker matched"      "${out}" "Welcome to Genesi OS"
stop_vm "${pid}"

# ── Never appears ────────────────────────────────────────────────────────────
# Must be 1 (a real failure), never 0 and never 2.
log="$(mktemp)"; sleep 60 & pid=$!
wait_for "${pid}" "${log}" $(( $(date +%s) + 6 )) "never happens" >/dev/null; rc=$?
ck "times out with 1 when the marker never comes" "${rc}" "1"
stop_vm "${pid}"

# ── The VM dies ──────────────────────────────────────────────────────────────
# A crashed qemu must be noticed immediately. Waiting out a 600s budget on a
# process that is already gone would turn one dead VM into a ten-minute stall
# per stage, and the job's own timeout would kill the build with no diagnosis.
log="$(mktemp)"; sleep 2 & pid=$!
start=$(date +%s)
wait_for "${pid}" "${log}" $(( $(date +%s) + 120 )) "nope" >/dev/null; rc=$?
elapsed=$(( $(date +%s) - start ))
ck "returns 2 when qemu dies" "${rc}" "2"
if [ "${elapsed}" -lt 20 ]; then
    printf '  PASS  gives up %ss after the vm died, not at the deadline\n' "${elapsed}"
else
    printf '  FAIL  waited %ss after the vm died\n' "${elapsed}"; fails=$((fails + 1))
fi

# ── Printed just before dying ────────────────────────────────────────────────
# The race that matters: the marker lands, then qemu exits before the next poll.
# Reporting that as a failure would fail builds at random.
log="$(mktemp)"; ( echo "Loading Linux" >> "${log}"; sleep 1 ) & pid=$!
sleep 3
wait_for "${pid}" "${log}" $(( $(date +%s) + 20 )) "Loading Linux" >/dev/null; rc=$?
ck "catches a marker printed just before the vm exited" "${rc}" "0"

# ── Case ─────────────────────────────────────────────────────────────────────
# systemd's console text has changed capitalisation across versions; matching
# must not be sensitive to it.
log="$(mktemp)"; echo "reached target Multi-User System" >> "${log}"; sleep 30 & pid=$!
wait_for "${pid}" "${log}" $(( $(date +%s) + 10 )) \
    "Reached target Multi-User System" "Reached target Basic System" >/dev/null; rc=$?
ck "matches case-insensitively" "${rc}" "0"
stop_vm "${pid}"

# ── stop_vm ──────────────────────────────────────────────────────────────────
# Three VMs are started in one run; leaking one would leave it holding the ISO
# and the runner's RAM while the next stage tries to boot the same image.
sleep 120 & pid=$!
stop_vm "${pid}"
if kill -0 "${pid}" 2>/dev/null; then
    printf '  FAIL  stop_vm left the process alive\n'; fails=$((fails + 1))
else
    printf '  PASS  stop_vm kills the vm\n'
fi

# ── The exit-code contract ───────────────────────────────────────────────────
# 1 blocks a publish and 2 does not, so the difference has to survive edits.
bash "${SRC}" /definitely/not/an.iso >/dev/null 2>&1
ck "a missing ISO is 'untestable' (2), not 'does not boot' (1)" "$?" "2"

# ── The markers are the test ─────────────────────────────────────────────────
#
# These strings were not guessed; they were read off a real serial console on
# 2026-08-29, after the first version of this test failed a perfectly good ISO
# by looking for text neither bootloader ever prints. GRUB 2.14 says
# "Booting `Genesi OS'", not "Loading Linux"; syslinux says "Automatic boot in
# N seconds..." and then goes silent without naming the kernel at all.
#
# A marker that no longer matches does not make the test fail — it makes the
# test fail a GOOD image, which is worse, because the reflex is to distrust the
# ISO rather than the test.
for marker in "Automatic boot in" "Booting" "Welcome to Genesi OS" \
              "Mounting '/dev/loop" "Reached target"; do
    if grep -qF -- "${marker}" "${SRC}"; then
        printf '  PASS  still looks for %s\n' "\"${marker}\""
    else
        printf '  FAIL  lost the marker %s — a real boot would look like a failure\n' "\"${marker}\""
        fails=$((fails + 1))
    fi
done

for code in 0 1 2; do
    if grep -q "^#   ${code} " "${SRC}"; then
        printf '  PASS  exit code %s is documented\n' "${code}"
    else
        printf '  FAIL  exit code %s lost its documentation\n' "${code}"; fails=$((fails + 1))
    fi
done

echo
if [ "${fails}" -eq 0 ]; then echo "iso-boot-test logic: OK"; exit 0; fi
echo "iso-boot-test logic: ${fails} failure(s)"
exit 1
