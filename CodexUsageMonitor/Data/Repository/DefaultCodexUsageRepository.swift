import Foundation

actor DefaultCodexUsageRepository {
    private struct AnalyticsFetchResult: Sendable {
        let index: Int
        let identifier: String
        let value: CodexAnalyticsSnapshot?
        let error: String?
    }
    private let official: any CodexUsageDataSource
    private let localCodex: (any CodexUsageDataSource)?
    private let web: any CodexUsageDataSource
    private let analyticsSources: [any CodexAnalyticsDataSource]
    private let cache: CachedSnapshotDataSource
    private let estimate: LocalEstimateDataSource
    private let requestTimeout: Duration
    private let analyticsTimeout: Duration
    private(set) var diagnostic = DataSourceDiagnostic()

    init(official: any CodexUsageDataSource, localCodex: (any CodexUsageDataSource)? = nil,
         web: any CodexUsageDataSource,
         analytics: (any CodexAnalyticsDataSource)? = nil,
         analyticsSources: [any CodexAnalyticsDataSource] = [],
         cache: CachedSnapshotDataSource, estimate: LocalEstimateDataSource,
         requestTimeout: Duration = .seconds(20),
         analyticsTimeout: Duration = .seconds(8)) {
        self.official = official; self.localCodex = localCodex; self.web = web
        self.analyticsSources = analyticsSources.isEmpty ? analytics.map { [$0] } ?? [] : analyticsSources
        self.cache = cache; self.estimate = estimate
        self.requestTimeout = requestTimeout; self.analyticsTimeout = analyticsTimeout
    }

    func fetch() async throws -> CodexUsageSnapshot {
        let quotaSnapshot = try await fetchQuota()
        let value = await fetchAnalytics(for: quotaSnapshot)
        if !value.isCached && !value.isEstimated {
            await cache.update(value)
        }
        return value
    }

    func fetchQuota() async throws -> CodexUsageSnapshot {
        var sources: [any CodexUsageDataSource] = [official]
        if let localCodex { sources.append(localCodex) }
        sources.append(contentsOf: [web, cache, estimate])
        var lastError: Error = UsageMonitorError.noAvailableDataSource
        for source in sources {
            try Task.checkCancellation()
            guard case .available = await source.availability() else { continue }
            let start = ContinuousClock.now
            do {
                let value = try await withTimeout(requestTimeout) { try await source.fetchUsage() }
                diagnostic.activeIdentifier = source.identifier
                if !value.isCached && !value.isEstimated {
                    diagnostic.lastSuccess = .now
                    diagnostic.lastFailure = nil
                }
                diagnostic.requestDuration = start.duration(to: .now).seconds
                diagnostic.fieldCompleteness = value.fieldCompleteness
                diagnostic.parserVersion = source.parserVersion
                if !value.isCached && !value.isEstimated {
                    await cache.update(value)
                    await estimate.record(value)
                }
                return value
            } catch is CancellationError { throw UsageMonitorError.cancelled }
            catch { lastError = error; diagnostic.lastFailure = SensitiveDataRedactor().redact(error.localizedDescription) }
        }
        throw lastError
    }

    func currentDiagnostic() -> DataSourceDiagnostic { diagnostic }

    func fetchAnalytics(for snapshot: CodexUsageSnapshot) async -> CodexUsageSnapshot {
        var combined = snapshot.analytics
        var successfulIdentifiers: [String] = []
        var available: [(Int, any CodexAnalyticsDataSource)] = []
        var availability: [String: String] = [:]
        for (index, source) in analyticsSources.enumerated() {
            switch await source.analyticsAvailability() {
            case .available:
                available.append((index, source))
                availability[source.analyticsIdentifier] = "可用"
            case .authenticationRequired:
                availability[source.analyticsIdentifier] = "需要登录"
            case .unavailable(let reason):
                availability[source.analyticsIdentifier] = SensitiveDataRedactor().redact(reason)
            }
        }
        let results = await withTaskGroup(of: AnalyticsFetchResult.self, returning: [AnalyticsFetchResult].self) { group in
            for (index, source) in available {
                group.addTask { [analyticsTimeout] in
                    do {
                        let value = try await self.withTimeout(analyticsTimeout) { try await source.fetchAnalytics() }
                        return AnalyticsFetchResult(index: index, identifier: source.analyticsIdentifier, value: value, error: nil)
                    } catch {
                        return AnalyticsFetchResult(index: index, identifier: source.analyticsIdentifier, value: nil,
                            error: SensitiveDataRedactor().redact(error.localizedDescription))
                    }
                }
            }
            var values: [AnalyticsFetchResult] = []
            for await result in group { values.append(result) }
            return values.sorted { $0.index < $1.index }
        }
        var failures: [String: String] = [:]
        for result in results {
            if let value = result.value {
                combined = combined?.merging(value) ?? value
                successfulIdentifiers.append(result.identifier)
            } else if let error = result.error {
                failures[result.identifier] = error
            }
        }
        diagnostic.analyticsIdentifier = successfulIdentifiers.isEmpty ? nil : successfulIdentifiers.joined(separator: ",")
        let analyticsParserVersions = analyticsSources.compactMap(\.analyticsParserVersion)
        if !analyticsParserVersions.isEmpty {
            diagnostic.parserVersion = ([diagnostic.parserVersion].compactMap { $0 } + analyticsParserVersions).joined(separator: " + ")
        }
        diagnostic.analyticsAvailability = availability
        diagnostic.analyticsFailures = failures
        diagnostic.lastAnalyticsFailure = failures.keys.sorted().last.flatMap { failures[$0] }
        guard combined != snapshot.analytics else { return snapshot }
        return CodexUsageSnapshot(
            id: snapshot.id, fetchedAt: snapshot.fetchedAt, sourceUpdatedAt: snapshot.sourceUpdatedAt,
            planName: snapshot.planName, primaryWindow: snapshot.primaryWindow,
            secondaryWindow: snapshot.secondaryWindow, credits: snapshot.credits,
            resetAllowance: snapshot.resetAllowance, analytics: combined,
            sourceKind: snapshot.sourceKind, sourceDisplayName: snapshot.sourceDisplayName,
            isEstimated: snapshot.isEstimated, isCached: snapshot.isCached,
            confidence: snapshot.confidence, fieldCompleteness: snapshot.fieldCompleteness,
            expiresAt: snapshot.expiresAt, diagnosticMessage: snapshot.diagnosticMessage
        )
    }

    private func withTimeout<Value: Sendable>(
        _ timeout: Duration,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask { try await operation() }
            group.addTask { try await Task.sleep(for: timeout); throw UsageMonitorError.requestTimedOut }
            guard let first = try await group.next() else { throw UsageMonitorError.noAvailableDataSource }
            group.cancelAll()
            return first
        }
    }
}

private extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
