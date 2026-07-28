import Foundation
import SwiftData

enum UsageHistoryStoreError: LocalizedError {
    case unavailable

    var errorDescription: String? { "历史存储当前不可用" }
}

extension UsageHistoryStoreError: UsageFailureClassifying {
    var usageFailureKind: UsageFailureKind { .persistence }
}

@Model
final class UsageSnapshotEntity {
    @Attribute(.unique) var id: UUID
    var fetchedAt: Date
    var sourceUpdatedAt: Date?
    var planName: String?
    var primaryRemaining: Double?
    var primaryReset: Date?
    var primaryDuration: String?
    var secondaryRemaining: Double?
    var secondaryReset: Date?
    var secondaryDuration: String?
    var creditsRemaining: Decimal?
    var creditsUnit: String?
    var resetAllowanceData: Data?
    var analyticsData: Data?
    var accountIdentityData: Data?
    var sourceKindRaw: String
    var isEstimated: Bool
    var isCached: Bool
    var confidenceRaw: String
    var fieldCompleteness: Double
    var processActive: Bool

    init(snapshot: CodexUsageSnapshot, processActive: Bool) {
        id = snapshot.id; fetchedAt = snapshot.fetchedAt; sourceUpdatedAt = snapshot.sourceUpdatedAt; planName = snapshot.planName
        primaryRemaining = snapshot.primaryWindow?.remainingPercentage; primaryReset = snapshot.primaryWindow?.resetsAt
        primaryDuration = snapshot.primaryWindow?.durationDescription
        secondaryRemaining = snapshot.secondaryWindow?.remainingPercentage; secondaryReset = snapshot.secondaryWindow?.resetsAt
        secondaryDuration = snapshot.secondaryWindow?.durationDescription
        creditsRemaining = snapshot.credits?.remaining; creditsUnit = snapshot.credits?.currencyOrUnit
        resetAllowanceData = snapshot.resetAllowance.flatMap { try? JSONEncoder().encode($0) }
        analyticsData = snapshot.analytics.flatMap { try? JSONEncoder().encode($0) }
        accountIdentityData = snapshot.accountIdentity.flatMap { try? JSONEncoder().encode($0) }
        sourceKindRaw = snapshot.sourceKind.rawValue
        isEstimated = snapshot.isEstimated; isCached = snapshot.isCached; confidenceRaw = snapshot.confidence.rawValue
        fieldCompleteness = snapshot.fieldCompleteness; self.processActive = processActive
    }
}

@MainActor
final class UsageHistoryStore: UsageHistoryReading, UsageHistoryWriting {
    let container: ModelContainer?
    var isAvailable: Bool { container != nil }

    private var context: ModelContext {
        get throws {
            guard let container else { throw UsageHistoryStoreError.unavailable }
            return container.mainContext
        }
    }

    init(inMemory: Bool = false) throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        container = try ModelContainer(for: UsageSnapshotEntity.self, configurations: configuration)
    }

    private init(disabled: Void) {
        container = nil
    }

    static func disabled() -> UsageHistoryStore {
        UsageHistoryStore(disabled: ())
    }

    func saveIfNeeded(_ snapshot: CodexUsageSnapshot, processActive: Bool) throws -> Bool {
        let context = try context
        var descriptor = FetchDescriptor<UsageSnapshotEntity>(sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        let last = try context.fetch(descriptor).first
        let newAnalyticsData = snapshot.analytics.flatMap { try? JSONEncoder().encode($0) }
        if let last {
            if last.id == snapshot.id, last.analyticsData != newAnalyticsData {
                last.analyticsData = newAnalyticsData
                try context.save()
                return true
            }
            let changed = abs((last.primaryRemaining ?? -1) - (snapshot.primaryWindow?.remainingPercentage ?? -1)) >= 0.5
                || abs((last.secondaryRemaining ?? -1) - (snapshot.secondaryWindow?.remainingPercentage ?? -1)) >= 0.5
                || last.creditsRemaining != snapshot.credits?.remaining
                || last.restoredResetAllowance?.availableCount != snapshot.resetAllowance?.availableCount
                || last.restoredAccountIdentity != snapshot.accountIdentity
                || last.primaryReset != snapshot.primaryWindow?.resetsAt
                || last.secondaryReset != snapshot.secondaryWindow?.resetsAt
                || last.sourceKindRaw != snapshot.sourceKind.rawValue
                || snapshot.fetchedAt.timeIntervalSince(last.fetchedAt) >= 600
            guard changed else { return false }
        }
        context.insert(UsageSnapshotEntity(snapshot: snapshot, processActive: processActive))
        try context.save(); return true
    }

    func points(since date: Date) throws -> [UsageSnapshotEntity] {
        let context = try context
        let descriptor = FetchDescriptor<UsageSnapshotEntity>(predicate: #Predicate { $0.fetchedAt >= date }, sortBy: [SortDescriptor(\.fetchedAt)])
        return try context.fetch(descriptor)
    }

    func usageSamples(since date: Date) throws -> [UsageHistorySample] {
        try points(since: date).compactMap { entity in
            guard !entity.isEstimated, let remaining = entity.primaryRemaining else { return nil }
            return UsageHistorySample(
                id: entity.id,
                recordedAt: entity.fetchedAt,
                remainingPercentage: remaining,
                resetsAt: entity.primaryReset,
                resetAllowanceAvailable: entity.restoredResetAllowance?.availableCount,
                isCached: entity.isCached
            )
        }
    }

    func creditBalanceSamples(since date: Date) throws -> [CreditBalanceSample] {
        let context = try context
        let recentDescriptor = FetchDescriptor<UsageSnapshotEntity>(
            predicate: #Predicate { $0.fetchedAt >= date },
            sortBy: [SortDescriptor(\.fetchedAt)]
        )
        var baselineDescriptor = FetchDescriptor<UsageSnapshotEntity>(
            predicate: #Predicate { $0.fetchedAt < date },
            sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)]
        )
        baselineDescriptor.fetchLimit = 1
        let recent = try context.fetch(recentDescriptor)
        var baselineCandidates = try context.fetch(baselineDescriptor)
        if baselineCandidates.first?.creditsRemaining == nil
            || baselineCandidates.first?.isCached == true
            || baselineCandidates.first?.isEstimated == true {
            var fallbackDescriptor = FetchDescriptor<UsageSnapshotEntity>(
                predicate: #Predicate { $0.fetchedAt < date },
                sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)]
            )
            fallbackDescriptor.fetchLimit = 50
            baselineCandidates = try context.fetch(fallbackDescriptor)
        }
        let baseline = baselineCandidates.first {
            $0.creditsRemaining != nil && !$0.isCached && !$0.isEstimated
        }
        let entities = (baseline.map { [$0] } ?? []) + recent
        return entities.compactMap { entity in
            guard let remaining = entity.creditsRemaining else { return nil }
            let identity = entity.restoredAccountIdentity
            return CreditBalanceSample(
                id: entity.id,
                recordedAt: entity.fetchedAt,
                remaining: remaining,
                isCached: entity.isCached,
                isEstimated: entity.isEstimated,
                accountKey: identity?.accountID ?? identity?.email,
                sourceKind: UsageSourceKind(rawValue: entity.sourceKindRaw) ?? .unavailable
            )
        }
    }

    func recentSnapshots(limit: Int = 12) throws -> [CodexUsageSnapshot] {
        let context = try context
        var descriptor = FetchDescriptor<UsageSnapshotEntity>(sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)])
        descriptor.fetchLimit = max(1, limit)
        return try context.fetch(descriptor).reversed().compactMap { $0.restoredSnapshot }
    }

    func cleanup(retentionDays: Int) throws {
        let context = try context
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: .now) ?? .distantPast
        try context.delete(model: UsageSnapshotEntity.self, where: #Predicate { $0.fetchedAt < cutoff })
        try context.save()
    }

    func clear() throws {
        let context = try context
        try context.delete(model: UsageSnapshotEntity.self)
        try context.save()
    }
}

private extension UsageSnapshotEntity {
    var restoredSnapshot: CodexUsageSnapshot? {
        guard !isEstimated,
              let sourceKind = UsageSourceKind(rawValue: sourceKindRaw),
              let confidence = UsageConfidence(rawValue: confidenceRaw) else { return nil }
        let primary = primaryRemaining.map {
            UsageLimitWindow(kind: .primary, remainingPercentage: $0, usedPercentage: 100 - $0,
                             resetsAt: primaryReset, durationDescription: primaryDuration)
        }
        let secondary = secondaryRemaining.map {
            UsageLimitWindow(kind: .secondary, remainingPercentage: $0, usedPercentage: 100 - $0,
                             resetsAt: secondaryReset, durationDescription: secondaryDuration)
        }
        let credits = (creditsRemaining != nil || creditsUnit != nil)
            ? CreditsUsage(remaining: creditsRemaining, used: nil, currencyOrUnit: creditsUnit, expiresAt: nil)
            : nil
        let analytics = analyticsData.flatMap { try? JSONDecoder().decode(CodexAnalyticsSnapshot.self, from: $0) }
        let resetAllowance = restoredResetAllowance
        let accountIdentity = restoredAccountIdentity
        return CodexUsageSnapshot(
            id: id, fetchedAt: fetchedAt, sourceUpdatedAt: sourceUpdatedAt, planName: planName,
            primaryWindow: primary, secondaryWindow: secondary, credits: credits,
            resetAllowance: resetAllowance, analytics: analytics, accountIdentity: accountIdentity,
            sourceKind: sourceKind, sourceDisplayName: sourceKind.label,
            confidence: confidence, fieldCompleteness: fieldCompleteness
        )
    }

    var restoredResetAllowance: UsageResetAllowance? {
        resetAllowanceData.flatMap { try? JSONDecoder().decode(UsageResetAllowance.self, from: $0) }
    }

    var restoredAccountIdentity: CodexAccountIdentity? {
        accountIdentityData.flatMap { try? JSONDecoder().decode(CodexAccountIdentity.self, from: $0) }
    }
}
