#!/usr/bin/env bash
# Build Genesi-Migrate-x86_64.AppImage -- the one file someone downloads on the
# distro they are leaving.
#
# It has to run on Ubuntu 20.04 as well as on Fedora 41, without installing a
# thing, so it carries its own Python and Qt:
#   * Python: a manylinux2014 Python AppImage from niess/python-appimage
#     (glibc 2.17 baseline, so the interpreter itself runs anywhere);
#   * Qt: the PySide6-Essentials wheel, whose manylinux_2_28 build sets the
#     real floor at glibc 2.28 (Ubuntu 20.04 has 2.31, Debian 11 2.31,
#     RHEL/Alma 8 2.28);
#   * libxcb-cursor: Qt >= 6.5 needs it for X11 and many distros don't
#     install it, so it rides along (Wayland sessions don't need it).
#
# Usage: ./build-appimage.sh [outdir]       (needs curl and pip-able network)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/../app"
OUT="${1:-$HERE/out}"
PYVER="${PYVER:-3.12}"
PYSIDE="${PYSIDE:-PySide6-Essentials==6.8.2.1}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$OUT"
cd "$WORK"

echo "==> fetching the Python $PYVER AppImage"
url="$(curl -fsSL "https://api.github.com/repos/niess/python-appimage/releases/tags/python$PYVER" \
       | grep -o '"browser_download_url": *"[^"]*manylinux2014_x86_64.AppImage"' \
       | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')"
[ -n "$url" ] || { echo "no manylinux2014 Python $PYVER AppImage found" >&2; exit 1; }
curl -fsSL -o python.AppImage "$url"
chmod +x python.AppImage
./python.AppImage --appimage-extract >/dev/null
mv squashfs-root AppDir
PY="$(ls AppDir/opt/python$PYVER/bin/python$PYVER)"

echo "==> installing $PYSIDE"
"$PY" -m pip install --quiet --no-warn-script-location --no-cache-dir "$PYSIDE"

# Only Fusion is used; the other Quick Controls styles are dead weight.
SITE="$("$PY" -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
for style in Material Universal Imagine FluentWinUI3 iOS macOS Windows; do
    rm -rf "$SITE/PySide6/Qt/qml/QtQuick/Controls/$style"
done
rm -rf "$SITE/PySide6/Qt/translations" "$SITE"/PySide6/*designer* "$SITE"/PySide6/*.exe

echo "==> adding the app"
mkdir -p AppDir/usr/share/genesi-migrate AppDir/usr/lib
cp "$APP"/*.py "$APP"/*.qml "$APP"/*.js "$APP"/*.sh "$APP"/*.json AppDir/usr/share/genesi-migrate/
cp -r "$APP/icons" AppDir/usr/share/genesi-migrate/
for lib in libxcb-cursor.so.0 libxcb-util.so.1; do
    src="$(ldconfig -p | awk -v l="$lib" '$1 == l { print $NF; exit }')"
    if [ -n "$src" ]; then cp -L "$src" AppDir/usr/lib/; else echo "warning: $lib not on the build host, X11-only users may need it" >&2; fi
done

# python-appimage's own AppRun/desktop/icon describe Python; replace them.
rm -f AppDir/AppRun AppDir/*.desktop AppDir/*.png AppDir/*.svg AppDir/.DirIcon
install -m755 "$HERE/AppRun" AppDir/AppRun
sed "s|@PYVER@|$PYVER|g" -i AppDir/AppRun
cp "$HERE/org.genesi.migrate.desktop" AppDir/
cp "$APP/icons/genesi-migrate.svg" AppDir/genesi-migrate.svg
cp "$APP/icons/genesi-migrate.svg" AppDir/.DirIcon

echo "==> packing"
curl -fsSL -o appimagetool \
    https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
chmod +x appimagetool
# --appimage-extract-and-run: no FUSE in containers/CI.
ARCH=x86_64 ./appimagetool --appimage-extract-and-run --no-appstream \
    AppDir "$OUT/Genesi-Migrate-x86_64.AppImage"
echo "==> $OUT/Genesi-Migrate-x86_64.AppImage"
