#!/bin/bash
# Збирає ClawdMenu.app (menu-bar-only, без Dock-іконки)
set -e; cd "$(dirname "$0")"
swift build -c release
APP=ClawdMenu.app; rm -rf $APP; mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp AppIcon.icns clawd.png $APP/Contents/Resources/
cp .build/release/ClawdMenu $APP/Contents/MacOS/
cat > $APP/Contents/Info.plist <<P
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleName</key><string>ClawdMenu</string>
<key>CFBundleIdentifier</key><string>com.user.clawdmenu</string>
<key>CFBundleExecutable</key><string>ClawdMenu</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSUIElement</key><true/>
</dict></plist>
P
codesign --force --sign - $APP
echo "OK: open $APP"
