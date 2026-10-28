import Foundation

enum UsagePaceBuilder {
    static func assess(snapshot: CodexUsageSnapshot, samples: [UsageHistorySample], now: Date) -> UsagePaceAssessment {
        guard !snapshot.isCached, !snapshot.isEstimated,
              [.verifiedOfficial, .localCodexSession, .officialWebPage].contains(snapshot.sourceKind),
              let remaining = snapshot.primaryWindow?.remainingPercentage, remaining.isFinite else {
            return .unavailable("需要最新的真实额度，缓存或估算数据不用于预测。")
        }
        let updatedAt = min(snapshot.sourceUpdatedAt ?? snapshot.fetchedAt, snapshot.fetchedAt)
        guard updatedAt <= now, now.timeIntervalSince(updatedAt) <= 15 * 60,
              snapshot.fetchedAt <= now,
              snapshot.expiresAt.map({ $0 > now }) ?? true else {
            return .unavailable("额度数据已过期，请刷新后查看预测。")
        }
        guard remaining > 0 else {
            return .unavailable("当前额度已耗尽，等待服务方重置。")
        }
        guard let resetsAt = snapshot.primaryWindow?.resetsAt else {
            return .unavailable("服务方未返回重置时间，暂时无法判断额度能否用至重置。")
        }
        guard resetsAt > now else {
            return .unavailable("已到重置时间，请刷新额度后重新观察。")
        }

        let current = UsageHistorySample(
            id: snapshot.id, recordedAt: updatedAt, remainingPercentage: remaining,
            resetsAt: resetsAt, isCached: false, accountIdentity: snapshot.accountIdentity,
            sourceKind: snapshot.sourceKind, planName: snapshot.planName
        )
        // Replace an already persisted copy; the current reading is the authoritative endpoint.
        let history = samples.filter { $0.id != current.id && $0.recordedAt < current.recordedAt }
        let segment = UsageTrendBuilder.recentContinuousSamples(from: history + [current], now: now)
        guard let first = segment.first,
              current.recordedAt.timeIntervalSince(first.recordedAt) >= 30 * 60 else {
            return .unavailable("同一额度周期内需要至少 30 分钟的连续真实记录；继续观察后会显示预测。")
        }
        let hours = current.recordedAt.timeIntervalSince(first.recordedAt) / 3600
        let consumed = first.remainingPercentage - remaining
        guard consumed >= 1 else {
            return .unavailable("观察期内消耗不足 1 个百分点，暂时无法可靠预测耗尽时间。")
        }
        let rate = consumed / hours
        let timeToReset = resetsAt.timeIntervalSince(current.recordedAt)
        let exhaustion = current.recordedAt.addingTimeInterval(remaining / rate * 3600)
        // The projection is anchored to the last observation, never extended by the UI clock.
        guard exhaustion > now else {
            return .unavailable("已超过上次预测的耗尽时间，请刷新额度确认当前状态。")
        }
        return .projected(UsagePaceProjection(
            samples: segment,
            observedAt: current.recordedAt,
            resetsAt: resetsAt,
            remainingPercentage: remaining,
            percentagePointsPerHour: rate,
            observationHours: hours,
            projectedExhaustionAt: exhaustion,
            projectedRemainingAtReset: max(0, remaining - rate * timeToReset / 3600),
            sustainablePercentagePointsPerHour: remaining / (timeToReset / 3600)
        ))
    }
}
