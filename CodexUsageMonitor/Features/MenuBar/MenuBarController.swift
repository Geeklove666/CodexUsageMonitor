import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let monitor: UsageMonitoringService
    private let history: UsageHistoryStore
    private let webSession: WebViewSession
    private let statusItem: NSStatusItem
    private var panel: TransparentMenuPanel?
    private var dashboardWindow: NSWindow?
    private var loginWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var statusTimer: Timer?
    private var outsideClickMonitor: Any?
    private var lastRenderedMenuDetail: String?

    init(monitor: UsageMonitoringService, history: UsageHistoryStore, webSession: WebViewSession) {
        self.monitor = monitor
        self.history = history
        self.webSession = webSession
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
        startStatusUpdates()
        monitor.displayStateDidChange = { [weak self] in self?.updateStatusTitle() }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePanel)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .noImage
        updateStatusTitle(force: true)
    }

    private func startStatusUpdates() {
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.monitor.updateClock() }
        }
        RunLoop.main.add(timer, forMode: .common)
        statusTimer = timer
    }

    private func updateStatusTitle(force: Bool = false) {
        guard let button = statusItem.button else { return }
        let detail = menuDetail
        guard force || detail != lastRenderedMenuDetail else { return }
        lastRenderedMenuDetail = detail
        button.attributedTitle = NSAttributedString(
            string: "Codex \(detail)",
            attributes: [
                .font: NSFont.menuBarFont(ofSize: 0),
                .foregroundColor: NSColor.labelColor
            ]
        )
        button.toolTip = "Codex Usage Monitor"
        button.setAccessibilityLabel("Codex，\(detail)")
    }

    private var menuDetail: String {
        let snapshot = monitor.snapshot
        guard let remaining = snapshot.primaryWindow?.remainingPercentage else { return "--%" }
        let prefix = snapshot.isEstimated ? "≈" : ""
        guard let reset = snapshot.primaryWindow?.resetsAt else { return "\(prefix)\(Int(remaining))%" }
        guard reset > monitor.now else { return "\(prefix)\(Int(remaining))% · 已过期" }
        return "\(prefix)\(Int(remaining))% · \(DurationFormatter.short(reset.timeIntervalSince(monitor.now)))"
    }

    @objc private func togglePanel() {
        if panel?.isVisible == true {
            closePanel()
        } else {
            openPanel()
        }
    }

    private func openPanel() {
        Task { await monitor.refreshIfStaleForMenuOpen() }
        let root = MenuPanelView(
            monitor: monitor,
            history: history,
            openDashboardAction: { [weak self] in self?.openDashboard() },
            openLoginAction: { [weak self] in self?.openLogin() },
            openSettingsAction: { [weak self] in self?.openSettings() }
        )
        .environment(webSession)

        let hostingView = NSHostingView(rootView: root)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let fitting = hostingView.fittingSize
        let contentSize = NSSize(width: 360, height: max(1, fitting.height))
        let panel = panel ?? makePanel()
        panel.contentView = hostingView
        panel.setContentSize(contentSize)
        position(panel, size: contentSize)
        panel.orderFrontRegardless()
        self.panel = panel
        installOutsideClickMonitor()
    }

    private func makePanel() -> TransparentMenuPanel {
        let panel = TransparentMenuPanel(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        return panel
    }

    private func position(_ panel: NSPanel, size: NSSize) {
        guard let button = statusItem.button, let buttonWindow = button.window else {
            panel.setFrame(NSRect(origin: .zero, size: size), display: true)
            return
        }
        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrame = buttonWindow.convertToScreen(buttonFrameInWindow)
        let screenFrame = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var x = buttonFrame.midX - size.width / 2
        x = min(max(x, screenFrame.minX + 8), screenFrame.maxX - size.width - 8)
        let y = max(screenFrame.minY + 8, buttonFrame.minY - size.height - 6)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private func installOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closePanel() }
        }
    }

    private func closePanel() {
        panel?.orderOut(nil)
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    private func openDashboard() {
        closePanel()
        if dashboardWindow == nil {
            dashboardWindow = makeWindow(
                title: "Codex Usage",
                size: NSSize(width: 960, height: 680),
                content: DashboardView(monitor: monitor, history: history)
                    .environment(webSession)
            )
        }
        show(dashboardWindow)
    }

    private func openLogin() {
        closePanel()
        webSession.openUsagePage()
        if loginWindow == nil {
            loginWindow = makeWindow(
                title: "Codex Usage 登录",
                size: NSSize(width: 760, height: 600),
                content: LoginView().environment(webSession)
            )
        }
        show(loginWindow)
    }

    private func openSettings() {
        closePanel()
        if settingsWindow == nil {
            settingsWindow = makeWindow(
                title: "Codex Usage Monitor Settings",
                size: NSSize(width: 720, height: 560),
                content: SettingsView(history: history, monitor: monitor).environment(webSession)
            )
        }
        show(settingsWindow)
    }

    private func makeWindow<Content: View>(title: String, size: NSSize, content: Content) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = NSHostingView(rootView: content)
        window.center()
        window.isReleasedWhenClosed = false
        return window
    }

    private func show(_ window: NSWindow?) {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private final class TransparentMenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
