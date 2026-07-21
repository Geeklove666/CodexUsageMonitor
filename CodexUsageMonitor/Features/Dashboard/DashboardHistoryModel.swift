import Foundation
import Observation

@MainActor
@Observable
final class DashboardHistoryModel {
    private let history: any UsageHistoryReading

    private(set) var points: [UsageTrendPoint] = []
    private(set) var velocity: UsageVelocity?
    private(set) var weeklySamples: [UsageHistorySample] = []
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
            points = UsageTrendBuilder.makePoints(from: samples, maxPoints: 240)
            velocity = UsageTrendBuilder.makeVelocity(from: samples, now: now)
            errorMessage = nil
        } catch {
            points = []
            velocity = nil
            weeklySamples = []
            errorMessage = "历史数据暂时无法读取"
        }
    }
}
