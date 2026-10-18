// VideoDrop — a native macOS audio and video downloader.
import AppKit
import SwiftUI

private let accent = Color(red: 0.49, green: 0.91, blue: 0.77)
private let pale = Color(red: 0.68, green: 0.76, blue: 0.77)
private let ink = Color(red: 0.08, green: 0.12, blue: 0.14)

enum DownloadState: String { case waiting, running, done, failed, cancelled }

struct DownloadItem: Identifiable {
    let id = UUID()
    let link: String
    let outputDirectory: URL
    let format: OutputFormat
    let quality: VideoQuality
    var title: String
    var state: DownloadState = .waiting
    var file: URL?
    var error: String?
}

final class DownloadModel: ObservableObject {
    @Published var link = ""
    @Published var format: OutputFormat = OutputFormat(rawValue: UserDefaults.standard.string(forKey: "videodrop-format") ?? "") ?? .mp4 {
        didSet { UserDefaults.standard.set(format.rawValue, forKey: "videodrop-format") }
    }
    @Published var quality: VideoQuality = VideoQuality(rawValue: UserDefaults.standard.string(forKey: "videodrop-quality") ?? "") ?? .best {
        didSet { UserDefaults.standard.set(quality.rawValue, forKey: "videodrop-quality") }
    }
    @Published var folder: URL
    @Published var items: [DownloadItem] = []
    @Published var paused = false
    @Published var busy = false
    @Published var status = "Paste a video or audio link to get started."
    @Published var hasError = false
    @Published var progress: Double? = nil
    @Published var progressLabel = ""
    @Published var detailLog = ""

    private var runner: DownloadTaskRunner?
    private var currentID: UUID?
    var activeItem: DownloadItem? { items.first { $0.id == currentID } }
    var pendingCount: Int { items.filter { $0.state == .waiting }.count }
    var isAudio: Bool { format.isAudio }

    init() {
        if let directory = UserDefaults.standard.string(forKey: "videodrop-save-directory") {
            folder = URL(fileURLWithPath: directory, isDirectory: true)
        } else {
            folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        }
    }

    func paste() {
        if let value = NSPasteboard.general.string(forType: .string) {
            link = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func chooseFolder() {
        let dialog = NSOpenPanel()
        dialog.canChooseDirectories = true
        dialog.canChooseFiles = false
        dialog.canCreateDirectories = true
        dialog.directoryURL = folder
        dialog.prompt = "Save here"
        guard dialog.runModal() == .OK, let choice = dialog.url else { return }
        folder = choice
        UserDefaults.standard.set(choice.path, forKey: "videodrop-save-directory")
    }

    func add() {
        do {
            let valid = try DownloadTaskRunner.checkedLink(link)
            if items.contains(where: { $0.link == valid && [.waiting, .running].contains($0.state) }) {
                hasError = false; status = "That link is already in the queue."
                return
            }
            let host = URLComponents(string: valid)?.host ?? "Video link"
            let item = DownloadItem(link: valid, outputDirectory: folder, format: format,
                                    quality: quality, title: host)
            items.append(item)
            link = ""
            hasError = false
            status = "Added to queue · \(item.format.rawValue)"
            next()
        } catch {
            hasError = true
            status = error.localizedDescription
        }
    }

    func cancelCurrent() {
        status = "Cancelling download…"
        runner?.cancel()
    }

    func remove(_ id: UUID) {
        guard currentID != id else { return }
        items.removeAll { $0.id == id }
    }

    func clearFinished() {
        items.removeAll { $0.state == .done || $0.state == .cancelled }
    }

    func retry(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard items[index].state == .failed || items[index].state == .cancelled else { return }
        items[index].state = .waiting
        items[index].error = nil
        next()
    }

    func togglePause() {
        paused.toggle()
        status = paused ? "Queue paused after the current download." : "Queue resumed."
        if !paused { next() }
    }

    func openFolder() { NSWorkspace.shared.open(folder) }

    func showFile(_ item: DownloadItem) {
        if let file = item.file {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        }
    }

    private func next() {
        guard !busy && !paused, let i = items.firstIndex(where: { $0.state == .waiting }) else { return }
        let selection = items[i]
        let id = selection.id
        let job = DownloadTaskRunner()
        runner = job
        currentID = id
        busy = true
        hasError = false
        progress = nil
        progressLabel = "Connecting…"
        detailLog = ""
        items[i].state = .running
        status = "Finding \(selection.format.isAudio ? "audio" : "video")…"

        DispatchQueue.global(qos: .userInitiated).async {
            let result = job.run(link: selection.link, folder: selection.outputDirectory,
                                 format: selection.format, quality: selection.quality) { update in
                DispatchQueue.main.async {
                    guard self.currentID == id else { return }
                    switch update {
                    case .title(let title):
                        if let index = self.items.firstIndex(where: { $0.id == id }) {
                            self.items[index].title = title
                        }
                        self.status = "Downloading \(title)"
                    case .progress(let fraction, let label):
                        self.progress = fraction
                        self.progressLabel = label
                    case .saved: break
                    case .raw(let message):
                        let safe = String(message.prefix(600))
                        self.detailLog += safe + "\n"
                        if self.detailLog.count > 18_000 {
                            self.detailLog = String(self.detailLog.suffix(16_000))
                        }
                    }
                }
            }
            DispatchQueue.main.async {
                guard let index = self.items.firstIndex(where: { $0.id == id }) else { return }
                if result.cancelled {
                    self.items[index].state = .cancelled
                    self.status = "Download cancelled."
                } else if let failure = result.failure {
                    self.items[index].state = .failed
                    self.items[index].error = failure
                    self.status = failure
                    self.hasError = true
                } else {
                    self.items[index].state = .done
                    self.items[index].file = result.file
                    self.status = "Saved to \(selection.outputDirectory.lastPathComponent)."
                    self.hasError = false
                }
                self.busy = false
                self.currentID = nil
                self.runner = nil
                self.progress = nil
                self.progressLabel = ""
                self.next()
            }
        }
    }
}

private struct SoftCard<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 13) { content }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

struct DownloaderView: View {
    @ObservedObject var model: DownloadModel
    @State private var showDetails = false

    private var buttonBackground: Color { accent }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "arrow.down.to.line.compact")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(ink)
                        .frame(width: 49, height: 49)
                        .background(accent, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("VideoDrop").font(.system(size: 29, weight: .bold, design: .rounded))
                        Text("A straightforward way to save videos and audio.")
                            .font(.system(size: 12)).foregroundStyle(pale)
                    }
                    Spacer()
                }.padding(.bottom, 5)

                SoftCard {
                    HStack {
                        smallHeading("PASTE A LINK")
                        Spacer()
                        Text("Video or audio").font(.system(size: 11)).foregroundStyle(pale)
                    }
                    HStack(spacing: 9) {
                        TextField("https://www.youtube.com/watch?v=…", text: $model.link)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(13)
                            .background(ink.opacity(0.7), in: RoundedRectangle(cornerRadius: 9))
                            .onSubmit(model.add)
                        Button(action: model.paste) {
                            Label("Paste", systemImage: "doc.on.clipboard")
                        }.buttonStyle(.bordered)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("FILE FORMAT").font(.system(size: 10, weight: .bold)).tracking(1.0).foregroundStyle(pale)
                            Picker("Format", selection: $model.format) {
                                ForEach(OutputFormat.allCases) { format in
                                    Text(format.rawValue).tag(format)
                                }
                            }.labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                            Text(model.format.description).font(.system(size: 10)).foregroundStyle(pale)
                        }.frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 7) {
                            Text("VIDEO QUALITY").font(.system(size: 10, weight: .bold)).tracking(1.0).foregroundStyle(pale)
                            Picker("Quality", selection: $model.quality) {
                                ForEach(VideoQuality.allCases) { quality in
                                    Text(quality.rawValue).tag(quality)
                                }
                            }.labelsHidden().pickerStyle(.menu).disabled(model.isAudio)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(model.isAudio ? "Best available source audio" : "Highest quality up to your limit")
                                .font(.system(size: 10)).foregroundStyle(pale)
                        }.frame(maxWidth: .infinity)
                    }
                    HStack(spacing: 9) {
                        Image(systemName: "folder").foregroundStyle(accent)
                        Text(model.folder.path)
                            .font(.system(size: 11)).lineLimit(1).truncationMode(.middle).foregroundStyle(pale)
                        Spacer(minLength: 6)
                        Button("Choose folder…", action: model.chooseFolder).buttonStyle(.bordered)
                    }
                    Button(action: model.add) {
                        HStack(spacing: 9) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Download")
                        }.font(.system(size: 13, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 7)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(buttonBackground)
                    .foregroundStyle(ink)
                    .disabled(model.link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                SoftCard {
                    HStack {
                        smallHeading("DOWNLOAD QUEUE")
                        Text("\(model.pendingCount) waiting").font(.system(size: 10)).foregroundStyle(pale)
                        Spacer()
                        Button(model.paused ? "Resume" : "Pause", action: model.togglePause)
                            .font(.system(size: 11)).disabled(!model.busy && model.pendingCount == 0)
                        Button("Clear completed", action: model.clearFinished)
                            .font(.system(size: 11))
                    }
                    if model.items.isEmpty {
                        HStack(spacing: 9) {
                            Image(systemName: "tray").font(.system(size: 22)).foregroundStyle(pale.opacity(0.6))
                            Text("Your downloads will show up here.").font(.system(size: 12)).foregroundStyle(pale)
                        }.frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 17)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 7) {
                                ForEach(model.items) { item in
                                    HStack(spacing: 10) {
                                        Image(systemName: symbol(item.state))
                                            .foregroundStyle(item.state == .failed ? .orange : accent)
                                            .font(.system(size: 15))
                                            .frame(width: 20)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                            Text("\(item.state.rawValue.capitalized) · \(item.format.rawValue) · \(item.outputDirectory.lastPathComponent)")
                                                .font(.system(size: 10)).foregroundStyle(pale).lineLimit(1)
                                            if let message = item.error {
                                                Text(message).font(.system(size: 10)).foregroundStyle(.orange)
                                                    .lineLimit(2).textSelection(.enabled)
                                            }
                                        }
                                        Spacer(minLength: 3)
                                        if item.state == .running {
                                            Button("Cancel", action: model.cancelCurrent).font(.system(size: 11))
                                        } else {
                                            if item.state == .done {
                                                Button("Finder") { model.showFile(item) }.font(.system(size: 11))
                                            }
                                            if item.state == .failed || item.state == .cancelled {
                                                Button("Retry") { model.retry(item.id) }.font(.system(size: 11))
                                            }
                                            Button { model.remove(item.id) } label: { Image(systemName: "xmark") }
                                                .buttonStyle(.plain).foregroundStyle(pale)
                                        }
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                                }
                            }
                        }.frame(maxHeight: 205)
                    }
                }

                SoftCard {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: model.hasError ? "exclamationmark.triangle.fill" : model.busy ? "arrow.down.circle" : "checkmark.circle")
                            .foregroundStyle(model.hasError ? .orange : accent).font(.system(size: 19))
                        Text(model.status).font(.system(size: 12)).foregroundStyle(model.hasError ? .orange : .white)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    if model.busy {
                        if let progress = model.progress {
                            ProgressView(value: progress).tint(accent)
                        } else { ProgressView().progressViewStyle(.linear).tint(accent) }
                        Text(model.progressLabel).font(.system(size: 11)).foregroundStyle(pale)
                    }
                    if showDetails {
                        ScrollView {
                            Text(model.detailLog.isEmpty ? "Download diagnostics will appear here." : model.detailLog)
                                .font(.system(size: 10, design: .monospaced)).foregroundStyle(pale)
                                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        }.frame(height: 100)
                    }
                    HStack {
                        Button(showDetails ? "Hide details" : "Details") { showDetails.toggle() }
                        Spacer()
                        Button("Open downloads folder", action: model.openFolder)
                    }.font(.system(size: 11))
                }

                Text("VideoDrop downloads from supported public sources. Please respect copyright and site terms.")
                    .font(.system(size: 10)).foregroundStyle(pale.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .frame(width: 680, height: 760)
        .background(ink)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }

    private func smallHeading(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .bold)).tracking(1.3).foregroundStyle(pale)
    }
    private func symbol(_ state: DownloadState) -> String {
        switch state {
        case .waiting: return "clock"
        case .running: return "arrow.down.circle.fill"
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }
}

final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    let model = DownloadModel()
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appMenu = NSMenu()
        let appItem = NSMenuItem()
        appMenu.addItem(appItem)
        let sub = NSMenu(title: "VideoDrop")
        appItem.submenu = sub
        sub.addItem(withTitle: "About VideoDrop", action: #selector(showAbout), keyEquivalent: "")
        sub.addItem(.separator())
        sub.addItem(withTitle: "Quit VideoDrop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenuItem(); appMenu.addItem(edit)
        let edits = NSMenu(title: "Edit"); edit.submenu = edits
        edits.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edits.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edits.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edits.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edits.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = appMenu

        let controller = NSHostingController(rootView: DownloaderView(model: model))
        window = NSWindow(contentViewController: controller)
        window.title = "VideoDrop"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 0.08, green: 0.12, blue: 0.14, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "VideoDrop", .applicationVersion: "1.1.0",
            .credits: NSAttributedString(string: "A simple video and audio downloader for macOS.\nPowered by yt-dlp and FFmpeg.")
        ])
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.busy else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "A download is still running"
        alert.informativeText = "Quitting will cancel the current download and discard the queue. Saved files will remain on disk."
        alert.addButton(withTitle: "Keep downloading")
        alert.addButton(withTitle: "Cancel and quit")
        if alert.runModal() == .alertSecondButtonReturn {
            model.cancelCurrent()
            return .terminateNow
        }
        return .terminateCancel
    }
}

@main
struct EntryPoint {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            SelfTest.run()
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = ApplicationDelegate()
        app.delegate = delegate
        app.run()
    }
}

enum SelfTest {
    static func run() {
        func check(_ test: @autoclosure () -> Bool, _ description: String) {
            guard test() else { fputs("FAILED: \(description)\n", stderr); exit(1) }
        }
        check((try? DownloadTaskRunner.checkedLink("https://example.com/watch?id=123")) != nil, "accept public HTTPS")
        check((try? DownloadTaskRunner.checkedLink("file:///etc/passwd")) == nil, "reject local files")
        check((try? DownloadTaskRunner.checkedLink("https://example.com/a b")) == nil, "reject spaces")
        check((try? DownloadTaskRunner.checkedLink("https://user:pass@example.com")) == nil, "reject embedded credentials")
        let tools = Executables(ytdlp: URL(fileURLWithPath: "/usr/bin/true"),
                                ffmpeg: URL(fileURLWithPath: "/usr/bin/true"), deno: nil)
        let output = URL(fileURLWithPath: "/tmp/videodrop-test")
        let args = DownloadTaskRunner.arguments(link: "https://example.com/v", folder: output, format: .mp4,
                                                quality: .fullHD, executables: tools)
        check(args.suffix(2) == ["--", "https://example.com/v"], "link is a positional argument")
        check(args.contains("--no-playlist"), "no playlists")
        check(args.contains("--ignore-config"), "ignore external config")
        check(!args.contains("--cookies"), "no cookie extraction")
        check(!args.contains("--cookies-from-browser"), "no browser access")
        check(!args.contains("--exec"), "no extra commands")
        for file in OutputFormat.allCases {
            let test = DownloadTaskRunner.arguments(link: "https://example.com/v", folder: output,
                                                    format: file, quality: .best, executables: tools)
            check(test.contains("--format"), "has format selection \(file.rawValue)")
        }
        print("VideoDrop: 15 core checks passed")
    }
}
