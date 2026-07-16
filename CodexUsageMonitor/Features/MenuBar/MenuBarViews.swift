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
    @Environment(\.openWindow) private var openWindow
    @Environment(WebViewSession.self) private var webSession
    @Environment(\.openSettings) private var openSettings
    @AppStorage(LocalCodexSessionAuthorization.preferenceKey) private var reuseLocalCodexLogin = false
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
                realtimeAuthorizationRequired: reuseLocalCodexLogin && !localRealtimeTokenUsage
            )
            statusSection
            actions
        }
        .padding(12)
        .background { AppBackground().allowsHitTesting(false) }
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .task { monitor.start() }
        .alert("浏览器与应用登录相互独立", isPresented: $showsBrowserChoice) {
            Button("应用内登录") {
                openWindow(id: "login"); webSession.openUsagePage(); NSApp.activate()
            }
            Button("仅在浏览器查看") {
                NSWorkspace.shared.open(OfficialPageConfiguration.analyticsURL)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("浏览器 Cookie 不会同步到监控应用。若要刷新额度，请选择“应用内登录”。")
        }
        .alert("授权复用本机 Codex 登录？", isPresented: $showsLocalCodexConsent) {
            Button("授权并使用") {
                reuseLocalCodexLogin = true
                localRealtimeTokenUsage = true
                Task { await monitor.refresh() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("应用将通过本机 Codex 官方 app-server 读取套餐与额度，并只扫描 ~/.codex/sessions 中的 token_count 事件计算今日 Token；不会直接读取 auth.json、登录 Token、提示词、回复或代码正文。")
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
                Button { Task { await monitor.refresh() } } label: {
                    Label("刷新", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                }
                .buttonStyle(CompactGlassButtonStyle())
                .disabled(monitor.isRefreshing)
                .help("立即刷新额度数据")

                Button {
                    openWindow(id: "dashboard"); NSApp.activate()
                } label: {
                    Label("完整面板", systemImage: "macwindow")
                        .symbolRenderingMode(.hierarchical)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CompactGlassButtonStyle(tint: AppleUI.accent))
                .help("打开完整用量 Dashboard")
            }

            VStack(spacing: 0) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible())], spacing: 0) {
                    utilityButton(localCodexActionTitle, symbol: "terminal.fill") {
                        if reuseLocalCodexLogin {
                            if localRealtimeTokenUsage { Task { await monitor.refresh() } }
                            else { showsRealtimeTokenConsent = true }
                        } else {
                            showsLocalCodexConsent = true
                        }
                    }
                    utilityButton("浏览器查看", symbol: "safari") {
                        showsBrowserChoice = true
                    }
                    utilityButton("设置", symbol: "gearshape") {
                        openSettings(); NSApp.activate()
                    }
                    utilityButton("退出 Codex Usage", symbol: "power", destructive: true) {
                        NSApp.terminate(nil)
                    }
                }
            }
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(.primary.opacity(0.06), lineWidth: 0.7)
            }
        }
    }

    private func utilityButton(_ title: String, symbol: String, destructive: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).symbolRenderingMode(.hierarchical)
                Text(title).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(destructive ? AppleUI.danger : Color.primary)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 31)
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
        reuseLocalCodexLogin && !localRealtimeTokenUsage ? "启用今日 Token" : "复用本机 Codex"
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
