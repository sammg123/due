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
    @FocusState private var newCourseFocused: Bool

    @State private var smart = SmartQuickAddParser()
    @State private var smartResult: (text: String, result: SmartParseResult)?
    @State private var smartTask: Task<Void, Never>?
    @State private var isSmartParsing = false

    private static let smartParseDebounce: UInt64 = 400_000_000
    private static let smartParseMinChars = 3
    private static let performAddWait: Double = 1.2

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
                .font(.system(size: 14))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .focused(isFocused)
                .onSubmit(performAdd)
                .onChange(of: text) { _, newValue in scheduleSmartParse(for: newValue) }

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

            if let previewText {
                HStack(spacing: 4) {
                    if isUsingSmartResult {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    Text(previewText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if isSmartParsing {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
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
        .animation(reduceMotion ? nil : .easeOut(duration: Theme.animationFast), value: isSmartParsing)
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
            Text(explicitCourse ?? "Course").font(.callout)
        }
        .menuStyle(.borderlessButton)
        .help("Course")
        .accessibilityLabel("Course")
    }

    /// Registers the course immediately (it gets a color and appears in the dropdown and Settings)
    /// and selects it for the next add.
    private func commitNewCourse() {
        if let registered = state.registerCourse(newCourseText) { explicitCourse = registered }
        newCourseText = ""
        showNewCourseField = false
        isFocused.wrappedValue = true
    }

    private func cancelNewCourse() {
        newCourseText = ""
        showNewCourseField = false
        isFocused.wrappedValue = true
    }

    // MARK: - Estimate

    private var estimateMenu: some View {
        Menu {
            Button("None") { explicitEstimate = nil }
            ForEach(Self.estimateOptions, id: \.self) { minutes in
                Button(DueLogic.estimateText(minutes: minutes)) { explicitEstimate = minutes }
            }
        } label: {
            Text(explicitEstimate.map { DueLogic.estimateText(minutes: $0) } ?? "Est.").font(.callout)
        }
        .menuStyle(.borderlessButton)
        .help("Estimated time")
        .accessibilityLabel("Estimated time")
    }

    // MARK: - Smart parse

    /// True while a debounced smart-parse call is in flight for the current text.
    private var isUsingSmartResult: Bool {
        guard let smartResult else { return false }
        return smartResult.text == text
    }

    /// Debounces 400ms after the last keystroke, then asks the on-device model for a parse.
    /// Cancels any in-flight parse for stale text first. Errors fall back to the regex parse
    /// silently; only the outer bar's preview line reflects readiness via `isSmartParsing`.
    private func scheduleSmartParse(for newText: String) {
        smartTask?.cancel()
        smartTask = nil
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard state.settings.smartParsing, SmartQuickAddParser.isAvailable, trimmed.count >= Self.smartParseMinChars else {
            isSmartParsing = false
            return
        }
        let now = state.now
        let courses = state.courses
        isSmartParsing = true
        smartTask = Task {
            try? await Task.sleep(nanoseconds: Self.smartParseDebounce)
            guard !Task.isCancelled else { return }
            do {
                let result = try await smart.parse(newText, now: now, knownCourses: courses)
                if !Task.isCancelled, text == newText { smartResult = (newText, result) }
            } catch {
                NSLog("Due: smart quick-add parse failed, using regex parse: \(error.localizedDescription)")
            }
            if text == newText { isSmartParsing = false }
        }
    }

    /// Waits for an in-flight smart parse (up to `performAddWait`) so pressing Enter fast still
    /// gets the better parse when it lands in time; otherwise proceeds with what's available.
    private func awaitSmartParse() async {
        guard let smartTask, isSmartParsing else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await smartTask.value }
            group.addTask { try? await Task.sleep(nanoseconds: UInt64(Self.performAddWait * 1_000_000_000)) }
            await group.next()
            group.cancelAll()
        }
    }

    // MARK: - Preview & add

    /// Model fields win where present for text still matching the parse; the regex parse fills
    /// every gap, exactly as `QuickAddParse.merging` documents.
    private var parsedNow: QuickAddParse {
        let base = QuickAddParser.parse(text, now: state.now)
        if let smartResult, smartResult.text == text {
            return base.merging(smartResult.result, now: state.now)
        }
        return base
    }

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
    /// otherwise the parsed value, otherwise the picker date. Wrapped in a `Task` so it stays
    /// callable synchronously from `.onSubmit` while it awaits an in-flight smart parse.
    private func performAdd() {
        Task { await performAddAsync() }
    }

    private func performAddAsync() async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await awaitSmartParse()
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
        smartTask?.cancel()
        smartTask = nil
        smartResult = nil
        isSmartParsing = false
        isFocused.wrappedValue = true
    }
}
