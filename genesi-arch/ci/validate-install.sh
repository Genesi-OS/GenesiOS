#!/usr/bin/env bash
# Genesi OS - install validation (CI + local).
#
# Reproduces what the Calamares installer would do to the TARGET, WITHOUT
# building an ISO or booting a VM, so a broken package set fails here in
# minutes instead of during a real install. Run inside a CachyOS/Arch
# environment (the CI uses the cachyos/cachyos-v3 container).
#
#   Level 1 - dependency dry-run (fast, ~1-2 min):
#       `pacman -Sp --needed <pkgs>` for the live-ISO list, the pacstrap base,
#       and the full netinstall set. Catches version/dependency conflicts like
#       the nvidia-open-dkms 595-vs-610 abort (paste.cachyos.org/p/dd018da.log)
#       without downloading or installing anything.
#
#   Level 2 - real install in a throwaway root (~10 min, downloads packages):
#       real `pacstrap` of the base into a temp dir, then install the netinstall
#       set into it the same way packages@online does. Catches FILE conflicts
#       and scriptlet errors too, not just dependency resolution.
#
# Exit non-zero if any check fails. Set SKIP_LEVEL2=1 to run only Level 1.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CALA="$REPO_ROOT/genesi-calamares-config-full/etc/calamares/modules"
PACSTRAP_CONF="$CALA/pacstrap.conf"
NETINSTALL="$CALA/netinstall.yaml"
LIVE_PKGS="$REPO_ROOT/genesi-arch/archiso/packages_desktop.x86_64"
# Locale used to expand placeholders like firefox-i18n-$LOCALE.
LOCALE_SUB="${LOCALE_SUB:-en-us}"

FAIL=0
note()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()    { printf '\033[1;32m  ✓ %s\033[0m\n' "$*"; }
bad()   { printf '\033[1;31m  ✗ %s\033[0m\n' "$*"; FAIL=1; }

# ---------------------------------------------------------------------------
# Configure the SAME repos the installed target sees: [genesi] + the CachyOS
# repos (already in the container) + core/extra + multilib (for lib32-*).
# ---------------------------------------------------------------------------
note "Configuring repositories ([genesi] + multilib)"
if ! grep -q '^\[genesi\]' /etc/pacman.conf; then
  cat >> /etc/pacman.conf <<'EOF'

[genesi]
SigLevel = Optional TrustAll
Server = https://raw.githubusercontent.com/zFreshy/GenesiOS/main/genesi-arch/repo/x86_64
EOF
  ok "added [genesi]"
fi
if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
  cat >> /etc/pacman.conf <<'EOF'

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
  ok "added [multilib]"
fi

note "Refreshing package databases (pacman -Sy)"
pacman -Sy --noconfirm >/dev/null || { bad "pacman -Sy failed"; exit 1; }

# ---------------------------------------------------------------------------
# Extract the three package sets. netinstall.yaml has nested subgroups, so we
# parse it with a proper YAML reader and walk recursively.
# ---------------------------------------------------------------------------
note "Parsing package lists"
python3 - "$PACSTRAP_CONF" "$NETINSTALL" "$LOCALE_SUB" <<'PY' > /tmp/_base.txt 2> /tmp/_net.txt
import sys, yaml
pacstrap_conf, netinstall, locale = sys.argv[1], sys.argv[2], sys.argv[3]

def clean(p):
    p = str(p).replace("$LOCALE", locale)
    return None if "$" in p else p   # drop any other unexpanded placeholder

# base packages -> stdout
base = yaml.safe_load(open(pacstrap_conf))
for p in base.get("basePackages", []) or []:
    c = clean(p)
    if c: print(c)

# netinstall packages (recursive over groups + subgroups) -> stderr
def walk(node):
    if isinstance(node, dict):
        for p in node.get("packages", []) or []:
            yield p
        for sg in node.get("subgroups", []) or []:
            yield from walk(sg)
    elif isinstance(node, list):
        for it in node:
            yield from walk(it)

net = yaml.safe_load(open(netinstall))
seen = set()
for p in walk(net):
    c = clean(p)
    if c and c not in seen:
        seen.add(c); print(c, file=sys.stderr)
PY

mapfile -t BASE < /tmp/_base.txt
mapfile -t NET  < /tmp/_net.txt
mapfile -t LIVE < <(grep -vE '^\s*(#|$)' "$LIVE_PKGS" | tr -d ' \t\r')

ok "base packages:       ${#BASE[@]}"
ok "netinstall packages: ${#NET[@]}"
ok "live ISO packages:   ${#LIVE[@]}"
[ "${#BASE[@]}" -gt 0 ] && [ "${#NET[@]}" -gt 0 ] || { bad "empty package set - parsing failed"; exit 1; }

# ---------------------------------------------------------------------------
# LEVEL 1 - dependency dry-run. -Sp resolves + prints targets without touching
# anything; non-zero exit means the set is unsatisfiable.
# ---------------------------------------------------------------------------
dryrun() { # <label> <pkgs...>
  local label="$1"; shift
  if pacman -Sp --needed "$@" >/dev/null 2>/tmp/_err; then
    ok "Level 1: $label resolves"
  else
    bad "Level 1: $label FAILED to resolve"
    grep -iE 'error|unable to satisfy|cannot resolve|target not found|conflict' /tmp/_err | sed 's/^/      /' | head -20
  fi
}

note "LEVEL 1 - dependency dry-run"
dryrun "live ISO airootfs"          "${LIVE[@]}"
dryrun "target base (pacstrap)"     "${BASE[@]}"
dryrun "target base + netinstall"   "${BASE[@]}" "${NET[@]}"

# ---------------------------------------------------------------------------
# LEVEL 2 - real install in a throwaway root. pacstrap the base, then install
# the netinstall set like packages@online does (--needed --overwrite=*).
# ---------------------------------------------------------------------------
if [ "${SKIP_LEVEL2:-0}" = "1" ]; then
  note "LEVEL 2 skipped (SKIP_LEVEL2=1)"
else
  note "LEVEL 2 - real pacstrap + netinstall in a throwaway root"
  ROOT="$(mktemp -d /tmp/genesi-root.XXXXXX)"
  trap 'rm -rf "$ROOT"' EXIT
  if pacstrap -c "$ROOT" "${BASE[@]}"; then
    ok "Level 2: pacstrap base OK"
    pacman --root "$ROOT" -Sy --noconfirm >/dev/null 2>&1 || true
    if pacman --root "$ROOT" -S --noconfirm --needed --overwrite='*' \
              --disable-download-timeout "${NET[@]}"; then
      ok "Level 2: netinstall set installed OK"
    else
      bad "Level 2: netinstall install FAILED (file conflict / scriptlet / dep)"
    fi
  else
    bad "Level 2: pacstrap base FAILED"
  fi
fi

# ---------------------------------------------------------------------------
note "RESULT"
if [ "$FAIL" -eq 0 ]; then
  ok "All install validations passed - safe to build the ISO"
  exit 0
else
  bad "Install validation FAILED - NOT safe to build the ISO"
  exit 1
fi
