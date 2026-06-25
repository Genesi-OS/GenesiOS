#!/bin/bash
# Setup completo do ambiente de build do Genesi OS

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Genesi OS - Complete Build Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================
# STEP 1: Build Genesi packages locally
# ============================================================
echo "📦 Step 1: Building Genesi packages..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cd "$SCRIPT_DIR/genesi-arch"
bash build-local-packages.sh

if [ ! -d "local-repo" ] || [ ! -f "local-repo/genesi.db" ]; then
    echo "❌ Failed to build packages!"
    exit 1
fi

echo "✅ Packages built successfully"
echo ""

# ============================================================
# STEP 2: Copy genesi-iso if not exists
# ============================================================
if [ ! -d "$SCRIPT_DIR/genesi-iso" ]; then
    echo "📋 Step 2: Creating genesi-iso from cachyos-live-iso-full..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    cp -r "$SCRIPT_DIR/cachyos-live-iso-full" "$SCRIPT_DIR/genesi-iso"
    echo "✅ genesi-iso created"
else
    echo "✅ genesi-iso already exists"
fi
echo ""

# ============================================================
# STEP 3: Apply rebranding
# ============================================================
echo "🎨 Step 3: Applying Genesi branding..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$SCRIPT_DIR/genesi-iso"

# Text replacements
find . -type f -not -path "./.git/*" -exec sed -i 's/CachyOS/Genesi OS/g' {} + 2>/dev/null || true
find . -type f -not -path "./.git/*" -exec sed -i 's/cachyos/genesi/g' {} + 2>/dev/null || true
find . -type f -not -path "./.git/*" -exec sed -i 's/CACHYOS/GENESI/g' {} + 2>/dev/null || true

# Color replacements
find . -type f -not -path "./.git/*" -exec sed -i 's/#3daee9/#00ff9f/g' {} + 2>/dev/null || true
find . -type f -not -path "./.git/*" -exec sed -i 's/#232629/#0a0f0d/g' {} + 2>/dev/null || true

# URL replacements
find . -type f -not -path "./.git/*" -exec sed -i 's|https://cachyos.org|https://github.com/Genesi-OS/GenesiOS|g' {} + 2>/dev/null || true

echo "✅ Branding applied"
echo ""

# ============================================================
# STEP 4: Setup local package repository in ISO
# ============================================================
echo "📦 Step 4: Setting up local package repository..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Create directory for local packages
mkdir -p "$SCRIPT_DIR/genesi-iso/archiso/airootfs/opt/genesi-packages"

# Copy packages
cp "$SCRIPT_DIR/genesi-arch/local-repo/"*.pkg.tar.zst "$SCRIPT_DIR/genesi-iso/archiso/airootfs/opt/genesi-packages/"

echo "✅ Local packages copied to ISO"
echo ""

# ============================================================
# STEP 5: Modify package list
# ============================================================
echo "📝 Step 5: Modifying package list..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

PKG_LIST="$SCRIPT_DIR/genesi-iso/archiso/packages_desktop.x86_64"

if [ -f "$PKG_LIST" ]; then
    # Remove CachyOS branding packages
    sed -i '/^cachyos-settings$/d' "$PKG_LIST"
    sed -i '/^cachyos-kde-settings$/d' "$PKG_LIST"
    sed -i '/^cachyos-hello$/d' "$PKG_LIST"
    
    # Add calamares if not present
    if ! grep -q "^calamares$" "$PKG_LIST"; then
        echo "calamares" >> "$PKG_LIST"
    fi
    
    echo "✅ Package list modified"
else
    echo "⚠️  Package list not found"
fi
echo ""

# ============================================================
# STEP 6: Copy customize scripts
# ============================================================
echo "📋 Step 6: Copying customize scripts..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Copy our customize scripts
cp "$SCRIPT_DIR/genesi-arch/archiso/airootfs/root/customize_airootfs.sh" \
   "$SCRIPT_DIR/genesi-iso/archiso/airootfs/root/customize_airootfs.sh"

cp "$SCRIPT_DIR/genesi-arch/archiso/airootfs/root/customize_airootfs_genesi.sh" \
   "$SCRIPT_DIR/genesi-iso/archiso/airootfs/root/customize_airootfs_genesi.sh"

# Copy Calamares config
mkdir -p "$SCRIPT_DIR/genesi-iso/archiso/airootfs/etc/calamares/modules"
cp "$SCRIPT_DIR/genesi-arch/archiso/airootfs/etc/calamares/modules/packages.conf.genesi" \
   "$SCRIPT_DIR/genesi-iso/archiso/airootfs/etc/calamares/modules/packages.conf.genesi"

echo "✅ Customize scripts copied"
echo ""

# ============================================================
# STEP 7: Copy profiledef.sh
# ============================================================
echo "📋 Step 7: Updating profiledef.sh..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cp "$SCRIPT_DIR/genesi-arch/archiso/profiledef.sh" \
   "$SCRIPT_DIR/genesi-iso/archiso/profiledef.sh"

echo "✅ profiledef.sh updated"
echo ""

# ============================================================
# DONE
# ============================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Setup complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📍 Next steps:"
echo "   cd genesi-iso"
echo "   sudo ./buildiso.sh -p desktop"
echo ""
echo "📦 Packages that will be installed:"
ls -lh "$SCRIPT_DIR/genesi-iso/archiso/airootfs/opt/genesi-packages/"
echo ""
