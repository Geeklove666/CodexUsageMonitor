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
            let samples = try history.usageSamples(since: range.startDate(relativeTo: now))
            weeklySamples = try history.usageSamples(since: UsageHistoryRange.week.startDate(relativeTo: now))
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
