#!/usr/bin/env bash
#
# genesi-keygen.sh — create the key that signs Genesi OS, once.
#
# This is the only place in the project where private key material is ever
# handled, and it is deliberately a script you run on YOUR machine rather than
# anything CI does. CI never generates a key; it only ever uses one that already
# exists as a GitHub secret. That split is the point: a key CI could regenerate
# is a key anyone with push access can silently replace.
#
# What it does, in order:
#   1. generates a signing key in a throwaway GNUPGHOME (nothing touches your
#      personal ~/.gnupg),
#   2. writes the PUBLIC half into packages/genesi-keyring/ so it ships to every
#      machine,
#   3. pushes the PRIVATE half straight into the GENESI_SIGNING_KEY repository
#      secret with `gh` — it is never written to a file inside the repo,
#   4. hands you one encrypted-at-rest backup to store offline,
#   5. deletes the throwaway keyring.
#
# Losing the private key with no backup is not a small problem: once machines
# are on SigLevel = Required, a repository you can no longer sign is a
# repository they can no longer install from. Step 4 is not optional.
#
# Usage:
#   ./genesi-arch/devtools/genesi-keygen.sh                  # first key
#   ./genesi-arch/devtools/genesi-keygen.sh --rotate         # add a new key
#   ./genesi-arch/devtools/genesi-keygen.sh --no-secret      # skip the gh step
#   ./genesi-arch/devtools/genesi-keygen.sh --repo owner/name
#
set -euo pipefail

# ── Where things live ────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
KEYRING_DIR="${REPO_ROOT}/genesi-arch/packages/genesi-keyring"
PUBRING="${KEYRING_DIR}/genesi.gpg"
TRUSTED="${KEYRING_DIR}/genesi-trusted"

KEY_NAME="Genesi OS"
KEY_EMAIL="dev@genesios.org"
KEY_COMMENT="Genesi OS repository signing key"
KEY_EXPIRY="5y"

ROTATE=0
SET_SECRET=1
GH_REPO=""

while [ $# -gt 0 ]; do
    case "$1" in
        --rotate)     ROTATE=1 ;;
        --no-secret)  SET_SECRET=0 ;;
        --repo)       GH_REPO="${2:?--repo needs owner/name}"; shift ;;
        --email)      KEY_EMAIL="${2:?--email needs an address}"; shift ;;
        -h|--help)    sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
        *)            echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

die() { echo "error: $*" >&2; exit 1; }
say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

# ── Preflight ────────────────────────────────────────────────────────────────
command -v gpg >/dev/null 2>&1 || die "gpg is not installed"
[ -d "${KEYRING_DIR}" ] || die "not a Genesi checkout: ${KEYRING_DIR} is missing"

if [ -f "${PUBRING}" ] && [ "${ROTATE}" -eq 0 ]; then
    die "a key already exists (${PUBRING}).
       Re-running would publish a keyring that does not match what CI signs
       with, which breaks verification on every machine. Use --rotate to ADD a
       key (keeping the old one valid for already-published packages), and read
       genesi-arch/docs/PACKAGE-SIGNING.md first."
fi

if [ "${SET_SECRET}" -eq 1 ]; then
    command -v gh >/dev/null 2>&1 \
        || die "gh (GitHub CLI) is not installed. Install it, or re-run with --no-secret
       and set the GENESI_SIGNING_KEY secret by hand."
    gh auth status >/dev/null 2>&1 \
        || die "gh is not authenticated — run: gh auth login"
    if [ -z "${GH_REPO}" ]; then
        GH_REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
        [ -n "${GH_REPO}" ] \
            || die "could not work out which GitHub repo to use — pass --repo owner/name"
    fi
fi

# ── A throwaway keyring, cleaned up no matter how we exit ────────────────────
WORKDIR="$(mktemp -d)"
chmod 700 "${WORKDIR}"
export GNUPGHOME="${WORKDIR}/gnupg"
mkdir -p "${GNUPGHOME}"
chmod 700 "${GNUPGHOME}"

cleanup() {
    # Shred what we can, then remove. The private key lived here.
    if command -v shred >/dev/null 2>&1; then
        find "${WORKDIR}" -type f -exec shred -u {} + 2>/dev/null || true
    fi
    rm -rf "${WORKDIR}"
}
trap cleanup EXIT INT TERM

# ── Generate ─────────────────────────────────────────────────────────────────
#
# RSA-4096 rather than ed25519. Both are fine for pacman, but this key has to be
# verifiable by every gpg an installed Genesi machine might ever carry, and this
# is the one decision in the file where "boring and universally supported" beats
# "modern".
#
# No passphrase. A passphrase would have to be stored as a second GitHub secret
# next to the key itself, which protects against nothing — the attacker who can
# read one secret can read both. The real protection is that the secret is
# write-only in the GitHub UI and never printed by the workflow.
say "Generating an RSA-4096 signing key (expires in ${KEY_EXPIRY})…"
gpg --batch --quiet --gen-key <<EOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Key-Usage: sign
Name-Real: ${KEY_NAME}
Name-Comment: ${KEY_COMMENT}
Name-Email: ${KEY_EMAIL}
Expire-Date: ${KEY_EXPIRY}
%commit
EOF

FPR="$(gpg --batch --with-colons --list-secret-keys \
        | awk -F: '/^fpr:/ { print $10; exit }')"
[ -n "${FPR}" ] || die "key generation produced no fingerprint"
say "Fingerprint: ${FPR}"

# ── Public half → the keyring package ────────────────────────────────────────
#
# On a rotation the OLD public key must stay in the keyring. Packages already
# published are signed by it, and a machine that has only the new key would
# reject every one of them.
if [ "${ROTATE}" -eq 1 ] && [ -f "${PUBRING}" ]; then
    say "Rotation: keeping the existing public key(s) in the keyring"
    gpg --batch --quiet --import "${PUBRING}"
fi

gpg --batch --quiet --export --output "${PUBRING}.new" \
    || die "could not export the public keyring"
mv -f "${PUBRING}.new" "${PUBRING}"

# genesi-trusted is what makes pacman TRUST the key rather than merely know it.
# Format is fixed by pacman-key: "<fingerprint>:<ownertrust>:", 4 = full trust.
# No comments and no blank lines — every line is fed to gpg as a key id.
if [ "${ROTATE}" -eq 1 ] && [ -f "${TRUSTED}" ]; then
    grep -v "^${FPR}:" "${TRUSTED}" > "${TRUSTED}.new" || true
else
    : > "${TRUSTED}.new"
fi
printf '%s:4:\n' "${FPR}" >> "${TRUSTED}.new"
mv -f "${TRUSTED}.new" "${TRUSTED}"

say "Wrote $(basename "${PUBRING}") and $(basename "${TRUSTED}") into packages/genesi-keyring/"

# ── Wire the package into the distribution ───────────────────────────────────
#
# This has to happen HERE, in the same commit as the key, and not a moment
# earlier. genesi-desktop is installed on every machine and is what a fresh
# install resolves; the instant it depends on genesi-keyring, that package must
# exist in the repository or `pacstrap`, `validate-install.sh` and the ISO
# pipeline all die with "target not found: genesi-keyring".
#
# Before the key exists CI skips building the package, so the dependency would
# point at nothing. After it exists CI builds it every run. Tying the edit to
# key generation is what keeps those two facts from ever disagreeing —
# ci/keyring-wiring-test.sh then enforces the same rule in both directions.
DESKTOP_PKGBUILD="${REPO_ROOT}/genesi-arch/packages/genesi-desktop/PKGBUILD"
if [ -f "${DESKTOP_PKGBUILD}" ] && ! grep -q "genesi-keyring" "${DESKTOP_PKGBUILD}"; then
    OLD_PKGREL="$(awk -F= '/^pkgrel=/ { print $2; exit }' "${DESKTOP_PKGBUILD}")"
    NEW_PKGREL=$(( OLD_PKGREL + 1 ))
    python3 - "${DESKTOP_PKGBUILD}" "${OLD_PKGREL}" "${NEW_PKGREL}" <<'PY'
import io, sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = io.open(path, encoding='utf-8').read()

note = (
    "# pkgrel %s: add genesi-keyring, the public key that verifies everything\n"
    "# else in this list. It is in the meta so it reaches EXISTING systems on a\n"
    "# plain `pacman -Syu` -- which has to happen before any machine's SigLevel\n"
    "# can be raised to Required, or that machine would be unable to verify the\n"
    "# very update that would have given it the key.\n"
) % new
s = s.replace("pkgrel=%s\n" % old, note + "pkgrel=%s\n" % new, 1)

dep = (
    "depends=(\n"
    "    # The trust anchor. First, because nothing below it means anything if\n"
    "    # the machine cannot tell a Genesi package from a file someone put at\n"
    "    # the repository URL.\n"
    "    'genesi-keyring'\n"
)
s = s.replace("depends=(\n", dep, 1)

io.open(path, 'w', encoding='utf-8', newline='\n').write(s)
PY
    say "genesi-desktop now depends on genesi-keyring (pkgrel ${OLD_PKGREL} -> ${NEW_PKGREL})"
fi

# ── Offline backup, before anything else can go wrong ────────────────────────
#
# Deliberately outside the repository. A private key inside a git checkout is
# one `git add -A` away from being public forever.
BACKUP="${HOME}/genesi-signing-key-${FPR:(-8)}.asc"
( umask 077; gpg --batch --quiet --armor --export-secret-keys --output "${BACKUP}" "${FPR}" )
chmod 600 "${BACKUP}"
say "Private key backed up to: ${BACKUP}"

# ── Private half → the GitHub secret ─────────────────────────────────────────
if [ "${SET_SECRET}" -eq 1 ]; then
    say "Setting repository secrets on ${GH_REPO}…"
    gpg --batch --quiet --armor --export-secret-keys "${FPR}" \
        | gh secret set GENESI_SIGNING_KEY --repo "${GH_REPO}" \
        || die "could not set GENESI_SIGNING_KEY"
    printf '%s' "${FPR}" \
        | gh secret set GENESI_SIGNING_KEY_ID --repo "${GH_REPO}" \
        || die "could not set GENESI_SIGNING_KEY_ID"
    say "Secrets set. The next publish run will sign."
else
    say "Skipping the gh step (--no-secret). Set these two secrets by hand:"
    echo "    GENESI_SIGNING_KEY     = the ARMORED PRIVATE KEY in ${BACKUP}"
    echo "    GENESI_SIGNING_KEY_ID  = ${FPR}"
fi

cat <<EOF

──────────────────────────────────────────────────────────────────────────────
 Done. What happens next, and what must NOT happen yet.
──────────────────────────────────────────────────────────────────────────────

 1. Commit the public half AND the genesi-desktop change together — they are
    one atomic change, and splitting them publishes a dependency on a package
    that does not exist yet:

      git add genesi-arch/packages/genesi-keyring genesi-arch/packages/genesi-desktop
      git commit -m "feat(keyring): publish the Genesi repository signing key"

    From that push on, publish-packages.yml signs every package and database,
    and genesi-keyring starts being built and shipped. ci/keyring-wiring-test.sh
    fails the build if the two ever drift apart.

 2. Move ${BACKUP}
    somewhere that is not this machine's home directory, then delete it here.
    Without it, a lost disk means a distribution you can never sign again.

 3. Do NOT change any SigLevel yet. Every machine still needs to RECEIVE
    genesi-keyring on a normal update first. Verify with:

      ./genesi-arch/ci/repo-signature-test.sh

    and only flip to SigLevel = Required once that passes against the live
    repository. genesi-arch/docs/PACKAGE-SIGNING.md walks through it.

EOF
