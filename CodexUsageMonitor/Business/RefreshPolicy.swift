import Foundation

struct RefreshPolicy: Sendable {
    func automaticDelay(
        configuredSeconds: Int,
        failureCount: Int,
        lastMenuOpenAt: Date?,
        now: Date,
        isLowPowerModeEnabled: Bool,
        hasThermalPressure: Bool,
        jitterFactor: Double
    ) -> TimeInterval {
        let base = configuredDelay(
            configuredSeconds: configuredSeconds,
            lastMenuOpenAt: lastMenuOpenAt,
            now: now,
            isLowPowerModeEnabled: isLowPowerModeEnabled,
            hasThermalPressure: hasThermalPressure
        )
        let backoffValues = AppConfiguration.Refresh.failureBackoff
        let backoff = backoffValues[min(max(failureCount, 0), backoffValues.count - 1)]
        return max(base, backoff) * jitterFactor.clamped(to: 0.95...1.05)
    }

    func shouldRefreshOnMenuOpen(
        snapshot: CodexUsageSnapshot,
        hasFailure: Bool,
        isRefreshing: Bool,
        maxAge: TimeInterval,
        now: Date
    ) -> Bool {
        guard !isRefreshing else { return false }
        if snapshot.sourceKind == .unavailable || hasFailure || snapshot.isCached || snapshot.isEstimated {
            return true
        }
        return now.timeIntervalSince(snapshot.fetchedAt) > maxAge
    }

    private func configuredDelay(
        configuredSeconds: Int,
        lastMenuOpenAt: Date?,
        now: Date,
        isLowPowerModeEnabled: Bool,
        hasThermalPressure: Bool
    ) -> TimeInterval {
        guard AutoRefreshFrequency(rawValue: configuredSeconds) == .adaptive else {
            return TimeInterval(AutoRefreshFrequency.sanitizedSeconds(configuredSeconds))
        }
        if isLowPowerModeEnabled || hasThermalPressure {
            return TimeInterval(AutoRefreshFrequency.tenMinutes.rawValue)
        }
        guard let lastMenuOpenAt else { return TimeInterval(AutoRefreshFrequency.tenMinutes.rawValue) }
        let age = now.timeIntervalSince(lastMenuOpenAt)
        if age <= 5 * 60 { return TimeInterval(AutoRefreshFrequency.oneMinute.rawValue) }
        if age <= 60 * 60 { return TimeInterval(AutoRefreshFrequency.fiveMinutes.rawValue) }
        return TimeInterval(AutoRefreshFrequency.tenMinutes.rawValue)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
