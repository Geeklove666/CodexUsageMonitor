import Foundation

enum AIProviderID: String, Codable, Sendable, CaseIterable {
    case codex
    case chatGPT
    case claude
    case gemini
    case openAIAPI
}

struct AIProviderDescriptor: Sendable, Codable, Equatable, Identifiable {
    let id: AIProviderID
    let displayName: String
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

struct AIProviderUsageSnapshot: Sendable, Codable, Equatable {
    let provider: AIProviderDescriptor
    let fetchedAt: Date
    let planName: String?
    let quotaWindows: [AIProviderQuotaWindow]
    let balance: AIProviderBalance?
    let sourceDisplayName: String
    let isCached: Bool
    let isEstimated: Bool
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

    func provider(for id: AIProviderID) -> (any AIUsageProvider)? {
        providers[id]
    }
}
