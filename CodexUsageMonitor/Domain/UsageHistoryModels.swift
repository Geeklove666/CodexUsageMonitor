import Foundation

struct UsageHistorySample: Identifiable, Sendable, Equatable {
    let id: UUID
    let recordedAt: Date
    let remainingPercentage: Double
    let resetsAt: Date?
    let resetAllowanceAvailable: Int?
    let isCached: Bool

    init(
        id: UUID = UUID(),
        recordedAt: Date,
        remainingPercentage: Double,
        resetsAt: Date?,
        resetAllowanceAvailable: Int? = nil,
        isCached: Bool
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.remainingPercentage = min(100, max(0, remainingPercentage))
        self.resetsAt = resetsAt
        self.resetAllowanceAvailable = resetAllowanceAvailable
        self.isCached = isCached
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
        "近 24 小时消耗 \(Int(consumedPercentage.rounded()))%"
    }

    var detailText: String {
        guard observationHours > 0 else { return "样本不足" }
        let dailyRate = consumedPercentage / observationHours * 24
        return "当前节奏约 \(Int(dailyRate.rounded()))% / 天"
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
}
