#!/usr/bin/env bash
# genesi-settings' upgrade scriptlet must not repaint a colour scheme the user
# picked. Its colour heals wrote Genesi's own values into every user's
# kdeglobals on each update, so a user on another scheme got it back half-Genesi
# ("when you update genesi-settings the color scheme gets messed up").
#
# The three migrations that touch kdeglobals run here for real, as root would,
# with kwriteconfig6/runuser/stat/id stubbed, for one user on Genesi and one on
# BreezeDark. The test reads which kdeglobals each one wrote.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scriptlet="$REPO_ROOT/genesi-arch/packages/genesi-settings/cachyos-settings.install"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fails=0

mkdir -p "$work/bin" "$work/home/gen/.config" "$work/home/breeze/.config"
printf '[General]\nColorScheme=Genesi\n' > "$work/home/gen/.config/kdeglobals"
printf '[General]\nColorScheme=BreezeDark\n' > "$work/home/breeze/.config/kdeglobals"
log="$work/writes"
: > "$log"

# kwriteconfig6 logs the file it was asked to write; runuser just runs it.
cat > "$work/bin/kwriteconfig6" <<EOF
#!/usr/bin/env bash
while [ \$# -gt 0 ]; do
  case "\$1" in --file) echo "\$2" >> "$log"; shift 2 ;; *) shift ;; esac
done
EOF
cat > "$work/bin/kreadconfig6" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$work/bin/runuser" <<'EOF'
#!/usr/bin/env bash
# runuser -u USER -- CMD...  ->  CMD... with HOME set to that user's home
u="$2"; shift 3
HOME="$FAKE_HOMES/$u" exec "$@"
EOF
cat > "$work/bin/stat" <<'EOF'
#!/usr/bin/env bash
basename "${@: -1}"
EOF
cat > "$work/bin/id" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$work/bin/"*

# The scriptlet loops over /home/*; run it once per user, pointed at that one
# scratch home. kwriteconfig6 gets "kdeglobals" (resolved under the user's
# HOME) or a full path, so either form counts as a write to that user.
per_user() {
    : > "$log"
    ( export PATH="$work/bin:$PATH" FAKE_HOMES="$work/home"
      sed "s|/home/\*|$work/home/$1|g" "$scriptlet" > "$work/one.sh"
      . "$work/one.sh"
      fix_selection_contrast
      fix_titlebar_uniformity
      fix_desktop_visual_defaults )
    grep -c -E "(^kdeglobals$|/\.config/kdeglobals$)" "$log" | tr -d ' ' || true
}

check() {
    if [ "$2" = ok ]; then echo "  PASS  $1"; else echo "  FAIL  $1 ($3)"; fails=$((fails + 1)); fi
}

gen=$(per_user gen)
breeze=$(per_user breeze)
[ "$gen" -gt 0 ] && r=ok || r=bad
check "a user on Genesi still gets the colour heals" "$r" "$gen kdeglobals writes"
[ "$breeze" -eq 0 ] && r=ok || r=bad
check "a user on another scheme keeps it: no kdeglobals writes" "$r" "$breeze kdeglobals writes"

[ "$fails" -eq 0 ] && echo "settings upgrade scheme: OK" || { echo "settings upgrade scheme: $fails failure(s)"; exit 1; }
