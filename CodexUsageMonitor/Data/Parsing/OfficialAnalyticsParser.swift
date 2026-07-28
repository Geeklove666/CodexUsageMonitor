import Foundation

struct OfficialAnalyticsParser: Sendable {
    let parserVersion = "2026.07-analytics-capture-1"

    func parse(data: Data) throws -> CodexAnalyticsSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageMonitorError.unsupportedResponse
        }

        let workspace: WorkspaceResponse? = decode(root[Paths.workspace])
        let tokenUsage: TokenUsageResponse? = decode(root[Paths.tokenUsage])
        let skillUsage: SkillUsageResponse? = decode(root[Paths.skills])
        let pluginUsage: PluginUsageResponse? = decode(root[Paths.plugins])
        let malformed = [
            (Paths.workspace, root[Paths.workspace] != nil && workspace == nil),
            (Paths.tokenUsage, root[Paths.tokenUsage] != nil && tokenUsage == nil),
            (Paths.skills, root[Paths.skills] != nil && skillUsage == nil),
            (Paths.plugins, root[Paths.plugins] != nil && pluginUsage == nil)
        ].filter { $0.1 }.map { $0.0 }
        let creditEvents = (root[Paths.creditEvents] as? [String: Any])?["data"] as? [Any]
        var availableSections: Set<CodexAnalyticsSection> = []
        if workspace != nil { availableSections.formUnion([.activity, .tokenUsage]) }
        if tokenUsage != nil { availableSections.insert(.productUsage) }
        if skillUsage != nil { availableSections.insert(.skills) }
        if pluginUsage != nil { availableSections.insert(.plugins) }
        if creditEvents != nil { availableSections.insert(.creditEvents) }

        let activity = (workspace?.data ?? []).compactMap(makeActivity).sorted { $0.date < $1.date }
        let products = (tokenUsage?.data ?? []).compactMap(makeProductUsage).sorted { $0.date < $1.date }
        let skills = aggregateSkills(skillUsage?.data ?? [])
        let plugins = aggregatePlugins(pluginUsage?.data ?? [])
        guard !activity.isEmpty || !products.isEmpty || !skills.isEmpty || !plugins.isEmpty || creditEvents != nil else {
            throw UsageMonitorError.parsingFailed
        }
        let dates = activity.map(\.date) + products.map(\.date)

        var result = CodexAnalyticsSnapshot(
            fetchedAt: .now,
            sourceDisplayName: "官方页面分析",
            rangeStart: dates.min(),
            rangeEnd: dates.max(),
            groupBy: workspace?.groupBy ?? tokenUsage?.groupBy ?? skillUsage?.groupBy ?? "day",
            dailyActivity: activity,
            dailyProductUsage: products,
            topSkills: skills,
            topPlugins: plugins,
            creditEventCount: creditEvents?.count,
            availableSections: availableSections,
            lifetimeTokens: nil,
            peakDailyTokens: nil,
            currentStreakDays: nil,
            longestStreakDays: nil,
            longestRunningTurnSeconds: nil
        )
        result.sectionSources = Dictionary(uniqueKeysWithValues: availableSections.map { ($0, "官方页面分析") })
        result.tokenRecordedDates = workspace == nil ? nil : Set(activity.map(\.date))
        result.warnings = malformed.map { "响应结构不兼容：\($0)" }
        return result
    }

    private func makeActivity(_ value: WorkspaceDay) -> CodexDailyActivity? {
        guard let date = parseDate(value.date) else { return nil }
        return CodexDailyActivity(
            date: date,
            users: value.totals.users,
            threads: value.totals.threads,
            turns: value.totals.turns,
            credits: value.totals.credits,
            uncachedInputTokens: value.totals.uncachedInputTokens,
            cachedInputTokens: value.totals.cachedInputTokens,
            outputTokens: value.totals.outputTokens,
            totalTokens: value.totals.totalTokens,
            clients: value.clients.map { breakdown(name: $0.clientID, value: $0) },
            models: value.models.map { breakdown(name: $0.model, value: $0) }
        )
    }

    private func makeProductUsage(_ value: TokenUsageDay) -> CodexDailyProductUsage? {
        guard let date = parseDate(value.date) else { return nil }
        return CodexDailyProductUsage(
            date: date,
            percentages: value.productSurfaceUsageValues,
            models: value.models.map { CodexModelCreditUsage(model: $0.model, speed: $0.speed, credits: $0.credits) }
        )
    }

    private func breakdown(name: String, value: ActivityValues) -> CodexActivityBreakdown {
        CodexActivityBreakdown(name: name, threads: value.threads, turns: value.turns,
                               credits: value.credits, totalTokens: value.totalTokens)
    }

    private func aggregateSkills(_ days: [SkillUsageDay]) -> [CodexNamedUsage] {
        var totals: [String: (String, Int)] = [:]
        for item in days.flatMap(\.skillUsageOverviews) {
            let current = totals[item.skillName]
            totals[item.skillName] = (item.displayName ?? item.skillName, (current?.1 ?? 0) + item.invocationCounts)
        }
        return totals.map { CodexNamedUsage(name: $0.key, displayName: $0.value.0, invocations: $0.value.1) }
            .sorted { $0.invocations == $1.invocations ? $0.displayName < $1.displayName : $0.invocations > $1.invocations }
    }

    private func aggregatePlugins(_ days: [PluginUsageDay]) -> [CodexNamedUsage] {
        var totals: [String: (String, Int)] = [:]
        for item in days.flatMap(\.pluginUsageOverviews) {
            let key = item.pluginID ?? item.pluginName
            let current = totals[key]
            totals[key] = (item.displayName ?? item.pluginName, (current?.1 ?? 0) + item.invocationCounts)
        }
        return totals.map { CodexNamedUsage(name: $0.key, displayName: $0.value.0, invocations: $0.value.1) }
            .sorted { $0.invocations == $1.invocations ? $0.displayName < $1.displayName : $0.invocations > $1.invocations }
    }

    private func decode<T: Decodable>(_ value: Any?) -> T? {
        guard let value, JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func parseDate(_ value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

private enum Paths {
    static let workspace = "/backend-api/wham/analytics/daily-workspace-usage-counts"
    static let tokenUsage = "/backend-api/wham/usage/daily-token-usage-breakdown"
    static let skills = "/backend-api/wham/analytics/daily-skill-usage-metrics"
    static let plugins = "/backend-api/wham/analytics/daily-plugin-usage-metrics"
    static let creditEvents = "/backend-api/wham/usage/credit-usage-events"
}

private struct WorkspaceResponse: Decodable { let data: [WorkspaceDay]; let groupBy: String?; enum CodingKeys: String, CodingKey { case data; case groupBy = "group_by" } }
private struct WorkspaceDay: Decodable { let date: String; let totals: ActivityValues; let clients: [ClientValues]; let models: [ModelValues] }
private struct ActivityValues: Decodable {
    let users: Int; let threads: Int; let turns: Int; let credits: Double
    let uncachedInputTokens: Int64; let cachedInputTokens: Int64; let outputTokens: Int64; let totalTokens: Int64
    enum CodingKeys: String, CodingKey {
        case users, threads, turns, credits
        case uncachedInputTokens = "uncached_text_input_tokens"
        case cachedInputTokens = "cached_text_input_tokens"
        case outputTokens = "text_output_tokens"
        case totalTokens = "text_total_tokens"
    }
}
private struct ClientValues: Decodable, ActivityValueProviding {
    let clientID: String; let users: Int; let threads: Int; let turns: Int; let credits: Double; let totalTokens: Int64
    enum CodingKeys: String, CodingKey { case clientID = "client_id"; case users, threads, turns, credits; case totalTokens = "text_total_tokens" }
}
private struct ModelValues: Decodable, ActivityValueProviding {
    let model: String; let users: Int; let threads: Int; let turns: Int; let credits: Double
    var totalTokens: Int64 { 0 }
}
private protocol ActivityValueProviding { var threads: Int { get }; var turns: Int { get }; var credits: Double { get }; var totalTokens: Int64 { get } }
private extension OfficialAnalyticsParser {
    func breakdown(name: String, value: any ActivityValueProviding) -> CodexActivityBreakdown {
        CodexActivityBreakdown(name: name, threads: value.threads, turns: value.turns,
                               credits: value.credits, totalTokens: value.totalTokens)
    }
}

private struct TokenUsageResponse: Decodable { let data: [TokenUsageDay]; let units: String?; let groupBy: String?; enum CodingKeys: String, CodingKey { case data, units; case groupBy = "group_by" } }
private struct TokenUsageDay: Decodable {
    let date: String; let productSurfaceUsageValues: [String: Double]; let models: [TokenModel]
    enum CodingKeys: String, CodingKey { case date, models; case productSurfaceUsageValues = "product_surface_usage_values" }
}
private struct TokenModel: Decodable { let model: String; let speed: String; let credits: Double }

private struct SkillUsageResponse: Decodable { let data: [SkillUsageDay]; let groupBy: String?; enum CodingKeys: String, CodingKey { case data; case groupBy = "group_by" } }
private struct SkillUsageDay: Decodable { let date: String; let skillUsageOverviews: [SkillUsageItem]; enum CodingKeys: String, CodingKey { case date; case skillUsageOverviews = "skill_usage_overviews" } }
private struct SkillUsageItem: Decodable { let skillName: String; let displayName: String?; let invocationCounts: Int; enum CodingKeys: String, CodingKey { case skillName = "skill_name"; case displayName = "display_name"; case invocationCounts = "invocation_counts" } }

private struct PluginUsageResponse: Decodable { let data: [PluginUsageDay]; let groupBy: String?; enum CodingKeys: String, CodingKey { case data; case groupBy = "group_by" } }
private struct PluginUsageDay: Decodable { let date: String; let pluginUsageOverviews: [PluginUsageItem]; enum CodingKeys: String, CodingKey { case date; case pluginUsageOverviews = "plugin_usage_overviews" } }
private struct PluginUsageItem: Decodable {
    let pluginID: String?; let pluginName: String; let displayName: String?; let invocationCounts: Int
    enum CodingKeys: String, CodingKey { case pluginID = "plugin_id"; case pluginName = "plugin_name"; case displayName = "display_name"; case invocationCounts = "invocation_counts" }
}
