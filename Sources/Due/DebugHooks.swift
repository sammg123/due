import AppKit

/// Dev-only, enabled with `DUE_DEBUG=1`. Lets a shell drive the real menu bar popover without
/// Accessibility permission: SIGUSR1 clicks the status item, SIGUSR2 sends Escape to the key window.
enum DebugHooks {
    private static var sources: [DispatchSourceSignal] = []

    static func installIfRequested() {
        guard ProcessInfo.processInfo.environment["DUE_DEBUG"] == "1" else { return }
        install(SIGUSR1) { StatusItem.click() }
        install(SIGUSR2) { sendEscape() }
    }

    private static func install(_ sig: Int32, _ action: @escaping () -> Void) {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler(handler: action)
        source.resume()
        sources.append(source)
    }

    private static func sendEscape() {
        guard let window = NSApp.keyWindow,
              let down = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil,
                characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53
              ) else {
            NSLog("DebugHooks: no key window")
            return
        }
        window.sendEvent(down)
    }
}
