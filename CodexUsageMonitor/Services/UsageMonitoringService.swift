import Foundation
import Observation
import OSLog

@MainActor @Observable
final class UsageMonitoringService {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "local.codex-usage-monitor", category: "monitoring")
    private let repository: DefaultCodexUsageRepository
    private let history: UsageHistoryStore
    private let realtimeTokenReader: LocalRealtimeTokenUsageReader
    private let processMonitor = CodexProcessMonitor()
    private let networkMonitor = NetworkMonitor()
    private let notificationService = NotificationService()
    private let resetDetector = ResetDetectionService()
    private var loopTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var failures = 0

    var snapshot = CodexUsageSnapshot.unavailable
    var isRefreshing = false
    var lastError: String?
    var now = Date.now
    var historyRevision = 0
    var diagnostic = DataSourceDiagnostic()
    var persistenceWarning: String?
    var status: MonitoringStatus {
        MonitoringStatus(snapshot: snapshot, lastError: lastError, isRefreshing: isRefreshing)
    }

    init(repository: DefaultCodexUsageRepository, history: UsageHistoryStore,
         realtimeTokenReader: LocalRealtimeTokenUsageReader = LocalRealtimeTokenUsageReader(),
         initialSnapshot: CodexUsageSnapshot = .unavailable) {
        self.repository = repository; self.history = history
        self.realtimeTokenReader = realtimeTokenReader; snapshot = initialSnapshot
        networkMonitor.onRestored = { [weak self] in Task { @MainActor in await self?.refresh() } }
    }

    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            await self?.refresh()
            while !Task.isCancelled {
                guard let self else { return }
                self.now = .now
                let defaults = UserDefaults.standard
                let active = max(30, defaults.double(forKey: "activeRefreshSeconds"))
                let idle = max(30, defaults.double(forKey: "idleRefreshSeconds"))
                let base = defaults.bool(forKey: "smartRefresh") ? (self.processMonitor.isActive() ? active : idle) : idle
                let backoff = [0.0, 60, 120, 300, 600, 1800][min(self.failures, 5)]
                let delay = max(base, backoff) * Double.random(in: 0.95...1.05)
                try? await Task.sleep(for: .seconds(delay))
                await self.refresh()
            }
        }
    }

    func refresh() async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        isRefreshing = true
        refreshTask = Task { [weak self] in
            guard let self else { return }
            let realtime = await self.realtimeTokenReader.analyticsSnapshot()
            if let realtime { self.snapshot = self.snapshot.mergingAnalytics(realtime) }
            guard self.networkMonitor.isOnline else {
                self.lastError = UsageMonitorError.networkUnavailable.localizedDescription
                return
            }
            do {
                let previous = self.snapshot
                var quota = try await self.repository.fetchQuota()
                if let realtime { quota = quota.mergingAnalytics(realtime) }
                self.snapshot = quota
                self.lastError = nil
                self.failures = 0
                self.logger.info("Quota refresh succeeded via \(quota.sourceKind.rawValue, privacy: .public)")
                self.isRefreshing = false

                let value = await self.repository.fetchAnalytics(for: quota)
                self.snapshot = value
                self.logger.info("Analytics enrichment finished")
                let reset = self.resetDetector.isReset(old: previous, new: value)
                do {
                    if try self.history.saveIfNeeded(value, processActive: self.processMonitor.isActive()) {
                        self.historyRevision += 1
                    }
                } catch {
                    self.persistenceWarning = "历史保存失败：\(SensitiveDataRedactor().redact(error.localizedDescription))"
                }
                await self.notificationService.evaluate(previous: previous, current: value, reset: reset)
            } catch {
                self.failures += 1
                let redacted = SensitiveDataRedactor().redact(error.localizedDescription)
                self.lastError = realtime == nil ? redacted : "额度刷新失败；今日 Token 已更新"
                self.logger.error("Usage refresh failed: \(redacted, privacy: .public)")
            }
            self.diagnostic = await self.repository.currentDiagnostic()
        }
        await refreshTask?.value
        refreshTask = nil
        isRefreshing = false; now = .now
    }

    func cancel() { loopTask?.cancel(); refreshTask?.cancel(); loopTask = nil; refreshTask = nil }
}
