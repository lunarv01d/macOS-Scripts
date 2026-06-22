#!/bin/bash

# Script to create macOS .app bundle for AD Unbind GUI

APP_NAME="UnbindAD"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="$SCRIPT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_PATH/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Remove existing app
rm -rf "$APP_PATH"

# Create directory structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Create the executable wrapper script
cat > "$MACOS_DIR/UnbindAD" << 'EOF'
#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PYTHON_GUI="$SCRIPT_DIR/UnBind_GUI.py"

# Request admin privileges
osascript - "$PYTHON_GUI" << 'OSASCRIPT'
on run argv
  set pythonScript to item 1 of argv
  do shell script "python3 " & quoted form of pythonScript with administrator privileges
end run
OSASCRIPT

exit $?
EOF

chmod +x "$MACOS_DIR/UnbindAD"

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>UnbindAD</string>
	<key>CFBundleIdentifier</key>
	<string>com.lisd.unbindad</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Unbind AD</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>10.13</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSRequiresIPhoneOS</key>
	<false/>
	<key>NSHumanReadableCopyright</key>
	<string>Lubbock Independent School District</string>
</dict>
</plist>
EOF

# Set app icon (using system Finder icon)
cp /System/Library/CoreServices/Finder.app/Contents/Resources/Finder.icns "$RESOURCES_DIR/AppIcon.icns" 2>/dev/null || true

# Mark as app bundle
touch "$APP_PATH"

echo "✓ Created: $APP_NAME.app"
echo ""
echo "Usage:"
echo "  1. Double-click $APP_NAME.app to run"
echo "  2. Or: open $APP_NAME.app"
echo ""
echo "App location: $APP_PATH"
