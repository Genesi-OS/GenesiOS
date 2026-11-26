#!/usr/bin/env bash
# Tests for genesi-channel, the script that edits the file every future
# `pacman -Syu` depends on.
#
# It is worth a suite of its own because the failure modes are silent. The
# version this replaces only UNCOMMENTED an existing [genesi-testing] block,
# and /etc/pacman-target.conf — the config the installer writes to a real
# install — never contained one. So on every installed machine `set testing`
# printed "Channel switched to: testing" and changed nothing. Nobody could tell
# from the output that the feature had never worked.
#
# No root, no pacman, no network: the script takes the config path and the
# pacman binary from the environment.
#
#   bash genesi-arch/ci/channel-switch-test.sh

set -uo pipefail

CLI="$(cd "$(dirname "$0")/.." && pwd)/packages/genesi-channel/genesi-channel"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fails=0
check() {           # check <label> <condition-result> [detail]
    if [ "$2" = "0" ]; then
        printf '  PASS  %s\n' "$1"
    else
        printf '  FAIL  %s%s\n' "$1" "${3:+  — $3}"
        fails=$((fails + 1))
    fi
}

# A pacman.conf shaped like the one on an INSTALLED system: [genesi] is there,
# the testing block is not. This is the case that was broken.
make_installed_conf() {
    cat > "$1" <<'EOF'
[options]
HoldPkg = pacman glibc
Architecture = auto

[genesi]
SigLevel = Optional TrustAll
Server = https://raw.githubusercontent.com/Genesi-OS/GenesiOS/main/genesi-arch/repo/$arch

[core]
Include = /etc/pacman.d/mirrorlist
EOF
}

# A pacman.conf shaped like the live ISO's: the block is present, commented.
make_iso_conf() {
    cat > "$1" <<'EOF'
[options]
Architecture = auto

[genesi]
SigLevel = Optional TrustAll
Server = https://raw.githubusercontent.com/Genesi-OS/GenesiOS/main/genesi-arch/repo/$arch

# Genesi testing channel — packages built from the `develop` branch.
#[genesi-testing]
#SigLevel = Optional TrustAll
#Server = https://raw.githubusercontent.com/Genesi-OS/GenesiOS/develop/genesi-arch/repo/$arch

[core]
Include = /etc/pacman.d/mirrorlist
EOF
}

# Stub pacman. `ok` succeeds; `fail` refuses, standing in for a repo whose db
# cannot be fetched.
make_pacman() {
    local path="$TMP/pacman-$1"
    if [ "$1" = "ok" ]; then
        printf '#!/usr/bin/env bash\nexit 0\n' > "$path"
    else
        printf '#!/usr/bin/env bash\necho "error: failed retrieving file" >&2\nexit 1\n' > "$path"
    fi
    chmod +x "$path"
    echo "$path"
}

PAC_OK="$(make_pacman ok)"
PAC_BAD="$(make_pacman fail)"

run() {             # run <conf> <pacman> <args...>
    GENESI_PACMAN_CONF="$1" GENESI_PACMAN_BIN="$2" bash "$CLI" "${@:3}"
}

echo "== an installed system that has never seen the testing block =="
CONF="$TMP/installed.conf"; make_installed_conf "$CONF"
check "starts on stable" "$([ "$(run "$CONF" "$PAC_OK" get)" = stable ]; echo $?)"
run "$CONF" "$PAC_OK" set testing >/dev/null 2>&1
check "set testing succeeds" "$?"
check "and the channel really changed" \
      "$([ "$(run "$CONF" "$PAC_OK" get)" = testing ]; echo $?)" \
      "this is the bug the old version had"
check "the repo block was written" \
      "$(grep -q '^\[genesi-testing\]$' "$CONF"; echo $?)"
check "pointing at the develop branch" \
      "$(grep -q 'GenesiOS/develop/genesi-arch/repo' "$CONF"; echo $?)"
check "stable stayed subscribed too" \
      "$(grep -q '^\[genesi\]$' "$CONF"; echo $?)" \
      "testing is additive, not a replacement"

echo
echo "== switching back =="
run "$CONF" "$PAC_OK" set stable >/dev/null 2>&1
check "set stable succeeds" "$?"
check "back on stable" "$([ "$(run "$CONF" "$PAC_OK" get)" = stable ]; echo $?)"
check "the block is commented, not deleted" \
      "$(grep -q '^#\[genesi-testing\]$' "$CONF"; echo $?)"

echo
echo "== toggling repeatedly must not duplicate anything =="
for _ in 1 2 3; do
    run "$CONF" "$PAC_OK" set testing >/dev/null 2>&1
    run "$CONF" "$PAC_OK" set stable  >/dev/null 2>&1
done
n=$(grep -c '\[genesi-testing\]' "$CONF")
check "exactly one testing block after 3 round trips" \
      "$([ "$n" = 1 ]; echo $?)" "found $n"
n=$(grep -c '^\[genesi\]$' "$CONF")
check "exactly one stable block" "$([ "$n" = 1 ]; echo $?)" "found $n"
check "setting the channel it is already on is a no-op" \
      "$(run "$CONF" "$PAC_OK" set stable | grep -q 'Already on'; echo $?)"

echo
echo "== the live ISO's config, where the block already exists =="
ISO="$TMP/iso.conf"; make_iso_conf "$ISO"
run "$ISO" "$PAC_OK" set testing >/dev/null 2>&1
check "enables the existing block" \
      "$([ "$(run "$ISO" "$PAC_OK" get)" = testing ]; echo $?)"
n=$(grep -c '\[genesi-testing\]' "$ISO")
check "without appending a second one" "$([ "$n" = 1 ]; echo $?)" "found $n"
check "the Server line was uncommented too" \
      "$(grep -q '^Server = https://raw.githubusercontent.com/Genesi-OS/GenesiOS/develop' "$ISO"; echo $?)"
check "the human comment above it stays a comment" \
      "$(grep -q '^# Genesi testing channel' "$ISO"; echo $?)"

echo
echo "== an unreachable testing repo must roll itself back =="
# This is the one that matters most: a repo whose db 404s makes every later
# `pacman -Syu` fail, which turns "I tried the beta" into "my system cannot
# update any more".
BAD="$TMP/rollback.conf"; make_installed_conf "$BAD"
before="$(cat "$BAD")"
run "$BAD" "$PAC_BAD" set testing >/dev/null 2>&1
rc=$?
check "the command reports failure" "$([ "$rc" != 0 ]; echo $?)" "exit was $rc"
check "and the channel is back on stable" \
      "$([ "$(run "$BAD" "$PAC_OK" get)" = stable ]; echo $?)"
check "[genesi] survived the rollback" \
      "$(grep -q '^Server = https://raw.githubusercontent.com/Genesi-OS/GenesiOS/main' "$BAD"; echo $?)"

echo
echo "== the testing repo must come BEFORE [genesi] =="
# pacman takes a package from the first repository listing it, regardless of
# version (pacman.conf(5)). Appended after [genesi], the testing repo lost every
# package the two share, so the channel never delivered one build: a tester on
# testing had genesi-store 23 while [genesi-testing] carried 24.
order_ok() {        # order_ok <conf>: testing header precedes [genesi]
    awk '/^[[:space:]]*#?\[genesi-testing\][[:space:]]*$/ && !t { t = NR }
         /^[[:space:]]*\[genesi\][[:space:]]*$/ && !s { s = NR }
         END { exit !(t && s && t < s) }' "$1"
    echo $?
}
FRESH="$TMP/order-fresh.conf"; make_installed_conf "$FRESH"
run "$FRESH" "$PAC_OK" set testing >/dev/null 2>&1
check "set testing on a fresh install puts the block above [genesi]" "$(order_ok "$FRESH")"
check "...enabled, with its Server line" \
      "$(grep -q '^Server = https://raw.githubusercontent.com/Genesi-OS/GenesiOS/develop' "$FRESH"; echo $?)"

# A machine switched by the old version: block enabled, at the end.
OLD="$TMP/order-old.conf"; make_installed_conf "$OLD"
printf '\n# Genesi testing channel — packages built from the %s branch.\n[genesi-testing]\nSigLevel = Optional TrustAll\nServer = https://raw.githubusercontent.com/Genesi-OS/GenesiOS/develop/genesi-arch/repo/$arch\n' "'develop'" >> "$OLD"
lines_before=$(grep -cv '^[[:space:]]*$' "$OLD")
check "(the old layout really is wrong)" "$([ "$(order_ok "$OLD")" != 0 ]; echo $?)"
run "$OLD" "$PAC_OK" repair >/dev/null 2>&1
check "repair moves it above [genesi]" "$(order_ok "$OLD")"
check "...still enabled" "$([ "$(run "$OLD" "$PAC_OK" get)" = testing ]; echo $?)"
check "...no line lost or added" \
      "$([ "$(grep -cv '^[[:space:]]*$' "$OLD")" = "$lines_before" ]; echo $?)"
check "...[core] still has its Include" \
      "$(awk '/^\[core\]/{c=1;next} c&&/^Include = /{f=1} /^\[/{c=0} END{exit !f}' "$OLD"; echo $?)"
snapshot="$(cat "$OLD")"
run "$OLD" "$PAC_OK" repair >/dev/null 2>&1
check "repair again changes nothing" "$([ "$(cat "$OLD")" = "$snapshot" ]; echo $?)"

# Every installed machine has a COMMENTED block after [genesi]. `repair` runs
# from the package on every upgrade, so it must leave those files alone:
# position only matters once the channel is on, and `set testing` places the
# block before enabling it.
OLDOFF="$TMP/order-old-off.conf"; make_iso_conf "$OLDOFF"
snapshot="$(cat "$OLDOFF")"
run "$OLDOFF" "$PAC_OK" repair >/dev/null 2>&1
check "repair leaves a machine that never enabled testing untouched"       "$([ "$(cat "$OLDOFF")" = "$snapshot" ]; echo $?)"
run "$OLDOFF" "$PAC_OK" set testing >/dev/null 2>&1
check "...and set testing places the block before enabling it" "$(order_ok "$OLDOFF")"

# Already-on-testing with the block in the wrong place: `set testing` fixes it.
OLDSET="$TMP/order-old-set.conf"; cp "$TMP/order-old.conf" "$OLDSET"
make_installed_conf "$OLDSET"
printf '\n[genesi-testing]\nSigLevel = Optional TrustAll\nServer = https://raw.githubusercontent.com/Genesi-OS/GenesiOS/develop/genesi-arch/repo/$arch\n' >> "$OLDSET"
run "$OLDSET" "$PAC_OK" set testing >/dev/null 2>&1
check "set testing while already on testing fixes the order" "$(order_ok "$OLDSET")"

# No [genesi] at all: nothing to come before, so nothing is touched.
NOSTABLE="$TMP/order-nostable.conf"
printf '[options]\nArchitecture = auto\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n\n[genesi-testing]\nServer = x\n' > "$NOSTABLE"
snapshot="$(cat "$NOSTABLE")"
run "$NOSTABLE" "$PAC_OK" repair >/dev/null 2>&1
check "without [genesi], repair leaves the file alone" "$([ "$(cat "$NOSTABLE")" = "$snapshot" ]; echo $?)"

echo
echo "== bad input =="
run "$CONF" "$PAC_OK" set banana >/dev/null 2>&1
check "an unknown channel is rejected" "$([ "$?" = 2 ]; echo $?)"
out="$(run "$CONF" "$PAC_OK" --help)"
check "help mentions both channels" \
      "$(echo "$out" | grep -q 'stable' && echo "$out" | grep -q 'testing'; echo $?)"

echo
if [ "$fails" = 0 ]; then
    echo "ALL TESTS PASSED"
    exit 0
fi
echo "FAILURES: $fails"
exit 1
