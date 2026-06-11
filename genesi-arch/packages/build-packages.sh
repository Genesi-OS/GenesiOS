#!/bin/bash
# Build all Genesi OS packages and create repository database

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/repo"

echo "=== Genesi OS Package Builder ==="
echo ""

# Create repo directory
mkdir -p "$REPO_DIR"

# List of packages to build
PACKAGES=(
    "genesi-settings"
    "genesi-kde-settings"
    "genesi-ai-mode"
    "genesi-mempalace"
    "genesi-update"
    "genesi-channel"
    "genesi-calamares"
    "genesi-welcome"
    # genesi-code is published to the separate release-hosted [genesi-apps] repo
    # (publish-apps.yml), NOT here — its 172 MB package exceeds GitHub's 100 MB
    # git file limit and can't be committed to genesi-arch/repo.
)

# Build each package
for pkg in "${PACKAGES[@]}"; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Building: $pkg"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ ! -d "$SCRIPT_DIR/$pkg" ]; then
        echo "❌ Package directory not found: $pkg"
        continue
    fi
    
    cd "$SCRIPT_DIR/$pkg"
    
    # Clean previous builds
    rm -f *.pkg.tar.zst
    
    # Build package
    if makepkg -sf --noconfirm; then
        echo "✅ Built: $pkg"
        
        # Move to repo
        mv *.pkg.tar.zst "$REPO_DIR/"
    else
        echo "❌ Failed to build: $pkg"
        exit 1
    fi
    
    echo ""
done

# Create repository database
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Creating repository database..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$REPO_DIR"

# Remove old database
rm -f genesi.db* genesi.files*

# Create new database
repo-add genesi.db.tar.gz *.pkg.tar.zst

echo ""
echo "✅ Repository database created!"
echo ""
echo "=== Built Packages ==="
ls -lh "$REPO_DIR"/*.pkg.tar.zst
echo ""
echo "=== Repository Files ==="
ls -lh "$REPO_DIR"/genesi.{db,files}.tar.gz
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ All packages built successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo "1. Upload packages to GitHub Releases"
echo "2. Update pacman.conf with repository URL"
echo "3. Run 'sudo pacman -Sy' to sync database"
echo ""
