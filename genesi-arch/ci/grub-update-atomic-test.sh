#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
updater="$REPO_ROOT/genesi-arch/packages/genesi-grub-theme/genesi-grub-update"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/boot/grub" "$work/bin"
config="$work/boot/grub/grub.cfg"
backup="$work/boot/grub/grub.cfg.genesi-last-good"

cat > "$work/bin/grub-mkconfig" <<'EOF'
#!/usr/bin/env bash
set -eu
[ "$1" = -o ]
case "${FAKE_GRUB_MODE:-good}" in
  good)
    cat > "$2" <<'CFG'
menuentry 'Genesi OS' {
  linux /boot/vmlinuz-linux-cachyos root=UUID=test rw
  initrd /boot/initramfs-linux-cachyos.img
}
CFG
    ;;
  no-kernel) printf "menuentry 'broken' { true }\n" > "$2" ;;
  fail) exit 9 ;;
esac
EOF
cat > "$work/bin/grub-script-check" <<'EOF'
#!/usr/bin/env bash
grep -q '^INVALID' "$1" && exit 1
exit 0
EOF
cat > "$work/bin/flock" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$work/bin/sync" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$work/bin/grub-mkconfig" "$work/bin/grub-script-check" \
    "$work/bin/flock" "$work/bin/sync"

cat > "$config" <<'EOF'
menuentry 'Previous Genesi OS' {
  linux /boot/vmlinuz-linux-cachyos root=UUID=old rw
}
EOF
cp "$config" "$work/original"

env PATH="$work/bin:$PATH" \
    GENESI_GRUB_CONFIG="$config" \
    GENESI_GRUB_BACKUP="$backup" \
    GENESI_GRUB_LOCK="$work/update.lock" \
    GENESI_GRUB_LIVE_MARKER="$work/not-live" \
    bash "$updater"

grep -q "menuentry 'Genesi OS'" "$config"
cmp -s "$backup" "$work/original"
cp "$config" "$work/known-good"

if env PATH="$work/bin:$PATH" FAKE_GRUB_MODE=no-kernel \
    GENESI_GRUB_CONFIG="$config" \
    GENESI_GRUB_BACKUP="$backup" \
    GENESI_GRUB_LOCK="$work/update.lock" \
    GENESI_GRUB_LIVE_MARKER="$work/not-live" \
    bash "$updater"; then
  echo 'broken candidate was accepted' >&2
  exit 1
fi
cmp -s "$config" "$work/known-good"

echo 'atomic GRUB update tests passed'
