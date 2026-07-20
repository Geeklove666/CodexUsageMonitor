import Foundation

enum LocalRealtimeTokenAuthorization {
    static let preferenceKey = "localRealtimeTokenUsageEnabled"
}

struct LocalRealtimeTokenUsageReader: RealtimeTokenUsageReading, Sendable {
    let sessionsRoot: URL
    private let cache: LocalRealtimeTokenScanCache

    init(sessionsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions", isDirectory: true)) {
        self.sessionsRoot = sessionsRoot
        cache = LocalRealtimeTokenScanCache()
    }

    fileprivate struct RolloutFile: Sendable, Equatable {
        let url: URL
        let size: Int64
        let modifiedAt: Date
    }

    private struct RolloutEvent: Decodable {
        let timestamp: String
        let payload: Payload

        struct Payload: Decodable {
            let type: String
            let info: Info?
        }

        struct Info: Decodable {
            let totalTokenUsage: TokenUsage

            enum CodingKeys: String, CodingKey { case totalTokenUsage = "total_token_usage" }
        }

        struct TokenUsage: Decodable {
            let totalTokens: Int64
            enum CodingKeys: String, CodingKey { case totalTokens = "total_tokens" }
        }
    }

    func analyticsSnapshot(now: Date = .now, authorizationGranted: Bool? = nil) async -> CodexAnalyticsSnapshot? {
        guard authorizationGranted ?? UserDefaults.standard.bool(forKey: LocalRealtimeTokenAuthorization.preferenceKey) else { return nil }
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        guard let rangeStart = calendar.date(byAdding: .day, value: -6, to: startOfToday),
              let files = rolloutFiles(modifiedSince: rangeStart) else { return nil }
        if let cached = await cache.value(rangeStart: rangeStart, files: files) { return cached }
        let value = await Task.detached(priority: .utility) {
            Self.snapshot(now: now, rangeStart: rangeStart, calendar: calendar, files: files)
        }.value
        await cache.store(value, rangeStart: rangeStart, files: files)
        return value
    }

    func currentAnalyticsSnapshot() async -> CodexAnalyticsSnapshot? {
        await analyticsSnapshot(now: .now, authorizationGranted: nil)
    }

    private static func snapshot(now: Date, rangeStart: Date, calendar: Calendar,
                                 files: [RolloutFile]) -> CodexAnalyticsSnapshot? {
        let decoder = JSONDecoder()
        let fractionalTimestamp = ISO8601DateFormatter()
        fractionalTimestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standardTimestamp = ISO8601DateFormatter()
        var tokensByDay: [Date: Int64] = [:]
        var observedEvents = 0

        for file in files {
            var previousTotal: Int64?
            scanTokenCountLines(at: file.url) { line in
                guard let event = try? decoder.decode(RolloutEvent.self, from: line),
                      event.payload.type == "token_count",
                      let info = event.payload.info,
                      let timestamp = fractionalTimestamp.date(from: event.timestamp)
                        ?? standardTimestamp.date(from: event.timestamp) else { return }
                let current = info.totalTokenUsage.totalTokens
                defer { previousTotal = current }
                guard timestamp >= rangeStart, timestamp <= now.addingTimeInterval(60) else { return }
                let increment = previousTotal.map { current >= $0 ? current - $0 : current } ?? current
                guard increment >= 0 else { return }
                tokensByDay[calendar.startOfDay(for: timestamp), default: 0] += increment
                observedEvents += 1
            }
        }

        guard observedEvents > 0 else { return nil }
        var value = CodexAnalyticsSnapshot(
            fetchedAt: now,
            sourceDisplayName: "本机 Codex 本地用量",
            rangeStart: rangeStart,
            rangeEnd: calendar.startOfDay(for: now),
            groupBy: "day",
            dailyActivity: tokensByDay.keys.sorted().map { date in
                CodexDailyActivity(
                    date: date, users: 0, threads: 0, turns: 0, credits: 0,
                    uncachedInputTokens: 0, cachedInputTokens: 0, outputTokens: 0,
                    totalTokens: tokensByDay[date] ?? 0, clients: [], models: []
                )
            },
            dailyProductUsage: [], topSkills: [], topPlugins: [], creditEventCount: nil,
            availableSections: [.tokenUsage], lifetimeTokens: nil, peakDailyTokens: nil,
            currentStreakDays: nil, longestStreakDays: nil, longestRunningTurnSeconds: nil
        )
        value.sectionSources[.tokenUsage] = "本机 Codex token_count 事件（最近 7 天）"
        value.warnings = ["每日 Token 仅统计这台 Mac 上 Codex 已落盘的 token_count 事件，不包含其他设备或尚未落盘的活动。"]
        return value
    }

    private func rolloutFiles(modifiedSince date: Date) -> [RolloutFile]? {
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }
        return enumerator.compactMap { item -> RolloutFile? in
            guard let url = item as? URL, url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate, modifiedAt >= date else { return nil }
            return RolloutFile(url: url, size: Int64(values.fileSize ?? 0), modifiedAt: modifiedAt)
        }.sorted { $0.url.path < $1.url.path }
    }

    private static func scanTokenCountLines(at url: URL, consume: (Data) -> Void) {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]), !data.isEmpty else { return }
        let tokenMarker = Data("\"token_count\"".utf8)
        var cursor = data.startIndex
        while cursor < data.endIndex,
              let marker = data.range(of: tokenMarker, options: [], in: cursor..<data.endIndex) {
            let lineStart = data[..<marker.lowerBound].lastIndex(of: 0x0A)
                .map { data.index(after: $0) } ?? data.startIndex
            let lineEnd = data[marker.upperBound...].firstIndex(of: 0x0A) ?? data.endIndex
            if data.distance(from: lineStart, to: lineEnd) <= 1_048_576 {
                consume(data.subdata(in: lineStart..<lineEnd))
            }
            guard lineEnd < data.endIndex else { break }
            cursor = data.index(after: lineEnd)
        }
    }

}

private actor LocalRealtimeTokenScanCache {
    private var rangeStart: Date?
    private var files: [LocalRealtimeTokenUsageReader.RolloutFile] = []
    private var snapshot: CodexAnalyticsSnapshot?
    private var hasValue = false

    func value(rangeStart: Date, files: [LocalRealtimeTokenUsageReader.RolloutFile]) -> CodexAnalyticsSnapshot? {
        guard hasValue, self.rangeStart == rangeStart, self.files == files else { return nil }
        return snapshot
    }

    func store(_ snapshot: CodexAnalyticsSnapshot?, rangeStart: Date,
               files: [LocalRealtimeTokenUsageReader.RolloutFile]) {
        self.rangeStart = rangeStart
        self.files = files
        self.snapshot = snapshot
        hasValue = true
    }
}
