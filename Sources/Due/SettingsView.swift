import SwiftUI
import AppKit
import DueCore

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            launchAtLoginSection
            urgencySection
            courseColorsSection
            dataSection
            doneRow
        }
        .padding(16)
        .frame(width: 300)
    }

    // MARK: - Launch at login

    private var launchAtLoginSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("General")
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    applyLaunchAtLogin(newValue)
                }
            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchAtLoginError = nil
            var next = state.settings
            next.launchAtLogin = enabled
            state.updateSettings(next)
        } catch {
            launchAtLogin = !enabled
            launchAtLoginError = error.localizedDescription
        }
    }

    // MARK: - Urgency

    private var urgencySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Urgency")
            Stepper(
                "Soon: within \(state.settings.soonDays) days",
                value: soonDaysBinding,
                in: 1...14
            )
            Stepper(
                "This week: within \(state.settings.weekDays) days",
                value: weekDaysBinding,
                in: (state.settings.soonDays + 1)...30
            )
        }
    }

    /// Raising "soon" past "this week" pulls "this week" along so it stays the larger value.
    private var soonDaysBinding: Binding<Int> {
        Binding(
            get: { state.settings.soonDays },
            set: { newValue in
                var next = state.settings
                next.soonDays = newValue
                if next.weekDays <= newValue {
                    next.weekDays = min(30, newValue + 1)
                }
                state.updateSettings(next)
            }
        )
    }

    private var weekDaysBinding: Binding<Int> {
        Binding(
            get: { state.settings.weekDays },
            set: { newValue in
                var next = state.settings
                next.weekDays = newValue
                state.updateSettings(next)
            }
        )
    }

    // MARK: - Course colors

    private var courseColorsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Course colors")
            if state.courses.isEmpty {
                Text("Add a course from the Course menu or with #Name in the add field.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.courses, id: \.self) { course in
                    CourseColorRow(course: course, state: state)
                }
            }
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Data")
            Text(abbreviatedStoragePath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([JSONStore.defaultURL()])
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }

    private var abbreviatedStoragePath: String {
        let path = JSONStore.defaultURL().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }

    // MARK: - Done

    private var doneRow: some View {
        HStack {
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }
}

/// Uppercase `.caption` secondary section header, matching the settings surface's
/// no-Form-chrome layout.
private struct SectionLabel: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// One course's name plus a color picker menu. The menu's closed-state label is an
/// icon-only swatch, so it carries `.help()` and `.accessibilityLabel()`.
private struct CourseColorRow: View {
    let course: String
    let state: AppState

    var body: some View {
        HStack {
            Text(course)
            Spacer()
            if !state.isCourseInUse(course) {
                Button {
                    state.removeCourse(course)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove \(course) (no assignments use it)")
                .accessibilityLabel("Remove \(course)")
            }
            Menu {
                ForEach(PaletteColor.allCases, id: \.self) { palette in
                    Button {
                        state.setColor(palette, forCourse: course)
                    } label: {
                        Label {
                            Text(palette.rawValue.capitalized)
                        } icon: {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(Theme.color(palette))
                        }
                    }
                }
            } label: {
                Circle()
                    .fill(Theme.color(state.color(forCourse: course)))
                    .frame(width: 12, height: 12)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Change color for \(course)")
            .accessibilityLabel("Color for \(course)")
        }
    }
}
