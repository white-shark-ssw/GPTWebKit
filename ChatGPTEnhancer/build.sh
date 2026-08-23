#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
rm -rf "$BUILD"
mkdir -p "$BUILD/package"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --sdk iphoneos -f clang++)"
SOURCES=()
while IFS= read -r source; do SOURCES+=("$source"); done < <(find "$ROOT/Sources" -name '*.mm' -type f | sort)
"$CLANG" \
  -isysroot "$SDK" \
  -target arm64-apple-ios17.0 \
  -dynamiclib \
  -fobjc-arc \
  -fblocks \
  -std=c++17 \
  -O2 \
  -Wno-deprecated-declarations \
  -framework Foundation \
  -framework UIKit \
  -framework QuartzCore \
  -framework CoreGraphics \
  -Wl,-install_name,@rpath/ChatGPTEnhancer.dylib \
  "${SOURCES[@]}" \
  -o "$BUILD/ChatGPTEnhancer.dylib"
codesign -f -s - "$BUILD/ChatGPTEnhancer.dylib"
cp "$BUILD/ChatGPTEnhancer.dylib" "$BUILD/package/"
cp "$ROOT/Support/ChatGPTEnhancer.plist" "$BUILD/package/"
cp "$ROOT/README.md" "$BUILD/package/README.txt"
(cd "$BUILD/package" && /usr/bin/zip -9 -r "../ChatGPTEnhancer-0.1.0-alpha9.zip" .)
file "$BUILD/ChatGPTEnhancer.dylib"
ls -lh "$BUILD/ChatGPTEnhancer.dylib" "$BUILD/ChatGPTEnhancer-0.1.0-alpha9.zip"
