import AppKit
import Foundation

enum SidebarItem: Hashable {
    case all
    case state(String)
    case tracker(String)
}

enum Prefs {
    static let downloadDirectory = "downloadDirectory"
    static let listenPort = "listenPort"
    static let downloadLimitKiB = "downloadLimitKiB"
    static let uploadLimitKiB = "uploadLimitKiB"
}

@MainActor
final class TorrentStore: ObservableObject {
    @Published private(set) var torrents: [Torrent] = []
    @Published private(set) var dhtNodes = 0
    @Published var lastError: String?
    @Published var showFileImporter = false
    @Published var showMagnetSheet = false

    private let session: RTSession
    private var timer: Timer?
    private var ticks = 0
    private var isShutDown = false

    static let stateDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Riptide/state", isDirectory: true)
    }()

    init() {
        let d = UserDefaults.standard
        if d.object(forKey: Prefs.listenPort) == nil { d.set(6881, forKey: Prefs.listenPort) }
        if d.string(forKey: Prefs.downloadDirectory) == nil {
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            d.set(downloads.path, forKey: Prefs.downloadDirectory)
        }
        session = RTSession(stateDirectory: Self.stateDirectory.path,
                            listenPort: Int32(d.integer(forKey: Prefs.listenPort)))
        applyLimits()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    var downloadDirectory: String {
        UserDefaults.standard.string(forKey: Prefs.downloadDirectory) ?? NSHomeDirectory()
    }

    private func tick() {
        guard !isShutDown else { return }
        session.processAlerts()
        torrents = session.statuses().map(Torrent.init).sorted { $0.addedTime > $1.addedTime }
        dhtNodes = Int(session.dhtNodes())
        ticks += 1
        if ticks % 120 == 0 { session.saveResumeDataAsync() }
    }

    // MARK: Adding

    func open(_ urls: [URL]) {
        for url in urls {
            if url.scheme?.lowercased() == "magnet" { addMagnet(url.absoluteString) }
            else if url.isFileURL { addTorrentFile(url) }
        }
    }

    func addTorrentFile(_ url: URL) {
        do { _ = try session.addTorrentFile(url.path, savePath: downloadDirectory); tick() }
        catch { lastError = "\(url.lastPathComponent): \(error.localizedDescription)" }
    }

    func addMagnet(_ link: String) {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        do { _ = try session.addMagnet(trimmed, savePath: downloadDirectory); tick() }
        catch { lastError = error.localizedDescription }
    }

    // MARK: Actions

    func pause(_ ids: Set<Torrent.ID>) { ids.forEach { session.pause($0) }; tick() }
    func resume(_ ids: Set<Torrent.ID>) { ids.forEach { session.resume($0) }; tick() }
    func recheck(_ ids: Set<Torrent.ID>) { ids.forEach { session.forceRecheck($0) }; tick() }
    func remove(_ ids: Set<Torrent.ID>, deleteFiles: Bool) {
        ids.forEach { session.remove($0, deleteFiles: deleteFiles) }
        tick()
    }

    func reveal(_ ids: Set<Torrent.ID>) {
        let urls = torrents.filter { ids.contains($0.id) }.map(\.folderURL)
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func copyMagnet(_ ids: Set<Torrent.ID>) {
        let links = torrents.filter { ids.contains($0.id) }.map { t -> String in
            var link = "magnet:?xt=urn:btih:\(t.id)&dn=" + (t.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
            for tr in t.trackers { link += "&tr=" + (tr.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "") }
            return link
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(links.joined(separator: "\n"), forType: .string)
    }

    func files(for id: Torrent.ID) -> [RTFileEntry] { session.files(for: id) }
    func peers(for id: Torrent.ID) -> [RTPeerEntry] { session.peers(for: id) }
    func setPriority(_ id: Torrent.ID, file: Int, priority: Int) {
        session.setFilePriority(id, fileIndex: Int32(file), priority: Int32(priority))
    }

    // MARK: Settings

    func applyLimits() {
        let d = UserDefaults.standard
        session.setDownloadLimit(Int32(max(0, d.integer(forKey: Prefs.downloadLimitKiB)) * 1024),
                                 uploadLimit: Int32(max(0, d.integer(forKey: Prefs.uploadLimitKiB)) * 1024))
    }

    func applyListenPort() {
        let port = UserDefaults.standard.integer(forKey: Prefs.listenPort)
        if (1...65535).contains(port) { session.setListenPort(Int32(port)) }
    }

    // MARK: Filtering

    func filtered(sidebar: SidebarItem, query: String) -> [Torrent] {
        let base: [Torrent]
        switch sidebar {
        case .all: base = torrents
        case .state(let s): base = torrents.filter { $0.state == s }
        case .tracker(let host): base = torrents.filter { $0.trackerHosts.contains(host) }
        }
        return keywordSearch(base, query: query)
    }

    func count(_ item: SidebarItem) -> Int { filtered(sidebar: item, query: "").count }

    var trackerHosts: [String] { Array(Set(torrents.flatMap(\.trackerHosts))).sorted() }

    var totalDownloadRate: Int64 { torrents.reduce(0) { $0 + $1.downloadRate } }
    var totalUploadRate: Int64 { torrents.reduce(0) { $0 + $1.uploadRate } }

    func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        timer?.invalidate()
        session.shutdown()
    }
}
