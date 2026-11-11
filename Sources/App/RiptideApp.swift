import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = TorrentStore()

    func application(_ application: NSApplication, open urls: [URL]) {
        store.open(urls)
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct RiptideApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Riptide", id: "main") {
            ContentView(store: delegate.store)
        }
        .defaultSize(width: 1100, height: 650)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Torrent File…") { delegate.store.showFileImporter = true }
                    .keyboardShortcut("o")
                Button("Add Magnet Link…") { delegate.store.showMagnetSheet = true }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView(store: delegate.store)
        }
    }
}
