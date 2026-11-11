import AppKit
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
    @State private var showInspector = true
    @State private var isDropTargeted = false

    private static let primaryStates = ["Downloading", "Seeding", "Paused"]
    private static let otherStates = ["Queued", "Checking", "Metadata", "Error"]
    private static let torrentType = UTType(filenameExtension: "torrent") ?? .data

    private var rows: [Torrent] {
        store.filtered(sidebar: sidebar ?? .all, query: query).sorted(using: sortOrder)
    }

    private var selectedTorrents: [Torrent] { store.torrents.filter { selection.contains($0.id) } }

    var body: some View {
        NavigationSplitView {
            sidebarList
                .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            torrentList
                .inspector(isPresented: $showInspector) {
                    InspectorView(store: store, torrent: selectedTorrents.count == 1 ? selectedTorrents.first : nil,
                                  selectionCount: selection.count)
                        .inspectorColumnWidth(min: 280, ideal: 320, max: 440)
                }
        }
        .navigationTitle(navigationTitle)
        .navigationSubtitle(navigationSubtitle)
        .searchable(text: $query, placement: .toolbar, prompt: "Search torrents")
        .toolbar { toolbarContent }
        .tint(Theme.deep)
        .fileImporter(isPresented: $store.showFileImporter, allowedContentTypes: [Self.torrentType],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { store.open(urls) }
        }
        .sheet(isPresented: $store.showMagnetSheet) { AddMagnetSheet(store: store) }
        .confirmationDialog(removeTitle, isPresented: $confirmRemove) {
            Button("Remove from List") { store.remove(pendingRemoval, deleteFiles: false); selection.subtract(pendingRemoval) }
            Button("Remove and Delete Files", role: .destructive) {
                store.remove(pendingRemoval, deleteFiles: true); selection.subtract(pendingRemoval)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deleting files removes the downloaded data from disk. This can't be undone.")
        }
        .alert("Couldn't add torrent", isPresented: Binding(get: { store.lastError != nil },
                                                           set: { if !$0 { store.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(store.lastError ?? "") }
    }

    private var navigationTitle: String {
        switch sidebar ?? .all {
        case .all: "All Torrents"
        case .state(let s): s
        case .tracker(let host): host
        }
    }

    private var navigationSubtitle: String {
        let n = rows.count
        return query.isEmpty ? "\(n) torrent\(n == 1 ? "" : "s")" : "\(n) match\(n == 1 ? "" : "es")"
    }

    private var removeTitle: String {
        pendingRemoval.count == 1 ? "Remove this torrent?" : "Remove \(pendingRemoval.count) torrents?"
    }

    private func askRemove(_ ids: Set<Torrent.ID>) {
        guard !ids.isEmpty else { return }
        pendingRemoval = ids
        confirmRemove = true
    }

    // MARK: Sidebar

    private var sidebarList: some View {
        List(selection: $sidebar) {
            Section("Library") {
                sidebarRow("All Torrents", icon: "tray.full", tint: Theme.deep, item: .all)
                ForEach(Self.primaryStates, id: \.self) { s in
                    sidebarRow(s, icon: Theme.sidebarIcon(for: s), tint: Theme.color(for: s), item: .state(s))
                }
                ForEach(Self.otherStates.filter { store.count(.state($0)) > 0 }, id: \.self) { s in
                    sidebarRow(s, icon: Theme.sidebarIcon(for: s), tint: Theme.color(for: s), item: .state(s))
                }
            }
            if !store.trackerHosts.isEmpty {
                Section("Trackers") {
                    ForEach(store.trackerHosts, id: \.self) { host in
                        sidebarRow(host, icon: "globe", tint: .secondary, item: .tracker(host))
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { transferSummary }
    }

    private func sidebarRow(_ title: String, icon: String, tint: Color, item: SidebarItem) -> some View {
        let n = store.count(item)
        return Label { Text(title).lineLimit(1) } icon: { Image(systemName: icon).foregroundStyle(tint) }
            .badge(n > 0 ? Text("\(n)") : nil)
            .tag(item)
    }

    private var transferSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(Format.rate(store.totalDownloadRate), systemImage: "arrow.down")
                    .foregroundStyle(store.totalDownloadRate > 0 ? Theme.deep : .secondary)
                Spacer()
                Label(Format.rate(store.totalUploadRate), systemImage: "arrow.up")
                    .foregroundStyle(store.totalUploadRate > 0 ? .green : .secondary)
            }
            .font(.callout.weight(.medium))
            HStack(spacing: 4) {
                Circle().fill(store.dhtNodes > 0 ? Color.green : Color.orange).frame(width: 6, height: 6)
                Text(store.dhtNodes > 0 ? "Connected · \(store.dhtNodes) DHT nodes" : "Connecting…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .monospacedDigit()
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(10)
    }

    // MARK: Torrent list

    private var torrentList: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { t in TorrentNameCell(torrent: t) }
                .width(min: 260, ideal: 420)
            TableColumn("Progress", value: \.progress) { t in ProgressCell(torrent: t) }
            .width(min: 110, ideal: 150)
            TableColumn("Speed", value: \.downloadRate) { t in SpeedCell(torrent: t) }
                .width(min: 90, ideal: 110)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .contextMenu(forSelectionType: Torrent.ID.self) { ids in
            Button("Resume", systemImage: "play.fill") { store.resume(ids) }
            Button("Pause", systemImage: "pause.fill") { store.pause(ids) }
            Divider()
            Button("Show in Finder", systemImage: "folder") { store.reveal(ids) }
            Button("Copy Magnet Link", systemImage: "link") { store.copyMagnet(ids) }
            Button("Verify Data", systemImage: "checkmark.shield") { store.recheck(ids) }
            Divider()
            Button("Remove…", systemImage: "trash", role: .destructive) { askRemove(ids) }
        } primaryAction: { ids in
            store.reveal(ids)
        }
        .onDeleteCommand { askRemove(selection) }
        .overlay {
            if store.torrents.isEmpty {
                EmptyLibraryView(store: store)
            } else if rows.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Theme.aqua, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .background(Theme.aqua.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .overlay { Label("Drop to add", systemImage: "arrow.down.doc").font(.title2.weight(.semibold)) }
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let torrents = urls.filter { $0.pathExtension.lowercased() == "torrent" || $0.scheme == "magnet" }
            store.open(torrents)
            return !torrents.isEmpty
        } isTargeted: { isDropTargeted = $0 }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Menu {
                Button("Open Torrent File…", systemImage: "doc") { store.showFileImporter = true }
                    .keyboardShortcut("o")
                Button("Add Magnet Link…", systemImage: "link") { store.showMagnetSheet = true }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
            } label: {
                Label("Add", systemImage: "plus")
            }
            .help("Add a torrent")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            ControlGroup {
                Button { store.resume(selection) } label: { Label("Resume", systemImage: "play.fill") }
                    .help("Resume")
                Button { store.pause(selection) } label: { Label("Pause", systemImage: "pause.fill") }
                    .help("Pause")
            }
            .disabled(selection.isEmpty)
            Button { askRemove(selection) } label: { Label("Remove", systemImage: "trash") }
                .help("Remove")
                .disabled(selection.isEmpty)
            Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.right") }
                .help(showInspector ? "Hide details" : "Show details")
        }
    }
}

// MARK: - Cells

struct TorrentNameCell: View {
    let torrent: Torrent
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        let selected = prominence == .increased
        HStack(spacing: 10) {
            Image(systemName: Theme.icon(for: torrent.state))
                .font(.title2)
                .foregroundStyle(selected ? .white : torrent.stateColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(torrent.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(torrent.summaryLine)
                    .font(.caption)
                    .foregroundStyle(torrent.state == "Error" && !selected ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
        .help(torrent.name)
    }
}

struct ProgressCell: View {
    let torrent: Torrent
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            SlimProgress(value: torrent.progress, color: prominence == .increased ? .white : torrent.stateColor)
            Text(Format.percent(torrent.progress)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}

struct SpeedCell: View {
    let torrent: Torrent
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        let selected = prominence == .increased
        VStack(alignment: .leading, spacing: 2) {
            if torrent.downloadRate > 0 {
                Label(Format.rate(torrent.downloadRate), systemImage: "arrow.down")
                    .foregroundStyle(selected ? .white : Theme.deep)
            }
            if torrent.uploadRate > 0 {
                Label(Format.rate(torrent.uploadRate), systemImage: "arrow.up")
                    .foregroundStyle(selected ? .white : .green)
            }
            if torrent.downloadRate == 0 && torrent.uploadRate == 0 {
                Text("–").foregroundStyle(.tertiary)
            }
        }
        .font(.caption.weight(.medium))
        .labelStyle(.titleAndIcon)
        .monospacedDigit()
    }
}

// MARK: - Empty state & magnet sheet

struct EmptyLibraryView: View {
    @ObservedObject var store: TorrentStore

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            Text("Welcome to Riptide").font(.title2.weight(.semibold))
            Text("Drop a .torrent file here, or add one to start downloading.")
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button { store.showFileImporter = true } label: {
                    Label("Open Torrent File", systemImage: "doc").padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                Button { store.showMagnetSheet = true } label: {
                    Label("Add Magnet Link", systemImage: "link").padding(.horizontal, 4)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
        .padding(40)
    }
}

struct AddMagnetSheet: View {
    @ObservedObject var store: TorrentStore
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""

    private var isValid: Bool { link.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("magnet:") }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.gradient)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Magnet Link").font(.title3.weight(.semibold))
                    Text("Paste one link per line.").font(.callout).foregroundStyle(.secondary)
                }
            }
            TextField("magnet:?xt=urn:btih:…", text: $link, axis: .vertical)
                .lineLimit(4...8)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            Label(store.downloadDirectory, systemImage: "folder")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") {
                    for line in link.split(whereSeparator: \.isNewline) { store.addMagnet(String(line)) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 540)
        .tint(Theme.deep)
        .onAppear {
            if let clip = NSPasteboard.general.string(forType: .string), clip.lowercased().hasPrefix("magnet:") {
                link = clip
            }
        }
    }
}
