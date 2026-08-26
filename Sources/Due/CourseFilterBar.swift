import SwiftUI
import DueCore

/// Horizontal row of course chips ("All" plus every known course) that narrows the list to
/// one course. Wraps in a horizontal scroll view once there are more chips than fit at the
/// popover width.
struct CourseFilterBar: View {
    @Binding var selected: String?
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                chip(title: "All", isSelected: selected == nil, tint: .accentColor) {
                    selected = nil
                }
                ForEach(state.courses, id: \.self) { course in
                    chip(
                        title: course,
                        isSelected: selected == course,
                        tint: Theme.color(state.color(forCourse: course))
                    ) {
                        selected = (selected == course) ? nil : course
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func chip(title: String, isSelected: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .foregroundStyle(isSelected ? tint : .secondary)
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(
                    isSelected ? AnyShapeStyle(tint.opacity(0.22)) : AnyShapeStyle(.quaternary),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
