import Foundation

enum DailyUsageMeasurement: Sendable, Equatable {
    case tokens(Int64)
    case estimatedCredits(Double)

    var isEstimated: Bool {
        if case .estimatedCredits = self { return true }
        return false
    }
}

struct DailyTokenUsage: Identifiable, Sendable, Equatable {
    let date: Date
    let measurement: DailyUsageMeasurement?
    let resetCount: Int?

    var id: Date { date }
    var tokens: Int64? {
        guard case let .tokens(value) = measurement else { return nil }
        return value
    }
    var estimatedCredits: Double? {
        guard case let .estimatedCredits(value) = measurement else { return nil }
        return value
    }
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
    var estimatedCreditDays: [DailyTokenUsage] { days.filter { $0.estimatedCredits != nil } }
    var totalEstimatedCredits: Double {
        estimatedCreditDays.reduce(0) { $0 + ($1.estimatedCredits ?? 0) }
    }
    var peakEstimatedCredits: Double? { estimatedCreditDays.compactMap(\.estimatedCredits).max() }
}

enum DailyTokenUsageBuilder {
    static func make(
        analytics: CodexAnalyticsSnapshot?,
        historySamples: [UsageHistorySample] = [],
        creditBalanceSamples: [CreditBalanceSample] = [],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> WeeklyTokenUsageSummary {
        let today = calendar.startOfDay(for: now)
        let resetCounts = dailyResetCounts(from: historySamples, calendar: calendar)
        let balanceEstimates = DailyCreditUsageEstimator.make(
            samples: creditBalanceSamples,
            calendar: calendar
        )
        let days = (0..<7).reversed().compactMap { offset -> DailyTokenUsage? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let tokens = analytics?.effectiveTokens(on: date, calendar: calendar)
            let measurement: DailyUsageMeasurement? = if let tokens {
                .tokens(tokens)
            } else if let credits = analytics?.calculatedCredits(on: date, calendar: calendar) {
                .estimatedCredits(credits)
            } else if let credits = balanceEstimates[date] {
                .estimatedCredits(credits)
            } else {
                nil
            }
            return DailyTokenUsage(
                date: date,
                measurement: measurement,
                resetCount: resetCounts[date]
            )
        }
        let source = analytics?.sectionSources[.tokenUsage]
            ?? analytics?.compactSourceDisplayName
            ?? (balanceEstimates.isEmpty ? nil : "Credits 余额变化（估算）")
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

enum DailyCreditUsageEstimator {
    static func make(
        samples: [CreditBalanceSample],
        calendar: Calendar = .current
    ) -> [Date: Double] {
        let samples = samples
            .filter { !$0.isCached && !$0.isEstimated }
            .sorted { $0.recordedAt < $1.recordedAt }
        guard samples.count > 1 else { return [:] }

        var result: [Date: Double] = [:]
        var previous = samples[0]
        for current in samples.dropFirst() {
            guard comparable(previous, current) else {
                previous = current
                continue
            }
            let day = calendar.startOfDay(for: current.recordedAt)
            result[day, default: 0] += max(
                0,
                NSDecimalNumber(decimal: previous.remaining - current.remaining).doubleValue
            )
            previous = current
        }
        return result
    }

    private static func comparable(_ previous: CreditBalanceSample, _ current: CreditBalanceSample) -> Bool {
        guard previous.sourceKind == current.sourceKind else { return false }
        switch (previous.accountKey, current.accountKey) {
        case let (lhs?, rhs?): return lhs == rhs
        case (nil, nil): return true
        default: return false
        }
    }
}
