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
    var localizedName: String { NSLocalizedString(rawValue, comment: "Media category") }
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

    private let preferenceKey = "autoCleanupEnabled"
    private let registeredBuildKey = "autoCleanupRegisteredBuild"
    private let launchAgentLabel = "com.vviniciusbarreto.whatsclean.autoclean"

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
        let defaults = UserDefaults.standard
        let plistExists = FileManager.default.fileExists(atPath: plistURL.path)
        let storedPreference = defaults.object(forKey: preferenceKey) as? Bool
        let jobLoaded = isJobLoaded()

        // Migrate pre-1.0.3 installations from their existing plist/job, then
        // preserve the user's intent independently of updater file replacement.
        let shouldBeEnabled = storedPreference ?? (plistExists || jobLoaded)
        guard shouldBeEnabled else {
            isEnabled = false
            return
        }

        defaults.set(true, forKey: preferenceKey)
        let buildChanged = defaults.string(forKey: registeredBuildKey) != currentBuild
        if !plistExists || !jobLoaded || buildChanged {
            installSchedule(showFeedback: false)
        } else {
            isEnabled = true
        }
    }

    func enable() {
        installSchedule(showFeedback: true)
    }

    private func installSchedule(showFeedback: Bool) {
        let exe = executablePath
        let applications = ["/Applications/", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path + "/"]
        guard applications.contains(where: { exe.hasPrefix($0) }) else {
            if showFeedback {
                feedbackMessage = NSLocalizedString("Install WhatsClean in the Applications folder before enabling automatic cleanup.", comment: "Auto cleanup error")
            }
            isEnabled = false
            return
        }

        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": [exe, "--clean-7days"],
            "StartInterval": 86400
        ]
        do {
            if FileManager.default.fileExists(atPath: plistURL.path) || isJobLoaded() {
                _ = runLaunchctl(["unload", plistURL.path])
            }
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
            UserDefaults.standard.set(true, forKey: preferenceKey)
            UserDefaults.standard.set(currentBuild, forKey: registeredBuildKey)
            if showFeedback {
                feedbackMessage = NSLocalizedString("Daily automatic cleanup is enabled.", comment: "Auto cleanup enabled")
            }
        } catch {
            isEnabled = false
            if showFeedback {
                feedbackMessage = String(format: NSLocalizedString("Automatic cleanup could not be enabled: %@", comment: "Auto cleanup error"), error.localizedDescription)
            }
        }
    }

    func disable() {
        _ = runLaunchctl(["unload", plistURL.path])
        try? FileManager.default.removeItem(at: plistURL)
        UserDefaults.standard.set(false, forKey: preferenceKey)
        UserDefaults.standard.removeObject(forKey: registeredBuildKey)
        self.isEnabled = false
        feedbackMessage = NSLocalizedString("Automatic cleanup is disabled.", comment: "Auto cleanup disabled")
    }

    private var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    private func isJobLoaded() -> Bool {
        runLaunchctl(["print", "gui/\(getuid())/\(launchAgentLabel)"]) == 0
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

enum WhatsAppFolderAccess {
    private static let bookmarkKey = "WhatsAppMediaFolderBookmark"
    private static let standardContainer = "group.net.whatsapp.WhatsApp.shared"
    private static let businessContainer = "group.net.whatsapp.WhatsAppSMB.shared"

    static var hasSelection: Bool {
        authorizedMediaRoot() != nil
    }

    static var selectedFolderName: String? {
        guard let url = resolveURL() else { return nil }
        return url.pathComponents.contains(businessContainer) ? "WhatsApp Business" : "WhatsApp"
    }

    static func resolveURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false

        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            if isStale { try? save(url) }
            return url
        }

        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            if isStale { try? save(url) }
            return url
        }
        return nil
    }

    @MainActor
    static func requestAccess() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Grant WhatsApp Access"
        panel.message = "WhatsClean has opened the expected WhatsApp media folder. Click Grant Access to continue."
        panel.prompt = "Grant Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true

        let media = suggestedContainerURL()
            .appendingPathComponent("Message", isDirectory: true)
            .appendingPathComponent("Media", isDirectory: true)
        panel.directoryURL = media

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return false }
        guard authorizedMediaRoot(from: selectedURL) != nil else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Choose the WhatsApp Folder"
            alert.informativeText = "For your safety, WhatsClean only accepts the official WhatsApp or WhatsApp Business data folder. No other app folders will be scanned."
            alert.runModal()
            return false
        }
        do {
            try save(selectedURL)
            NotificationCenter.default.post(name: .whatsAppFolderChanged, object: nil)
            return true
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Access Could Not Be Saved"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return false
        }
    }

    @MainActor
    private static func suggestedContainerURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let groupContainers = home.appendingPathComponent("Library/Group Containers", isDirectory: true)
        let standard = groupContainers.appendingPathComponent(standardContainer, isDirectory: true)
        let business = groupContainers.appendingPathComponent(businessContainer, isDirectory: true)

        let hasStandardApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "net.whatsapp.WhatsApp") != nil
        let hasBusinessApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "net.whatsapp.WhatsAppSMB") != nil
        return hasBusinessApp && !hasStandardApp ? business : standard
    }

    static func authorizedMediaRoot() -> URL? {
        guard let selectedURL = resolveURL() else { return nil }
        return authorizedMediaRoot(from: selectedURL)
    }

    private static func authorizedMediaRoot(from selectedURL: URL) -> URL? {
        let url = selectedURL.standardizedFileURL
        let components = url.pathComponents
        guard let containerIndex = components.firstIndex(where: {
            $0 == standardContainer || $0 == businessContainer
        }) else { return nil }

        let remainder = Array(components.dropFirst(containerIndex + 1))
        let containerURL = URL(fileURLWithPath: NSString.path(withComponents: Array(components.prefix(containerIndex + 1))), isDirectory: true)

        if remainder.isEmpty {
            return containerURL
                .appendingPathComponent("Message", isDirectory: true)
                .appendingPathComponent("Media", isDirectory: true)
        }
        if remainder == ["Message"] {
            return url.appendingPathComponent("Media", isDirectory: true)
        }
        if remainder == ["Message", "Media"] {
            return url
        }
        return nil
    }

    private static func save(_ url: URL) throws {
        let data: Data
        do {
            data = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            data = try url.bookmarkData(
                options: [.minimalBookmark],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }
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
    @Published var lastRefreshedAt: Date?

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
        guard let mediaRoot = WhatsAppFolderAccess.authorizedMediaRoot() else { return [] }
        return [mediaRoot]
    }

    nonisolated static func scanSynchronously() -> ScanResult {
        let roots = getMediaRoots()
        let authorizedFolder = WhatsAppFolderAccess.resolveURL()
        let isAccessingAuthorizedFolder = authorizedFolder?.startAccessingSecurityScopedResource() == true
        defer {
            if isAccessingAuthorizedFolder {
                authorizedFolder?.stopAccessingSecurityScopedResource()
            }
        }
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
            lastRefreshedAt = Date()
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
            statusMessage = NSLocalizedString("Grant access to WhatsApp data to begin scanning.", comment: "Scanner status")
        } else if result.inaccessibleRoots > 0 {
            statusMessage = NSLocalizedString("WhatsApp access is no longer available. Open WhatsClean Settings and grant folder access again.", comment: "Scanner status")
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
    @State private var hasMediaAccess = WhatsAppFolderAccess.hasSelection

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
                        Label(cat.localizedName, systemImage: cat.icon).tag(cat)
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
                        Text(String(format: NSLocalizedString("Clean 7d+ (%lld)", comment: "Cleanup button with file count"), Int64(scanner.olderThan7DaysCount)))
                            .lineLimit(1)
                    }
                }
                .foregroundColor(scanner.olderThan7DaysCount > 0 ? .orange : .secondary)
                .disabled(scanner.olderThan7DaysCount == 0)

                Button(action: { scanner.scan() }) {
                    if scanner.isScanning {
                        HStack(spacing: 5) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Refreshing…")
                        }
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(scanner.isScanning || !hasMediaAccess)
                .help("Refresh media list")

                Button(action: openSettings) {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Open WhatsClean settings")
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
                        Text(item.category.localizedName)
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
                if !hasMediaAccess {
                    VStack(spacing: 12) {
                        Image(systemName: "hand.raised.circle")
                            .font(.system(size: 38))
                            .foregroundColor(.accentColor)
                        Text("WhatsApp Access Required")
                            .font(.headline)
                        Text("WhatsClean will open the correct WhatsApp location for you. Select the highlighted folder and grant access once.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 440)
                        Button("Grant WhatsApp Access") {
                            hasMediaAccess = WhatsAppFolderAccess.requestAccess()
                            if hasMediaAccess { scanner.scan() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(24)
                } else if scanner.isScanning && scanner.items.isEmpty {
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
                Text(String(format: NSLocalizedString("%lld file(s) • Total: %@", comment: "File count and total size"), Int64(filteredItems.count), scanner.totalSizeString))
                    .font(.callout).foregroundColor(.secondary)
                Spacer()
                if scanner.isScanning {
                    Text("Refreshing…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if let lastRefreshedAt = scanner.lastRefreshedAt {
                    Text(String(format: NSLocalizedString("Updated %@", comment: "Last refresh time"), DateFormatter.localizedString(from: lastRefreshedAt, dateStyle: .none, timeStyle: .short)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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
            Text(String(format: NSLocalizedString("Found %lld file(s) older than seven days (%@). They will be moved to the Trash to free up space.", comment: "Old media cleanup confirmation"), Int64(scanner.olderThan7DaysCount), scanner.olderThan7DaysSizeString))
        }
        .alert("Move selected files to the Trash?", isPresented: $showDeleteSelectedAlert) {
            Button("Move to Trash", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(String(format: NSLocalizedString("The %lld selected file(s) will be moved to the Trash.", comment: "Selected files cleanup confirmation"), Int64(selectedItems.count)))
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
        .onAppear {
            hasMediaAccess = WhatsAppFolderAccess.hasSelection
            if hasMediaAccess { scanner.scan() }
        }
        .onReceive(timer) { _ in
            if hasMediaAccess { scanner.scan() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .whatsAppFolderChanged)) { _ in
            hasMediaAccess = WhatsAppFolderAccess.hasSelection
            if hasMediaAccess { scanner.scan() }
        }
    }

    private func openSettings() {
        SettingsWindowController.shared.show()
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
                operationMessage = String(format: NSLocalizedString("Could not save %@: %@", comment: "Save error"), u.lastPathComponent, error.localizedDescription)
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
        if failed == 0 {
            return String(format: NSLocalizedString("%lld file(s) moved to the Trash.", comment: "Deletion result"), Int64(deleted))
        }
        return String(format: NSLocalizedString("%lld file(s) moved to the Trash; %lld could not be moved. Check macOS permissions.", comment: "Deletion result"), Int64(deleted), Int64(failed))
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

        // Sparkle's automatic scheduler only checks after its configured interval.
        // Also perform a silent launch check when the user has automatic checks enabled.
        if controller.updater.automaticallyChecksForUpdates {
            controller.updater.checkForUpdatesInBackground()
        }
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

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }
    var localizedName: String { NSLocalizedString(rawValue, comment: "Appearance option") }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct WhatsCleanSettingsView: View {
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue
    @ObservedObject private var updates = UpdateManager.shared
    @State private var selectedFolderName = WhatsAppFolderAccess.selectedFolderName

    var body: some View {
        Form {
            Section("WhatsApp Access") {
                HStack {
                    Text(selectedFolderName ?? "Not granted")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(selectedFolderName == nil ? "Grant Access…" : "Change Folder…") {
                        if WhatsAppFolderAccess.requestAccess() {
                            selectedFolderName = WhatsAppFolderAccess.selectedFolderName
                        }
                    }
                }
                Text("WhatsClean remembers this choice and reuses it on future launches.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("General") {
                Picker("Appearance", selection: $appAppearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.localizedName).tag(appearance.rawValue)
                    }
                }
                .pickerStyle(.segmented)

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

            Section("Help") {
                HStack {
                    Button("Getting Started…") {
                        OnboardingWindowController.shared.show()
                    }
                    Button("About WhatsClean…") {
                        AboutWindowController.shared.show()
                    }
                }
            }

            Text("Updates are securely verified and installed by Sparkle using official WhatsClean releases on GitHub.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 480)
        .preferredColorScheme(AppAppearance(rawValue: appAppearance)?.colorScheme)
    }
}

struct OnboardingView: View {
    let completion: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 92, height: 92)

            VStack(spacing: 6) {
                Text("Welcome to WhatsClean")
                    .font(.largeTitle.bold())
                Text("A simple, private way to review and clean WhatsApp media on your Mac.")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 16) {
                onboardingRow(
                    icon: "hand.tap",
                    title: "Open it only when you need it",
                    detail: "Review your WhatsApp images, videos, audio, and documents, move what you no longer need to the Trash, and close the app. WhatsClean does not need to stay open."
                )
                onboardingRow(
                    icon: "bolt.shield",
                    title: "Optional automatic cleanup",
                    detail: "Enable Auto (7d) once to move WhatsApp media older than seven days to the Trash every day. macOS runs the task briefly; WhatsClean does not remain in the background consuming RAM or CPU."
                )
                onboardingRow(
                    icon: "lock.shield",
                    title: "Private and under your control",
                    detail: "Files are processed locally on your Mac. Deleted items go to the Trash, and automatic cleanup can be disabled at any time."
                )
            }
            .frame(maxWidth: 620)

            HStack {
                Button("About WhatsClean…") {
                    AboutWindowController.shared.show()
                }
                Spacer()
                Button("Get Started") { completion() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
        .frame(minWidth: 560, idealWidth: 680, minHeight: 480)
    }

    private func onboardingRow(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct AboutWhatsCleanView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 104, height: 104)
            VStack(spacing: 4) {
                Text("WhatsClean").font(.largeTitle.bold())
                Text(String(format: NSLocalizedString("Version %@", comment: "App version"), version)).foregroundColor(.secondary)
            }
            Text("Clean WhatsApp media on macOS without keeping another app running in the background.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Text("Use WhatsClean when you need it and close it when you are done. If Auto (7d) is enabled, macOS briefly runs a scheduled cleanup once a day and moves WhatsApp media older than seven days to the Trash—without WhatsClean continuously using RAM or CPU.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 500)
            HStack(spacing: 16) {
                Link("Project on GitHub", destination: URL(string: "https://github.com/vviniciusbarreto/WhatsClean")!)
                Link("GPLv3 License", destination: URL(string: "https://github.com/vviniciusbarreto/WhatsClean/blob/main/LICENSE")!)
            }
            Text("Created by Vinicius Barreto • Open source and privacy-friendly")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(30)
        .frame(minWidth: 520, idealWidth: 580, minHeight: 490)
    }
}

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    private init() {
        let window = NSWindow()
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: OnboardingView {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboardingV1")
            NSApp.keyWindow?.close()
        })
        window.title = NSLocalizedString("Getting Started", comment: "Onboarding window title")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 680, height: 560))
        window.minSize = NSSize(width: 560, height: 480)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboardingV1")
    }
}

@MainActor
final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()

    private init() {
        let window = NSWindow(contentViewController: NSHostingController(rootView: AboutWhatsCleanView()))
        window.title = NSLocalizedString("About WhatsClean", comment: "About window title")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 580, height: 520))
        window.minSize = NSSize(width: 520, height: 490)
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let hostingController = NSHostingController(rootView: WhatsCleanSettingsView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = NSLocalizedString("WhatsClean Settings", comment: "Settings window title")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 480, height: 460))
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

extension Notification.Name {
    static let menuBarPreferenceChanged = Notification.Name("WhatsCleanMenuBarPreferenceChanged")
    static let whatsAppFolderChanged = Notification.Name("WhatsCleanWhatsAppFolderChanged")
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
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboardingV1") {
            DispatchQueue.main.async {
                OnboardingWindowController.shared.show()
            }
        }
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
            menu.addItem(withTitle: NSLocalizedString("Open WhatsClean", comment: "Menu bar item"), action: #selector(showMainWindow), keyEquivalent: "")
            menu.addItem(withTitle: NSLocalizedString("Check for Updates…", comment: "Menu bar item"), action: #selector(checkForUpdates), keyEquivalent: "")
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: NSLocalizedString("Getting Started…", comment: "Menu bar item"), action: #selector(showOnboarding), keyEquivalent: "")
            menu.addItem(withTitle: NSLocalizedString("About WhatsClean…", comment: "Menu bar item"), action: #selector(showAbout), keyEquivalent: "")
            menu.addItem(withTitle: NSLocalizedString("Settings…", comment: "Menu bar item"), action: #selector(showSettings), keyEquivalent: ",")
            menu.addItem(NSMenuItem.separator())
            let quitItem = menu.addItem(withTitle: NSLocalizedString("Quit", comment: "Menu bar item"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
        SettingsWindowController.shared.show()
    }

    @objc private func showOnboarding() {
        OnboardingWindowController.shared.show()
    }

    @objc private func showAbout() {
        AboutWindowController.shared.show()
    }
}

#if !UI_TEST_RENDER
@main
struct WhatsCleanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue

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
        WindowGroup {
            ContentView()
                .preferredColorScheme(AppAppearance(rawValue: appAppearance)?.colorScheme)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About WhatsClean") {
                    AboutWindowController.shared.show()
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    SettingsWindowController.shared.show()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .help) {
                Button("Getting Started…") {
                    OnboardingWindowController.shared.show()
                }
            }
        }
    }
}
#endif
