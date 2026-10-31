import Foundation

enum UsageTrendBuilder {
    static func makePoints(from samples: [UsageHistorySample], maxPoints: Int? = nil) -> [UsageTrendPoint] {
        let sorted = samples.sorted { $0.recordedAt < $1.recordedAt }
        var previous: UsageHistorySample?

        let points = sorted.map { sample in
            let resetChanged = previous?.resetsAt != nil
                && sample.resetsAt != nil
                && previous?.resetsAt != sample.resetsAt
            let allowanceRecovered = previous.map {
                sample.remainingPercentage - $0.remainingPercentage >= 5
            } ?? false
            let point = UsageTrendPoint(
                id: sample.id,
                date: sample.recordedAt,
                remainingPercentage: sample.remainingPercentage,
                isReset: resetChanged && allowanceRecovered,
                isCached: sample.isCached
            )
            previous = sample
            return point
        }
        guard let maxPoints, maxPoints >= 4, points.count > maxPoints else { return points }
        return downsample(points, maximumCount: maxPoints)
    }

    static func makeVelocity(from samples: [UsageHistorySample], now: Date = .now) -> UsageVelocity? {
        let segment = recentContinuousSamples(from: samples, now: now)
        guard let first = segment.first, let last = segment.last,
              now.timeIntervalSince(last.recordedAt) <= 15 * 60 else { return nil }
        let hours = last.recordedAt.timeIntervalSince(first.recordedAt) / 3600
        let consumed = first.remainingPercentage - last.remainingPercentage
        guard hours >= 0.5, consumed > 0 else { return nil }
        return UsageVelocity(consumedPercentage: consumed, observationHours: hours)
    }

    /// A rate must never bridge a reset, account/source/plan change, or a long offline gap.
    static func recentContinuousSamples(from samples: [UsageHistorySample], now: Date) -> [UsageHistorySample] {
        let recent = samples
            .filter {
                !$0.isCached && $0.remainingPercentage.isFinite
                    && $0.recordedAt >= now.addingTimeInterval(-24 * 60 * 60)
                    && $0.recordedAt <= now
            }
            .sorted { $0.recordedAt < $1.recordedAt }
        var segment: [UsageHistorySample] = []
        for sample in recent {
            if let previous = segment.last {
                let gap = sample.recordedAt.timeIntervalSince(previous.recordedAt)
                if sample.resetsAt != previous.resetsAt
                    || sample.accountIdentity != previous.accountIdentity
                    || sample.sourceKind != previous.sourceKind
                    || sample.planName != previous.planName
                    || sample.remainingPercentage - previous.remainingPercentage >= 0.5
                    || gap > 2 * 60 * 60
                    || gap == 0 {
                    segment.removeAll(keepingCapacity: true)
                }
            }
            segment.append(sample)
        }
        return segment
    }

    private static func downsample(_ points: [UsageTrendPoint], maximumCount: Int) -> [UsageTrendPoint] {
        var retained = Set([0, points.count - 1])
        if let minimum = points.indices.min(by: { points[$0].remainingPercentage < points[$1].remainingPercentage }) {
            retained.insert(minimum)
        }
        if let maximum = points.indices.max(by: { points[$0].remainingPercentage < points[$1].remainingPercentage }) {
            retained.insert(maximum)
        }
        for index in points.indices where points[index].isReset { retained.insert(index) }

        let available = max(0, maximumCount - retained.count)
        if available > 0 {
            let candidates = points.indices.filter { !retained.contains($0) }
            if candidates.count <= available {
                retained.formUnion(candidates)
            } else {
                let step = Double(candidates.count - 1) / Double(max(1, available - 1))
                for slot in 0..<available {
                    retained.insert(candidates[Int((Double(slot) * step).rounded())])
                }
            }
        }
        return retained.sorted().map { points[$0] }
    }
}
