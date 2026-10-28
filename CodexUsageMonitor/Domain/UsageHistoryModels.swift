import Foundation

struct UsageHistorySample: Identifiable, Sendable, Equatable {
    let id: UUID
    let recordedAt: Date
    let remainingPercentage: Double
    let resetsAt: Date?
    let resetAllowanceAvailable: Int?
    let isCached: Bool
    let accountIdentity: CodexAccountIdentity?
    let sourceKind: UsageSourceKind?
    let planName: String?

    init(
        id: UUID = UUID(),
        recordedAt: Date,
        remainingPercentage: Double,
        resetsAt: Date?,
        resetAllowanceAvailable: Int? = nil,
        isCached: Bool,
        accountIdentity: CodexAccountIdentity? = nil,
        sourceKind: UsageSourceKind? = nil,
        planName: String? = nil
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.remainingPercentage = min(100, max(0, remainingPercentage))
        self.resetsAt = resetsAt
        self.resetAllowanceAvailable = resetAllowanceAvailable
        self.isCached = isCached
        self.accountIdentity = accountIdentity
        self.sourceKind = sourceKind
        self.planName = planName
    }
}

struct CreditBalanceSample: Identifiable, Sendable, Equatable {
    let id: UUID
    let recordedAt: Date
    let remaining: Decimal
    let isCached: Bool
    let isEstimated: Bool
    let accountKey: String?
    let sourceKind: UsageSourceKind

    init(
        id: UUID = UUID(),
        recordedAt: Date,
        remaining: Decimal,
        isCached: Bool,
        isEstimated: Bool,
        accountKey: String? = nil,
        sourceKind: UsageSourceKind = .unavailable
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.remaining = remaining
        self.isCached = isCached
        self.isEstimated = isEstimated
        self.accountKey = accountKey
        self.sourceKind = sourceKind
    }
}

struct UsageTrendPoint: Identifiable, Sendable, Equatable {
    let id: UUID
    let date: Date
    let remainingPercentage: Double
    let isReset: Bool
    let isCached: Bool
}

struct UsageVelocity: Sendable, Equatable {
    let consumedPercentage: Double
    let observationHours: Double

    var consumedText: String {
        "观察期消耗 \(CountFormatter.decimal(consumedPercentage))%"
    }

    var detailText: String {
        guard observationHours > 0 else { return "样本不足" }
        let dailyRate = consumedPercentage / observationHours * 24
        return "近 \(DurationFormatter.compactChinese(observationHours * 3600))，当前节奏约 \(CountFormatter.decimal(dailyRate)) 个百分点 / 天"
    }
}

enum UsageHistoryRange: String, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case month

    var id: Self { self }

    var label: String {
        switch self {
        case .day: "24 小时"
        case .week: "7 天"
        case .month: "30 天"
        }
    }

    func startDate(relativeTo now: Date) -> Date {
        let interval: TimeInterval = switch self {
        case .day: 24 * 60 * 60
        case .week: 7 * 24 * 60 * 60
        case .month: 30 * 24 * 60 * 60
        }
        return now.addingTimeInterval(-interval)
    }
}

@MainActor
protocol UsageHistoryReading: AnyObject {
    func usageSamples(since date: Date) throws -> [UsageHistorySample]
    func creditBalanceSamples(since date: Date) throws -> [CreditBalanceSample]
}
