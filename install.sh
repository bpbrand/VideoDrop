#!/bin/bash
set -euo pipefail

REPO="bpbrand/VideoDrop"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "VideoDrop is available for Mac only." >&2; exit 1
fi
case "$(uname -m)" in
  arm64) ARCH=arm64 ;;
  x86_64) ARCH=x86_64 ;;
  *) echo "This Mac's CPU is not supported." >&2; exit 1 ;;
esac
if (( $(sw_vers -productVersion | cut -d. -f1) < 13 )); then
  echo "VideoDrop requires macOS 13 or later." >&2; exit 1
fi

ASSET="VideoDrop-macOS-${ARCH}.zip"
URL="https://github.com/${REPO}/releases/latest/download/${ASSET}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Downloading VideoDrop…"
curl -fLSs --retry 3 "$URL" -o "$WORK/$ASSET" || {
  echo "Couldn't download VideoDrop. Check the latest release at https://github.com/${REPO}/releases/latest" >&2
  exit 1
}
curl -fLSs --retry 3 "${URL}.sha256" -o "$WORK/$ASSET.sha256"
( cd "$WORK" && shasum -a 256 -c "$ASSET.sha256" )

mkdir -p "$WORK/unpacked"
ditto -x -k "$WORK/$ASSET" "$WORK/unpacked"
APP="$WORK/unpacked/VideoDrop.app"
if [[ ! -d "$APP" ]]; then echo "The release archive doesn't contain VideoDrop.app." >&2; exit 1; fi
ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null || true)"
if [[ "$ID" != "io.videodrop.downloader" ]]; then
  echo "The app identifier isn't what was expected." >&2; exit 1
fi

DESTDIR="$HOME/Applications"
DEST="$DESTDIR/VideoDrop.app"
mkdir -p "$DESTDIR"
if [[ -e "$DEST" ]]; then
  OLDID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$DEST/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$OLDID" != "$ID" ]]; then
    echo "A different app called VideoDrop already exists in $DESTDIR. Nothing was replaced." >&2; exit 1
  fi
  mv "$DEST" "$WORK/previous.app"
fi
if ! ditto "$APP" "$DEST"; then
  rm -rf "$DEST"
  if [[ -d "$WORK/previous.app" ]]; then mv "$WORK/previous.app" "$DEST"; fi
  echo "Installation failed; your old app (if any) was restored." >&2
  exit 1
fi

echo "Installed VideoDrop in $DEST"
open "$DEST"
