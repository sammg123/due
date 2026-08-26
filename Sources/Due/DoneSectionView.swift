import SwiftUI
import DueCore

/// Collapsible "Done" content, placed as the last `Section`'s body in the list.
/// A `Group` (not a stack) so each row is still a separate List row when embedded.
struct DoneSectionView: View {
    let items: [Assignment]
    let stats: DoneStats
    @AppStorage("doneExpanded") private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            headerRow
            if expanded {
                statsRow
                ForEach(items) { item in
                    AssignmentRow(assignment: item)
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
            }
        }
    }

    private var headerRow: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: Theme.animationBase)) {
                expanded.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .font(.caption2)
                Text("Done (\(items.count))")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .accessibilityLabel(expanded ? "Collapse done section" : "Expand done section")
    }

    private var statsRow: some View {
        statsText
            .font(.caption)
            .foregroundStyle(.secondary)
            .listRowSeparator(.hidden)
    }

    private var statsText: Text {
        if let rate = stats.onTimeRate {
            Text("\(stats.completedThisWeek) done this week · \(Int(rate * 100))% on time")
        } else {
            Text("\(stats.completedThisWeek) done this week")
        }
    }
}
