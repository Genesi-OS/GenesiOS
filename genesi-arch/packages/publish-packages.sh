#!/usr/bin/env bash
# Publish packages to GitHub Releases

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/repo"
RELEASE_TAG="packages-$(date +%Y%m%d)"

echo "=== Publishing Genesi OS Packages ==="
echo ""

# Check if repo exists
if [ ! -d "$REPO_DIR" ]; then
    echo "Error: repo/ directory not found"
    echo "Run ./build-packages.sh first"
    exit 1
fi

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) not installed"
    echo "Install: sudo pacman -S github-cli"
    echo "Or visit: https://cli.github.com/"
    exit 1
fi

# Check if logged in
if ! gh auth status &> /dev/null; then
    echo "Error: Not logged in to GitHub"
    echo "Run: gh auth login"
    exit 1
fi

echo "Repository: Genesi-OS/GenesiOS"
echo "Release tag: $RELEASE_TAG"
echo "Packages to upload:"
ls -lh "$REPO_DIR"/*.pkg.tar.zst "$REPO_DIR"/genesi.db.tar.gz "$REPO_DIR"/genesi.files.tar.gz 2>/dev/null || true
echo ""

read -p "Continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted"
    exit 1
fi

# Create release if it doesn't exist
echo ">>> Creating/updating release..."
gh release create "$RELEASE_TAG" \
    --repo Genesi-OS/GenesiOS \
    --title "Genesi OS Packages - $(date +%Y-%m-%d)" \
    --notes "Genesi OS package repository

## Packages included:
$(cd "$REPO_DIR" && ls -1 *.pkg.tar.zst | sed 's/^/- /')

## Installation:
\`\`\`bash
# Add repository to /etc/pacman.conf
[genesi]
SigLevel = Optional TrustAll
Server = https://github.com/Genesi-OS/GenesiOS/releases/download/$RELEASE_TAG/\$arch

# Update and install
sudo pacman -Sy
sudo pacman -S genesi-settings genesi-kde-settings genesi-ai-mode
\`\`\`
" 2>/dev/null || echo "Release already exists, will update files"

# Upload packages
echo ">>> Uploading packages..."
cd "$REPO_DIR"
gh release upload "$RELEASE_TAG" \
    --repo Genesi-OS/GenesiOS \
    --clobber \
    *.pkg.tar.zst \
    genesi.db.tar.gz \
    genesi.files.tar.gz

echo ""
echo "=== Publish Complete ==="
echo "Repository URL:"
echo "https://github.com/Genesi-OS/GenesiOS/releases/tag/$RELEASE_TAG"
echo ""
echo "Users can now update with:"
echo "sudo pacman -Syu"
echo ""
