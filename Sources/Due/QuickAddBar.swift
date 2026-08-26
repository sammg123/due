import SwiftUI
import DueCore

/// Free-text entry with explicit course/date/estimate overrides. Explicit control choices win
/// over what `QuickAddParser` finds in the text; unset controls defer to the parse.
struct QuickAddBar: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var isFocused: FocusState<Bool>.Binding

    @State private var text = ""
    @State private var pickerDate: Date
    @State private var didTouchDate = false
    @State private var explicitCourse: String?
    @State private var explicitEstimate: Int?
    @State private var showNewCourseField = false
    @State private var newCourseText = ""

    private static let estimateOptions = [15, 30, 45, 60, 90, 120, 180, 240]

    init(isFocused: FocusState<Bool>.Binding) {
        self.isFocused = isFocused
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        _pickerDate = State(initialValue: DueLogic.endOfDay(tomorrow))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Add assignment (e.g. pset 4 fri 5pm #CS225 ~2h)", text: $text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .focused(isFocused)
                .onSubmit(performAdd)

            HStack(spacing: 8) {
                courseMenu
                DatePicker("Due date", selection: $pickerDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .onChange(of: pickerDate) { didTouchDate = true }
                    .help("Due date")
                    .accessibilityLabel("Due date")
                estimateMenu
            }

            if showNewCourseField {
                HStack(spacing: 6) {
                    TextField("Course name", text: $newCourseText)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .onSubmit(commitNewCourse)
                    Button("Add", action: commitNewCourse)
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }

            if let previewText {
                Text(previewText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            isFocused.wrappedValue = true
        }
        .background(
            Button("", action: { isFocused.wrappedValue = true })
                .keyboardShortcut("n")
                .opacity(0)
                .accessibilityHidden(true)
        )
        .animation(reduceMotion ? nil : .easeOut(duration: Theme.animationFast), value: previewText)
    }

    // MARK: - Course

    private var courseMenu: some View {
        Menu {
            ForEach(state.courses, id: \.self) { course in
                Button(course) { explicitCourse = course }
            }
            if !state.courses.isEmpty { Divider() }
            Button("None") { explicitCourse = nil }
            Button("New course…") { showNewCourseField = true }
        } label: {
            Text(explicitCourse ?? "Course").font(.caption)
        }
        .menuStyle(.borderlessButton)
        .help("Course")
        .accessibilityLabel("Course")
    }

    private func commitNewCourse() {
        let clean = newCourseText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty { explicitCourse = clean }
        newCourseText = ""
        showNewCourseField = false
    }

    // MARK: - Estimate

    private var estimateMenu: some View {
        Menu {
            Button("None") { explicitEstimate = nil }
            ForEach(Self.estimateOptions, id: \.self) { minutes in
                Button(DueLogic.estimateText(minutes: minutes)) { explicitEstimate = minutes }
            }
        } label: {
            Text(explicitEstimate.map { DueLogic.estimateText(minutes: $0) } ?? "Est.").font(.caption)
        }
        .menuStyle(.borderlessButton)
        .help("Estimated time")
        .accessibilityLabel("Estimated time")
    }

    // MARK: - Preview & add

    private var parsedNow: QuickAddParse { QuickAddParser.parse(text, now: state.now) }

    private var previewText: String? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let parsed = parsedNow
        var parts = ["Due \(DueLogic.fullDueText(for: effectiveDue(parsed)))"]
        if let course = explicitCourse ?? parsed.course { parts.append(course) }
        if let estimate = explicitEstimate ?? parsed.estimateMinutes {
            parts.append(DueLogic.estimateText(minutes: estimate))
        }
        return parts.joined(separator: " · ")
    }

    private func effectiveDue(_ parsed: QuickAddParse) -> Date {
        didTouchDate ? pickerDate : (parsed.dueDate ?? pickerDate)
    }

    /// Parse once and submit exactly what the preview line showed: explicit controls win,
    /// otherwise the parsed value, otherwise the picker date.
    private func performAdd() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let parsed = parsedNow
        let added = state.add(
            title: parsed.title,
            course: explicitCourse ?? parsed.course,
            dueDate: effectiveDue(parsed),
            estimateMinutes: explicitEstimate ?? parsed.estimateMinutes
        )
        guard added != nil else { return }
        text = ""
        explicitEstimate = nil
        didTouchDate = false
        isFocused.wrappedValue = true
    }
}
