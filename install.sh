#!/bin/bash
set -euo pipefail

REPO="bpbrand/VideoDrop"
APP_NAME="VideoDrop.app"
EXPECTED_ID="io.videodrop.downloader"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "VideoDrop is available for Mac only." >&2
  exit 1
fi
case "$(uname -m)" in
  arm64) ARCH=arm64 ;;
  x86_64) ARCH=x86_64 ;;
  *) echo "This Mac's CPU is not supported." >&2; exit 1 ;;
esac
if (( $(sw_vers -productVersion | cut -d. -f1) < 13 )); then
  echo "VideoDrop requires macOS 13 or later." >&2
  exit 1
fi

ASSET="VideoDrop-macOS-${ARCH}.zip"
URL="https://github.com/${REPO}/releases/latest/download/${ASSET}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

printf 'Downloading VideoDrop...\n'
curl -fLSs --retry 3 "$URL" -o "$WORK/$ASSET" || {
  echo "Couldn't download VideoDrop. See https://github.com/${REPO}/releases/latest" >&2
  exit 1
}
curl -fLSs --retry 3 "${URL}.sha256" -o "$WORK/$ASSET.sha256"
( cd "$WORK" && shasum -a 256 -c "$ASSET.sha256" )

mkdir -p "$WORK/unpacked"
ditto -x -k "$WORK/$ASSET" "$WORK/unpacked"
APP="$WORK/unpacked/$APP_NAME"
if [[ ! -d "$APP" ]]; then
  echo "VideoDrop.app wasn't found in the download." >&2
  exit 1
fi
bundle_id() {
  /usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null || true
}
if [[ "$(bundle_id "$APP")" != "$EXPECTED_ID" ]]; then
  echo "The downloaded app has an unexpected identifier." >&2
  exit 1
fi

check_tools() {
  local app="$1" tool
  for tool in yt-dlp ffmpeg ffprobe deno; do
    if [[ ! -x "$app/Contents/MacOS/tools/$tool" ]]; then
      echo "VideoDrop is missing a required download component: $tool" >&2
      return 1
    fi
  done
}
check_tools "$APP" || {
  echo "The downloaded app is incomplete. Nothing has been installed." >&2
  exit 1
}

# Prefer an existing installation so subsequent installs don't create another copy.
# Otherwise use /Applications when it's writable, or personal Applications.
SYSTEM_DIR="/Applications"
PERSONAL_DIR="$HOME/Applications"
if [[ -d "$SYSTEM_DIR/$APP_NAME" ]]; then
  if [[ "$(bundle_id "$SYSTEM_DIR/$APP_NAME")" != "$EXPECTED_ID" ]]; then
    echo "Another app called VideoDrop exists in /Applications. Nothing was replaced." >&2
    exit 1
  fi
  if [[ -w "$SYSTEM_DIR" ]]; then
    DESTDIR="$SYSTEM_DIR"
  else
    echo "VideoDrop already exists in /Applications, but this account cannot update it." >&2
    echo "Ask an administrator to update the existing app, instead of creating a second copy." >&2
    exit 1
  fi
elif [[ -d "$PERSONAL_DIR/$APP_NAME" ]]; then
  DESTDIR="$PERSONAL_DIR"
elif [[ -w "$SYSTEM_DIR" ]]; then
  DESTDIR="$SYSTEM_DIR"
else
  DESTDIR="$PERSONAL_DIR"
fi
DEST="$DESTDIR/$APP_NAME"
mkdir -p "$DESTDIR"
if [[ -e "$DEST" ]] && [[ "$(bundle_id "$DEST")" != "$EXPECTED_ID" ]]; then
  echo "Another app called VideoDrop exists in $DESTDIR. Nothing was replaced." >&2
  exit 1
fi

# Avoid macOS reactivating an older running instance under the same app name.
if pgrep -x VideoDrop >/dev/null 2>&1; then
  echo "Closing VideoDrop before updating..."
  osascript -e 'tell application id "io.videodrop.downloader" to quit' >/dev/null 2>&1 || true
  for ((i=0; i<20; i++)); do
    if ! pgrep -x VideoDrop >/dev/null 2>&1; then break; fi
    sleep 0.5
  done
  if pgrep -x VideoDrop >/dev/null 2>&1; then
    echo "VideoDrop is still running. Finish any downloads, quit VideoDrop, and rerun this command." >&2
    exit 1
  fi
fi

if [[ -e "$DEST" ]]; then
  mv "$DEST" "$WORK/previous.app"
fi
if ! ditto "$APP" "$DEST" || ! check_tools "$DEST"; then
  rm -rf "$DEST"
  if [[ -d "$WORK/previous.app" ]]; then mv "$WORK/previous.app" "$DEST"; fi
  echo "Installation failed; the previous app (if any) has been restored." >&2
  exit 1
fi

printf 'Installed VideoDrop in %s\n' "$DEST"
# -n starts the exact newly installed app, rather than reusing a different copy.
if ! open -n "$DEST"; then
  echo "VideoDrop is installed, but could not be opened automatically. Open it from $DEST." >&2
  exit 1
fi
printf 'VideoDrop is ready!\n'
