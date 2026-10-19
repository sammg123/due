import Foundation

/// `due://` links the desktop widget opens in the app.
public enum DueLink: String, CaseIterable, Sendable {
    /// Show the quick-add box.
    case add
    /// Open the menu bar popover.
    case open
    /// Open the Notes window.
    case notes

    public static let scheme = "due"

    public var url: URL {
        var parts = URLComponents()
        parts.scheme = Self.scheme
        parts.host = rawValue
        guard let url = parts.url else { preconditionFailure("DueLink \(rawValue) is not a valid URL") }
        return url
    }

    /// Accepts `due://add`, `due://open` and `due://notes` in any case, with or without a trailing slash.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let host = url.host?.lowercased(),
              let link = DueLink(rawValue: host) else { return nil }
        self = link
    }
}
