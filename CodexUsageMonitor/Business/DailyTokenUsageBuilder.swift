import Foundation

struct DailyTokenUsage: Identifiable, Sendable, Equatable {
    let date: Date
    let tokens: Int64?
    let resetCount: Int?

    var id: Date { date }
}

struct WeeklyTokenUsageSummary: Sendable, Equatable {
    let days: [DailyTokenUsage]
    let sourceName: String?

    var knownDays: [DailyTokenUsage] { days.filter { $0.tokens != nil } }
    var totalTokens: Int64 { knownDays.reduce(0) { $0 + ($1.tokens ?? 0) } }
    var averageTokens: Int64? {
        guard !knownDays.isEmpty else { return nil }
        return totalTokens / Int64(knownDays.count)
    }
    var peakTokens: Int64? { knownDays.compactMap(\.tokens).max() }
}

enum DailyTokenUsageBuilder {
    static func make(
        analytics: CodexAnalyticsSnapshot?,
        historySamples: [UsageHistorySample] = [],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> WeeklyTokenUsageSummary {
        let today = calendar.startOfDay(for: now)
        let resetCounts = dailyResetCounts(from: historySamples, calendar: calendar)
        let days = (0..<7).reversed().compactMap { offset -> DailyTokenUsage? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DailyTokenUsage(
                date: date,
                tokens: analytics?.tokens(on: date, calendar: calendar),
                resetCount: resetCounts[date]
            )
        }
        let source = analytics?.sectionSources[.tokenUsage] ?? analytics?.compactSourceDisplayName
        return WeeklyTokenUsageSummary(days: days, sourceName: source)
    }

    private static func dailyResetCounts(
        from samples: [UsageHistorySample],
        calendar: Calendar
    ) -> [Date: Int] {
        let samples = samples
            .filter { !$0.isCached }
            .sorted { $0.recordedAt < $1.recordedAt }
        var result: [Date: Int] = [:]
        for sample in samples {
            result[calendar.startOfDay(for: sample.recordedAt)] = 0
        }

        for (previous, current) in zip(samples, samples.dropFirst()) {
            let manualUses = max(
                0,
                (previous.resetAllowanceAvailable ?? current.resetAllowanceAvailable ?? 0)
                    - (current.resetAllowanceAvailable ?? previous.resetAllowanceAvailable ?? 0)
            )
            let scheduledReset = previous.resetsAt != nil
                && current.resetsAt != nil
                && previous.resetsAt != current.resetsAt
                && current.remainingPercentage - previous.remainingPercentage >= 5
            let count = max(manualUses, scheduledReset ? 1 : 0)
            guard count > 0 else { continue }
            result[calendar.startOfDay(for: current.recordedAt), default: 0] += count
        }
        return result
    }
}
