import AppKit
import DueCore

/// Owns the state the whole app shares, so the `due://` links the desktop widget opens and the
/// SwiftUI scenes act on the same `AppState`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// About two seconds of 0.2s retries for `due://open` arriving during launch.
    private static let openRetries = 10

    let state = AppState.loadFromDisk()
    private lazy var quickAddPanel = QuickAddPanel(state: state)
    private var dataWatcher: DataFileWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The widget's checkboxes write assignments.json directly; adopt those edits live.
        dataWatcher = DataFileWatcher(fileURL: JSONStore.defaultURL()) { [weak self] in
            self?.state.reloadFromDisk()
        }
        // Catch a widget edit that landed between loading the state and starting the watcher.
        state.reloadFromDisk()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(handle)
    }

    private func handle(_ url: URL) {
        switch DueLink(url: url) {
        case .add:
            quickAddPanel.show()
        case .open:
            StatusItem.click(retries: Self.openRetries)
        case nil:
            NSLog("Due: ignoring unrecognized link \(url.absoluteString)")
        }
    }
}
