import SwiftUI
import AppKit
import DueCore

/// The Notes window: sidebar of notes (searchable, sorted by class, date, or name) and the
/// editor. Lives in its own window because a 440pt menu bar popover is no place to write.
struct NotesWindowView: View {
    @Environment(AppState.self) private var appState
    @Environment(NotesState.self) private var notes
    @Environment(LectureEngine.self) private var engine
    @AppStorage("notesSort") private var sortRaw = NoteSort.dateEdited.rawValue
    @State private var search = ""

    private var sort: NoteSort { NoteSort(rawValue: sortRaw) ?? .dateEdited }

    var body: some View {
        @Bindable var notes = notes
        NavigationSplitView {
            NotesSidebar(sort: sort, search: search, selection: $notes.selectedNoteID)
                .navigationSplitViewColumnWidth(
                    min: Theme.notesSidebarMinWidth,
                    ideal: Theme.notesSidebarIdealWidth,
                    max: Theme.notesSidebarMaxWidth
                )
        } detail: {
            if let note = notes.note(notes.selectedNoteID) {
                NoteEditorView(noteID: note.id)
                    .id(note.id) // reset editor-local state (AI revert, focus) when switching notes
            } else {
                noNoteSelected
            }
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Search notes")
        .navigationTitle("Notes")
        .frame(minWidth: Theme.notesMinWidth, minHeight: Theme.notesMinHeight)
        .toolbar {
            ToolbarItem(placement: .automatic) { sortMenu }
            ToolbarItem(placement: .primaryAction) { newNoteButton }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let error = notes.lastError {
                errorBanner(error)
            }
        }
        // Land in the note that was last worked on instead of an empty pane.
        .onAppear {
            if notes.selectedNoteID == nil {
                notes.selectedNoteID = NotesLogic.sort(notes.notes, by: .dateEdited).first?.id
            }
        }
        // Debounced autosaves must reach disk when the window goes away or the app quits.
        .onDisappear { notes.flushPendingSaves() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            notes.flushPendingSaves()
        }
    }

    private var newNoteButton: some View {
        Button {
            notes.createNote(course: nil)
        } label: {
            Image(systemName: "square.and.pencil")
        }
        .keyboardShortcut("n")
        .help("New note (⌘N)")
        .accessibilityLabel("New note")
    }

    private var sortMenu: some View {
        Menu {
            ForEach(NoteSort.allCases, id: \.self) { option in
                Button {
                    sortRaw = option.rawValue
                } label: {
                    if option == sort {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .help("Sort notes by class, date, or name")
        .accessibilityLabel("Sort notes")
    }

    private var noNoteSelected: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 36))
                .foregroundStyle(.quaternary)
            Text(notes.notes.isEmpty ? "No notes yet" : "Select a note")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(notes.notes.isEmpty
                ? "Write class notes, record a lecture, and let the on-device model tidy them up."
                : "Pick a note from the sidebar, or start a new one.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button("New Note") { notes.createNote(course: nil) }
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button {
                notes.clearError()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red.opacity(0.8))
            .help("Dismiss error")
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
