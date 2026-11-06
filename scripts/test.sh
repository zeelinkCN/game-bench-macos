#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
zsh scripts/build.sh > build/test-build.log 2>&1
xcrun clang -O2 tests/core_smoke.c build/RetroBridge.o -framework AudioToolbox -o build/core-smoke
build/core-smoke
SDK_PATH="$(xcrun --show-sdk-path)"
if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk; fi
xcrun swiftc -O -sdk "$SDK_PATH" -swift-version 5 -parse-as-library \
    Sources/App/Library.swift Sources/App/ChineseNames.swift Sources/App/SeriesCatalog.swift Sources/App/IPSPatch.swift tests/library_smoke.swift -framework SwiftUI -framework AppKit -o build/library-smoke
build/library-smoke
