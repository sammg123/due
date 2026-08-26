import Foundation

extension Array {
    /// Same semantics as SwiftUI's `move(fromOffsets:toOffset:)`, without importing SwiftUI into the core.
    /// `toOffset` is a position in the ORIGINAL array (insert-before index), matching `onMove`.
    func moving(fromOffsets source: IndexSet, toOffset destination: Int) -> [Element] {
        let moved = source.map { self[$0] }
        var remaining: [Element] = []
        var insertAt = destination
        for (i, element) in enumerated() {
            if source.contains(i) {
                if i < destination { insertAt -= 1 }
            } else {
                remaining.append(element)
            }
        }
        let clamped = Swift.max(0, Swift.min(insertAt, remaining.count))
        remaining.insert(contentsOf: moved, at: clamped)
        return remaining
    }
}
