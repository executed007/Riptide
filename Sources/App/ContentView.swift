import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var store: TorrentStore
    @State private var sidebar: SidebarItem? = .all
    @State private var query = ""
    @State private var selection = Set<Torrent.ID>()
    @State private var sortOrder = [KeyPathComparator(\Torrent.addedTime, order: .reverse)]
    @State private var pendingRemoval: Set<Torrent.ID> = []
    @State private var confirmRemove = false

    private static let stateRows = ["Downloading", "Seeding", "Paused", "Queued", "Checking", "Metadata", "Error"]
    private static let torrentType = UTType(filenameExtension: "torrent") ?? .data

    private var rows: [Torrent] {
        store.filtered(sidebar: sidebar ?? .all, query: query).sorted(using: sortOrder)
    }

    private var selectedTorrents: [Torrent] { store.torrents.filter { selection.contains($0.id) } }

    var body: some View {
        NavigationSplitView {
            sidebarList
                .navigationSplitViewColumnWidth(min: 170, ideal: 200)
        } detail: {
            VSplitView {
                torrentTable
                    .frame(minHeight: 200)
                if let one = selectedTorrents.first, selection.count == 1 {
                    DetailView(store: store, torrent: one)
                        .frame(minHeight: 160, idealHeight: 230)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
        }
        .searchable(text: $query, placement: .toolbar,
                    prompt: "Search name, state, tracker, hash, files — comma = AND")
        .toolbar { toolbarContent }
        .fileImporter(isPresented: $store.showFileImporter, allowedContentTypes: [Self.torrentType],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { store.open(urls) }
        }
        .sheet(isPresented: $store.showMagnetSheet) { AddMagnetSheet(store: store) }
        .confirmationDialog(removeTitle, isPresented: $confirmRemove) {
            Button("Remove Torrent") { store.remove(pendingRemoval, deleteFiles: false); selection.subtract(pendingRemoval) }
            Button("Remove Torrent and Delete Data", role: .destructive) {
                store.remove(pendingRemoval, deleteFiles: true); selection.subtract(pendingRemoval)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deleting data removes the downloaded files from disk. This cannot be undone.")
        }
        .alert("Couldn't add torrent", isPresented: Binding(get: { store.lastError != nil },
                                                           set: { if !$0 { store.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(store.lastError ?? "") }
        .dropDestination(for: URL.self) { urls, _ in
            let torrents = urls.filter { $0.pathExtension.lowercased() == "torrent" || $0.scheme == "magnet" }
            store.open(torrents)
            return !torrents.isEmpty
        }
    }

    private var removeTitle: String {
        pendingRemoval.count == 1 ? "Remove this torrent?" : "Remove \(pendingRemoval.count) torrents?"
    }

    private func askRemove(_ ids: Set<Torrent.ID>) {
        guard !ids.isEmpty else { return }
        pendingRemoval = ids
        confirmRemove = true
    }

    // MARK: Sidebar (like Deluge's filter tree)

    private var sidebarList: some View {
        List(selection: $sidebar) {
            Section("States") {
                sidebarRow("All", icon: "tray.full", item: .all)
                ForEach(Self.stateRows, id: \.self) { s in
                    if store.count(.state(s)) > 0 || ["Downloading", "Seeding", "Paused"].contains(s) {
                        sidebarRow(s, icon: icon(for: s), item: .state(s))
                    }
                }
            }
            if !store.trackerHosts.isEmpty {
                Section("Trackers") {
                    ForEach(store.trackerHosts, id: \.self) { host in
                        sidebarRow(host, icon: "antenna.radiowaves.left.and.right", item: .tracker(host))
                    }
                }
            }
        }
    }

    private func sidebarRow(_ title: String, icon: String, item: SidebarItem) -> some View {
        Label(title, systemImage: icon)
            .badge(store.count(item))
            .tag(item)
    }

    private func icon(for state: String) -> String {
        switch state {
        case "Downloading": "arrow.down.circle"
        case "Seeding": "arrow.up.circle"
        case "Paused": "pause.circle"
        case "Queued": "clock"
        case "Checking": "checkmark.circle"
        case "Metadata": "magnifyingglass.circle"
        case "Error": "exclamationmark.triangle"
        default: "circle"
        }
    }

    // MARK: Table

    private var torrentTable: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { t in
                Text(t.name).lineLimit(1).help(t.errorMessage.isEmpty ? t.name : t.errorMessage)
            }
            .width(min: 200, ideal: 340)
            TableColumn("Size", value: \.totalWanted) { t in
                Text(t.totalWanted > 0 ? Format.bytes(t.totalWanted) : "–").monospacedDigit()
            }
            .width(80)
            TableColumn("Progress", value: \.progress) { t in
                HStack(spacing: 6) {
                    ProgressView(value: t.progress).tint(t.state == "Seeding" ? .green : .accentColor)
                    Text(Format.percent(t.progress)).monospacedDigit().font(.caption).frame(width: 44, alignment: .trailing)
                }
            }
            .width(min: 120, ideal: 160)
            TableColumn("State", value: \.state) { t in
                Text(t.state).foregroundStyle(t.state == "Error" ? .red : .primary)
            }
            .width(90)
            TableColumn("Down", value: \.downloadRate) { t in Text(Format.rate(t.downloadRate)).monospacedDigit() }
                .width(85)
            TableColumn("Up", value: \.uploadRate) { t in Text(Format.rate(t.uploadRate)).monospacedDigit() }
                .width(85)
            TableColumn("Seeds/Peers", value: \.peers) { t in Text("\(t.seeds) / \(t.peers)").monospacedDigit() }
                .width(80)
            TableColumn("ETA") { t in Text(Format.eta(t.eta)).monospacedDigit() }
                .width(70)
            TableColumn("Ratio", value: \.ratio) { t in Text(String(format: "%.2f", t.ratio)).monospacedDigit() }
                .width(50)
        }
        .contextMenu(forSelectionType: Torrent.ID.self) { ids in
            Button("Resume") { store.resume(ids) }
            Button("Pause") { store.pause(ids) }
            Divider()
            Button("Show in Finder") { store.reveal(ids) }
            Button("Copy Magnet Link") { store.copyMagnet(ids) }
            Button("Force Recheck") { store.recheck(ids) }
            Divider()
            Button("Remove…") { askRemove(ids) }
        } primaryAction: { ids in
            store.reveal(ids)
        }
        .onDeleteCommand { askRemove(selection) }
        .overlay {
            if store.torrents.isEmpty {
                ContentUnavailableView {
                    Label("No torrents", systemImage: "arrow.down.circle")
                } description: {
                    Text("Open a .torrent file, paste a magnet link, or drop a .torrent file here.")
                } actions: {
                    HStack {
                        Button("Open Torrent File…") { store.showFileImporter = true }
                        Button("Add Magnet Link…") { store.showMagnetSheet = true }
                    }
                }
            } else if rows.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    // MARK: Toolbar & status bar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { store.showFileImporter = true } label: { Label("Open Torrent", systemImage: "doc.badge.plus") }
                .help("Open a .torrent file (⌘O)")
            Button { store.showMagnetSheet = true } label: { Label("Add Magnet", systemImage: "link.badge.plus") }
                .help("Add a magnet link (⇧⌘M)")
            Button { store.resume(selection) } label: { Label("Resume", systemImage: "play.fill") }
                .disabled(selection.isEmpty)
            Button { store.pause(selection) } label: { Label("Pause", systemImage: "pause.fill") }
                .disabled(selection.isEmpty)
            Button { askRemove(selection) } label: { Label("Remove", systemImage: "trash") }
                .disabled(selection.isEmpty)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            Text("\(store.torrents.count) torrents")
            Spacer()
            Label(Format.rate(store.totalDownloadRate), systemImage: "arrow.down")
            Label(Format.rate(store.totalUploadRate), systemImage: "arrow.up")
            Label("DHT \(store.dhtNodes)", systemImage: "point.3.connected.trianglepath.dotted")
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }
}

struct AddMagnetSheet: View {
    @ObservedObject var store: TorrentStore
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Magnet Link").font(.headline)
            TextField("magnet:?xt=urn:btih:…", text: $link, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
            Text("Downloads to \(store.downloadDirectory)")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") {
                    for line in link.split(whereSeparator: \.isNewline) { store.addMagnet(String(line)) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!link.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("magnet:"))
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            if let clip = NSPasteboard.general.string(forType: .string), clip.lowercased().hasPrefix("magnet:") {
                link = clip
            }
        }
    }
}
