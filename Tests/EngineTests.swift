import Foundation

@main
struct EngineTests {
    static func main() {
        var passed = 0
        func expect(_ assertion: @autoclosure () -> Bool, _ message: String) {
            guard assertion() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
            passed += 1
        }
        expect((try? DownloadTaskRunner.checkedLink("https://example.org/v")) == "https://example.org/v", "valid link")
        expect((try? DownloadTaskRunner.checkedLink("HTTP://EXAMPLE.ORG/v")) != nil, "case-insensitive protocol")
        expect((try? DownloadTaskRunner.checkedLink("ftp://example.org/v")) == nil, "reject ftp")
        expect((try? DownloadTaskRunner.checkedLink("file:///Users/me/secret")) == nil, "reject file URL")
        expect((try? DownloadTaskRunner.checkedLink("https://me:password@example.com")) == nil, "reject embedded credentials")
        expect((try? DownloadTaskRunner.checkedLink("http://example.org/a b")) == nil, "reject unencoded whitespace")
        expect((try? DownloadTaskRunner.checkedLink("https://youtube.com/playlist?list=abc")) == nil, "reject full playlist link")
        expect((try? DownloadTaskRunner.checkedLink("")) == nil, "reject empty")
        expect((try? DownloadTaskRunner.checkedLink("javascript:alert(1)")) == nil, "reject scripting scheme")
        let fake = Executables(ytdlp: URL(fileURLWithPath: "/tmp/bin/yt-dlp"), ffmpeg: URL(fileURLWithPath: "/tmp/bin/ffmpeg"), deno: nil)
        let dest = URL(fileURLWithPath: "/tmp/public-tests")
        let url = "https://youtube.com/watch?v=123"
        for f in OutputFormat.allCases {
            let command = DownloadTaskRunner.arguments(link: url, folder: dest, format: f, quality: .fullHD, executables: fake)
            expect(command.suffix(2) == ["--", url], "URL positional terminator \(f)")
            expect(command.contains("--ignore-config"), "ignore outside config \(f)")
            expect(command.contains("--no-plugin-dirs"), "no plugin dirs \(f)")
            expect(command.contains("--no-playlist"), "no playlist \(f)")
            expect(!command.contains("--cookies") && !command.contains("--cookies-from-browser"), "no browser or cookie access \(f)")
            expect(command.contains("--no-overwrites"), "no clobber \(f)")
            expect(command.contains("%(title).170B [%(id)s].%(ext)s"), "filename template \(f)")
            expect(command.contains("temp:/tmp/public-tests/.videodrop-partials"), "standard temp destination \(f)")
            let formatIndex = command.firstIndex(of: "--format")!
            expect(formatIndex + 1 < command.count, "video format exists \(f)")
            expect(command[formatIndex + 1].contains("height<=?1080") != f.isAudio, "resolution constraint for video only \(f)")
            if f.isAudio {
                expect(command.contains("--extract-audio"), "audio extraction \(f)")
            } else {
                expect(command.contains("--remux-video"), "video remux \(f)")
            }
        }
        let parsed = DownloadUpdate.decode("VD_TITLE:\"Test video\"")
        if case .title(let title) = parsed { expect(title == "Test video", "title JSON") }
        else { expect(false, "title event") }
        let saved = DownloadUpdate.decode("VD_FILE:\"/tmp/my movie.mp4\"")
        if case .saved(let file) = saved { expect(file.path == "/tmp/my movie.mp4", "saved JSON") }
        else { expect(false, "saved event") }
        print("PASS: \(passed) core tests")
    }
}
