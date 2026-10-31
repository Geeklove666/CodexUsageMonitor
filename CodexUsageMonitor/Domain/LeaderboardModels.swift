import Foundation

enum LeaderboardConfiguration {
    static let siteURL = URL(string: "https://codex-token-league.russetwolf8.chatgpt.site")!
    static let enabledKey = "leaderboardSyncEnabled"
    static let handleKey = "leaderboardPublicHandle"
    static let lastSyncKey = "leaderboardLastSync"
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }
}

struct LeaderboardDailyCount: Codable, Sendable, Equatable {
    let date: String
    let tokens: Int64
}

struct LeaderboardUpload: Encodable, Sendable, Equatable {
    let source = "codex-local-effective-v1"
    let days: [LeaderboardDailyCount]

    static func make(analytics: CodexAnalyticsSnapshot, now: Date = .now) -> LeaderboardUpload? {
        let calendar = LeaderboardConfiguration.calendar
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -6, to: today), analytics.has(.tokenUsage) else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let dates = Set(analytics.dailyActivity.map { calendar.startOfDay(for: $0.date) })
        let counts = dates.sorted().compactMap { day -> LeaderboardDailyCount? in
            guard day >= start, day <= today,
                  let tokens = analytics.effectiveTokens(on: day, calendar: calendar),
                  tokens >= 0, tokens <= 100_000_000_000 else { return nil }
            return LeaderboardDailyCount(date: formatter.string(from: day), tokens: tokens)
        }
        return counts.isEmpty ? nil : LeaderboardUpload(days: counts)
    }
}

struct LeaderboardDeviceStart: Decodable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationUri: URL
    let expiresIn: Int
    let interval: Int
}

struct LeaderboardCredential: Codable, Sendable {
    struct Profile: Codable, Sendable { let handle: String }
    let accessToken: String
    let deviceId: String
    let profile: Profile
}

enum LeaderboardError: LocalizedError {
    case server(String), keychain, pending, expired
    var errorDescription: String? {
        switch self {
        case let .server(message): message
        case .keychain: "设备授权无法保存到钥匙串，请重试"
        case .pending: "等待浏览器确认连接"
        case .expired: "设备连接已过期，请重新连接"
        }
    }
}
