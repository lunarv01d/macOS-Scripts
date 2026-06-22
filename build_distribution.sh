#!/bin/bash

# Master build script - creates both .app and .pkg

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Building UnbindAD distribution..."
echo ""

# Build app
echo "Step 1: Creating .app bundle..."
bash "$SCRIPT_DIR/create_app_bundle.sh"
if [[ $? -ne 0 ]]; then
  echo "Failed to create app bundle"
  exit 1
fi

echo ""
echo "Step 2: Creating .pkg installer..."
bash "$SCRIPT_DIR/create_pkg_installer.sh"
if [[ $? -ne 0 ]]; then
  echo "Failed to create .pkg installer"
  exit 1
fi

echo ""
echo "============================================"
echo "✓ Build complete!"
echo "============================================"
echo ""
echo "Distribution files:"
echo "  1. UnbindAD.app          - Double-click to run"
echo "  2. UnbindAD_*.pkg        - Installer for /Applications"
echo ""
echo "Next steps:"
echo "  • Distribute UnbindAD.app to technicians via email/Jamf"
echo "  • Or use the .pkg for Jamf policies"
echo ""
