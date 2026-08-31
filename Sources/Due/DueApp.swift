import SwiftUI
import DueCore

@main
struct DueApp: App {
    @State private var state = AppState.loadFromDisk()
    @State private var notesState = NotesState.loadFromDisk()
    // App-level so a recording survives the notes window closing.
    @State private var lectureEngine = LectureEngine()

    init() { DebugHooks.installIfRequested() }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(state)
                .environment(notesState)
                .environment(lectureEngine)
        } label: {
            MenuBarLabel()
                .environment(state)
        }
        .menuBarExtraStyle(.window)

        Window("Notes", id: "notes") {
            NotesWindowView()
                .environment(state)
                .environment(notesState)
                .environment(lectureEngine)
        }
        .defaultSize(width: Theme.notesDefaultWidth, height: Theme.notesDefaultHeight)

        // Only opened when launched as `Due --preview`: the popover in a normal window, for screenshots and dev.
        Window("Due Preview", id: "preview") {
            PopoverView()
                .environment(state)
                .environment(notesState)
                .environment(lectureEngine)
        }
        .windowResizability(.contentSize)

        // `Due --preview-settings`: the settings popover content in a window, for screenshots.
        Window("Due Settings Preview", id: "settings-preview") {
            SettingsView()
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
            if CommandLine.arguments.contains("--preview-settings") {
                openWindow(id: "settings-preview")
                NSApp.activate(ignoringOtherApps: true)
            }
            // `Due --notes`: straight into the notes window, for screenshots and dev.
            if CommandLine.arguments.contains("--notes") {
                openWindow(id: "notes")
                NSApp.activate(ignoringOtherApps: true)
            }
            // `Due --ai-test <cleanUp|summarize|outline> <file>` or
            // `Due --ai-test custom <file> <instruction>`: run a note AI action inside
            // the real app process and exit. Prints result or error to stdout for dev use.
            if let idx = CommandLine.arguments.firstIndex(of: "--ai-test") {
                let args = CommandLine.arguments
                let kind = args.count > idx + 1 ? args[idx + 1] : ""
                let text = args.count > idx + 2 ? (try? String(contentsOfFile: args[idx + 2], encoding: .utf8)) : nil
                let instruction = args.count > idx + 3 ? args[idx + 3] : nil
                let modelSetting = state.settings.notesAIModel
                Task {
                    do {
                        let ai = NoteAI()
                        let out: String
                        if kind == "custom", let text, let instruction {
                            out = try await ai.runCustom(instruction, on: text, modelSetting: modelSetting)
                        } else if let action = NoteAIAction(rawValue: kind), let text {
                            out = try await ai.run(action, on: text, modelSetting: modelSetting)
                        } else {
                            print("usage: Due --ai-test <cleanUp|summarize|outline> <file> | custom <file> <instruction>")
                            exit(2)
                        }
                        print("AI-TEST OK via \(ai.engineName ?? "?") (\(out.count) chars)\n\(out)")
                        exit(0)
                    } catch {
                        print("AI-TEST ERR: \(String(describing: error))")
                        exit(1)
                    }
                }
            }
        }
        .accessibilityLabel(count > 0 ? "\(count) due today" : "Nothing due today")
    }
}
