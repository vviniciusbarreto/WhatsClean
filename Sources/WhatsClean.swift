import SwiftUI
import AppKit
import Quartz
import AVFoundation
import ImageIO
import os.log
import Sparkle

private let appLogger = Logger(subsystem: "com.vviniciusbarreto.whatsclean", category: "lifecycle")

enum MediaCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case images = "Images"
    case videos = "Videos"
    case audio = "Audio"
    case docs = "Documents"
    var id: String { self.rawValue }
    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .images: return "photo"
        case .videos: return "video"
        case .audio: return "waveform"
        case .docs: return "doc.text"
        }
    }
}

struct MediaItem: Identifiable, Hashable, Sendable {
    let id: String
    let url: URL
    let name: String
    let category: MediaCategory
    let ext: String
    let size: Int64
    let date: Date

    var sizeFormatted: String {
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useAll]
        bcf.countStyle = .file
        return bcf.string(fromByteCount: size)
    }

    var dateFormatted: String {
        let df = DateFormatter()
        df.dateFormat = "dd/MM/yyyy HH:mm:ss"
        return df.string(from: date)
    }

    var isOlderThan7Days: Bool {
        return date < Date().addingTimeInterval(-7 * 86400)
    }
}

final class QuickLookManager: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookManager()
    var currentURL: URL?

    func preview(url: URL) {
        self.currentURL = url
        DispatchQueue.main.async {
            if let panel = QLPreviewPanel.shared() {
                panel.dataSource = self
                panel.delegate = self
                panel.reloadData()
                panel.makeKeyAndOrderFront(nil)
            } else {
                Process.launchedProcess(launchPath: "/usr/bin/qlmanage", arguments: ["-p", url.path])
            }
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return currentURL != nil ? 1 : 0
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        return (currentURL as NSURL?) ?? NSURL()
    }
}

final class AutoCleanerManager: ObservableObject {
    @Published var isEnabled: Bool = false
    @Published var feedbackMessage: String?

    private let plistURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.vviniciusbarreto.whatsclean.autoclean.plist")
    }()

    private var executablePath: String {
        let candidates = [
            "/Applications/WhatsClean.app/Contents/MacOS/WhatsClean",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/WhatsClean.app/Contents/MacOS/WhatsClean").path,
            Bundle.main.executablePath ?? ""
        ]
        for c in candidates where FileManager.default.fileExists(atPath: c) {
            return c
        }
        return candidates[0]
    }

    init() {
        checkStatus()
    }

    func checkStatus() {
        self.isEnabled = FileManager.default.fileExists(atPath: plistURL.path)
    }

    func enable() {
        let exe = executablePath
        let applications = ["/Applications/", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path + "/"]
        guard applications.contains(where: { exe.hasPrefix($0) }) else {
            feedbackMessage = "Install WhatsClean in the Applications folder before enabling automatic cleanup."
            isEnabled = false
            return
        }

        let plist: [String: Any] = [
            "Label": "com.vviniciusbarreto.whatsclean.autoclean",
            "ProgramArguments": [exe, "--clean-7days"],
            "StartInterval": 86400
        ]
        do {
            try FileManager.default.createDirectory(
                at: plistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
            let status = runLaunchctl(["load", "-w", plistURL.path])
            guard status == 0 else {
                try? FileManager.default.removeItem(at: plistURL)
                throw NSError(domain: "WhatsClean", code: Int(status), userInfo: [
                    NSLocalizedDescriptionKey: "macOS refused to schedule automatic cleanup."
                ])
            }
            isEnabled = true
            feedbackMessage = "Daily automatic cleanup is enabled."
        } catch {
            isEnabled = false
            feedbackMessage = "Automatic cleanup could not be enabled: \(error.localizedDescription)"
        }
    }

    func disable() {
        _ = runLaunchctl(["unload", plistURL.path])
        try? FileManager.default.removeItem(at: plistURL)
        self.isEnabled = false
        feedbackMessage = "Automatic cleanup is disabled."
    }

    private func runLaunchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}

final class ThumbnailCache {
    static let shared: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 500
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()
}

struct AsyncThumbnailView: View {
    let item: MediaItem
    @State private var thumbnail: NSImage? = nil

    var body: some View {
        Group {
            if let img = thumbnail {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12), lineWidth: 1))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(categoryColor.opacity(0.15))
                    Image(systemName: item.category.icon)
                        .font(.system(size: 15))
                        .foregroundColor(categoryColor)
                }
                .frame(width: 36, height: 36)
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }

    private var categoryColor: Color {
        switch item.category {
        case .images: return .blue
        case .videos: return .purple
        case .audio: return .orange
        case .docs: return .red
        default: return .gray
        }
    }

    private func loadThumbnail() {
        let key = item.id as NSString
        if let cached = ThumbnailCache.shared.object(forKey: key) {
            self.thumbnail = cached
            return
        }

        let url = item.url
        if item.category == .images || item.ext == "JPG" || item.ext == "PNG" || item.ext == "GIF" {
            DispatchQueue.global(qos: .utility).async {
                let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
                let thumbnailOptions = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 72,
                    kCGImageSourceShouldCacheImmediately: true
                ] as CFDictionary
                if let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
                   let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) {
                    let img = NSImage(cgImage: cgImage, size: NSSize(width: 36, height: 36))
                    ThumbnailCache.shared.setObject(img, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
                    DispatchQueue.main.async { self.thumbnail = img }
                }
            }
        } else if item.category == .videos {
            DispatchQueue.global(qos: .utility).async {
                let asset = AVURLAsset(url: url)
                let gen = AVAssetImageGenerator(asset: asset)
                gen.appliesPreferredTrackTransform = true
                gen.maximumSize = CGSize(width: 72, height: 72)
                let time = CMTime(seconds: 0.5, preferredTimescale: 60)
                if let cgImage = try? gen.copyCGImage(at: time, actualTime: nil) {
                    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 36, height: 36))
                    ThumbnailCache.shared.setObject(nsImage, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
                    DispatchQueue.main.async { self.thumbnail = nsImage }
                }
            }
        }
    }
}

@MainActor
class MediaScanner: ObservableObject {
    @Published var items: [MediaItem] = []
    @Published var totalSizeString: String = "0 B"
    @Published var olderThan7DaysCount: Int = 0
    @Published var olderThan7DaysSizeString: String = "0 B"
    @Published var isScanning = false
    @Published var statusMessage: String?

    struct ScanResult: Sendable {
        let items: [MediaItem]
        let totalBytes: Int64
        let oldBytes: Int64
        let oldCount: Int
        let rootsFound: Int
        let inaccessibleRoots: Int
    }

    nonisolated private static func getMediaRoots() -> [URL] {
#if QA_TESTING
        if let testRoot = ProcessInfo.processInfo.environment["WHATSCLEAN_QA_MEDIA_ROOT"] {
            return [URL(fileURLWithPath: testRoot, isDirectory: true)]
        }
#endif
        let home = FileManager.default.homeDirectoryForCurrentUser
        let specificDirs: [URL] = [
            home.appendingPathComponent("Library/Group Containers/group.net.whatsapp.WhatsApp.shared/Message/Media"),
            home.appendingPathComponent("Library/Group Containers/group.net.whatsapp.WhatsAppSMB.shared/Message/Media"),
            home.appendingPathComponent("Library/Application Support/WhatsApp/Message/Media"),
            home.appendingPathComponent("Library/Application Support/WhatsApp Web")
        ]

        return specificDirs.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    nonisolated static func scanSynchronously() -> ScanResult {
        let roots = getMediaRoots()
        var scanned: [MediaItem] = []
        var seenFiles = Set<String>()
        var totalBytes: Int64 = 0
        var oldBytes: Int64 = 0
        var oldCount: Int = 0
        var inaccessibleRoots = 0

        let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "svg", "psd", "ai", "heic", "webp", "bmp", "tiff"]
        let videoExts: Set<String> = ["mp4", "mov", "m4v", "mkv", "avi", "webm"]
        let audioExts: Set<String> = ["opus", "mp3", "m4a", "wav", "flac", "ogg", "aac", "wma"]
        let docExts: Set<String> = ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "zip", "rar", "7z", "tar", "gz", "csv"]
        let excludedDirs = ["avatars", "stickers", "profile", "profilepictures", "frameworks", "codesignature"]

        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]

        for root in roots {
            guard FileManager.default.isReadableFile(atPath: root.path),
                  let enumerator = FileManager.default.enumerator(
                    at: root,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                  ) else {
                inaccessibleRoots += 1
                continue
            }

            while let fileURL = enumerator.nextObject() as? URL {
                let pathLower = fileURL.path.lowercased()
                if excludedDirs.contains(where: { pathLower.contains($0) }) { continue }

                guard let res = try? fileURL.resourceValues(forKeys: Set(keys)),
                      res.isRegularFile == true,
                      let size = res.fileSize,
                      let date = res.contentModificationDate,
                      size > 50 else { continue }

                if seenFiles.contains(fileURL.path) { continue }
                seenFiles.insert(fileURL.path)

                let ext = fileURL.pathExtension.lowercased()
                var cat: MediaCategory? = nil
                var fmt = ext.uppercased()

                if imageExts.contains(ext) { cat = .images }
                else if videoExts.contains(ext) { cat = .videos }
                else if audioExts.contains(ext) { cat = .audio }
                else if docExts.contains(ext) { cat = .docs }
                else if ext == "thumb" || ext.isEmpty {
                    if let handle = try? FileHandle(forReadingFrom: fileURL) {
                        let header = handle.readData(ofLength: 16)
                        try? handle.close()
                        if header.starts(with: [0xFF, 0xD8, 0xFF]) { cat = .images; fmt = "JPG" }
                        else if header.starts(with: [0x89, 0x50, 0x4E, 0x47]) { cat = .images; fmt = "PNG" }
                        else if header.starts(with: [0x47, 0x49, 0x46, 0x38]) { cat = .images; fmt = "GIF" }
                        else if header.count >= 8 && Array(header[4..<8]) == [0x66, 0x74, 0x79, 0x70] { cat = .videos; fmt = "MP4" }
                        else if header.starts(with: [0x4F, 0x67, 0x67, 0x53]) { cat = .audio; fmt = "OPUS" }
                        else if header.starts(with: [0x25, 0x50, 0x44, 0x46]) { cat = .docs; fmt = "PDF" }
                    }
                }
                guard let validCategory = cat else { continue }
                if fmt == "WEBP" && size < 65536 { continue }

                let isOld = date < Date().addingTimeInterval(-7 * 86400)
                if isOld {
                    oldCount += 1
                    oldBytes += Int64(size)
                }

                scanned.append(MediaItem(
                    id: fileURL.path,
                    url: fileURL,
                    name: fileURL.lastPathComponent,
                    category: validCategory,
                    ext: fmt,
                    size: Int64(size),
                    date: date
                ))
                totalBytes += Int64(size)
            }
        }
        scanned.sort { $0.date > $1.date }
        return ScanResult(
            items: scanned,
            totalBytes: totalBytes,
            oldBytes: oldBytes,
            oldCount: oldCount,
            rootsFound: roots.count,
            inaccessibleRoots: inaccessibleRoots
        )
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            let result = await Task.detached(priority: .utility) {
                MediaScanner.scanSynchronously()
            }.value
            apply(result)
            isScanning = false
        }
    }

    private func apply(_ result: ScanResult) {
        items = result.items
        olderThan7DaysCount = result.oldCount
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useAll]
        bcf.countStyle = .file
        totalSizeString = bcf.string(fromByteCount: result.totalBytes)
        olderThan7DaysSizeString = bcf.string(fromByteCount: result.oldBytes)
        if result.rootsFound == 0 {
            statusMessage = "No WhatsApp media folders were found. Open WhatsApp and download some media before refreshing."
        } else if result.inaccessibleRoots > 0 {
            statusMessage = "macOS blocked access to a WhatsApp folder. Allow WhatsClean in System Settings > Privacy & Security > Full Disk Access."
        } else {
            statusMessage = nil
        }
    }

    @discardableResult
    func deleteOlderThan7Days() -> (deleted: Int, failed: Int) {
        var deleted = 0
        var failed = 0
        for item in items where item.isOlderThan7Days {
            do {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                deleted += 1
            } catch {
                failed += 1
            }
        }
        scan()
        return (deleted, failed)
    }
}

struct ContentView: View {
    @StateObject private var scanner = MediaScanner()
    @StateObject private var autoCleaner = AutoCleanerManager()
    @State private var selectedCategory: MediaCategory = .all
    @State private var searchText: String = ""
    @State private var selectedItems = Set<String>()
    @State private var showDelete7DaysAlert: Bool = false
    @State private var showDeleteSelectedAlert: Bool = false
    @State private var showAutoCleanConfirmation: Bool = false
    @State private var showAutoCleanFeedbackAlert: Bool = false
    @State private var operationMessage: String?

    let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var filteredItems: [MediaItem] {
        scanner.items.filter { item in
            let matchesCategory = (selectedCategory == .all || item.category == selectedCategory)
            let matchesSearch = searchText.isEmpty || item.name.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                Picker("Category", selection: $selectedCategory) {
                    ForEach(MediaCategory.allCases) { cat in
                        Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Category")
                .frame(minWidth: 240, maxWidth: .infinity)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search...", text: $searchText).textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .frame(minWidth: 140, idealWidth: 200, maxWidth: 260)
                }

                HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button(action: {
                    if autoCleaner.isEnabled {
                        autoCleaner.disable()
                        showAutoCleanFeedbackAlert = true
                    } else {
                        showAutoCleanConfirmation = true
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: autoCleaner.isEnabled ? "bolt.shield.fill" : "bolt.shield")
                        Text(autoCleaner.isEnabled ? "Auto (7d): ON" : "Auto (7d)")
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(autoCleaner.isEnabled ? .green : .secondary)
                .help("Automatically clean files older than seven days every 24 hours")

                Button(action: { showDelete7DaysAlert = true }) {
                    HStack(spacing: 5) {
                        Image(systemName: "trash.circle")
                        Text("Clean 7d+ (\(scanner.olderThan7DaysCount))")
                            .lineLimit(1)
                    }
                }
                .foregroundColor(scanner.olderThan7DaysCount > 0 ? .orange : .secondary)
                .disabled(scanner.olderThan7DaysCount == 0)

                Button(action: { scanner.scan() }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh media list")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            Table(filteredItems, selection: $selectedItems) {
                TableColumn("Preview") { item in
                    AsyncThumbnailView(item: item)
                }
                .width(42)

                TableColumn("Name") { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .lineLimit(1)
                            .font(.body.weight(.medium))
                        Text(item.category.rawValue)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .width(min: 220, ideal: 340)

                TableColumn("Format") { item in
                    Text(item.ext)
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(4)
                }
                .width(70)

                TableColumn("Size") { item in
                    Text(item.sizeFormatted)
                        .font(.system(.body, design: .monospaced))
                }
                .width(95)

                TableColumn("Date") { item in
                    Text(item.dateFormatted)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(item.isOlderThan7Days ? .orange : .secondary)
                }
                .width(160)
            }
            .overlay {
                if scanner.isScanning && scanner.items.isEmpty {
                    ProgressView("Scanning media…")
                } else if let message = scanner.statusMessage, scanner.items.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 34))
                            .foregroundColor(.secondary)
                        Text("Media unavailable")
                            .font(.headline)
                        Text(message)
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)
                    }
                    .padding(24)
                }
            }
            .contextMenu {
                Button("Quick Look (Space)") { quickLookSelected() }
                Button("Open with Default App") { openSelected() }
                Button("Show in Finder") { revealSelected() }
                Button("Save to Downloads") { saveSelected() }
                Divider()
                Button("Move to Trash", role: .destructive) { showDeleteSelectedAlert = true }
            }

            Divider()

            VStack(spacing: 8) {
                HStack {
                Text("\(filteredItems.count) file(s) • Total: \(scanner.totalSizeString)")
                    .font(.callout).foregroundColor(.secondary)
                Spacer()
                }

                HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button(action: quickLookSelected) {
                    Label("Quick Look", systemImage: "eye.circle")
                }
                .disabled(selectedItems.isEmpty)
                .keyboardShortcut(.space, modifiers: [])

                Button(action: openSelected) {
                    Label("Open", systemImage: "arrow.up.forward.app")
                }
                .disabled(selectedItems.isEmpty)

                Button(action: revealSelected) {
                    Label("Finder", systemImage: "folder")
                }
                .disabled(selectedItems.isEmpty)

                Button(action: saveSelected) {
                    Label("Save", systemImage: "arrow.down.circle")
                }
                .disabled(selectedItems.isEmpty)

                Button(role: .destructive, action: { showDeleteSelectedAlert = true }) {
                    Label("Move to Trash", systemImage: "trash")
                }
                .disabled(selectedItems.isEmpty)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 680, minHeight: 500)
        .navigationTitle("WhatsClean")
        .alert("Clean media older than seven days?", isPresented: $showDelete7DaysAlert) {
            Button("Move to Trash", role: .destructive) {
                let result = scanner.deleteOlderThan7Days()
                operationMessage = deletionMessage(deleted: result.deleted, failed: result.failed)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Found \(scanner.olderThan7DaysCount) file(s) older than seven days (\(scanner.olderThan7DaysSizeString)). They will be moved to the Trash to free up space.")
        }
        .alert("Move selected files to the Trash?", isPresented: $showDeleteSelectedAlert) {
            Button("Move to Trash", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The \(selectedItems.count) selected file(s) will be moved to the Trash.")
        }
        .alert("Operation Result", isPresented: Binding(
            get: { operationMessage != nil },
            set: { if !$0 { operationMessage = nil } }
        )) {
            Button("OK") { operationMessage = nil }
        } message: {
            Text(operationMessage ?? "")
        }
        .alert(autoCleaner.isEnabled ? "Automatic Cleanup Enabled" : "Automatic Cleanup Disabled", isPresented: $showAutoCleanFeedbackAlert) {
            Button("OK") { }
        } message: {
            Text(autoCleaner.feedbackMessage ?? "The automatic cleanup setting was updated.")
        }
        .alert("Enable automatic cleanup?", isPresented: $showAutoCleanConfirmation) {
            Button("Enable", role: .destructive) {
                autoCleaner.enable()
                showAutoCleanFeedbackAlert = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Once a day, WhatsClean will automatically move WhatsApp media older than seven days to the Trash. You can disable this setting at any time.")
        }
        .onAppear { scanner.scan() }
        .onReceive(timer) { _ in scanner.scan() }
    }

    private func getSelectedURLs() -> [URL] {
        return scanner.items.filter { selectedItems.contains($0.id) }.map { $0.url }
    }

    private func quickLookSelected() {
        if let first = getSelectedURLs().first {
            QuickLookManager.shared.preview(url: first)
        }
    }

    private func openSelected() {
        for u in getSelectedURLs() { NSWorkspace.shared.open(u) }
    }

    private func revealSelected() {
        let urls = getSelectedURLs()
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    private func saveSelected() {
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        for u in getSelectedURLs() {
            var dest = downloads.appendingPathComponent(u.lastPathComponent)
            if u.pathExtension.lowercased() == "thumb" {
                dest = downloads.appendingPathComponent(u.deletingPathExtension().appendingPathExtension("jpg").lastPathComponent)
            }
            dest = uniqueDestination(for: dest)
            do {
                try FileManager.default.copyItem(at: u, to: dest)
            } catch {
                operationMessage = "Could not save \(u.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    private func uniqueDestination(for requestedURL: URL) -> URL {
        guard FileManager.default.fileExists(atPath: requestedURL.path) else { return requestedURL }
        let directory = requestedURL.deletingLastPathComponent()
        let ext = requestedURL.pathExtension
        let base = requestedURL.deletingPathExtension().lastPathComponent
        var index = 2
        while true {
            let suffix = "\(base) \(index)" + (ext.isEmpty ? "" : ".\(ext)")
            let candidate = directory.appendingPathComponent(suffix)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }

    private func deleteSelected() {
        var deleted = 0
        var failed = 0
        for u in getSelectedURLs() {
            do {
                try FileManager.default.trashItem(at: u, resultingItemURL: nil)
                deleted += 1
            } catch {
                failed += 1
            }
        }
        selectedItems.removeAll()
        operationMessage = deletionMessage(deleted: deleted, failed: failed)
        scanner.scan()
    }

    private func deletionMessage(deleted: Int, failed: Int) -> String {
        if failed == 0 { return "\(deleted) file(s) moved to the Trash." }
        return "\(deleted) file(s) moved to the Trash; \(failed) could not be moved. Check macOS permissions."
    }
}

@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            controller.updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
        }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set {
            controller.updater.automaticallyDownloadsUpdates = newValue
            objectWillChange.send()
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

struct WhatsCleanSettingsView: View {
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @ObservedObject private var updates = UpdateManager.shared

    var body: some View {
        Form {
            Section("General") {
                Toggle("Show WhatsClean in the menu bar", isOn: $showMenuBarIcon)
                    .onChange(of: showMenuBarIcon) { _ in
                        NotificationCenter.default.post(name: .menuBarPreferenceChanged, object: nil)
                    }
            }

            Section("Updates") {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updates.automaticallyChecksForUpdates },
                    set: { updates.automaticallyChecksForUpdates = $0 }
                ))
                Toggle("Automatically download updates", isOn: Binding(
                    get: { updates.automaticallyDownloadsUpdates },
                    set: { updates.automaticallyDownloadsUpdates = $0 }
                ))
                .disabled(!updates.automaticallyChecksForUpdates)

                Button("Check for Updates Now") {
                    updates.checkForUpdates()
                }
            }

            Text("Updates are securely verified and installed by Sparkle using official WhatsClean releases on GitHub.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 480)
    }
}

extension Notification.Name {
    static let menuBarPreferenceChanged = Notification.Name("WhatsCleanMenuBarPreferenceChanged")
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var preferenceObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["showMenuBarIcon": true])
        _ = UpdateManager.shared
        preferenceObserver = NotificationCenter.default.addObserver(
            forName: .menuBarPreferenceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateMenuBarItem() }
        }
        updateMenuBarItem()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let preferenceObserver {
            NotificationCenter.default.removeObserver(preferenceObserver)
        }
    }

    private func updateMenuBarItem() {
        if UserDefaults.standard.bool(forKey: "showMenuBarIcon") {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "WhatsClean")

            let menu = NSMenu()
            menu.addItem(withTitle: "Open WhatsClean", action: #selector(showMainWindow), keyEquivalent: "")
            menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
            menu.addItem(NSMenuItem.separator())
            let quitItem = menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            for menuItem in menu.items where menuItem !== quitItem { menuItem.target = self }
            quitItem.target = NSApp
            item.menu = menu
            statusItem = item
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    @objc private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
    }

    @objc private func checkForUpdates() {
        UpdateManager.shared.checkForUpdates()
    }

    @objc private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

#if !UI_TEST_RENDER
@main
struct WhatsCleanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        if CommandLine.arguments.contains("--clean-7days") {
            let scanner = MediaScanner()
            let result = MediaScanner.scanSynchronously()
            scanner.items = result.items
            let deletion = scanner.deleteOlderThan7Days()
            appLogger.info("Automatic cleanup finished: \(deletion.deleted) moved, \(deletion.failed) failed")
            exit(deletion.failed == 0 ? 0 : 1)
        }
    }

    var body: some Scene {
        WindowGroup { ContentView() }
        Settings { WhatsCleanSettingsView() }
    }
}
#endif
