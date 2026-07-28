import Foundation

struct UsageSnapshotPipelineResult: Sendable, Equatable {
    let historyChanged: Bool
    let persistenceWarning: String?
}

@MainActor
final class UsageSnapshotPipeline {
    private let history: any UsageHistoryWriting
    private let processMonitor: CodexProcessMonitor
    private let notificationService: NotificationService
    private let resetDetector: ResetDetectionService

    init(
        history: any UsageHistoryWriting,
        processMonitor: CodexProcessMonitor = CodexProcessMonitor(),
        notificationService: NotificationService = NotificationService(),
        resetDetector: ResetDetectionService = ResetDetectionService()
    ) {
        self.history = history
        self.processMonitor = processMonitor
        self.notificationService = notificationService
        self.resetDetector = resetDetector
    }

    func process(previous: CodexUsageSnapshot, current: CodexUsageSnapshot) async -> UsageSnapshotPipelineResult {
        let result = persist(current)
        let reset = resetDetector.isReset(old: previous, new: current)
        await notificationService.evaluate(previous: previous, current: current, reset: reset)
        return result
    }

    func persistAnalytics(_ snapshot: CodexUsageSnapshot) -> UsageSnapshotPipelineResult {
        persist(snapshot)
    }

    private func persist(_ snapshot: CodexUsageSnapshot) -> UsageSnapshotPipelineResult {
        do {
            return UsageSnapshotPipelineResult(
                historyChanged: try history.saveIfNeeded(snapshot, processActive: processMonitor.isActive()),
                persistenceWarning: nil
            )
        } catch {
            let message = SensitiveDataRedactor().redact(error.localizedDescription)
            return UsageSnapshotPipelineResult(historyChanged: false, persistenceWarning: "历史保存失败：\(message)")
        }
    }
}
