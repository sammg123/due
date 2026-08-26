import SwiftUI
import DueCore

@main
struct DueApp: App {
    @State private var state = AppState.loadFromDisk()

    init() { DebugHooks.installIfRequested() }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(state)
        } label: {
            MenuBarLabel()
                .environment(state)
        }
        .menuBarExtraStyle(.window)

        // Only opened when launched as `Due --preview`: the popover in a normal window, for screenshots and dev.
        Window("Due Preview", id: "preview") {
            PopoverView()
                .environment(state)
        }
        .windowResizability(.contentSize)
    }
}

/// Always mounted, so it also owns the once-a-minute clock refresh that rolls buckets over at midnight.
struct MenuBarLabel: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @State private var clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        let count = state.todayCount
        Group {
            if count > 0 {
                Label("\(count)", systemImage: "checklist")
            } else {
                Image(systemName: "checklist")
            }
        }
        .onReceive(clock) { state.refreshNow($0) }
        .onAppear {
            if CommandLine.arguments.contains("--preview") {
                openWindow(id: "preview")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .accessibilityLabel(count > 0 ? "\(count) due today" : "Nothing due today")
    }
}
