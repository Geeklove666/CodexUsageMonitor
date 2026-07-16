import Foundation

@MainActor
final class DependencyContainer {
    let webSession = WebViewSession()
    let history: UsageHistoryStore
    let repository: DefaultCodexUsageRepository
    let monitoring: UsageMonitoringService

    init() {
        var persistenceWarnings: [String] = []
        do {
            history = try UsageHistoryStore()
        } catch {
            history = try! UsageHistoryStore(inMemory: true)
            persistenceWarnings.append("历史数据库无法打开，本次改用临时内存存储：\(SensitiveDataRedactor().redact(error.localizedDescription))")
        }
        let configuredRetention = UserDefaults.standard.object(forKey: "retentionDays") == nil ? 30 : UserDefaults.standard.integer(forKey: "retentionDays")
        do { try history.cleanup(retentionDays: configuredRetention.clamped(to: 7...90)) }
        catch { persistenceWarnings.append("历史清理失败：\(SensitiveDataRedactor().redact(error.localizedDescription))") }
        let restored: [CodexUsageSnapshot]
        do { restored = try history.recentSnapshots(limit: 24) }
        catch {
            restored = []
            persistenceWarnings.append("历史恢复失败：\(SensitiveDataRedactor().redact(error.localizedDescription))")
        }
        let cache = CachedSnapshotDataSource(snapshot: restored.last)
        let estimate = LocalEstimateDataSource(history: restored)
        let webSource = OfficialWebViewDataSource(
            session: webSession, apiParser: OfficialUsageAPIParser(), parser: OfficialPageDOMParser()
        )
        let realtimeTokenReader = LocalRealtimeTokenUsageReader()
        let localSource = LocalCodexSessionDataSource()
        repository = DefaultCodexUsageRepository(
            official: VerifiedOfficialDataSource(),
            localCodex: localSource,
            web: webSource,
            analyticsSources: [localSource, webSource],
            cache: cache, estimate: estimate)
        let initialSnapshot = restored.last.flatMap {
            try? CachedSnapshotDataSource.cachedSnapshot(from: $0, maximumAge: 86_400)
        } ?? .unavailable
        monitoring = UsageMonitoringService(
            repository: repository, history: history,
            realtimeTokenReader: realtimeTokenReader, initialSnapshot: initialSnapshot
        )
        monitoring.persistenceWarning = persistenceWarnings.isEmpty ? nil : persistenceWarnings.joined(separator: "\n")
        webSession.onPageReady = { [weak monitoring] in
            Task { @MainActor in
                // Let any launch-time refresh finish before consuming the restored session.
                try? await Task.sleep(for: .milliseconds(350))
                await monitoring?.refresh()
            }
        }
        let defaults = UserDefaults.standard
        let localAuthorized = defaults.bool(forKey: LocalCodexSessionAuthorization.preferenceKey)
        let webEnrichment = defaults.bool(forKey: "officialWebAnalyticsEnrichment")
        // Avoid hidden page/network activity when the user selected local-only monitoring.
        if !localAuthorized || webEnrichment { webSession.openUsagePage() }
        monitoring.start()
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int { Swift.min(range.upperBound, Swift.max(range.lowerBound, self)) }
}
