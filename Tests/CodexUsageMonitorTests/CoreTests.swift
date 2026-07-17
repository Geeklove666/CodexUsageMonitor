import XCTest
import SwiftUI
@testable import CodexUsageMonitor

final class ModelAndFormattingTests: XCTestCase {
    func testPercentageBoundariesAreClamped() {
        XCTAssertEqual(UsageLimitWindow(kind: .primary, remainingPercentage: -2, usedPercentage: 104, resetsAt: nil, durationDescription: nil).remainingPercentage, 0)
        XCTAssertEqual(UsageLimitWindow(kind: .primary, remainingPercentage: 101, usedPercentage: -1, resetsAt: nil, durationDescription: nil).remainingPercentage, 100)
    }
    func testZeroAndHundred() {
        XCTAssertEqual(UsageLimitWindow(kind: .primary, remainingPercentage: 0, usedPercentage: 100, resetsAt: nil, durationDescription: nil).remainingPercentage, 0)
        XCTAssertEqual(UsageLimitWindow(kind: .primary, remainingPercentage: 100, usedPercentage: 0, resetsAt: nil, durationDescription: nil).remainingPercentage, 100)
    }
    func testCountdownPastAndFuture() {
        XCTAssertEqual(DurationFormatter.short(-1), "已到期")
        XCTAssertEqual(DurationFormatter.short(3_720), "1h2m")
        XCTAssertEqual(DurationFormatter.compactChinese(601_200), "6天23时")
    }
    func testTokenSmallGoalFormatting() {
        XCTAssertEqual(TokenMilestoneFormatter.message(tokens: 0), "距离花掉 1 个小目标（Token）还差 100M")
        XCTAssertEqual(TokenMilestoneFormatter.message(tokens: 80_000_000), "距离花掉 1 个小目标（Token）还差 20M")
        XCTAssertEqual(TokenMilestoneFormatter.message(tokens: 100_000_000), "目前已经花掉了 1 个小目标")
        XCTAssertEqual(TokenMilestoneFormatter.message(tokens: 118_000_000), "目前已经花掉了 1.18 个小目标")
        XCTAssertEqual(TokenMilestoneFormatter.todayMessage(tokens: 18_000_000), "今天已经花掉了 0.18 个小目标")
    }
    func testSubscriptionTierFormatting() {
        XCTAssertEqual(SubscriptionTierFormatter.displayName("plus"), "$20 Plus 订阅")
        XCTAssertEqual(SubscriptionTierFormatter.displayName("Free"), "$0 Free")
        XCTAssertEqual(SubscriptionTierFormatter.displayName("go"), "$8 Go 订阅")
        XCTAssertEqual(SubscriptionTierFormatter.displayName("pro"), "$200 Pro 20x 订阅")
        XCTAssertEqual(SubscriptionTierFormatter.displayName("Pro"), "$200 Pro 20x 订阅")
        XCTAssertEqual(SubscriptionTierFormatter.displayName("pro_5x"), "$100 Pro 5x 订阅")
        XCTAssertEqual(SubscriptionTierFormatter.displayName("prolite"), "$100 Pro 5x 订阅")
        XCTAssertEqual(SubscriptionTierFormatter.displayName("pro 20x"), "$200 Pro 20x 订阅")
        XCTAssertEqual(SubscriptionTierFormatter.displayName("enterprise"), "Enterprise 订阅")
        XCTAssertEqual(SubscriptionTierFormatter.displayName(nil), "用量监控")
    }
    func testCreditsDisplayKeepsTwoFractionDigits() {
        XCTAssertEqual(CreditsDisplay.value(CreditsUsage(remaining: Decimal(string: "2474.4415625"), used: nil, currencyOrUnit: "Credits", expiresAt: nil)), "2474.44")
        XCTAssertEqual(CreditsDisplay.value(CreditsUsage(remaining: Decimal(2500), used: nil, currencyOrUnit: "Credits", expiresAt: nil)), "2500.00")
    }
}

final class MonitoringStatusTests: XCTestCase {
    func testCachedSnapshotStillReportsRefreshingWhileRequestIsRunning() {
        let cached = CodexUsageSnapshot(
            primaryWindow: UsageLimitWindow(kind: .primary, remainingPercentage: 70, usedPercentage: 30, resetsAt: nil, durationDescription: nil),
            sourceKind: .cachedSnapshot, sourceDisplayName: "cache", isCached: true,
            confidence: .medium, fieldCompleteness: 0.25
        )
        XCTAssertEqual(MonitoringStatus(snapshot: cached, lastError: nil, isRefreshing: true), .refreshing)
    }

    func testUnavailableSnapshotIsNeverReportedLive() {
        XCTAssertEqual(MonitoringStatus(snapshot: .unavailable, lastError: nil, isRefreshing: false), .needsLogin)
        XCTAssertEqual(MonitoringStatus(snapshot: .unavailable, lastError: "当前网络不可用", isRefreshing: false), .unavailable)
    }

    func testFailedRefreshWithExistingSnapshotIsDegraded() {
        let snapshot = CodexUsageSnapshot(
            primaryWindow: UsageLimitWindow(kind: .primary, remainingPercentage: 70, usedPercentage: 30, resetsAt: nil, durationDescription: nil),
            sourceKind: .officialWebPage, sourceDisplayName: "test", confidence: .high, fieldCompleteness: 0.25
        )
        XCTAssertEqual(MonitoringStatus(snapshot: snapshot, lastError: "读取超时", isRefreshing: false), .degraded)
    }
}

final class ConsumptionMilestonePolicyTests: XCTestCase {
    func testEveryTwentyPercentCreatesMilestone() {
        XCTAssertEqual(ConsumptionMilestonePolicy.step(remainingPercentage: 100), 0)
        XCTAssertEqual(ConsumptionMilestonePolicy.step(remainingPercentage: 80), 1)
        XCTAssertEqual(ConsumptionMilestonePolicy.step(remainingPercentage: 60), 2)
        XCTAssertEqual(ConsumptionMilestonePolicy.step(remainingPercentage: 40), 3)
        XCTAssertEqual(ConsumptionMilestonePolicy.step(remainingPercentage: 20), 4)
        XCTAssertEqual(ConsumptionMilestonePolicy.step(remainingPercentage: 0), 5)
    }

    func testCrossedMilestonesAreEmittedOnceInOrder() {
        XCTAssertEqual(ConsumptionMilestonePolicy.crossedMilestones(from: 0, to: 1), [20])
        XCTAssertEqual(ConsumptionMilestonePolicy.crossedMilestones(from: 1, to: 4), [40, 60, 80])
        XCTAssertEqual(ConsumptionMilestonePolicy.crossedMilestones(from: 4, to: 4), [])
        XCTAssertEqual(ConsumptionMilestonePolicy.crossedMilestones(from: 4, to: 3), [])
    }
}

final class MenuBarQuotaLevelTests: XCTestCase {
    func testFiveRemainingQuotaBands() {
        XCTAssertEqual(MenuBarQuotaLevel(remainingPercentage: 100), .healthy)
        XCTAssertEqual(MenuBarQuotaLevel(remainingPercentage: 80), .healthy)
        XCTAssertEqual(MenuBarQuotaLevel(remainingPercentage: 79.9), .good)
        XCTAssertEqual(MenuBarQuotaLevel(remainingPercentage: 60), .good)
        XCTAssertEqual(MenuBarQuotaLevel(remainingPercentage: 59.9), .moderate)
        XCTAssertEqual(MenuBarQuotaLevel(remainingPercentage: 40), .moderate)
        XCTAssertEqual(MenuBarQuotaLevel(remainingPercentage: 39.9), .low)
        XCTAssertEqual(MenuBarQuotaLevel(remainingPercentage: 20), .low)
        XCTAssertEqual(MenuBarQuotaLevel(remainingPercentage: 19.9), .critical)
        XCTAssertEqual(MenuBarQuotaLevel(remainingPercentage: 0), .critical)
    }
}

final class AutoRefreshFrequencyTests: XCTestCase {
    func testOnlySupportedRefreshIntervalsAreAccepted() {
        XCTAssertEqual(AutoRefreshFrequency.allCases.map(\.rawValue), [0, 60, 300, 600])
        XCTAssertEqual(AutoRefreshFrequency.sanitizedSeconds(0), 0)
        XCTAssertEqual(AutoRefreshFrequency.sanitizedSeconds(60), 60)
        XCTAssertEqual(AutoRefreshFrequency.sanitizedSeconds(300), 300)
        XCTAssertEqual(AutoRefreshFrequency.sanitizedSeconds(600), 600)
        XCTAssertEqual(AutoRefreshFrequency.sanitizedSeconds(30), AutoRefreshFrequency.defaultValue.rawValue)
        XCTAssertEqual(AutoRefreshFrequency.sanitizedSeconds(1_800), AutoRefreshFrequency.defaultValue.rawValue)
    }
}

final class ParserTests: XCTestCase {
    let parser = OfficialPageDOMParser()
    func testVisibleOfficialPageText() throws {
        let parsed = try parser.parse(html: "<main><h2>Usage</h2><p>72% remaining</p></main>")
        XCTAssertEqual(parsed.primaryWindow?.remainingPercentage, 72)
        XCTAssertEqual(parsed.fieldCompleteness, 0.25)
    }
    func testChineseVisibleText() throws {
        XCTAssertEqual(try parser.parse(html: "<div>额度 19% 剩余</div>").primaryWindow?.remainingPercentage, 19)
    }
    func testStructureChangeFailsClosed() {
        XCTAssertThrowsError(try parser.parse(html: "<html>Account settings</html>"))
    }
    func testOutOfRangeFailsClosed() {
        XCTAssertThrowsError(try parser.parse(html: "<p>Usage 900% remaining</p>"))
    }
    func testMissingCreditsIsPartialNotZero() throws {
        let result = try parser.parse(html: "<p>80% remaining</p>")
        XCTAssertNil(result.credits)
    }
    func testVisibleUsedPercentageIsConvertedToRemaining() throws {
        let result = try parser.parse(html: "<section>5 hour limit 23% used</section>")
        XCTAssertEqual(result.primaryWindow?.usedPercentage, 23)
        XCTAssertEqual(result.primaryWindow?.remainingPercentage, 77)
    }
    func testVisibleWeeklyWindow() throws {
        let result = try parser.parse(html: "<div>5 hour limit 20% used</div><div>Weekly limit 35% used</div>")
        XCTAssertEqual(result.primaryWindow?.remainingPercentage, 80)
        XCTAssertEqual(result.secondaryWindow?.remainingPercentage, 65)
    }
    func testVisibleResetAllowance() throws {
        let result = try parser.parse(html: "<div>额度 81% 剩余</div><div>使用限额重置 可用 3 次</div>")
        XCTAssertEqual(result.resetAllowance?.availableCount, 3)
    }
}

final class OfficialUsageAPIParserTests: XCTestCase {
    let parser = OfficialUsageAPIParser()

    func testOfficialWhamResponse() throws {
        let json = #"""
        {
          "plan_type": "plus",
          "rate_limit": {
            "primary_window": {"used_percent": 18.5, "limit_window_seconds": 18000, "reset_at": 1784100000},
            "secondary_window": {"used_percent": 42, "limit_window_seconds": 604800, "reset_at": 1784500000}
          },
          "credits": {"has_credits": true, "unlimited": false, "balance": 12.75}
        }
        """#.data(using: .utf8)!
        let result = try parser.parse(data: json)
        XCTAssertEqual(result.planName, "Plus")
        XCTAssertEqual(result.primaryWindow?.remainingPercentage, 81.5)
        XCTAssertEqual(result.primaryWindow?.durationDescription, "5 小时")
        XCTAssertEqual(result.secondaryWindow?.remainingPercentage, 58)
        XCTAssertEqual(result.secondaryWindow?.durationDescription, "1 周")
        XCTAssertEqual(result.credits?.remaining, Decimal(string: "12.75"))
        XCTAssertEqual(result.fieldCompleteness, 1, accuracy: 0.001)
    }

    func testMillisecondResetTimestamp() throws {
        let json = #"{"rate_limit":{"primary_window":{"used_percent":0,"reset_at":1784100000000}}}"#.data(using: .utf8)!
        let result = try parser.parse(data: json)
        XCTAssertEqual(result.primaryWindow?.remainingPercentage, 100)
        let timestamp = try XCTUnwrap(result.primaryWindow?.resetsAt?.timeIntervalSince1970)
        XCTAssertEqual(timestamp, 1_784_100_000, accuracy: 0.1)
    }

    func testEmptyResponseFailsClosed() {
        XCTAssertThrowsError(try parser.parse(data: Data(#"{"plan_type":"plus"}"#.utf8)))
    }

    func testResetAllowanceFromOfficialUsageResponse() throws {
        let json = #"{"rate_limit":{"primary_window":{"used_percent":19}},"rate_limit_reset_credits":{"available_count":3,"credits":[{"reset_type":"full","status":"available","expires_at":1784500000,"title":"Full reset"}]}}"#.data(using: .utf8)!
        let result = try parser.parse(data: json)
        XCTAssertEqual(result.resetAllowance?.availableCount, 3)
        XCTAssertEqual(result.resetAllowance?.credits.first?.resetType, "full")
        XCTAssertEqual(result.resetAllowance?.credits.first?.expiresAt, Date(timeIntervalSince1970: 1_784_500_000))
    }
}

final class LocalCodexSessionParserTests: XCTestCase {
    func testAppServerRateLimitsParseIntoLocalCodexSnapshot() throws {
        let reset = Int(Date.now.addingTimeInterval(3_600).timeIntervalSince1970)
        let account = """
        {"id":2,"result":{"account":{"type":"chatgpt","planType":"pro_20x"}}}
        """.data(using: .utf8)!
        let limits = """
        {"id":3,"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":\(reset)},"secondary":{"usedPercent":10,"windowDurationMins":10080,"resetsAt":\(reset)},"credits":{"balance":"2500","hasCredits":true,"unlimited":false},"planType":"pro_20x"},"rateLimitResetCredits":{"availableCount":3,"credits":[]}}}
        """.data(using: .utf8)!

        let snapshot = try CodexAppServerRateLimitParser().parse(account: account, rateLimits: limits)

        XCTAssertEqual(snapshot.sourceKind, .localCodexSession)
        XCTAssertEqual(snapshot.sourceDisplayName, "本机 Codex 登录")
        XCTAssertEqual(snapshot.planName, "pro_20x")
        XCTAssertEqual(snapshot.accountIdentity?.planName, "pro_20x")
        XCTAssertEqual(snapshot.primaryWindow?.remainingPercentage, 75)
        XCTAssertEqual(snapshot.secondaryWindow?.remainingPercentage, 90)
        XCTAssertEqual(snapshot.credits?.remaining, Decimal(2500))
        XCTAssertEqual(snapshot.resetAllowance?.availableCount, 3)
        XCTAssertEqual(LocalCodexSessionAuthorization.preferenceKey, "reuseLocalCodexLogin")
    }

    func testAppServerRateLimitsAcceptNullResetCreditList() throws {
        let reset = Int(Date.now.addingTimeInterval(3_600).timeIntervalSince1970)
        let account = """
        {"id":2,"result":{"account":{"type":"chatgpt","planType":"plus"},"requiresOpenaiAuth":true}}
        """.data(using: .utf8)!
        let limits = """
        {"id":3,"result":{"rateLimits":{"limitId":"codex","limitName":null,"primary":{"usedPercent":0,"windowDurationMins":10080,"resetsAt":\(reset)},"secondary":null,"credits":{"hasCredits":true,"unlimited":false,"balance":"2184.4377075000"},"individualLimit":null,"spendControlReached":false,"planType":"plus","rateLimitReachedType":null},"rateLimitResetCredits":{"availableCount":1,"credits":null}}}
        """.data(using: .utf8)!

        let snapshot = try CodexAppServerRateLimitParser().parse(account: account, rateLimits: limits)

        XCTAssertEqual(snapshot.planName, "plus")
        XCTAssertEqual(snapshot.primaryWindow?.remainingPercentage, 100)
        XCTAssertEqual(snapshot.secondaryWindow, nil)
        XCTAssertEqual(snapshot.credits?.remaining, Decimal(string: "2184.4377075000"))
        XCTAssertEqual(snapshot.resetAllowance?.availableCount, 1)
        XCTAssertEqual(snapshot.resetAllowance?.credits, [])
    }

    func testAppServerRateLimitsUsesLimitIdFallbackForCredits() throws {
        let reset = Int(Date.now.addingTimeInterval(3_600).timeIntervalSince1970)
        let account = """
        {"id":2,"result":{"account":{"type":"chatgpt","email":"USER@Example.COM","planType":"pro_20x","provider_account_id":"acct_123"}}}
        """.data(using: .utf8)!
        let limits = """
        {"id":3,"result":{"rateLimits":{"primary":{"usedPercent":40,"windowDurationMins":300,"resetsAt":\(reset)},"plan_type":"pro_20x"},"rate_limits_by_limit_id":{"credits":{"limit_name":"Credit balance","credits":{"hasCredits":true,"unlimited":false,"balance":"123.4567"},"individual_limit":{"limit":2500,"used":100,"remaining_percent":96,"resets_at":\(reset)}}}}}
        """.data(using: .utf8)!

        let snapshot = try CodexAppServerRateLimitParser().parse(account: account, rateLimits: limits)

        XCTAssertEqual(snapshot.accountIdentity?.email, "user@example.com")
        XCTAssertEqual(snapshot.accountIdentity?.accountID, "acct_123")
        XCTAssertEqual(snapshot.planName, "pro_20x")
        XCTAssertEqual(snapshot.credits?.remaining, Decimal(string: "123.4567"))
        XCTAssertTrue(snapshot.diagnosticMessage?.contains("子额度 1 项") == true)
        XCTAssertTrue(snapshot.diagnosticMessage?.contains("个人消费限制剩余 96%") == true)
    }

    func testAppServerRateLimitsReturnsPartialSnapshotWhenOnlyIdentityAndCreditsExist() throws {
        let account = """
        {"id":2,"result":{"account":{"type":"chatgpt","email":"user@example.com","planType":"plus"}}}
        """.data(using: .utf8)!
        let limits = """
        {"id":3,"result":{"rateLimits":{"credits":{"hasCredits":true,"unlimited":false,"balance":"50.25"},"planType":"plus"}}}
        """.data(using: .utf8)!

        let snapshot = try CodexAppServerRateLimitParser().parse(account: account, rateLimits: limits)

        XCTAssertNil(snapshot.primaryWindow)
        XCTAssertEqual(snapshot.credits?.remaining, Decimal(string: "50.25"))
        XCTAssertEqual(snapshot.accountIdentity?.email, "user@example.com")
        XCTAssertEqual(snapshot.confidence, .medium)
    }
}

final class OfficialAnalyticsParserTests: XCTestCase {
    func testCapturedAnalyticsResponsesAreAggregatedWithoutInventingData() throws {
        let json = #"""
        {
          "/backend-api/wham/analytics/daily-workspace-usage-counts": {
            "group_by": "day",
            "data": [
              {"date":"2026-07-14","totals":{"users":1,"threads":2,"turns":4,"credits":1.5,"uncached_text_input_tokens":1000,"cached_text_input_tokens":2000,"text_output_tokens":300,"text_total_tokens":3300},"clients":[{"client_id":"desktop_app","users":1,"threads":2,"turns":4,"credits":1.5,"text_total_tokens":3300}],"models":[{"model":"codex-test","users":1,"threads":2,"turns":4,"credits":1.5}]},
              {"date":"2026-07-15","totals":{"users":1,"threads":1,"turns":3,"credits":0.5,"uncached_text_input_tokens":500,"cached_text_input_tokens":0,"text_output_tokens":100,"text_total_tokens":600},"clients":[{"client_id":"desktop_app","users":1,"threads":1,"turns":3,"credits":0.5,"text_total_tokens":600}],"models":[{"model":"codex-test","users":1,"threads":1,"turns":3,"credits":0.5}]}
            ]
          },
          "/backend-api/wham/usage/daily-token-usage-breakdown": {"group_by":"day","units":"percent","data":[{"date":"2026-07-15","product_surface_usage_values":{"desktop_app":75,"cli":25},"models":[{"model":"codex-test","speed":"standard","credits":2.0}]}]},
          "/backend-api/wham/analytics/daily-skill-usage-metrics": {"group_by":"day","data":[{"date":"2026-07-14","skill_usage_overviews":[{"skill_name":"alpha","display_name":"Alpha","skill_ids":["1"],"invocation_counts":2}]},{"date":"2026-07-15","skill_usage_overviews":[{"skill_name":"alpha","display_name":"Alpha","skill_ids":["1"],"invocation_counts":3}]}]},
          "/backend-api/wham/analytics/daily-plugin-usage-metrics": {"group_by":"day","data":[{"date":"2026-07-15","plugin_usage_overviews":[{"plugin_id":"plugin-1","plugin_name":"plugin","display_name":"Plugin","invocation_counts":4}]}]},
          "/backend-api/wham/usage/credit-usage-events": {"data":[{"id":"a"},{"id":"b"}]}
        }
        """#.data(using: .utf8)!

        let result = try OfficialAnalyticsParser().parse(data: json)
        XCTAssertEqual(result.totalThreads, 3)
        XCTAssertEqual(result.totalTurns, 7)
        XCTAssertEqual(result.totalTokens, 3_900)
        XCTAssertEqual(result.uncachedInputTokens, 1_500)
        XCTAssertEqual(result.cachedInputTokens, 2_000)
        XCTAssertEqual(result.outputTokens, 400)
        XCTAssertEqual(result.activeDays, 2)
        XCTAssertEqual(result.totalCredits, 2, accuracy: 0.001)
        XCTAssertEqual(result.topSkills.first?.invocations, 5)
        XCTAssertEqual(result.topPlugins.first?.invocations, 4)
        XCTAssertEqual(result.creditEventCount, 2)
        XCTAssertEqual(result.clientBreakdown.first?.turns, 7)
        XCTAssertEqual(result.modelBreakdown.first?.threads, 3)
        XCTAssertEqual(result.productSurfaceAverages.first?.name, "desktop_app")
        XCTAssertEqual(result.modelCreditBreakdown.first?.credits, 2)
        XCTAssertTrue(result.has(.tokenUsage))
        XCTAssertEqual(result.sourceDisplayName, "官方页面分析")
    }

    func testEmptyCaptureFailsClosed() {
        XCTAssertThrowsError(try OfficialAnalyticsParser().parse(data: Data("{}".utf8)))
    }

    func testPartialSanitizedFixturePreservesUnknownSections() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "analytics-partial", withExtension: "json"))
        let result = try OfficialAnalyticsParser().parse(data: Data(contentsOf: url))
        XCTAssertTrue(result.has(.activity))
        XCTAssertTrue(result.has(.tokenUsage))
        XCTAssertFalse(result.has(.skills))
        XCTAssertFalse(result.has(.plugins))
        XCTAssertEqual(result.totalTokens, 2_300)
        XCTAssertEqual(result.totalThreads, 2)
    }
}

final class LocalRealtimeTokenUsageReaderTests: XCTestCase {
    func testOnlyTodayDeltasAreSummedWithoutReadingMessagePayloads() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func event(_ date: Date, _ total: Int64) -> String {
            #"{"timestamp":"\#(formatter.string(from: date))","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":0,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":\#(total)}}}}"#
        }
        let content = [
            #"{"timestamp":"\#(formatter.string(from: start.addingTimeInterval(-60)))","payload":{"type":"user_message","message":"must be ignored"}}"#,
            event(start.addingTimeInterval(-30), 1_000),
            event(start.addingTimeInterval(60), 1_600),
            event(start.addingTimeInterval(120), 2_000)
        ].joined(separator: "\n") + "\n"
        let file = root.appendingPathComponent("rollout-test.jsonl")
        try Data(content.utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)

        let reader = LocalRealtimeTokenUsageReader(sessionsRoot: root)
        let analytics = await reader.analyticsSnapshot(now: now, authorizationGranted: true)
        XCTAssertEqual(analytics?.todayTokens, 1_000)
        XCTAssertEqual(analytics?.sourceDisplayName, "本机 Codex 实时用量")

        let appended = event(start.addingTimeInterval(180), 2_500) + "\n"
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(appended.utf8))
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(1)], ofItemAtPath: file.path)
        let updated = await reader.analyticsSnapshot(now: now.addingTimeInterval(2), authorizationGranted: true)
        XCTAssertEqual(updated?.todayTokens, 1_500)
    }

    func testRealtimeTodayReplacesDelayedTodayButPreservesHistory() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        func snapshot(source: String, days: [(Date, Int64)]) -> CodexAnalyticsSnapshot {
            CodexAnalyticsSnapshot(
                fetchedAt: .now, sourceDisplayName: source, rangeStart: days.map(\.0).min(), rangeEnd: days.map(\.0).max(),
                groupBy: "day", dailyActivity: days.map {
                    CodexDailyActivity(date: $0.0, users: 0, threads: 0, turns: 0, credits: 0,
                        uncachedInputTokens: 0, cachedInputTokens: 0, outputTokens: 0,
                        totalTokens: $0.1, clients: [], models: [])
                }, dailyProductUsage: [], topSkills: [], topPlugins: [], creditEventCount: nil,
                availableSections: [.tokenUsage], lifetimeTokens: nil, peakDailyTokens: nil,
                currentStreakDays: nil, longestStreakDays: nil, longestRunningTurnSeconds: nil
            )
        }
        let delayed = snapshot(source: "本机 Codex 用量", days: [(yesterday, 500), (today, 100)])
        let realtime = snapshot(source: "本机 Codex 实时用量", days: [(today, 900)])
        let merged = delayed.merging(realtime)
        XCTAssertEqual(merged.tokens(on: yesterday, calendar: calendar), 500)
        XCTAssertEqual(merged.tokens(on: today, calendar: calendar), 900)
        XCTAssertEqual(merged.sourceDisplayName, "本机 Codex（实时 + 历史）")
        XCTAssertEqual(merged.compactSourceDisplayName, "本机实时")
    }
}

final class OfficialPageConfigurationTests: XCTestCase {
    @MainActor func testInjectedScriptsUseMutableBindingsForReassignedState() {
        let usage = WebViewSession.usageFetchScript
        let analytics = WebViewSession.analyticsReadScript
        XCTAssertTrue(usage.contains("var lastStatus"))
        XCTAssertFalse(usage.contains("let lastStatus"))
        XCTAssertTrue(analytics.contains("var previousCount"))
        XCTAssertTrue(analytics.contains("var stableSince"))
        XCTAssertFalse(analytics.contains("let previousCount"))
        XCTAssertFalse(analytics.contains("let stableSince"))
    }

    func testNewAnalyticsRouteIsAccepted() throws {
        let url = try XCTUnwrap(URL(string: "https://chatgpt.com/codex/settings/analytics"))
        XCTAssertTrue(OfficialPageConfiguration.isAuthenticatedChatPage(url))
    }

    func testLegacyUsageRouteIsAccepted() throws {
        let url = try XCTUnwrap(URL(string: "https://chatgpt.com/codex/settings/usage"))
        XCTAssertTrue(OfficialPageConfiguration.isAuthenticatedChatPage(url))
    }

    func testLoginAndForeignPagesAreRejected() throws {
        XCTAssertFalse(OfficialPageConfiguration.isAuthenticatedChatPage(try XCTUnwrap(URL(string: "https://chatgpt.com/auth/login"))))
        XCTAssertFalse(OfficialPageConfiguration.isAuthenticatedChatPage(try XCTUnwrap(URL(string: "https://chatgpt.com/"))))
        XCTAssertFalse(OfficialPageConfiguration.isAuthenticatedChatPage(try XCTUnwrap(URL(string: "https://chatgpt.com/codex"))))
        XCTAssertFalse(OfficialPageConfiguration.isAuthenticatedChatPage(try XCTUnwrap(URL(string: "https://example.com/codex/settings/usage"))))
    }

    func testNavigationAllowlistDoesNotAcceptArbitraryOpenAISubdomains() {
        XCTAssertTrue(OfficialPageConfiguration.isAllowedNavigationHost("auth.openai.com"))
        XCTAssertTrue(OfficialPageConfiguration.isAllowedNavigationHost("chatgpt.com"))
        XCTAssertFalse(OfficialPageConfiguration.isAllowedNavigationHost("unrelated.openai.com"))
        XCTAssertFalse(OfficialPageConfiguration.isAllowedNavigationHost("openai.com.attacker.example"))
    }
}

final class SecurityTests: XCTestCase {
    let redactor = SensitiveDataRedactor()
    func testAuthorizationRedaction() { XCTAssertFalse(redactor.redact("Authorization: Bearer secret123").contains("secret123")) }
    func testCookieRedaction() { XCTAssertFalse(redactor.redact("Cookie: session=very-secret").contains("very-secret")) }
    func testAccessTokenRedaction() { XCTAssertFalse(redactor.redact("access_token=abc123").contains("abc123")) }
    func testEmailRedaction() { XCTAssertFalse(redactor.redact("hello user@example.com").contains("user@example.com")) }
    func testQueryTokenRedaction() { XCTAssertFalse(redactor.redact("https://x.test/?token=abc123&x=1").contains("abc123")) }
}

final class ResetDetectionTests: XCTestCase {
    func snapshot(_ value: Double, reset: Date? = nil, time: Date) -> CodexUsageSnapshot {
        CodexUsageSnapshot(fetchedAt: time, primaryWindow: UsageLimitWindow(kind: .primary, remainingPercentage: value, usedPercentage: 100-value, resetsAt: reset, durationDescription: nil), sourceKind: .officialWebPage, sourceDisplayName: "test", confidence: .high, fieldCompleteness: 0.5)
    }
    func testResetDetected() {
        let now = Date.now
        XCTAssertTrue(ResetDetectionService().isReset(old: snapshot(10, reset: now, time: now), new: snapshot(90, reset: now.addingTimeInterval(3600), time: now.addingTimeInterval(1))))
    }
    func testSmallFluctuationIsNotReset() {
        let now = Date.now
        XCTAssertFalse(ResetDetectionService().isReset(old: snapshot(18, time: now), new: snapshot(21, time: now.addingTimeInterval(1))))
    }
}

@MainActor
final class UsageHistoryTests: XCTestCase {
    func testSecondaryWindowChangeIsPersisted() throws {
        let store = try UsageHistoryStore(inMemory: true)
        let first = historySnapshot(primary: 80, secondary: 70)
        let second = historySnapshot(primary: 80, secondary: 60)
        XCTAssertTrue(try store.saveIfNeeded(first, processActive: true))
        XCTAssertTrue(try store.saveIfNeeded(second, processActive: true))
        XCTAssertEqual(try store.points(since: .distantPast).count, 2)
    }

    func testPersistedSnapshotRestoresCacheAfterRelaunch() async throws {
        let store = try UsageHistoryStore(inMemory: true)
        let snapshot = historySnapshot(primary: 63, secondary: 41)
        XCTAssertTrue(try store.saveIfNeeded(snapshot, processActive: false))
        let restored = try store.recentSnapshots()
        XCTAssertEqual(restored.last?.primaryWindow?.remainingPercentage, 63)
        XCTAssertEqual(restored.last?.secondaryWindow?.remainingPercentage, 41)

        let cache = CachedSnapshotDataSource(snapshot: restored.last)
        let cached = try await cache.fetchUsage()
        XCTAssertTrue(cached.isCached)
        XCTAssertEqual(cached.primaryWindow?.remainingPercentage, 63)
    }

    func testAnalyticsIsRestoredWithCachedSnapshot() throws {
        let store = try UsageHistoryStore(inMemory: true)
        let fixtureURL = try XCTUnwrap(Bundle.module.url(forResource: "analytics-partial", withExtension: "json"))
        let analytics = try OfficialAnalyticsParser().parse(data: Data(contentsOf: fixtureURL))
        let base = historySnapshot(primary: 63, secondary: 41)
        let snapshot = CodexUsageSnapshot(
            id: base.id, fetchedAt: base.fetchedAt, sourceUpdatedAt: base.sourceUpdatedAt,
            planName: base.planName, primaryWindow: base.primaryWindow, secondaryWindow: base.secondaryWindow,
            credits: base.credits, analytics: analytics, sourceKind: base.sourceKind,
            sourceDisplayName: base.sourceDisplayName, confidence: base.confidence,
            fieldCompleteness: base.fieldCompleteness
        )
        XCTAssertTrue(try store.saveIfNeeded(snapshot, processActive: false))
        let restored = try XCTUnwrap(store.recentSnapshots().last?.analytics)
        XCTAssertEqual(restored.totalTokens, analytics.totalTokens)
        XCTAssertEqual(restored.availableSections, analytics.availableSections)
    }

    func testResetAllowanceIsRestoredWithCachedSnapshot() async throws {
        let store = try UsageHistoryStore(inMemory: true)
        let base = historySnapshot(primary: 63, secondary: 41)
        let expiration = Date.now.addingTimeInterval(86_400)
        let snapshot = CodexUsageSnapshot(
            id: base.id, fetchedAt: base.fetchedAt, sourceUpdatedAt: base.sourceUpdatedAt,
            planName: base.planName, primaryWindow: base.primaryWindow, secondaryWindow: base.secondaryWindow,
            credits: base.credits,
            resetAllowance: UsageResetAllowance(availableCount: 3, credits: [
                UsageResetCredit(resetType: "full", status: "available", grantedAt: nil,
                                 expiresAt: expiration, title: "Full reset")
            ]),
            sourceKind: base.sourceKind, sourceDisplayName: base.sourceDisplayName,
            confidence: base.confidence, fieldCompleteness: base.fieldCompleteness
        )
        XCTAssertTrue(try store.saveIfNeeded(snapshot, processActive: false))
        let restored = try XCTUnwrap(store.recentSnapshots().last)
        XCTAssertEqual(restored.resetAllowance?.availableCount, 3)
        XCTAssertEqual(restored.resetAllowance?.credits.first?.expiresAt, expiration)
        let cached = try await CachedSnapshotDataSource(snapshot: restored).fetchUsage()
        XCTAssertEqual(cached.resetAllowance?.availableCount, 3)
    }

    func testRestoredHistoryEnablesLocalEstimate() async throws {
        let now = Date.now
        let first = CodexUsageSnapshot(
            fetchedAt: now.addingTimeInterval(-600),
            primaryWindow: UsageLimitWindow(kind: .primary, remainingPercentage: 80, usedPercentage: 20, resetsAt: now.addingTimeInterval(3600), durationDescription: "5 小时"),
            sourceKind: .officialWebPage, sourceDisplayName: "test", confidence: .high, fieldCompleteness: 0.25
        )
        let second = CodexUsageSnapshot(
            fetchedAt: now.addingTimeInterval(-300),
            primaryWindow: UsageLimitWindow(kind: .primary, remainingPercentage: 70, usedPercentage: 30, resetsAt: now.addingTimeInterval(3600), durationDescription: "5 小时"),
            sourceKind: .officialWebPage, sourceDisplayName: "test", confidence: .high, fieldCompleteness: 0.25
        )
        let estimate = LocalEstimateDataSource(history: [first, second])
        let availability = await estimate.availability()
        XCTAssertEqual(availability, .available)
        let value = try await estimate.fetchUsage()
        XCTAssertTrue(value.isEstimated)
        XCTAssertNotNil(value.primaryWindow?.remainingPercentage)
    }

    private func historySnapshot(primary: Double, secondary: Double) -> CodexUsageSnapshot {
        CodexUsageSnapshot(
            primaryWindow: UsageLimitWindow(kind: .primary, remainingPercentage: primary, usedPercentage: 100 - primary,
                                            resetsAt: nil, durationDescription: "5 小时"),
            secondaryWindow: UsageLimitWindow(kind: .secondary, remainingPercentage: secondary, usedPercentage: 100 - secondary,
                                              resetsAt: nil, durationDescription: "1 周"),
            sourceKind: .officialWebPage,
            sourceDisplayName: "test",
            confidence: .high,
            fieldCompleteness: 0.65
        )
    }
}

actor StubDataSource: CodexUsageDataSource {
    let identifier: String
    let displayName: String
    let sourceKind: UsageSourceKind
    let state: DataSourceAvailability
    let result: Result<CodexUsageSnapshot, Error>
    init(_ id: String, kind: UsageSourceKind, state: DataSourceAvailability = .available, result: Result<CodexUsageSnapshot, Error>) {
        identifier = id; displayName = id; sourceKind = kind; self.state = state; self.result = result
    }
    func availability() async -> DataSourceAvailability { state }
    func fetchUsage() async throws -> CodexUsageSnapshot { try result.get() }
}

actor StubAnalyticsDataSource: CodexAnalyticsDataSource {
    let analyticsIdentifier = "analytics-stub"
    let state: DataSourceAvailability
    let result: Result<CodexAnalyticsSnapshot, Error>
    init(state: DataSourceAvailability = .available, result: Result<CodexAnalyticsSnapshot, Error>) {
        self.state = state; self.result = result
    }
    func analyticsAvailability() async -> DataSourceAvailability { state }
    func fetchAnalytics() async throws -> CodexAnalyticsSnapshot { try result.get() }
}

actor CountingAnalyticsDataSource: CodexAnalyticsDataSource {
    let analyticsIdentifier = "analytics-counting"
    private(set) var fetchCount = 0
    let result: CodexAnalyticsSnapshot

    init(result: CodexAnalyticsSnapshot) { self.result = result }
    func analyticsAvailability() async -> DataSourceAvailability { .available }
    func fetchAnalytics() async throws -> CodexAnalyticsSnapshot {
        fetchCount += 1
        return result
    }
}

actor CacheInvalidatingStubDataSource: CodexUsageDataSource, RefreshCacheInvalidatingDataSource {
    let identifier: String
    let displayName: String
    let sourceKind: UsageSourceKind
    let result: Result<CodexUsageSnapshot, Error>
    private(set) var invalidationCount = 0

    init(_ id: String, kind: UsageSourceKind, result: Result<CodexUsageSnapshot, Error>) {
        identifier = id
        displayName = id
        sourceKind = kind
        self.result = result
    }

    func availability() async -> DataSourceAvailability { .available }
    func fetchUsage() async throws -> CodexUsageSnapshot { try result.get() }
    func invalidateRefreshCaches() async { invalidationCount += 1 }
}

actor DelayedDataSource: CodexUsageDataSource {
    let identifier = "delayed"
    let displayName = "delayed"
    let sourceKind = UsageSourceKind.verifiedOfficial
    func availability() async -> DataSourceAvailability { .available }
    func fetchUsage() async throws -> CodexUsageSnapshot {
        try await Task.sleep(for: .seconds(5))
        throw UsageMonitorError.noAvailableDataSource
    }
}

final class RepositoryTests: XCTestCase {
    func value(_ kind: UsageSourceKind = .officialWebPage) -> CodexUsageSnapshot {
        CodexUsageSnapshot(primaryWindow: UsageLimitWindow(kind: .primary, remainingPercentage: 42, usedPercentage: 58, resetsAt: nil, durationDescription: nil), sourceKind: kind, sourceDisplayName: "test", confidence: .high, fieldCompleteness: 0.25)
    }
    func testOfficialSuccess() async throws {
        let result = value(.verifiedOfficial)
        let repository = DefaultCodexUsageRepository(
            official: StubDataSource("official", kind: .verifiedOfficial, result: .success(result)),
            web: StubDataSource("web", kind: .officialWebPage, result: .failure(UsageMonitorError.parsingFailed)),
            cache: CachedSnapshotDataSource(), estimate: LocalEstimateDataSource())
        let kind = try await repository.fetch().sourceKind
        XCTAssertEqual(kind, .verifiedOfficial)
    }
    func testOfficialUnavailableFallsBackToWeb() async throws {
        let repository = DefaultCodexUsageRepository(
            official: StubDataSource("official", kind: .verifiedOfficial, state: .unavailable("no"), result: .failure(UsageMonitorError.noAvailableDataSource)),
            web: StubDataSource("web", kind: .officialWebPage, result: .success(value())),
            cache: CachedSnapshotDataSource(), estimate: LocalEstimateDataSource())
        let kind = try await repository.fetch().sourceKind
        XCTAssertEqual(kind, .officialWebPage)
    }
    func testFailureFallsBackToCache() async throws {
        let cache = CachedSnapshotDataSource()
        await cache.update(value())
        let repository = DefaultCodexUsageRepository(
            official: StubDataSource("official", kind: .verifiedOfficial, state: .unavailable("no"), result: .failure(UsageMonitorError.noAvailableDataSource)),
            web: StubDataSource("web", kind: .officialWebPage, result: .failure(UsageMonitorError.parsingFailed)),
            cache: cache, estimate: LocalEstimateDataSource())
        let kind = try await repository.fetch().sourceKind
        XCTAssertEqual(kind, .cachedSnapshot)
        let diagnostic = await repository.currentDiagnostic()
        XCTAssertEqual(diagnostic.lastFailure, UsageMonitorError.parsingFailed.localizedDescription)
    }
    func testAllSourcesFail() async {
        let failed = StubDataSource("x", kind: .verifiedOfficial, state: .unavailable("no"), result: .failure(UsageMonitorError.noAvailableDataSource))
        let repository = DefaultCodexUsageRepository(official: failed, web: failed, cache: CachedSnapshotDataSource(), estimate: LocalEstimateDataSource())
        do { _ = try await repository.fetch(); XCTFail("Expected failure") } catch { XCTAssertNotNil(error as? UsageMonitorError) }
    }

    func testOfficialWebQuotaIsMergedWithIndependentWebAnalytics() async throws {
        let analyticsData = try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "analytics-partial", withExtension: "json")))
        let analytics = try OfficialAnalyticsParser().parse(data: analyticsData)
        let unavailable = StubDataSource("unavailable", kind: .verifiedOfficial, state: .unavailable("no"), result: .failure(UsageMonitorError.noAvailableDataSource))
        let repository = DefaultCodexUsageRepository(
            official: unavailable,
            web: StubDataSource("web", kind: .officialWebPage, result: .success(value(.officialWebPage))),
            analytics: StubAnalyticsDataSource(result: .success(analytics)),
            cache: CachedSnapshotDataSource(), estimate: LocalEstimateDataSource()
        )
        let merged = try await repository.fetch()
        XCTAssertEqual(merged.sourceKind, .officialWebPage)
        XCTAssertEqual(merged.analytics?.totalTokens, 2_300)
    }

    func testQuotaFetchDoesNotWaitForOrStartAnalytics() async throws {
        let analytics = CodexAnalyticsSnapshot(
            fetchedAt: .now, sourceDisplayName: "analytics", rangeStart: nil, rangeEnd: nil,
            groupBy: "day", dailyActivity: [], dailyProductUsage: [], topSkills: [], topPlugins: [],
            creditEventCount: nil, availableSections: [], lifetimeTokens: nil, peakDailyTokens: nil,
            currentStreakDays: nil, longestStreakDays: nil, longestRunningTurnSeconds: nil
        )
        let counter = CountingAnalyticsDataSource(result: analytics)
        let unavailable = StubDataSource(
            "unavailable", kind: .officialWebPage, state: .unavailable("no"),
            result: .failure(UsageMonitorError.noAvailableDataSource)
        )
        let repository = DefaultCodexUsageRepository(
            official: StubDataSource("official", kind: .verifiedOfficial, result: .success(value(.verifiedOfficial))),
            web: unavailable, analytics: counter,
            cache: CachedSnapshotDataSource(), estimate: LocalEstimateDataSource()
        )

        let quota = try await repository.fetchQuota()
        XCTAssertEqual(quota.primaryWindow?.remainingPercentage, 42)
        let countAfterQuota = await counter.fetchCount
        XCTAssertEqual(countAfterQuota, 0)

        _ = await repository.fetchAnalytics(for: quota)
        let countAfterAnalytics = await counter.fetchCount
        XCTAssertEqual(countAfterAnalytics, 1)
    }

    func testManualQuotaFetchInvalidatesRefreshCaches() async throws {
        let local = CacheInvalidatingStubDataSource(
            "local", kind: .localCodexSession, result: .success(value(.localCodexSession))
        )
        let unavailable = StubDataSource(
            "unavailable", kind: .verifiedOfficial, state: .unavailable("no"),
            result: .failure(UsageMonitorError.noAvailableDataSource)
        )
        let repository = DefaultCodexUsageRepository(
            official: unavailable, localCodex: local,
            web: unavailable, cache: CachedSnapshotDataSource(), estimate: LocalEstimateDataSource()
        )

        _ = try await repository.fetchQuota(forceRefresh: true)

        let invalidationCount = await local.invalidationCount
        XCTAssertEqual(invalidationCount, 1)
    }

    func testAutomaticQuotaFetchDoesNotInvalidateRefreshCaches() async throws {
        let local = CacheInvalidatingStubDataSource(
            "local", kind: .localCodexSession, result: .success(value(.localCodexSession))
        )
        let unavailable = StubDataSource(
            "unavailable", kind: .verifiedOfficial, state: .unavailable("no"),
            result: .failure(UsageMonitorError.noAvailableDataSource)
        )
        let repository = DefaultCodexUsageRepository(
            official: unavailable, localCodex: local,
            web: unavailable, cache: CachedSnapshotDataSource(), estimate: LocalEstimateDataSource()
        )

        _ = try await repository.fetchQuota(forceRefresh: false)

        let invalidationCount = await local.invalidationCount
        XCTAssertEqual(invalidationCount, 0)
    }

    func testRequestTimeoutIsBoundedAndReported() async {
        let unavailable = StubDataSource("unavailable", kind: .officialWebPage, state: .unavailable("no"), result: .failure(UsageMonitorError.noAvailableDataSource))
        let repository = DefaultCodexUsageRepository(
            official: DelayedDataSource(), web: unavailable,
            cache: CachedSnapshotDataSource(), estimate: LocalEstimateDataSource(),
            requestTimeout: .milliseconds(20)
        )
        do {
            _ = try await repository.fetch()
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? UsageMonitorError, .requestTimedOut)
        }
    }
}

@MainActor
final class NativeUISnapshotSmokeTests: XCTestCase {
    func testButtonPressFeedbackChangesOnlyLocalAppearance() {
        let idle = StableButtonPressFeedback(isPressed: false)
        let pressed = StableButtonPressFeedback(isPressed: true)

        XCTAssertLessThan(pressed.contentOpacity, idle.contentOpacity)
        XCTAssertGreaterThan(pressed.fillOpacity, idle.fillOpacity)
    }

    func testDesignSystemDoesNotApplyScaleEffects() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("CodexUsageMonitor/Shared/Components/AppleDesignSystem.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains(".scaleEffect("))
    }

    func testDashboardFollowsDesignChecklistStructure() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("CodexUsageMonitor/Features/Dashboard/DashboardView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        for destination in ["概览", "使用历史", "告警", "数据来源", "设置"] {
            XCTAssertTrue(source.contains(destination), "Missing dashboard destination: \(destination)")
        }
        for state in ["live", "loading", "cached", "estimated", "offline", "unavailable", "exhausted"] {
            XCTAssertTrue(source.contains("case \(state)"), "Missing dashboard state: \(state)")
        }
        for plan in ["$0/月", "$8/月", "$20/月", "$100/月", "$200/月"] {
            XCTAssertTrue(source.contains(plan), "Missing US pricing baseline: \(plan)")
        }
        XCTAssertTrue(source.contains("自动刷新频率"))
        XCTAssertTrue(source.contains("AutoRefreshFrequency.allCases"))
        XCTAssertTrue(source.contains("真实刷新诊断"))
        XCTAssertTrue(source.contains("DemoQuotaSnapshot.make(snapshot: monitor.snapshot"))
        XCTAssertFalse(source.contains("Picker(\"Demo 状态\""))
        XCTAssertFalse(source.contains("Demo 界面壳"))
        XCTAssertFalse(source.contains("Demo 数值"))
        XCTAssertFalse(source.contains(".glassEffect("), "Dashboard content must not apply glassEffect directly.")
    }

    func testEnabledLocalCodexMenuActionDoesNotStartLoginFlow() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("CodexUsageMonitor/Features/MenuBar/MenuBarViews.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("localCodexLogin ? \"刷新本机 Codex\" : \"启用本机 Codex\""))
        XCTAssertFalse(source.contains("try? await LocalCodexLoginProbe().startLogin()"))
    }

    func testMenuBarTitleUsesSystemLabelColor() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("CodexUsageMonitor/Features/MenuBar/MenuBarController.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains(".foregroundColor: NSColor.labelColor"))
        XCTAssertFalse(source.contains("MenuBarQuotaLevel(remainingPercentage: $0).color"))
        XCTAssertFalse(source.contains("NSColor(labelColor:"))
    }

    func testCompactUsageSummaryRendersAtMenuWidth() throws {
        let snapshot = CodexUsageSnapshot(
            primaryWindow: UsageLimitWindow(kind: .primary, remainingPercentage: 64, usedPercentage: 36, resetsAt: .now.addingTimeInterval(3600), durationDescription: "5 小时"),
            secondaryWindow: UsageLimitWindow(kind: .secondary, remainingPercentage: 82, usedPercentage: 18, resetsAt: .now.addingTimeInterval(7200), durationDescription: "1 周"),
            resetAllowance: UsageResetAllowance(availableCount: 3),
            sourceKind: .officialWebPage, sourceDisplayName: "test", confidence: .high, fieldCompleteness: 0.75
        )
        let renderer = ImageRenderer(content: CompactUsageSummary(snapshot: snapshot, now: .now).frame(width: 354))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertGreaterThan(image.width, 350)
        XCTAssertGreaterThan(image.height, 100)
    }


    func testHeroCardRendersAtSupportedDashboardWidths() throws {
        let snapshot = CodexUsageSnapshot(
            primaryWindow: UsageLimitWindow(kind: .primary, remainingPercentage: 64, usedPercentage: 36, resetsAt: .now.addingTimeInterval(3600), durationDescription: "5 小时"),
            sourceKind: .officialWebPage, sourceDisplayName: "test", confidence: .high, fieldCompleteness: 0.25
        )
        for width in [672.0, 812.0, 1052.0] {
            let renderer = ImageRenderer(content: UsageHeroCard(snapshot: snapshot, now: .now).frame(width: width))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.cgImage)
            XCTAssertEqual(image.width, Int(width))
            XCTAssertGreaterThan(image.height, 160)
        }
    }

    func testCompactAnalyticsKeepsStableHeightWhileSourceSwitches() throws {
        let fixtureURL = try XCTUnwrap(Bundle.module.url(forResource: "analytics-partial", withExtension: "json"))
        let analytics = try OfficialAnalyticsParser().parse(data: Data(contentsOf: fixtureURL))
        let emptyRenderer = ImageRenderer(content: CompactAnalyticsSummary(analytics: nil).frame(width: 354))
        let loadedRenderer = ImageRenderer(content: CompactAnalyticsSummary(analytics: analytics).frame(width: 354))
        emptyRenderer.scale = 1
        loadedRenderer.scale = 1
        let emptyImage = try XCTUnwrap(emptyRenderer.cgImage)
        let loadedImage = try XCTUnwrap(loadedRenderer.cgImage)
        XCTAssertEqual(emptyImage.height, loadedImage.height)
        XCTAssertGreaterThan(emptyImage.height, 60)
    }
}
