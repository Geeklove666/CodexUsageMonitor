import Foundation

enum CodexAnalyticsSection: String, Sendable, Codable, Hashable, CaseIterable {
    case tokenUsage
    case activity
    case productUsage
    case skills
    case plugins
    case creditEvents
}

struct CodexAnalyticsSnapshot: Sendable, Codable, Equatable {
    let fetchedAt: Date
    let sourceDisplayName: String
    let rangeStart: Date?
    let rangeEnd: Date?
    let groupBy: String
    let dailyActivity: [CodexDailyActivity]
    let dailyProductUsage: [CodexDailyProductUsage]
    let topSkills: [CodexNamedUsage]
    let topPlugins: [CodexNamedUsage]
    let creditEventCount: Int?
    let availableSections: Set<CodexAnalyticsSection>
    let lifetimeTokens: Int64?
    let peakDailyTokens: Int64?
    let currentStreakDays: Int?
    let longestStreakDays: Int?
    let longestRunningTurnSeconds: Int?
    var sectionSources: [CodexAnalyticsSection: String] = [:]
    var warnings: [String] = []
    /// `nil` preserves legacy cached snapshots. A non-nil set distinguishes a
    /// real zero-token bucket from an activity-only day introduced by merging.
    var tokenRecordedDates: Set<Date>? = nil

    func has(_ section: CodexAnalyticsSection) -> Bool { availableSections.contains(section) }
    var hasAccountUsageSummary: Bool {
        lifetimeTokens != nil || peakDailyTokens != nil || currentStreakDays != nil
            || longestStreakDays != nil || longestRunningTurnSeconds != nil
    }

    var totalThreads: Int { dailyActivity.reduce(0) { $0 + $1.threads } }
    var totalTurns: Int { dailyActivity.reduce(0) { $0 + $1.turns } }
    var activeDays: Int { dailyActivity.filter { $0.turns > 0 || $0.threads > 0 || $0.totalTokens > 0 }.count }
    var totalCredits: Double { dailyActivity.reduce(0) { $0 + $1.credits } }
    var uncachedInputTokens: Int64 { dailyActivity.reduce(0) { $0 + $1.uncachedInputTokens } }
    var cachedInputTokens: Int64 { dailyActivity.reduce(0) { $0 + $1.cachedInputTokens } }
    var outputTokens: Int64 { dailyActivity.reduce(0) { $0 + $1.outputTokens } }
    var totalTokens: Int64 { dailyActivity.reduce(0) { $0 + $1.totalTokens } }
    var totalSkillInvocations: Int { topSkills.reduce(0) { $0 + $1.invocations } }
    var totalPluginInvocations: Int { topPlugins.reduce(0) { $0 + $1.invocations } }

    func tokens(on date: Date, calendar: Calendar = .current) -> Int64? {
        guard has(.tokenUsage) else { return nil }
        let matching = dailyActivity.filter { calendar.isDate($0.date, inSameDayAs: date) }
        guard !matching.isEmpty else { return nil }
        return matching.reduce(0) { $0 + $1.totalTokens }
    }

    func effectiveTokens(on date: Date, calendar: Calendar = .current) -> Int64? {
        guard has(.tokenUsage) else { return nil }
        if let tokenRecordedDates,
           !tokenRecordedDates.contains(where: { calendar.isDate($0, inSameDayAs: date) }) {
            return nil
        }
        let matching = dailyActivity.filter { calendar.isDate($0.date, inSameDayAs: date) }
        guard !matching.isEmpty else { return nil }
        return matching.reduce(0) { result, activity in
            result + max(0, activity.totalTokens - activity.cachedInputTokens)
        }
    }

    var todayTokens: Int64? { effectiveTokens(on: .now) }

    func calculatedCredits(on date: Date, calendar: Calendar = .current) -> Double? {
        guard has(.tokenUsage) else { return nil }
        let matching = dailyActivity.filter { calendar.isDate($0.date, inSameDayAs: date) }
        guard matching.contains(where: { $0.credits > 0 }) else { return nil }
        return matching.reduce(0) { $0 + max(0, $1.credits) }
    }

    var todayCalculatedCredits: Double? { calculatedCredits(on: .now) }

    var clientBreakdown: [CodexActivityBreakdown] { aggregate(\.clients) }
    var modelBreakdown: [CodexActivityBreakdown] { aggregate(\.models) }
    var productSurfaceAverages: [(name: String, percentage: Double)] {
        guard !dailyProductUsage.isEmpty else { return [] }
        var totals: [String: Double] = [:]
        for day in dailyProductUsage {
            for (name, value) in day.percentages { totals[name, default: 0] += value }
        }
        return totals.map { ($0.key, $0.value / Double(dailyProductUsage.count)) }
            .filter { $0.percentage > 0 }
            .sorted { $0.percentage == $1.percentage ? $0.name < $1.name : $0.percentage > $1.percentage }
    }
    var modelCreditBreakdown: [CodexModelCreditUsage] {
        var totals: [String: (model: String, speed: String, credits: Double)] = [:]
        for item in dailyProductUsage.flatMap(\.models) {
            let key = "\(item.model)|\(item.speed)"
            let old = totals[key]
            totals[key] = (item.model, item.speed, (old?.credits ?? 0) + item.credits)
        }
        return totals.values.map { CodexModelCreditUsage(model: $0.model, speed: $0.speed, credits: $0.credits) }
            .sorted { $0.credits > $1.credits }
    }

    private func aggregate(_ keyPath: KeyPath<CodexDailyActivity, [CodexActivityBreakdown]>) -> [CodexActivityBreakdown] {
        var values: [String: CodexActivityBreakdown] = [:]
        for day in dailyActivity {
            for item in day[keyPath: keyPath] {
                let old = values[item.name]
                values[item.name] = CodexActivityBreakdown(
                    name: item.name,
                    threads: (old?.threads ?? 0) + item.threads,
                    turns: (old?.turns ?? 0) + item.turns,
                    credits: (old?.credits ?? 0) + item.credits,
                    totalTokens: (old?.totalTokens ?? 0) + item.totalTokens
                )
            }
        }
        return values.values.sorted { $0.turns == $1.turns ? $0.name < $1.name : $0.turns > $1.turns }
    }

    func merging(_ other: CodexAnalyticsSnapshot) -> CodexAnalyticsSnapshot {
        let preferredTokenSource: CodexAnalyticsSnapshot = {
            if has(.tokenUsage), sourceDisplayName.contains("本机 Codex") { return self }
            if other.has(.tokenUsage), other.sourceDisplayName.contains("本机 Codex") { return other }
            if other.has(.tokenUsage) { return other }
            return self
        }()
        let preferredActivitySource = other.has(.activity) ? other : self
        let tokenActivity = mergedTokenActivity(preferred: preferredTokenSource, other: other)
        let mergedActivity = mergeDailyActivity(tokenActivity: tokenActivity, activitySource: preferredActivitySource)
        let mergedProducts = other.has(.productUsage) ? other.dailyProductUsage : dailyProductUsage
        let mergedSkills = other.has(.skills) ? other.topSkills : topSkills
        let mergedPlugins = other.has(.plugins) ? other.topPlugins : topPlugins
        let mergedSections = availableSections.union(other.availableSections)
        let dates = mergedActivity.map(\.date) + mergedProducts.map(\.date)
        let sources = [sourceDisplayName, other.sourceDisplayName].reduce(into: [String]()) { result, value in
            if !result.contains(value) { result.append(value) }
        }
        let mergedSourceName: String = {
            let hasRealtime = sources.contains {
                $0.contains("本机 Codex 实时")
                    || $0.contains("本机 Codex（实时")
                    || $0.contains("本机 Codex 本地用量")
            }
            let hasLocalHistory = sources.contains {
                $0.contains("本机 Codex 用量") || $0.contains("实时 + 历史")
            }
            if hasRealtime && hasLocalHistory {
                return "本机 Codex（实时 + 历史）"
            }
            if hasRealtime {
                return "本机 Codex 实时用量"
            }
            return sources.joined(separator: " + ")
        }()
        var result = CodexAnalyticsSnapshot(
            fetchedAt: max(fetchedAt, other.fetchedAt),
            sourceDisplayName: mergedSourceName,
            rangeStart: dates.min() ?? minOptional(rangeStart, other.rangeStart),
            rangeEnd: dates.max() ?? maxOptional(rangeEnd, other.rangeEnd),
            groupBy: other.groupBy,
            dailyActivity: mergedActivity,
            dailyProductUsage: mergedProducts,
            topSkills: mergedSkills,
            topPlugins: mergedPlugins,
            creditEventCount: other.has(.creditEvents) ? other.creditEventCount : creditEventCount,
            availableSections: mergedSections,
            lifetimeTokens: lifetimeTokens ?? other.lifetimeTokens,
            peakDailyTokens: peakDailyTokens ?? other.peakDailyTokens,
            currentStreakDays: currentStreakDays ?? other.currentStreakDays,
            longestStreakDays: longestStreakDays ?? other.longestStreakDays,
            longestRunningTurnSeconds: longestRunningTurnSeconds ?? other.longestRunningTurnSeconds
        )
        result.sectionSources = sectionSources.merging(other.sectionSources) { _, newer in newer }
        result.warnings = Array(Set(warnings + other.warnings)).sorted()
        result.tokenRecordedDates = Set(tokenActivity.map { Calendar.current.startOfDay(for: $0.date) })
        return result
    }

    var compactSourceDisplayName: String {
        if sourceDisplayName.contains("本机 Codex（实时")
            || sourceDisplayName.contains("本机 Codex 实时")
            || sourceDisplayName.contains("本机 Codex 本地用量") {
            return "本机实时"
        }
        if sourceDisplayName == "本机 Codex 用量" { return "本机 Codex" }
        return sourceDisplayName
    }

    private func mergedTokenActivity(preferred: CodexAnalyticsSnapshot,
                                     other: CodexAnalyticsSnapshot) -> [CodexDailyActivity] {
        guard sourceDisplayName.contains("实时") || other.sourceDisplayName.contains("实时") else {
            return preferred.dailyActivity
        }
        let baseline = sourceDisplayName.contains("实时") ? other.dailyActivity : dailyActivity
        let realtime = sourceDisplayName.contains("实时") ? dailyActivity : other.dailyActivity
        var values = dailyActivityByCalendarDay(baseline)
        for day in realtime {
            values[Calendar.current.startOfDay(for: day.date)] = day
        }
        return values.keys.sorted().compactMap { values[$0] }
    }

    private func mergeDailyActivity(tokenActivity: [CodexDailyActivity],
                                    activitySource: CodexAnalyticsSnapshot) -> [CodexDailyActivity] {
        let tokenDays = dailyActivityByCalendarDay(tokenActivity)
        let activityDays = dailyActivityByCalendarDay(activitySource.dailyActivity)
        return Set(tokenDays.keys).union(activityDays.keys).sorted().map { date in
            let token = tokenDays[date]
            let activity = activityDays[date]
            return CodexDailyActivity(
                date: date,
                users: activity?.users ?? 0,
                threads: activity?.threads ?? 0,
                turns: activity?.turns ?? 0,
                credits: token?.credits ?? activity?.credits ?? 0,
                uncachedInputTokens: token?.uncachedInputTokens ?? 0,
                cachedInputTokens: token?.cachedInputTokens ?? 0,
                outputTokens: token?.outputTokens ?? 0,
                totalTokens: token?.totalTokens ?? 0,
                clients: activity?.clients ?? [],
                models: activity?.models ?? []
            )
        }
    }

    /// Date-only buckets can arrive as UTC midnight while local session data is
    /// grouped at local midnight. Treat both as the same calendar day so the
    /// realtime value replaces the delayed account-usage value instead of being
    /// counted a second time.
    private func dailyActivityByCalendarDay(
        _ values: [CodexDailyActivity],
        calendar: Calendar = .current
    ) -> [Date: CodexDailyActivity] {
        values.reduce(into: [:]) { result, value in
            result[calendar.startOfDay(for: value.date)] = value
        }
    }

    private func minOptional(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) { case let (l?, r?): min(l, r); case let (l?, nil): l; case let (nil, r?): r; default: nil }
    }

    private func maxOptional(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) { case let (l?, r?): max(l, r); case let (l?, nil): l; case let (nil, r?): r; default: nil }
    }
}

struct CodexDailyActivity: Sendable, Codable, Equatable, Identifiable {
    var id: Date { date }
    let date: Date
    let users: Int
    let threads: Int
    let turns: Int
    let credits: Double
    let uncachedInputTokens: Int64
    let cachedInputTokens: Int64
    let outputTokens: Int64
    let totalTokens: Int64
    let clients: [CodexActivityBreakdown]
    let models: [CodexActivityBreakdown]
}

struct CodexActivityBreakdown: Sendable, Codable, Equatable, Identifiable {
    var id: String { name }
    let name: String
    let threads: Int
    let turns: Int
    let credits: Double
    let totalTokens: Int64
}

struct CodexDailyProductUsage: Sendable, Codable, Equatable, Identifiable {
    var id: Date { date }
    let date: Date
    let percentages: [String: Double]
    let models: [CodexModelCreditUsage]
}

struct CodexModelCreditUsage: Sendable, Codable, Equatable, Identifiable {
    var id: String { "\(model)-\(speed)" }
    let model: String
    let speed: String
    let credits: Double
}

struct CodexNamedUsage: Sendable, Codable, Equatable, Identifiable {
    var id: String { name }
    let name: String
    let displayName: String
    let invocations: Int
}
