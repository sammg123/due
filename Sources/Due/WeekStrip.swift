import SwiftUI
import DueCore

/// Week navigation header plus the 7-day load strip: today plus the next 6 days, each a
/// weekday letter over a small load dot. Dot color reads absolute load (not urgency), so it
/// stays meaningful even for days past the "this week" bucket. The header lets the caller page
/// between weeks and select either a single day or the whole visible week.
struct WeekStrip: View {
    let days: [WeekDay]
    let title: String
    let selectedDay: Date?
    /// True when the whole visible week (not a single day) is the active scope.
    let isWeekScope: Bool
    let canGoBack: Bool
    let onSelectDay: (Date) -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSelectWeek: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            weekHeader

            HStack(spacing: 0) {
                ForEach(days) { day in
                    WeekStripColumn(
                        day: day,
                        isSelected: selectedDay.map { Calendar.current.isDate($0, inSameDayAs: day.date) } ?? false,
                        onSelect: { onSelectDay(day.date) }
                    )
                }
            }
        }
    }

    private var weekHeader: some View {
        HStack(spacing: 4) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(canGoBack ? .secondary : Color.secondary.opacity(0.35))
            .disabled(!canGoBack)
            .help("Previous week")
            .accessibilityLabel("Previous week")

            Spacer(minLength: 4)

            Button(action: onSelectWeek) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isWeekScope ? Color.accentColor : .primary)
            }
            .buttonStyle(.plain)
            .help("Select this week")
            .accessibilityLabel("Select week: \(title)")
            .accessibilityAddTraits(isWeekScope ? .isSelected : [])

            Spacer(minLength: 4)

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Next week")
            .accessibilityLabel("Next week")
        }
    }
}

private struct WeekStripColumn: View {
    let day: WeekDay
    let isSelected: Bool
    let onSelect: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                Text(day.weekdayLetter)
                    .font(.caption2)
                    .fontWeight(day.isToday || isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.accentColor : (day.isToday ? .primary : .secondary))

                loadDot

                Text(day.count > 0 ? "\(day.count)" : "0")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .opacity(day.count > 0 ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.18))
                } else if day.isToday {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.quaternary)
                }
            }
        }
        .buttonStyle(.plain)
        .help("\(day.count) due \(fullDateText)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var loadDot: some View {
        ZStack {
            Circle()
                .strokeBorder(.secondary, lineWidth: 1)
                .opacity(day.count == 0 ? 1 : 0)
            Circle()
                .fill(fillColor ?? .clear)
                .opacity(day.count == 0 ? 0 : 1)
        }
        .frame(width: 8, height: 8)
        .animation(reduceMotion ? nil : .easeOut(duration: Theme.animationBase), value: day.count)
    }

    /// Absolute load, not urgency: 1 to 2 is light, 3 to 4 is moderate, 5+ is heavy.
    private var fillColor: Color? {
        switch day.count {
        case 0: return nil
        case 1...2: return .blue
        case 3...4: return .orange
        default: return .red
        }
    }

    private var fullDateText: String {
        Self.fullDateFormatter.string(from: day.date)
    }

    private var accessibilityText: String {
        let prefix = day.isToday ? "Today, " : ""
        let dueText = day.count == 1 ? "1 due" : "\(day.count) due"
        return "\(prefix)\(fullDateText), \(dueText)"
    }

    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()
}
