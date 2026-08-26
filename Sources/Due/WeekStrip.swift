import SwiftUI
import DueCore

/// Glanceable 7-day load strip: today plus the next 6 days, each a weekday letter over a
/// small load dot. Dot color reads absolute load (not urgency), so it stays meaningful
/// even for days past the "this week" bucket.
struct WeekStrip: View {
    let days: [WeekDay]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                WeekStripColumn(day: day)
            }
        }
    }
}

private struct WeekStripColumn: View {
    let day: WeekDay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            Text(day.weekdayLetter)
                .font(.caption2)
                .fontWeight(day.isToday ? .semibold : .regular)
                .foregroundStyle(day.isToday ? .primary : .secondary)

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
            if day.isToday {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quaternary)
            }
        }
        .help("\(day.count) due \(fullDateText)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
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
