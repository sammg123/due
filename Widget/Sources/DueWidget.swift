import SwiftUI
import WidgetKit
import DueCore
import os

/// Desktop widget: what's due next, a checkbox per row, and a + that opens Due's quick add.
struct DueWidget: Widget {
    static let kind = "DueWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: DueProvider()) { entry in
            DueWidgetEntryView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Due")
        .description("What's due next, with a quick way to add more.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct DueEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// Set when the assignments file exists but could not be read.
    let loadError: String?

    static func make(_ loaded: Result<AppData, Error>, at date: Date, family: WidgetFamily) -> DueEntry {
        switch loaded {
        case .success(let data):
            return DueEntry(date: date, snapshot: .make(from: data, now: date, limit: family.rowLimit), loadError: nil)
        case .failure(let error):
            return DueEntry(date: date, snapshot: .make(from: .empty, now: date, limit: 0), loadError: error.localizedDescription)
        }
    }

    /// Gallery preview and placeholder content, used only when there is nothing real to show.
    static func sample(at date: Date, family: WidgetFamily) -> DueEntry {
        let calendar = Calendar.current
        func at(days: Int, hour: Int, minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: days, to: date) ?? date
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        let items = [
            Assignment(title: "Problem set 5", course: "MATH 126", dueDate: at(days: 0, hour: 17), sortOrder: 0),
            Assignment(title: "Essay draft", course: "WRIT 150", dueDate: at(days: 1, hour: 23, minute: 59), sortOrder: 1),
            Assignment(title: "Read chapter 7", course: "ECON 203", dueDate: at(days: 2, hour: 9), sortOrder: 2),
            Assignment(title: "Lab report", course: "BISC 120", dueDate: at(days: 4, hour: 23, minute: 59), sortOrder: 3),
        ]
        let colors: [String: PaletteColor] = ["MATH 126": .blue, "WRIT 150": .purple, "ECON 203": .teal, "BISC 120": .pink]
        let data = AppData(assignments: items, courseColors: colors, settings: DueSettings())
        return make(.success(data), at: date, family: family)
    }
}

struct DueProvider: TimelineProvider {
    func placeholder(in context: Context) -> DueEntry {
        .sample(at: Date(), family: context.family)
    }

    func getSnapshot(in context: Context, completion: @escaping (DueEntry) -> Void) {
        let now = Date()
        let loaded = WidgetDataSource.load()
        if context.isPreview, case .success(let data) = loaded, data.assignments.allSatisfy(\.isDone) {
            completion(.sample(at: now, family: context.family))
            return
        }
        completion(.make(loaded, at: now, family: context.family))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DueEntry>) -> Void) {
        let now = Date()
        let loaded = WidgetDataSource.load()
        let data = (try? loaded.get()) ?? .empty
        let entries = WidgetTimeline.entryDates(for: data, from: now).map {
            DueEntry.make(loaded, at: $0, family: context.family)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

/// Reads the same assignments.json the app writes (see the sandbox exception in project.yml).
/// The widget never sees `DUE_DATA_PATH`, so a dev build pointed elsewhere and the widget disagree.
enum WidgetDataSource {
    static let log = Logger(subsystem: "com.due.tracker.widget", category: "data")

    static func load() -> Result<AppData, Error> {
        let store = JSONStore(url: JSONStore.defaultURL())
        do {
            return .success(try store.load())
        } catch {
            log.error("Could not read \(store.url.path, privacy: .public): \(String(describing: error), privacy: .public)")
            return .failure(error)
        }
    }
}

extension WidgetFamily {
    /// Rows that fit without crowding: small lists titles only, large gets a full list.
    var rowLimit: Int {
        switch self {
        case .systemLarge: return 8
        default: return 3
        }
    }
}
