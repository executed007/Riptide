import Foundation

struct Torrent: Identifiable, Hashable, Searchable {
    let id: String              // info-hash (hex)
    let name: String
    let state: String
    let errorMessage: String
    let trackerStatus: String
    let savePath: String
    let trackers: [String]
    let files: [String]
    let progress: Double
    let downloadRate: Int64
    let uploadRate: Int64
    let totalWanted: Int64
    let totalWantedDone: Int64
    let totalUploaded: Int64
    let totalDownloaded: Int64
    let peers: Int
    let seeds: Int
    let queuePosition: Int
    let addedTime: Date

    init(_ s: RTTorrentStatus) {
        id = s.infoHash; name = s.name; state = s.state
        errorMessage = s.errorMessage; trackerStatus = s.trackerStatus; savePath = s.savePath
        trackers = s.trackers; files = s.filePaths
        progress = s.progress; downloadRate = s.downloadRate; uploadRate = s.uploadRate
        totalWanted = s.totalWanted; totalWantedDone = s.totalWantedDone
        totalUploaded = s.totalUploaded; totalDownloaded = s.totalDownloaded
        peers = Int(s.numPeers); seeds = Int(s.numSeeds); queuePosition = Int(s.queuePosition)
        addedTime = Date(timeIntervalSince1970: s.addedTime)
    }

    var searchName: String { name }
    var searchableTexts: [String] { [name, state] + trackers + [id, trackerStatus, errorMessage] + files }

    var isActive: Bool { state == "Downloading" || state == "Metadata" || state == "Seeding" || state == "Checking" }
    var isPaused: Bool { state == "Paused" || state == "Error" }

    /// Seconds left, nil when unknown or finished.
    var eta: Double? {
        let left = totalWanted - totalWantedDone
        guard left > 0, downloadRate > 0 else { return nil }
        return Double(left) / Double(downloadRate)
    }

    var ratio: Double {
        let base = max(totalDownloaded, totalWantedDone)
        return base > 0 ? Double(totalUploaded) / Double(base) : 0
    }

    var trackerHosts: [String] {
        trackers.compactMap { URL(string: $0)?.host?.lowercased() }
    }

    var folderURL: URL {
        let base = URL(fileURLWithPath: savePath)
        if let first = files.first, let top = first.split(separator: "/").first, files.count > 1 || first.contains("/") {
            return base.appendingPathComponent(String(top))
        }
        return files.first.map { base.appendingPathComponent($0) } ?? base
    }
}

enum Format {
    static func bytes(_ v: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: v, countStyle: .file)
    }
    static func rate(_ v: Int64) -> String { v > 0 ? bytes(v) + "/s" : "–" }
    static func eta(_ seconds: Double?) -> String {
        guard let s = seconds, s.isFinite else { return "–" }
        let f = DateComponentsFormatter()
        f.allowedUnits = s >= 86400 ? [.day, .hour] : s >= 3600 ? [.hour, .minute] : [.minute, .second]
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        return f.string(from: s) ?? "–"
    }
    static func percent(_ p: Double) -> String { String(format: "%.1f%%", p * 100) }
}
