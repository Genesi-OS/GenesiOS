#!/usr/bin/env bash
#
# hypr-migration-test.sh — every section of the Hyprland migration must apply.
#
# ── Why ──────────────────────────────────────────────────────────────────────
#
# genesi-caelestia-settings ships hyprland.conf into /etc/skel, which only ever
# seeds NEW accounts. Everyone already installed keeps the copy Calamares made,
# so anything added to that file reaches existing users through _migrate_hypr()
# in the .install scriptlet -- or it reaches them not at all.
#
# It reached them not at all. _migrate_hypr() used to open with a "skip if
# fully up to date" gate that listed every previous migration by hand. A
# section added without also adding its marker to that list was unreachable:
# the function returned first. The display keybinds were written, shipped and
# installed, and never applied to a single existing config. Nothing errored --
# the scriptlet ran, succeeded, and did nothing.
#
# ── How this stays true ──────────────────────────────────────────────────────
#
# The markers are read OUT OF THE SCRIPTLET: every `grep -q 'X' "$cfg"` that
# guards an append. Add a section and this test starts requiring it without
# anyone remembering to come here. That is the point -- the bug was a
# hand-maintained list, so a hand-maintained list cannot be the fix.
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL="$ROOT/genesi-arch/packages/genesi-caelestia-settings/genesi-caelestia-settings.install"
SKEL="$ROOT/genesi-arch/packages/genesi-caelestia-settings/hyprland.conf"

fail=0
note() { printf '  %s\n' "$*"; }

echo "== Hyprland migration =="
[ -f "$INSTALL" ] || { note "FAIL  missing $INSTALL"; exit 1; }
[ -f "$SKEL" ]    || { note "FAIL  missing $SKEL"; exit 1; }

# Only _migrate_hypr's own guards. The scriptlet migrates several files, and
# the qt6ct markers would otherwise be checked against the wrong config.
mapfile -t MARKERS < <(
  sed -n '/^_migrate_hypr()/,/^}/p' "$INSTALL" \
    | grep -oE "grep -q '[^']+'" \
    | sed -E "s/^grep -q '(.*)'$/\1/" \
    | grep -vF 'caelestia shell -d' \
    | sort -u
)
if [ "${#MARKERS[@]}" -eq 0 ]; then
  note "FAIL  no section markers found in _migrate_hypr -- it was restructured"
  note "      and this check is now blind."
  exit 1
fi
note "sections found: ${#MARKERS[@]}"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cfg="$tmp/hyprland.conf"

run_migration() {
  # The scriptlet only DEFINES functions, so sourcing it is safe.
  ( set +eu
    # shellcheck disable=SC1090
    . "$INSTALL" >/dev/null 2>&1
    _migrate_hypr "$cfg" "$(id -u):$(id -g)" >/dev/null 2>&1
  )
}

echo
note "case 1: a long-installed user, carrying every marker but the newest"
# This is exactly the state the old gate mistook for "nothing to do".
{
  echo "exec-once = caelestia shell -d"
  for m in "${MARKERS[@]}"; do
    [ "$m" = "${MARKERS[${#MARKERS[@]}-1]}" ] && continue
    echo "# seeded: $m"
  done
} > "$cfg"
missing=()
run_migration
for m in "${MARKERS[@]}"; do grep -qF "$m" "$cfg" || missing+=("$m"); done
if [ "${#missing[@]}" -gt 0 ]; then
  note "FAIL  the migration ran and these sections did not apply:"
  for m in "${missing[@]}"; do note "        - $m"; done
  note "      A section that never applies ships as a feature nobody has."
  fail=1
else
  note "PASS  all ${#MARKERS[@]} sections applied"
fi

echo
note "case 2: pacman runs post_upgrade on EVERY upgrade -- twice must be safe"
before="$(wc -l < "$cfg")"
run_migration
after="$(wc -l < "$cfg")"
if [ "$before" != "$after" ]; then
  note "FAIL  the second run added $((after - before)) lines -- not idempotent"
  fail=1
else
  note "PASS  idempotent ($before lines both times)"
fi

echo
note "case 3: a config that is not Genesi's is left alone"
printf 'bind = SUPER, Q, killactive,\n' > "$cfg"
run_migration
if [ "$(wc -l < "$cfg")" != "1" ]; then
  note "FAIL  edited a config that is not ours"
  fail=1
else
  note "PASS  untouched"
fi

echo
note "case 4: no marker may collide with what the Genesi CLIs write"
# Genesi's CLIs append their own `source = ...` lines to hyprland.conf the
# first time someone changes a setting. A section marker that is a SUBSTRING of
# one of those lines makes the migration believe it already ran -- so the
# people who TRIED a feature are exactly the ones who never get the rest of it.
#
# Not hypothetical: the display keybinds guarded on the word "genesi-display",
# which is inside `source = ~/.config/hypr/genesi-display.conf` -- a line
# genesi-display itself writes. Reported from hardware as "the keys still do
# nothing" after the fix that was supposed to deliver them.
#
# Checked statically. Running the migration and looking for the marker proves
# nothing here: the colliding line contains the marker, so the check would
# pass on exactly the broken case.
CLI_LINES="$(
  for cli in "$ROOT"/genesi-arch/packages/genesi-*/genesi-display              "$ROOT"/genesi-arch/packages/genesi-*/genesi-input; do
    [ -f "$cli" ] || continue
    grep -hoE '(# )?genesi-[a-z]+(\.conf|: [a-z -]+)' "$cli"
    grep -hoE 'source = [^"]*genesi-[a-z]+\.conf' "$cli"
  done | sort -u
)"
if [ -z "$CLI_LINES" ]; then
  note "FAIL  found nothing the CLIs write -- they were renamed or moved,"
  note "      and this check is now blind."
  fail=1
else
  collided=()
  for m in "${MARKERS[@]}"; do
    if printf '%s
' "$CLI_LINES" | grep -qF -- "$m"; then
      collided+=("$m")
    fi
  done
  if [ "${#collided[@]}" -gt 0 ]; then
    note "FAIL  these markers also match a line a Genesi CLI writes into"
    note "      hyprland.conf, so the section is skipped for anyone who has"
    note "      used that tool:"
    for m in "${collided[@]}"; do note "        - $m"; done
    note "      Guard on a line the section itself appends (the bind, the"
    note "      exec-once), never on a tool's name."
    fail=1
  else
    note "PASS  all ${#MARKERS[@]} markers are specific to their own section"
  fi
fi

echo
note "case 5: /etc/skel and the migration must agree"
# A new account gets the skel file; an existing one gets the migration. If they
# disagree, the two halves of the user base end up on different desktops.
skel_missing=()
for m in "${MARKERS[@]}"; do grep -qF "$m" "$SKEL" || skel_missing+=("$m"); done
if [ "${#skel_missing[@]}" -gt 0 ]; then
  note "FAIL  the migration adds these and /etc/skel/hyprland.conf lacks them,"
  note "      so a NEW account would never get them:"
  for m in "${skel_missing[@]}"; do note "        - $m"; done
  fail=1
else
  note "PASS  new and existing accounts get the same set"
fi

echo
[ "$fail" -eq 0 ] || { echo "Hyprland migration: FAILED"; exit 1; }
echo "Hyprland migration: OK"
