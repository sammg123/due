import SwiftUI
import DueCore

/// What is showing inline over the menu bar panel. Edit and settings used to be `.popover`s, but a
/// popover is its own window: focusing it makes the panel resign key and the panel closes itself.
@Observable
final class PanelOverlay {
    enum Content: Equatable {
        case edit(Assignment)
        case settings
    }

    var content: Content?

    func edit(_ assignment: Assignment) { content = .edit(assignment) }
    func showSettings() { content = .settings }
    func close() { content = nil }
}

/// Dimmed scrim plus a card, drawn inside the panel's own window. Clicking the scrim closes it.
struct PanelOverlayHost: View {
    @Environment(AppState.self) private var state
    @Environment(PanelOverlay.self) private var overlay

    var body: some View {
        if let content = overlay.content {
            ZStack {
                Color.black.opacity(0.35)
                    .contentShape(Rectangle())
                    .onTapGesture { overlay.close() }
                card(for: content)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
                    .shadow(radius: 12)
                    .padding(12)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func card(for content: PanelOverlay.Content) -> some View {
        switch content {
        case .edit(let assignment):
            EditAssignmentView(assignment: assignment, onClose: overlay.close)
                .environment(state)
                .id(assignment.id)
        case .settings:
            ScrollView { SettingsView(onClose: overlay.close).environment(state) }
                .frame(maxHeight: Theme.popoverMaxHeight - 40)
        }
    }
}
