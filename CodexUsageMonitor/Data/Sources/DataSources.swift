import Foundation

struct VerifiedOfficialDataSource: CodexUsageDataSource {
    let identifier = "verified-official"
    let displayName = "已验证官方数据源"
    let sourceKind = UsageSourceKind.verifiedOfficial
    func availability() async -> DataSourceAvailability { .unavailable("本机未发现官方机器可读额度接口") }
    func fetchUsage() async throws -> CodexUsageSnapshot { throw UsageMonitorError.noAvailableDataSource }
}

actor CachedSnapshotDataSource: CodexUsageDataSource {
    let identifier = "cached-snapshot"
    let displayName = "最近一次有效快照"
    let sourceKind = UsageSourceKind.cachedSnapshot
    private var snapshot: CodexUsageSnapshot?
    init(snapshot: CodexUsageSnapshot? = nil) { self.snapshot = snapshot }

    func update(_ value: CodexUsageSnapshot) { if !value.isEstimated && value.sourceKind != .unavailable { snapshot = value } }
    func availability() async -> DataSourceAvailability { snapshot == nil ? .unavailable("没有有效快照") : .available }
    func fetchUsage() async throws -> CodexUsageSnapshot {
        guard let snapshot else { throw UsageMonitorError.staleData }
        return try Self.cachedSnapshot(from: snapshot)
    }

    static func cachedSnapshot(from snapshot: CodexUsageSnapshot, now: Date = .now,
                               maximumAge: TimeInterval = 3_600) throws -> CodexUsageSnapshot {
        let age = now.timeIntervalSince(snapshot.fetchedAt)
        guard age <= maximumAge, snapshot.primaryWindow?.resetsAt.map({ $0 > now }) ?? true else { throw UsageMonitorError.staleData }
        return CodexUsageSnapshot(fetchedAt: snapshot.fetchedAt, sourceUpdatedAt: snapshot.sourceUpdatedAt,
            planName: snapshot.planName, primaryWindow: snapshot.primaryWindow, secondaryWindow: snapshot.secondaryWindow,
            credits: snapshot.credits, resetAllowance: snapshot.resetAllowance, analytics: snapshot.analytics,
            sourceKind: .cachedSnapshot, sourceDisplayName: "最近一次有效快照",
            isEstimated: false, isCached: true, confidence: age < 900 ? .medium : .low,
            fieldCompleteness: snapshot.fieldCompleteness, expiresAt: snapshot.expiresAt,
            diagnosticMessage: age >= 900 ? "数据已过期" : "当前显示缓存")
    }
}

actor LocalEstimateDataSource: CodexUsageDataSource {
    let identifier = "local-estimate"
    let displayName = "本地历史趋势"
    let sourceKind = UsageSourceKind.localEstimate
    private var history: [CodexUsageSnapshot] = []
    init(history: [CodexUsageSnapshot] = []) { self.history = history.filter { !$0.isEstimated } }
    func replaceHistory(_ values: [CodexUsageSnapshot]) { history = values.filter { !$0.isEstimated } }
    func record(_ value: CodexUsageSnapshot) {
        guard !value.isEstimated, !value.isCached, value.primaryWindow?.remainingPercentage != nil else { return }
        history.append(value)
        if history.count > 24 { history.removeFirst(history.count - 24) }
    }
    func availability() async -> DataSourceAvailability { history.count >= 2 ? .available : .unavailable("真实历史快照不足") }
    func fetchUsage() async throws -> CodexUsageSnapshot {
        let points = history.suffix(12).compactMap { snapshot -> (Date, Double, Date?)? in
            guard let value = snapshot.primaryWindow?.remainingPercentage else { return nil }
            return (snapshot.fetchedAt, value, snapshot.primaryWindow?.resetsAt)
        }
        guard points.count >= 2, let first = points.first, let last = points.last,
              last.0.timeIntervalSince(first.0) > 60 else { throw UsageMonitorError.insufficientHistory }
        let rate = (last.1 - first.1) / last.0.timeIntervalSince(first.0)
        let elapsed = Date.now.timeIntervalSince(last.0)
        let estimated = min(100, max(0, last.1 + rate * elapsed))
        let window = UsageLimitWindow(kind: .primary, remainingPercentage: estimated, usedPercentage: 100 - estimated,
                                      resetsAt: last.2, durationDescription: nil)
        return CodexUsageSnapshot(primaryWindow: window, sourceKind: .localEstimate, sourceDisplayName: displayName,
                                  isEstimated: true, confidence: .low, fieldCompleteness: 0.25,
                                  expiresAt: Date.now.addingTimeInterval(300), diagnosticMessage: "根据本地真实历史快照估算")
    }
}
