import Foundation
import Observation

@MainActor
@Observable
final class SettingsModel {
    var message: String?
    var notificationAuthorization: NotificationAuthorizationState = .unknown
    var launchAtLoginState: LaunchAtLoginService.State = .disabled
    var launchAtLoginError: String?
    var localCodexStatus: LocalCodexLoginStatus = .unavailable("尚未检查")

    func load() async {
        notificationAuthorization = await NotificationService().authorizationState()
        refreshLaunchAtLoginState()
        await refreshLocalCodexStatus()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginService().setEnabled(enabled)
            refreshLaunchAtLoginState()
            launchAtLoginError = nil
        } catch {
            refreshLaunchAtLoginState()
            launchAtLoginError = "自动启动设置失败：\(SensitiveDataRedactor().redact(error.localizedDescription))"
        }
    }

    func refreshLaunchAtLoginState() {
        launchAtLoginState = LaunchAtLoginService().state
    }

    func requestNotificationAuthorization() async -> Bool {
        let granted = (try? await NotificationService().requestAuthorization()) ?? false
        notificationAuthorization = await NotificationService().authorizationState()
        return granted
    }

    func refreshLocalCodexStatus() async {
        localCodexStatus = await LocalCodexLoginProbe().status()
    }

    func startLocalCodexLogin() async {
        do {
            try await LocalCodexLoginProbe().startLogin()
            message = "已打开 Codex 登录流程"
            await refreshLocalCodexStatus()
        } catch {
            message = "无法打开 Codex 登录：\(SensitiveDataRedactor().redact(error.localizedDescription))"
        }
    }
}
