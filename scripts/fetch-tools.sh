#!/bin/bash
set -euo pipefail

ARCH="${1:-$(uname -m)}"
DEST="${2:-dist/tools}"
case "$ARCH" in
  arm64) DENO_ARCH=aarch64; FFMPEG_ARCH=arm64 ;;
  x86_64) DENO_ARCH=x86_64; FFMPEG_ARCH=x64 ;;
  *) echo "Unsupported CPU architecture: $ARCH" >&2; exit 1 ;;
esac

# Pinned releases so each build uses an explicitly reviewed dependency version.
YTDLP_VERSION=2026.08.19
DENO_VERSION=v2.9.6
FFMPEG_VERSION=ffmpeg-2026.06.11

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"

fetch() { curl -fLSs --retry 3 --connect-timeout 20 "$1" -o "$2"; }
verify() {
  local actual="$1" checksum_file="$2" expected
  expected="$(head -n 1 "$checksum_file" | awk '{print $1}')"
  if [[ ! "$expected" =~ ^[a-fA-F0-9]{64}$ ]]; then
    echo "Invalid checksum provided for $actual" >&2; exit 1
  fi
  printf '%s  %s\n' "$expected" "$actual" | shasum -a 256 -c -
}

echo 'Fetching yt-dlp…'
ytdlp_base="https://github.com/yt-dlp/yt-dlp/releases/download/$YTDLP_VERSION"
fetch "$ytdlp_base/yt-dlp_macos" "$WORK/yt-dlp"
fetch "$ytdlp_base/SHA2-256SUMS" "$WORK/SHA2-256SUMS"
expected="$(awk '($2 == "yt-dlp_macos" || $2 == "*yt-dlp_macos") {print $1; exit}' "$WORK/SHA2-256SUMS")"
if [[ ! "$expected" =~ ^[a-fA-F0-9]{64}$ ]]; then
  echo "Unable to find the yt-dlp_macos checksum." >&2; exit 1
fi
printf '%s  %s\n' "$expected" "$WORK/yt-dlp" | shasum -a 256 -c -
cp "$WORK/yt-dlp" "$DEST/yt-dlp"

echo 'Fetching Deno…'
deno_file="deno-${DENO_ARCH}-apple-darwin.zip"
deno_base="https://github.com/denoland/deno/releases/download/$DENO_VERSION/$deno_file"
fetch "$deno_base" "$WORK/$deno_file"
fetch "${deno_base}.sha256sum" "$WORK/${deno_file}.sha256sum"
verify "$WORK/$deno_file" "$WORK/${deno_file}.sha256sum"
mkdir -p "$WORK/deno"
unzip -q "$WORK/$deno_file" -d "$WORK/deno"
cp "$WORK/deno/deno" "$DEST/deno"

echo 'Fetching FFmpeg…'
ffmpeg_file="ffmpeg-macos-${FFMPEG_ARCH}.tar.gz"
ffmpeg_base="https://github.com/vanloctech/ffmpeg-macos/releases/download/${FFMPEG_VERSION}/$ffmpeg_file"
fetch "$ffmpeg_base" "$WORK/$ffmpeg_file"
fetch "${ffmpeg_base}.sha256" "$WORK/${ffmpeg_file}.sha256"
verify "$WORK/$ffmpeg_file" "$WORK/${ffmpeg_file}.sha256"
mkdir -p "$WORK/ffmpeg"
tar -xzf "$WORK/$ffmpeg_file" -C "$WORK/ffmpeg"
for executable in ffmpeg ffprobe; do
  tool="$(find "$WORK/ffmpeg" -type f -name "$executable" -print -quit)"
  if [[ -z "$tool" ]]; then echo "$executable not present in FFmpeg archive" >&2; exit 1; fi
  cp "$tool" "$DEST/$executable"
done

chmod 755 "$DEST"/*
for executable in yt-dlp ffmpeg ffprobe deno; do
  "$DEST/$executable" -version 2>/dev/null | head -n 1 || true
  test -x "$DEST/$executable" || exit 1
done
