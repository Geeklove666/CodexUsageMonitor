import Foundation
import Observation

@MainActor
@Observable
final class DashboardInteractionModel {
    private(set) var notificationAuthorization: NotificationAuthorizationState = .unknown

    func loadNotificationAuthorization() async {
        notificationAuthorization = await NotificationService().authorizationState()
    }

    func setNotificationsEnabled(_ enabled: Bool) async -> Bool {
        guard enabled else { return false }
        let service = NotificationService()
        let granted = (try? await service.requestAuthorization()) ?? false
        notificationAuthorization = await service.authorizationState()
        return granted
    }

    func alertStatusMessage(notificationsEnabled: Bool) -> String {
        guard notificationsEnabled else { return "额度通知当前已关闭。" }
        guard notificationAuthorization.canDeliver else {
            return "系统通知权限不可用，请在系统设置中允许通知。"
        }
        return "通知规则已连接真实偏好设置，并依据真实额度变化触发。"
    }
}
