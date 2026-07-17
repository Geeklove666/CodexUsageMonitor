import AppKit
import SwiftData
import SwiftUI

@main
struct CodexUsageMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var container = DependencyContainer()

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView(monitor: container.monitoring)
                .environment(container.webSession)
        } label: {
            MenuBarLabel(snapshot: container.monitoring.snapshot, now: container.monitoring.now)
        }
        .menuBarExtraStyle(.window)

        Window("Codex Usage", id: "dashboard") {
            DashboardView(monitor: container.monitoring, history: container.history)
                .environment(container.webSession)
                .modelContainer(container.history.container)
                .frame(minWidth: 720, minHeight: 520)
        }
        .defaultSize(width: 960, height: 680)

        Window("Codex Usage 登录", id: "login") {
            LoginView().environment(container.webSession).frame(minWidth: 760, minHeight: 600)
        }

        Settings { SettingsView(history: container.history, monitor: container.monitoring).environment(container.webSession) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            UsageMonitoringService.refreshIntervalPreferenceKey: AutoRefreshFrequency.defaultValue.rawValue,
            "notificationsEnabled": false,
            "notifyEvery20": true, "notifyReset": true,
            LocalRealtimeTokenAuthorization.preferenceKey: false,
            "retentionDays": 30
        ])
        NSApp.setActivationPolicy(UserDefaults.standard.bool(forKey: "showDockIcon") ? .regular : .accessory)
        Task { @MainActor in
            for window in NSApp.windows { window.isReleasedWhenClosed = false }
        }
    }
}
