import SwiftUI
import DueCore

/// One list row: urgency bar, done toggle, title/course/estimate, relative due text,
/// and hover-only edit/delete actions.
struct AssignmentRow: View {
    let assignment: Assignment
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var showEdit = false

    private var bucket: DueBucket { state.bucket(for: assignment) }

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(Theme.color(bucket))
                .frame(width: Theme.urgencyBarWidth)

            doneToggle

            VStack(alignment: .leading, spacing: 2) {
                Text(assignment.title)
                    .font(.body)
                    .lineLimit(1)
                    .strikethrough(assignment.isDone)

                if assignment.course != nil || assignment.estimateMinutes != nil {
                    HStack(spacing: 6) {
                        if let course = assignment.course {
                            Text(course)
                                .font(.caption2)
                                .padding(.vertical, 2)
                                .padding(.horizontal, 6)
                                .background(
                                    Theme.color(state.color(forCourse: course)).opacity(0.18),
                                    in: Capsule()
                                )
                                .foregroundStyle(Theme.color(state.color(forCourse: course)))
                        }
                        if let estimate = assignment.estimateMinutes {
                            HStack(spacing: 2) {
                                Image(systemName: "clock")
                                Text(DueLogic.estimateText(minutes: estimate))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer(minLength: 4)

            Text(state.relativeDueText(for: assignment))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.textColor(bucket))
                .help(DueLogic.fullDueText(for: assignment.dueDate))

            if isHovering {
                Button { showEdit = true } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Edit assignment")
                .accessibilityLabel("Edit assignment")

                Button { state.delete(assignment.id) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Delete assignment")
                .accessibilityLabel("Delete assignment")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(minHeight: 28)
        .opacity(assignment.isDone ? 0.5 : 1)
        .contentShape(Rectangle())
        .background(
            isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: Theme.rowCornerRadius)
        )
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { showEdit = true }
        .popover(isPresented: $showEdit) {
            EditAssignmentView(assignment: assignment)
                .environment(state)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: Theme.animationFast), value: assignment.isDone)
    }

    private var doneToggle: some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) {
                state.toggleDone(assignment.id)
            }
        } label: {
            Image(systemName: assignment.isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(assignment.isDone ? Theme.color(bucket) : .secondary)
        }
        .buttonStyle(.plain)
        .help(assignment.isDone ? "Mark not done" : "Mark done")
        .accessibilityLabel(assignment.isDone ? "Mark not done" : "Mark done")
    }
}
