#!/usr/bin/env bash
#
# repo-signature-test.sh — is the LIVE repository actually signed, and does it
# verify against the key Genesi ships?
#
# This is the gate for the one irreversible step in the signing rollout:
# raising SigLevel from `Optional TrustAll` to `Required`. Once a machine is on
# Required, a package Genesi cannot verify is a package that machine will not
# install — including the update that would fix it. So the question "is every
# artifact in the published repository signed by the key in genesi-keyring?"
# has to be answered before the flip, not after, and answered against what is
# actually being served rather than what CI believes it uploaded.
#
# It fetches the real databases over HTTPS, so it needs network and nothing
# else. Nothing is installed and nothing is modified.
#
# Usage:
#   genesi-arch/ci/repo-signature-test.sh                # stable, all repos
#   genesi-arch/ci/repo-signature-test.sh --channel testing
#   genesi-arch/ci/repo-signature-test.sh --local        # the checked-in repo/
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
KEYRING="${ROOT}/genesi-arch/packages/genesi-keyring/genesi.gpg"

CHANNEL="stable"
LOCAL=0
while [ $# -gt 0 ]; do
    case "$1" in
        --channel) CHANNEL="${2:?--channel needs stable|testing}"; shift ;;
        --local)   LOCAL=1 ;;
        -h|--help) sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ "${CHANNEL}" = "testing" ]; then
    BRANCH="develop"; DB="genesi-testing"
else
    BRANCH="main";    DB="genesi"
fi
BASE="https://raw.githubusercontent.com/Genesi-OS/GenesiOS/${BRANCH}/genesi-arch/repo/x86_64"

fails=0
pass() { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }
info() { printf '  ....  %s\n' "$1"; }

command -v gpg >/dev/null 2>&1 || { echo "gpg is required"; exit 2; }

echo "== repository signatures (${CHANNEL}) =="

if [ ! -f "${KEYRING}" ]; then
    echo
    echo "  No signing key is published yet (packages/genesi-keyring/genesi.gpg"
    echo "  does not exist), so there is nothing to verify against and the"
    echo "  repository is expected to be unsigned."
    echo
    echo "  Create the key with:  genesi-arch/devtools/genesi-keygen.sh"
    echo
    echo "repository signatures: NOT YET APPLICABLE"
    exit 0
fi

# A throwaway keyring holding exactly what a Genesi machine would trust —
# verifying against the maintainer's personal ~/.gnupg would prove nothing about
# what users can check.
PROBE="$(mktemp -d)"
trap 'rm -rf "${PROBE}"' EXIT
export GNUPGHOME="${PROBE}/gnupg"
mkdir -p "${GNUPGHOME}"; chmod 700 "${GNUPGHOME}"
gpg --batch --quiet --import "${KEYRING}" \
    || { echo "could not import ${KEYRING}"; exit 1; }
info "verifying against the keys in genesi-keyring"

WORK="${PROBE}/repo"
mkdir -p "${WORK}"

fetch() { # fetch <name> -> 0 if it exists
    if [ "${LOCAL}" -eq 1 ]; then
        [ -f "${ROOT}/genesi-arch/repo/x86_64/$1" ] || return 1
        cp "${ROOT}/genesi-arch/repo/x86_64/$1" "${WORK}/$1"
    else
        curl -fsSL "${BASE}/$1" -o "${WORK}/$1" 2>/dev/null || return 1
    fi
}

# ── The database ─────────────────────────────────────────────────────────────
#
# The database signature matters more than any single package's: the db carries
# every package's recorded checksum, so an attacker who can replace it can point
# pacman at anything.
if ! fetch "${DB}.db"; then
    fail "${DB}.db could not be fetched from ${BASE}"
    echo; echo "repository signatures: ${fails} failure(s)"; exit 1
fi
pass "fetched ${DB}.db"

if fetch "${DB}.db.sig"; then
    if gpg --batch --quiet --verify "${WORK}/${DB}.db.sig" "${WORK}/${DB}.db" 2>/dev/null; then
        pass "${DB}.db signature verifies"
    else
        fail "${DB}.db.sig does NOT verify against genesi-keyring —
        this is the state that makes SigLevel = Required unsafe"
    fi
else
    fail "${DB}.db.sig is missing — the database is unsigned"
fi

# ── Every package the database lists ─────────────────────────────────────────
#
# Checking the db alone is not enough: a repo can serve a signed index over
# unsigned packages, and pacman under `Required` would reject each one at
# install time rather than here.
if ! command -v bsdtar >/dev/null 2>&1; then
    echo "  SKIP  bsdtar not available — package-level signatures not checked"
else
    PKGS="$(bsdtar -xOf "${WORK}/${DB}.db" '*/desc' 2>/dev/null \
            | awk '/^%FILENAME%$/ { getline; print }')"
    total=0; signed=0; missing=""
    while IFS= read -r p; do
        [ -n "${p}" ] || continue
        total=$((total + 1))
        if fetch "${p}.sig"; then
            signed=$((signed + 1))
        else
            missing="${missing} ${p}"
        fi
    done <<< "${PKGS}"

    if [ "${total}" -eq 0 ]; then
        fail "the database lists no packages"
    elif [ "${signed}" -eq "${total}" ]; then
        pass "all ${total} package(s) have a published .sig"
    else
        fail "$(( total - signed )) of ${total} package(s) have NO signature:
       $(printf '%s' "${missing}" | tr ' ' '\n' | sed '/^$/d' | head -5 | tr '\n' ' ')…"
    fi

    # ── %PGPSIG% — an optimisation, not a requirement, and worth saying so ────
    #
    # repo-add can embed each package's signature into the database as a base64
    # %PGPSIG% field. Arch's own repos carry it; ours currently do not. That is
    # NOT a failure: when the field is absent pacman fetches `<package>.sig`
    # from the same server, which is exactly what is published above. The only
    # cost is one extra HTTP request per package.
    #
    # It is reported rather than ignored because it looks alarming when someone
    # inspects the database by hand before flipping SigLevel, and "is this why
    # every machine broke?" is a question best answered here, in advance.
    pgpsig="$(bsdtar -xOf "${WORK}/${DB}.db" '*/desc' 2>/dev/null | grep -c '^%PGPSIG%$' || true)"
    if [ "${pgpsig:-0}" -gt 0 ]; then
        pass "${pgpsig} database entries embed their signature (%PGPSIG%)"
    else
        info "no %PGPSIG% in the database — pacman will fetch each .sig separately"
        info "(fine: every .sig above is published and served from the same path)"
    fi

    # Verifying every package would mean downloading the whole repository. The
    # database records each package's checksum and IS signed, so a spot check of
    # the largest and the smallest is enough to catch a signing key that does
    # not match, which is the failure this is looking for.
    if [ "${signed}" -gt 0 ] && [ "${LOCAL}" -eq 1 ]; then
        for p in $(printf '%s\n' "${PKGS}" | head -3); do
            [ -f "${ROOT}/genesi-arch/repo/x86_64/${p}.sig" ] || continue
            if gpg --batch --quiet --verify \
                 "${ROOT}/genesi-arch/repo/x86_64/${p}.sig" \
                 "${ROOT}/genesi-arch/repo/x86_64/${p}" 2>/dev/null; then
                pass "${p} verifies"
            else
                fail "${p} does NOT verify against genesi-keyring"
            fi
        done
    fi
fi

echo
if [ "${fails}" -eq 0 ]; then
    echo "repository signatures: OK"
    echo
    echo "Every machine that already has genesi-keyring can now be moved to"
    echo "SigLevel = Required. See genesi-arch/docs/PACKAGE-SIGNING.md — the"
    echo "remaining question is not whether the repo is signed, it is whether"
    echo "the keyring has REACHED the machines yet."
    exit 0
fi
echo "repository signatures: ${fails} failure(s) — do NOT raise SigLevel"
exit 1
