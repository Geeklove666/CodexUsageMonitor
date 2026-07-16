import ServiceManagement

@MainActor
struct LaunchAtLoginService {
    enum State: Equatable {
        case disabled
        case enabled
        case requiresApproval
        case unavailable

        var isSelected: Bool {
            self == .enabled || self == .requiresApproval
        }

        var message: String {
            switch self {
            case .disabled: "未启用"
            case .enabled: "已启用 · 登录 Mac 后自动运行"
            case .requiresApproval: "等待你在系统设置中允许"
            case .unavailable: "当前安装位置无法注册登录项"
            }
        }

        var symbol: String {
            switch self {
            case .disabled: "circle"
            case .enabled: "checkmark.circle.fill"
            case .requiresApproval: "person.badge.clock.fill"
            case .unavailable: "exclamationmark.triangle.fill"
            }
        }
    }

    var state: State {
        switch SMAppService.mainApp.status {
        case .notRegistered: .disabled
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard SMAppService.mainApp.status == .notRegistered else { return }
            try SMAppService.mainApp.register()
        } else {
            guard SMAppService.mainApp.status != .notRegistered else { return }
            try SMAppService.mainApp.unregister()
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
