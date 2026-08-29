#!/usr/bin/env bash
#
# systemd-enable-test.sh — the ISO's enable symlinks must BE symlinks.
#
# ── The bug this exists for ───────────────────────────────────────────────────
#
# `systemctl enable` works by putting a symlink in a `.wants/` directory. Git
# records a symlink as mode 120000, with the link target as the blob content.
# On a Windows checkout without core.symlinks, git materialises that as an
# ordinary text file — and if someone then commits from that checkout, the
# symlink becomes mode 100644 in history. The file still LOOKS right: it is
# named correctly and contains the target path.
#
# All 21 entries in this profile were in that state. The consequence, on a real
# ISO booted 2026-08-29:
#
#     pacman-init.service - Initializes Pacman keyring
#        Loaded: loaded (/etc/systemd/system/pacman-init.service; disabled)
#        Active: inactive (dead)
#
# So the live session had no pacman keyring. And that is not a live-session
# inconvenience, because the installer does not BUILD the target's keyring — it
# COPIES the live one:
#
#     cp -a /etc/pacman.d/gnupg "$ROOT/etc/pacman.d/" 2>/dev/null
#
# An empty source, a silenced error, and every installed machine comes out with
# no keyring at all. Which in turn means genesi-keyring's scriptlet — guarded on
# `pacman-key -l` succeeding — skips, so the signing key never gets imported and
# package signing can never be switched on.
#
# One flattened symlink, and the trust anchor of the whole distribution never
# arrives. This check costs a second.
#
# It will re-break: anyone committing this tree from Windows re-flattens them.
# That is precisely why it is a test and not a one-time fix.
#
# Usage: genesi-arch/ci/systemd-enable-test.sh
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}" || exit 2

fails=0
pass() { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }

echo "== systemd enable symlinks in the ISO profile =="

# Every tracked file under any *.wants/ directory of the archiso profile.
entries="$(git ls-files -s 'genesi-arch/archiso/airootfs/etc/systemd/system/*.wants/*' 2>/dev/null)"

if [ -z "${entries}" ]; then
    fail "found no .wants entries at all — did the profile move?"
    echo; echo "systemd enable symlinks: ${fails} failure(s)"; exit 1
fi

total=0
while read -r mode sha _stage path; do
    [ -n "${mode}" ] || continue
    total=$((total + 1))
    name="$(basename "$(dirname "${path}")")/$(basename "${path}")"

    if [ "${mode}" != "120000" ]; then
        fail "${name} is mode ${mode}, not a symlink (120000).
        systemd will not enable it, and the service silently never runs.
        Fix without rewriting content:
          git update-index --cacheinfo 120000,${sha},${path}"
        continue
    fi

    # A symlink blob is the bare target path. A trailing newline makes the
    # link point at \"...service\\n\", which resolves to nothing — the same
    # outcome, harder to see.
    content="$(git cat-file blob "${sha}")"
    raw="$(git cat-file -s "${sha}")"
    if [ "${raw}" -ne "${#content}" ]; then
        fail "${name} has a trailing newline in its link target"
        continue
    fi

    # And it must point at a unit that exists — in the profile itself for a
    # relative target, or in the package-provided path for an absolute one.
    case "${content}" in
        /*) : ;;   # /usr/lib/systemd/system/... comes from a package
        *)
            target="genesi-arch/archiso/airootfs/etc/systemd/system/$(basename "${content}")"
            if [ ! -f "${target}" ]; then
                fail "${name} points at ${content}, which is not in the profile"
                continue
            fi ;;
    esac
done <<< "${entries}"

if [ "${fails}" -eq 0 ]; then
    pass "all ${total} entries are real symlinks with resolvable targets"
fi

# The keyring one specifically, because of what it costs when it is wrong.
if printf '%s' "${entries}" | grep -q 'multi-user.target.wants/pacman-init.service'; then
    pass "pacman-init.service is enabled (the live keyring, and every install's)"
else
    fail "pacman-init.service is no longer enabled in multi-user.target.wants —
        the live ISO will have no pacman keyring, and the installer copies the
        live keyring to the target, so installs come out with none either"
fi

echo
if [ "${fails}" -eq 0 ]; then echo "systemd enable symlinks: OK"; exit 0; fi
echo "systemd enable symlinks: ${fails} failure(s)"
exit 1
