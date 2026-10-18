# Third-party components

Release bundles include three independent command-line executables. Relevant GPL/LGPL license texts accompany the app in `Contents/Resources/Licenses`:

- **yt-dlp**, from https://github.com/yt-dlp/yt-dlp — the source project uses the Unlicense, but the PyInstaller-packaged `yt-dlp_macos` executable also includes third-party GPLv3+ code, so that distributed binary is GPLv3+. See its upstream `THIRD_PARTY_LICENSES.txt` and corresponding release source.
- **FFmpeg**, from https://github.com/vanloctech/ffmpeg-macos — licensed under FFmpeg's LGPL/GPL terms and additional third-party codec licenses. Its build scripts and the matching binary releases are hosted in that repository; FFmpeg upstream source is available at https://ffmpeg.org/download.html. The included build enables GPL components such as x264/x265. Consult the project's LICENSE and build instructions for source and licensing obligations before public redistribution.
- **Deno**, from https://github.com/denoland/deno — MIT licensed; macOS runtime binaries.

These are invoked as separate programs. VideoDrop does not ship a browser extension, request browser cookies, or capture your browsing history.

The release workflow records dependency versions in `scripts/fetch-tools.sh`. Each dependency is downloaded from its upstream release and verified with SHA-256 checksums. Downloaded binaries are bundled in the finished application; they are not part of this source repository.
