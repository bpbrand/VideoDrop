# VideoDrop

**Save videos and audio from links, without the fuss.**

VideoDrop is a simple native macOS downloader. Paste a link, pick your format and quality, and save the file.

### Download

**[Download VideoDrop for Mac →](https://github.com/bpbrand/VideoDrop/releases/latest)**

Choose **Apple Silicon** (M1/M2/M3/M4/M5) or **Intel**, depending on your Mac.

1. Download the matching `VideoDrop-macOS-…zip` file.
2. Unzip it and drag **VideoDrop.app** into Applications.
3. Open VideoDrop, paste a link, and click **Download**.

The download already contains the tools it needs. No Homebrew, Terminal, or programming tools required.

> **First opening:** VideoDrop isn't notarized by Apple yet. If macOS blocks it, try opening it, then go to **System Settings → Privacy & Security → Open Anyway**. Only do this for a download you trust. [Apple's instructions](https://support.apple.com/en-us/102445).

### Formats

| Video | Audio |
|---|---|
| MP4 and MKV | MP3, M4A and WAV |

Choose the best available quality, or limit video to 4K, 1080p, or 720p. Features include a download queue, progress updates, cancellation, and a custom save folder.

Supports macOS **13 or later** on Apple Silicon and Intel Macs. Supported sites and available qualities vary; some sites may restrict downloading. Save only content you have permission to download.

<details>
<summary>Optional: install from Terminal</summary>

```sh
curl -fsSL https://raw.githubusercontent.com/bpbrand/VideoDrop/main/install.sh | bash
```

Review the [installer script](install.sh) before running it. It downloads the right release for your Mac, checks its SHA-256 checksum, and installs the app to your personal Applications folder.

</details>

### More information

See [Building & releasing](docs/BUILDING.md) for maintainer instructions and [third-party notices](THIRD-PARTY-NOTICES.md) for included components.
