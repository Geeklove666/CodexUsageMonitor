import XCTest
@testable import CodexUsageMonitor

final class LeaderboardTests: XCTestCase {
    func testUploadIncludesOnlyDatesAndEffectiveTokenCounts() throws {
        let now = Date(timeIntervalSince1970: 1_792_915_200)
        let analytics = snapshot(now:now, date:now, tokens:1200, cached:400)
        let upload = try XCTUnwrap(LeaderboardUpload.make(analytics:analytics,now:now))
        XCTAssertEqual(upload.days.first?.tokens,800)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(upload)) as? [String:Any])
        XCTAssertEqual(Set(object.keys),Set(["source","days"]))
        XCTAssertEqual(object["source"] as? String,"codex-local-effective-v1")
        let day = try XCTUnwrap((object["days"] as? [[String:Any]])?.first)
        XCTAssertEqual(Set(day.keys),Set(["date","tokens"]))
    }

    func testShanghaiBucketsUseCorrectMidnightAcrossUTCDates() throws {
        let formatter = ISO8601DateFormatter()
        let now = try XCTUnwrap(formatter.date(from:"2026-10-30T18:00:00Z"))
        let earlier = try XCTUnwrap(formatter.date(from:"2026-10-30T15:59:59Z"))
        let later = try XCTUnwrap(formatter.date(from:"2026-10-30T16:00:00Z"))
        XCTAssertNotEqual(LeaderboardConfiguration.calendar.startOfDay(for:earlier),LeaderboardConfiguration.calendar.startOfDay(for:later))
        let upload = try XCTUnwrap(LeaderboardUpload.make(analytics:snapshot(now:now,date:later,tokens:100,cached:0),now:now))
        XCTAssertEqual(upload.days.first?.date,"2026-10-31")
    }

    func testMissingTokenRecordDoesNotUploadFabricatedZero() {
        let now = Date.now
        var analytics = snapshot(now:now,date:now,tokens:0,cached:0)
        analytics.tokenRecordedDates = []
        XCTAssertNil(LeaderboardUpload.make(analytics:analytics,now:now))
    }

    func testRealZeroIsPreservedButOldAndFutureDaysAreExcluded() throws {
        let now = Date.now
        let zero = try XCTUnwrap(LeaderboardUpload.make(analytics:snapshot(now:now,date:now,tokens:0,cached:0),now:now))
        XCTAssertEqual(zero.days.first?.tokens,0)
        XCTAssertNil(LeaderboardUpload.make(analytics:snapshot(now:now,date:now.addingTimeInterval(-10*86400),tokens:1,cached:0),now:now))
        XCTAssertNil(LeaderboardUpload.make(analytics:snapshot(now:now,date:now.addingTimeInterval(2*86400),tokens:1,cached:0),now:now))
    }

    func testLocalScannerCanBucketEventsInShanghaiIndependentlyOfSystemTimezone() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from:"2026-10-30T18:00:00Z"))
        let lines = """
        {"timestamp":"2026-10-30T15:59:59Z","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":100,"cached_input_tokens":20}}}}
        {"timestamp":"2026-10-30T16:00:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":160,"cached_input_tokens":30}}}}
        """
        try Data((lines+"\n").utf8).write(to:root.appendingPathComponent("rollout-fixture.jsonl"))
        let reader = LocalRealtimeTokenUsageReader(sessionsRoot:root,calendar:LeaderboardConfiguration.calendar)
        let value = await reader.analyticsSnapshot(now:now,authorizationGranted:true)
        let analytics = try XCTUnwrap(value)
        let upload = try XCTUnwrap(LeaderboardUpload.make(analytics:analytics,now:now))
        XCTAssertEqual(upload.days.map(\.date),["2026-10-30","2026-10-31"])
        XCTAssertEqual(upload.days.map(\.tokens),[80,50])
    }

    private func snapshot(now:Date,date:Date,tokens:Int64,cached:Int64) -> CodexAnalyticsSnapshot {
        let day = LeaderboardConfiguration.calendar.startOfDay(for:date)
        return CodexAnalyticsSnapshot(fetchedAt:now,sourceDisplayName:"本机测试",rangeStart:day,rangeEnd:day,groupBy:"day",
            dailyActivity:[CodexDailyActivity(date:day,users:1,threads:0,turns:0,credits:0,uncachedInputTokens:tokens-cached,cachedInputTokens:cached,outputTokens:0,totalTokens:tokens,clients:[],models:[])],
            dailyProductUsage:[],topSkills:[],topPlugins:[],creditEventCount:nil,availableSections:[.tokenUsage],lifetimeTokens:nil,peakDailyTokens:nil,currentStreakDays:nil,longestStreakDays:nil,longestRunningTurnSeconds:nil)
    }
}
