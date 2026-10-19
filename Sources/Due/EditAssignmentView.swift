import SwiftUI
import DueCore

/// Popover form for editing one assignment in place. Title must be non-empty to save.
struct EditAssignmentView: View {
    let assignment: Assignment
    @Environment(AppState.self) private var state
    let onClose: () -> Void

    @State private var title: String
    @State private var course: String
    @State private var dueDate: Date
    @State private var estimateMinutes: Int?
    @State private var notes: String
    @State private var showCustomEstimate = false
    @State private var customEstimateText = ""

    private static let estimateOptions = [15, 30, 45, 60, 90, 120, 180, 240]

    init(assignment: Assignment, onClose: @escaping () -> Void) {
        self.assignment = assignment
        self.onClose = onClose
        _title = State(initialValue: assignment.title)
        _course = State(initialValue: assignment.course ?? "")
        _dueDate = State(initialValue: assignment.dueDate)
        _estimateMinutes = State(initialValue: assignment.estimateMinutes)
        _notes = State(initialValue: assignment.notes ?? "")
    }

    private var isTitleValid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit assignment").font(.headline)

            TextField("Title", text: $title).textFieldStyle(.roundedBorder)

            courseField

            DatePicker("Due", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)

            estimateField

            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isTitleValid)
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private var courseField: some View {
        HStack(spacing: 6) {
            TextField("Course", text: $course).textFieldStyle(.roundedBorder)
            Menu {
                ForEach(state.courses, id: \.self) { suggestion in
                    Button(suggestion) { course = suggestion }
                }
            } label: {
                Image(systemName: "chevron.down.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
            .disabled(state.courses.isEmpty)
            .help("Course suggestions")
            .accessibilityLabel("Course suggestions")
        }
    }

    private var estimateField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Menu {
                Button("None") {
                    estimateMinutes = nil
                    showCustomEstimate = false
                }
                ForEach(Self.estimateOptions, id: \.self) { minutes in
                    Button(DueLogic.estimateText(minutes: minutes)) {
                        estimateMinutes = minutes
                        showCustomEstimate = false
                    }
                }
                Button("Custom minutes…") { showCustomEstimate = true }
            } label: {
                Text(estimateLabel)
            }
            .help("Estimated time")
            .accessibilityLabel("Estimated time")

            if showCustomEstimate {
                TextField("Minutes", text: $customEstimateText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if let minutes = Int(customEstimateText), minutes > 0 {
                            estimateMinutes = minutes
                        }
                        showCustomEstimate = false
                    }
            }
        }
    }

    private var estimateLabel: String {
        guard let estimateMinutes else { return "Est. None" }
        return "Est. \(DueLogic.estimateText(minutes: estimateMinutes))"
    }

    private func save() {
        guard isTitleValid else { return }
        let cleanCourse = course.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let edited = Assignment(
            id: assignment.id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            course: cleanCourse.isEmpty ? nil : cleanCourse,
            dueDate: dueDate,
            estimateMinutes: estimateMinutes,
            notes: cleanNotes.isEmpty ? nil : cleanNotes,
            isDone: assignment.isDone,
            completedAt: assignment.completedAt,
            createdAt: assignment.createdAt,
            sortOrder: assignment.sortOrder
        )
        state.update(edited)
        onClose()
    }
}
