# Building and releasing VideoDrop

This repository contains the SwiftUI application source and GitHub Actions build workflow. Public releases include `VideoDrop.app` and the download tools it needs.

## Test a build

Open **Actions → Build VideoDrop → Run workflow**. GitHub builds Apple Silicon and Intel versions. Download the generated artifacts from the successful workflow run and test both on Macs if possible.

## Publish a version

1. Commit the source files and workflow to the repository's `main` branch. Make sure you upload the `.github/workflows` directory, not just a ZIP file.
2. Run the workflow manually once and inspect the results.
3. Create a new GitHub Release with a NEW tag (for this version, `v1.1.0`). Publish it.
4. The release workflow builds both apps, uploads checksummed ZIP files, and attaches them to that release automatically. Give the workflow a few minutes and refresh the release page.
5. Test a downloaded file from the actual release on a Mac before sending the download link to friends.

## Local development (macOS 13+)

Run `bash scripts/build-macos.sh` on a Mac with Xcode command-line tools to compile the app. By default it creates an app in `dist/` without fetching bundled download components. For a complete distributable bundle use:

```sh
bash scripts/fetch-tools.sh "$(uname -m)" dist/tools
bash scripts/build-macos.sh dist/tools
```

The build script performs smoke tests on the compiled app. Development-only local builds need `yt-dlp`, FFmpeg, and Deno to download if the tools aren't bundled.

## Code signing and macOS security

The workflow uses **ad-hoc signing**, not an Apple Developer ID. This verifies bundle integrity locally but DOES NOT make the app notarized or bypass macOS Gatekeeper. For unrestricted first launch you must enroll in Apple's Developer Program, sign the nested command-line tools and app with Developer ID, notarize the ZIP/DMG, and test on a clean Mac. Do not advise users to disable Gatekeeper globally. See [Apple's guidance](https://support.apple.com/en-us/102445).

## Maintenance

- Bump the app version in `scripts/build-macos.sh` and in the About panel in `Source/VideoDrop.swift` when releasing.
- Review `scripts/fetch-tools.sh` dependency tags/checksums and applicable GPL/FFmpeg redistribution requirements (including corresponding source and license texts) before making releases public.
- Run engine tests (`swiftc -parse-as-library Source/DownloadEngine.swift Tests/EngineTests.swift -o /tmp/vd-tests && /tmp/vd-tests`) and the workflow on both architectures.
- Don't add generated `.app` binaries to the source repository; release them as GitHub Release assets.
