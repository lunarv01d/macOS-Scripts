#!/bin/bash

# Script to create a .pkg installer for AD Unbind

APP_NAME="UnbindAD"
VERSION="1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="/tmp/unbindad_build"
APP_PATH="$SCRIPT_DIR/$APP_NAME.app"
PKG_OUTPUT="$SCRIPT_DIR/UnbindAD_$VERSION.pkg"

# Check if app exists
if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: $APP_NAME.app not found. Run create_app_bundle.sh first."
  exit 1
fi

# Create build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/Applications"

# Copy app to build directory
cp -r "$APP_PATH" "$BUILD_DIR/Applications/"

# Create component plist
cat > "$BUILD_DIR/component.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>BundleIsRelocatable</key>
	<true/>
	<key>BundleOverwriteAction</key>
	<string>upgrade</string>
	<key>RootRelativeBundlePath</key>
	<string>Applications/UnbindAD.app</string>
</dict>
</plist>
EOF

# Create the package
pkgbuild \
  --root "$BUILD_DIR" \
  --component-plist "$BUILD_DIR/component.plist" \
  --identifier "com.lisd.unbindad" \
  --version "$VERSION" \
  --install-location "/" \
  "$PKG_OUTPUT"

# Create distribution plist for better installer UI
cat > "$BUILD_DIR/distribution.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<installer-gui-script minSpecVersion="1">
  <title>Unbind from Active Directory</title>
  <organization>Lubbock Independent School District</organization>
  <options require-scripts="false" />
  <license file="LICENSE.txt" />
  <pkg-ref id="com.lisd.unbindad" />
  <options hostArchitectures="arm64,x86_64"/>
  <choices-outline>
    <line choice="com.lisd.unbindad"/>
  </choices-outline>
  <choice id="com.lisd.unbindad" title="Unbind AD App">
    <pkg-ref id="com.lisd.unbindad"/>
  </choice>
</installer-gui-script>
EOF

# Clean up
rm -rf "$BUILD_DIR"

echo "✓ Created: $(basename $PKG_OUTPUT)"
echo ""
echo "To install:"
echo "  1. Open the .pkg file"
echo "  2. Follow the installer"
echo "  3. App will be installed to /Applications/UnbindAD.app"
echo ""
echo "Package location: $PKG_OUTPUT"
