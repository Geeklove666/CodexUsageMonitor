import CoreServices
import Foundation

/// Uses the native macOS FSEvents service to coalesce local CLI data changes.
/// It never opens or reads changed files; parsing remains in the authorized providers.
final class LocalUsageEventMonitor: @unchecked Sendable {
    private let paths: [String]
    private let queue = DispatchQueue(label: "local.codex-usage-monitor.file-events", qos: .utility)
    private let lock = NSLock()
    private var stream: FSEventStreamRef?
    private var pendingWork: DispatchWorkItem?
    var onChange: (@Sendable () -> Void)?

    init(paths: [URL]) {
        self.paths = paths.map(\.path)
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard stream == nil, !paths.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<LocalUsageEventMonitor>.fromOpaque(info).takeUnretainedValue().scheduleChange()
        }
        guard let created = FSEventStreamCreate(
            nil,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.8,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else { return }
        stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
    }

    func stop() {
        lock.lock()
        let current = stream
        stream = nil
        pendingWork?.cancel()
        pendingWork = nil
        lock.unlock()
        guard let current else { return }
        FSEventStreamStop(current)
        FSEventStreamInvalidate(current)
        FSEventStreamRelease(current)
    }

    private func scheduleChange() {
        lock.lock()
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange?() }
        pendingWork = work
        lock.unlock()
        queue.asyncAfter(deadline: .now() + 1, execute: work)
    }

    deinit { stop() }
}
