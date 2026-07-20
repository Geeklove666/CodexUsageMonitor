import Foundation
import Observation
import OSLog

@MainActor @Observable
final class UsageMonitoringService {
    static let refreshIntervalPreferenceKey = "autoRefreshSeconds"

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "local.codex-usage-monitor", category: "monitoring")
    private let repository: any CodexUsageRepository
    private let realtimeTokenReader: any RealtimeTokenUsageReading
    private let snapshotPipeline: UsageSnapshotPipeline
    private let refreshPolicy = RefreshPolicy()
    private let networkMonitor = NetworkMonitor()
    private var loopTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var activeRefreshForceRefresh = false
    private var refreshGeneration: UInt64 = 0
    private var analyticsTask: Task<Void, Never>?
    private var resetBoundaryTask: Task<Void, Never>?
    private var networkRestoreTask: Task<Void, Never>?
    private var failures = 0
    private var lastMenuOpenAt: Date?
    private var automaticRefreshSuspended = false

    @ObservationIgnored var displayStateDidChange: (() -> Void)?
    var snapshot = CodexUsageSnapshot.unavailable {
        didSet { if oldValue != snapshot { displayStateDidChange?() } }
    }
    var isRefreshing = false
    var lastError: String?
    @ObservationIgnored var now = Date.now
    var historyRevision = 0
    var diagnostic = DataSourceDiagnostic()
    var persistenceWarning: String?
    var status: MonitoringStatus {
        MonitoringStatus(snapshot: snapshot, lastError: lastError, isRefreshing: isRefreshing)
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
            Task { @MainActor in await self?.refreshAfterNetworkRestore() }
        }
    }

    func start() {
        guard loopTask == nil else { return }
        startLoop(refreshImmediately: true)
    }

    func restartRefreshLoop() {
        loopTask?.cancel()
        loopTask = nil
        guard !automaticRefreshSuspended else { return }
        startLoop(refreshImmediately: false)
    }

    private func startLoop(refreshImmediately: Bool) {
        loopTask = Task { [weak self] in
            if refreshImmediately { await self?.refresh(reason: "启动刷新", forceRefresh: false) }
            while !Task.isCancelled {
                guard let self else { return }
                self.now = .now
                let defaults = UserDefaults.standard
                let configured = defaults.object(forKey: Self.refreshIntervalPreferenceKey) as? Int
                    ?? AutoRefreshFrequency.defaultValue.rawValue
                let process = ProcessInfo.processInfo
                let delay = refreshPolicy.automaticDelay(
                    configuredSeconds: configured,
                    failureCount: self.failures,
                    lastMenuOpenAt: self.lastMenuOpenAt,
                    now: self.now,
                    isLowPowerModeEnabled: process.isLowPowerModeEnabled,
                    hasThermalPressure: process.thermalState == .serious || process.thermalState == .critical,
                    jitterFactor: Double.random(in: 0.95...1.05)
                )
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self.refresh(reason: "自动刷新", forceRefresh: false)
            }
        }
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
        loopTask?.cancel()
        resetBoundaryTask?.cancel()
        networkRestoreTask?.cancel()
        loopTask = nil
        resetBoundaryTask = nil
        networkRestoreTask = nil
    }

    func resumeAfterWake() {
        automaticRefreshSuspended = false
        now = .now
        displayStateDidChange?()
        guard loopTask == nil else { return }
        startLoop(refreshImmediately: false)
        Task { [weak self] in
            await self?.refresh(reason: "系统唤醒", forceRefresh: false)
        }
    }

    func refreshIfStaleForMenuOpen(maxAge: TimeInterval = 120) async {
        noteMenuOpened()
        if refreshPolicy.shouldRefreshOnMenuOpen(
            snapshot: snapshot,
            lastError: lastError,
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
                    self.lastError = self.diagnostic.lastFailure ?? "未能获取新额度，正在保留上次数据"
                    self.failures += 1
                    self.logger.warning("Quota refresh fell back to \(quota.sourceKind.rawValue, privacy: .public)")
                } else {
                    self.lastError = nil
                    self.failures = 0
                    self.logger.info("Quota refresh succeeded via \(quota.sourceKind.rawValue, privacy: .public)")
                }
                self.applyPipelineResult(await self.snapshotPipeline.process(previous: previous, current: quota))
                self.scheduleResetBoundaryRefresh(for: quota)
                self.startAnalyticsEnrichment(for: quota, generation: generation)
            } catch {
                if let realtime = await realtimeValue {
                    self.snapshot = self.snapshot.mergingAnalytics(realtime)
                }
                self.failures += 1
                let redacted = SensitiveDataRedactor().redact(error.localizedDescription)
                let quotaError = redacted
                self.lastError = self.snapshot.analytics?.todayTokens == nil
                    ? quotaError : "\(quotaError)；今日 Token 保留上次结果"
                self.logger.error("Usage refresh failed: \(redacted, privacy: .public)")
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
        resetBoundaryTask?.cancel()
        guard !snapshot.isCached, !snapshot.isEstimated else { return }
        let now = Date.now
        let resetDates = [snapshot.primaryWindow?.resetsAt, snapshot.secondaryWindow?.resetsAt]
            .compactMap { $0 }
            .filter { $0 > now }
        guard let nextReset = resetDates.min() else { return }
        let delay = max(5, nextReset.timeIntervalSince(now) + 5)
        resetBoundaryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.now = .now
            }
            await self?.refresh(reason: "额度重置边界", forceRefresh: false)
        }
    }

    private func applyPipelineResult(_ result: UsageSnapshotPipelineResult) {
        if result.historyChanged { historyRevision += 1 }
        if let warning = result.persistenceWarning { persistenceWarning = warning }
    }

    private func refreshAfterNetworkRestore() async {
        guard !automaticRefreshSuspended else { return }
        networkRestoreTask?.cancel()
        networkRestoreTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            guard !Task.isCancelled, let self, !self.automaticRefreshSuspended else { return }
            await self.refresh(reason: "网络恢复", forceRefresh: false)
            self.networkRestoreTask = nil
        }
        await networkRestoreTask?.value
    }

    func cancel() {
        loopTask?.cancel(); refreshTask?.cancel(); analyticsTask?.cancel(); resetBoundaryTask?.cancel(); networkRestoreTask?.cancel()
        loopTask = nil; refreshTask = nil; analyticsTask = nil; resetBoundaryTask = nil; networkRestoreTask = nil
    }

}
