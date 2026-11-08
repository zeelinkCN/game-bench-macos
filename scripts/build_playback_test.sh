#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
TEST_APP="$PWD/build/PlaybackPerformance.app"
TEST_LIBRARY="${GAMEBENCH_LIBRARY_DIR:-$PWD/../GameBench-Library}"
TEST_SDK="$(xcrun --show-sdk-path)"
if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
    TEST_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
mkdir -p "$TEST_APP/Contents/MacOS" "$TEST_APP/Contents/Resources"
cp tests/playback-performance-info.plist "$TEST_APP/Contents/Info.plist"
ln -sfn "$PWD/.cache/cores" "$TEST_APP/Contents/Resources/Cores"
ln -sfn "$TEST_LIBRARY" "$TEST_APP/Contents/Resources/Games"
xcrun clang -O2 -target arm64-apple-macosx14.0 -isysroot "$TEST_SDK" -std=c11 -c Sources/Core/RetroBridge.c -o build/RetroBridge.o
xcrun swiftc -O -sdk "$TEST_SDK" -swift-version 5 -parse-as-library -target arm64-apple-macosx14.0 \
    -D PLAYBACK_PERFORMANCE_TESTS -import-objc-header Sources/Core/RetroBridge.h \
    Sources/App/*.swift tests/playback_performance.swift build/RetroBridge.o \
    -framework SwiftUI -framework AppKit -framework GameController -framework IOKit \
    -framework AudioToolbox -o "$TEST_APP/Contents/MacOS/PlaybackPerformance"
"$TEST_APP/Contents/MacOS/PlaybackPerformance" --body-only
echo "Open $TEST_APP to run the three-game presentation test. Results: build/playback-performance-report.json"
