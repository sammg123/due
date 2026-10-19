import AppKit
import SwiftUI
import DueCore

/// The quick-add box the desktop widget's + opens. Spotlight-style: it floats in the upper part
/// of the screen under the pointer, takes the keyboard, and closes after an add, on Escape, or
/// when you click anywhere else.
@MainActor
final class QuickAddPanel: NSObject, NSWindowDelegate {
    /// Fraction of the screen height between the top of the visible area and the box.
    private static let topOffsetFraction: CGFloat = 0.2

    private let state: AppState
    private var panel: NSPanel?
    /// The app that was in front when the box opened; it gets the keyboard back afterwards.
    private var previousApp: NSRunningApplication?

    init(state: AppState) {
        self.state = state
    }

    func show() {
        if let panel, panel.isVisible {
            // Already open: keep whatever is typed and just bring it forward.
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        let panel = self.panel ?? makePanel()
        self.panel = panel
        // Fresh content each time, so a reopened box starts empty with its default due date.
        let root = QuickAddPanelView(onClose: { [weak self] in self?.dismiss() }).environment(state)
        let host = NSHostingController(rootView: root)
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        panel.setContentSize(host.view.fittingSize)
        place(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Escape or a successful add: close and hand the keyboard back to where the user was.
    private func dismiss() {
        panel?.orderOut(nil)
        previousApp?.activate()
        previousApp = nil
    }

    /// Clicking elsewhere already moved focus, so only hide.
    func windowDidResignKey(_ notification: Notification) {
        panel?.orderOut(nil)
        previousApp = nil
    }

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(
            contentRect: .zero,
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        return panel
    }

    private func place(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        guard let visible = (NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main)?.visibleFrame else {
            panel.center()
            return
        }
        let top = visible.maxY - visible.height * Self.topOffsetFraction
        panel.setFrameTopLeftPoint(NSPoint(x: visible.midX - panel.frame.width / 2, y: top))
    }
}

/// Borderless-looking panels still have to opt in to taking the keyboard.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct QuickAddPanelView: View {
    let onClose: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Add to Due", systemImage: "checklist")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            QuickAddBar(isFocused: $isFocused, onAdded: { _ in onClose() })
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(width: Theme.popoverWidth)
        // The titlebar is transparent and empty; without this SwiftUI adds its height on top.
        .ignoresSafeArea()
        .background(escapeButton)
    }

    private var escapeButton: some View {
        Button("", action: onClose)
            .keyboardShortcut(.escape, modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}
