#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
swift build -c release
APP="$PWD/ToDo App.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ToDoApp "$APP/Contents/MacOS/ToDoApp"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ToDoApp</string>
<key>CFBundleIdentifier</key><string>local.luoziming.todoapp</string>
<key>CFBundleName</key><string>ToDo App</string>
<key>CFBundleDisplayName</key><string>ToDo App</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built: $APP"
