import AppIntents
import AppKit
import DueCore
import os

/// The small widget's Notes icon. Runs in the widget process and hands `due://notes` to the app.
struct OpenNotesIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Notes"
    static let isDiscoverable = false

    private static let log = Logger(subsystem: "com.due.tracker.widget", category: "OpenNotesIntent")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        guard NSWorkspace.shared.open(DueLink.notes.url) else {
            Self.log.error("Could not open \(DueLink.notes.url.absoluteString, privacy: .public)")
            throw OpenNotesError.couldNotOpen
        }
        return .result()
    }
}

enum OpenNotesError: Error, CustomLocalizedStringResourceConvertible {
    case couldNotOpen

    var localizedStringResource: LocalizedStringResource { "Due could not open Notes." }
}
