import Foundation
import Observation

@MainActor @Observable
final class UsageMonitoringService {
    private let logger = AppLogger(.monitoring)
    private let repository: any CodexUsageRepository
    private let realtimeTokenReader: any RealtimeTokenUsageReading
    private let snapshotPipeline: UsageSnapshotPipeline
    private let refreshPolicy = RefreshPolicy()
    private let scheduler = RefreshScheduler()
    private let networkMonitor = NetworkMonitor()
    private var refreshTask: Task<Void, Never>?
    private var activeRefreshForceRefresh = false
    private var refreshGeneration: UInt64 = 0
    private var analyticsTask: Task<Void, Never>?
    private var failures = 0
    private var lastMenuOpenAt: Date?
    private var automaticRefreshSuspended = false

    @ObservationIgnored var displayStateDidChange: (() -> Void)?
    var snapshot = CodexUsageSnapshot.unavailable {
        didSet { if oldValue != snapshot { displayStateDidChange?() } }
    }
    var isRefreshing = false
    var lastFailure: UsageFailure?
    @ObservationIgnored var now = Date.now
    var historyRevision = 0
    var diagnostic = DataSourceDiagnostic()
    var persistenceWarning: String?
    var status: MonitoringStatus {
        MonitoringStatus(snapshot: snapshot, failure: lastFailure, isRefreshing: isRefreshing)
    }

    init(repository: any CodexUsageRepository,
         realtimeTokenReader: any RealtimeTokenUsageReading,
         snapshotPipeline: UsageSnapshotPipeline,
         initialSnapshot: CodexUsageSnapshot = .unavailable) {
        self.repository = repository
        self.realtimeTokenReader = realtimeTokenReader
        self.snapshotPipeline = snapshotPipeline
        snapshot = initialSnapshot
        networkMonitor.onRestored = { [weak self] in
            Task { @MainActor in self?.refreshAfterNetworkRestore() }
        }
    }

    func start() {
        guard !scheduler.isAutomaticLoopRunning else { return }
        startLoop(refreshImmediately: true)
    }

    func restartRefreshLoop() {
        scheduler.stopAutomaticLoop()
        guard !automaticRefreshSuspended else { return }
        startLoop(refreshImmediately: false)
    }

    private func startLoop(refreshImmediately: Bool) {
        scheduler.startAutomaticLoop(
            refreshImmediately: refreshImmediately,
            delayProvider: { [weak self] in self?.automaticRefreshDelay() ?? 600 },
            refresh: { [weak self] reason in
                await self?.refresh(reason: reason, forceRefresh: false)
            }
        )
    }

    private func automaticRefreshDelay() -> TimeInterval {
        now = .now
        let configured = UserDefaults.standard.object(forKey: AppPreferences.Key.autoRefreshSeconds) as? Int
            ?? AutoRefreshFrequency.defaultValue.rawValue
        let process = ProcessInfo.processInfo
        return refreshPolicy.automaticDelay(
            configuredSeconds: configured,
            failureCount: failures,
            lastMenuOpenAt: lastMenuOpenAt,
            now: now,
            isLowPowerModeEnabled: process.isLowPowerModeEnabled,
            hasThermalPressure: process.thermalState == .serious || process.thermalState == .critical,
            jitterFactor: Double.random(in: 0.95...1.05)
        )
    }

    func noteMenuOpened() {
        lastMenuOpenAt = .now
        now = .now
    }

    func updateClock() {
        let current = Date.now
        guard current.timeIntervalSince(now) >= 30 else { return }
        now = current
        displayStateDidChange?()
    }

    func suspendAutomaticRefresh() {
        automaticRefreshSuspended = true
        scheduler.cancelAll()
    }

    func resumeAfterWake() {
        automaticRefreshSuspended = false
        now = .now
        displayStateDidChange?()
        guard !scheduler.isAutomaticLoopRunning else { return }
        startLoop(refreshImmediately: false)
        Task { [weak self] in
            await self?.refresh(reason: "系统唤醒", forceRefresh: false)
        }
    }

    func refreshIfStaleForMenuOpen(maxAge: TimeInterval = AppConfiguration.Refresh.menuFreshnessLimit) async {
        noteMenuOpened()
        if refreshPolicy.shouldRefreshOnMenuOpen(
            snapshot: snapshot,
            hasFailure: lastFailure != nil,
            isRefreshing: isRefreshing,
            maxAge: maxAge,
            now: .now
        ) {
            await refresh(reason: "菜单打开", forceRefresh: false)
        }
    }

    func refresh(reason: String = "手动刷新", forceRefresh: Bool = true) async {
        if let refreshTask {
            let existingGeneration = refreshGeneration
            let existingIsForceRefresh = activeRefreshForceRefresh
            await refreshTask.value
            guard forceRefresh, !existingIsForceRefresh else { return }
            if refreshGeneration == existingGeneration {
                self.refreshTask = nil
                activeRefreshForceRefresh = false
                isRefreshing = false
            }
        }
        isRefreshing = true
        logger.debug("Refresh requested: \(reason), force=\(forceRefresh)")
        refreshGeneration &+= 1
        let generation = refreshGeneration
        activeRefreshForceRefresh = forceRefresh
        analyticsTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            let previous = self.snapshot
            async let realtimeValue = self.realtimeTokenReader.currentAnalyticsSnapshot()
            do {
                var quota = try await self.repository.fetchQuota(forceRefresh: forceRefresh)
                if let realtime = await realtimeValue { quota = quota.mergingAnalytics(realtime) }
                self.snapshot = quota
                self.diagnostic = await self.repository.currentDiagnostic()
                self.diagnostic.lastRefreshReason = reason
                if quota.isCached || quota.isEstimated {
                    let message = self.diagnostic.lastFailure ?? "未能获取新额度，正在保留上次数据"
                    self.lastFailure = UsageFailure(
                        kind: self.diagnostic.lastFailureKind ?? .unavailable,
                        userMessage: message,
                        diagnosticMessage: message
                    )
                    self.failures += 1
                    self.logger.warning("Quota refresh fell back to \(quota.sourceKind.rawValue)")
                } else {
                    self.lastFailure = nil
                    self.failures = 0
                    self.logger.info("Quota refresh succeeded via \(quota.sourceKind.rawValue)")
                }
                self.applyPipelineResult(await self.snapshotPipeline.process(previous: previous, current: quota))
                self.scheduleResetBoundaryRefresh(for: quota)
                self.startAnalyticsEnrichment(for: quota, generation: generation)
            } catch {
                if let realtime = await realtimeValue {
                    self.snapshot = self.snapshot.mergingAnalytics(realtime)
                }
                self.failures += 1
                var failure = UsageFailure(error: error)
                if self.snapshot.analytics?.todayTokens != nil {
                    failure = failure.appendingUserContext("今日 Token 保留上次结果")
                }
                self.lastFailure = failure
                self.logger.error("Usage refresh failed [\(failure.kind.rawValue)]: \(failure.diagnosticMessage)")
                self.diagnostic = await self.repository.currentDiagnostic()
                self.diagnostic.lastRefreshReason = reason
            }
        }
        await refreshTask?.value
        if refreshGeneration == generation {
            refreshTask = nil
            activeRefreshForceRefresh = false
            isRefreshing = false
            now = .now
        }
    }

    private func startAnalyticsEnrichment(for quota: CodexUsageSnapshot, generation: UInt64) {
        analyticsTask = Task { [weak self] in
            guard let self else { return }
            let enriched = await self.repository.fetchAnalytics(for: quota, forceRefresh: false)
            guard !Task.isCancelled,
                  self.refreshGeneration == generation,
                  self.snapshot.id == quota.id
            else {
                self.logger.info("Discarded stale analytics enrichment")
                return
            }
            if let analytics = enriched.analytics {
                self.snapshot = self.snapshot.mergingAnalytics(analytics)
            }
            self.logger.info("Analytics enrichment finished")
            self.applyPipelineResult(self.snapshotPipeline.persistAnalytics(self.snapshot))
            let refreshReason = self.diagnostic.lastRefreshReason
            self.diagnostic = await self.repository.currentDiagnostic()
            self.diagnostic.lastRefreshReason = refreshReason
        }
    }

    private func scheduleResetBoundaryRefresh(for snapshot: CodexUsageSnapshot) {
        guard !snapshot.isCached, !snapshot.isEstimated else {
            scheduler.scheduleResetBoundary(at: nil, now: .now) {}
            return
        }
        let current = Date.now
        let nextReset = [snapshot.primaryWindow?.resetsAt, snapshot.secondaryWindow?.resetsAt]
            .compactMap { $0 }
            .filter { $0 > current }
            .min()
        scheduler.scheduleResetBoundary(at: nextReset, now: current) { [weak self] in
            guard let self else { return }
            self.now = .now
            await self.refresh(reason: "额度重置边界", forceRefresh: false)
        }
    }

    private func applyPipelineResult(_ result: UsageSnapshotPipelineResult) {
        if result.historyChanged { historyRevision += 1 }
        if let warning = result.persistenceWarning { persistenceWarning = warning }
    }

    private func refreshAfterNetworkRestore() {
        guard !automaticRefreshSuspended else { return }
        scheduler.scheduleNetworkRestore { [weak self] in
            guard let self, !self.automaticRefreshSuspended else { return }
            await self.refresh(reason: "网络恢复", forceRefresh: false)
        }
    }

    func cancel() {
        refreshTask?.cancel()
        analyticsTask?.cancel()
        scheduler.cancelAll()
        refreshTask = nil
        analyticsTask = nil
    }

}
