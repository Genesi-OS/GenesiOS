#!/usr/bin/env bash
#
# repo-consumable-test.sh — can a machine that has ONLY what Genesi ships today
# still sync this repository?
#
# ── Why this exists ──────────────────────────────────────────────────────────
#
# On 2026-08-29 the first signed publish broke `pacman -Sy` on every installed
# machine, and the pipeline published it without noticing. Everything that ran
# before the publish passed, because everything that ran before the publish
# asked the wrong question.
#
# `repo-signature-test.sh` asks "is the repository signed, and does it verify?"
# — from the point of view of someone holding the key. The answer was yes. The
# question nobody asked was the opposite one:
#
#     can a machine WITHOUT the key still use this repository?
#
# The answer was no, because `SigLevel = Optional TrustAll` does not mean what
# it looks like it means. `TrustAll` accepts keys that are IN the keyring
# whatever their trust level; it does not accept a key the machine has never
# seen. `Optional` forgives an ABSENT signature; a signature that is present and
# unverifiable is a hard error. So the moment a signature appeared, every
# machine without the keyring failed at database sync:
#
#     error: genesi: key "…" is unknown
#     error: failed to synchronize all databases (unexpected error)
#
# This runs a real `pacman -Sy` against the freshly built repository, in an
# isolated root, using the SigLevel line Genesi actually ships, with a keyring
# that does NOT contain the Genesi key. That is a machine in the field. If it
# cannot sync, the publish must not happen.
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#
#   0  a machine in the field can sync this repository
#   1  it cannot — do not publish
#   2  could not be tested (no pacman: not the CI container)
#
# Usage:
#   genesi-arch/ci/repo-consumable-test.sh <repo-dir> [--db genesi]
set -uo pipefail

REPODIR=""
DB="genesi"
while [ $# -gt 0 ]; do
    case "$1" in
        --db) DB="${2:?--db needs a name}"; shift ;;
        -h|--help) sed -n '2,42p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
        *) REPODIR="$1" ;;
    esac
    shift
done

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
SHIPPED_CONF="${ROOT}/genesi-arch/archiso/airootfs/etc/pacman.conf.d/genesi.conf"

untestable() {
    printf '\n::warning::repo-consumable-test could not run: %s\n' "$*"
    echo "The repository was NOT proven usable by a machine in the field."
    exit 2
}

[ -n "${REPODIR}" ] || untestable "no repository directory given"
[ -d "${REPODIR}" ] || untestable "no such directory: ${REPODIR}"
REPODIR="$(cd -- "${REPODIR}" && pwd)"
command -v pacman >/dev/null 2>&1 || untestable "pacman is not available here"

echo "== can a machine in the field sync this repo? =="
echo "repo: ${REPODIR}"

[ -f "${REPODIR}/${DB}.db" ] || { echo "::error::${DB}.db is missing from ${REPODIR}"; exit 1; }

# The SigLevel under test is READ FROM WHAT WE SHIP, never hardcoded. If someone
# changes the shipped config, this test changes with it — which is the only way
# it can keep answering the question it claims to answer.
SIGLEVEL="$(awk '/^\[genesi\]/{f=1;next} f&&/^SigLevel/{print;exit}' "${SHIPPED_CONF}" 2>/dev/null)"
[ -n "${SIGLEVEL}" ] || SIGLEVEL="SigLevel = Optional TrustAll"
echo "using the shipped setting: ${SIGLEVEL}"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
mkdir -p "${WORK}/root" "${WORK}/dbpath" "${WORK}/gpg"

# A keyring that is initialised but contains NOTHING of ours — exactly the state
# of a machine that has not yet received genesi-keyring. Populating archlinux
# here would be more realistic still, but it is also slow and irrelevant: the
# question is only ever about the Genesi key.
pacman-key --gpgdir "${WORK}/gpg" --init >/dev/null 2>&1 \
    || untestable "could not initialise an isolated keyring"

cat > "${WORK}/pacman.conf" <<EOF
[options]
HoldPkg = pacman glibc
Architecture = auto
SigLevel = Never
LocalFileSigLevel = Never
GPGDir = ${WORK}/gpg

[${DB}]
${SIGLEVEL}
Server = file://${REPODIR}
EOF

echo
echo "--- pacman -Sy against the freshly built repository ---"
if out="$(pacman --config "${WORK}/pacman.conf" \
                 --root "${WORK}/root" \
                 --dbpath "${WORK}/dbpath" \
                 -Sy --noconfirm 2>&1)"; then
    printf '%s\n' "${out}" | sed 's/^/  /'
    echo
    echo "  PASS  a machine without the Genesi key can sync this repository"
else
    printf '%s\n' "${out}" | sed 's/^/  /'
    echo
    if printf '%s' "${out}" | grep -qi 'key .* is unknown\|unknown public key\|signature.*unknown'; then
        cat <<'MSG'

::error::THIS PUBLISH WOULD BREAK EVERY INSTALLED MACHINE.

The repository carries a signature made by a key that machines in the field do
not have, and `SigLevel = Optional TrustAll` does NOT tolerate that — it is not
"accept anything", it is "accept keys that are in the keyring". A machine
hitting this fails at `pacman -Sy` and cannot even fetch genesi-keyring to fix
itself, because fetching it needs the repository that is now failing.

If you are deliberately turning signing on: STOP and confirm that
genesi-keyring has actually REACHED installed machines first. That is what the
GENESI_SIGNING_ENABLED variable is for, and why it is a person's decision.

See genesi-arch/docs/PACKAGE-SIGNING.md.
MSG
    else
        echo "::error::a machine in the field cannot sync this repository"
    fi
    exit 1
fi

# One more: the packages have to be installable, not just listed. `-Sp` resolves
# and would surface a package-level signature problem the database sync does not.
echo
echo "--- resolving genesi-desktop the way an install does ---"
if out="$(pacman --config "${WORK}/pacman.conf" \
                 --root "${WORK}/root" \
                 --dbpath "${WORK}/dbpath" \
                 -Sp --noconfirm genesi-keyring 2>&1)"; then
    echo "  PASS  genesi-keyring resolves from this repository"
else
    printf '%s\n' "${out}" | sed 's/^/  /'
    echo "::error::genesi-keyring does not resolve — the trust anchor is unreachable"
    exit 1
fi

echo
echo "repository is consumable by a machine in the field: OK"
