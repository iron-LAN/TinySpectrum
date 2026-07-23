#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p .build/module-cache
env CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
  SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
  swift build -c release --scratch-path .build
APP="dist/TinySpectrum.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/TinySpectrum "$APP/Contents/MacOS/TinySpectrum"
cp Resources/Info.plist "$APP/Contents/Info.plist"
rm -f "$APP/Contents/Resources/ShureExport.png"
codesign --force --deep --sign - "$APP"
echo "$APP"
