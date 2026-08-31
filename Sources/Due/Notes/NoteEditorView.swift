import SwiftUI
import AppKit
import DueCore

/// The writing surface: title, class, body editor with debounced autosave, lecture capture,
/// and the on-device AI actions. Recreated per note via `.id(note.id)` in the window view.
struct NoteEditorView: View {
    let noteID: UUID
    @Environment(AppState.self) private var appState
    @Environment(NotesState.self) private var notes
    @Environment(LectureEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var ai = NoteAI()
    @State private var aiError: String?
    @State private var showNewCourseField = false
    @State private var newCourseText = ""
    @FocusState private var newCourseFocused: Bool

    private var note: Note? { notes.note(noteID) }

    var body: some View {
        if let note {
            content(note)
        } else {
            // The note was deleted while open; the window view clears the selection next pass.
            Color.clear
        }
    }

    private func content(_ note: Note) -> some View {
        VStack(spacing: 0) {
            header(note)
            if engine.isCapturing(note.id) || engine.warning != nil {
                RecorderBar()
            }
            Divider()
            TextEditor(text: bodyBinding)
                .font(.system(size: 14))
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, Theme.notesEditorInset - 5)
                .padding(.vertical, 8)
            Divider()
            statusBar(note)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) { recordButton(note) }
            ToolbarItem(placement: .automatic) { aiMenu(note) }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: Theme.animationBase), value: engine.isCapturing(note.id))
    }

    // MARK: - Header

    private func header(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Untitled", text: titleBinding)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .accessibilityLabel("Note title")

            HStack(spacing: 10) {
                courseMenu(note)
                Text("Edited \(NoteDates.editedLabel(note.updatedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if note.lectureSeconds > 0 {
                    recordingsMenu(note)
                }
                Spacer()
            }

            if showNewCourseField {
                newCourseField
            }
        }
        .padding(.horizontal, Theme.notesEditorInset)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func courseMenu(_ note: Note) -> some View {
        Menu {
            ForEach(appState.courses, id: \.self) { course in
                Button(course) { setCourse(course) }
            }
            if !appState.courses.isEmpty { Divider() }
            Button("None") { setCourse(nil) }
            Button("New course…") { showNewCourseField = true }
        } label: {
            if let course = note.course {
                Text(course)
                    .font(.caption)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 7)
                    .background(Theme.color(appState.color(forCourse: course)).opacity(0.18), in: Capsule())
                    .foregroundStyle(Theme.color(appState.color(forCourse: course)))
            } else {
                Text("Add class")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Class")
        .accessibilityLabel("Class")
    }

    private var newCourseField: some View {
        HStack(spacing: 6) {
            TextField("Course name", text: $newCourseText)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .frame(maxWidth: 200)
                .focused($newCourseFocused)
                .onSubmit(commitNewCourse)
                .onExitCommand { cancelNewCourse() }
            Button("Add", action: commitNewCourse)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.blue)
                .disabled(newCourseText.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", action: cancelNewCourse)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { newCourseFocused = true }
    }

    /// Registers through AppState so the course gets a color and shows up everywhere
    /// (assignments, settings, notes) with the same tag.
    private func commitNewCourse() {
        if let registered = appState.registerCourse(newCourseText) { setCourse(registered) }
        newCourseText = ""
        showNewCourseField = false
    }

    private func cancelNewCourse() {
        newCourseText = ""
        showNewCourseField = false
    }

    private func setCourse(_ course: String?) {
        notes.updateCourse(noteID, course: course)
        if let course { _ = appState.registerCourse(course) }
    }

    private func recordingsMenu(_ note: Note) -> some View {
        Menu {
            ForEach(note.audioFiles, id: \.self) { file in
                Button(file) { openRecording(file) }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "waveform")
                Text(NoteDates.lectureLabel(seconds: note.lectureSeconds))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Open a lecture recording")
        .accessibilityLabel("Lecture recordings")
    }

    private func openRecording(_ file: String) {
        guard let dir = notes.audioDirectory, NotesStore.isSafeAudioFileName(file) else { return }
        NSWorkspace.shared.open(dir.appendingPathComponent(file))
    }

    // MARK: - Bindings

    private var titleBinding: Binding<String> {
        Binding(
            get: { notes.note(noteID)?.title ?? "" },
            set: { notes.updateTitle(noteID, title: $0) }
        )
    }

    private var bodyBinding: Binding<String> {
        Binding(
            get: { notes.note(noteID)?.body ?? "" },
            set: { notes.updateBody(noteID, body: $0) }
        )
    }

    // MARK: - Recording

    private func recordButton(_ note: Note) -> some View {
        Group {
            if engine.isCapturing(note.id) {
                Button {
                    engine.stop()
                } label: {
                    Label("Stop", systemImage: "stop.circle.fill")
                        .foregroundStyle(.red)
                }
                .help("Stop the lecture recording")
                .accessibilityLabel("Stop recording")
            } else {
                Button {
                    let saveAudio = appState.settings.saveLectureAudio
                    Task { await engine.start(noteID: note.id, notesState: notes, saveAudio: saveAudio) }
                } label: {
                    Label("Record", systemImage: "mic")
                }
                .disabled(engine.isActive)
                .help(engine.isActive ? "Already recording in another note" : "Record a lecture into this note")
                .accessibilityLabel("Record lecture")
            }
        }
    }

    // MARK: - AI

    private func aiMenu(_ note: Note) -> some View {
        Menu {
            ForEach(NoteAIAction.allCases) { action in
                Button {
                    runAI(action, on: note)
                } label: {
                    Label(action.label, systemImage: action.systemImage)
                }
                .help(action.help)
            }
        } label: {
            Label("AI", systemImage: "sparkles")
        }
        .disabled(!NoteAI.isAvailable || ai.isRunning || note.body.isEmpty)
        .help(NoteAI.isAvailable
            ? "Clean up, summarize, or outline this note on-device"
            : (NoteAI.unavailableReason ?? "Apple Intelligence is unavailable"))
        .accessibilityLabel("AI actions")
    }

    private func runAI(_ action: NoteAIAction, on note: Note) {
        aiError = nil
        let original = note.body
        Task {
            do {
                let result = try await ai.run(action, on: original)
                // The note may have changed while the model ran (typing, transcript chunks);
                // applying a stale rewrite would drop that. Skip instead.
                guard notes.note(noteID)?.body == original else {
                    aiError = "The note changed while the model was working. Try again."
                    return
                }
                // applyAIEdit keeps the pre-edit body in NotesState, so revert still works
                // if the user switched notes while the model ran.
                switch action {
                case .cleanUp, .outline:
                    notes.applyAIEdit(noteID, body: result)
                case .summarize:
                    notes.applyAIEdit(noteID, body: "## Summary\n\n\(result)\n\n\(original)")
                }
            } catch {
                aiError = error.localizedDescription
            }
        }
    }

    // MARK: - Status bar

    private func statusBar(_ note: Note) -> some View {
        HStack(spacing: 10) {
            Text("\(note.wordCount) \(note.wordCount == 1 ? "word" : "words")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if ai.isRunning {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(ai.runningAction.map { "\($0.label)…" } ?? "Working…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let aiError {
                Text(aiError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .help(aiError)
                Button {
                    self.aiError = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red.opacity(0.8))
                .accessibilityLabel("Dismiss AI error")
            }

            if notes.aiBackup(noteID) != nil {
                Button("Revert AI edit") {
                    notes.revertAIEdit(noteID)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .help("Put the note back exactly as it was before the AI edit")
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: notes.isSaving ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                Text(notes.isSaving ? "Saving…" : "Saved")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .accessibilityLabel(notes.isSaving ? "Saving" : "All changes saved")
        }
        .padding(.horizontal, Theme.notesEditorInset)
        .padding(.vertical, 7)
    }
}
