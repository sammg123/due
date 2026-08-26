import Foundation
import ServiceManagement

/// Thin wrapper around `SMAppService.mainApp`.
///
/// Only functions when running from a real `.app` bundle (e.g. `~/Applications/Due.app`).
/// Running from `.build/debug/Due` directly, `setEnabled` throws, so callers must catch
/// the error and surface it rather than assume success.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ on: Bool) throws {
        if on {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
