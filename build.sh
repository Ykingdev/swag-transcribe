#!/bin/sh
# Builds swag-transcribe.app next to this script, icon included. Run: ./build.sh && open swag-transcribe.app
set -e
cd "$(dirname "$0")"
swift build -c release
BIN=.build/release/SwagTranscribe
APP=swag-transcribe.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

# App icon: render the SwiftUI AppIconView at 1024 px, scale down to every iconset size.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
"$BIN" --render icon "$ICONSET/icon_512x512@2x.png"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    [ "$size" = 512 ] || sips -z $((size * 2)) $((size * 2)) "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
echo "built $APP"
