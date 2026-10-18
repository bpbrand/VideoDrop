#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must be run on macOS." >&2; exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/dist"
APP="$OUT/VideoDrop.app"
TOOLS="${1:-}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$OUT"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>VideoDrop</string>
<key>CFBundleDisplayName</key><string>VideoDrop</string>
<key>CFBundleIdentifier</key><string>io.videodrop.downloader</string>
<key>CFBundleExecutable</key><string>VideoDrop</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>VideoDrop.icns</string>
<key>LSApplicationCategoryType</key><string>public.app-category.video</string>
</dict></plist>
PLIST

iconutil -c icns "$ROOT/Resources/VideoDrop.iconset" -o "$APP/Contents/Resources/VideoDrop.icns"
cp "$ROOT/THIRD-PARTY-NOTICES.md" "$APP/Contents/Resources/THIRD-PARTY-NOTICES.md"
mkdir -p "$APP/Contents/Resources/Licenses"
cp "$ROOT/legal/"*.txt "$APP/Contents/Resources/Licenses/"

# Set a deployment target that matches the published system requirements.
ARCH="$(uname -m)"
swiftc -swift-version 5 -O -target "${ARCH}-apple-macosx13.0" \
  -framework SwiftUI -framework AppKit \
  "$ROOT/Source/DownloadEngine.swift" "$ROOT/Source/VideoDrop.swift" \
  -o "$APP/Contents/MacOS/VideoDrop"

"$APP/Contents/MacOS/VideoDrop" --self-test

if [[ -n "$TOOLS" ]]; then
  for tool in yt-dlp ffmpeg ffprobe deno; do
    if [[ ! -x "$TOOLS/$tool" ]]; then
      echo "Bundled tool missing or not executable: $tool" >&2
      exit 1
    fi
  done
  mkdir -p "$APP/Contents/MacOS/tools"
  cp "$TOOLS"/{yt-dlp,ffmpeg,ffprobe,deno} "$APP/Contents/MacOS/tools/"
  chmod 755 "$APP/Contents/MacOS/tools/"*
  for tool in "$APP/Contents/MacOS/tools/"*; do
    codesign --force --sign - --timestamp=none "$tool"
  done
fi
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"
