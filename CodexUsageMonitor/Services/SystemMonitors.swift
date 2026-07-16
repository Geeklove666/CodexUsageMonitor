import AppKit
import Foundation
import Network

struct CodexProcessMonitor: Sendable {
    func isActive() -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            let name = app.localizedName?.lowercased() ?? ""
            let bundle = app.bundleIdentifier?.lowercased() ?? ""
            return name.contains("codex") || bundle.contains("codex")
        }
    }
}

final class NetworkMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "CodexUsageMonitor.Network")
    private let lock = NSLock()
    private var _online = true
    var isOnline: Bool { lock.withLock { _online } }
    var onRestored: (@Sendable () -> Void)?
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let wasOnline = lock.withLock { let old = _online; _online = path.status == .satisfied; return old }
            if !wasOnline && path.status == .satisfied { onRestored?() }
        }
        monitor.start(queue: queue)
    }
    deinit { monitor.cancel() }
}

struct ResetDetectionService: Sendable {
    func isReset(old: CodexUsageSnapshot, new: CodexUsageSnapshot) -> Bool {
        guard !new.isEstimated, new.confidence != .low,
              new.fetchedAt > old.fetchedAt,
              let before = old.primaryWindow?.remainingPercentage,
              let after = new.primaryWindow?.remainingPercentage,
              after - before >= 30, after >= 70 else { return false }
        if let oldReset = old.primaryWindow?.resetsAt, let newReset = new.primaryWindow?.resetsAt { return newReset > oldReset }
        return true
    }
}

extension NSLock {
    fileprivate func withLock<T>(_ body: () -> T) -> T { lock(); defer { unlock() }; return body() }
}
