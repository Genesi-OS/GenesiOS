#!/usr/bin/env bash
# genesi-apply-theme.sh runs at EVERY KDE login. It must repair Genesi for a
# user who is on Genesi and leave alone a user who picked something else.
#
# It re-applied the Genesi colour scheme (and icons and selection colours) at
# every login for everyone, so a user's own scheme reverted on each reboot.
# The script runs here for real with every desktop tool stubbed, and the test
# reads what it CALLED, per scenario.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$REPO_ROOT/genesi-settings-full/usr/bin/genesi-apply-theme.sh"
if [ ! -f "$script" ]; then
    echo "FAIL: $script missing (check out with submodules)"
    exit 1
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fails=0

mkdir -p "$work/bin" "$work/icons/Tela-circle-green-dark"
log="$work/calls"
for tool in plasma-apply-colorscheme kwriteconfig6 plasma-apply-wallpaperimage plasma-changeicons qdbus6; do
    printf '#!/usr/bin/env bash\necho "%s $*" >> "%s"\n' "$tool" "$log" > "$work/bin/$tool"
done
printf '#!/usr/bin/env bash\nexit 0\n' > "$work/bin/pgrep"
# kreadconfig6 answers from env: SCHEME / ICONS.
cat > "$work/bin/kreadconfig6" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *ColorScheme*) printf '%s' "${FAKE_SCHEME-}" ;;
  *Theme*)       printf '%s' "${FAKE_ICONS-}" ;;
esac
EOF
chmod +x "$work/bin/"*

# Absolute paths in the script point at the stubs.
sed -e "s|/usr/lib/plasma-changeicons|$work/bin/plasma-changeicons|" \
    -e "s|/usr/share/icons/Tela-circle-green-dark|$work/icons/Tela-circle-green-dark|" \
    "$script" > "$work/apply.sh"

run() {   # run <first|later> <scheme> <icons>
    : > "$log"
    local home="$work/home-$RANDOM"
    mkdir -p "$home/.config"
    [ "$1" = later ] && touch "$home/.config/.genesi-theme-applied"
    HOME="$home" PATH="$work/bin:$PATH" FAKE_SCHEME="$2" FAKE_ICONS="$3" bash "$work/apply.sh"
}

has()  { grep -q -- "$1" "$log"; }
check() {
    if eval "$2"; then echo "  PASS  $1"; else echo "  FAIL  $1"; sed 's/^/          /' "$log"; fails=$((fails + 1)); fi
}

run first "" ""
check "first login applies Genesi" "has 'plasma-apply-colorscheme Genesi'"
check "first login sets the icons" "has 'plasma-changeicons Tela-circle-green-dark'"

run later "BreezeLight" "Papirus-Dark"
check "a scheme the user picked is not replaced" "! has 'plasma-apply-colorscheme'"
check "...nor its selection colours" "! has 'Colors:Selection'"
check "icons the user picked are not replaced" "! has 'plasma-changeicons'"

run later "Genesi" "Tela-circle-green-dark"
check "a user still on Genesi gets the repair bounce" \
      "has 'plasma-apply-colorscheme BreezeDark' && has 'plasma-apply-colorscheme Genesi'"
check "...and the readable selection colours" "has 'Colors:Selection'"
check "...and the icon repair" "has 'plasma-changeicons Tela-circle-green-dark'"

run later "Genesi" "breeze-dark"
check "Genesi colours with the user's own icons keeps their icons" "! has 'plasma-changeicons'"

[ "$fails" -eq 0 ] && echo "apply theme: OK" || { echo "apply theme: $fails failure(s)"; exit 1; }
