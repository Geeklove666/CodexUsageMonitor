import Darwin
import Foundation
import Security

enum LocalCodexSessionAuthorization {
    static let preferenceKey = AppPreferences.Key.reuseLocalCodexLogin
    static let allowCustomExecutableKey = AppPreferences.Key.allowCustomCodexExecutable
}

enum LocalCodexLoginStatus: Equatable, Sendable {
    case loggedIn(String)
    case loggedOut(String)
    case unavailable(String)

    var label: String {
        switch self {
        case .loggedIn(let detail): "已登录 · \(detail)"
        case .loggedOut(let detail): "未登录 · \(detail)"
        case .unavailable(let detail): "不可用 · \(detail)"
        }
    }
}

enum LocalCodexSessionError: LocalizedError, Equatable, Sendable {
    case executableMissing
    case notAuthorized
    case notChatGPTLogin
    case openAIAuthRequired
    case invalidResponse
    case serverFailure
    case protocolFailure(String)

    var errorDescription: String? {
        switch self {
        case .executableMissing: "未找到本机 Codex 命令"
        case .notAuthorized: "尚未授权使用本机 Codex 登录"
        case .notChatGPTLogin: "本机 Codex 当前不是 ChatGPT 登录"
        case .openAIAuthRequired: "本机 Codex 尚未登录 ChatGPT，请点击 Codex 登录完成授权后再刷新"
        case .invalidResponse: "本机 Codex 返回了无法识别的额度数据"
        case .serverFailure: "本机 Codex 数据服务暂时不可用"
        case .protocolFailure(let message): "本机 Codex 协议错误：\(message)"
        }
    }
}

extension LocalCodexSessionError: UsageFailureClassifying {
    var usageFailureKind: UsageFailureKind {
        switch self {
        case .notAuthorized, .notChatGPTLogin, .openAIAuthRequired: .authentication
        case .invalidResponse, .protocolFailure: .parsing
        case .executableMissing, .serverFailure: .unavailable
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

struct LocalCodexLoginProbe: Sendable {
    let locator: CodexExecutableLocator

    init(locator: CodexExecutableLocator = CodexExecutableLocator()) {
        self.locator = locator
    }

    func status() async -> LocalCodexLoginStatus {
        guard let executable = locator.locate() else {
            return .unavailable("未找到 OpenAI 签名的本机 Codex 命令")
        }
        do {
            let result = try await run(executable: executable, arguments: ["login", "status"], waitsForExit: true)
            let output = SensitiveDataRedactor().redact(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
            guard result.exitCode == 0 else { return .loggedOut(output.isEmpty ? "需要运行 codex login" : output) }
            return output.localizedCaseInsensitiveContains("logged in")
                ? .loggedIn(output.replacingOccurrences(of: "Logged in using ", with: ""))
                : .loggedOut(output.isEmpty ? "需要运行 codex login" : output)
        } catch {
            return .unavailable(SensitiveDataRedactor().redact(error.localizedDescription))
        }
    }

    func startLogin() async throws {
        guard let executable = locator.locate() else { throw LocalCodexSessionError.executableMissing }
        _ = try await run(executable: executable, arguments: ["login"], waitsForExit: false)
    }

    private func run(executable: URL, arguments: [String], waitsForExit: Bool) async throws -> (output: String, exitCode: Int32) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let output = Pipe()
                process.executableURL = executable
                process.arguments = arguments
                process.standardOutput = output
                process.standardError = output
                process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
                do {
                    try process.run()
                    if waitsForExit {
                        process.waitUntilExit()
                        let data = output.fileHandleForReading.readDataToEndOfFile()
                        continuation.resume(returning: (String(data: data, encoding: .utf8) ?? "", process.terminationStatus))
                    } else {
                        continuation.resume(returning: ("", 0))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

struct LocalCodexSessionDataSource: CodexUsageDataSource, CodexAnalyticsDataSource, RefreshCacheInvalidatingDataSource {
    let identifier = "local-codex-session"
    let analyticsIdentifier = "local-codex-account-usage"
    let displayName = "本机 Codex 登录"
    let sourceKind = UsageSourceKind.localCodexSession
    let parserVersion: String? = "Codex app-server v2 rate-limits"
    let analyticsParserVersion: String? = "Codex app-server v2 account-usage"
    let locator: CodexExecutableLocator
    let parser: CodexAppServerRateLimitParser
    let usageParser: CodexAppServerAccountUsageParser
    let accountUsageCache: LocalAccountUsageCache
    let quotaCache: LocalQuotaSnapshotCache
    let loginStatusCache: LocalCodexLoginStatusCache

    init(locator: CodexExecutableLocator = CodexExecutableLocator(),
         parser: CodexAppServerRateLimitParser = CodexAppServerRateLimitParser(),
         usageParser: CodexAppServerAccountUsageParser = CodexAppServerAccountUsageParser(),
         accountUsageCache: LocalAccountUsageCache = LocalAccountUsageCache(),
         quotaCache: LocalQuotaSnapshotCache = LocalQuotaSnapshotCache(),
         loginStatusCache: LocalCodexLoginStatusCache = LocalCodexLoginStatusCache()) {
        self.locator = locator
        self.parser = parser
        self.usageParser = usageParser
        self.accountUsageCache = accountUsageCache
        self.quotaCache = quotaCache
        self.loginStatusCache = loginStatusCache
    }

    func availability() async -> DataSourceAvailability {
        guard UserDefaults.standard.bool(forKey: LocalCodexSessionAuthorization.preferenceKey) else {
            return .unavailable("需要用户主动授权")
        }
        guard locator.locate() != nil else { return .unavailable("未找到本机 Codex 命令") }
        let status: LocalCodexLoginStatus
        if let cached = await loginStatusCache.freshValue() {
            status = cached
        } else {
            status = await LocalCodexLoginProbe(locator: locator).status()
            await loginStatusCache.store(status)
        }
        guard case .loggedIn = status else {
            return .authenticationRequired
        }
        return .available
    }

    func fetchUsage() async throws -> CodexUsageSnapshot {
        guard UserDefaults.standard.bool(forKey: LocalCodexSessionAuthorization.preferenceKey) else {
            throw LocalCodexSessionError.notAuthorized
        }
        if let cached = await quotaCache.freshValue() { return cached }
        guard let executable = locator.locate() else { throw LocalCodexSessionError.executableMissing }
        let client = CodexAppServerClient(executable: executable)
        let responses = try await LocalCodexQuotaRetryPolicy.run {
            try await client.readAccountAndRateLimits()
        }
        let quota: CodexUsageSnapshot
        do {
            quota = try parser.parse(account: responses.account, rateLimits: responses.rateLimits)
        } catch is DecodingError {
            throw LocalCodexSessionError.invalidResponse
        }
        await quotaCache.store(quota)
        return quota
    }

    func analyticsAvailability() async -> DataSourceAvailability { await availability() }

    func fetchAnalytics() async throws -> CodexAnalyticsSnapshot {
        guard UserDefaults.standard.bool(forKey: LocalCodexSessionAuthorization.preferenceKey) else {
            throw LocalCodexSessionError.notAuthorized
        }
        if let cached = await accountUsageCache.freshValue() {
            do {
                return try usageParser.parse(response: cached)
            } catch is DecodingError {
                throw LocalCodexSessionError.invalidResponse
            }
        }
        guard let executable = locator.locate() else { throw LocalCodexSessionError.executableMissing }
        let response = try await CodexAppServerClient(executable: executable).readAccountUsage()
        await accountUsageCache.store(response)
        do {
            return try usageParser.parse(response: response)
        } catch is DecodingError {
            throw LocalCodexSessionError.invalidResponse
        }
    }

    func invalidateRefreshCaches() async {
        await quotaCache.clear()
        await accountUsageCache.clear()
        await loginStatusCache.clear()
    }
}

enum LocalCodexQuotaRetryPolicy {
    static func run<T: Sendable>(_ operation: () async throws -> T) async throws -> T {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                return try await operation()
            } catch {
                lastError = error
                guard attempt < 2, shouldRetry(error) else { throw error }
                try await Task.sleep(for: .milliseconds(Int.random(in: 800...1_600) * (attempt + 1)))
            }
        }
        throw lastError ?? LocalCodexSessionError.serverFailure
    }

    static func shouldRetry(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if case LocalCodexSessionError.serverFailure = error { return true }
        guard case LocalCodexSessionError.protocolFailure(let message) = error else { return false }
        let normalized = message.lowercased()
        return ["overloaded", "temporarily", "unavailable", "timeout", "timed out",
                "connection reset", "connection refused", "broken pipe", "服务暂时",
                "failed to fetch codex rate", "rate limit reset"]
            .contains { normalized.contains($0) }
    }
}

actor LocalQuotaSnapshotCache {
    private var value: CodexUsageSnapshot?
    private var storedAt: Date?
    private let lifetime: TimeInterval

    init(lifetime: TimeInterval = AppConfiguration.Refresh.localQuotaCacheLifetime) { self.lifetime = lifetime }

    func freshValue(now: Date = .now) -> CodexUsageSnapshot? {
        guard let value, let storedAt, now.timeIntervalSince(storedAt) < lifetime else { return nil }
        return value
    }

    func store(_ value: CodexUsageSnapshot, now: Date = .now) {
        self.value = value
        storedAt = now
    }

    func clear() {
        value = nil
        storedAt = nil
    }
}

actor LocalAccountUsageCache {
    private var value: Data?
    private var fetchedAt: Date?
    private let lifetime: TimeInterval = AppConfiguration.Refresh.localAnalyticsCacheLifetime

    func freshValue(now: Date = .now) -> Data? {
        guard let value, let fetchedAt, now.timeIntervalSince(fetchedAt) < lifetime else { return nil }
        return value
    }

    func store(_ value: Data, now: Date = .now) {
        self.value = value
        fetchedAt = now
    }

    func clear() {
        value = nil
        fetchedAt = nil
    }
}

actor LocalCodexLoginStatusCache {
    private var value: LocalCodexLoginStatus?
    private var checkedAt: Date?
    private let lifetime: TimeInterval

    init(lifetime: TimeInterval = AppConfiguration.Refresh.localLoginStatusCacheLifetime) {
        self.lifetime = lifetime
    }

    func freshValue(now: Date = .now) -> LocalCodexLoginStatus? {
        guard let value, let checkedAt, now.timeIntervalSince(checkedAt) < lifetime else { return nil }
        return value
    }

    func store(_ value: LocalCodexLoginStatus, now: Date = .now) {
        self.value = value
        checkedAt = now
    }

    func clear() {
        value = nil
        checkedAt = nil
    }
}
