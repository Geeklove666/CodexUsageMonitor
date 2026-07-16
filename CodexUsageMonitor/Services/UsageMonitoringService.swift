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
    private var analyticsTask: Task<Void, Never>?
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
        analyticsTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            let previous = self.snapshot
            async let realtimeValue = self.realtimeTokenReader.analyticsSnapshot()
            do {
                var quota = try await self.repository.fetchQuota()
                if let realtime = await realtimeValue { quota = quota.mergingAnalytics(realtime) }
                self.snapshot = quota
                self.diagnostic = await self.repository.currentDiagnostic()
                if quota.isCached || quota.isEstimated {
                    self.lastError = self.diagnostic.lastFailure ?? "未能获取新额度，正在保留上次数据"
                    self.failures += 1
                    self.logger.warning("Quota refresh fell back to \(quota.sourceKind.rawValue, privacy: .public)")
                } else {
                    self.lastError = nil
                    self.failures = 0
                    self.logger.info("Quota refresh succeeded via \(quota.sourceKind.rawValue, privacy: .public)")
                }
                await self.persistAndNotify(previous: previous, current: quota)
                self.startAnalyticsEnrichment(for: quota)
            } catch {
                if let realtime = await realtimeValue {
                    self.snapshot = self.snapshot.mergingAnalytics(realtime)
                }
                self.failures += 1
                let redacted = SensitiveDataRedactor().redact(error.localizedDescription)
                let quotaError = UserDefaults.standard.bool(forKey: LocalCodexSessionAuthorization.preferenceKey)
                    ? redacted : "尚未授权复用本机 Codex 登录"
                self.lastError = self.snapshot.analytics?.todayTokens == nil
                    ? quotaError : "\(quotaError)；今日 Token 保留上次结果"
                self.logger.error("Usage refresh failed: \(redacted, privacy: .public)")
                self.diagnostic = await self.repository.currentDiagnostic()
            }
        }
        await refreshTask?.value
        refreshTask = nil
        isRefreshing = false; now = .now
    }

    private func startAnalyticsEnrichment(for quota: CodexUsageSnapshot) {
        analyticsTask = Task { [weak self] in
            guard let self else { return }
            let enriched = await self.repository.fetchAnalytics(for: quota)
            guard !Task.isCancelled else { return }
            if let analytics = enriched.analytics {
                self.snapshot = self.snapshot.mergingAnalytics(analytics)
            }
            self.logger.info("Analytics enrichment finished")
            do {
                if try self.history.saveIfNeeded(self.snapshot, processActive: self.processMonitor.isActive()) {
                    self.historyRevision += 1
                }
            } catch {
                self.persistenceWarning = "历史保存失败：\(SensitiveDataRedactor().redact(error.localizedDescription))"
            }
            self.diagnostic = await self.repository.currentDiagnostic()
        }
    }

    private func persistAndNotify(previous: CodexUsageSnapshot, current: CodexUsageSnapshot) async {
        let reset = resetDetector.isReset(old: previous, new: current)
        do {
            if try history.saveIfNeeded(current, processActive: processMonitor.isActive()) {
                historyRevision += 1
            }
        } catch {
            persistenceWarning = "历史保存失败：\(SensitiveDataRedactor().redact(error.localizedDescription))"
        }
        await notificationService.evaluate(previous: previous, current: current, reset: reset)
    }

    func cancel() {
        loopTask?.cancel(); refreshTask?.cancel(); analyticsTask?.cancel()
        loopTask = nil; refreshTask = nil; analyticsTask = nil
    }
}
