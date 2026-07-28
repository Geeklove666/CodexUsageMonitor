import Foundation

enum AIProviderID: String, Codable, Sendable, CaseIterable {
    case codex
    case chatGPT
    case claude
    case gemini
    case openAIAPI
}

enum AIProviderCapability: String, Codable, Sendable, Hashable, CaseIterable {
    case quotaWindows
    case balance
    case localTokenHistory
    case remoteUsageHistory
    case costEstimate
}

enum AIProviderAuthenticationMode: String, Codable, Sendable, Hashable, CaseIterable {
    case localCLI
    case localFiles
    case embeddedBrowser
    case apiKey
    case oauth
}

struct AIProviderDescriptor: Sendable, Codable, Equatable, Identifiable {
    let id: AIProviderID
    let displayName: String
    let capabilities: Set<AIProviderCapability>
    let authenticationModes: Set<AIProviderAuthenticationMode>

    init(id: AIProviderID, displayName: String,
         capabilities: Set<AIProviderCapability> = [],
         authenticationModes: Set<AIProviderAuthenticationMode> = []) {
        self.id = id
        self.displayName = displayName
        self.capabilities = capabilities
        self.authenticationModes = authenticationModes
    }
}

struct AIProviderQuotaWindow: Sendable, Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let remainingPercentage: Double?
    let usedPercentage: Double?
    let resetsAt: Date?
}

struct AIProviderBalance: Sendable, Codable, Equatable {
    let remaining: Decimal?
    let used: Decimal?
    let unit: String?
}

struct AIProviderDailyUsage: Sendable, Codable, Equatable, Identifiable {
    var id: Date { date }
    let date: Date
    let tokens: Int64
}

struct AIProviderUsageSnapshot: Sendable, Codable, Equatable {
    let provider: AIProviderDescriptor
    let fetchedAt: Date
    let planName: String?
    let quotaWindows: [AIProviderQuotaWindow]
    let balance: AIProviderBalance?
    let dailyUsage: [AIProviderDailyUsage]
    let sourceDisplayName: String
    let isCached: Bool
    let isEstimated: Bool

    init(provider: AIProviderDescriptor, fetchedAt: Date, planName: String?,
         quotaWindows: [AIProviderQuotaWindow], balance: AIProviderBalance?,
         dailyUsage: [AIProviderDailyUsage] = [], sourceDisplayName: String,
         isCached: Bool, isEstimated: Bool) {
        self.provider = provider
        self.fetchedAt = fetchedAt
        self.planName = planName
        self.quotaWindows = quotaWindows
        self.balance = balance
        self.dailyUsage = dailyUsage
        self.sourceDisplayName = sourceDisplayName
        self.isCached = isCached
        self.isEstimated = isEstimated
    }
}

protocol AIUsageProvider: Sendable {
    var descriptor: AIProviderDescriptor { get }
    func availability() async -> DataSourceAvailability
    func fetchUsage(forceRefresh: Bool) async throws -> AIProviderUsageSnapshot
}

struct AIProviderRegistry: Sendable {
    private let providers: [AIProviderID: any AIUsageProvider]

    init(_ providers: [any AIUsageProvider]) {
        var registered: [AIProviderID: any AIUsageProvider] = [:]
        for provider in providers {
            registered[provider.descriptor.id] = provider
        }
        self.providers = registered
    }

    var registeredProviderIDs: Set<AIProviderID> { Set(providers.keys) }

    var registeredProviders: [any AIUsageProvider] {
        providers.values.sorted { $0.descriptor.displayName < $1.descriptor.displayName }
    }

    func provider(for id: AIProviderID) -> (any AIUsageProvider)? {
        providers[id]
    }
}
