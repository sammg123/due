import SwiftUI
import DueCore

/// The note list: flat when sorted by date/name, grouped under course headers when sorted
/// by class. Courses reuse the exact tag colors from the assignment list.
struct NotesSidebar: View {
    @Environment(AppState.self) private var appState
    @Environment(NotesState.self) private var notes
    @Environment(LectureEngine.self) private var engine
    let sort: NoteSort
    let search: String
    @Binding var selection: UUID?

    @State private var pendingDelete: Note?

    private var filtered: [Note] { NotesLogic.filter(notes.notes, course: nil, search: search) }

    var body: some View {
        List(selection: $selection) {
            if sort == .course {
                ForEach(NotesLogic.groupedByCourse(filtered)) { group in
                    Section {
                        rows(group.notes)
                    } header: {
                        courseHeader(group.course)
                    }
                }
            } else {
                rows(NotesLogic.sort(filtered, by: sort))
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if filtered.isEmpty, !search.isEmpty {
                Text("No notes match “\(search)”")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .confirmationDialog(
            "Delete “\(pendingDelete?.displayTitle ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
        ) {
            Button("Delete Note", role: .destructive) {
                if let note = pendingDelete { notes.deleteNote(note.id) }
                pendingDelete = nil
            }
        } message: {
            Text(deleteMessage)
        }
    }

    private var deleteMessage: String {
        guard let note = pendingDelete, !note.audioFiles.isEmpty else { return "This can't be undone." }
        return "Its \(note.audioFiles.count == 1 ? "recording" : "\(note.audioFiles.count) recordings") will be deleted too. This can't be undone."
    }

    private func rows(_ items: [Note]) -> some View {
        ForEach(items) { note in
            NoteListRow(note: note, isCapturing: engine.isCapturing(note.id))
                .tag(note.id)
                .contextMenu {
                    // Deleting the note a lecture is recording into would orphan the mic
                    // session (its only Stop controls live on that note's editor).
                    if engine.isCapturing(note.id) {
                        Button("Stop the recording before deleting") {}
                            .disabled(true)
                    } else {
                        Button("Delete…", role: .destructive) { pendingDelete = note }
                    }
                }
        }
    }

    private func courseHeader(_ course: String?) -> some View {
        HStack(spacing: 6) {
            if let course {
                Circle()
                    .fill(Theme.color(appState.color(forCourse: course)))
                    .frame(width: 8, height: 8)
                Text(course)
            } else {
                Text("No class")
            }
        }
        .font(.caption.weight(.semibold))
    }
}

/// One sidebar row: title, two-line preview, then course tag / lecture badge / edited date.
struct NoteListRow: View {
    let note: Note
    let isCapturing: Bool
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                if isCapturing {
                    Circle()
                        .fill(.red)
                        .frame(width: 7, height: 7)
                        .accessibilityLabel("Recording")
                }
                Text(note.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            if !note.preview.isEmpty {
                Text(note.preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                if let course = note.course {
                    Text(course)
                        .font(.caption2)
                        .padding(.vertical, 1)
                        .padding(.horizontal, 5)
                        .background(Theme.color(appState.color(forCourse: course)).opacity(0.18), in: Capsule())
                        .foregroundStyle(Theme.color(appState.color(forCourse: course)))
                }
                if note.lectureSeconds > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "waveform")
                        Text(NoteDates.lectureLabel(seconds: note.lectureSeconds))
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text(NoteDates.editedLabel(note.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}

/// Compact date/duration labels for note rows and the editor's metadata line.
enum NoteDates {
    static func editedLabel(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return timeFormatter.string(from: date)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return (sameYear ? dayFormatter : dayYearFormatter).string(from: date)
    }

    static func lectureLabel(seconds: Int) -> String {
        let minutes = max(1, seconds / 60)
        guard minutes >= 60 else { return "\(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let dayYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()
}
