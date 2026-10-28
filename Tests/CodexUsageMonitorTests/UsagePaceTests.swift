import XCTest
@testable import CodexUsageMonitor

final class UsagePaceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)
    private let identity = CodexAccountIdentity(accountID: "fixture-account")

    func testWarnsWhenRateWouldExhaustBeforeReset() throws {
        let snapshot = snapshot(remaining: 20, resetIn: 4 * 3600)
        let projection = try XCTUnwrap(assess(snapshot, startingAt: 30).projection)
        XCTAssertEqual(projection.percentagePointsPerHour, 10, accuracy: 0.001)
        XCTAssertEqual(projection.projectedExhaustionAt, now.addingTimeInterval(2 * 3600))
        XCTAssertEqual(projection.projectedRemainingAtReset, 0)
        XCTAssertEqual(projection.sustainablePercentagePointsPerHour, 5, accuracy: 0.001)
        XCTAssertTrue(projection.runsOutBeforeReset)
    }

    func testProjectsRemainingAtResetWhenPaceIsSustainable() throws {
        let projection = try XCTUnwrap(assess(snapshot(remaining: 60, resetIn: 2 * 3600), startingAt: 70).projection)
        XCTAssertEqual(projection.projectedRemainingAtReset, 40, accuracy: 0.001)
        XCTAssertFalse(projection.runsOutBeforeReset)
        XCTAssertEqual(projection.projectionEnd, projection.resetsAt)
    }

    func testExhaustionExactlyAtResetIsNotAnEarlyExhaustion() throws {
        let projection = try XCTUnwrap(assess(snapshot(remaining: 20, resetIn: 2 * 3600), startingAt: 30).projection)
        XCTAssertFalse(projection.runsOutBeforeReset)
        XCTAssertEqual(projection.projectedExhaustionAt, projection.resetsAt)
    }

    func testRequiresThirtyMinutesAndMeasurableConsumption() {
        let current = snapshot(remaining: 20)
        let short = sample(at: now.addingTimeInterval(-29 * 60), remaining: 30, reset: current.primaryWindow?.resetsAt)
        XCTAssertNil(UsagePaceBuilder.assess(snapshot: current, samples: [short], now: now).projection)
        XCTAssertNil(assess(current, startingAt: 20).projection)
        XCTAssertNil(assess(current, startingAt: 20.5).projection)
        XCTAssertNotNil(assess(current, startingAt: 21).projection)
    }

    func testRejectsCachedEstimatedStaleFutureExpiredAndUnavailableSnapshots() {
        let invalid = [
            snapshot(remaining: 20, cached: true),
            snapshot(remaining: 20, estimated: true),
            snapshot(remaining: 20, fetchedAt: now.addingTimeInterval(-901)),
            snapshot(remaining: 20, fetchedAt: now.addingTimeInterval(1)),
            snapshot(remaining: 20, expiresAt: now),
            snapshot(remaining: 20, source: .unavailable),
            snapshot(remaining: 20, source: .cachedSnapshot),
            snapshot(remaining: 20, source: .localEstimate)
        ]
        for current in invalid {
            XCTAssertNil(assess(current, startingAt: 30).projection)
        }
    }

    func testRejectsMissingElapsedResetAndExhaustedQuota() {
        XCTAssertNil(assess(snapshot(remaining: 20, resetIn: nil), startingAt: 30).projection)
        XCTAssertNil(assess(snapshot(remaining: 20, resetIn: 0), startingAt: 30).projection)
        XCTAssertNil(assess(snapshot(remaining: 0), startingAt: 30).projection)
    }

    func testRejectsOldSourceTimestampDespiteRecentFetch() {
        let current = snapshot(remaining: 20, sourceUpdatedAt: now.addingTimeInterval(-1800))
        XCTAssertNil(assess(current, startingAt: 30).projection)
    }

    func testClockDoesNotPushPredictedExhaustionIntoTheFuture() throws {
        let current = snapshot(remaining: 20, resetIn: 4 * 3600)
        let samples = [sample(at: now.addingTimeInterval(-3600), remaining: 30, reset: current.primaryWindow?.resetsAt)]
        let initial = try XCTUnwrap(UsagePaceBuilder.assess(snapshot: current, samples: samples, now: now).projection)
        let later = try XCTUnwrap(UsagePaceBuilder.assess(snapshot: current, samples: samples, now: now.addingTimeInterval(300)).projection)
        XCTAssertEqual(initial.projectedExhaustionAt, later.projectedExhaustionAt)
        XCTAssertEqual(initial.projectedRemainingAtReset, later.projectedRemainingAtReset)
    }

    func testResetBoundaryDoesNotRequireLargeRecovery() {
        let current = snapshot(remaining: 20)
        let oldCycle = sample(at: now.addingTimeInterval(-3600), remaining: 30,
                              reset: now.addingTimeInterval(1800))
        XCTAssertNil(UsagePaceBuilder.assess(snapshot: current, samples: [oldCycle], now: now).projection)
        XCTAssertNil(UsageTrendBuilder.makeVelocity(from: [oldCycle, sample(at: now, remaining: 20,
            reset: current.primaryWindow?.resetsAt)], now: now))
    }

    func testRecoveryWithoutChangedResetStartsNewObservation() {
        let current = snapshot(remaining: 50)
        let samples = [
            sample(at: now.addingTimeInterval(-3600), remaining: 80, reset: current.primaryWindow?.resetsAt),
            sample(at: now.addingTimeInterval(-600), remaining: 20, reset: current.primaryWindow?.resetsAt)
        ]
        XCTAssertNil(UsagePaceBuilder.assess(snapshot: current, samples: samples, now: now).projection)
    }

    func testAccountSourceAndPlanChangesStartNewObservations() {
        let current = snapshot(remaining: 20)
        let reset = current.primaryWindow?.resetsAt
        let changed = [
            sample(at: now.addingTimeInterval(-3600), remaining: 30, reset: reset,
                   identity: CodexAccountIdentity(accountID: "another-fixture-account")),
            sample(at: now.addingTimeInterval(-3600), remaining: 30, reset: reset, source: .officialWebPage),
            sample(at: now.addingTimeInterval(-3600), remaining: 30, reset: reset, plan: "pro")
        ]
        for previous in changed {
            XCTAssertNil(UsagePaceBuilder.assess(snapshot: current, samples: [previous], now: now).projection)
        }
    }

    func testLongGapStartsNewObservation() {
        let current = snapshot(remaining: 20)
        let previous = sample(at: now.addingTimeInterval(-7201), remaining: 80, reset: current.primaryWindow?.resetsAt)
        XCTAssertNil(UsagePaceBuilder.assess(snapshot: current, samples: [previous], now: now).projection)
    }

    func testCachedFutureAndDuplicateCurrentSamplesCannotDistortProjection() throws {
        let current = snapshot(remaining: 20)
        let reset = current.primaryWindow?.resetsAt
        let samples = [
            sample(at: now.addingTimeInterval(-3600), remaining: 30, reset: reset),
            sample(at: now.addingTimeInterval(-1800), remaining: 99, reset: reset, cached: true),
            sample(at: now.addingTimeInterval(60), remaining: 1, reset: reset),
            sample(id: current.id, at: now, remaining: 20, reset: reset)
        ]
        let projection = try XCTUnwrap(UsagePaceBuilder.assess(snapshot: current, samples: samples, now: now).projection)
        XCTAssertEqual(projection.percentagePointsPerHour, 10, accuracy: 0.001)
        XCTAssertEqual(projection.samples.count, 2)
    }

    func testStopsShowingProjectionAfterPredictedExhaustionPasses() {
        let current = snapshot(remaining: 1)
        // 99 percentage points in 30 minutes predicts exhaustion in about 18 seconds.
        let samples = [sample(at: now.addingTimeInterval(-1800), remaining: 100, reset: current.primaryWindow?.resetsAt)]
        XCTAssertNil(UsagePaceBuilder.assess(snapshot: current, samples: samples, now: now.addingTimeInterval(60)).projection)
    }

    func testVelocityRejectsStaleAndFutureData() {
        let reset = now.addingTimeInterval(3600)
        let stale = [sample(at: now.addingTimeInterval(-7200), remaining: 50, reset: reset),
                     sample(at: now.addingTimeInterval(-3600), remaining: 40, reset: reset)]
        XCTAssertNil(UsageTrendBuilder.makeVelocity(from: stale, now: now))
        let future = [sample(at: now, remaining: 50, reset: reset),
                      sample(at: now.addingTimeInterval(3600), remaining: 40, reset: reset)]
        XCTAssertNil(UsageTrendBuilder.makeVelocity(from: future, now: now))
    }

    func testObservationNeverUsesMoreThanTheLastTwentyFourHours() throws {
        let current = snapshot(remaining: 20)
        let samples = (1...30).map { hours in
            sample(at: now.addingTimeInterval(-Double(hours) * 3600), remaining: 20 + Double(hours),
                   reset: current.primaryWindow?.resetsAt)
        }
        let projection = try XCTUnwrap(UsagePaceBuilder.assess(snapshot: current, samples: samples, now: now).projection)
        XCTAssertEqual(projection.observationHours, 24)
        XCTAssertEqual(projection.percentagePointsPerHour, 1, accuracy: 0.001)
        XCTAssertEqual(projection.samples.count, 25)
    }

    private func assess(_ current: CodexUsageSnapshot, startingAt remaining: Double) -> UsagePaceAssessment {
        UsagePaceBuilder.assess(snapshot: current, samples: [sample(
            at: current.fetchedAt.addingTimeInterval(-3600), remaining: remaining,
            reset: current.primaryWindow?.resetsAt
        )], now: now)
    }

    private func sample(id: UUID = UUID(), at date: Date, remaining: Double, reset: Date?,
                        cached: Bool = false, identity: CodexAccountIdentity? = nil,
                        source: UsageSourceKind = .localCodexSession, plan: String = "plus") -> UsageHistorySample {
        UsageHistorySample(id: id, recordedAt: date, remainingPercentage: remaining, resetsAt: reset,
                           isCached: cached, accountIdentity: identity ?? self.identity, sourceKind: source, planName: plan)
    }

    private func snapshot(remaining: Double, resetIn: TimeInterval? = 3600,
                          cached: Bool = false, estimated: Bool = false,
                          fetchedAt: Date? = nil, sourceUpdatedAt: Date? = nil, expiresAt: Date? = nil,
                          source: UsageSourceKind = .localCodexSession) -> CodexUsageSnapshot {
        CodexUsageSnapshot(
            fetchedAt: fetchedAt ?? now, sourceUpdatedAt: sourceUpdatedAt, planName: "plus",
            primaryWindow: UsageLimitWindow(kind: .primary, remainingPercentage: remaining,
                usedPercentage: 100 - remaining, resetsAt: resetIn.map { now.addingTimeInterval($0) }, durationDescription: nil),
            accountIdentity: identity, sourceKind: source, sourceDisplayName: "测试来源",
            isEstimated: estimated, isCached: cached, confidence: .high, fieldCompleteness: 1, expiresAt: expiresAt
        )
    }
}

@MainActor
final class DashboardPaceHistoryTests: XCTestCase {
    func testVelocityAndPaceSamplesDoNotDependOnChartRange() throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let reset = now.addingTimeInterval(3600)
        let store = PaceHistoryStub(samples: [
            UsageHistorySample(recordedAt: now.addingTimeInterval(-3600), remainingPercentage: 50, resetsAt: reset, isCached: false),
            UsageHistorySample(recordedAt: now, remainingPercentage: 40, resetsAt: reset, isCached: false)
        ])
        let model = DashboardHistoryModel(history: store)
        model.load(range: .day, now: now)
        let velocity = try XCTUnwrap(model.velocity)
        let paceSamples = model.paceSamples
        for range in UsageHistoryRange.allCases {
            model.load(range: range, now: now)
            XCTAssertEqual(model.velocity, velocity)
            XCTAssertEqual(model.paceSamples, paceSamples)
        }
    }

    func testHistoryFailureClearsPriorPaceSamples() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let reset = now.addingTimeInterval(3600)
        let store = PaceHistoryStub(samples: [
            UsageHistorySample(recordedAt: now.addingTimeInterval(-3600), remainingPercentage: 50, resetsAt: reset, isCached: false),
            UsageHistorySample(recordedAt: now, remainingPercentage: 40, resetsAt: reset, isCached: false)
        ])
        let model = DashboardHistoryModel(history: store)
        model.load(range: .day, now: now)
        XCTAssertFalse(model.paceSamples.isEmpty)
        XCTAssertNotNil(model.velocity)
        store.shouldFail = true
        model.load(range: .day, now: now)
        XCTAssertTrue(model.paceSamples.isEmpty)
        XCTAssertNil(model.velocity)
        XCTAssertNotNil(model.errorMessage)
    }
}

@MainActor
private final class PaceHistoryStub: UsageHistoryReading {
    let samples: [UsageHistorySample]
    var shouldFail = false
    init(samples: [UsageHistorySample]) { self.samples = samples }
    func usageSamples(since date: Date) throws -> [UsageHistorySample] {
        if shouldFail { throw URLError(.cannotOpenFile) }
        return samples.filter { $0.recordedAt >= date }
    }
    func creditBalanceSamples(since _: Date) throws -> [CreditBalanceSample] { [] }
}
