import Foundation
import Observation

@MainActor
@Observable
final class DashboardHistoryModel {
    private let history: any UsageHistoryReading

    private(set) var points: [UsageTrendPoint] = []
    private(set) var velocity: UsageVelocity?
    private(set) var paceSamples: [UsageHistorySample] = []
    private(set) var weeklySamples: [UsageHistorySample] = []
    private(set) var weeklyCreditBalanceSamples: [CreditBalanceSample] = []
    private(set) var errorMessage: String?

    init(history: any UsageHistoryReading) {
        self.history = history
    }

    func load(range: UsageHistoryRange, now: Date = .now) {
        do {
            let rangeStart = range.startDate(relativeTo: now)
            let weekStart = UsageHistoryRange.week.startDate(relativeTo: now)
            let samplesStart = min(rangeStart, weekStart)
            let availableSamples = try history.usageSamples(since: samplesStart)
            let samples = availableSamples.filter { $0.recordedAt >= rangeStart }
            weeklySamples = availableSamples.filter { $0.recordedAt >= weekStart }
            weeklyCreditBalanceSamples = try history.creditBalanceSamples(since: weekStart)
            points = UsageTrendBuilder.makePoints(from: samples, maxPoints: 240)
            // The chart range controls only the chart; pace always uses the latest 24 hours.
            paceSamples = UsageTrendBuilder.recentContinuousSamples(from: availableSamples, now: now)
            velocity = UsageTrendBuilder.makeVelocity(from: paceSamples, now: now)
            errorMessage = nil
        } catch {
            points = []
            velocity = nil
            paceSamples = []
            weeklySamples = []
            weeklyCreditBalanceSamples = []
            errorMessage = "历史数据暂时无法读取"
        }
    }
}
