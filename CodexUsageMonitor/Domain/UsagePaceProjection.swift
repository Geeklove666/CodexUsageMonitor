import Foundation

enum UsagePaceAssessment: Sendable, Equatable {
    case projected(UsagePaceProjection)
    case unavailable(String)

    var projection: UsagePaceProjection? {
        guard case let .projected(value) = self else { return nil }
        return value
    }
}

struct UsagePaceProjection: Sendable, Equatable {
    let samples: [UsageHistorySample]
    let observedAt: Date
    let resetsAt: Date
    let remainingPercentage: Double
    let percentagePointsPerHour: Double
    let observationHours: Double
    let projectedExhaustionAt: Date
    let projectedRemainingAtReset: Double
    let sustainablePercentagePointsPerHour: Double

    var runsOutBeforeReset: Bool { projectedExhaustionAt < resetsAt }
    var projectionEnd: Date { min(projectedExhaustionAt, resetsAt) }
    var headline: String { runsOutBeforeReset ? "按当前速度，可能在重置前耗尽" : "按当前速度，预计可用至重置" }
}
