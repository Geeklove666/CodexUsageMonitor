import Foundation
import UserNotifications

enum NotificationAuthorizationState: String, Sendable {
    case notDetermined, denied, authorized, provisional, ephemeral, unknown
    var label: String {
        switch self {
        case .notDetermined: "尚未请求系统权限"
        case .denied: "系统通知权限已关闭"
        case .authorized: "系统通知权限已允许"
        case .provisional: "系统通知为临时允许"
        case .ephemeral: "系统通知为临时会话权限"
        case .unknown: "无法确定系统通知权限"
        }
    }
    var canDeliver: Bool { self == .authorized || self == .provisional || self == .ephemeral }
}

actor NotificationService {
    private let defaults = UserDefaults.standard

    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func authorizationState() async -> NotificationAuthorizationState {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let state: NotificationAuthorizationState = switch settings.authorizationStatus {
                case .notDetermined: .notDetermined
                case .denied: .denied
                case .authorized: .authorized
                case .provisional: .provisional
                case .ephemeral: .ephemeral
                @unknown default: .unknown
                }
                continuation.resume(returning: state)
            }
        }
    }

    func evaluate(previous: CodexUsageSnapshot?, current: CodexUsageSnapshot, reset: Bool) async {
        guard defaults.bool(forKey: "notificationsEnabled"),
              await authorizationState().canDeliver,
              let remaining = current.primaryWindow?.remainingPercentage else { return }
        let cycle = cycleIdentifier(current, reset: reset)
        pruneMilestoneState(keeping: cycle)
        let currentStep = ConsumptionMilestonePolicy.step(remainingPercentage: remaining)
        let stateKey = "consumption.step.\(cycle)"

        if defaults.bool(forKey: "notifyEvery20") {
            let previousStep: Int?
            if defaults.object(forKey: stateKey) != nil {
                previousStep = defaults.integer(forKey: stateKey)
            } else if let previousRemaining = previous?.primaryWindow?.remainingPercentage,
                      cycleIdentifier(previous ?? current, reset: false) == cycle {
                previousStep = ConsumptionMilestonePolicy.step(remainingPercentage: previousRemaining)
            } else {
                previousStep = nil
            }

            if let previousStep, currentStep >= previousStep {
                for milestone in ConsumptionMilestonePolicy.crossedMilestones(from: previousStep, to: currentStep) {
                    let key = "consumption.\(cycle).\(milestone)"
                    let content = UNMutableNotificationContent()
                    content.title = "Codex 额度已使用 \(milestone)%"
                    let prefix = current.isEstimated ? "根据本地历史估算，" : ""
                    content.body = "\(prefix)当前主额度窗口剩余约 \(Int(remaining))%。"
                    content.sound = .default
                    try? await UNUserNotificationCenter.current().add(
                        UNNotificationRequest(identifier: key, content: content, trigger: nil)
                    )
                }
            }
            defaults.set(reset ? currentStep : max(previousStep ?? currentStep, currentStep), forKey: stateKey)
        }

        if reset && defaults.bool(forKey: "notifyReset") {
            defaults.set(currentStep, forKey: stateKey)
            let content = UNMutableNotificationContent(); content.title = "Codex 额度已经重置"; content.body = "已检测到额度周期恢复。"; content.sound = .default
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "reset.\(cycle)", content: content, trigger: nil))
        }
    }

    private func cycleIdentifier(_ snapshot: CodexUsageSnapshot, reset: Bool) -> String {
        if let resetAt = snapshot.primaryWindow?.resetsAt { return "reset-\(Int(resetAt.timeIntervalSince1970 / 60))" }
        let key = "consumption.fallbackCycle"
        var generation = defaults.integer(forKey: key)
        if defaults.object(forKey: key) == nil { generation = Int(Date.now.timeIntervalSince1970 / 86_400) }
        if reset { generation += 1 }
        defaults.set(generation, forKey: key)
        return "fallback-\(generation)"
    }

    private func pruneMilestoneState(keeping cycle: String) {
        for key in defaults.dictionaryRepresentation().keys
            where (key.hasPrefix("consumption.step.") || key.hasPrefix("consumption.reset-") || key.hasPrefix("consumption.fallback-"))
                && !key.contains(cycle) {
            defaults.removeObject(forKey: key)
        }
    }
}

enum ConsumptionMilestonePolicy {
    static func step(remainingPercentage: Double) -> Int {
        let used = min(100, max(0, 100 - remainingPercentage))
        return Int(used / 20)
    }

    static func crossedMilestones(from previousStep: Int, to currentStep: Int) -> [Int] {
        let start = min(5, max(0, previousStep))
        let end = min(5, max(0, currentStep))
        guard end > start else { return [] }
        return ((start + 1)...end).map { $0 * 20 }
    }
}
