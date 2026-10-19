import SwiftUI
import WidgetKit
import DueCore

struct DueWidgetEntryView: View {
    let entry: DueEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallDueView(entry: entry)
        default:
            ListDueView(entry: entry)
        }
    }
}

// MARK: - Small: the menu bar number plus the next few titles. The Notes button opens Notes;
// everywhere else opens quick add.

struct SmallDueView: View {
    let entry: DueEntry
    private var snapshot: WidgetSnapshot { entry.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("\(snapshot.todayCount)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(countColor)
                    .contentTransition(.numericText())
                Spacer()
                HStack(spacing: 6) {
                    NotesButton()
                    AddGlyph()
                }
            }
            Text(snapshot.countCaption)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            if let error = entry.loadError {
                LoadErrorText(message: error)
            } else if snapshot.isEmpty {
                Label("All caught up", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(snapshot.rows) { row in
                        HStack(spacing: 6) {
                            UrgencyBar(bucket: row.bucket, height: 12)
                            Text(row.title)
                                .font(.system(size: 12))
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .widgetURL(DueLink.add.url)
    }

    private var countColor: Color {
        if snapshot.overdueCount > 0 { return PaletteStyle.color(DueBucket.overdue) }
        if snapshot.todayCount > 0 { return PaletteStyle.color(DueBucket.today) }
        return .primary
    }
}

// MARK: - Medium and large: headline, add button, and checkable rows. Tapping elsewhere opens Due.

struct ListDueView: View {
    let entry: DueEntry
    private var snapshot: WidgetSnapshot { entry.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let error = entry.loadError {
                LoadErrorText(message: error)
            } else if snapshot.isEmpty {
                emptyState
            } else {
                VStack(spacing: 4) {
                    ForEach(snapshot.rows) { DueRowView(row: $0) }
                }
            }
            Spacer(minLength: 0)
        }
        .widgetURL(DueLink.open.url)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(entry.loadError == nil ? snapshot.headline : "Due")
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            if snapshot.hiddenCount > 0 {
                Text("\(snapshot.hiddenCount) more")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            NotesButton()
            Link(destination: DueLink.add.url) { AddGlyph() }
        }
    }

    private var emptyState: some View {
        Image(systemName: "checkmark.circle")
            .font(.system(size: 30, weight: .light))
            .foregroundStyle(.green)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Nothing open")
    }
}

/// Mirrors the popover row: urgency bar, done circle, title over course, short due text.
private struct DueRowView: View {
    let row: WidgetRow

    var body: some View {
        HStack(spacing: 8) {
            UrgencyBar(bucket: row.bucket, height: 22)

            Button(intent: ToggleDoneIntent(id: row.id)) {
                Image(systemName: "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark \(row.title) done")

            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if let course = row.course {
                    Text(course)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(PaletteStyle.color(row.courseColor))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            Text(row.dueText)
                .font(.system(size: 11.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(PaletteStyle.textColor(row.bucket))
                .lineLimit(1)
        }
        .frame(height: 30)
    }
}

// MARK: - Pieces

private struct UrgencyBar: View {
    let bucket: DueBucket
    let height: CGFloat

    var body: some View {
        Capsule()
            .fill(PaletteStyle.color(bucket))
            .frame(width: 3, height: height)
            .widgetAccentable()
    }
}

/// The + mark. A `Link` in medium and large; the small widget's whole surface is the link.
private struct AddGlyph: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if renderingMode == .fullColor {
            glyph.foregroundStyle(.white)
                .background(Circle().fill(Color.accentColor))
        } else {
            // When the desktop dims widgets to gray, a white + on a filled circle turns into one
            // flat disc; draw it like the Notes icon so the + stays visible.
            glyph.foregroundStyle(.primary)
                .background(Circle().fill(.quaternary))
        }
    }

    private var glyph: some View {
        Image(systemName: "plus")
            .font(.system(size: 12, weight: .bold))
            .frame(width: 24, height: 24)
            .accessibilityLabel("Add assignment")
    }
}

/// Opens the Notes window. A `Link` like the +, except in the small widget: that whole widget
/// is the add link, and only an intent button gets its own tap target inside it.
private struct NotesButton: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .systemSmall {
            Button(intent: OpenNotesIntent()) { NotesGlyph() }
                .buttonStyle(.plain)
        } else {
            Link(destination: DueLink.notes.url) { NotesGlyph() }
        }
    }
}

/// Quieter than the + so adding stays the widget's main action.
private struct NotesGlyph: View {
    var body: some View {
        Image(systemName: "note.text")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 24, height: 24)
            .background(Circle().fill(.quaternary))
            .accessibilityLabel("Open Notes")
    }
}

private struct LoadErrorText: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Can't read your list")
                .font(.system(size: 12, weight: .semibold))
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }
}
