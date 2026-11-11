# Riptide

A native macOS BitTorrent client built on **libtorrent-rasterbar 2.1** (the engine
Deluge uses), with Deluge-style search from `../item-search`.

## Features

- Open `.torrent` files (⌘O, drag and drop, or double-click in Finder via "Open With")
  and magnet links (⇧⌘M, or clicking a `magnet:` link in a browser)
- Trackers, DHT, peer exchange, local peer discovery, UPnP/NAT-PMP, web seeds
- Clean two-line torrent list (state icon, name, "350 MB of 735 MB · 1m left · 49 peers"),
  slim progress bars and live speeds — sortable
- Inspector panel (toggle with the toolbar button): progress ring, pause/resume, stat tiles,
  Info / Files / Peers / Trackers tabs
- Sidebar filters by **state** and by **tracker**, with counts (like Deluge's filter tree),
  plus a live transfer summary and DHT connection status
- **Search**: comma-separated keywords, all must match; each matches name, state, any
  tracker URL, info-hash, tracker status, error or any file path
- Pause / resume / force recheck / remove (optionally deleting data), Show in Finder,
  copy magnet link; multi-select and right-click menu
- Detail pane: overview, files with per-file priority (skip / normal / high), trackers, peers
- Settings (⌘,): download folder, download/upload limits, listening port
- Remembers every torrent and its progress across restarts (libtorrent resume data,
  saved every 2 minutes, on completion and on quit) plus the DHT routing table

## Build and run

Requires macOS 26, the Xcode Command Line Tools, and Homebrew:

```bash
brew install libtorrent-rasterbar dylibbundler
./build.sh                 # search tests + build/Riptide.app (libraries bundled inside)
open build/Riptide.app
./test-live.sh             # optional: live download/pause/resume/remove test (needs network)
```

To redraw the icon after editing `Resources/Icon/make_icon.swift`:

```bash
swift Resources/Icon/make_icon.swift /tmp/icon.png 1024 && mkdir -p /tmp/AppIcon.iconset && \
for s in 16 32 128 256 512; do sips -z $s $s /tmp/icon.png --out /tmp/AppIcon.iconset/icon_${s}x${s}.png; \
sips -z $((s*2)) $((s*2)) /tmp/icon.png --out /tmp/AppIcon.iconset/icon_${s}x${s}@2x.png; done && \
iconutil -c icns /tmp/AppIcon.iconset -o Resources/AppIcon.icns
```

## Versions

- `v1.0` (tag, branch `main`): first release, table-based UI
- `v2.0` (tag, branch `v2-redesign`): logo, cleaner UI, inspector
- Built apps are archived in `releases/` (not in git)

## Layout

| Path | What |
|---|---|
| `Sources/Bridge/TorrentBridge.{h,mm}` | Objective-C++ wrapper around libtorrent |
| `Sources/App/TorrentStore.swift` | Polls the session every second, actions, settings |
| `Sources/App/Search.swift` | Keyword search and type-ahead (Deluge design, quirks fixed) |
| `Sources/App/ContentView.swift`, `DetailView.swift` | SwiftUI interface |
| `Sources/App/InspectorView.swift`, `SettingsView.swift`, `Theme.swift` | Inspector, tabbed settings, brand colors |
| `Resources/Info.plist` | `.torrent` file type and `magnet:` URL scheme |
| `Resources/AppIcon.icns`, `Resources/Icon/` | App icon and the Core Graphics script that draws it |
| `Tests/Search`, `Tests/Bridge` | Search unit tests, live libtorrent smoke test |

App data lives in `~/Library/Application Support/Riptide/state` (one `.resume` file per
torrent plus `session.state`).

## Notes

- The app is signed ad hoc (no developer certificate). It runs on this Mac; another Mac
  will show a Gatekeeper warning the first time.
- Riptide registers as an *alternate* handler for `.torrent` files, so it won't take over
  from another torrent app unless you choose it in Finder → Get Info → Open with.
- Only download content you have the right to share.
