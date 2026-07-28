import Foundation

enum LocalClaudeUsageAuthorization {
    static let preferenceKey = AppPreferences.Key.localClaudeUsageEnabled
}

struct LocalClaudeUsageProvider: AIUsageProvider {
    let descriptor = AIProviderDescriptor(
        id: .claude,
        displayName: "Claude Code",
        capabilities: [.localTokenHistory],
        authenticationModes: [.localFiles]
    )

    private let projectsRoot: URL

    init(projectsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects", isDirectory: true)) {
        self.projectsRoot = projectsRoot
    }

    func availability() async -> DataSourceAvailability {
        guard UserDefaults.standard.bool(forKey: LocalClaudeUsageAuthorization.preferenceKey) else {
            return .authenticationRequired
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: projectsRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .unavailable("尚未发现本机 Claude Code 会话记录")
        }
        return .available
    }

    func fetchUsage(forceRefresh _: Bool) async throws -> AIProviderUsageSnapshot {
        guard case .available = await availability() else {
            throw UsageMonitorError.noAvailableDataSource
        }
        let root = projectsRoot
        let values = await Task.detached(priority: .utility) {
            Self.readDailyUsage(root: root, now: .now)
        }.value
        guard !values.isEmpty else { throw UsageMonitorError.noAvailableDataSource }
        let total = values.reduce(Int64(0)) { $0 + $1.tokens }
        return AIProviderUsageSnapshot(
            provider: descriptor,
            fetchedAt: .now,
            planName: nil,
            quotaWindows: [],
            balance: AIProviderBalance(remaining: nil, used: Decimal(total), unit: "Token（最近 7 天）"),
            dailyUsage: values,
            sourceDisplayName: "本机 Claude Code 用量",
            isCached: false,
            isEstimated: false
        )
    }

    static func readDailyUsage(root: URL, now: Date, calendar: Calendar = .current) -> [AIProviderDailyUsage] {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -6, to: today),
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else { return [] }

        var totals: [Date: Int64] = [:]
        var seenMessageIDs = Set<String>()
        let fractionalTimestampFormatter = ISO8601DateFormatter()
        fractionalTimestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestampFormatter = ISO8601DateFormatter()
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  modified >= start,
                  let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }
            for line in data.split(separator: 0x0A) where line.count <= 1_048_576 {
                guard line.range(of: Data("\"usage\"".utf8)) != nil,
                      let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      let message = object["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any] else { continue }
                if let identifier = message["id"] as? String, !seenMessageIDs.insert(identifier).inserted { continue }
                guard let timestamp = Self.timestamp(
                    from: object["timestamp"],
                    fractionalFormatter: fractionalTimestampFormatter,
                    standardFormatter: timestampFormatter
                ), timestamp >= start,
                      timestamp <= now.addingTimeInterval(60) else { continue }
                let tokenKeys = ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]
                let tokens = tokenKeys.reduce(Int64(0)) { partial, key in
                    partial + Self.int64(from: usage[key])
                }
                if tokens > 0 { totals[calendar.startOfDay(for: timestamp), default: 0] += tokens }
            }
        }
        return totals.keys.sorted().map { AIProviderDailyUsage(date: $0, tokens: totals[$0] ?? 0) }
    }

    private static func timestamp(
        from value: Any?,
        fractionalFormatter: ISO8601DateFormatter,
        standardFormatter: ISO8601DateFormatter
    ) -> Date? {
        if let seconds = value as? TimeInterval { return Date(timeIntervalSince1970: seconds) }
        guard let string = value as? String else { return nil }
        return fractionalFormatter.date(from: string) ?? standardFormatter.date(from: string)
    }

    private static func int64(from value: Any?) -> Int64 {
        if let value = value as? NSNumber { return max(0, value.int64Value) }
        if let value = value as? String, let parsed = Int64(value) { return max(0, parsed) }
        return 0
    }
}
