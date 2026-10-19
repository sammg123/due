import AppIntents
import DueCore

/// The widget's checkbox. Runs inside the widget process and writes assignments.json directly,
/// so it works even when Due is not running; the app picks the change up from disk.
struct ToggleDoneIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Assignment Done"
    static let isDiscoverable = false

    @Parameter(title: "Assignment")
    var assignmentID: String

    init() {}

    init(id: UUID) {
        assignmentID = id.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: assignmentID) else {
            throw ToggleDoneError.invalidID(assignmentID)
        }
        let state = AppState.loadFromDisk()
        if let error = state.lastError { throw ToggleDoneError.storage(error) }
        guard state.assignments.contains(where: { $0.id == id }) else {
            throw ToggleDoneError.invalidID(assignmentID)
        }
        state.toggleDone(id)
        if let error = state.lastError { throw ToggleDoneError.storage(error) }
        return .result()
    }
}

enum ToggleDoneError: Error, CustomLocalizedStringResourceConvertible {
    case invalidID(String)
    case storage(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidID: return "That assignment no longer exists."
        case .storage(let message): return "Due couldn't save: \(message)"
        }
    }
}
