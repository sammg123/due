import Foundation
import Observation

/// Single source of truth for the notes window. Every mutation replaces the note with a new
/// value; body edits persist on a debounce (Google-Docs-style autosave), everything else
/// (create, delete, transcript chunks, recordings) writes through immediately.
@MainActor
@Observable
public final class NotesState {
    public private(set) var notes: [Note]
    public var selectedNoteID: UUID?
    public private(set) var lastError: String?

    private let store: NotesStore?
    private var pendingSaves: [UUID: Note] = [:]
    /// Session-only pre-AI-edit bodies, keyed by note. Never persisted.
    private var aiBackups: [UUID: String] = [:]
    /// Session-only pre-AI-edit drawing scenes, keyed by drawing. Never persisted.
    private var drawingAIBackups: [UUID: Drawing] = [:]
    /// Loaded drawings, filled lazily as blocks render.
    private var drawingsCache: [UUID: Drawing] = [:]
    private var saveTask: Task<Void, Never>?

    /// Keystroke-to-disk delay. Short enough that a crash loses at most a moment of typing.
    public static let autosaveDebounceNanoseconds: UInt64 = 800_000_000

    public init(notes: [Note] = [], store: NotesStore? = nil) {
        self.notes = notes
        self.store = store
    }

    /// Loads every note. Corrupt files are kept on disk and reported via `lastError`.
    public static func load(store: NotesStore) -> NotesState {
        do {
            let result = try store.loadAll()
            let state = NotesState(notes: result.notes, store: store)
            if !result.skippedFiles.isEmpty {
                state.lastError = "Could not read: \(result.skippedFiles.joined(separator: ", "))"
            }
            return state
        } catch {
            let state = NotesState(notes: [], store: store)
            state.lastError = "Could not read notes: \(error.localizedDescription)"
            return state
        }
    }

    public static func loadFromDisk() -> NotesState {
        load(store: NotesStore(directory: NotesStore.defaultDirectory()))
    }

    // MARK: - Derived

    public func note(_ id: UUID?) -> Note? {
        guard let id else { return nil }
        return notes.first { $0.id == id }
    }

    public var audioDirectory: URL? { store?.audioDirectory }

    /// True while a debounced body edit hasn't reached disk yet ("Saving…" vs "Saved").
    public var isSaving: Bool { !pendingSaves.isEmpty }

    /// Every course used by a note, most recently edited first.
    public var courses: [String] {
        var seen = Set<String>()
        return NotesLogic.sort(notes, by: .dateEdited).compactMap { note in
            guard let c = note.course, !c.isEmpty, !seen.contains(c) else { return nil }
            seen.insert(c)
            return c
        }
    }

    // MARK: - Mutations

    @discardableResult
    public func createNote(course: String?, at date: Date = Date()) -> Note {
        let note = Note(title: "", course: course, body: "", createdAt: date, updatedAt: date)
        notes = notes + [note]
        selectedNoteID = note.id
        persistNow(note)
        return note
    }

    public func updateBody(_ id: UUID, body: String, at date: Date = Date()) {
        guard let existing = note(id), existing.body != body else { return }
        // Typing over an AI edit invalidates its one-click revert; keeping it would let a
        // later "Revert" silently destroy the newer typing.
        aiBackups.removeValue(forKey: id)
        apply(existing.updating(body: body, at: date), debounced: true)
    }

    public func updateTitle(_ id: UUID, title: String, at date: Date = Date()) {
        guard let existing = note(id), existing.title != title else { return }
        apply(existing.updating(title: title, at: date), debounced: true)
    }

    public func updateCourse(_ id: UUID, course: String?, at date: Date = Date()) {
        guard let existing = note(id), existing.course != course else { return }
        apply(existing.updating(course: course, at: date), debounced: false)
    }

    /// Replaces the whole body (AI actions), remembering the previous body for one-click
    /// revert. Lives here (not in view state) so the revert survives switching notes while
    /// the model is still working. Persists immediately.
    public func applyAIEdit(_ id: UUID, body: String, at date: Date = Date()) {
        guard let existing = note(id) else { return }
        aiBackups[id] = existing.body
        apply(existing.updating(body: body, at: date), debounced: false)
    }

    /// The body as it was before the last AI edit, while revert is still meaningful.
    public func aiBackup(_ id: UUID) -> String? { aiBackups[id] }

    public func revertAIEdit(_ id: UUID, at date: Date = Date()) {
        guard let backup = aiBackups.removeValue(forKey: id), let existing = note(id) else { return }
        apply(existing.updating(body: backup, at: date), debounced: false)
    }

    public func deleteNote(_ id: UUID) {
        // Evict the note's drawings from memory too, or an in-flight AI edit resolving
        // after the delete would find them in the cache and resurrect their files.
        for fileName in note(id)?.drawingFiles ?? [] {
            if let drawingID = UUID(uuidString: (fileName as NSString).deletingPathExtension) {
                drawingsCache.removeValue(forKey: drawingID)
                drawingAIBackups.removeValue(forKey: drawingID)
            }
        }
        notes = notes.filter { $0.id != id }
        pendingSaves.removeValue(forKey: id)
        aiBackups.removeValue(forKey: id)
        if selectedNoteID == id { selectedNoteID = nil }
        guard let store else { return }
        do {
            try store.delete(id)
        } catch {
            lastError = "Could not delete note: \(error.localizedDescription)"
        }
    }

    /// Appends a transcription chunk under `sessionHeading`, adding the heading on first use.
    /// Writes through immediately so a crash mid-lecture loses at most one chunk.
    public func appendTranscript(_ id: UUID, text: String, sessionHeading: String, at date: Date = Date()) {
        guard let existing = note(id) else { return }
        let chunk = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chunk.isEmpty else { return }
        let body: String
        if existing.body.contains(sessionHeading) {
            body = existing.body + " " + chunk
        } else {
            let base = existing.body.isEmpty ? "" : existing.body + "\n\n"
            body = base + "## \(sessionHeading)\n\n" + chunk
        }
        apply(existing.updating(body: body, at: date), debounced: false)
    }

    /// Registers a finished recording on the note.
    public func recordAudioFile(_ id: UUID, fileName: String, seconds: Int, at date: Date = Date()) {
        guard let existing = note(id) else { return }
        apply(existing.updating(addingAudioFile: fileName, seconds: seconds, at: date), debounced: false)
    }

    // MARK: - Drawings

    public func drawing(_ id: UUID) -> Drawing? {
        if let cached = drawingsCache[id] { return cached }
        guard let store, let loaded = try? store.loadDrawing(id: id) else { return nil }
        drawingsCache[id] = loaded
        return loaded
    }

    /// The body line that places a drawing inside a note.
    public static func drawingMarker(_ id: UUID) -> String { "[drawing: \(id.uuidString)]" }

    /// Creates an empty drawing, registers it on the note, and appends its marker to the
    /// body. Everything persists immediately.
    @discardableResult
    public func attachDrawing(to noteID: UUID, at date: Date = Date()) -> Drawing? {
        guard let existing = note(noteID) else { return nil }
        let drawing = Drawing(createdAt: date, updatedAt: date)
        drawingsCache[drawing.id] = drawing
        persistDrawing(drawing)
        let base = existing.body.isEmpty ? "" : existing.body + "\n\n"
        var next = existing.updating(body: base + Self.drawingMarker(drawing.id) + "\n", at: date)
        next = next.updating(addingDrawingFile: NotesStore.drawingFileName(for: drawing.id), at: date)
        apply(next, debounced: false)
        return drawing
    }

    /// Saves a drawing edit and bumps the note so it sorts as recently edited.
    /// A drawing whose note is gone is never written: that would orphan a file on disk
    /// that no cleanup path can reach.
    public func updateDrawing(_ drawing: Drawing, for noteID: UUID, at date: Date = Date()) {
        guard let existing = note(noteID) else {
            drawingsCache.removeValue(forKey: drawing.id)
            drawingAIBackups.removeValue(forKey: drawing.id)
            return
        }
        var copy = drawing
        copy.updatedAt = date
        drawingsCache[copy.id] = copy
        persistDrawing(copy)
        apply(existing.updating(body: existing.body, at: date), debounced: false)
    }

    /// Removes the drawing's file, its registration, and its marker line(s) from the body.
    public func deleteDrawing(_ id: UUID, from noteID: UUID, at date: Date = Date()) {
        drawingsCache.removeValue(forKey: id)
        drawingAIBackups.removeValue(forKey: id)
        if let store {
            try? store.deleteDrawing(id: id)
        }
        guard let existing = note(noteID) else { return }
        let marker = Self.drawingMarker(id)
        let body = existing.body
            .components(separatedBy: .newlines)
            .filter { $0.trimmingCharacters(in: .whitespaces).lowercased() != marker.lowercased() }
            .joined(separator: "\n")
        var next = existing.updating(body: body, at: date)
        next = next.updating(removingDrawingFile: NotesStore.drawingFileName(for: id), at: date)
        apply(next, debounced: false)
    }

    /// Replaces a drawing's scene from an AI edit, keeping the previous scene for revert.
    public func applyAIDrawing(_ id: UUID, elements: [DrawingElement], for noteID: UUID, at date: Date = Date()) {
        guard let existing = drawing(id) else { return }
        drawingAIBackups[id] = existing
        updateDrawing(existing.updating(elements: elements, at: date), for: noteID, at: date)
    }

    public func drawingAIBackup(_ id: UUID) -> Drawing? { drawingAIBackups[id] }

    public func revertAIDrawing(_ id: UUID, for noteID: UUID, at date: Date = Date()) {
        guard let backup = drawingAIBackups.removeValue(forKey: id) else { return }
        updateDrawing(backup, for: noteID, at: date)
    }

    /// A manual edit to the drawing invalidates the AI revert, same rule as note bodies.
    public func clearDrawingAIBackup(_ id: UUID) {
        drawingAIBackups.removeValue(forKey: id)
    }

    private func persistDrawing(_ drawing: Drawing) {
        guard let store else { return }
        do {
            try store.saveDrawing(drawing)
        } catch {
            lastError = "Could not save drawing: \(error.localizedDescription)"
        }
    }

    /// Writes every debounced edit now. Call on window close / app quit.
    public func flushPendingSaves() {
        saveTask?.cancel()
        saveTask = nil
        let pending = pendingSaves
        pendingSaves = [:]
        for note in pending.values { persistNow(note) }
    }

    public func clearError() { lastError = nil }

    // MARK: - Private

    private func apply(_ note: Note, debounced: Bool) {
        guard let idx = notes.firstIndex(where: { $0.id == note.id }) else { return }
        var next = notes
        next[idx] = note
        notes = next
        if debounced {
            scheduleSave(note)
        } else {
            pendingSaves.removeValue(forKey: note.id)
            persistNow(note)
        }
    }

    private func scheduleSave(_ note: Note) {
        pendingSaves[note.id] = note
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: NotesState.autosaveDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            self?.flushPendingSaves()
        }
    }

    private func persistNow(_ note: Note) {
        guard let store else { return }
        do {
            try store.save(note)
        } catch {
            lastError = "Could not save note: \(error.localizedDescription)"
        }
    }
}
