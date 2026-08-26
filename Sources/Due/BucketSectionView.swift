import SwiftUI
import DueCore

/// One bucket's `Section` inside the list: uppercased title + count header (with a
/// "sort by due date" context menu) and its reorderable rows.
struct BucketSectionView: View {
    let group: BucketGroup
    @Environment(AppState.self) private var state

    var body: some View {
        Section {
            ForEach(group.items) { assignment in
                AssignmentRow(assignment: assignment)
            }
            .onMove { state.move(in: group.bucket, fromOffsets: $0, toOffset: $1) }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
        } header: {
            header
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
        }
        .listSectionSeparator(.hidden)
        .listSectionSeparatorTint(.clear)
        .listRowSeparatorTint(.clear)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(group.bucket.title.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textColor(group.bucket))
            Text("\(group.items.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .contextMenu {
            Button("Sort by due date") { state.sortByDueDate(in: group.bucket) }
            Button("Sort by course") { state.sortByCourse(in: group.bucket) }
        }
    }
}
