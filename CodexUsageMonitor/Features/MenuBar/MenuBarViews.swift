import AppKit
import SwiftUI

enum MenuBarQuotaLevel: String, CaseIterable {
    case healthy
    case good
    case moderate
    case low
    case critical

    init(remainingPercentage: Double) {
        switch remainingPercentage {
        case 80...: self = .healthy
        case 60..<80: self = .good
        case 40..<60: self = .moderate
        case 20..<40: self = .low
        default: self = .critical
        }
    }

    var color: Color {
        switch self {
        case .healthy: Color(nsColor: .systemGreen)
        case .good: Color(nsColor: .systemBlue)
        case .moderate: Color(nsColor: .systemYellow)
        case .low: Color(nsColor: .systemOrange)
        case .critical: Color(nsColor: .systemRed)
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .healthy: "额度充足"
        case .good: "额度良好"
        case .moderate: "额度适中"
        case .low: "额度偏低"
        case .critical: "额度紧张"
        }
    }
}

struct MenuBarLabel: View {
    let snapshot: CodexUsageSnapshot
    let now: Date

    var body: some View {
        Text("Codex \(menuDetail)")
            .fontWeight(.semibold)
            .foregroundStyle(menuColor)
            .accessibilityLabel(accessibilityLabel)
    }

    private var menuDetail: String {
        guard let remaining = snapshot.primaryWindow?.remainingPercentage else { return "--%" }
        let prefix = snapshot.isEstimated ? "≈" : ""
        guard let reset = snapshot.primaryWindow?.resetsAt else { return "\(prefix)\(Int(remaining))%" }
        guard reset > now else { return "\(prefix)\(Int(remaining))% · 已过期" }
        return "\(prefix)\(Int(remaining))% · \(DurationFormatter.short(reset.timeIntervalSince(now)))"
    }

    private var quotaLevel: MenuBarQuotaLevel? {
        snapshot.primaryWindow?.remainingPercentage.map(MenuBarQuotaLevel.init)
    }

    private var menuColor: Color { quotaLevel?.color ?? .primary }

    private var accessibilityLabel: String {
        guard let quotaLevel else { return "Codex，暂无额度数据" }
        return "Codex，\(quotaLevel.accessibilityDescription)，\(menuDetail)"
    }
}

struct MenuPanelView: View {
    @Bindable var monitor: UsageMonitoringService
    var openDashboardAction: (() -> Void)?
    var openLoginAction: (() -> Void)?
    var openSettingsAction: (() -> Void)?
    @Environment(\.openWindow) private var openWindow
    @Environment(WebViewSession.self) private var webSession
    @Environment(\.openSettings) private var openSettings
    @AppStorage(LocalCodexSessionAuthorization.preferenceKey) private var localCodexLogin = false
    @AppStorage(LocalRealtimeTokenAuthorization.preferenceKey) private var localRealtimeTokenUsage = false
    @State private var showsBrowserChoice = false
    @State private var showsLocalCodexConsent = false
    @State private var showsRealtimeTokenConsent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            CompactUsageSummary(snapshot: monitor.snapshot, now: monitor.now)
            progressSection
            CompactAnalyticsSummary(
                analytics: monitor.snapshot.analytics,
                realtimeAuthorizationRequired: !localRealtimeTokenUsage
            )
            statusSection
            actions
        }
        .padding(12)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .background { MenuPanelRootBackground().allowsHitTesting(false) }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background { MenuPanelHostWindowConfigurator().frame(width: 0, height: 0) }
        .containerBackground(.clear, for: .window)
        .task {
            monitor.start()
            await monitor.refreshIfStaleForMenuOpen()
        }
        .alert("浏览器与应用登录相互独立", isPresented: $showsBrowserChoice) {
            Button("应用内登录") {
                showLogin()
            }
            Button("仅在浏览器查看") {
                NSWorkspace.shared.open(OfficialPageConfiguration.analyticsURL)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("浏览器 Cookie 不会同步到监控应用。若要刷新额度，请选择“应用内登录”。")
        }
        .alert("允许使用本机 Codex 登录读取额度？", isPresented: $showsLocalCodexConsent) {
            Button("授权并刷新") {
                localCodexLogin = true
                Task { await monitor.refresh() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("应用会调用 OpenAI 签名的本机 codex 命令读取额度数据；不会直接读取 auth.json，也不会保存 Token。")
        }
        .alert("允许读取本机实时 Token 事件？", isPresented: $showsRealtimeTokenConsent) {
            Button("授权并刷新") {
                localRealtimeTokenUsage = true
                Task { await monitor.refresh() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只读取 ~/.codex/sessions 中 token_count 事件的时间戳和累计数值，用于计算这台 Mac 今天的 Token；不会提取消息正文。")
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.3), radius: 4)
                .accessibilityLabel(monitor.status.label)
            VStack(alignment: .leading, spacing: 1) {
                Text("Codex Usage").font(.body.weight(.semibold))
                Text(SubscriptionTierFormatter.displayName(monitor.snapshot.planName))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            ProgressView().controlSize(.small).opacity(monitor.isRefreshing ? 1 : 0).frame(width: 16)
            SourceBadge(snapshot: monitor.snapshot, compact: true)
        }
    }

    private var progressSection: some View {
        AppleCard(padding: 11, cornerRadius: 16, shadowRadius: 8, shadowY: 2) {
            VStack(spacing: 9) {
                UsageProgressRow(title: "主额度", window: monitor.snapshot.primaryWindow, now: monitor.now,
                                 color: primaryQuotaColor, isEstimated: monitor.snapshot.isEstimated)
                if let secondary = monitor.snapshot.secondaryWindow {
                    Divider().opacity(0.3)
                    UsageProgressRow(title: "次级额度", window: secondary, now: monitor.now,
                                     color: AppleUI.purple, isEstimated: monitor.snapshot.isEstimated)
                }
            }
        }
    }

    private var statusSection: some View {
        MonitoringStatusBar(snapshot: monitor.snapshot, lastError: monitor.lastError, isRefreshing: monitor.isRefreshing)
    }

    private var actions: some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                Button { requestRefresh() } label: {
                    Label(monitor.isRefreshing ? "刷新中…" : "刷新",
                          systemImage: monitor.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CompactGlassButtonStyle())
                .disabled(monitor.isRefreshing)
                .help("同步刷新额度数据和今日 Token")

                Button {
                    showDashboard()
                } label: {
                    Label("完整面板", systemImage: "macwindow")
                        .symbolRenderingMode(.hierarchical)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CompactGlassButtonStyle())
                .help("打开完整用量面板")
            }

            VStack(spacing: 0) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible())], spacing: 0) {
                    utilityButton(localCodexActionTitle, symbol: "terminal.fill") {
                        if localCodexLogin {
                            Task { await monitor.refresh() }
                        } else {
                            showsLocalCodexConsent = true
                        }
                    }
                    utilityButton("OpenAI 登录", symbol: "person.crop.circle") {
                        showsBrowserChoice = true
                    }
                    utilityButton("设置", symbol: "gearshape") {
                        showSettings()
                    }
                    utilityButton("退出 Codex Usage", symbol: "power", destructive: true) {
                        NSApp.terminate(nil)
                    }
                }
            }
            .padding(4)
            .liquidGlassSurface(cornerRadius: 18)
            .background(Color(nsColor: .controlAccentColor).opacity(0.025), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.16), lineWidth: 0.6)
            }
        }
    }

    private func utilityButton(_ title: String, symbol: String, destructive: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(destructive ? AppleUI.danger : AppleUI.accent)
                    .frame(width: 18)
                Text(title).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(destructive ? AppleUI.danger : Color.primary.opacity(0.86))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(PanelUtilityButtonStyle())
        .help(title)
    }

    private var statusColor: Color {
        switch monitor.status {
        case .live: AppleUI.success
        case .cached, .estimated: AppleUI.purple
        case .refreshing: AppleUI.accent
        case .needsLogin, .degraded, .unavailable: AppleUI.warning
        }
    }

    private var primaryQuotaColor: Color {
        monitor.snapshot.primaryWindow?.remainingPercentage
            .map { MenuBarQuotaLevel(remainingPercentage: $0).color } ?? AppleUI.accent
    }

    private var localCodexActionTitle: String {
        localCodexLogin ? "刷新本机 Codex" : "启用本机 Codex"
    }

    private func requestRefresh() {
        Task { await monitor.refresh() }
    }

    private func showDashboard() {
        if let openDashboardAction {
            openDashboardAction()
        } else {
            openWindow(id: "dashboard")
            NSApp.activate()
        }
    }

    private func showLogin() {
        if let openLoginAction {
            openLoginAction()
        } else {
            openWindow(id: "login")
            webSession.openUsagePage()
            NSApp.activate()
        }
    }

    private func showSettings() {
        if let openSettingsAction {
            openSettingsAction()
        } else {
            openSettings()
            NSApp.activate()
        }
    }
}

private struct MenuPanelRootBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        shape
            .fill(Color(nsColor: reduceTransparency ? .windowBackgroundColor : .controlBackgroundColor))
            .overlay {
                shape.strokeBorder(
                    Color(nsColor: .separatorColor).opacity(contrast == .increased ? 0.45 : 0.20),
                    lineWidth: contrast == .increased ? 1 : 0.7
                )
            }
    }
}

private struct MenuPanelHostWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configure(view, attemptsRemaining: 8)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(nsView, attemptsRemaining: 4)
    }

    private func configure(_ view: NSView, attemptsRemaining: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30)) {
            guard let window = view.window else {
                if attemptsRemaining > 0 { configure(view, attemptsRemaining: attemptsRemaining - 1) }
                return
            }
            guard MenuPanelWindowConfigurationRegistry.markIfNeeded(windowNumber: window.windowNumber) else {
                return
            }

            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true

            clearBackgrounds(from: window.contentView)
            clearBackgrounds(from: window.contentView?.superview)
        }
    }

    private func clearBackgrounds(from view: NSView?) {
        guard let view else { return }
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        if let visualEffect = view as? NSVisualEffectView {
            visualEffect.blendingMode = .withinWindow
            visualEffect.state = .inactive
            visualEffect.isHidden = true
        }
        for subview in view.subviews {
            clearBackgrounds(from: subview)
        }
    }
}

@MainActor
private enum MenuPanelWindowConfigurationRegistry {
    private static var configuredWindowNumbers = Set<Int>()

    static func markIfNeeded(windowNumber: Int) -> Bool {
        guard windowNumber > 0 else { return true }
        return configuredWindowNumbers.insert(windowNumber).inserted
    }
}

struct AnalyticsSourceBadge: View {
    let analytics: CodexAnalyticsSnapshot
    var compact = false

    var body: some View {
        Label(analytics.sourceDisplayName, systemImage: "chart.bar.doc.horizontal")
            .font((compact ? Font.caption2 : Font.caption).weight(.semibold))
            .foregroundStyle(AppleUI.purple)
            .padding(.horizontal, compact ? 7 : 9)
            .padding(.vertical, compact ? 4 : 5)
            .background(AppleUI.purple.opacity(0.10), in: Capsule())
            .help("分析数据来源，与额度来源可能不同")
    }
}

struct SourceBadge: View {
    let snapshot: CodexUsageSnapshot
    var compact = false

    var body: some View {
        Label(displayName, systemImage: icon)
            .font((compact ? Font.caption2 : Font.caption).weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 5 : 6)
            .background(tint.opacity(0.09), in: Capsule())
            .accessibilityLabel("数据来源：\(snapshot.sourceKind.label)")
    }

    private var icon: String {
        snapshot.sourceKind == .unavailable ? "exclamationmark.triangle.fill" : snapshot.isEstimated ? "function" : "externaldrive.connected.to.line.below"
    }

    private var tint: Color {
        snapshot.sourceKind == .unavailable ? AppleUI.warning : snapshot.isEstimated ? AppleUI.purple : AppleUI.accent
    }

    private var displayName: String {
        guard compact else { return snapshot.sourceKind.label }
        return switch snapshot.sourceKind {
        case .localCodexSession: "本机 Codex"
        case .officialWebPage: "官方页面"
        case .verifiedOfficial: "官方数据"
        case .cachedSnapshot: "缓存"
        case .localEstimate: "本地估算"
        case .unavailable: "无法读取"
        }
    }
}
