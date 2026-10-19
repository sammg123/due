import Foundation
import Observation

/// Single source of truth for the UI. Every mutation replaces `data` with a new value and persists it.
@MainActor
@Observable
public final class AppState {
    public private(set) var data: AppData
    /// Refreshed by the app on a timer so buckets roll over at midnight without a relaunch.
    public private(set) var now: Date
    public private(set) var lastError: String?

    private let store: JSONStore?
    private let calendar: Calendar

    public init(data: AppData = .empty, store: JSONStore? = nil, now: Date = Date(), calendar: Calendar = .current) {
        self.data = data
        self.store = store
        self.now = now
        self.calendar = calendar
    }

    /// Loads from the default file. A corrupt file is kept on disk and reported via `lastError`.
    public static func loadFromDisk() -> AppState {
        let store = JSONStore(url: JSONStore.defaultURL())
        do {
            return AppState(data: try store.load(), store: store)
        } catch {
            let state = AppState(data: .empty, store: nil)
            state.lastError = "Could not read \(store.url.lastPathComponent): \(error.localizedDescription)"
            return state
        }
    }

    // MARK: - Derived

    public var assignments: [Assignment] { data.assignments }
    public var settings: DueSettings { data.settings }
    public var grouped: [BucketGroup] { DueLogic.grouped(data.assignments, now: now, settings: data.settings, calendar: calendar) }
    public var todayCount: Int { DueLogic.todayCount(data.assignments, now: now, calendar: calendar) }
    public var openCount: Int { data.assignments.filter { !$0.isDone }.count }
    public var weekLoad: [WeekDay] { DueLogic.weekLoad(data.assignments, now: now, calendar: calendar) }

    // MARK: Week navigation and filtering

    public func weekInterval(offset: Int) -> DateInterval {
        DueLogic.weekInterval(containing: now, offsetWeeks: offset, calendar: calendar)
    }

    /// Load strip for the calendar week `offset` weeks from now, optionally narrowed to one course.
    public func weekLoad(offset: Int, course: String? = nil) -> [WeekDay] {
        let items = DueLogic.filter(data.assignments, course: course, scope: .all, calendar: calendar)
        return DueLogic.weekLoad(items, week: weekInterval(offset: offset), now: now, calendar: calendar)
    }

    public func weekTitle(offset: Int) -> String {
        DueLogic.weekTitle(weekInterval(offset: offset), now: now, calendar: calendar)
    }

    public func dayTitle(_ day: Date) -> String {
        DueLogic.dayTitle(day, now: now, calendar: calendar)
    }

    /// Bucketed list narrowed by course and scope.
    public func grouped(course: String?, scope: ListScope) -> [BucketGroup] {
        let items = DueLogic.filter(data.assignments, course: course, scope: scope, calendar: calendar)
        return DueLogic.grouped(items, now: now, settings: data.settings, calendar: calendar)
    }

    public func openCount(course: String?, scope: ListScope) -> Int {
        DueLogic.filter(data.assignments, course: course, scope: scope, calendar: calendar).filter { !$0.isDone }.count
    }
    public var doneStats: DoneStats { DueLogic.doneStats(data.assignments, now: now, calendar: calendar) }
    public var openEstimateMinutesThisWeek: Int {
        DueLogic.openEstimateMinutesThisWeek(data.assignments, now: now, settings: data.settings, calendar: calendar)
    }

    /// Every known course: ones used by an assignment (most recently used first) followed by
    /// registered-but-unused ones (alphabetical). A course is registered the moment it gets a color.
    public var courses: [String] {
        let ordered = data.assignments.sorted { $0.createdAt > $1.createdAt }
        var seen = Set<String>()
        let used = ordered.compactMap { a -> String? in
            guard let c = a.course, !c.isEmpty, !seen.contains(c) else { return nil }
            seen.insert(c)
            return c
        }
        let unused = data.courseColors.keys.filter { !seen.contains($0) }.sorted()
        return used + unused
    }

    public func isCourseInUse(_ course: String) -> Bool {
        data.assignments.contains { $0.course == course }
    }

    public func color(forCourse course: String) -> PaletteColor {
        data.courseColors[course] ?? .gray
    }

    public func bucket(for assignment: Assignment) -> DueBucket {
        DueLogic.bucket(for: assignment, now: now, settings: data.settings, calendar: calendar)
    }

    public func relativeDueText(for assignment: Assignment) -> String {
        DueLogic.relativeDueText(for: assignment.dueDate, now: now, calendar: calendar)
    }

    // MARK: - Mutations
    //
    // Each one first adopts any edit the desktop widget wrote to disk, so the save that follows
    // builds on it instead of writing stale memory over it.

    @discardableResult
    public func add(title: String, course: String?, dueDate: Date, estimateMinutes: Int? = nil, notes: String? = nil) -> Assignment? {
        reloadFromDisk()
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return nil }
        let cleanCourse = course?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextOrder = (data.assignments.map(\.sortOrder).max() ?? -1) + 1
        let item = Assignment(
            title: cleanTitle,
            course: (cleanCourse?.isEmpty ?? true) ? nil : cleanCourse,
            dueDate: dueDate,
            estimateMinutes: estimateMinutes,
            notes: notes,
            createdAt: Date(),
            sortOrder: nextOrder
        )
        var next = data
        next.assignments = data.assignments + [item]
        if let c = item.course, next.courseColors[c] == nil {
            next.courseColors[c] = Self.nextCourseColor(existing: next.courseColors)
        }
        commit(next)
        return item
    }

    /// Parses "pset 4 fri 5pm #CS225 ~2h". Explicit UI fields win over parsed ones when provided.
    @discardableResult
    public func addQuick(_ text: String, fallbackDue: Date, course: String? = nil, estimateMinutes: Int? = nil) -> Assignment? {
        let parsed = QuickAddParser.parse(text, now: now, calendar: calendar)
        return add(
            title: parsed.title,
            course: course ?? parsed.course,
            dueDate: parsed.dueDate ?? fallbackDue,
            estimateMinutes: estimateMinutes ?? parsed.estimateMinutes
        )
    }

    public func update(_ assignment: Assignment) {
        reloadFromDisk()
        guard let idx = data.assignments.firstIndex(where: { $0.id == assignment.id }) else { return }
        var next = data
        var items = data.assignments
        items[idx] = assignment
        next.assignments = items
        if let c = assignment.course, !c.isEmpty, next.courseColors[c] == nil {
            next.courseColors[c] = Self.nextCourseColor(existing: next.courseColors)
        }
        commit(next)
    }

    public func toggleDone(_ id: UUID) {
        reloadFromDisk()
        guard let item = data.assignments.first(where: { $0.id == id }) else { return }
        update(item.togglingDone(at: Date()))
    }

    public func delete(_ id: UUID) {
        reloadFromDisk()
        var next = data
        next.assignments = data.assignments.filter { $0.id != id }
        commit(next)
    }

    public func clearCompleted() {
        reloadFromDisk()
        var next = data
        next.assignments = data.assignments.filter { !$0.isDone }
        commit(next)
    }

    /// Drag reorder inside one bucket. Offsets are relative to the bucket's displayed items.
    public func move(in bucket: DueBucket, fromOffsets: IndexSet, toOffset: Int) {
        // Offsets index the list as it was drawn; if the widget changed it since, they are stale.
        guard !reloadFromDisk() else { return }
        guard bucket != .done else { return }
        guard let group = grouped.first(where: { $0.bucket == bucket }) else { return }
        applyOrder(group.items.moving(fromOffsets: fromOffsets, toOffset: toOffset))
    }

    /// Resets a bucket to due-date order.
    public func sortByDueDate(in bucket: DueBucket) {
        reloadFromDisk()
        guard let group = grouped.first(where: { $0.bucket == bucket }) else { return }
        applyOrder(group.items.sorted { $0.dueDate < $1.dueDate })
    }

    /// Groups a bucket by course (alphabetical, no-course last), due date within a course.
    public func sortByCourse(in bucket: DueBucket) {
        reloadFromDisk()
        guard let group = grouped.first(where: { $0.bucket == bucket }) else { return }
        applyOrder(group.items.sorted {
            let a = $0.course ?? "\u{FFFF}", b = $1.course ?? "\u{FFFF}"
            if a != b { return a.localizedCaseInsensitiveCompare(b) == .orderedAscending }
            return $0.dueDate < $1.dueDate
        })
    }

    private func applyOrder(_ ordered: [Assignment]) {
        // Reuse the bucket's existing sortOrder slots so relative position vs other buckets is unchanged.
        let slots = ordered.map(\.sortOrder).sorted()
        let byID = Dictionary(zip(ordered.map(\.id), slots), uniquingKeysWith: { first, _ in first })
        var next = data
        next.assignments = data.assignments.map { a in
            guard let slot = byID[a.id] else { return a }
            return a.withSortOrder(slot)
        }
        commit(next)
    }

    /// Adds a course to the dropdown (and gives it a color) before any assignment uses it.
    /// Returns the cleaned name, or nil if it was blank.
    @discardableResult
    public func registerCourse(_ name: String) -> String? {
        reloadFromDisk()
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        guard data.courseColors[clean] == nil else { return clean }
        var next = data
        next.courseColors[clean] = Self.nextCourseColor(existing: next.courseColors)
        commit(next)
        return clean
    }

    /// Removes a course that no assignment uses. Returns false (and changes nothing) if it is in use.
    @discardableResult
    public func removeCourse(_ course: String) -> Bool {
        reloadFromDisk()
        guard !isCourseInUse(course) else { return false }
        var next = data
        next.courseColors.removeValue(forKey: course)
        commit(next)
        return true
    }

    public func setColor(_ color: PaletteColor, forCourse course: String) {
        reloadFromDisk()
        var next = data
        next.courseColors[course] = color
        commit(next)
    }

    public func updateSettings(_ settings: DueSettings) {
        reloadFromDisk()
        var next = data
        next.settings = settings
        commit(next)
    }

    /// Adopts the file on disk when another writer (the desktop widget's checkboxes) changed it.
    /// Does not save. Returns true when `data` changed.
    @discardableResult
    public func reloadFromDisk() -> Bool {
        guard let store else { return false }
        do {
            guard let fresh = try store.loadIfChanged(comparedTo: data) else { return false }
            data = fresh
            return true
        } catch {
            lastError = "Could not read \(store.url.lastPathComponent): \(error.localizedDescription)"
            return false
        }
    }

    public func refreshNow(_ date: Date = Date()) {
        now = date
    }

    public func clearError() { lastError = nil }

    // MARK: - Private

    private func commit(_ next: AppData) {
        data = next
        guard let store else { return }
        do {
            try store.save(next)
        } catch {
            lastError = "Could not save: \(error.localizedDescription)"
        }
    }

    static func nextCourseColor(existing: [String: PaletteColor]) -> PaletteColor {
        let used = Set(existing.values)
        if let free = PaletteColor.courseRotation.first(where: { !used.contains($0) }) { return free }
        return PaletteColor.courseRotation[existing.count % PaletteColor.courseRotation.count]
    }
}
