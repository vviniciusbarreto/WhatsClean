import SwiftUI
import AppKit
import Quartz
import AVFoundation

enum MediaCategory: String, CaseIterable, Identifiable {
    case all = "Todos"
    case images = "Imagens"
    case videos = "Vídeos"
    case audio = "Áudios"
    case docs = "Documentos"
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

struct MediaItem: Identifiable, Hashable {
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
    
    func toggle() {
        if isEnabled {
            disable()
        } else {
            enable()
        }
    }
    
    func enable() {
        let exe = executablePath
        let plistContent = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n<key>Label</key>\n<string>com.vviniciusbarreto.whatsclean.autoclean</string>\n<key>ProgramArguments</key>\n<array>\n<string>\(exe)</string>\n<string>--clean-7days</string>\n</array>\n<key>StartInterval</key>\n<integer>86400</integer>\n<key>RunAtLoad</key>\n<true/>\n</dict>\n</plist>"
        try? plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
        Process.launchedProcess(launchPath: "/bin/launchctl", arguments: ["load", "-w", plistURL.path])
        if FileManager.default.fileExists(atPath: exe) {
            Process.launchedProcess(launchPath: exe, arguments: ["--clean-7days"])
        }
        self.isEnabled = true
    }
    
    func disable() {
        Process.launchedProcess(launchPath: "/bin/launchctl", arguments: ["unload", plistURL.path])
        try? FileManager.default.removeItem(at: plistURL)
        self.isEnabled = false
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
        .task {
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
        let url = item.url
        if item.category == .images || item.ext == "JPG" || item.ext == "PNG" || item.ext == "GIF" {
            DispatchQueue.global(qos: .userInitiated).async {
                if let img = NSImage(contentsOf: url) {
                    DispatchQueue.main.async { self.thumbnail = img }
                }
            }
        } else if item.category == .videos {
            DispatchQueue.global(qos: .userInitiated).async {
                let asset = AVURLAsset(url: url)
                let gen = AVAssetImageGenerator(asset: asset)
                gen.appliesPreferredTrackTransform = true
                let time = CMTime(seconds: 0.5, preferredTimescale: 60)
                if let cgImage = try? gen.copyCGImage(at: time, actualTime: nil) {
                    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 36, height: 36))
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
    
    private func getMediaRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var dirs: [URL] = [
            home.appendingPathComponent("Library/Group Containers/group.net.whatsapp.WhatsApp.shared/Message/Media"),
            home.appendingPathComponent("Library/Group Containers/group.net.whatsapp.WhatsApp.shared"),
            home.appendingPathComponent("Library/Group Containers/group.net.whatsapp.WhatsAppSMB.shared/Message/Media"),
            home.appendingPathComponent("Library/Group Containers/group.net.whatsapp.WhatsAppSMB.shared"),
            home.appendingPathComponent("Library/Group Containers/group.net.whatsapp.family"),
            home.appendingPathComponent("Library/Containers/net.whatsapp.WhatsApp"),
            home.appendingPathComponent("Library/Application Support/WhatsApp"),
            home.appendingPathComponent("Library/Application Support/WhatsApp Web")
        ]
        
        let containers = home.appendingPathComponent("Library/Containers")
        let webAppPaths = [
            home.appendingPathComponent("Applications/WhatsApp Web.app"),
            URL(fileURLWithPath: "/Applications/WhatsApp Web.app")
        ]
        for wApp in webAppPaths {
            let plistURL = wApp.appendingPathComponent("Contents/Info.plist")
            if let data = try? Data(contentsOf: plistURL),
               let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
               let bundleId = plist["CFBundleIdentifier"] as? String {
                let containerURL = containers.appendingPathComponent(bundleId)
                dirs.append(containerURL)
            }
        }
        
        var unique: [URL] = []
        var seen = Set<String>()
        for d in dirs {
            let p = d.path
            if FileManager.default.fileExists(atPath: p) && !seen.contains(p) {
                seen.insert(p)
                unique.append(d)
            }
        }
        return unique
    }
    
    func scan() {
        let roots = getMediaRoots()
        guard !roots.isEmpty else {
            self.items = []
            return
        }
        
        var scanned: [MediaItem] = []
        var seenFiles = Set<String>()
        var totalBytes: Int64 = 0
        var oldBytes: Int64 = 0
        var oldCount: Int = 0
        
        let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "svg", "psd", "ai", "heic", "webp", "bmp", "tiff"]
        let videoExts: Set<String> = ["mp4", "mov", "m4v", "mkv", "avi", "webm"]
        let audioExts: Set<String> = ["opus", "mp3", "m4a", "wav", "flac", "ogg", "aac", "wma"]
        let docExts: Set<String> = ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "zip", "rar", "7z", "tar", "gz", "csv"]
        let excludedDirs = ["avatars", "stickers", "profile", "profilepictures", "frameworks", "codesignature"]
        
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { continue }
            
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
        self.items = scanned
        self.olderThan7DaysCount = oldCount
        
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useAll]
        bcf.countStyle = .file
        self.totalSizeString = bcf.string(fromByteCount: totalBytes)
        self.olderThan7DaysSizeString = bcf.string(fromByteCount: oldBytes)
    }
    
    func deleteOlderThan7Days() -> Int {
        var deleted = 0
        for item in items where item.isOlderThan7Days {
            do {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                deleted += 1
            } catch {
                try? FileManager.default.removeItem(at: item.url)
                deleted += 1
            }
        }
        scan()
        return deleted
    }
}

struct ContentView: View {
    @StateObject private var scanner = MediaScanner()
    @StateObject private var autoCleaner = AutoCleanerManager()
    @State private var selectedCategory: MediaCategory = .all
    @State private var searchText: String = ""
    @State private var selectedItems = Set<String>()
    @State private var showDelete7DaysAlert: Bool = false
    @State private var showAutoCleanFeedbackAlert: Bool = false
    
    let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    
    var filteredItems: [MediaItem] {
        scanner.items.filter { item in
            let matchesCategory = (selectedCategory == .all || item.category == selectedCategory)
            let matchesSearch = searchText.isEmpty || item.name.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 10) {
                Picker("Categoria", selection: $selectedCategory) {
                    ForEach(MediaCategory.allCases) { cat in
                        Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 380)
                
                Spacer()
                
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Buscar por nome...", text: $searchText).textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .frame(width: 200)
                
                Button(action: {
                    autoCleaner.toggle()
                    showAutoCleanFeedbackAlert = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: autoCleaner.isEnabled ? "bolt.shield.fill" : "bolt.shield")
                        Text(autoCleaner.isEnabled ? "Auto-Limpeza (7d): ATIVA" : "Ativar Auto-Limpeza (7d)")
                            .fontWeight(autoCleaner.isEnabled ? .semibold : .regular)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(autoCleaner.isEnabled ? .green : .secondary)
                
                Button(action: { showDelete7DaysAlert = true }) {
                    Label("Limpar +7d (\(scanner.olderThan7DaysCount))", systemImage: "clock.arrow.circlepath")
                }
                .foregroundColor(scanner.olderThan7DaysCount > 0 ? .orange : .secondary)
                .disabled(scanner.olderThan7DaysCount == 0)
                
                Button(action: { scanner.scan() }) {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Table
            Table(filteredItems, selection: $selectedItems) {
                TableColumn("Prévia") { item in
                    AsyncThumbnailView(item: item)
                }
                .width(42)
                
                TableColumn("Nome") { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .lineLimit(1)
                            .fontWeight(.medium)
                        Text(item.category.rawValue)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .width(min: 240, ideal: 360)
                
                TableColumn("Formato") { item in
                    Text(item.ext)
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(4)
                }
                .width(75)
                
                TableColumn("Tamanho") { item in
                    Text(item.sizeFormatted)
                        .font(.system(.body, design: .monospaced))
                }
                .width(100)
                
                TableColumn("Data") { item in
                    Text(item.dateFormatted)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(item.isOlderThan7Days ? .orange : .secondary)
                }
                .width(170)
            }
            .contextMenu {
                Button("Quick Look (Espaço)") { quickLookSelected() }
                Button("Abrir no App Padrão") { openSelected() }
                Button("Revelar no Finder") { revealSelected() }
                Button("Salvar em Downloads") { saveSelected() }
                Divider()
                Button("Mover para o Lixo", role: .destructive) { deleteSelected() }
            }
            
            Divider()
            
            // Bottom Action Bar
            HStack(spacing: 12) {
                Text("\(filteredItems.count) arquivo(s) • Total: \(scanner.totalSizeString)")
                    .font(.callout).foregroundColor(.secondary)
                Spacer()
                
                Button(action: quickLookSelected) {
                    Label("Quick Look (Espaço)", systemImage: "eye.circle")
                }
                .disabled(selectedItems.isEmpty)
                .keyboardShortcut(.space, modifiers: [])
                
                Button(action: openSelected) {
                    Label("Abrir", systemImage: "arrow.up.forward.app")
                }
                .disabled(selectedItems.isEmpty)
                
                Button(action: revealSelected) {
                    Label("No Finder", systemImage: "folder")
                }
                .disabled(selectedItems.isEmpty)
                
                Button(action: saveSelected) {
                    Label("Salvar em Downloads", systemImage: "arrow.down.circle")
                }
                .disabled(selectedItems.isEmpty)
                
                Button(role: .destructive, action: deleteSelected) {
                    Label("Mover para o Lixo", systemImage: "trash")
                }
                .disabled(selectedItems.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 980, minHeight: 600)
        .navigationTitle("WhatsClean")
        .alert("Limpar Mídias com mais de 7 dias?", isPresented: $showDelete7DaysAlert) {
            Button("Mover para o Lixo", role: .destructive) {
                _ = scanner.deleteOlderThan7Days()
            }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("Foram encontrados \(scanner.olderThan7DaysCount) arquivo(s) com mais de 7 dias (\(scanner.olderThan7DaysSizeString)). Eles serão movidos para o Lixo do Mac para liberar espaço.")
        }
        .alert(autoCleaner.isEnabled ? "Auto-Limpeza Ativada com Sucesso!" : "Auto-Limpeza Desativada", isPresented: $showAutoCleanFeedbackAlert) {
            Button("OK") { }
        } message: {
            if autoCleaner.isEnabled {
                Text("O WhatsClean executará a limpeza automática diária de todos os arquivos do WhatsApp com mais de 7 dias em segundo plano (com o aplicativo aberto ou fechado).\n\nQuando finaliza, o processo consome 0% de CPU e 0 MB de memória RAM.")
            } else {
                Text("A rotina automática em segundo plano foi desativada.")
            }
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
            try? FileManager.default.copyItem(at: u, to: dest)
        }
    }
    
    private func deleteSelected() {
        for u in getSelectedURLs() { try? FileManager.default.trashItem(at: u, resultingItemURL: nil) }
        scanner.scan()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct WhatsCleanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        if CommandLine.arguments.contains("--clean-7days") {
            let scanner = MediaScanner()
            _ = scanner.deleteOlderThan7Days()
            exit(0)
        }
    }
    
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
