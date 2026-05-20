#!/bin/bash
# Prepare local repository and build ISO

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Genesi OS - Prepare and Build ISO"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Build Configuration:"
echo "  - Using repository packages (no local compilation)"
echo "  - Calamares: cachyos-calamares-next from repos"
echo "  - Genesi packages: from CachyOS repos"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo "❌ ERROR: Do not run this script with sudo!"
    echo ""
    echo "This script will:"
    echo "  1. Build packages as normal user (makepkg requirement)"
    echo "  2. Ask for sudo password only when building ISO"
    echo ""
    echo "Please run: bash prepare-and-build.sh"
    exit 1
fi

# Step 1: Create empty local repository database
# We're using packages from CachyOS repos, but mkarchiso expects the genesi.db to exist
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Creating empty local repository database..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

mkdir -p "$SCRIPT_DIR/local-repo"
echo "✅ Created directory: $SCRIPT_DIR/local-repo"

# Create empty database files to prevent mkarchiso errors
touch "$SCRIPT_DIR/local-repo/.empty"
echo "✅ Created empty marker file"

cd "$SCRIPT_DIR/local-repo"
echo "📋 Current directory: $(pwd)"

# Try to create database with repo-add
echo "📦 Running repo-add to create genesi.db..."
# Don't try to add .empty to the DB, it's not a real package and breaks pacman
# Just create an empty tar.gz file and name it correctly
tar czf genesi.db.tar.gz -T /dev/null 2>/dev/null || touch genesi.db.tar.gz

# Create symlinks
ln -sf genesi.db.tar.gz genesi.db 2>/dev/null || true
ln -sf genesi.db.tar.gz genesi.files 2>/dev/null || true

echo ""
echo "📋 Repository database files created:"
ls -lah genesi.* 2>/dev/null || echo "❌ No files created!"

cd "$SCRIPT_DIR"
echo ""
echo "✅ Empty repository database created (using packages from CachyOS repos)"
echo ""

# Step 2: Copy Genesi Calamares config to airootfs/root (for customize_airootfs.sh to use)
echo ""
echo "📋 Copying Genesi Calamares config to airootfs/root..."

# Copy the genesi-calamares-config-full to /root/ inside airootfs
# This will be used by customize_airootfs.sh to overwrite Calamares files AFTER package installation
# DO NOT copy them to /etc/calamares inside airootfs during prepare, as that causes pacman conflicts
# when it tries to install the cachyos-calamares-next package
sudo mkdir -p "$SCRIPT_DIR/archiso/airootfs/root/"
sudo rm -rf "$SCRIPT_DIR/archiso/airootfs/root/genesi-calamares-config-full"
sudo cp -r "../genesi-calamares-config-full" "$SCRIPT_DIR/archiso/airootfs/root/"

echo "✅ Genesi Calamares config copied to /root/ (will be applied by customize_airootfs.sh)"
echo ""

# Step 2.5: (REMOVED) Genesi Settings used to be copied manually here from
# the genesi-settings-full/ submodule. That was needed when genesi-settings
# wasn't in packages_desktop.x86_64. Now that it IS in the package list,
# pacstrap installs the package -> mkarchiso saw the manually-copied files
# as pre-existing -> "conflicting files" abort. Drop the manual cp; let
# pacstrap do its thing. The same applies to wallpapers + apply-theme.sh.
# Files now provided by:
#   - genesi-settings package (skel-override, wallpapers, apply-theme.sh)
#   - genesi-welcome package
#   - genesi-ai-mode package
#   - genesi-calamares-branding package
echo "📋 (Genesi Settings now installed via pacstrap from [genesi] repo)"
echo ""

# Step 2.6: Create CachyOS mirrorlist files in airootfs
echo "📋 Creating CachyOS mirrorlist files..."

# Create the mirrorlist files that will be copied during installation
sudo mkdir -p "$SCRIPT_DIR/archiso/airootfs/etc/pacman.d/"

# Download or create cachyos-mirrorlist
if [ -f /etc/pacman.d/cachyos-mirrorlist ]; then
    sudo cp /etc/pacman.d/cachyos-mirrorlist "$SCRIPT_DIR/archiso/airootfs/etc/pacman.d/"
else
    sudo bash -c 'cat > '"$SCRIPT_DIR"'/archiso/airootfs/etc/pacman.d/cachyos-mirrorlist << "EOF"
##
## CachyOS repository mirrorlist
## Only working mirrors (nl.cachyos.org removed due to DNS issues)
##
Server = https://mirror.cachyos.org/repo/$arch/$repo
Server = https://cdn-77.cachyos.org/repo/$arch/$repo
Server = https://build.cachyos.org/repo/$arch/$repo
EOF'
fi

# Create v3 and v4 mirrorlists (copies of the main one)
sudo cp "$SCRIPT_DIR/archiso/airootfs/etc/pacman.d/cachyos-mirrorlist" "$SCRIPT_DIR/archiso/airootfs/etc/pacman.d/cachyos-v3-mirrorlist"
sudo cp "$SCRIPT_DIR/archiso/airootfs/etc/pacman.d/cachyos-mirrorlist" "$SCRIPT_DIR/archiso/airootfs/etc/pacman.d/cachyos-v4-mirrorlist"

echo "✅ CachyOS mirrorlist files created"
echo ""
echo "📋 Verifying copied files:"
echo "  - Skel override: $(ls -d $SCRIPT_DIR/archiso/airootfs/usr/share/genesi/skel-override 2>/dev/null && echo '✅' || echo '❌')"
echo "  - Wallpaper: $(ls $SCRIPT_DIR/archiso/airootfs/usr/share/wallpapers/genesi/wallpaper.png 2>/dev/null && echo '✅' || echo '❌')"
echo "  - Theme script: $(ls $SCRIPT_DIR/archiso/airootfs/usr/bin/genesi-apply-theme.sh 2>/dev/null && echo '✅' || echo '❌')"
echo "  - CachyOS mirrorlist: $(ls $SCRIPT_DIR/archiso/airootfs/etc/pacman.d/cachyos-mirrorlist 2>/dev/null && echo '✅' || echo '❌')"
echo ""

# Step 3: Copy empty repository database to airootfs
# This prevents errors when mkarchiso tries to sync the genesi repository
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Copying empty repository database to airootfs..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

sudo mkdir -p "$SCRIPT_DIR/archiso/airootfs/opt/genesi-packages/"
sudo chmod 755 "$SCRIPT_DIR/archiso/airootfs/opt/genesi-packages/"
echo "✅ Created directory: $SCRIPT_DIR/archiso/airootfs/opt/genesi-packages/"

echo ""
echo "📋 Files in local-repo before copy:"
ls -lah "$SCRIPT_DIR/local-repo/" || echo "❌ Directory not found!"

# Copy only the database files (no packages)
echo ""
echo "📦 Copying database files..."
if sudo cp -av "$SCRIPT_DIR/local-repo/"genesi.db* "$SCRIPT_DIR/archiso/airootfs/opt/genesi-packages/" 2>&1; then
    echo "✅ Copied genesi.db*"
else
    echo "⚠️  Failed to copy genesi.db*"
fi

if sudo cp -av "$SCRIPT_DIR/local-repo/"genesi.files* "$SCRIPT_DIR/archiso/airootfs/opt/genesi-packages/" 2>&1; then
    echo "✅ Copied genesi.files*"
else
    echo "⚠️  Failed to copy genesi.files*"
fi

echo ""
echo "📋 Files in airootfs/opt/genesi-packages after copy:"
sudo ls -lah "$SCRIPT_DIR/archiso/airootfs/opt/genesi-packages/" || echo "❌ Directory not found!"

echo ""
echo "✅ Empty repository database copied (packages will come from CachyOS repos)"
echo ""
echo ""

# Step 4: Build ISO (this will ask for sudo password)
echo "🔨 Building ISO (will ask for sudo password)..."
echo ""
cd "$SCRIPT_DIR"

# Create logs directory
mkdir -p "$SCRIPT_DIR/logs"
LOG_FILE="$SCRIPT_DIR/logs/build-$(date +%Y%m%d-%H%M%S).log"

echo "📝 Saving build output to: $LOG_FILE"
echo ""

# Run buildiso and capture ALL output (stdout + stderr)
sudo ./buildiso.sh -p desktop 2>&1 | tee "$LOG_FILE"

# Check if build succeeded
if [ ${PIPESTATUS[0]} -eq 0 ]; then
    BUILD_SUCCESS=true
else
    BUILD_SUCCESS=false
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$BUILD_SUCCESS" = true ]; then
    echo "✅ ISO build complete!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "ISO location: $SCRIPT_DIR/out/"
    ls -lh "$SCRIPT_DIR/out/"*.iso 2>/dev/null || echo "No ISO found"
else
    echo "❌ ISO build FAILED!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "❌ Build failed! Check the log for details:"
    echo "   $LOG_FILE"
    echo ""
    echo "Last 50 lines of log:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    tail -50 "$LOG_FILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 1
fi

echo ""
echo "📝 Full build log saved to: $LOG_FILE"
echo ""
