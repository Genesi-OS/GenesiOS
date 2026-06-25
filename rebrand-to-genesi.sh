#!/bin/bash
# Script para rebrandar CachyOS → Genesi OS

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎨 Rebranding CachyOS to Genesi OS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

TARGET_DIR="genesi-iso"

if [ ! -d "$TARGET_DIR" ]; then
    echo "❌ Directory $TARGET_DIR not found!"
    echo "Run: cp -r cachyos-live-iso-full genesi-iso"
    exit 1
fi

cd "$TARGET_DIR"

echo "📝 Step 1: Replacing text references..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Replace CachyOS → Genesi OS (case variations)
find . -type f -not -path "./.git/*" -exec sed -i 's/CachyOS/Genesi OS/g' {} + 2>/dev/null || true
find . -type f -not -path "./.git/*" -exec sed -i 's/cachyos/genesi/g' {} + 2>/dev/null || true
find . -type f -not -path "./.git/*" -exec sed -i 's/CACHYOS/GENESI/g' {} + 2>/dev/null || true

echo "✅ Text references replaced"
echo ""

echo "🎨 Step 2: Replacing colors..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Replace colors (blue → green/teal)
find . -type f -not -path "./.git/*" -exec sed -i 's/#3daee9/#00ff9f/g' {} + 2>/dev/null || true
find . -type f -not -path "./.git/*" -exec sed -i 's/#232629/#0a0f0d/g' {} + 2>/dev/null || true
find . -type f -not -path "./.git/*" -exec sed -i 's/#31363b/#0a0f0d/g' {} + 2>/dev/null || true

echo "✅ Colors replaced"
echo ""

echo "🔗 Step 3: Replacing URLs..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Replace URLs
find . -type f -not -path "./.git/*" -exec sed -i 's|https://cachyos.org|https://github.com/Genesi-OS/GenesiOS|g' {} + 2>/dev/null || true
find . -type f -not -path "./.git/*" -exec sed -i 's|https://discuss.cachyos.org|https://github.com/Genesi-OS/GenesiOS/issues|g' {} + 2>/dev/null || true
find . -type f -not -path "./.git/*" -exec sed -i 's|https://paste.cachyos.org|https://github.com/Genesi-OS/GenesiOS|g' {} + 2>/dev/null || true

echo "✅ URLs replaced"
echo ""

echo "📦 Step 4: Updating package lists..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Remove CachyOS-specific packages from package list
if [ -f "archiso/packages_desktop.x86_64" ]; then
    # Comment out cachyos-specific packages
    sed -i 's/^cachyos-settings/#cachyos-settings/g' archiso/packages_desktop.x86_64
    sed -i 's/^cachyos-kde-settings/#cachyos-kde-settings/g' archiso/packages_desktop.x86_64
    sed -i 's/^cachyos-hello/#cachyos-hello/g' archiso/packages_desktop.x86_64
    
    echo "✅ Package list updated"
else
    echo "⚠️  Package list not found"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Rebranding complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo "1. Copy Genesi logos and images to genesi-iso/"
echo "2. cd genesi-iso && sudo ./buildiso.sh -p desktop"
echo ""
