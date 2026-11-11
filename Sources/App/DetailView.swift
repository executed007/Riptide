import SwiftUI

/// Bottom pane for the selected torrent: overview, files, trackers, peers.
struct DetailView: View {
    @ObservedObject var store: TorrentStore
    let torrent: Torrent
    @State private var tab = 0
    @State private var files: [FileRow] = []
    @State private var peers: [PeerRow] = []

    struct FileRow: Identifiable {
        let id: Int
        let path: String
        let size: Int64
        let downloaded: Int64
        let priority: Int
    }

    struct PeerRow: Identifiable {
        let id: String
        let client: String
        let progress: Double
        let downloadRate: Int64
        let uploadRate: Int64
    }

    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Overview").tag(0)
                Text("Files").tag(1)
                Text("Trackers").tag(2)
                Text("Peers").tag(3)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)
            .padding(8)

            Group {
                switch tab {
                case 1: filesTab
                case 2: trackersTab
                case 3: peersTab
                default: overviewTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear(perform: reload)
        .onChange(of: torrent.id) { _, _ in reload() }
        .onChange(of: tab) { _, _ in reload() }
        .onReceive(refresh) { _ in reload() }
    }

    private func reload() {
        if tab == 1 {
            files = store.files(for: torrent.id).enumerated().map { i, f in
                FileRow(id: i, path: f.path, size: f.size, downloaded: f.downloaded, priority: Int(f.priority))
            }
        }
        if tab == 3 {
            peers = store.peers(for: torrent.id).map {
                PeerRow(id: $0.address, client: $0.client, progress: $0.progress,
                        downloadRate: $0.downloadRate, uploadRate: $0.uploadRate)
            }
        }
    }

    private var overviewTab: some View {
        Form {
            LabeledContent("Name", value: torrent.name)
            LabeledContent("State", value: torrent.errorMessage.isEmpty ? torrent.state : "\(torrent.state): \(torrent.errorMessage)")
            LabeledContent("Downloaded", value: "\(Format.bytes(torrent.totalWantedDone)) of \(Format.bytes(torrent.totalWanted)) (\(Format.percent(torrent.progress)))")
            LabeledContent("Uploaded", value: "\(Format.bytes(torrent.totalUploaded)) (ratio \(String(format: "%.2f", torrent.ratio)))")
            LabeledContent("Tracker status", value: torrent.trackerStatus.isEmpty ? "–" : torrent.trackerStatus)
            LabeledContent("Save location") {
                Button(torrent.savePath) { store.reveal([torrent.id]) }.buttonStyle(.link)
            }
            LabeledContent("Info hash") { Text(torrent.id).textSelection(.enabled).monospaced() }
            LabeledContent("Added", value: torrent.addedTime.formatted(date: .abbreviated, time: .shortened))
        }
        .formStyle(.grouped)
    }

    private var filesTab: some View {
        Table(files) {
            TableColumn("File") { row in Text(row.path).lineLimit(1).help(row.path) }
                .width(min: 240, ideal: 420)
            TableColumn("Size") { row in Text(Format.bytes(row.size)).monospacedDigit() }
                .width(80)
            TableColumn("Progress") { row in
                let p = row.size > 0 ? Double(row.downloaded) / Double(row.size) : 1
                ProgressView(value: min(max(p, 0), 1))
            }
            .width(min: 90, ideal: 130)
            TableColumn("Priority") { row in
                Picker("", selection: Binding(
                    get: { row.priority == 0 ? 0 : (row.priority >= 7 ? 7 : 4) },
                    set: { store.setPriority(torrent.id, file: row.id, priority: $0); reload() })) {
                    Text("Skip").tag(0)
                    Text("Normal").tag(4)
                    Text("High").tag(7)
                }
                .labelsHidden()
            }
            .width(100)
        }
        .overlay {
            if files.isEmpty {
                Text(torrent.state == "Metadata" ? "Fetching file list from peers…" : "No files")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var trackersTab: some View {
        List {
            if !torrent.trackerStatus.isEmpty {
                Text("Status: \(torrent.trackerStatus)").foregroundStyle(.secondary)
            }
            ForEach(torrent.trackers, id: \.self) { Text($0).textSelection(.enabled) }
            if torrent.trackers.isEmpty { Text("No trackers (DHT and peer exchange only)").foregroundStyle(.secondary) }
        }
    }

    private var peersTab: some View {
        Table(peers) {
            TableColumn("Address") { p in Text(p.id).monospaced() }.width(min: 160, ideal: 200)
            TableColumn("Client") { p in Text(p.client) }.width(min: 120, ideal: 180)
            TableColumn("Progress") { p in Text(Format.percent(p.progress)).monospacedDigit() }.width(70)
            TableColumn("Down") { p in Text(Format.rate(p.downloadRate)).monospacedDigit() }.width(85)
            TableColumn("Up") { p in Text(Format.rate(p.uploadRate)).monospacedDigit() }.width(85)
        }
        .overlay { if peers.isEmpty { Text("No connected peers").foregroundStyle(.secondary) } }
    }
}

struct SettingsView: View {
    @ObservedObject var store: TorrentStore
    @AppStorage(Prefs.downloadDirectory) private var downloadDirectory = ""
    @AppStorage(Prefs.listenPort) private var listenPort = 6881
    @AppStorage(Prefs.downloadLimitKiB) private var downloadLimit = 0
    @AppStorage(Prefs.uploadLimitKiB) private var uploadLimit = 0

    var body: some View {
        Form {
            Section("Downloads") {
                LabeledContent("Save new torrents to") {
                    HStack {
                        Text(downloadDirectory).lineLimit(1).truncationMode(.middle)
                        Button("Choose…", action: chooseFolder)
                    }
                }
            }
            Section("Bandwidth (KiB/s, 0 = unlimited)") {
                TextField("Download limit", value: $downloadLimit, format: .number)
                TextField("Upload limit", value: $uploadLimit, format: .number)
            }
            Section("Network") {
                TextField("Listening port", value: $listenPort, format: .number.grouping(.never))
                Text("DHT, local peer discovery, UPnP and NAT-PMP are on.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onChange(of: downloadLimit) { _, _ in store.applyLimits() }
        .onChange(of: uploadLimit) { _, _ in store.applyLimits() }
        .onChange(of: listenPort) { _, _ in store.applyListenPort() }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: downloadDirectory)
        if panel.runModal() == .OK, let url = panel.url { downloadDirectory = url.path }
    }
}
