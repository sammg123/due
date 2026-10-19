import SwiftUI
import AppKit
import DueCore

/// Palette and urgency colors. Compiled into both the app and the desktop widget
/// (Widget/project.yml lists this folder) so the two always agree.
enum PaletteStyle {
    /// Maps the persisted palette onto system colors so light/dark mode is automatic.
    static func color(_ p: PaletteColor) -> Color {
        switch p {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        case .cyan: return .cyan
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .brown: return .brown
        case .gray: return .secondary
        }
    }

    static func color(_ bucket: DueBucket) -> Color { color(bucket.paletteColor) }

    /// Bucket color for TEXT. Yellow on a light background fails contrast, so "Soon" text uses
    /// amber in light mode and stays yellow in dark mode. Bars and dots keep `color(_:)`.
    static func textColor(_ bucket: DueBucket) -> Color {
        guard bucket == .soon else { return color(bucket) }
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? .systemYellow : NSColor(red: 0.62, green: 0.44, blue: 0.0, alpha: 1)
        })
    }
}
