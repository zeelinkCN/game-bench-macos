#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
APP="$PWD/build/拾光游戏厅.app"
LIBRARY_DIR="${GAMEBENCH_LIBRARY_DIR:-}"
THIN_BUILD="${GAMEBENCH_THIN_BUILD:-0}"
if [[ "$THIN_BUILD" != "1" && -z "$LIBRARY_DIR" ]]; then
    if [[ -f "$PWD/Resources/Games/catalog.json" ]]; then LIBRARY_DIR="$PWD/Resources/Games"
    elif [[ -f "$PWD/../GameBench-Library/catalog.json" ]]; then LIBRARY_DIR="$PWD/../GameBench-Library"
    else
        echo "Missing private game library. Set GAMEBENCH_LIBRARY_DIR or clone GameBench-Library beside this repository." >&2
        exit 1
    fi
fi
SDK_PATH="$(xcrun --show-sdk-path)"
# The 27.2 command-line SDK exposes SwiftUI macros without shipping their plugin.
# The installed 26.5 SDK provides the compatible property-wrapper API instead.
if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
    SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
mkdir -p build "$APP/Contents/MacOS" "$APP/Contents/Resources/Cores"
python3 scripts/fetch_cores.py
python3 scripts/make_demo.py
xcrun clang -O2 -target arm64-apple-macosx14.0 -isysroot "$SDK_PATH" -std=c11 -Wall -Wextra -c Sources/Core/RetroBridge.c -o build/RetroBridge.o
xcrun swiftc -O -sdk "$SDK_PATH" -swift-version 5 -parse-as-library -target arm64-apple-macosx14.0 \
    -import-objc-header Sources/Core/RetroBridge.h Sources/App/*.swift build/RetroBridge.o \
    -framework SwiftUI -framework AppKit -framework GameController -framework IOKit \
    -framework AudioToolbox -o "$APP/Contents/MacOS/GameBench"
cp -R Resources/Demo Resources/Licenses "$APP/Contents/Resources/"
rm -rf "$APP/Contents/Resources/Games"
if [[ "$THIN_BUILD" == "1" ]]; then
    mkdir -p "$APP/Contents/Resources/Games"
    print '[]' > "$APP/Contents/Resources/Games/catalog.json"
else
    cp -R "$LIBRARY_DIR" "$APP/Contents/Resources/Games"
fi
if [[ -d Resources/Translations ]]; then cp -R Resources/Translations "$APP/Contents/Resources/"; fi
cp .cache/cores/*.dylib "$APP/Contents/Resources/Cores/"
cp .cache/cores/manifest.json "$APP/Contents/Resources/Cores/source-manifest.json"
cp THIRD_PARTY.md "$APP/Contents/Resources/"
if [[ ! -s Resources/AppIcon.icns ]]; then
    echo "Missing application icon: Resources/AppIcon.icns" >&2
    exit 1
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>拾光游戏厅</string>
<key>CFBundleDisplayName</key><string>拾光游戏厅</string>
<key>CFBundleIdentifier</key><string>local.gamebench.mac</string>
<key>CFBundleExecutable</key><string>GameBench</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.0</string>
<key>CFBundleVersion</key><string>6</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>LSUIElement</key><false/>
<key>LSBackgroundOnly</key><false/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSSupportsAutomaticGraphicsSwitching</key><true/>
<key>NSHumanReadableCopyright</key><string>Game Bench. See THIRD_PARTY.md for emulator licenses.</string>
</dict></plist>
PLIST
for core in "$APP"/Contents/Resources/Cores/*.dylib; do /usr/bin/codesign --force --sign - "$core" 2>/dev/null; done
/usr/bin/codesign --force --sign - "$APP"
echo "Built: $APP"
