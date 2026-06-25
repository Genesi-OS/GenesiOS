#!/usr/bin/env bash
# Genesi OS - install validation (CI + local).
#
# Reproduces what the Calamares installer would do to the TARGET, WITHOUT
# building an ISO or booting a VM, so a broken package set fails here in
# minutes instead of during a real install. Run inside a CachyOS/Arch
# environment (the CI uses the cachyos/cachyos-v3 container).
#
# netinstall.yaml is a SELECTION UI: the user gets the selected:true groups by
# default and can opt into selected:false ones (nvidia, alternative kernels,
# ...). So we validate:
#
#   * DEFAULT set  = pacstrap base + packages in selected:true groups. Split by
#                    Calamares' `critical` flag, because that flag decides
#                    whether a failure aborts the real install:
#       - HARD (critical:true / unset)  = the gate. Must resolve & install.
#       - SOFT (critical:false)         = best-effort. Calamares continues the
#                 install without these, so we only WARN on failure — a transient
#                 repo skew (e.g. firefox-i18n pinned ahead of CachyOS's firefox)
#                 must never block the ISO.
#       Level 1 - `pacman -Sp` dependency dry-run (fast)
#       Level 2 - real `pacstrap` into a throwaway root + install the set the
#                 same way packages@online does (catches file/scriptlet errors)
#
#   * Each OPT-IN group (selected:false) is dry-run INDIVIDUALLY (base+group),
#     never all together (they are mutually exclusive - e.g. one kernel).
#       - a real dependency CONFLICT (like the nvidia-open-dkms 595-vs-610
#         abort) => FAIL the build
#       - merely missing/removed packages (a stale netinstall entry, e.g. an
#         old kernel pruned from the repos) => WARN only, don't block the ISO
#
# Exit non-zero if any HARD check fails. Set SKIP_LEVEL2=1 for Level 1 only.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CALA="$REPO_ROOT/genesi-calamares-config-full/etc/calamares/modules"
PACSTRAP_CONF="$CALA/pacstrap.conf"
NETINSTALL="$CALA/netinstall.yaml"
LIVE_PKGS="$REPO_ROOT/genesi-arch/archiso/packages_desktop.x86_64"
LOCALE_SUB="${LOCALE_SUB:-en-us}"   # expands firefox-i18n-$LOCALE etc.

FAIL=0
note() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m  ✓ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m  ! %s\033[0m\n' "$*"; }
bad()  { printf '\033[1;31m  ✗ %s\033[0m\n' "$*"; FAIL=1; }

# ---------------------------------------------------------------------------
# Same repos the installed target sees: [genesi] + CachyOS (already present) +
# core/extra + multilib (for lib32-*).
# ---------------------------------------------------------------------------
note "Configuring repositories ([genesi] + multilib)"
# Disable signature checking globally for CI to prevent transient keyring failures
sed -i 's/^SigLevel.*/SigLevel = Never/g' /etc/pacman.conf

grep -q '^\[genesi\]' /etc/pacman.conf || cat >> /etc/pacman.conf <<'EOF'

[genesi]
SigLevel = Never
Server = https://raw.githubusercontent.com/Genesi-OS/GenesiOS/main/genesi-arch/repo/x86_64
EOF
grep -q '^\[multilib\]' /etc/pacman.conf || cat >> /etc/pacman.conf <<'EOF'

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF

note "Refreshing package databases (pacman -Sy)"
pacman -Sy --noconfirm >/dev/null || { bad "pacman -Sy failed"; exit 1; }

# ---------------------------------------------------------------------------
# Parse package sets (selection-aware). Writes:
#   /tmp/_base.txt     pacstrap basePackages
#   /tmp/_default.txt  netinstall packages from selected:true nodes
#   /tmp/_optin.tsv    one opt-in (selected:false) group per line: "name\tpkgs"
# ---------------------------------------------------------------------------
note "Parsing package lists (selection-aware)"
python3 - "$PACSTRAP_CONF" "$NETINSTALL" "$LOCALE_SUB" \
         /tmp/_base.txt /tmp/_default.txt /tmp/_default_soft.txt /tmp/_optin.tsv <<'PY'
import sys, yaml
pacstrap_conf, netinstall, locale, f_base, f_def, f_soft, f_opt = sys.argv[1:8]

def clean(p):
    p = str(p).replace("$LOCALE", locale)
    return None if "$" in p else p   # drop any other unexpanded placeholder

def pkgs_of(node):
    out = []
    for p in node.get("packages", []) or []:
        c = clean(p)
        if c:
            out.append(c)
    return out

# base
base = yaml.safe_load(open(pacstrap_conf))
with open(f_base, "w") as fh:
    for p in base.get("basePackages", []) or []:
        c = clean(p)
        if c:
            fh.write(c + "\n")

net = yaml.safe_load(open(netinstall)) or []

def selected(node):           # default-checked unless explicitly false
    return node.get("selected", True) is not False

# A group flagged `critical: false` is non-blocking: Calamares CONTINUES the
# install if it fails. We mirror that by splitting the default (selected) set
# into HARD (the real gate) and SOFT (critical:false) packages. The SOFT set
# only warns — never fails — on resolve/install errors, so a transient upstream
# skew (e.g. firefox-i18n pinning a firefox newer than CachyOS has rebuilt yet)
# can't block the whole ISO. Criticality propagates down to subgroups.
default_hard, default_soft, optin = [], [], []

def collect(node, soft):       # split an active (selected) subtree by criticality
    soft = soft or (node.get("critical") is False)
    (default_soft if soft else default_hard).extend(pkgs_of(node))
    for sg in node.get("subgroups", []) or []:
        if selected(sg):
            collect(sg, soft)

def all_pkgs(node):            # every package in a subtree, ignoring selection
    out = list(pkgs_of(node))
    for sg in node.get("subgroups", []) or []:
        out += all_pkgs(sg)
    return out

for grp in net:
    name = grp.get("name", "?")
    if selected(grp):
        collect(grp, False)
        # selected:false subgroups inside a selected group are opt-in too
        for sg in grp.get("subgroups", []) or []:
            if not selected(sg):
                optin.append((f"{name} / {sg.get('name','?')}", all_pkgs(sg)))
    else:
        optin.append((name, all_pkgs(grp)))

def dedupe(seq, exclude=()):   # keep order, drop dups and anything excluded
    seen, out = set(exclude), []
    for p in seq:
        if p not in seen:
            seen.add(p); out.append(p)
    return out

hard = dedupe(default_hard)
soft = dedupe(default_soft, exclude=set(hard))   # hard wins if a pkg is in both

with open(f_def, "w") as fh:
    fh.write("\n".join(hard) + ("\n" if hard else ""))
with open(f_soft, "w") as fh:
    fh.write("\n".join(soft) + ("\n" if soft else ""))
with open(f_opt, "w") as fh:
    for name, ps in optin:
        ps = sorted(set(ps))
        if ps:
            fh.write(name + "\t" + " ".join(ps) + "\n")
PY

mapfile -t BASE    < /tmp/_base.txt
mapfile -t DEFAULT < /tmp/_default.txt
mapfile -t SOFT    < /tmp/_default_soft.txt
mapfile -t LIVE    < <(grep -vE '^\s*(#|$)' "$LIVE_PKGS" | tr -d ' \t\r')
ok "base packages:            ${#BASE[@]}"
ok "default (critical) pkgs:  ${#DEFAULT[@]}"
ok "default (non-critical):   ${#SOFT[@]}"
ok "live ISO packages:        ${#LIVE[@]}"
ok "opt-in groups:            $(wc -l < /tmp/_optin.tsv)"
[ "${#BASE[@]}" -gt 0 ] && [ "${#DEFAULT[@]}" -gt 0 ] || { bad "empty set - parse failed"; exit 1; }

# ---------------------------------------------------------------------------
# LEVEL 1 - dependency dry-run of the HARD (always-installed) sets.
# ---------------------------------------------------------------------------
dryrun_hard() { # <label> <pkgs...>
  local label="$1"; shift
  if pacman -Sp --needed --noconfirm "$@" >/dev/null 2>/tmp/_err </dev/null; then
    ok "Level 1: $label resolves"
  else
    bad "Level 1: $label FAILED to resolve"
    grep -iE 'error|unable to satisfy|cannot resolve|target not found|conflict' /tmp/_err \
      | sed 's/^/      /' | head -20
  fi
}

note "LEVEL 1 - dependency dry-run (hard gate)"
dryrun_hard "live ISO airootfs"        "${LIVE[@]}"
dryrun_hard "target base (pacstrap)"   "${BASE[@]}"
dryrun_hard "base + default netinstall (critical)" "${BASE[@]}" "${DEFAULT[@]}"

# Non-critical (critical:false) default groups: resolve as a courtesy check but
# only WARN on failure — Calamares continues the install without them, so a
# transient repo skew here must not block the ISO.
if [ "${#SOFT[@]}" -gt 0 ]; then
  if pacman -Sp --needed --noconfirm "${BASE[@]}" "${SOFT[@]}" >/dev/null 2>/tmp/_err </dev/null; then
    ok "Level 1: base + non-critical netinstall resolves"
  else
    warn "Level 1: non-critical netinstall has unresolved deps (install continues without them — critical:false)"
    grep -iE 'unable to satisfy|cannot resolve|target not found|conflict' /tmp/_err \
      | sed 's/^/      /' | head -10
  fi
fi

# ---------------------------------------------------------------------------
# Opt-in groups: dry-run each on top of base. Distinguish a real dependency
# conflict (fail) from merely-missing packages (warn).
# ---------------------------------------------------------------------------
note "Opt-in groups - dependency dry-run (conflict=fail, missing=warn)"
while IFS=$'\t' read -r gname gpkgs; do
  [ -n "$gname" ] || continue
  # shellcheck disable=SC2086
  if pacman -Sp --needed --noconfirm "${BASE[@]}" $gpkgs >/dev/null 2>/tmp/_err </dev/null; then
    ok "opt-in: $gname resolves"
  elif grep -qiE 'unable to satisfy|could not satisfy|in conflict|cannot resolve.*dependency' /tmp/_err; then
    bad "opt-in: $gname has a DEPENDENCY CONFLICT (install-breaker)"
    grep -iE 'unable to satisfy|could not satisfy|conflict|cannot resolve' /tmp/_err \
      | sed 's/^/      /' | head -10
  else
    warn "opt-in: $gname has missing/removed packages (stale netinstall entry, not blocking)"
    grep -iE 'target not found' /tmp/_err | sed 's/^/      /' | head -10
  fi
done < /tmp/_optin.tsv

# ---------------------------------------------------------------------------
# LEVEL 2 - real install of the DEFAULT path into a throwaway root.
# ---------------------------------------------------------------------------
if [ "${SKIP_LEVEL2:-0}" = "1" ]; then
  note "LEVEL 2 skipped (SKIP_LEVEL2=1)"
else
  note "LEVEL 2 - real pacstrap base + install default netinstall set"
  ROOT="$(mktemp -d /tmp/genesi-root.XXXXXX)"
  trap 'rm -rf "$ROOT"' EXIT
  if pacstrap -c "$ROOT" "${BASE[@]}" </dev/null; then
    ok "Level 2: pacstrap base OK"
    pacman --root "$ROOT" -Sy --noconfirm >/dev/null 2>&1 </dev/null || true
    if pacman --root "$ROOT" -S --noconfirm --needed --overwrite='*' \
              --disable-download-timeout "${DEFAULT[@]}" </dev/null; then
      ok "Level 2: default (critical) netinstall set installed OK"
    else
      bad "Level 2: default netinstall install FAILED (file conflict / scriptlet / dep)"
    fi
    # Non-critical packages: best-effort, never fail the build. Install them one
    # at a time so a single skewed package (e.g. firefox-i18n-en-us pinned ahead
    # of CachyOS's firefox) is skipped while the rest (firefox itself, printing,
    # ...) still go in — exactly what Calamares does for critical:false groups.
    if [ "${#SOFT[@]}" -gt 0 ]; then
      skipped=0
      for pkg in "${SOFT[@]}"; do
        [ -n "$pkg" ] || continue
        pacman --root "$ROOT" -S --noconfirm --needed --overwrite='*' \
               --disable-download-timeout "$pkg" </dev/null >/dev/null 2>/tmp/_err \
          || { warn "Level 2: non-critical '$pkg' skipped (critical:false, won't block the ISO)"; skipped=$((skipped+1)); }
      done
      ok "Level 2: non-critical set processed best-effort ($skipped skipped)"
    fi
  else
    bad "Level 2: pacstrap base FAILED"
  fi
fi

# ---------------------------------------------------------------------------
note "RESULT"
if [ "$FAIL" -eq 0 ]; then
  ok "All hard install validations passed - safe to build the ISO"
  exit 0
else
  bad "Install validation FAILED - NOT safe to build the ISO"
  exit 1
fi
