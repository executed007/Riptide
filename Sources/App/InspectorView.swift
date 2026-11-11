import SwiftUI

/// Right-hand inspector for the selected torrent.
struct InspectorView: View {
    @ObservedObject var store: TorrentStore
    let torrent: Torrent?
    let selectionCount: Int

    var body: some View {
        if let torrent {
            TorrentInspector(store: store, torrent: torrent)
        } else {
            ContentUnavailableView(selectionCount > 1 ? "\(selectionCount) torrents selected" : "No selection",
                                   systemImage: "info.circle",
                                   description: Text(selectionCount > 1 ? "Select a single torrent to see its details."
                                                                        : "Select a torrent to see its details."))
        }
    }
}

private struct TorrentInspector: View {
    @ObservedObject var store: TorrentStore
    let torrent: Torrent
    @State private var tab = Tab.info
    @State private var files: [FileRow] = []
    @State private var peers: [PeerRow] = []

    enum Tab: String, CaseIterable { case info = "Info", files = "Files", peers = "Peers", trackers = "Trackers" }

    struct FileRow: Identifiable {
        let id: Int
        let path: String
        let size: Int64
        let downloaded: Int64
        let priority: Int
        var name: String { (path as NSString).lastPathComponent }
        var progress: Double { size > 0 ? min(1, Double(downloaded) / Double(size)) : 1 }
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
            header
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            Divider()
            Group {
                switch tab {
                case .info: infoTab
                case .files: filesTab
                case .peers: peersTab
                case .trackers: trackersTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear(perform: reload)
        .onChange(of: torrent.id) { _, _ in reload() }
        .onChange(of: tab) { _, _ in reload() }
        .onReceive(refresh) { _ in reload() }
    }

    private func reload() {
        if tab == .files {
            files = store.files(for: torrent.id).enumerated().map { i, f in
                FileRow(id: i, path: f.path, size: f.size, downloaded: f.downloaded, priority: Int(f.priority))
            }
        }
        if tab == .peers {
            peers = store.peers(for: torrent.id).map {
                PeerRow(id: $0.address, client: $0.client, progress: $0.progress,
                        downloadRate: $0.downloadRate, uploadRate: $0.uploadRate)
            }.sorted { $0.downloadRate > $1.downloadRate }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                ProgressRing(value: torrent.progress, color: torrent.stateColor)
                VStack(alignment: .leading, spacing: 6) {
                    Text(torrent.name)
                        .font(.headline)
                        .lineLimit(3)
                        .textSelection(.enabled)
                    Label(torrent.state, systemImage: Theme.icon(for: torrent.state))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .foregroundStyle(torrent.stateColor)
                        .background(torrent.stateColor.opacity(0.14), in: Capsule())
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                if torrent.isPaused || torrent.state == "Queued" {
                    Button { store.resume([torrent.id]) } label: { Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button { store.pause([torrent.id]) } label: { Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                }
                Button { store.reveal([torrent.id]) } label: { Label("Show in Finder", systemImage: "folder").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
            }
            .controlSize(.regular)
        }
        .padding(16)
    }

    // MARK: Tabs

    private var infoTab: some View {
        ScrollView {
            VStack(spacing: 14) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    StatTile(title: "Download", value: Format.rate(torrent.downloadRate), icon: "arrow.down", tint: Theme.deep)
                    StatTile(title: "Upload", value: Format.rate(torrent.uploadRate), icon: "arrow.up", tint: .green)
                    StatTile(title: "Time left", value: Format.eta(torrent.eta), icon: "clock", tint: .orange)
                    StatTile(title: "Peers", value: "\(torrent.seeds) seeds · \(torrent.peers)", icon: "person.2", tint: .purple)
                }
                VStack(spacing: 0) {
                    InfoRow("Downloaded", "\(Format.bytes(torrent.totalWantedDone)) of \(Format.bytes(torrent.totalWanted))")
                    InfoRow("Uploaded", Format.bytes(torrent.totalUploaded))
                    InfoRow("Ratio", String(format: "%.2f", torrent.ratio))
                    InfoRow("Tracker", torrent.trackerStatus.isEmpty ? "–" : torrent.trackerStatus)
                    if !torrent.errorMessage.isEmpty { InfoRow("Error", torrent.errorMessage) }
                    InfoRow("Added", torrent.addedTime.formatted(date: .abbreviated, time: .shortened))
                    InfoRow("Location", torrent.savePath)
                    InfoRow("Info hash", torrent.id, monospaced: true, last: true)
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(16)
        }
    }

    private var filesTab: some View {
        List(files) { f in
            HStack(spacing: 10) {
                Image(systemName: f.priority == 0 ? "minus.circle" : "doc")
                    .foregroundStyle(f.priority == 0 ? .secondary : Theme.deep)
                VStack(alignment: .leading, spacing: 4) {
                    Text(f.name).lineLimit(1).truncationMode(.middle).help(f.path)
                        .foregroundStyle(f.priority == 0 ? .secondary : .primary)
                    SlimProgress(value: f.progress, color: f.priority == 0 ? .secondary : Theme.deep)
                    Text("\(Format.bytes(f.downloaded)) of \(Format.bytes(f.size))")
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
                Menu {
                    Picker("Priority", selection: Binding(
                        get: { f.priority == 0 ? 0 : (f.priority >= 7 ? 7 : 4) },
                        set: { store.setPriority(torrent.id, file: f.id, priority: $0); reload() })) {
                        Text("Don't Download").tag(0)
                        Text("Normal").tag(4)
                        Text("High").tag(7)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: f.priority >= 7 ? "flag.fill" : "ellipsis.circle")
                        .foregroundStyle(f.priority >= 7 ? .orange : .secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.vertical, 3)
        }
        .overlay {
            if files.isEmpty {
                ContentUnavailableView(torrent.state == "Metadata" ? "Fetching file list…" : "No files",
                                       systemImage: "doc.on.doc")
            }
        }
    }

    private var peersTab: some View {
        List(peers) { p in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.client.isEmpty ? "Unknown client" : p.client).lineLimit(1)
                    Text(p.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(p.downloadRate > 0 ? "↓ " + Format.rate(p.downloadRate) : Format.percent(p.progress))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(p.downloadRate > 0 ? Theme.deep : .secondary)
                    if p.uploadRate > 0 {
                        Text("↑ " + Format.rate(p.uploadRate)).font(.caption).foregroundStyle(.green)
                    }
                }
                .monospacedDigit()
            }
            .padding(.vertical, 2)
        }
        .overlay {
            if peers.isEmpty {
                ContentUnavailableView("No connected peers", systemImage: "person.2.slash")
            }
        }
    }

    private var trackersTab: some View {
        List {
            if !torrent.trackerStatus.isEmpty {
                Label(torrent.trackerStatus,
                      systemImage: torrent.trackerStatus.hasPrefix("Error") ? "exclamationmark.triangle" : "checkmark.circle")
                    .foregroundStyle(torrent.trackerStatus.hasPrefix("Error") ? .red : .green)
            }
            ForEach(torrent.trackers, id: \.self) { url in
                VStack(alignment: .leading, spacing: 2) {
                    Text(URL(string: url)?.host ?? url).font(.body.weight(.medium))
                    Text(url).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(1)
                }
                .padding(.vertical, 2)
            }
        }
        .overlay {
            if torrent.trackers.isEmpty {
                ContentUnavailableView("No trackers", systemImage: "antenna.radiowaves.left.and.right.slash",
                                       description: Text("Peers are found through DHT and peer exchange."))
            }
        }
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct InfoRow: View {
    let title: String
    let value: String
    var monospaced = false
    var last = false

    init(_ title: String, _ value: String, monospaced: Bool = false, last: Bool = false) {
        self.title = title; self.value = value; self.monospaced = monospaced; self.last = last
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Text(value)
                    .font(monospaced ? .caption.monospaced() : .callout)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            if !last { Divider().padding(.leading, 12) }
        }
    }
}
