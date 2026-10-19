import SwiftUI
import DueCore

/// App-wide colors and layout constants. Colors live in `PaletteStyle`, shared with the widget.
enum Theme {
    static func color(_ p: PaletteColor) -> Color { PaletteStyle.color(p) }
    static func color(_ bucket: DueBucket) -> Color { PaletteStyle.color(bucket) }
    static func textColor(_ bucket: DueBucket) -> Color { PaletteStyle.textColor(bucket) }

    // Layout constants (8pt grid).
    static let popoverWidth: CGFloat = 440
    static let popoverMaxHeight: CGFloat = 760
    static let urgencyBarWidth: CGFloat = 3
    static let rowCornerRadius: CGFloat = 8
    /// The MenuBarExtra window sizes to content and `List` has no intrinsic height, so the
    /// popover computes the list height from these measured row/header sizes.
    static let rowHeight: CGFloat = 50
    /// Added per extra wrapped title line (titles wrap to at most 2 lines).
    static let extraTitleLineHeight: CGFloat = 18
    /// Rough characters per title line at `popoverWidth`, used only for the height estimate.
    static let titleCharsPerLine = 42
    static let sectionHeaderHeight: CGFloat = 30
    static let statsLineHeight: CGFloat = 20
    static let emptyStateHeight: CGFloat = 88
    static let listMaxHeight: CGFloat = 440
    static let animationFast: Double = 0.15
    static let animationBase: Double = 0.3

    // Notes window (same 8pt grid as the popover).
    static let notesMinWidth: CGFloat = 640
    static let notesMinHeight: CGFloat = 420
    static let notesDefaultWidth: CGFloat = 820
    static let notesDefaultHeight: CGFloat = 580
    static let notesSidebarMinWidth: CGFloat = 220
    static let notesSidebarIdealWidth: CGFloat = 260
    static let notesSidebarMaxWidth: CGFloat = 340
    static let notesEditorInset: CGFloat = 20
}

extension Theme {
    private static var swatchCache: [String: NSImage] = [:]

    /// A filled-circle bitmap for AppKit menus. SwiftUI shapes are dropped from menu labels and
    /// SF Symbols become monochrome template images there, so menus need a real non-template image.
    static func swatch(_ palette: PaletteColor, diameter: CGFloat = 12) -> NSImage {
        let key = "\(palette.rawValue)-\(diameter)"
        if let cached = swatchCache[key] { return cached }
        let image = NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            NSColor(color(palette)).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        image.isTemplate = false
        swatchCache[key] = image
        return image
    }
}
