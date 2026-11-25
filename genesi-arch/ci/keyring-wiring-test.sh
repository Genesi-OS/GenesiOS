#!/usr/bin/env bash
#
# keyring-wiring-test.sh — the keyring package and the things that reference it
# must appear together, in both directions.
#
# There are exactly two consistent states, and no third:
#
#   A. No key yet.  packages/genesi-keyring/ has no genesi.gpg, CI skips
#      building it, and NOTHING may declare a dependency on it. A dependency
#      here would break `pacstrap`, `validate-install.sh` and the ISO build with
#      "target not found: genesi-keyring" — the update pipeline would keep
#      working while installs quietly stopped.
#
#   B. Key exists.  genesi.gpg + genesi-trusted are committed, CI builds and
#      signs, and genesi-desktop MUST depend on it — otherwise `pacman -Syu`
#      has no reason to pull it and the key never reaches a single existing
#      machine. That is not hypothetical: genesi-mesh shipped to the repo and
#      reached nobody for weeks for exactly this reason (genesi-desktop
#      pkgrel 10).
#
# Every other combination is a bug that only shows up on someone else's
# computer, which is why it is checked here.
#
# Usage: genesi-arch/ci/keyring-wiring-test.sh
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
KEYRING_DIR="${ROOT}/genesi-arch/packages/genesi-keyring"
DESKTOP="${ROOT}/genesi-arch/packages/genesi-desktop/PKGBUILD"
ISOLIST="${ROOT}/genesi-arch/archiso/packages_desktop.x86_64"
WORKFLOW="${ROOT}/.github/workflows/publish-packages.yml"

fails=0
pass() { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }

echo "== genesi-keyring wiring =="

# ── The package itself is always present, key or not ─────────────────────────
for f in PKGBUILD genesi-keyring.install genesi-revoked; do
    if [ -f "${KEYRING_DIR}/${f}" ]; then
        pass "packages/genesi-keyring/${f} exists"
    else
        fail "packages/genesi-keyring/${f} is missing"
    fi
done

# genesi-revoked is fed line-by-line to gpg as key ids by `pacman-key
# --populate`. A "# nothing revoked yet" comment in there would be parsed as a
# key and break the populate on every machine.
if [ -f "${KEYRING_DIR}/genesi-revoked" ]; then
    if [ -s "${KEYRING_DIR}/genesi-revoked" ] \
       && grep -q '^[[:space:]]*#' "${KEYRING_DIR}/genesi-revoked"; then
        fail "genesi-revoked contains comments — pacman-key reads every line as a key id"
    else
        pass "genesi-revoked has no comment lines"
    fi
fi

# ── Newline handling is not cosmetic here ────────────────────────────────────
#
# genesi.gpg is binary: any CRLF translation corrupts it, and a corrupted
# keyring does not fail loudly -- it simply verifies nothing, and every check
# reports an unknown key. genesi-trusted/-revoked are the opposite: pacman-key
# reads them line by line and hands each line to gpg as a key id, so a CRLF
# checkout gives gpg "<fingerprint>", which it rejects. The key then installs
# and is never trusted, which surfaces only on the first machine moved to
# SigLevel = Required. Git's auto-detection would probably get both right;
# "probably" is the wrong guarantee for the file that decides what a machine
# installs as root.
ATTRS="${ROOT}/.gitattributes"
check_attr() { # <path> <expected substring>
    if grep -q "genesi-keyring/$1" "${ATTRS}" 2>/dev/null        && grep "genesi-keyring/$1" "${ATTRS}" | grep -q "$2"; then
        pass ".gitattributes pins $1 ($2)"
    else
        fail ".gitattributes does not pin genesi-keyring/$1 as '$2' --
        a CRLF checkout would silently corrupt it"
    fi
}
check_attr "genesi.gpg"      "binary"
check_attr "genesi-trusted"  "eol=lf"
check_attr "genesi-revoked"  "eol=lf"

# ── The workflow must always be able to cope with 'no key yet' ───────────────
if grep -q 'genesi-keyring has no public key yet' "${WORKFLOW}"; then
    pass "publish-packages.yml skips genesi-keyring when unkeyed"
else
    fail "publish-packages.yml lost the 'skip genesi-keyring when unkeyed' guard"
fi
if grep -q '"genesi-keyring"' "${WORKFLOW}"; then
    pass "genesi-keyring is in the PACKAGES list"
else
    fail "genesi-keyring is not in publish-packages.yml PACKAGES"
fi

# ── The biconditional ────────────────────────────────────────────────────────
HAS_KEY=0
if [ -f "${KEYRING_DIR}/genesi.gpg" ] && [ -f "${KEYRING_DIR}/genesi-trusted" ]; then
    HAS_KEY=1
fi

DESKTOP_DEPENDS=0
if grep -qE "^[[:space:]]*'genesi-keyring'" "${DESKTOP}"; then
    DESKTOP_DEPENDS=1
fi

# The live ISO carries it too, and for a reason that is easy to lose: the
# installer downloads genesi-calamares from [genesi] at the moment the user
# clicks Install. A live medium without the key would fail that download the
# day signing is switched on -- breaking INSTALLATION, not updates.
ISO_LISTS=0
if grep -qx 'genesi-keyring' "${ISOLIST}" 2>/dev/null; then
    ISO_LISTS=1
fi

if [ "${HAS_KEY}" -eq 1 ]; then
    echo "  (a signing key IS committed)"
    if [ "${ISO_LISTS}" -eq 1 ]; then
        pass "the live ISO carries genesi-keyring"
    else
        fail "a key exists but the live ISO does not carry genesi-keyring.
        calamares-online.sh pulls genesi-calamares from [genesi] on the Install
        click; without the key that breaks the moment signing is enabled."
    fi

    # Shipping the key file without naming it in --populate leaves it present
    # and untrusted, which is the most confusing possible failure.
    if grep -q 'pacman-key --populate .*genesi'          "${ROOT}/genesi-arch/archiso/airootfs/usr/local/bin/calamares-online.sh" 2>/dev/null; then
        pass "the installer populates the genesi keyring, not just archlinux/cachyos"
    else
        fail "calamares-online.sh does not --populate genesi: the key would ship
        on the ISO and never be trusted"
    fi

    if [ "${DESKTOP_DEPENDS}" -eq 1 ]; then
        pass "genesi-desktop depends on genesi-keyring"
    else
        fail "a key exists but genesi-desktop does NOT depend on genesi-keyring —
        it would never reach an installed machine. Add 'genesi-keyring' to
        depends= in packages/genesi-desktop/PKGBUILD and bump pkgrel."
    fi

    # A trusted file that does not describe the shipped keyring is the failure
    # mode that only bites after SigLevel is raised.
    if [ -s "${KEYRING_DIR}/genesi-trusted" ]; then
        if grep -qE '^[0-9A-Fa-f]{40}:[0-9]+:$' "${KEYRING_DIR}/genesi-trusted"; then
            pass "genesi-trusted is <fingerprint>:<ownertrust>:"
        else
            fail "genesi-trusted is not in <40-hex-fingerprint>:<n>: form:
$(cat "${KEYRING_DIR}/genesi-trusted")"
        fi
    else
        fail "genesi-trusted is empty while genesi.gpg exists"
    fi

    if command -v gpg >/dev/null 2>&1; then
        probe="$(mktemp -d)"
        if GNUPGHOME="${probe}" gpg --batch --quiet --import "${KEYRING_DIR}/genesi.gpg" 2>/dev/null; then
            while IFS=: read -r fpr _; do
                [ -n "${fpr}" ] || continue
                if GNUPGHOME="${probe}" gpg --batch --list-keys "${fpr}" >/dev/null 2>&1; then
                    pass "genesi.gpg contains ${fpr}"
                else
                    fail "genesi-trusted names ${fpr} but genesi.gpg does not contain it"
                fi
            done < "${KEYRING_DIR}/genesi-trusted"
        else
            fail "genesi.gpg is not a keyring gpg can import"
        fi
        rm -rf "${probe}"
    else
        echo "  SKIP  gpg not available — keyring content not cross-checked"
    fi
else
    echo "  (no signing key committed yet)"
    if [ "${DESKTOP_DEPENDS}" -eq 0 ] && [ "${ISO_LISTS}" -eq 0 ]; then
        pass "nothing references the not-yet-built genesi-keyring"
    else
        fail "genesi-desktop depends on genesi-keyring but no key is committed —
        CI skips building the package, so every install and the ISO build will
        fail with 'target not found: genesi-keyring'.
        Run genesi-arch/devtools/genesi-keygen.sh, or drop the dependency."
    fi
fi

echo
if [ "${fails}" -eq 0 ]; then
    echo "keyring wiring: OK"
    exit 0
fi
echo "keyring wiring: ${fails} failure(s)"
exit 1
