import Foundation

/// Calls `onChange` (on the main queue, debounced) when the file is written by anyone.
/// Watches the parent directory because atomic saves replace the file rather than editing it.
public final class DataFileWatcher {
    private static let debounce: TimeInterval = 0.2

    private let source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    /// False when the folder could not be opened; edits from elsewhere then show after relaunch.
    public var isWatching: Bool { source != nil }

    public init(fileURL: URL, onChange: @escaping () -> Void) {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            NSLog("Due: could not create \(directory.path) to watch it: \(error.localizedDescription)")
        }
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("Due: could not watch \(directory.path) (errno \(errno)); widget edits show after relaunch")
            source = nil
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        self.source = source
        source.setEventHandler { [weak self] in self?.schedule(onChange) }
        source.setCancelHandler { close(fd) }
        source.resume()
    }

    deinit { source?.cancel() }

    private func schedule(_ onChange: @escaping () -> Void) {
        pending?.cancel()
        let work = DispatchWorkItem(block: onChange)
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounce, execute: work)
    }
}
