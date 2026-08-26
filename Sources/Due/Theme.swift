import SwiftUI
import DueCore

/// Maps the persisted palette onto system colors so light/dark mode is automatic.
enum Theme {
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

    // Layout constants (8pt grid).
    static let popoverWidth: CGFloat = 340
    static let popoverMaxHeight: CGFloat = 560
    static let urgencyBarWidth: CGFloat = 3
    static let rowCornerRadius: CGFloat = 8
    /// The MenuBarExtra window sizes to content and `List` has no intrinsic height, so the
    /// popover computes the list height from these measured row/header sizes.
    static let rowHeight: CGFloat = 47
    static let sectionHeaderHeight: CGFloat = 30
    static let statsLineHeight: CGFloat = 20
    static let emptyStateHeight: CGFloat = 88
    static let listMaxHeight: CGFloat = 360
    static let animationFast: Double = 0.15
    static let animationBase: Double = 0.3
}
