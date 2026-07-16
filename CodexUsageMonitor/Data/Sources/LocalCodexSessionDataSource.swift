import Darwin
import Foundation
import Security

enum LocalCodexSessionAuthorization {
    static let preferenceKey = "experimentalReuseLocalCodexLogin"
    static let allowCustomExecutableKey = "allowCustomCodexExecutable"
}

enum LocalCodexSessionError: LocalizedError, Sendable {
    case executableMissing
    case notAuthorized
    case notChatGPTLogin
    case invalidResponse
    case serverFailure
    case protocolFailure(String)

    var errorDescription: String? {
        switch self {
        case .executableMissing: "未找到本机 Codex 命令"
        case .notAuthorized: "尚未授权复用本机 Codex 登录"
        case .notChatGPTLogin: "本机 Codex 当前不是 ChatGPT 登录"
        case .invalidResponse: "本机 Codex 返回了无法识别的额度数据"
        case .serverFailure: "本机 Codex 数据服务暂时不可用"
        case .protocolFailure(let message): "本机 Codex 协议错误：\(message)"
        }
    }
}

struct CodexExecutableLocator: Sendable {
    func locate() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let trustedCandidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "\(home)/Applications/ChatGPT.app/Contents/Resources/codex",
            "\(home)/Applications/Codex.app/Contents/Resources/codex"
        ]

        if let trusted = trustedCandidates.lazy
            .map({ URL(fileURLWithPath: $0).standardizedFileURL })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) && isTrustedOpenAIExecutable($0) }) {
            return trusted
        }

        // PATH and environment overrides are intentionally opt-in because executing
        // an arbitrary binary after login reuse consent would otherwise permit PATH hijacking.
        guard UserDefaults.standard.bool(forKey: LocalCodexSessionAuthorization.allowCustomExecutableKey) else {
            return nil
        }
        var candidates = [environment["CODEX_CLI_PATH"], "\(home)/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
            .compactMap { $0 }

        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/codex" })
        }

        return candidates.lazy
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func isTrustedOpenAIExecutable(_ executable: URL) -> Bool {
        guard let appRange = executable.path.range(of: ".app/Contents/", options: .backwards) else { return false }
        let appPath = String(executable.path[..<appRange.lowerBound]) + ".app"
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: appPath) as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return false }
        var requirement: SecRequirement?
        let expression = #"anchor apple generic and certificate leaf[subject.OU] = "2DC432GLL2""#
        guard SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        return SecStaticCodeCheckValidity(staticCode, [], requirement) == errSecSuccess
    }
}

struct LocalCodexSessionDataSource: CodexUsageDataSource, CodexAnalyticsDataSource {
    let identifier = "local-codex-session"
    let analyticsIdentifier = "local-codex-account-usage"
    let displayName = "本机 Codex 登录（实验性）"
    let sourceKind = UsageSourceKind.localCodexSession
    let parserVersion: String? = "Codex app-server v2 rate-limits"
    let analyticsParserVersion: String? = "Codex app-server v2 account-usage"
    let locator: CodexExecutableLocator
    let parser: CodexAppServerRateLimitParser
    let usageParser: CodexAppServerAccountUsageParser
    let realtimeTokenReader: LocalRealtimeTokenUsageReader
    let accountUsageCache: LocalAccountUsageCache

    init(locator: CodexExecutableLocator = CodexExecutableLocator(),
         parser: CodexAppServerRateLimitParser = CodexAppServerRateLimitParser(),
         usageParser: CodexAppServerAccountUsageParser = CodexAppServerAccountUsageParser(),
         realtimeTokenReader: LocalRealtimeTokenUsageReader = LocalRealtimeTokenUsageReader(),
         accountUsageCache: LocalAccountUsageCache = LocalAccountUsageCache()) {
        self.locator = locator
        self.parser = parser
        self.usageParser = usageParser
        self.realtimeTokenReader = realtimeTokenReader
        self.accountUsageCache = accountUsageCache
    }

    func availability() async -> DataSourceAvailability {
        guard UserDefaults.standard.bool(forKey: LocalCodexSessionAuthorization.preferenceKey) else {
            return .unavailable("需要用户主动授权")
        }
        guard locator.locate() != nil else { return .unavailable("未找到本机 Codex 命令") }
        return .available
    }

    func fetchUsage() async throws -> CodexUsageSnapshot {
        guard UserDefaults.standard.bool(forKey: LocalCodexSessionAuthorization.preferenceKey) else {
            throw LocalCodexSessionError.notAuthorized
        }
        guard let executable = locator.locate() else { throw LocalCodexSessionError.executableMissing }
        let responses = try await CodexAppServerClient(executable: executable).readAccountAndRateLimits()
        let quota = try parser.parse(account: responses.account, rateLimits: responses.rateLimits)
        guard let analytics = await realtimeTokenReader.analyticsSnapshot() else { return quota }
        return CodexUsageSnapshot(
            id: quota.id, fetchedAt: quota.fetchedAt, sourceUpdatedAt: quota.sourceUpdatedAt,
            planName: quota.planName, primaryWindow: quota.primaryWindow, secondaryWindow: quota.secondaryWindow,
            credits: quota.credits, resetAllowance: quota.resetAllowance, analytics: analytics, sourceKind: quota.sourceKind,
            sourceDisplayName: quota.sourceDisplayName, isEstimated: quota.isEstimated, isCached: quota.isCached,
            confidence: quota.confidence, fieldCompleteness: quota.fieldCompleteness,
            expiresAt: quota.expiresAt, diagnosticMessage: quota.diagnosticMessage
        )
    }

    func analyticsAvailability() async -> DataSourceAvailability { await availability() }

    func fetchAnalytics() async throws -> CodexAnalyticsSnapshot {
        guard UserDefaults.standard.bool(forKey: LocalCodexSessionAuthorization.preferenceKey) else {
            throw LocalCodexSessionError.notAuthorized
        }
        if let cached = await accountUsageCache.freshValue() {
            return try usageParser.parse(response: cached)
        }
        guard let executable = locator.locate() else { throw LocalCodexSessionError.executableMissing }
        let response = try await CodexAppServerClient(executable: executable).readAccountUsage()
        await accountUsageCache.store(response)
        return try usageParser.parse(response: response)
    }
}

actor LocalAccountUsageCache {
    private var value: Data?
    private var fetchedAt: Date?
    private let lifetime: TimeInterval = 900

    func freshValue(now: Date = .now) -> Data? {
        guard let value, let fetchedAt, now.timeIntervalSince(fetchedAt) < lifetime else { return nil }
        return value
    }

    func store(_ value: Data, now: Date = .now) {
        self.value = value
        fetchedAt = now
    }
}

struct CodexAppServerResponses: Sendable {
    let account: Data
    let rateLimits: Data
}

struct CodexAppServerClient: Sendable {
    let executable: URL

    func readAccountAndRateLimits() async throws -> CodexAppServerResponses {
        let output: Data
        do {
            output = try await runAccountAndRateLimits(refreshToken: false)
        } catch LocalCodexSessionError.protocolFailure(let message)
                    where Self.isAuthenticationFailure(message) {
            output = try await runAccountAndRateLimits(refreshToken: true)
        }

        var account: Data?
        var rateLimits: Data?
        for line in output.split(separator: 0x0A) where !line.isEmpty {
            let data = Data(line)
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = (object["id"] as? NSNumber)?.intValue else { continue }
            if let error = object["error"] as? [String: Any] {
                throw LocalCodexSessionError.protocolFailure(
                    SensitiveDataRedactor().redact(error["message"] as? String ?? "未知服务错误")
                )
            }
            if id == 2 { account = data }
            if id == 3 { rateLimits = data }
        }

        guard let account, let rateLimits else { throw LocalCodexSessionError.invalidResponse }
        return CodexAppServerResponses(account: account, rateLimits: rateLimits)
    }

    private func runAccountAndRateLimits(refreshToken: Bool) async throws -> Data {
        let runner = CodexAppServerProcess(executable: executable)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        continuation.resume(returning: try runner.run(refreshToken: refreshToken))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            runner.stop()
        }
    }

    private static func isAuthenticationFailure(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("auth") || normalized.contains("token")
            || normalized.contains("unauthorized") || normalized.contains("登录")
    }

    func readAccountUsage() async throws -> Data {
        let runner = CodexAppServerProcess(executable: executable)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do { continuation.resume(returning: try runner.runAccountUsage()) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: {
            runner.stop()
        }
    }
}

private final class CodexAppServerProcess: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errorOutput = Pipe()
    private let lock = NSLock()
    private var stopped = false
    private var readBuffer = Data()
    private var stderrBuffer = Data()

    init(executable: URL) {
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errorOutput
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        errorOutput.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            self.lock.lock()
            if self.stderrBuffer.count < 16_384 { self.stderrBuffer.append(data.prefix(16_384 - self.stderrBuffer.count)) }
            self.lock.unlock()
        }
    }

    func run(refreshToken: Bool) throws -> Data {
        try start()
        defer { finish() }
        try send("{\"method\":\"account/read\",\"id\":2,\"params\":{\"refreshToken\":\(refreshToken)}}")
        try send(#"{"method":"account/rateLimits/read","id":3}"#)
        let responses = try readResponses(ids: [2, 3])
        guard let account = responses[2], let rateLimits = responses[3] else {
            throw LocalCodexSessionError.invalidResponse
        }
        let data = account + Data([0x0A]) + rateLimits + Data([0x0A])
        try checkCancellation()
        return data
    }

    func runAccountUsage() throws -> Data {
        try start()
        defer { finish() }
        // A proactive refresh is required on some persisted ChatGPT sessions;
        // without it account/usage/read can time out even though account/read succeeds.
        try send(#"{"method":"account/read","id":2,"params":{"refreshToken":true}}"#)
        _ = try readResponse(id: 2)
        try send(#"{"method":"account/usage/read","id":4}"#)
        let usage = try readResponse(id: 4)
        try checkCancellation()
        return usage
    }

    private func start() throws {
        lock.lock()
        let wasStopped = stopped
        lock.unlock()
        guard !wasStopped else { throw CancellationError() }

        try process.run()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let initialize = #"{"method":"initialize","id":1,"params":{"clientInfo":{"name":"codex_usage_monitor","title":"Codex Usage Monitor","version":"__VERSION__"},"capabilities":{"experimentalApi":true}}}"#
            .replacingOccurrences(of: "__VERSION__", with: version)
        try send(initialize)
        _ = try readResponse(id: 1)
        try send(#"{"method":"initialized"}"#)
    }

    private func finish() {
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        let deadline = Date.now.addingTimeInterval(1)
        while process.isRunning, Date.now < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning { process.interrupt() }
        errorOutput.fileHandleForReading.readabilityHandler = nil
    }

    private func checkCancellation() throws {
        lock.lock()
        let wasCancelled = stopped
        lock.unlock()
        if wasCancelled { throw CancellationError() }
    }

    private func send(_ message: String) throws {
        guard let data = (message + "\n").data(using: .utf8) else {
            throw LocalCodexSessionError.invalidResponse
        }
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    private func readResponse(id expectedID: Int) throws -> Data {
        for _ in 0..<100 {
            let line = try readLine()
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = (object["id"] as? NSNumber)?.intValue,
                  id == expectedID else { continue }
            if let error = object["error"] as? [String: Any] {
                let message = SensitiveDataRedactor().redact(error["message"] as? String ?? "未知服务错误")
                throw LocalCodexSessionError.protocolFailure(message)
            }
            return line
        }
        throw LocalCodexSessionError.invalidResponse
    }

    private func readResponses(ids expectedIDs: Set<Int>) throws -> [Int: Data] {
        var responses: [Int: Data] = [:]
        for _ in 0..<200 where responses.count < expectedIDs.count {
            let line = try readLine()
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = (object["id"] as? NSNumber)?.intValue,
                  expectedIDs.contains(id) else { continue }
            if let error = object["error"] as? [String: Any] {
                let message = SensitiveDataRedactor().redact(error["message"] as? String ?? "未知服务错误")
                throw LocalCodexSessionError.protocolFailure(message)
            }
            responses[id] = line
        }
        guard responses.count == expectedIDs.count else { throw LocalCodexSessionError.invalidResponse }
        return responses
    }

    private func readLine() throws -> Data {
        while readBuffer.count < 1_048_576 {
            if let newline = readBuffer.firstIndex(of: 0x0A) {
                let line = Data(readBuffer[..<newline])
                readBuffer.removeSubrange(...newline)
                return line
            }
            try checkCancellation()
            let descriptor = output.fileHandleForReading.fileDescriptor
            var pollState = pollfd(fd: descriptor, events: Int16(POLLIN | POLLHUP | POLLERR), revents: 0)
            let pollResult = Darwin.poll(&pollState, 1, 250)
            if pollResult < 0 {
                if errno == EINTR { continue }
                throw processFailure()
            }
            if pollResult == 0 { continue }

            var bytes = [UInt8](repeating: 0, count: 4096)
            let count = Darwin.read(descriptor, &bytes, bytes.count)
            if count < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                throw processFailure()
            }
            guard count > 0 else { throw processFailure() }
            readBuffer.append(contentsOf: bytes.prefix(count))
        }
        throw LocalCodexSessionError.invalidResponse
    }

    private func processFailure() -> LocalCodexSessionError {
        lock.lock()
        let captured = stderrBuffer
        lock.unlock()
        guard let message = String(data: captured, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else { return .serverFailure }
        return .protocolFailure(SensitiveDataRedactor().redact(String(message.prefix(500))))
    }

    func stop() {
        lock.lock()
        stopped = true
        let shouldTerminate = process.isRunning
        lock.unlock()
        if shouldTerminate { process.terminate() }
        try? input.fileHandleForWriting.close()
        try? output.fileHandleForReading.close()
    }
}

struct CodexAppServerRateLimitParser: Sendable {
    func parse(account accountData: Data, rateLimits rateLimitsData: Data, now: Date = .now) throws -> CodexUsageSnapshot {
        let decoder = JSONDecoder()
        let accountResponse = try decoder.decode(AccountResponse.self, from: accountData)
        guard let account = accountResponse.result?.account else { throw LocalCodexSessionError.notChatGPTLogin }
        guard account.type == "chatgpt" || account.type == "personalAccessToken" else {
            throw LocalCodexSessionError.notChatGPTLogin
        }

        let limitsResponse = try decoder.decode(RateLimitsResponse.self, from: rateLimitsData)
        guard let limits = limitsResponse.result?.rateLimits,
              let primary = makeWindow(limits.primary, kind: .primary) else {
            throw LocalCodexSessionError.invalidResponse
        }
        let secondary = makeWindow(limits.secondary, kind: .secondary)
        let credits = makeCredits(limits.credits)
        let resetAllowance = makeResetAllowance(limitsResponse.result?.rateLimitResetCredits)
        let planName = account.planType ?? limits.planType
        let completeness = min(1, 0.25 + (secondary == nil ? 0 : 0.2) + (planName == nil ? 0 : 0.2)
            + (credits == nil ? 0 : 0.15) + (resetAllowance == nil ? 0 : 0.1))
        let details = [limits.limitName, limits.rateLimitReachedType,
                       limits.individualLimit.map { "个人消费限制剩余 \($0.remainingPercent)%" },
                       resetAllowance.map { "使用限额重置可用 \($0.availableCount) 次" }]
            .compactMap { $0 }.joined(separator: " · ")

        return CodexUsageSnapshot(
            fetchedAt: now,
            planName: planName,
            primaryWindow: primary,
            secondaryWindow: secondary,
            credits: credits,
            resetAllowance: resetAllowance,
            sourceKind: .localCodexSession,
            sourceDisplayName: "本机 Codex app-server（实验性）",
            confidence: .verified,
            fieldCompleteness: completeness,
            expiresAt: now.addingTimeInterval(300),
            diagnosticMessage: details.isEmpty ? "经用户授权复用本机 Codex 登录；应用未读取或保存 Token" : details
        )
    }

    private func makeCredits(_ value: CreditsSnapshot?) -> CreditsUsage? {
        guard let value, value.hasCredits || value.unlimited || value.balance != nil else { return nil }
        let balance = value.balance.flatMap { Decimal(string: $0) }
        return CreditsUsage(remaining: balance, used: nil, currencyOrUnit: value.unlimited ? "无限" : "Credits", expiresAt: nil)
    }

    private func makeResetAllowance(_ value: ResetCreditsSnapshot?) -> UsageResetAllowance? {
        guard let value else { return nil }
        let credits = value.credits.map {
            UsageResetCredit(
                resetType: $0.resetType,
                status: $0.status,
                grantedAt: $0.grantedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                expiresAt: $0.expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                title: $0.title
            )
        }
        return UsageResetAllowance(availableCount: value.availableCount, credits: credits)
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
}

private struct LocalCodexAccount: Decodable {
    let type: String
    let planType: String?
}

private struct RateLimitsResponse: Decodable {
    let result: RateLimitsResult?
}

private struct RateLimitsResult: Decodable {
    let rateLimits: RateLimitsValue?
    let rateLimitResetCredits: ResetCreditsSnapshot?
}

private struct ResetCreditsSnapshot: Decodable {
    let availableCount: Int
    let credits: [ResetCreditSnapshot]
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
}

private struct CreditsSnapshot: Decodable {
    let balance: String?
    let hasCredits: Bool
    let unlimited: Bool
}

private struct SpendControlLimitSnapshot: Decodable {
    let limit: String
    let remainingPercent: Int
    let resetsAt: Int64
    let used: String
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
