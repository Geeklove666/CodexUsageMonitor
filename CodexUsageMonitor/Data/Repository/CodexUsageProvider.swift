import Foundation

struct CodexUsageProvider: AIUsageProvider {
    let descriptor = AIProviderDescriptor(
        id: .codex,
        displayName: "Codex",
        capabilities: [.quotaWindows, .balance, .localTokenHistory, .remoteUsageHistory],
        authenticationModes: [.localCLI, .localFiles, .embeddedBrowser]
    )
    private let repository: any CodexUsageRepository

    init(repository: any CodexUsageRepository) {
        self.repository = repository
    }

    func availability() async -> DataSourceAvailability {
        .available
    }

    func fetchUsage(forceRefresh: Bool) async throws -> AIProviderUsageSnapshot {
        let snapshot = try await repository.fetchQuota(forceRefresh: forceRefresh)
        var windows: [AIProviderQuotaWindow] = []
        if let primary = snapshot.primaryWindow {
            windows.append(Self.window(primary, id: "primary", title: "主额度"))
        }
        if let secondary = snapshot.secondaryWindow {
            windows.append(Self.window(secondary, id: "secondary", title: "其他额度"))
        }
        let balance = snapshot.credits.map {
            AIProviderBalance(remaining: $0.remaining, used: $0.used, unit: $0.currencyOrUnit)
        }
        return AIProviderUsageSnapshot(
            provider: descriptor,
            fetchedAt: snapshot.fetchedAt,
            planName: snapshot.planName,
            quotaWindows: windows,
            balance: balance,
            sourceDisplayName: snapshot.sourceDisplayName,
            isCached: snapshot.isCached,
            isEstimated: snapshot.isEstimated
        )
    }

    private static func window(_ value: UsageLimitWindow, id: String, title: String) -> AIProviderQuotaWindow {
        AIProviderQuotaWindow(
            id: id,
            title: title,
            remainingPercentage: value.remainingPercentage,
            usedPercentage: value.usedPercentage,
            resetsAt: value.resetsAt
        )
    }
}
