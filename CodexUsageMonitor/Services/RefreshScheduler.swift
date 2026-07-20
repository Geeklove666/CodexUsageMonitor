import Foundation

@MainActor
final class RefreshScheduler {
    private var automaticLoopTask: Task<Void, Never>?
    private var resetBoundaryTask: Task<Void, Never>?
    private var networkRestoreTask: Task<Void, Never>?

    var isAutomaticLoopRunning: Bool { automaticLoopTask != nil }

    func startAutomaticLoop(
        refreshImmediately: Bool,
        delayProvider: @escaping @MainActor () -> TimeInterval,
        refresh: @escaping @MainActor (String) async -> Void
    ) {
        guard automaticLoopTask == nil else { return }
        automaticLoopTask = Task { [weak self] in
            guard self != nil else { return }
            if refreshImmediately { await refresh("启动刷新") }
            while !Task.isCancelled {
                let delay = delayProvider()
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await refresh("自动刷新")
            }
        }
    }

    func stopAutomaticLoop() {
        automaticLoopTask?.cancel()
        automaticLoopTask = nil
    }

    func scheduleResetBoundary(
        at resetDate: Date?,
        now: Date,
        action: @escaping @MainActor () async -> Void
    ) {
        resetBoundaryTask?.cancel()
        resetBoundaryTask = nil
        guard let resetDate, resetDate > now else { return }
        let grace = AppConfiguration.Refresh.resetBoundaryGrace
        let delay = max(grace, resetDate.timeIntervalSince(now) + grace)
        resetBoundaryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await action()
            self?.resetBoundaryTask = nil
        }
    }

    func scheduleNetworkRestore(action: @escaping @MainActor () async -> Void) {
        networkRestoreTask?.cancel()
        networkRestoreTask = Task { [weak self] in
            do {
                try await Task.sleep(for: AppConfiguration.Refresh.networkRestoreDebounce)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await action()
            self?.networkRestoreTask = nil
        }
    }

    func cancelDeferredWork() {
        resetBoundaryTask?.cancel()
        networkRestoreTask?.cancel()
        resetBoundaryTask = nil
        networkRestoreTask = nil
    }

    func cancelAll() {
        stopAutomaticLoop()
        cancelDeferredWork()
    }
}
