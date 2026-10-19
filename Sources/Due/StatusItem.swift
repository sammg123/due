import AppKit

/// The menu bar icon. Clicking it programmatically opens the popover without Accessibility access.
enum StatusItem {
    private static let retryDelay: TimeInterval = 0.2

    /// `retries` covers a cold launch from the widget, when the link can arrive before SwiftUI
    /// has created the menu bar item.
    static func click(retries: Int = 0) {
        guard let button = findButton() else {
            if retries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { click(retries: retries - 1) }
            } else {
                NSLog("Due: status bar button not found")
            }
            return
        }
        button.performClick(nil)
    }

    private static func findButton() -> NSStatusBarButton? {
        NSApp.windows
            .filter { $0.className.contains("StatusBar") }
            .flatMap { $0.contentView.map(allSubviews) ?? [] }
            .compactMap { $0 as? NSStatusBarButton }
            .first
    }

    private static func allSubviews(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(allSubviews)
    }
}
