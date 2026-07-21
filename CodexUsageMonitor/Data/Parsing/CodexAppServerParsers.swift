import Foundation

struct CodexAppServerRateLimitParser: Sendable {
    func parse(account accountData: Data, rateLimits rateLimitsData: Data, now: Date = .now) throws -> CodexUsageSnapshot {
        let decoder = JSONDecoder()
        let accountResponse = try decoder.decode(AccountResponse.self, from: accountData)
        guard let account = accountResponse.result?.account else { throw LocalCodexSessionError.openAIAuthRequired }
        guard account.type == "chatgpt" || account.type == "personalAccessToken" else {
            throw LocalCodexSessionError.notChatGPTLogin
        }

        let limitsResponse = try decoder.decode(RateLimitsResponse.self, from: rateLimitsData)
        guard let result = limitsResponse.result,
              let limits = result.rateLimits else {
            throw LocalCodexSessionError.invalidResponse
        }
        let candidates = rateLimitCandidates(primary: limits, byLimitID: result.rateLimitsByLimitId)
        let primary = candidates.lazy.compactMap { makeWindow($0.primary, kind: .primary) }.first
        let secondary = makeWindow(limits.secondary, kind: .secondary)
            ?? candidates.dropFirst().lazy.compactMap { makeWindow($0.secondary, kind: .secondary) }.first
        let credits = candidates.lazy.compactMap { makeCredits($0.credits) }.first
        let resetAllowance = makeResetAllowance(limitsResponse.result?.rateLimitResetCredits)
        let planName = account.planType ?? candidates.lazy.compactMap(\.planType).first
        let accountIdentity = CodexAccountIdentity(
            email: account.email,
            accountID: account.accountID,
            planName: planName
        )
        guard primary != nil || secondary != nil || credits != nil || accountIdentity.hasAnyValue else {
            throw LocalCodexSessionError.invalidResponse
        }
        let completeness = min(1, 0.25 + (secondary == nil ? 0 : 0.2) + (planName == nil ? 0 : 0.2)
            + (credits == nil ? 0 : 0.15) + (resetAllowance == nil ? 0 : 0.1))
        let individualLimit = candidates.lazy.compactMap(\.individualLimit).first
        let details = [limits.limitName, limits.rateLimitReachedType,
                       individualLimit?.remainingPercent.map { "个人消费限制剩余 \(Int($0.rounded()))%" },
                       result.rateLimitsByLimitId.map { "子额度 \($0.count) 项" },
                       resetAllowance.map { "使用限额重置可用 \($0.availableCount) 次" }]
            .compactMap { $0 }.joined(separator: " · ")

        return CodexUsageSnapshot(
            fetchedAt: now,
            planName: planName,
            primaryWindow: primary,
            secondaryWindow: secondary,
            credits: credits,
            resetAllowance: resetAllowance,
            accountIdentity: accountIdentity,
            sourceKind: .localCodexSession,
            sourceDisplayName: "本机 Codex 登录",
            confidence: primary == nil && secondary == nil ? .medium : .verified,
            fieldCompleteness: completeness,
            expiresAt: now.addingTimeInterval(300),
            diagnosticMessage: details.isEmpty ? "经用户授权使用本机 Codex 登录读取额度；应用未读取或保存 Token" : details
        )
    }

    private func rateLimitCandidates(primary: RateLimitsValue, byLimitID: [String: RateLimitsValue]?) -> [RateLimitsValue] {
        [primary] + (byLimitID?.values.sorted {
            ($0.limitName ?? $0.limitId ?? "") < ($1.limitName ?? $1.limitId ?? "")
        } ?? [])
    }

    private func makeCredits(_ value: CreditsSnapshot?) -> CreditsUsage? {
        guard let value, value.hasCredits || value.unlimited || value.balance != nil else { return nil }
        let balance = value.balance.flatMap { Decimal(string: $0) }
        return CreditsUsage(remaining: balance, used: nil, currencyOrUnit: value.unlimited ? "无限" : "Credits", expiresAt: nil)
    }

    private func makeResetAllowance(_ value: ResetCreditsSnapshot?) -> UsageResetAllowance? {
        guard let value else { return nil }
        let credits = (value.credits ?? []).map {
            UsageResetCredit(
                resetType: $0.resetType,
                status: $0.status,
                grantedAt: $0.grantedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                expiresAt: $0.expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                title: $0.title
            )
        }
        return UsageResetAllowance(availableCount: value.availableCount ?? 0, credits: credits)
    }

    private func makeWindow(_ value: RateWindow?, kind: UsageWindowKind) -> UsageLimitWindow? {
        guard let used = value?.usedPercent else { return nil }
        let reset = value?.resetsAt.map { Date(timeIntervalSince1970: $0) }
        let duration = value?.windowDurationMins.map(durationDescription)
        return UsageLimitWindow(kind: kind, remainingPercentage: 100 - used,
                                usedPercentage: used, resetsAt: reset, durationDescription: duration)
    }

    private func durationDescription(minutes: Double) -> String {
        let value = Int(minutes.rounded())
        if value >= 10_080, value.isMultiple(of: 10_080) { return "\(value / 10_080) 周" }
        if value >= 1_440, value.isMultiple(of: 1_440) { return "\(value / 1_440) 天" }
        if value >= 60, value.isMultiple(of: 60) { return "\(value / 60) 小时" }
        return "\(value) 分钟"
    }
}

struct CodexAppServerAccountUsageParser: Sendable {
    func parse(response data: Data, now: Date = .now) throws -> CodexAnalyticsSnapshot {
        let value = try JSONDecoder().decode(AccountUsageEnvelope.self, from: data)
        guard let result = value.result else { throw LocalCodexSessionError.invalidResponse }
        let allBuckets = result.dailyUsageBuckets ?? []
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let startOfToday = calendar.startOfDay(for: now)
        let cutoff = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? .distantPast
        let activity = allBuckets.compactMap { bucket -> CodexDailyActivity? in
            guard let date = parseDate(bucket.startDate, calendar: calendar), date >= cutoff, date <= startOfToday else { return nil }
            return CodexDailyActivity(
                date: date, users: 0, threads: 0, turns: 0, credits: 0,
                uncachedInputTokens: 0, cachedInputTokens: 0, outputTokens: 0,
                totalTokens: bucket.tokens, clients: [], models: []
            )
        }.sorted { $0.date < $1.date }
        guard result.summary.hasAnyValue || result.dailyUsageBuckets != nil else {
            throw LocalCodexSessionError.invalidResponse
        }
        var snapshot = CodexAnalyticsSnapshot(
            fetchedAt: now,
            sourceDisplayName: "本机 Codex 用量",
            rangeStart: activity.map(\.date).min(),
            rangeEnd: activity.map(\.date).max(),
            groupBy: "day",
            dailyActivity: activity,
            dailyProductUsage: [],
            topSkills: [],
            topPlugins: [],
            creditEventCount: nil,
            availableSections: result.dailyUsageBuckets == nil ? [] : [.tokenUsage],
            lifetimeTokens: result.summary.lifetimeTokens,
            peakDailyTokens: result.summary.peakDailyTokens,
            currentStreakDays: result.summary.currentStreakDays.flatMap(Int.init(exactly:)),
            longestStreakDays: result.summary.longestStreakDays.flatMap(Int.init(exactly:)),
            longestRunningTurnSeconds: result.summary.longestRunningTurnSec.flatMap(Int.init(exactly:))
        )
        if snapshot.has(.tokenUsage) { snapshot.sectionSources[.tokenUsage] = "本机 Codex 用量" }
        return snapshot
    }

    private func parseDate(_ value: String, calendar: Calendar) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

private struct AccountResponse: Decodable {
    let result: AccountResult?
}

private struct AccountResult: Decodable {
    let account: LocalCodexAccount?
    let requiresOpenaiAuth: Bool?
}

private struct LocalCodexAccount: Decodable {
    let type: String
    let email: String?
    let accountID: String?
    let planType: String?

    enum CodingKeys: String, CodingKey {
        case type, email, planType
        case accountID
        case accountId
        case accountIDSnake = "account_id"
        case providerAccountID
        case providerAccountIDSnake = "provider_account_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        email = try? container.decodeIfPresent(String.self, forKey: .email)
        planType = try? container.decodeIfPresent(String.self, forKey: .planType)
        accountID = Self.firstString(
            in: container,
            keys: [.accountID, .accountId, .accountIDSnake, .providerAccountID, .providerAccountIDSnake]
        )
    }

    private static func firstString(
        in container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> String? {
        for key in keys {
            if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                return value
            }
        }
        return nil
    }
}

private struct RateLimitsResponse: Decodable {
    let result: RateLimitsResult?
}

private struct RateLimitsResult: Decodable {
    let rateLimits: RateLimitsValue?
    let rateLimitsByLimitId: [String: RateLimitsValue]?
    let rateLimitResetCredits: ResetCreditsSnapshot?

    enum CodingKeys: String, CodingKey {
        case rateLimits
        case rateLimitsByLimitId
        case rateLimitsByLimitIdSnake = "rate_limits_by_limit_id"
        case rateLimitResetCredits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rateLimits = try? container.decodeIfPresent(RateLimitsValue.self, forKey: .rateLimits)
        rateLimitsByLimitId = (try? container.decodeIfPresent([String: RateLimitsValue].self, forKey: .rateLimitsByLimitId))
            ?? (try? container.decodeIfPresent([String: RateLimitsValue].self, forKey: .rateLimitsByLimitIdSnake))
        rateLimitResetCredits = try? container.decodeIfPresent(ResetCreditsSnapshot.self, forKey: .rateLimitResetCredits)
    }
}

private struct ResetCreditsSnapshot: Decodable {
    let availableCount: Int?
    let credits: [ResetCreditSnapshot]?
}

private struct ResetCreditSnapshot: Decodable {
    let resetType: String?
    let status: String?
    let grantedAt: Int64?
    let expiresAt: Int64?
    let title: String?
}

private struct RateLimitsValue: Decodable {
    let primary: RateWindow?
    let secondary: RateWindow?
    let credits: CreditsSnapshot?
    let individualLimit: SpendControlLimitSnapshot?
    let limitId: String?
    let limitName: String?
    let planType: String?
    let rateLimitReachedType: String?

    enum CodingKeys: String, CodingKey {
        case primary, secondary, credits
        case individualLimit
        case individualLimitSnake = "individual_limit"
        case limitId
        case limitIdSnake = "limit_id"
        case limitName
        case limitNameSnake = "limit_name"
        case planType
        case planTypeSnake = "plan_type"
        case rateLimitReachedType
        case rateLimitReachedTypeSnake = "rate_limit_reached_type"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primary = try? container.decodeIfPresent(RateWindow.self, forKey: .primary)
        secondary = try? container.decodeIfPresent(RateWindow.self, forKey: .secondary)
        credits = try? container.decodeIfPresent(CreditsSnapshot.self, forKey: .credits)
        individualLimit = (try? container.decodeIfPresent(SpendControlLimitSnapshot.self, forKey: .individualLimit))
            ?? (try? container.decodeIfPresent(SpendControlLimitSnapshot.self, forKey: .individualLimitSnake))
        limitId = (try? container.decodeIfPresent(String.self, forKey: .limitId))
            ?? (try? container.decodeIfPresent(String.self, forKey: .limitIdSnake))
        limitName = (try? container.decodeIfPresent(String.self, forKey: .limitName))
            ?? (try? container.decodeIfPresent(String.self, forKey: .limitNameSnake))
        planType = (try? container.decodeIfPresent(String.self, forKey: .planType))
            ?? (try? container.decodeIfPresent(String.self, forKey: .planTypeSnake))
        rateLimitReachedType = (try? container.decodeIfPresent(String.self, forKey: .rateLimitReachedType))
            ?? (try? container.decodeIfPresent(String.self, forKey: .rateLimitReachedTypeSnake))
    }
}

private struct CreditsSnapshot: Decodable {
    let balance: String?
    let hasCredits: Bool
    let unlimited: Bool
}

private struct SpendControlLimitSnapshot: Decodable {
    let limit: Double?
    let remainingPercent: Double?
    let resetsAt: Int64?
    let used: Double?

    enum CodingKeys: String, CodingKey {
        case limit
        case remainingPercent
        case remainingPercentSnake = "remaining_percent"
        case resetsAt
        case resetsAtSnake = "resets_at"
        case used
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limit = Self.decodeDouble(container, .limit)
        remainingPercent = Self.decodeDouble(container, .remainingPercent)
            ?? Self.decodeDouble(container, .remainingPercentSnake)
        resetsAt = (try? container.decodeIfPresent(Int64.self, forKey: .resetsAt))
            ?? (try? container.decodeIfPresent(Int64.self, forKey: .resetsAtSnake))
        used = Self.decodeDouble(container, .used)
    }

    private static func decodeDouble(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) { return Double(value) }
        return nil
    }
}

private struct RateWindow: Decodable {
    let usedPercent: Double?
    let windowDurationMins: Double?
    let resetsAt: Double?
}

private struct AccountUsageEnvelope: Decodable {
    let result: AccountUsageResult?
}

private struct AccountUsageResult: Decodable {
    let summary: AccountUsageSummary
    let dailyUsageBuckets: [AccountUsageBucket]?
}

private struct AccountUsageSummary: Decodable {
    let lifetimeTokens: Int64?
    let peakDailyTokens: Int64?
    let longestRunningTurnSec: Int64?
    let currentStreakDays: Int64?
    let longestStreakDays: Int64?

    var hasAnyValue: Bool {
        lifetimeTokens != nil || peakDailyTokens != nil || longestRunningTurnSec != nil
            || currentStreakDays != nil || longestStreakDays != nil
    }
}

private struct AccountUsageBucket: Decodable {
    let startDate: String
    let tokens: Int64
}
