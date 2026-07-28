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
        let previousInput: Int64?
        let previousCachedInput: Int64?
        let previousOutput: Int64?
        let currentModel: String?
        let currentServiceTier: String?
        let tokensByDay: [Date: TokenTotals]
    }

    fileprivate struct TokenTotals: Sendable {
        var processed: Int64 = 0
        var cachedInput: Int64 = 0
        var credits: Double = 0

        var effective: Int64 { max(0, processed - cachedInput) }

        mutating func add(processed: Int64, cachedInput: Int64, credits: Double = 0) {
            self.processed += processed
            self.cachedInput += min(processed, cachedInput)
            self.credits += max(0, credits)
        }
    }

    private struct RolloutEvent: Decodable {
        let timestamp: String
        let payload: Payload

        struct Payload: Decodable {
            let type: String
            let info: Info?
            let threadSettings: ThreadSettings?

            enum CodingKeys: String, CodingKey {
                case type, info
                case threadSettings = "thread_settings"
            }
        }

        struct ThreadSettings: Decodable {
            let model: String?
            let serviceTier: String?

            enum CodingKeys: String, CodingKey {
                case model
                case serviceTier = "service_tier"
            }
        }

        struct Info: Decodable {
            let totalTokenUsage: TokenUsage

            enum CodingKeys: String, CodingKey { case totalTokenUsage = "total_token_usage" }
        }

        struct TokenUsage: Decodable {
            let totalTokens: Int64
            let inputTokens: Int64?
            let cachedInputTokens: Int64?
            let outputTokens: Int64?

            enum CodingKeys: String, CodingKey {
                case totalTokens = "total_tokens"
                case inputTokens = "input_tokens"
                case cachedInputTokens = "cached_input_tokens"
                case outputTokens = "output_tokens"
            }
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
        var tokensByDay: [Date: TokenTotals] = [:]
        for state in states.values {
            for (date, tokens) in state.tokensByDay where date >= rangeStart {
                tokensByDay[date, default: TokenTotals()].add(
                    processed: tokens.processed,
                    cachedInput: tokens.cachedInput,
                    credits: tokens.credits
                )
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
                    date: date, users: 0, threads: 0, turns: 0,
                    credits: tokensByDay[date]?.credits ?? 0,
                    uncachedInputTokens: tokensByDay[date]?.effective ?? 0,
                    cachedInputTokens: tokensByDay[date]?.cachedInput ?? 0,
                    outputTokens: 0,
                    totalTokens: tokensByDay[date]?.processed ?? 0, clients: [], models: []
                )
            },
            dailyProductUsage: [], topSkills: [], topPlugins: [], creditEventCount: nil,
            availableSections: [.tokenUsage], lifetimeTokens: nil, peakDailyTokens: nil,
            currentStreakDays: nil, longestStreakDays: nil, longestRunningTurnSeconds: nil
        )
        value.sectionSources[.tokenUsage] = "本机 Codex token_count（最近 7 天）"
        value.tokenRecordedDates = Set(tokensByDay.keys)
        value.warnings = [
            "每日优先显示本机 token_count 的有效 Token；仅在 Token 记录缺失时，才使用 Credits 变化估算。"
        ]
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
        var previousInput = canContinue ? previous?.previousInput : nil
        var previousCachedInput = canContinue ? previous?.previousCachedInput : nil
        var previousOutput = canContinue ? previous?.previousOutput : nil
        var currentModel = canContinue ? previous?.currentModel : nil
        var currentServiceTier = canContinue ? previous?.currentServiceTier : nil
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
                previousTotal: nil, previousInput: nil, previousCachedInput: nil,
                previousOutput: nil, currentModel: nil, currentServiceTier: nil,
                tokensByDay: [:]
            ), rangeStart: rangeStart)
        }

        let decoder = JSONDecoder()
        let fractionalTimestamp = ISO8601DateFormatter()
        fractionalTimestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standardTimestamp = ISO8601DateFormatter()
        let tokenMarker = Data("\"token_count\"".utf8)
        let settingsMarker = Data("\"thread_settings_applied\"".utf8)
        var cursor = data.startIndex
        var consumed = data.startIndex
        while cursor < data.endIndex {
            let newline = data[cursor...].firstIndex(of: 0x0A)
            let lineEnd = newline ?? data.endIndex
            let line = data.subdata(in: cursor..<lineEnd)
            var mayAdvance = true
            if line.count <= 1_048_576,
               (line.range(of: tokenMarker) != nil || line.range(of: settingsMarker) != nil) {
                if let event = try? decoder.decode(RolloutEvent.self, from: line),
                   let timestamp = fractionalTimestamp.date(from: event.timestamp)
                    ?? standardTimestamp.date(from: event.timestamp) {
                    if event.payload.type == "thread_settings_applied",
                       let settings = event.payload.threadSettings {
                        currentModel = settings.model ?? currentModel
                        currentServiceTier = settings.serviceTier ?? currentServiceTier
                    }
                    guard event.payload.type == "token_count", let info = event.payload.info else {
                        consumed = newline.map { data.index(after: $0) } ?? lineEnd
                        if let newline { cursor = data.index(after: newline); continue }
                        break
                    }
                    let current = info.totalTokenUsage.totalTokens
                    let currentInput = info.totalTokenUsage.inputTokens
                    let currentCachedInput = info.totalTokenUsage.cachedInputTokens ?? 0
                    let currentOutput = info.totalTokenUsage.outputTokens
                    let increment = previousTotal.map { current >= $0 ? current - $0 : current } ?? current
                    let inputIncrement = currentInput.map { value in
                        previousInput.map { value >= $0 ? value - $0 : value } ?? value
                    }
                    let cachedIncrement = previousCachedInput.map {
                        currentCachedInput >= $0 ? currentCachedInput - $0 : currentCachedInput
                    } ?? currentCachedInput
                    let outputIncrement = currentOutput.map { value in
                        previousOutput.map { value >= $0 ? value - $0 : value } ?? value
                    }
                    previousTotal = current
                    previousInput = currentInput
                    previousCachedInput = currentCachedInput
                    previousOutput = currentOutput
                    if timestamp >= rangeStart, timestamp <= now.addingTimeInterval(60), increment >= 0 {
                        let credits = currentModel.flatMap { model in
                            OpenAIChatGPTCreditCalculator.credits(
                                uncachedInputTokens: max(0, (inputIncrement ?? 0) - cachedIncrement),
                                cachedInputTokens: max(0, cachedIncrement),
                                outputTokens: max(0, outputIncrement ?? 0),
                                model: model,
                                serviceTier: currentServiceTier
                            )
                        } ?? 0
                        tokensByDay[calendar.startOfDay(for: timestamp), default: TokenTotals()].add(
                            processed: increment,
                            cachedInput: max(0, cachedIncrement),
                            credits: credits
                        )
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
            previousInput: previousInput,
            previousCachedInput: previousCachedInput,
            previousOutput: previousOutput,
            currentModel: currentModel,
            currentServiceTier: currentServiceTier,
            tokensByDay: tokensByDay
        )
    }

    private static func pruning(_ state: FileScanState, rangeStart: Date) -> FileScanState {
        FileScanState(
            size: state.size,
            modifiedAt: state.modifiedAt,
            scannedOffset: state.scannedOffset,
            previousTotal: state.previousTotal,
            previousInput: state.previousInput,
            previousCachedInput: state.previousCachedInput,
            previousOutput: state.previousOutput,
            currentModel: state.currentModel,
            currentServiceTier: state.currentServiceTier,
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
