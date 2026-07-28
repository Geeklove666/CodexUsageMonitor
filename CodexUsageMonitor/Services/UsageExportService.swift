import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct UsageExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText, .data] }
    let data: Data

    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct UsageExportPayload {
    let document: UsageExportDocument
    let contentType: UTType
    let defaultFilename: String
}

@MainActor
struct UsageExportService {
    private let redactor = SensitiveDataRedactor()

    func usageJSON(current: CodexUsageSnapshot,
                   providers: [AIProviderID: AIProviderUsageSnapshot],
                   history: UsageHistoryStore) throws -> UsageExportPayload {
        let envelope = UsageExportEnvelope(
            schemaVersion: 1,
            generatedAt: .now,
            current: SafeSnapshot(current),
            history: try history.recentSnapshots(limit: 10_000).map(SafeSnapshot.init),
            providers: providers.values.sorted { $0.provider.displayName < $1.provider.displayName }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return UsageExportPayload(
            document: UsageExportDocument(data: try encoder.encode(envelope)),
            contentType: .json,
            defaultFilename: "Codex-Usage-Export-\(Self.dayStamp).json"
        )
    }

    func historyCSV(history: UsageHistoryStore) throws -> UsageExportPayload {
        let formatter = ISO8601DateFormatter()
        var rows = [[
            "fetched_at", "source", "confidence", "plan", "primary_remaining_percent",
            "primary_reset_at", "secondary_remaining_percent", "secondary_reset_at",
            "credits_remaining", "cached", "estimated", "today_tokens"
        ]]
        for value in try history.recentSnapshots(limit: 10_000) {
            let primaryRemaining = value.primaryWindow?.remainingPercentage.map { String($0) } ?? ""
            let primaryReset = value.primaryWindow?.resetsAt.map { formatter.string(from: $0) } ?? ""
            let secondaryRemaining = value.secondaryWindow?.remainingPercentage.map { String($0) } ?? ""
            let secondaryReset = value.secondaryWindow?.resetsAt.map { formatter.string(from: $0) } ?? ""
            let credits = value.credits?.remaining.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
            let todayTokens = value.analytics?.todayTokens.map { String($0) } ?? ""
            rows.append([
                formatter.string(from: value.fetchedAt), value.sourceDisplayName, value.confidence.rawValue,
                value.planName ?? "", primaryRemaining, primaryReset, secondaryRemaining, secondaryReset,
                credits, String(value.isCached), String(value.isEstimated), todayTokens
            ])
        }
        let csv = rows.map { $0.map(Self.csvField).joined(separator: ",") }.joined(separator: "\n") + "\n"
        return UsageExportPayload(
            document: UsageExportDocument(data: Data(csv.utf8)),
            contentType: .commaSeparatedText,
            defaultFilename: "Codex-Usage-History-\(Self.dayStamp).csv"
        )
    }

    func diagnosticJSON(snapshot: CodexUsageSnapshot,
                        providers: [AIProviderID: AIProviderUsageSnapshot],
                        providerFailures: [AIProviderID: String],
                        diagnostic: DataSourceDiagnostic,
                        persistenceWarning: String?) throws -> UsageExportPayload {
        let report = DiagnosticReport(
            schemaVersion: 1,
            generatedAt: .now,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            snapshot: SafeSnapshot(snapshot),
            activeSource: diagnostic.activeIdentifier,
            analyticsSource: diagnostic.analyticsIdentifier,
            lastSuccess: diagnostic.lastSuccess,
            lastFailure: diagnostic.lastFailure.map(redactor.redact),
            lastFailureKind: diagnostic.lastFailureKind?.rawValue,
            lastAnalyticsFailure: diagnostic.lastAnalyticsFailure.map(redactor.redact),
            analyticsAvailability: diagnostic.analyticsAvailability.mapValues(redactor.redact),
            analyticsFailures: diagnostic.analyticsFailures.mapValues(redactor.redact),
            requestDuration: diagnostic.requestDuration,
            parserVersion: diagnostic.parserVersion,
            fieldCompleteness: diagnostic.fieldCompleteness,
            lastRefreshReason: diagnostic.lastRefreshReason.map(redactor.redact),
            attempts: diagnostic.attempts.map {
                DiagnosticAttempt(
                    sourceIdentifier: $0.sourceIdentifier,
                    sourceLabel: $0.sourceLabel,
                    availability: redactor.redact($0.availability),
                    succeeded: $0.succeeded,
                    duration: $0.duration,
                    error: $0.error.map(redactor.redact),
                    timestamp: $0.timestamp
                )
            },
            providerStates: providers.values.map {
                "\($0.provider.id.rawValue): \($0.sourceDisplayName), \($0.dailyUsage.count) daily records"
            }.sorted(),
            providerFailures: providerFailures.map { "\($0.key.rawValue): \(redactor.redact($0.value))" }.sorted(),
            persistenceWarning: persistenceWarning.map(redactor.redact)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return UsageExportPayload(
            document: UsageExportDocument(data: try encoder.encode(report)),
            contentType: .json,
            defaultFilename: "Codex-Usage-Diagnostics-\(Self.dayStamp).json"
        )
    }

    private static var dayStamp: String {
        Date.now.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
            .replacingOccurrences(of: "/", with: "-")
    }

    private static func csvField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

private struct UsageExportEnvelope: Codable {
    let schemaVersion: Int
    let generatedAt: Date
    let current: SafeSnapshot
    let history: [SafeSnapshot]
    let providers: [AIProviderUsageSnapshot]
}

private struct SafeSnapshot: Codable {
    let fetchedAt: Date
    let sourceUpdatedAt: Date?
    let planName: String?
    let primaryWindow: UsageLimitWindow?
    let secondaryWindow: UsageLimitWindow?
    let credits: CreditsUsage?
    let resetAllowance: UsageResetAllowance?
    let analytics: CodexAnalyticsSnapshot?
    let sourceKind: UsageSourceKind
    let sourceDisplayName: String
    let isEstimated: Bool
    let isCached: Bool
    let confidence: UsageConfidence
    let fieldCompleteness: Double

    init(_ value: CodexUsageSnapshot) {
        fetchedAt = value.fetchedAt
        sourceUpdatedAt = value.sourceUpdatedAt
        planName = value.planName
        primaryWindow = value.primaryWindow
        secondaryWindow = value.secondaryWindow
        credits = value.credits
        resetAllowance = value.resetAllowance
        analytics = value.analytics
        sourceKind = value.sourceKind
        sourceDisplayName = value.sourceDisplayName
        isEstimated = value.isEstimated
        isCached = value.isCached
        confidence = value.confidence
        fieldCompleteness = value.fieldCompleteness
    }
}

private struct DiagnosticReport: Codable {
    let schemaVersion: Int
    let generatedAt: Date
    let appVersion: String
    let buildNumber: String
    let bundleIdentifier: String
    let operatingSystem: String
    let snapshot: SafeSnapshot
    let activeSource: String
    let analyticsSource: String?
    let lastSuccess: Date?
    let lastFailure: String?
    let lastFailureKind: String?
    let lastAnalyticsFailure: String?
    let analyticsAvailability: [String: String]
    let analyticsFailures: [String: String]
    let requestDuration: TimeInterval?
    let parserVersion: String?
    let fieldCompleteness: Double
    let lastRefreshReason: String?
    let attempts: [DiagnosticAttempt]
    let providerStates: [String]
    let providerFailures: [String]
    let persistenceWarning: String?
}

private struct DiagnosticAttempt: Codable {
    let sourceIdentifier: String
    let sourceLabel: String
    let availability: String
    let succeeded: Bool
    let duration: TimeInterval?
    let error: String?
    let timestamp: Date
}
