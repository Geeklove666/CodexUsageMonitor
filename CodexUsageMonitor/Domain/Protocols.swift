import Foundation

protocol CodexUsageDataSource: Sendable {
    var identifier: String { get }
    var displayName: String { get }
    var sourceKind: UsageSourceKind { get }
    var parserVersion: String? { get }
    func availability() async -> DataSourceAvailability
    func fetchUsage() async throws -> CodexUsageSnapshot
}

extension CodexUsageDataSource { var parserVersion: String? { nil } }

protocol CodexAnalyticsDataSource: Sendable {
    var analyticsIdentifier: String { get }
    var analyticsParserVersion: String? { get }
    func analyticsAvailability() async -> DataSourceAvailability
    func fetchAnalytics() async throws -> CodexAnalyticsSnapshot
}

extension CodexAnalyticsDataSource { var analyticsParserVersion: String? { nil } }

protocol RefreshCacheInvalidatingDataSource: Sendable {
    func invalidateRefreshCaches() async
}

protocol CodexUsageDOMParser: Sendable {
    var parserVersion: String { get }
    func parse(html: String) throws -> ParsedCodexUsage
}

struct ParsedCodexUsage: Sendable, Equatable {
    let planName: String?
    let primaryWindow: UsageLimitWindow?
    let secondaryWindow: UsageLimitWindow?
    let credits: CreditsUsage?
    let resetAllowance: UsageResetAllowance?
    let sourceUpdatedAt: Date?
    let fieldCompleteness: Double

    init(planName: String?, primaryWindow: UsageLimitWindow?, secondaryWindow: UsageLimitWindow?,
         credits: CreditsUsage?, resetAllowance: UsageResetAllowance? = nil,
         sourceUpdatedAt: Date?, fieldCompleteness: Double) {
        self.planName = planName
        self.primaryWindow = primaryWindow
        self.secondaryWindow = secondaryWindow
        self.credits = credits
        self.resetAllowance = resetAllowance
        self.sourceUpdatedAt = sourceUpdatedAt
        self.fieldCompleteness = fieldCompleteness
    }
}
