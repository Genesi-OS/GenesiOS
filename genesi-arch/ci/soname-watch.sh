#!/usr/bin/env bash
# Is every shared library our compiled packages ask for still shipped?
#
# Arch bumps a library's soname now and then and rebuilds its own packages the
# same day. Ours are not rebuilt, and keep asking for the old file. On
# 2026-11-20 sndio went from libsndio.so.7 to .so.9; genesi-libcava and the
# Caelestia services plugin still wanted .so.7, the plugin failed to load,
# and every Genesi Hyprland desktop came up blank. Nothing warned anyone.
#
# This downloads the compiled (x86_64) packages from our [genesi] repo, reads
# what each ELF file needs (readelf NEEDED), and checks every library against
# the current repositories (`pacman -F`) and against what our own packages
# ship. Anything found nowhere is reported with the package to rebuild.
#
# Runs inside the same CachyOS image the publish uses. Writes the report to
# $REPORT (default soname-report.txt) and exits 1 when something is missing.
set -uo pipefail

REPO_URL="${GENESI_REPO_URL:-https://raw.githubusercontent.com/Genesi-OS/GenesiOS/main/genesi-arch/repo/x86_64}"
REPORT="${REPORT:-soname-report.txt}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pacman -Sy --noconfirm --needed binutils curl >/dev/null
pacman -Fy >/dev/null

curl -fsSL -o "$WORK/genesi.db" "$REPO_URL/genesi.db" || { echo "cannot download genesi.db" >&2; exit 2; }
mkdir -p "$WORK/db" && tar -xf "$WORK/genesi.db" -C "$WORK/db"

files=()
for desc in "$WORK"/db/*/desc; do
    f="$(awk '/^%FILENAME%$/{getline; print; exit}' "$desc")"
    case "$f" in *-x86_64.pkg.tar.zst) files+=("$f") ;; esac
done
echo "compiled packages to check: ${#files[@]}"

declare -A ours needs_of
for f in "${files[@]}"; do
    pkgdir="$WORK/pkg/${f%.pkg.tar.zst}"
    mkdir -p "$pkgdir"
    curl -fsSL -o "$WORK/$f" "$REPO_URL/$f" || { echo "cannot download $f" >&2; continue; }
    tar -xf "$WORK/$f" -C "$pkgdir" 2>/dev/null
    while IFS= read -r -d '' elf; do
        # libraries this package ships itself satisfy anyone's NEEDED
        case "$(basename "$elf")" in *.so*) ours["$(basename "$elf")"]=1 ;; esac
        soname="$(readelf -d "$elf" 2>/dev/null | sed -n 's/.*(SONAME).*\[\(.*\)\]/\1/p')"
        [ -n "$soname" ] && ours["$soname"]=1
        while IFS= read -r lib; do
            needs_of["$lib"]+="${f%%-[0-9]*} "
        done < <(readelf -d "$elf" 2>/dev/null | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p')
    done < <(find "$pkgdir" -type f \( -name '*.so*' -o -perm -u+x \) -print0)
done

: > "$REPORT"
missing=0
for lib in "${!needs_of[@]}"; do
    [ -n "${ours[$lib]:-}" ] && continue
    if ! pacman -F --quiet "$lib" >/dev/null 2>&1; then
        pkgs="$(printf '%s\n' ${needs_of[$lib]} | sort -u | tr '\n' ' ')"
        echo "$lib  <- needed by: $pkgs" >> "$REPORT"
        missing=$((missing + 1))
    fi
done

if [ "$missing" -gt 0 ]; then
    echo "MISSING: $missing librar(y/ies) no repository ships any more:"
    cat "$REPORT"
    echo
    echo "Rebuild those packages against the current libraries: bump their pkgrel."
    exit 1
fi
echo "every library our compiled packages need is still shipped"
