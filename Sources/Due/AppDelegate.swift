import AppKit
import DueCore

/// Owns the state the whole app shares, so the `due://` links the desktop widget opens and the
/// SwiftUI scenes act on the same `AppState`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// About two seconds of 0.2s retries for `due://open` arriving during launch.
    private static let openRetries = 10

    let state = AppState.loadFromDisk()
    /// Opens the Notes window. SwiftUI only hands out `openWindow` to views, so the menu bar
    /// label installs it when it appears; a `due://notes` that arrives first waits for it.
    let notesOpener = DeferredAction()
    private lazy var quickAddPanel = QuickAddPanel(state: state)
    private var dataWatcher: DataFileWatcher?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Take `due://` links before AppKit hands them to SwiftUI, which answers any URL by
        // also opening the first window scene (Notes) on top of whatever the link asked for.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The widget's checkboxes write assignments.json directly; adopt those edits live.
        dataWatcher = DataFileWatcher(fileURL: JSONStore.defaultURL()) { [weak self] in
            self?.state.reloadFromDisk()
        }
        // Catch a widget edit that landed between loading the state and starting the watcher.
        state.reloadFromDisk()
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: text) else {
            NSLog("Due: ignoring a link event with no URL")
            return
        }
        handle(url)
    }

    private func handle(_ url: URL) {
        switch DueLink(url: url) {
        case .add:
            quickAddPanel.show()
        case .open:
            StatusItem.click(retries: Self.openRetries)
        case .notes:
            notesOpener.run()
        case nil:
            NSLog("Due: ignoring unrecognized link \(url.absoluteString)")
        }
    }
}
