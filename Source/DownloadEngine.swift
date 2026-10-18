// VideoDrop — audio and video download engine.
import Foundation

struct VideoDropError: LocalizedError {
    let detail: String
    var errorDescription: String? { detail }
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case mp4 = "MP4 video"
    case mkv = "MKV video"
    case mp3 = "MP3 audio"
    case m4a = "M4A audio"
    case wav = "WAV audio"
    var id: String { rawValue }
    var isAudio: Bool { self == .mp3 || self == .m4a || self == .wav }
    var description: String {
        switch self {
        case .mp4: return "Compatible video"
        case .mkv: return "Flexible video format"
        case .mp3: return "Universal audio"
        case .m4a: return "Efficient audio"
        case .wav: return "Uncompressed audio"
        }
    }
}

enum VideoQuality: String, CaseIterable, Identifiable {
    case best = "Best available"
    case ultra = "Up to 4K"
    case fullHD = "Up to 1080p"
    case hd = "Up to 720p"
    var id: String { rawValue }
    var restriction: String {
        switch self {
        case .best: return ""
        case .ultra: return "[height<=?2160]"
        case .fullHD: return "[height<=?1080]"
        case .hd: return "[height<=?720]"
        }
    }
}

struct Executables {
    let ytdlp: URL
    let ffmpeg: URL
    let deno: URL?

    private static func find(_ name: String) -> URL? {
        var directories = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin"]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            directories.append(contentsOf: path.split(separator: ":").map(String.init))
        }
        for directory in directories {
            let target = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: target.path) { return target }
        }
        return nil
    }
    // Prefer the download components packaged with the app. No Homebrew or
    // command-line setup is required for released builds.
    static func locate() throws -> Executables {
        let tools = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/tools", isDirectory: true)
        let bundledYtdlp = tools.appendingPathComponent("yt-dlp")
        let bundledFFmpeg = tools.appendingPathComponent("ffmpeg")
        let bundledDeno = tools.appendingPathComponent("deno")
        let fm = FileManager.default
        let packaged = fm.fileExists(atPath: bundledYtdlp.path) ||
                       fm.fileExists(atPath: bundledFFmpeg.path)
        if packaged {
            guard fm.isExecutableFile(atPath: bundledYtdlp.path),
                  fm.isExecutableFile(atPath: bundledFFmpeg.path),
                  fm.isExecutableFile(atPath: bundledDeno.path) else {
                throw VideoDropError(detail: "VideoDrop's download tools are incomplete. Reinstall VideoDrop from the official download page.")
            }
            return Executables(ytdlp: bundledYtdlp, ffmpeg: bundledFFmpeg, deno: bundledDeno)
        }
        // Source builds can use tools already installed on a developer's Mac.
        guard let ytdlp = find("yt-dlp"), let ffmpeg = find("ffmpeg") else {
            throw VideoDropError(detail: "Download tools are missing. Install VideoDrop from its GitHub release page.")
        }
        return Executables(ytdlp: ytdlp, ffmpeg: ffmpeg, deno: find("deno"))
    }
}

enum DownloadUpdate {
    case title(String)
    case progress(Double?, String)
    case saved(URL)
    case raw(String)

    static func decode(_ message: String) -> DownloadUpdate {
        func json(_ prefix: String) -> Any? {
            guard message.hasPrefix(prefix), let data = String(message.dropFirst(prefix.count)).data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        }
        if let name = json("VD_TITLE:") as? String { return .title(name) }
        if let path = json("VD_FILE:") as? String { return .saved(URL(fileURLWithPath: path)) }
        if let p = json("VD_PROGRESS:") as? [String: Any] {
            let current = (p["downloaded_bytes"] as? NSNumber)?.doubleValue ?? 0
            let total = (p["total_bytes"] as? NSNumber)?.doubleValue ?? (p["total_bytes_estimate"] as? NSNumber)?.doubleValue ?? 0
            let ratio: Double? = total > 0 ? min(1, max(0, current / total)) : nil
            if p["status"] as? String == "finished" { return .progress(nil, "Finishing the file…") }
            var description = ByteCountFormatter.string(fromByteCount: Int64(current), countStyle: .file)
            if let speed = p["speed"] as? NSNumber, speed.doubleValue > 0 {
                description += " · " + ByteCountFormatter.string(fromByteCount: speed.int64Value, countStyle: .file) + "/s"
            }
            if let remaining = p["eta"] as? NSNumber, remaining.intValue > 0 {
                description += " · \(remaining.intValue)s left"
            }
            return .progress(ratio, description)
        }
        if message.hasPrefix("VD_POST:") { return .progress(nil, "Combining audio and video…") }
        return .raw(message)
    }
}

struct DownloadOutcome {
    let file: URL?
    let cancelled: Bool
    let failure: String?
}

final class DownloadTaskRunner {
    private let lock = NSLock()
    private var process: Process?
    private var stopped = false

    static func checkedLink(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: { $0.isWhitespace }),
              let parts = URLComponents(string: trimmed),
              ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty,
              parts.user == nil && parts.password == nil else {
            throw VideoDropError(detail: "Paste a video or audio link starting with https:// or http://.")
        }
        if (host == "youtube.com" || host.hasSuffix(".youtube.com")) && parts.path == "/playlist" {
            throw VideoDropError(detail: "Paste the link to one video instead of a full playlist.")
        }
        return trimmed
    }

    static func arguments(link: String, folder: URL, format: OutputFormat,
                          quality: VideoQuality, executables: Executables) -> [String] {
        let formatSpec: String
        if format.isAudio {
            formatSpec = "bestaudio/best"
        } else if format == .mp4 {
            // Prefer H.264/AAC or MP4 streams for broad player compatibility.
            let cap = quality.restriction
            formatSpec = "bv*[ext=mp4]\(cap)+ba[ext=m4a]/b[ext=mp4]\(cap)/bv*\(cap)+ba/b\(cap)"
        } else {
            let cap = quality.restriction
            formatSpec = "bv*\(cap)+ba/b\(cap)"
        }
        var arguments = [
            "--ignore-config", "--no-plugin-dirs", "--no-playlist", "--playlist-items", "1",
            "--no-simulate", "--newline", "--no-colors", "--progress", "--progress-delta", "0.5",
            "--socket-timeout", "30", "--retries", "3", "--fragment-retries", "3",
            "--no-overwrites", "--no-mtime", "--match-filter", "!is_live",
            "--ffmpeg-location", executables.ffmpeg.deletingLastPathComponent().path,
            "--format", formatSpec,
            "--trim-filenames", "170",
            "--paths", folder.path,
            "--paths", "temp:\(folder.appendingPathComponent(".videodrop-partials", isDirectory: true).path)",
            "--output", "%(title).170B [%(id)s].%(ext)s",
            "--print", "before_dl:VD_TITLE:%(title)j",
            "--print", "after_move:VD_FILE:%(filepath)j",
            "--progress-template", "download:VD_PROGRESS:%(progress)j",
            "--progress-template", "postprocess:VD_POST:%(progress.status)s"
        ]
        if let deno = executables.deno {
            arguments += ["--js-runtimes", "deno:\(deno.path)"]
        }
        if format == .mp4 {
            arguments += ["--format-sort", "res,vcodec:h264,acodec:aac"]
        }
        switch format {
        case .mp4: arguments += ["--merge-output-format", "mp4", "--remux-video", "mp4"]
        case .mkv: arguments += ["--merge-output-format", "mkv", "--remux-video", "mkv"]
        case .mp3: arguments += ["--extract-audio", "--audio-format", "mp3", "--audio-quality", "0"]
        case .m4a: arguments += ["--extract-audio", "--audio-format", "m4a", "--audio-quality", "0"]
        case .wav: arguments += ["--extract-audio", "--audio-format", "wav"]
        }
        arguments += ["--", link] // Never interpret a URL as a command-line flag.
        return arguments
    }

    func cancel() {
        lock.lock()
        stopped = true
        let current = process
        lock.unlock()
        if let current = current, current.isRunning { current.terminate() }
    }

    func run(link: String, folder: URL, format: OutputFormat, quality: VideoQuality,
             event: @escaping (DownloadUpdate) -> Void) -> DownloadOutcome {
        do {
            let link = try Self.checkedLink(link)
            let tools = try Executables.locate()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            guard FileManager.default.isWritableFile(atPath: folder.path) else {
                throw VideoDropError(detail: "VideoDrop can't write to that folder. Choose another one.")
            }
            let task = Process()
            task.executableURL = tools.ytdlp
            task.arguments = Self.arguments(link: link, folder: folder, format: format,
                                             quality: quality, executables: tools)
            var environment = ProcessInfo.processInfo.environment
            let dependencyDirectories = [tools.ytdlp, tools.ffmpeg] + (tools.deno.map { [$0] } ?? [])
            environment["PATH"] = dependencyDirectories.map { $0.deletingLastPathComponent().path }.joined(separator: ":") + ":/usr/bin:/bin:/usr/sbin:/sbin"
            environment["PYTHONUNBUFFERED"] = "1"
            task.environment = environment
            task.standardInput = FileHandle.nullDevice
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            lock.lock()
            if stopped { lock.unlock(); return DownloadOutcome(file: nil, cancelled: true, failure: nil) }
            process = task
            do { try task.run() } catch { process = nil; lock.unlock(); throw error }
            lock.unlock()
            pipe.fileHandleForWriting.closeFile()

            var buffer = Data()
            var output: URL?
            var errors: [String] = []
            func processLine(_ bytes: Data) {
                let line = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .newlines)
                guard !line.isEmpty else { return }
                let decoded = DownloadUpdate.decode(line)
                if case .saved(let url) = decoded { output = url }
                if line.contains("ERROR:") { errors.append(line); errors = Array(errors.suffix(3)) }
                event(decoded)
            }
            while true {
                let data = pipe.fileHandleForReading.availableData
                if data.isEmpty { break }
                buffer.append(data)
                while let index = buffer.firstIndex(of: 10) {
                    processLine(Data(buffer[..<index]))
                    buffer.removeSubrange(...index)
                }
                if buffer.count > 1_048_576 { processLine(buffer); buffer.removeAll(keepingCapacity: true) }
            }
            if !buffer.isEmpty { processLine(buffer) }
            pipe.fileHandleForReading.closeFile()
            task.waitUntilExit()
            lock.lock(); let wasCancelled = stopped; process = nil; lock.unlock()
            if wasCancelled { return DownloadOutcome(file: nil, cancelled: true, failure: nil) }
            if task.terminationStatus != 0 {
                return DownloadOutcome(file: nil, cancelled: false,
                                       failure: errors.last ?? "This link couldn't be downloaded. It may be unavailable or unsupported. Try another link or update yt-dlp.")
            }
            guard let file = output, FileManager.default.fileExists(atPath: file.path) else {
                return DownloadOutcome(file: nil, cancelled: false,
                                       failure: "Download finished but no output file was reported. See Details for more information.")
            }
            return DownloadOutcome(file: file, cancelled: false, failure: nil)
        } catch {
            return DownloadOutcome(file: nil, cancelled: false, failure: error.localizedDescription)
        }
    }
}
