import SwiftUI
import AppKit
import DueCore

/// Top-level popover content: header, week strip, quick add, bucketed list (with a
/// collapsible Done section folded in), and footer.
struct PopoverView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @FocusState private var quickAddFocused: Bool
    @State private var showSettings = false
    @AppStorage("doneExpanded") private var doneExpanded = false

    private var openGroups: [BucketGroup] { state.grouped.filter { $0.bucket != .done } }
    private var doneItems: [Assignment] { state.grouped.first { $0.bucket == .done }?.items ?? [] }
    private var hasOpenItems: Bool { state.assignments.contains { !$0.isDone } }

    var body: some View {
        VStack(spacing: 0) {
            header

            if let error = state.lastError {
                errorBanner(error)
            }

            WeekStrip(days: state.weekLoad)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            QuickAddBar(isFocused: $quickAddFocused)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            if hasOpenItems || !doneItems.isEmpty {
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
        .onAppear { state.refreshNow() }
        .overlay(escapeButton)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Due").font(.headline)
            Spacer()
            Text(summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")
            .accessibilityLabel("Settings")
            .popover(isPresented: $showSettings) {
                SettingsView().environment(state)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
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
                emptyState
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
        .animation(reduceMotion ? nil : .easeOut(duration: Theme.animationBase), value: state.grouped)
    }

    /// Estimated content height so the menu bar window can size itself; the list scrolls past `listMaxHeight`.
    private var listHeight: CGFloat {
        let open = openGroups.reduce(CGFloat(0)) { total, group in
            total + Theme.sectionHeaderHeight + CGFloat(group.items.count) * Theme.rowHeight
        }
        let doneRows = doneExpanded ? Theme.statsLineHeight + CGFloat(doneItems.count) * Theme.rowHeight : 0
        let done = doneItems.isEmpty ? 0 : Theme.sectionHeaderHeight + doneRows
        let empty = hasOpenItems ? 0 : Theme.emptyStateHeight
        return min(Theme.listMaxHeight, open + done + empty + 8)
    }

    private var emptyState: some View {
        Text("Nothing due. Add something above.")
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
        Button("", action: { dismiss() })
            .keyboardShortcut(.escape, modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}
