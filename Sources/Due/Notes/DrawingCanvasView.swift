import SwiftUI
import AppKit
import DueCore

/// The drawing editor, presented as a sheet over the note. Manual tools (pen with shape
/// snap, boxes, arrows, text, select/move, erase), full undo/redo, an AI bar that makes
/// or edits the scene from an instruction, sketch redraw via a local vision model, and
/// PNG export. Every mutation persists immediately through NotesState.
struct DrawingCanvasView: View {
    let drawingID: UUID
    let noteID: UUID

    @Environment(AppState.self) private var appState
    @Environment(NotesState.self) private var notes
    @Environment(\.dismiss) private var dismiss

    enum Tool: String, CaseIterable {
        case select, pen, rect, ellipse, arrow, text, erase

        var systemImage: String {
            switch self {
            case .select: return "cursorarrow"
            case .pen: return "pencil.line"
            case .rect: return "rectangle"
            case .ellipse: return "circle"
            case .arrow: return "arrow.up.right"
            case .text: return "textformat"
            case .erase: return "eraser"
            }
        }

        var help: String {
            switch self {
            case .select: return "Select and move"
            case .pen: return "Draw freehand (Assist snaps rough shapes)"
            case .rect: return "Draw a box"
            case .ellipse: return "Draw an ellipse"
            case .arrow: return "Draw an arrow"
            case .text: return "Click to place text"
            case .erase: return "Erase elements"
            }
        }
    }

    @State private var drawing = Drawing()
    @State private var loaded = false
    @State private var tool: Tool = .pen
    @State private var color: PaletteColor = .blue
    @AppStorage("drawAssist") private var assist = true

    @State private var undoStack: [Drawing] = []
    @State private var redoStack: [Drawing] = []

    // In-flight gesture state.
    @State private var currentPoints: [DrawingPoint] = []
    @State private var dragStart: DrawingPoint?
    @State private var dragCurrent: DrawingPoint?
    @State private var selectedID: UUID?
    @State private var lastDragPoint: DrawingPoint?
    @State private var gestureDidSnapshot = false

    @State private var pendingTextPoint: DrawingPoint?
    @State private var pendingText = ""
    @FocusState private var textEntryFocused: Bool

    @State private var ai = NoteAI()
    @State private var aiTask: Task<Void, Never>?
    @State private var aiPrompt = ""
    @State private var aiError: String?
    @State private var visionAvailable = false
    @State private var showDeleteConfirm = false

    private static let canvasWidth: CGFloat = 720
    private var canvasScale: CGFloat { Self.canvasWidth / Drawing.width }
    private static let paletteChoices: [PaletteColor] = [.blue, .teal, .green, .yellow, .orange, .red, .purple, .pink, .gray]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            toolRow
            canvas
            if pendingTextPoint != nil {
                textEntryRow
            }
            promptBar
            statusRow
        }
        .frame(width: Self.canvasWidth + 2 * Theme.notesEditorInset)
        .onAppear(perform: load)
        .onDisappear { aiTask?.cancel() }
        .task { visionAvailable = await visionModelInstalled() }
        .confirmationDialog("Delete this drawing?", isPresented: $showDeleteConfirm) {
            Button("Delete Drawing", role: .destructive) {
                notes.deleteDrawing(drawingID, from: noteID)
                dismiss()
            }
        } message: {
            Text("Removes it from the note. This can't be undone.")
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let existing = notes.drawing(drawingID) {
            drawing = existing
            if let course = notes.note(noteID)?.course {
                color = appState.color(forCourse: course)
            }
        } else {
            dismiss()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text("Drawing")
                .font(.title3.weight(.semibold))
            Spacer()
            Toggle("Assist", isOn: $assist)
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Snap rough strokes to clean lines, boxes, and ellipses")
            Button {
                undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(undoStack.isEmpty)
            .keyboardShortcut("z", modifiers: .command)
            .help("Undo")
            Button {
                redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(redoStack.isEmpty)
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .help("Redo")
            Button {
                exportPNG()
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(drawing.isEmpty)
            .help("Export as PNG")
            Button {
                showDeleteConfirm = true
            } label: {
                Image(systemName: "trash")
            }
            .help("Delete this drawing")
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, Theme.notesEditorInset)
        .padding(.vertical, 10)
    }

    // MARK: - Tools

    private var toolRow: some View {
        HStack(spacing: 6) {
            ForEach(Tool.allCases, id: \.self) { t in
                Button {
                    tool = t
                } label: {
                    Image(systemName: t.systemImage)
                        .frame(width: 26, height: 22)
                        .background(tool == t ? Color.accentColor.opacity(0.2) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(t.help)
                .accessibilityLabel(t.help)
            }
            Divider().frame(height: 18)
            ForEach(Self.paletteChoices, id: \.self) { palette in
                Button {
                    color = palette
                } label: {
                    Circle()
                        .fill(Theme.color(palette))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(.primary.opacity(color == palette ? 0.8 : 0), lineWidth: 2))
                }
                .buttonStyle(.plain)
                .help(palette.rawValue.capitalized)
                .accessibilityLabel("Color \(palette.rawValue)")
            }
            Spacer()
            if visionAvailable, drawing.elements.contains(where: { $0.kind == .stroke }) {
                Button {
                    vectorizeSketch()
                } label: {
                    Label("Redraw sketch", systemImage: "wand.and.rays")
                        .font(.caption)
                }
                .disabled(ai.isRunning)
                .help("Have the vision model turn your rough sketch into clean shapes")
            }
            Button {
                runAI("Add whatever diagram elements would best illustrate this note. Keep the existing elements.")
            } label: {
                Label("Suggest", systemImage: "sparkles")
                    .font(.caption)
            }
            .disabled(ai.isRunning || !ai.canRun)
            .help("Let the model add what the note suggests is missing")
        }
        .padding(.horizontal, Theme.notesEditorInset)
        .padding(.vertical, 6)
    }

    // MARK: - Canvas

    private var canvas: some View {
        DrawingSceneCanvas(elements: drawing.elements, previewElements: previewElements, highlightedID: selectedID)
            .frame(width: Self.canvasWidth, height: Self.canvasWidth * Drawing.height / Drawing.width)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: Theme.rowCornerRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.rowCornerRadius).strokeBorder(.quaternary, lineWidth: 1))
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .onTapGesture(count: 2) { location in
                editLabel(at: normalized(location))
            }
            .padding(.horizontal, Theme.notesEditorInset)
            .padding(.vertical, 6)
    }

    private var previewElements: [DrawingElement] {
        if tool == .pen, currentPoints.count > 1 {
            return [.stroke(points: currentPoints, color: color, width: 3)]
        }
        if let start = dragStart, let current = dragCurrent {
            switch tool {
            case .rect:
                return [.rect(x: min(start.x, current.x), y: min(start.y, current.y),
                              w: abs(current.x - start.x), h: abs(current.y - start.y), label: nil, color: color)]
            case .ellipse:
                return [.ellipse(x: min(start.x, current.x), y: min(start.y, current.y),
                                 w: abs(current.x - start.x), h: abs(current.y - start.y), label: nil, color: color)]
            case .arrow:
                return [.arrow(from: start, to: current, label: nil, color: color)]
            default:
                break
            }
        }
        return []
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let p = normalized(value.location)
                switch tool {
                case .pen:
                    currentPoints.append(p)
                case .rect, .ellipse, .arrow:
                    if dragStart == nil { dragStart = normalized(value.startLocation) }
                    dragCurrent = p
                case .select:
                    if lastDragPoint == nil {
                        selectedID = DrawingGeometry.hitTest(drawing.elements, at: p)
                        lastDragPoint = p
                    } else if let selectedID, let last = lastDragPoint {
                        moveSelected(selectedID, dx: p.x - last.x, dy: p.y - last.y)
                        lastDragPoint = p
                    }
                case .erase:
                    if let hit = DrawingGeometry.hitTest(drawing.elements, at: p) {
                        snapshotOncePerGesture()
                        commit(drawing.elements.filter { $0.id != hit }, snapshot: false)
                    }
                case .text:
                    break
                }
            }
            .onEnded { value in
                let p = normalized(value.location)
                defer {
                    currentPoints = []
                    dragStart = nil
                    dragCurrent = nil
                    lastDragPoint = nil
                    gestureDidSnapshot = false
                }
                switch tool {
                case .pen:
                    commitStroke()
                case .rect, .ellipse, .arrow:
                    commitShape()
                case .text:
                    pendingTextPoint = p
                    pendingText = ""
                    textEntryFocused = true
                case .select:
                    if gestureDidSnapshot {
                        // A manual reposition invalidates the AI revert like any other
                        // manual edit; a live Revert would silently discard the move.
                        notes.clearDrawingAIBackup(drawingID)
                        persist()
                    }
                case .erase:
                    break
                }
            }
    }

    private func normalized(_ location: CGPoint) -> DrawingPoint {
        DrawingPoint(
            x: min(max(location.x / canvasScale, 0), Drawing.width),
            y: min(max(location.y / canvasScale, 0), Drawing.height)
        )
    }

    // MARK: - Committing edits

    private func commitStroke() {
        guard currentPoints.count > 1 else { return }
        var element = DrawingElement.stroke(points: currentPoints, color: color, width: 3)
        if assist, let shape = ShapeRecognizer.recognize(currentPoints) {
            switch shape {
            case .line(let from, let to):
                element = .stroke(points: [from, to], color: color, width: 3)
            case .rect(let x, let y, let w, let h):
                element = .rect(x: x, y: y, w: w, h: h, label: nil, color: color)
            case .ellipse(let x, let y, let w, let h):
                element = .ellipse(x: x, y: y, w: w, h: h, label: nil, color: color)
            }
        }
        commit(drawing.elements + [element])
    }

    private func commitShape() {
        guard let element = previewElements.first else { return }
        // Ignore accidental clicks that made a degenerate shape.
        if element.kind == .arrow {
            guard abs(element.to.x - element.from.x) + abs(element.to.y - element.from.y) > 12 else { return }
        } else {
            guard element.w > 12, element.h > 12 else { return }
        }
        commit(drawing.elements + [element])
    }

    private func commitText() {
        defer {
            pendingTextPoint = nil
            pendingText = ""
        }
        let string = pendingText.trimmingCharacters(in: .whitespaces)
        guard let point = pendingTextPoint, !string.isEmpty else { return }
        commit(drawing.elements + [.text(x: point.x, y: point.y, string: string, size: 16, color: color)])
    }

    private func moveSelected(_ id: UUID, dx: Double, dy: Double) {
        snapshotOncePerGesture()
        let moved = drawing.elements.map { $0.id == id ? DrawingGeometry.moving($0, dx: dx, dy: dy) : $0 }
        drawing = drawing.updating(elements: moved)
    }

    private func snapshotOncePerGesture() {
        guard !gestureDidSnapshot else { return }
        gestureDidSnapshot = true
        pushUndo()
    }

    /// Replaces the scene, recording undo and persisting. Manual edits invalidate AI revert.
    private func commit(_ elements: [DrawingElement], snapshot: Bool = true) {
        if snapshot { pushUndo() }
        drawing = drawing.updating(elements: elements)
        notes.clearDrawingAIBackup(drawingID)
        persist()
    }

    private func persist() {
        notes.updateDrawing(drawing, for: noteID)
    }

    private func pushUndo() {
        undoStack.append(drawing)
        if undoStack.count > 60 { undoStack.removeFirst() }
        redoStack = []
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(drawing)
        drawing = previous
        persist()
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(drawing)
        drawing = next
        persist()
    }

    // MARK: - Labels

    private func editLabel(at point: DrawingPoint) {
        guard let hit = DrawingGeometry.hitTest(drawing.elements, at: point),
              let element = drawing.elements.first(where: { $0.id == hit }),
              element.kind == .rect || element.kind == .ellipse || element.kind == .arrow || element.kind == .text
        else { return }
        // Reuse the text entry row for label editing: prefill and route the commit.
        pendingTextPoint = nil
        labelEditingID = hit
        pendingText = element.text
        textEntryFocused = true
    }

    @State private var labelEditingID: UUID?

    private func commitLabel() {
        defer {
            labelEditingID = nil
            pendingText = ""
        }
        guard let id = labelEditingID else { return }
        let updated = drawing.elements.map { e -> DrawingElement in
            guard e.id == id else { return e }
            var copy = e
            copy.text = pendingText.trimmingCharacters(in: .whitespaces)
            return copy
        }
        commit(updated)
    }

    private var textEntryRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "textformat")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField(labelEditingID == nil ? "Text to place" : "Label", text: $pendingText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .focused($textEntryFocused)
                .onSubmit { labelEditingID == nil ? commitText() : commitLabel() }
                .onExitCommand {
                    pendingTextPoint = nil
                    labelEditingID = nil
                    pendingText = ""
                }
            Button("Add") { labelEditingID == nil ? commitText() : commitLabel() }
                .disabled(pendingText.trimmingCharacters(in: .whitespaces).isEmpty && labelEditingID == nil)
        }
        .padding(.horizontal, Theme.notesEditorInset)
        .padding(.vertical, 4)
    }

    // MARK: - AI

    private var promptBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField(
                drawing.isEmpty
                    ? "Ask AI to draw (\"flowchart of the outlier procedure\", \"graph e^(-x^2/2)\")"
                    : "Ask AI to edit this drawing (\"label the boxes\", \"add a normal curve\")",
                text: $aiPrompt
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .onSubmit(submitPrompt)
            .disabled(ai.isRunning)
            if !aiPrompt.trimmingCharacters(in: .whitespaces).isEmpty, !ai.isRunning {
                Button(action: submitPrompt) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Apply AI drawing edit")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: Theme.rowCornerRadius))
        .padding(.horizontal, Theme.notesEditorInset)
        .padding(.vertical, 6)
        .opacity(ai.canRun ? 1 : 0.4)
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            if ai.isRunning {
                ProgressView()
                    .controlSize(.mini)
                Text("\(ai.runningLabel ?? "Working")… (\(ai.engineName ?? "model"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                .accessibilityLabel("Dismiss error")
            }
            if notes.drawingAIBackup(drawingID) != nil {
                Button("Revert AI edit") {
                    notes.revertAIDrawing(drawingID, for: noteID)
                    if let restored = notes.drawing(drawingID) { drawing = restored }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            }
            Spacer()
            Text("\(drawing.elements.count) elements")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, Theme.notesEditorInset)
        .padding(.vertical, 7)
    }

    private func submitPrompt() {
        let instruction = aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }
        runAI(instruction)
        aiPrompt = ""
    }

    private func runAI(_ instruction: String) {
        guard ai.canRun, !ai.isRunning else { return }
        aiError = nil
        let context = notes.note(noteID)?.body ?? ""
        let current = drawing.elements
        let modelSetting = appState.settings.notesAIModel
        aiTask = Task {
            do {
                let scene = try await ai.runDrawing(instruction, elements: current, noteContext: context, modelSetting: modelSetting)
                guard !Task.isCancelled else { return }
                applyAIScene(scene, ifStillCurrent: current)
            } catch {
                aiError = error.localizedDescription
            }
        }
    }

    private func vectorizeSketch() {
        guard let png = renderPNG() else {
            aiError = "Could not render the sketch"
            return
        }
        aiError = nil
        let context = notes.note(noteID)?.body ?? ""
        let current = drawing.elements
        aiTask = Task {
            do {
                let scene = try await ai.vectorizeSketch(png: png, noteContext: context)
                guard !Task.isCancelled else { return }
                applyAIScene(scene, ifStillCurrent: current)
            } catch {
                aiError = error.localizedDescription
            }
        }
    }

    /// The drawing may have changed while the model ran; applying a stale scene would
    /// silently drop that work, so skip instead (same rule as note text).
    private func applyAIScene(_ scene: [DrawingElement], ifStillCurrent expected: [DrawingElement]) {
        guard drawing.elements == expected else {
            aiError = "The drawing changed while the model was working. Try again."
            return
        }
        pushUndo()
        notes.applyAIDrawing(drawingID, elements: scene, for: noteID)
        if let updated = notes.drawing(drawingID) { drawing = updated }
    }

    private func visionModelInstalled() async -> Bool {
        guard let installed = await OllamaClient.installedModels() else { return false }
        return OllamaModels.preferredVision(from: installed) != nil
    }

    // MARK: - Export

    @MainActor
    private func renderPNG() -> Data? {
        let content = DrawingSceneCanvas(elements: drawing.elements)
            .frame(width: Drawing.width, height: Drawing.height)
            .background(Color.white)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func exportPNG() {
        guard let png = renderPNG() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(notes.note(noteID)?.displayTitle ?? "drawing").png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try png.write(to: url)
        } catch {
            aiError = "Export failed: \(error.localizedDescription)"
        }
    }
}
