import Foundation

@MainActor
final class DependencyContainer {
    let webSession = WebViewSession()
    let history: UsageHistoryStore
    let repository: DefaultCodexUsageRepository
    let monitoring: UsageMonitoringService
    let menuBarController: MenuBarController
    let lifecycleCoordinator: AppLifecycleCoordinator

    init() {
        let persistenceLogger = AppLogger(.persistence)
        var persistenceWarnings: [String] = []
        do {
            history = try UsageHistoryStore()
        } catch {
            let persistentFailure = UsageFailure(error: error)
            persistenceLogger.error("Persistent history store failed: \(persistentFailure.diagnosticMessage)")
            do {
                history = try UsageHistoryStore(inMemory: true)
                persistenceWarnings.append("历史数据库无法打开，本次改用临时内存存储：\(persistentFailure.userMessage)")
            } catch {
                let memoryFailure = UsageFailure(error: error)
                history = .disabled()
                persistenceWarnings.append("历史功能暂时不可用，额度监控仍可继续：\(memoryFailure.userMessage)")
                persistenceLogger.error("In-memory history store failed: \(memoryFailure.diagnosticMessage)")
            }
        }
        let restored: [CodexUsageSnapshot]
        if history.isAvailable {
            let configuredRetention = UserDefaults.standard.object(forKey: AppPreferences.Key.retentionDays) == nil
                ? AppConfiguration.Persistence.defaultRetentionDays
                : UserDefaults.standard.integer(forKey: AppPreferences.Key.retentionDays)
            let retentionRange = AppConfiguration.Persistence.minimumRetentionDays...AppConfiguration.Persistence.maximumRetentionDays
            do { try history.cleanup(retentionDays: configuredRetention.clamped(to: retentionRange)) }
            catch { persistenceWarnings.append("历史清理失败：\(SensitiveDataRedactor().redact(error.localizedDescription))") }
            do { restored = try history.recentSnapshots(limit: AppConfiguration.Persistence.restoredSnapshotLimit) }
            catch {
                restored = []
                persistenceWarnings.append("历史恢复失败：\(SensitiveDataRedactor().redact(error.localizedDescription))")
            }
        } else {
            restored = []
        }
        let cache = CachedSnapshotDataSource(snapshot: restored.last)
        let estimate = LocalEstimateDataSource(history: restored)
        let webSource = OfficialWebViewDataSource(
            session: webSession, apiParser: OfficialUsageAPIParser(), parser: OfficialPageDOMParser()
        )
        let localCodexSource = LocalCodexSessionDataSource()
        let realtimeTokenReader = LocalRealtimeTokenUsageReader()
        repository = DefaultCodexUsageRepository(
            official: VerifiedOfficialDataSource(),
            localCodex: localCodexSource,
            web: webSource,
            analyticsSources: [localCodexSource, webSource],
            cache: cache, estimate: estimate)
        let initialSnapshot = restored.last.flatMap {
            try? CachedSnapshotDataSource.cachedSnapshot(
                from: $0,
                maximumAge: AppConfiguration.Persistence.restoredSnapshotMaximumAge
            )
        } ?? .unavailable
        let snapshotPipeline = UsageSnapshotPipeline(history: history)
        monitoring = UsageMonitoringService(
            repository: repository,
            realtimeTokenReader: realtimeTokenReader,
            providerRegistry: AIProviderRegistry([
                CodexUsageProvider(repository: repository),
                LocalClaudeUsageProvider()
            ]),
            snapshotPipeline: snapshotPipeline,
            initialSnapshot: initialSnapshot
        )
        menuBarController = MenuBarController(monitor: monitoring, history: history, webSession: webSession)
        lifecycleCoordinator = AppLifecycleCoordinator(monitor: monitoring)
        monitoring.persistenceWarning = persistenceWarnings.isEmpty ? nil : persistenceWarnings.joined(separator: "\n")
        webSession.onPageReady = { [weak monitoring] in
            Task { @MainActor in
                await monitoring?.refresh(reason: "网页登录就绪", forceRefresh: true)
            }
        }
        monitoring.start()
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int { Swift.min(range.upperBound, Swift.max(range.lowerBound, self)) }
}
