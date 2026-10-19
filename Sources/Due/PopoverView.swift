import SwiftUI
import AppKit
import DueCore

/// Top-level popover content: header, week strip, quick add, bucketed list (with a
/// collapsible Done section folded in), and footer.
struct PopoverView: View {
    @Environment(AppState.self) private var state
    @Environment(LectureEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @FocusState private var quickAddFocused: Bool
    @State private var overlay = PanelOverlay()
    @AppStorage("doneExpanded") private var doneExpanded = false

    @State private var weekOffset = 0
    @State private var scope: ListScope = .all
    @State private var courseFilter: String? = nil

    /// How many weeks back paging is allowed to go.
    private static let maxWeeksBack = 4

    private var filteredGroups: [BucketGroup] { state.grouped(course: courseFilter, scope: scope) }
    private var openGroups: [BucketGroup] { filteredGroups.filter { $0.bucket != .done } }
    private var doneItems: [Assignment] { filteredGroups.first { $0.bucket == .done }?.items ?? [] }
    private var hasOpenItems: Bool { state.openCount(course: courseFilter, scope: scope) > 0 }
    /// The list (with its scope bar) stays visible while scoped even if that scope is empty,
    /// so the scoped empty message can show instead of the generic "nothing at all" state.
    private var showList: Bool { !scope.isAll || hasOpenItems || !doneItems.isEmpty }

    private var selectedDay: Date? {
        if case .day(let day) = scope { return day }
        return nil
    }

    private var isWeekScope: Bool {
        if case .week = scope { return true }
        return false
    }

    private var canGoBackAWeek: Bool { weekOffset > -Self.maxWeeksBack }

    var body: some View {
        VStack(spacing: 0) {
            header

            if let error = state.lastError {
                errorBanner(error)
            }

            WeekStrip(
                days: state.weekLoad(offset: weekOffset, course: courseFilter),
                title: state.weekTitle(offset: weekOffset),
                selectedDay: selectedDay,
                isWeekScope: isWeekScope,
                canGoBack: canGoBackAWeek,
                onSelectDay: selectDay,
                onPrevious: goToPreviousWeek,
                onNext: goToNextWeek,
                onSelectWeek: toggleWeekScope
            )
                .padding(.horizontal, 12)
                .padding(.top, 8)

            QuickAddBar(isFocused: $quickAddFocused)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            if state.courses.count >= 1 {
                CourseFilterBar(selected: $courseFilter)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            if !scope.isAll {
                scopeBar
            }

            if showList {
                list
                    .frame(height: listHeight)
                    .animation(reduceMotion ? nil : .easeOut(duration: Theme.animationBase), value: listHeight)
            } else {
                emptyState
            }

            footer
        }
        .frame(width: Theme.popoverWidth)
        .frame(maxHeight: Theme.popoverMaxHeight)
        .onAppear {
            state.refreshNow()
            scope = .all
            weekOffset = 0
        }
        .overlay(escapeButton)
        .overlay { PanelOverlayHost() }
        .animation(reduceMotion ? nil : .easeOut(duration: Theme.animationFast), value: overlay.content)
        .environment(overlay)
    }

    // MARK: - Week and scope navigation

    private func selectDay(_ day: Date) {
        if case .day(let current) = scope, Calendar.current.isDate(current, inSameDayAs: day) {
            scope = .all
        } else {
            scope = .day(day)
        }
    }

    private func toggleWeekScope() {
        if isWeekScope {
            scope = .all
        } else {
            scope = .week(state.weekInterval(offset: weekOffset))
        }
    }

    private func goToPreviousWeek() {
        weekOffset -= 1
        scope = weekOffset == 0 ? .all : .week(state.weekInterval(offset: weekOffset))
    }

    private func goToNextWeek() {
        weekOffset += 1
        scope = weekOffset == 0 ? .all : .week(state.weekInterval(offset: weekOffset))
    }

    // MARK: - Scope bar

    private var scopeBar: some View {
        HStack(spacing: 4) {
            Text(scopeTitle)
                .fontWeight(.semibold)
            Text("· \(state.openCount(course: courseFilter, scope: scope)) open")
                .foregroundStyle(.secondary)
            Spacer()
            Button("All") {
                scope = .all
                weekOffset = 0
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .help("Show all assignments")
            .accessibilityLabel("Show all assignments")
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var scopeTitle: String {
        switch scope {
        case .all: return ""
        case .day(let day): return state.dayTitle(day)
        case .week: return state.weekTitle(offset: weekOffset)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Due").font(.title3.weight(.semibold))
            if engine.isActive {
                recordingPill
            }
            Spacer()
            Text(summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                openNotes()
            } label: {
                Image(systemName: "note.text")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .help("Notes (⇧⌘N)")
            .accessibilityLabel("Notes")
            Button {
                overlay.showSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    /// Visible whenever a lecture is being captured, even with the notes window closed,
    /// so a live mic is never invisible. Click-through to the note.
    private var recordingPill: some View {
        Button {
            openNotes()
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)
                Text(LectureEngine.elapsedText(engine.elapsed))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 7)
            .background(.red.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Recording a lecture. Open Notes")
        .accessibilityLabel("Recording a lecture, \(LectureEngine.elapsedText(engine.elapsed)) elapsed. Open Notes")
    }

    private func openNotes() {
        openWindow(id: "notes")
        NSApp.activate(ignoringOtherApps: true)
        dismiss()
    }

    private var summaryText: String {
        var summary = state.todayCount > 0 ? "\(state.todayCount) today" : "Nothing today"
        if state.openEstimateMinutesThisWeek > 0 {
            summary += " · \(DueLogic.estimateText(minutes: state.openEstimateMinutesThisWeek)) this week"
        }
        return summary
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button {
                state.clearError()
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
    }

    // MARK: - List

    private var list: some View {
        List {
            if !hasOpenItems {
                emptyStateView(innerEmptyText)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }
            ForEach(openGroups) { group in
                BucketSectionView(group: group)
            }
            if !doneItems.isEmpty {
                Section {
                    DoneSectionView(items: doneItems, stats: state.doneStats)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(reduceMotion ? nil : .easeOut(duration: Theme.animationBase), value: filteredGroups)
    }

    /// Estimated content height so the menu bar window can size itself; the list scrolls past `listMaxHeight`.
    private var listHeight: CGFloat {
        let open = openGroups.reduce(CGFloat(0)) { total, group in
            total + Theme.sectionHeaderHeight + rowsHeight(group.items)
        }
        let doneRows = doneExpanded ? Theme.statsLineHeight + rowsHeight(doneItems) : 0
        let done = doneItems.isEmpty ? 0 : Theme.sectionHeaderHeight + doneRows
        let empty = hasOpenItems ? 0 : Theme.emptyStateHeight
        return min(Theme.listMaxHeight, open + done + empty + 8)
    }

    private func rowsHeight(_ items: [Assignment]) -> CGFloat {
        items.reduce(CGFloat(0)) { total, item in
            let wraps = item.title.count > Theme.titleCharsPerLine
            return total + Theme.rowHeight + (wraps ? Theme.extraTitleLineHeight : 0)
        }
    }

    private var emptyState: some View {
        emptyStateView("Nothing due. Add something above.")
    }

    /// The inner empty message shown inside the list frame when the current scope has no open
    /// items. Scoped views get a scope-specific message instead of the generic one.
    private var innerEmptyText: String {
        switch scope {
        case .all: return "Nothing due. Add something above."
        case .day(let day): return "Nothing due \(state.dayTitle(day))."
        case .week: return "Nothing due this week."
        }
    }

    private func emptyStateView(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Clear completed") { state.clearCompleted() }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .disabled(doneItems.isEmpty)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Escape to dismiss

    private var escapeButton: some View {
        Button("", action: { if overlay.content != nil { overlay.close() } else { dismiss() } })
            .keyboardShortcut(.escape, modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}
