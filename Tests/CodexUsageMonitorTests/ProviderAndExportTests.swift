import XCTest
@testable import CodexUsageMonitor

final class ProviderCapabilityTests: XCTestCase {
    func testCodexAndClaudeDeclareDifferentCapabilities() {
        let repository = CapabilityStubRepository()
        let codex = CodexUsageProvider(repository: repository)
        let claude = LocalClaudeUsageProvider(projectsRoot: URL(fileURLWithPath: "/tmp/missing"))

        XCTAssertTrue(codex.descriptor.capabilities.contains(.quotaWindows))
        XCTAssertTrue(codex.descriptor.capabilities.contains(.balance))
        XCTAssertEqual(claude.descriptor.capabilities, [.localTokenHistory])
        XCTAssertEqual(claude.descriptor.authenticationModes, [.localFiles])
    }

    func testClaudeReaderCountsOnlyStructuredUsageAndDeduplicatesMessageIDs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let timestamp = ISO8601DateFormatter().string(from: .now)
        let valid = """
        {"timestamp":"\(timestamp)","type":"assistant","message":{"id":"msg-1","usage":{"input_tokens":100,"output_tokens":20,"cache_creation_input_tokens":5,"cache_read_input_tokens":10},"content":"must not be read"}}
        """
        let duplicate = valid
        let unrelated = "{\"timestamp\":\"\(timestamp)\",\"message\":{\"id\":\"msg-2\",\"content\":\"usage word only\"}}"
        try Data("\(valid)\n\(duplicate)\n\(unrelated)\n".utf8)
            .write(to: root.appendingPathComponent("session.jsonl"))

        let values = LocalClaudeUsageProvider.readDailyUsage(root: root, now: .now)

        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values.first?.tokens, 135)
    }
}

@MainActor
final class UsageExportServiceTests: XCTestCase {
    func testJSONExportOmitsAccountIdentity() throws {
        let history = try UsageHistoryStore(inMemory: true)
        let snapshot = CodexUsageSnapshot(
            planName: "plus",
            primaryWindow: UsageLimitWindow(
                kind: .primary, remainingPercentage: 50, usedPercentage: 50,
                resetsAt: nil, durationDescription: nil
            ),
            accountIdentity: CodexAccountIdentity(email: "private@example.com", accountID: "secret-account"),
            sourceKind: .localCodexSession,
            sourceDisplayName: "本机 Codex 登录",
            confidence: .verified,
            fieldCompleteness: 0.5
        )
        _ = try history.saveIfNeeded(snapshot, processActive: false)

        let payload = try UsageExportService().usageJSON(current: snapshot, providers: [:], history: history)
        let exported = String(decoding: payload.document.data, as: UTF8.self)

        XCTAssertFalse(exported.contains("private@example.com"))
        XCTAssertFalse(exported.contains("secret-account"))
        XCTAssertTrue(exported.contains("schemaVersion"))
        XCTAssertTrue(exported.contains("fieldCompleteness"))
    }
}

private actor CapabilityStubRepository: CodexUsageRepository {
    func fetchQuota(forceRefresh _: Bool) async throws -> CodexUsageSnapshot { .unavailable }
    func fetchAnalytics(for snapshot: CodexUsageSnapshot, forceRefresh _: Bool) async -> CodexUsageSnapshot { snapshot }
    func currentDiagnostic() async -> DataSourceDiagnostic { DataSourceDiagnostic() }
}
