import Foundation

/// An action whose handler shows up later than the first request for it, like a SwiftUI
/// window opener that only exists once a view has appeared. Requests made before then run
/// once, on install.
@MainActor
public final class DeferredAction {
    private var handler: (() -> Void)?
    private var isPending = false

    public init() {}

    public func install(_ handler: @escaping () -> Void) {
        self.handler = handler
        guard isPending else { return }
        isPending = false
        handler()
    }

    public func run() {
        guard let handler else {
            isPending = true
            return
        }
        handler()
    }
}
