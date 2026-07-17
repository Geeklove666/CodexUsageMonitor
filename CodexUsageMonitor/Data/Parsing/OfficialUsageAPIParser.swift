import Foundation

/// Parses the same `/wham/usage` response model used by the official Codex client.
struct OfficialUsageAPIParser: Sendable {
    let parserVersion = "2026.07-wham-1"

    func parse(data: Data) throws -> ParsedCodexUsage {
        let response: UsageResponse
        do { response = try JSONDecoder().decode(UsageResponse.self, from: data) }
        catch { throw UsageMonitorError.unsupportedResponse }

        let primary = makeWindow(response.rateLimit?.primaryWindow, kind: .primary)
        let secondary = makeWindow(response.rateLimit?.secondaryWindow, kind: .secondary)
        let resetAllowance = makeResetAllowance(response.rateLimitResetCredits)
        guard primary != nil || secondary != nil || response.credits != nil || resetAllowance != nil else {
            throw UsageMonitorError.parsingFailed
        }

        let credits = response.credits.map {
            CreditsUsage(
                remaining: $0.balance,
                used: nil,
                currencyOrUnit: $0.unlimited == true ? "Unlimited" : $0.hasCredits == false ? "Unavailable" : "Credits",
                expiresAt: nil
            )
        }
        var completeness = 0.0
        if primary != nil { completeness += 0.4 }
        if secondary != nil { completeness += 0.25 }
        if credits != nil { completeness += 0.2 }
        if response.planType != nil { completeness += 0.15 }
        if resetAllowance != nil { completeness += 0.1 }

        return ParsedCodexUsage(
            planName: response.planType.map(planDisplayName),
            primaryWindow: primary ?? secondary,
            secondaryWindow: primary == nil ? nil : secondary,
            credits: credits,
            resetAllowance: resetAllowance,
            sourceUpdatedAt: .now,
            fieldCompleteness: completeness
        )
    }

    private func makeResetAllowance(_ value: UsageResetCredits?) -> UsageResetAllowance? {
        guard let value else { return nil }
        return UsageResetAllowance(
            availableCount: value.availableCount,
            credits: value.credits.map {
                UsageResetCredit(
                    resetType: $0.resetType,
                    status: $0.status,
                    grantedAt: $0.grantedAt.flatMap(dateFromEpoch),
                    expiresAt: $0.expiresAt.flatMap(dateFromEpoch),
                    title: $0.title
                )
            }
        )
    }

    private func makeWindow(_ value: RateLimitWindow?, kind: UsageWindowKind) -> UsageLimitWindow? {
        guard let value, let used = value.usedPercent, (0...100).contains(used) else { return nil }
        return UsageLimitWindow(
            kind: kind,
            remainingPercentage: 100 - used,
            usedPercentage: used,
            resetsAt: value.resetAt.flatMap(dateFromEpoch),
            durationDescription: value.limitWindowSeconds.map(durationDescription)
        )
    }

    private func dateFromEpoch(_ value: Double) -> Date? {
        guard value.isFinite, value > 0 else { return nil }
        return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1_000 : value)
    }

    private func durationDescription(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes % 10_080 == 0 { return "\(minutes / 10_080) 周" }
        if minutes % 1_440 == 0 { return "\(minutes / 1_440) 天" }
        if minutes % 60 == 0 { return "\(minutes / 60) 小时" }
        return "\(minutes) 分钟"
    }

    private func planDisplayName(_ value: String) -> String {
        switch value.lowercased() {
        case "free": "Free"
        case "plus": "Plus"
        case "pro": "Pro 20x"
        case "prolite", "pro_5x", "pro5x": "Pro 5x"
        case "pro_20x", "pro20x": "Pro 20x"
        case "team", "business", "self_serve_business_usage_based": "Business"
        case "enterprise", "enterprise_cbp_automation", "enterprise_cbp_usage_based": "Enterprise"
        case "edu", "education", "edu_plus", "edu_pro": "Edu"
        default: value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

private struct UsageResponse: Decodable {
    let planType: String?
    let rateLimit: RateLimit?
    let credits: UsageCredits?
    let rateLimitResetCredits: UsageResetCredits?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case credits
        case rateLimitResetCredits = "rate_limit_reset_credits"
    }
}

private struct UsageResetCredits: Decodable {
    let availableCount: Int
    let credits: [UsageResetCreditResponse]

    enum CodingKeys: String, CodingKey {
        case availableCount = "available_count"
        case credits
    }
}

private struct UsageResetCreditResponse: Decodable {
    let resetType: String?
    let status: String?
    let grantedAt: Double?
    let expiresAt: Double?
    let title: String?

    enum CodingKeys: String, CodingKey {
        case resetType = "reset_type"
        case status
        case grantedAt = "granted_at"
        case expiresAt = "expires_at"
        case title
    }
}

private struct RateLimit: Decodable {
    let primaryWindow: RateLimitWindow?
    let secondaryWindow: RateLimitWindow?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

private struct RateLimitWindow: Decodable {
    let usedPercent: Double?
    let limitWindowSeconds: Double?
    let resetAt: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAt = "reset_at"
    }
}

private struct UsageCredits: Decodable {
    let hasCredits: Bool?
    let unlimited: Bool?
    let balance: Decimal?

    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited, balance
    }
}
