import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: TorrentStore

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            BandwidthSettings(store: store)
                .tabItem { Label("Bandwidth", systemImage: "speedometer") }
            NetworkSettings(store: store)
                .tabItem { Label("Network", systemImage: "network") }
        }
        .frame(width: 500)
        .tint(Theme.deep)
    }
}

private struct GeneralSettings: View {
    @AppStorage(Prefs.downloadDirectory) private var downloadDirectory = ""

    var body: some View {
        Form {
            LabeledContent("Save downloads to") {
                HStack {
                    Label((downloadDirectory as NSString).lastPathComponent, systemImage: "folder.fill")
                        .help(downloadDirectory)
                    Button("Change…", action: chooseFolder)
                }
            }
            Text(downloadDirectory).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: downloadDirectory)
        if panel.runModal() == .OK, let url = panel.url { downloadDirectory = url.path }
    }
}

private struct BandwidthSettings: View {
    @ObservedObject var store: TorrentStore
    @AppStorage(Prefs.downloadLimitKiB) private var downloadLimit = 0
    @AppStorage(Prefs.uploadLimitKiB) private var uploadLimit = 0

    var body: some View {
        Form {
            Section {
                LimitField(title: "Download limit", icon: "arrow.down", value: $downloadLimit)
                LimitField(title: "Upload limit", icon: "arrow.up", value: $uploadLimit)
            } footer: {
                Text("In KiB/s. Leave at 0 for unlimited.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: downloadLimit) { _, _ in store.applyLimits() }
        .onChange(of: uploadLimit) { _, _ in store.applyLimits() }
    }
}

private struct LimitField: View {
    let title: String
    let icon: String
    @Binding var value: Int

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                TextField("", value: $value, format: .number).frame(width: 90).multilineTextAlignment(.trailing)
                Text(value == 0 ? "unlimited" : "KiB/s").foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
            }
        } label: { Label(title, systemImage: icon) }
    }
}

private struct NetworkSettings: View {
    @ObservedObject var store: TorrentStore
    @AppStorage(Prefs.listenPort) private var listenPort = 6881

    var body: some View {
        Form {
            Section {
                LabeledContent("Listening port") {
                    TextField("", value: $listenPort, format: .number.grouping(.never))
                        .frame(width: 90).multilineTextAlignment(.trailing)
                }
            } footer: {
                Text("DHT, peer exchange, local peer discovery, UPnP and NAT-PMP are on.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Status") {
                LabeledContent("DHT nodes", value: "\(store.dhtNodes)")
            }
        }
        .formStyle(.grouped)
        .onChange(of: listenPort) { _, _ in store.applyListenPort() }
    }
}
