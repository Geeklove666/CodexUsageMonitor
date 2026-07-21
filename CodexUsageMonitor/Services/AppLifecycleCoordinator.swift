import AppKit

@MainActor
final class AppLifecycleCoordinator: NSObject {
    private weak var monitor: UsageMonitoringService?

    init(monitor: UsageMonitoringService) {
        self.monitor = monitor
        super.init()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func willSleep() {
        monitor?.suspendAutomaticRefresh()
    }

    @objc private func didWake() {
        monitor?.resumeAfterWake()
    }
}
