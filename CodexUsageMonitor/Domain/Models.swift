import Foundation

enum UsageSourceKind: String, Codable, Sendable, CaseIterable {
    case verifiedOfficial, localCodexSession, officialWebPage, cachedSnapshot, localEstimate, unavailable

    var label: String {
        switch self {
        case .verifiedOfficial: "官方数据"
        case .localCodexSession: "本机 Codex 登录"
        case .officialWebPage: "官方页面读取"
        case .cachedSnapshot: "缓存数据"
        case .localEstimate: "本地估算"
        case .unavailable: "当前无法读取"
        }
    }
}

enum UsageConfidence: String, Codable, Sendable, Equatable { case verified, high, medium, low, unavailable }
enum UsageWindowKind: String, Codable, Sendable { case primary, secondary, rolling, weekly, unknown }

struct UsageLimitWindow: Sendable, Codable, Equatable {
    let kind: UsageWindowKind
    let remainingPercentage: Double?
    let usedPercentage: Double?
    let resetsAt: Date?
    let durationDescription: String?

    init(kind: UsageWindowKind, remainingPercentage: Double?, usedPercentage: Double?, resetsAt: Date?, durationDescription: String?) {
        self.kind = kind
        self.remainingPercentage = remainingPercentage.map { min(100, max(0, $0)) }
        self.usedPercentage = usedPercentage.map { min(100, max(0, $0)) }
        self.resetsAt = resetsAt
        self.durationDescription = durationDescription
    }
}

struct CreditsUsage: Sendable, Codable, Equatable {
    let remaining: Decimal?
    let used: Decimal?
    let currencyOrUnit: String?
    let expiresAt: Date?
}

struct UsageResetCredit: Sendable, Codable, Equatable {
    let resetType: String?
    let status: String?
    let grantedAt: Date?
    let expiresAt: Date?
    let title: String?
}

struct UsageResetAllowance: Sendable, Codable, Equatable {
    let availableCount: Int
    let credits: [UsageResetCredit]

    init(availableCount: Int, credits: [UsageResetCredit] = []) {
        self.availableCount = max(0, availableCount)
        self.credits = credits
    }

    var nextExpiration: Date? {
        credits.compactMap(\.expiresAt).filter { $0 > .now }.min()
    }
}

struct CodexUsageSnapshot: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    let fetchedAt: Date
    let sourceUpdatedAt: Date?
    let planName: String?
    let primaryWindow: UsageLimitWindow?
    let secondaryWindow: UsageLimitWindow?
    let credits: CreditsUsage?
    let resetAllowance: UsageResetAllowance?
    let analytics: CodexAnalyticsSnapshot?
    let sourceKind: UsageSourceKind
    let sourceDisplayName: String
    let isEstimated: Bool
    let isCached: Bool
    let confidence: UsageConfidence
    let fieldCompleteness: Double
    let expiresAt: Date?
    let diagnosticMessage: String?

    init(id: UUID = UUID(), fetchedAt: Date = .now, sourceUpdatedAt: Date? = nil, planName: String? = nil,
         primaryWindow: UsageLimitWindow? = nil, secondaryWindow: UsageLimitWindow? = nil, credits: CreditsUsage? = nil,
         resetAllowance: UsageResetAllowance? = nil, analytics: CodexAnalyticsSnapshot? = nil,
         sourceKind: UsageSourceKind, sourceDisplayName: String, isEstimated: Bool = false, isCached: Bool = false,
         confidence: UsageConfidence, fieldCompleteness: Double, expiresAt: Date? = nil, diagnosticMessage: String? = nil) {
        self.id = id; self.fetchedAt = fetchedAt; self.sourceUpdatedAt = sourceUpdatedAt; self.planName = planName
        self.primaryWindow = primaryWindow; self.secondaryWindow = secondaryWindow; self.credits = credits
        self.resetAllowance = resetAllowance; self.analytics = analytics
        self.sourceKind = sourceKind; self.sourceDisplayName = sourceDisplayName; self.isEstimated = isEstimated
        self.isCached = isCached; self.confidence = confidence; self.fieldCompleteness = min(1, max(0, fieldCompleteness))
        self.expiresAt = expiresAt; self.diagnosticMessage = diagnosticMessage
    }

    static let unavailable = CodexUsageSnapshot(sourceKind: .unavailable, sourceDisplayName: "无可用数据源", confidence: .unavailable, fieldCompleteness: 0, diagnosticMessage: "需要登录 Codex Usage 页面")

    func mergingAnalytics(_ value: CodexAnalyticsSnapshot) -> CodexUsageSnapshot {
        CodexUsageSnapshot(
            id: id, fetchedAt: fetchedAt, sourceUpdatedAt: sourceUpdatedAt, planName: planName,
            primaryWindow: primaryWindow, secondaryWindow: secondaryWindow, credits: credits,
            resetAllowance: resetAllowance, analytics: analytics?.merging(value) ?? value,
            sourceKind: sourceKind, sourceDisplayName: sourceDisplayName,
            isEstimated: isEstimated, isCached: isCached, confidence: confidence,
            fieldCompleteness: fieldCompleteness, expiresAt: expiresAt,
            diagnosticMessage: diagnosticMessage
        )
    }
}

enum DataSourceAvailability: Sendable, Equatable { case available, authenticationRequired, unavailable(String) }

enum MonitoringStatus: String, Sendable, Equatable {
    case refreshing, live, cached, estimated, needsLogin, degraded, unavailable

    init(snapshot: CodexUsageSnapshot, lastError: String?, isRefreshing: Bool) {
        if isRefreshing {
            self = .refreshing
        } else if snapshot.isCached {
            self = lastError == nil ? .cached : .degraded
        } else if snapshot.isEstimated {
            self = lastError == nil ? .estimated : .degraded
        } else if snapshot.sourceKind != .unavailable {
            self = lastError == nil ? .live : .degraded
        } else if let lastError, lastError.contains("登录") {
            self = .needsLogin
        } else if lastError != nil {
            self = .unavailable
        } else {
            self = .needsLogin
        }
    }

    var label: String {
        switch self {
        case .refreshing: "正在读取数据"
        case .live: "数据正常"
        case .cached: "正在使用缓存数据"
        case .estimated: "正在使用本地估算"
        case .needsLogin: "需要登录"
        case .degraded: "刷新失败，保留上次数据"
        case .unavailable: "当前无法读取"
        }
    }
}

enum UsageMonitorError: LocalizedError, Sendable {
    case noAvailableDataSource, authenticationRequired, authenticationExpired, networkUnavailable, requestTimedOut
    case unsupportedResponse, parsingFailed, pageStructureChanged, insufficientHistory, staleData, cancelled

    var errorDescription: String? {
        switch self {
        case .noAvailableDataSource: "当前没有可用的数据源"
        case .authenticationRequired, .authenticationExpired: "需要重新登录 Codex"
        case .networkUnavailable: "当前网络不可用"
        case .requestTimedOut: "读取额度超时"
        case .unsupportedResponse, .parsingFailed, .pageStructureChanged: "官方页面结构可能已经更新"
        case .insufficientHistory: "历史数据不足，暂时无法估算"
        case .staleData: "数据已过期"
        case .cancelled: "操作已取消"
        }
    }
}

struct DataSourceDiagnostic: Sendable {
    var activeIdentifier = "none"
    var analyticsIdentifier: String?
    var lastSuccess: Date?
    var lastFailure: String?
    var lastAnalyticsFailure: String?
    var analyticsAvailability: [String: String] = [:]
    var analyticsFailures: [String: String] = [:]
    var requestDuration: TimeInterval?
    var parserVersion: String?
    var fieldCompleteness: Double = 0
    var attempts: [DataSourceAttemptDiagnostic] = []
    var lastRefreshReason: String?
}

struct DataSourceAttemptDiagnostic: Identifiable, Sendable, Equatable {
    let id = UUID()
    let sourceIdentifier: String
    let sourceLabel: String
    let kind: UsageSourceKind?
    let availability: String
    let succeeded: Bool
    let duration: TimeInterval?
    let error: String?
    let timestamp: Date
}
