import AppKit
import SwiftUI

enum Theme {
    /// Brand colors, matching the app icon gradient. `deep` lightens in dark mode for contrast.
    static let deep = Color(nsColor: NSColor(name: "RiptideDeep") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0x4C / 255, green: 0x9D / 255, blue: 0xFF / 255, alpha: 1)
            : NSColor(srgbRed: 0x13 / 255, green: 0x51 / 255, blue: 0xB4 / 255, alpha: 1)
    })
    static let aqua = Color(red: 0x1F / 255, green: 0xB8 / 255, blue: 0xCD / 255)
    static let gradient = LinearGradient(colors: [deep, aqua], startPoint: .leading, endPoint: .trailing)

    static func color(for state: String) -> Color {
        switch state {
        case "Downloading": deep
        case "Seeding": .green
        case "Queued": .orange
        case "Checking": .yellow
        case "Metadata": .purple
        case "Error": .red
        default: .secondary
        }
    }

    static func icon(for state: String) -> String {
        switch state {
        case "Downloading": "arrow.down.circle.fill"
        case "Seeding": "arrow.up.circle.fill"
        case "Paused": "pause.circle.fill"
        case "Queued": "clock.fill"
        case "Checking": "checkmark.circle.fill"
        case "Metadata": "magnifyingglass.circle.fill"
        case "Error": "exclamationmark.triangle.fill"
        default: "circle"
        }
    }

    static func sidebarIcon(for state: String) -> String {
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
}

/// Slim rounded progress bar in the state's color.
struct SlimProgress: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(color.gradient)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: 5)
        .animation(.easeOut(duration: 0.4), value: value)
    }
}

/// Circular progress used in the inspector header.
struct ProgressRing: View {
    let value: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 7)
            Circle()
                .trim(from: 0, to: max(0, min(1, value)))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(Format.percent(value))
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .monospacedDigit()
        }
        .frame(width: 72, height: 72)
        .animation(.easeOut(duration: 0.4), value: value)
    }
}

extension Torrent {
    var stateColor: Color { Theme.color(for: state) }

    /// "350 MB of 735 MB · 3m left · 22 peers"
    var summaryLine: String {
        var parts: [String] = []
        switch state {
        case "Metadata":
            parts.append("Fetching torrent info from peers")
        case "Seeding":
            parts.append(Format.bytes(totalWanted))
            parts.append("ratio \(String(format: "%.2f", ratio))")
        case "Error":
            parts.append(errorMessage.isEmpty ? "Error" : errorMessage)
        default:
            parts.append("\(Format.bytes(totalWantedDone)) of \(Format.bytes(totalWanted))")
            if state == "Downloading", let eta { parts.append("\(Format.eta(eta)) left") }
        }
        if peers > 0 && state != "Paused" { parts.append("\(peers) peer\(peers == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
}
