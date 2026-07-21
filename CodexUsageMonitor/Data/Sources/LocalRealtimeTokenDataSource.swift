import Foundation

enum LocalRealtimeTokenAuthorization {
    static let preferenceKey = AppPreferences.Key.localRealtimeTokenUsageEnabled
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

    fileprivate struct FileScanState: Sendable {
        let size: Int64
        let modifiedAt: Date
        let scannedOffset: UInt64
        let previousTotal: Int64?
        let tokensByDay: [Date: Int64]
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
        let previousStates = await cache.states(for: files)
        let states = await Task.detached(priority: .utility) {
            Dictionary(uniqueKeysWithValues: files.map { file in
                (file.url, Self.scan(file: file, previous: previousStates[file.url],
                                     now: now, rangeStart: rangeStart, calendar: calendar))
            })
        }.value
        await cache.store(states, retaining: files)
        return Self.snapshot(now: now, rangeStart: rangeStart, states: states)
    }

    func currentAnalyticsSnapshot() async -> CodexAnalyticsSnapshot? {
        await analyticsSnapshot(now: .now, authorizationGranted: nil)
    }

    private static func snapshot(now: Date, rangeStart: Date,
                                 states: [URL: FileScanState]) -> CodexAnalyticsSnapshot? {
        var tokensByDay: [Date: Int64] = [:]
        for state in states.values {
            for (date, tokens) in state.tokensByDay where date >= rangeStart {
                tokensByDay[date, default: 0] += tokens
            }
        }
        guard !tokensByDay.isEmpty else { return nil }
        var value = CodexAnalyticsSnapshot(
            fetchedAt: now,
            sourceDisplayName: "本机 Codex 实时用量",
            rangeStart: rangeStart,
            rangeEnd: Calendar.current.startOfDay(for: now),
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

    private static func scan(file: RolloutFile, previous: FileScanState?, now: Date,
                             rangeStart: Date, calendar: Calendar) -> FileScanState {
        if let previous, previous.size == file.size, previous.modifiedAt == file.modifiedAt {
            return pruning(previous, rangeStart: rangeStart)
        }

        let canContinue = previous.map {
            file.size > $0.size && $0.scannedOffset <= UInt64(max(0, $0.size))
        } ?? false
        let startingOffset = canContinue ? previous?.scannedOffset ?? 0 : 0
        var previousTotal = canContinue ? previous?.previousTotal : nil
        var tokensByDay = canContinue ? previous?.tokensByDay ?? [:] : [:]
        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: file.url)
            defer { try? handle.close() }
            try handle.seek(toOffset: startingOffset)
            data = try handle.readToEnd() ?? Data()
        } catch {
            return pruning(previous ?? FileScanState(
                size: file.size, modifiedAt: file.modifiedAt, scannedOffset: 0,
                previousTotal: nil, tokensByDay: [:]
            ), rangeStart: rangeStart)
        }

        let decoder = JSONDecoder()
        let fractionalTimestamp = ISO8601DateFormatter()
        fractionalTimestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standardTimestamp = ISO8601DateFormatter()
        let tokenMarker = Data("\"token_count\"".utf8)
        var cursor = data.startIndex
        var consumed = data.startIndex
        while cursor < data.endIndex {
            let newline = data[cursor...].firstIndex(of: 0x0A)
            let lineEnd = newline ?? data.endIndex
            let line = data.subdata(in: cursor..<lineEnd)
            var mayAdvance = true
            if line.count <= 1_048_576, line.range(of: tokenMarker) != nil {
                if let event = try? decoder.decode(RolloutEvent.self, from: line),
                   event.payload.type == "token_count",
                   let info = event.payload.info,
                   let timestamp = fractionalTimestamp.date(from: event.timestamp)
                    ?? standardTimestamp.date(from: event.timestamp) {
                    let current = info.totalTokenUsage.totalTokens
                    let increment = previousTotal.map { current >= $0 ? current - $0 : current } ?? current
                    previousTotal = current
                    if timestamp >= rangeStart, timestamp <= now.addingTimeInterval(60), increment >= 0 {
                        tokensByDay[calendar.startOfDay(for: timestamp), default: 0] += increment
                    }
                } else if newline == nil {
                    mayAdvance = false
                }
            }
            guard mayAdvance else { break }
            consumed = newline.map { data.index(after: $0) } ?? lineEnd
            guard let newline else { break }
            cursor = data.index(after: newline)
        }

        tokensByDay = tokensByDay.filter { $0.key >= rangeStart }
        return FileScanState(
            size: file.size,
            modifiedAt: file.modifiedAt,
            scannedOffset: startingOffset + UInt64(data.distance(from: data.startIndex, to: consumed)),
            previousTotal: previousTotal,
            tokensByDay: tokensByDay
        )
    }

    private static func pruning(_ state: FileScanState, rangeStart: Date) -> FileScanState {
        FileScanState(
            size: state.size,
            modifiedAt: state.modifiedAt,
            scannedOffset: state.scannedOffset,
            previousTotal: state.previousTotal,
            tokensByDay: state.tokensByDay.filter { $0.key >= rangeStart }
        )
    }

}

private actor LocalRealtimeTokenScanCache {
    private var fileStates: [URL: LocalRealtimeTokenUsageReader.FileScanState] = [:]

    func states(for files: [LocalRealtimeTokenUsageReader.RolloutFile])
        -> [URL: LocalRealtimeTokenUsageReader.FileScanState] {
        let active = Set(files.map(\.url))
        return fileStates.filter { active.contains($0.key) }
    }

    func store(_ states: [URL: LocalRealtimeTokenUsageReader.FileScanState],
               retaining files: [LocalRealtimeTokenUsageReader.RolloutFile]) {
        let active = Set(files.map(\.url))
        fileStates = states.filter { active.contains($0.key) }
    }
}
