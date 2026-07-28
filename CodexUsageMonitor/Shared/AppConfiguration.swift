import Foundation

enum AppPreferences {
    enum Key {
        static let autoRefreshSeconds = "autoRefreshSeconds"
        static let showDockIcon = "showDockIcon"
        static let notificationsEnabled = "notificationsEnabled"
        static let notifyEvery20 = "notifyEvery20"
        static let notifyReset = "notifyReset"
        static let retentionDays = "retentionDays"
        static let debugMode = "debugMode"
        static let reuseLocalCodexLogin = "reuseLocalCodexLogin"
        static let allowCustomCodexExecutable = "allowCustomCodexExecutable"
        static let localRealtimeTokenUsageEnabled = "localRealtimeTokenUsageEnabled"
        static let localClaudeUsageEnabled = "localClaudeUsageEnabled"
    }

    @MainActor static let registeredDefaults: [String: Any] = [
        Key.autoRefreshSeconds: AutoRefreshFrequency.defaultValue.rawValue,
        Key.showDockIcon: false,
        Key.notificationsEnabled: false,
        Key.notifyEvery20: true,
        Key.notifyReset: true,
        Key.retentionDays: AppConfiguration.Persistence.defaultRetentionDays,
        Key.debugMode: false,
        Key.reuseLocalCodexLogin: false,
        Key.allowCustomCodexExecutable: false,
        Key.localRealtimeTokenUsageEnabled: false,
        Key.localClaudeUsageEnabled: false
    ]
}

enum AppConfiguration {
    enum Refresh {
        static let failureBackoff: [TimeInterval] = [0, 60, 120, 300, 600, 1_800]
        static let requestTimeout: Duration = .seconds(20)
        static let localCodexRequestTimeout: Duration = .seconds(45)
        static let analyticsTimeout: Duration = .seconds(8)
        static let networkRestoreDebounce: Duration = .seconds(2)
        static let resetBoundaryGrace: TimeInterval = 5
        static let menuFreshnessLimit: TimeInterval = 120
        static let localLoginStatusCacheLifetime: TimeInterval = 120
        static let localQuotaCacheLifetime: TimeInterval = 45
        static let localAnalyticsCacheLifetime: TimeInterval = 900
    }

    enum Persistence {
        static let defaultRetentionDays = 30
        static let minimumRetentionDays = 7
        static let maximumRetentionDays = 90
        static let restoredSnapshotLimit = 24
        static let restoredSnapshotMaximumAge: TimeInterval = 86_400
    }
}
