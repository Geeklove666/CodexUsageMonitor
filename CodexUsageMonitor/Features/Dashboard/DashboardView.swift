import AppKit
import Charts
import SwiftUI

struct DashboardView: View {
    @Bindable var monitor: UsageMonitoringService
    @State private var historyModel: DashboardHistoryModel
    @State private var interactionModel = DashboardInteractionModel()
    @State private var selection: DashboardSection = .overview
    @State private var chartRange: UsageHistoryRange = .week
    @State private var showsPlanReference = false
    @AppStorage(AppPreferences.Key.autoRefreshSeconds) private var autoRefreshSeconds = AutoRefreshFrequency.defaultValue.rawValue
    @AppStorage(AppPreferences.Key.notificationsEnabled) private var notificationsEnabled = false
    @AppStorage(AppPreferences.Key.notifyEvery20) private var notifyEvery20 = true
    @AppStorage(AppPreferences.Key.notifyReset) private var notifyReset = true
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(WebViewSession.self) private var webSession

    init(monitor: UsageMonitoringService, history: UsageHistoryStore) {
        self.monitor = monitor
        _historyModel = State(initialValue: DashboardHistoryModel(history: history))
    }

    var body: some View {
        NavigationSplitView {
            List(DashboardSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle("Codex 额度")
            .safeAreaInset(edge: .bottom) { sidebarFooter }
        } detail: {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: AppleUI.spacingXL) {
                        pageHeader
                        content
                    }
                    .padding(AppleUI.contentPadding)
                    .frame(maxWidth: 1080, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .navigationTitle(selection.title)
            .toolbar { toolbarContent }
        }
        .task {
            monitor.start()
            await interactionModel.loadNotificationAuthorization()
        }
        .task(id: "\(chartRange.rawValue)-\(monitor.historyRevision)") {
            historyModel.load(range: chartRange)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button { refreshFromDashboard() } label: {
                Label(monitor.isRefreshing ? "刷新中" : "刷新", systemImage: "arrow.clockwise")
            }
            .disabled(monitor.isRefreshing)
            .help("刷新额度来源，并同步刷新今日 Token")
            .accessibilityValue(monitor.isRefreshing ? "正在刷新" : "可刷新")
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusBadge(status: dashboardStatus)
            Text(monitor.snapshot.sourceDisplayName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .liquidGlassSurface(cornerRadius: AppleUI.cardRadius)
        .padding([.horizontal, .bottom], 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("数据状态，\(dashboardStatus.accessibilityText)")
    }

    private var pageHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                headerCopy
                Spacer(minLength: 24)
                if dashboardStatus != .live { StatusBadge(status: dashboardStatus) }
            }
            VStack(alignment: .leading, spacing: 10) {
                headerCopy
                if dashboardStatus != .live { StatusBadge(status: dashboardStatus) }
            }
        }
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(selection.title)
                .font(.largeTitle.weight(.semibold))
            Text(selection.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        let snapshot = DashboardQuotaSnapshot.make(snapshot: monitor.snapshot, status: dashboardStatus, now: monitor.now)
        switch selection {
        case .summary:
            summary(snapshot)
        case .overview:
            overview(snapshot)
        case .usageHistory:
            usageHistory(snapshot)
        case .alerts:
            alerts(snapshot)
        case .dataSource:
            dataSource(snapshot)
        case .settings:
            settings(snapshot)
        }
    }

    private func summary(_ snapshot: DashboardQuotaSnapshot) -> some View {
        let weeklyTokens = DailyTokenUsageBuilder.make(
            analytics: monitor.snapshot.analytics,
            historySamples: historyModel.weeklySamples,
            now: monitor.now
        )
        return VStack(alignment: .leading, spacing: 20) {
            if snapshot.status == .offline || snapshot.status == .unavailable {
                InlineNotice(status: snapshot.status, message: snapshot.statusMessage)
            }
            QuotaSummaryCard(snapshot: snapshot, velocity: historyModel.velocity)
            WeeklyTokenUsageCard(summary: weeklyTokens)
            ResetAndAlertsSection(
                snapshot: snapshot,
                notificationsEnabled: notificationsEnabled,
                notifyEvery20: notifyEvery20,
                notifyReset: notifyReset
            )
        }
    }

    private func overview(_ snapshot: DashboardQuotaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            if snapshot.status == .offline || snapshot.status == .unavailable {
                InlineNotice(status: snapshot.status, message: snapshot.statusMessage)
            }
            QuotaSummaryCard(snapshot: snapshot, velocity: historyModel.velocity)
            SecondaryAllowanceGrid(allowances: snapshot.secondaryAllowances)
            UsageTrendSection(
                range: $chartRange,
                status: snapshot.status,
                points: historyModel.points,
                errorMessage: historyModel.errorMessage
            )
            ResetAndAlertsSection(
                snapshot: snapshot,
                notificationsEnabled: notificationsEnabled,
                notifyEvery20: notifyEvery20,
                notifyReset: notifyReset
            )
            if snapshot.status != .live {
                DataQualityNote(snapshot: snapshot)
            }
        }
    }

    private func usageHistory(_ snapshot: DashboardQuotaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            UsageTrendSection(
                range: $chartRange,
                status: snapshot.status,
                points: historyModel.points,
                errorMessage: historyModel.errorMessage,
                expanded: true
            )
            AllowanceTable(allowances: snapshot.allAllowances)
        }
    }

    private func alerts(_ snapshot: DashboardQuotaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            InlineNotice(
                status: (snapshot.remainingPercent ?? 100) <= 0 ? .exhausted : snapshot.status,
                message: alertStatusMessage
            )
            AppleCard {
                VStack(spacing: 0) {
                    SettingsRow(
                        symbol: "bell.badge.fill",
                        color: AppleUI.accent,
                        title: "额度通知",
                        detail: interactionModel.notificationAuthorization.label
                    ) {
                        Toggle("启用额度通知", isOn: notificationsBinding).labelsHidden()
                    }
                    Divider().opacity(0.35).padding(.leading, 45)
                    SettingsRow(
                        symbol: "20.circle.fill",
                        color: AppleUI.warning,
                        title: "每消耗 20%",
                        detail: "跨过 20%、40%、60%、80% 和 100% 时提醒"
                    ) {
                        Toggle("每消耗 20%", isOn: $notifyEvery20)
                            .labelsHidden()
                            .disabled(!notificationsEnabled)
                    }
                    Divider().opacity(0.35).padding(.leading, 45)
                    SettingsRow(
                        symbol: "arrow.counterclockwise.circle.fill",
                        color: AppleUI.success,
                        title: "额度重置",
                        detail: "检测到新额度周期时提醒"
                    ) {
                        Toggle("额度重置", isOn: $notifyReset)
                            .labelsHidden()
                            .disabled(!notificationsEnabled)
                    }
                }
            }
        }
    }

    private func dataSource(_ snapshot: DashboardQuotaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            AppleCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "数据来源", subtitle: "当前完整面板使用真实监控快照。")
                    InfoRow(title: "额度来源", value: monitor.snapshot.sourceDisplayName, symbol: "externaldrive")
                    InfoRow(title: "新鲜度", value: snapshot.status.freshnessText(fetchedAt: monitor.snapshot.fetchedAt, now: monitor.now), symbol: "clock")
                    InfoRow(title: "来源状态", value: snapshot.status.label, symbol: snapshot.status.symbol)
                    InfoRow(
                        title: "网页备用来源",
                        value: webSession.hasLoadedUsagePage ? "已就绪" : "未启用（按需加载）",
                        symbol: "safari"
                    )
                    Divider()
                    HStack {
                        Button { openWindow(id: "login"); webSession.openUsagePage(); NSApp.activate() } label: {
                            Label("OpenAI 登录", systemImage: "person.crop.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .labelStyle(.titleAndIcon)
                        Button { Task { await monitor.refresh() } } label: {
                            Label("刷新真实来源", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .labelStyle(.titleAndIcon)
                    }
                }
            }

            DataSourceDiagnosticsCard(diagnostic: monitor.diagnostic)

            AppleCard {
                DisclosureGroup(isExpanded: $showsPlanReference) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(ChatGPTPlan.usBaseline) { plan in
                            PlanPriceRow(plan: plan)
                        }
                    }
                    .padding(.top, 12)
                } label: {
                    SectionHeading(title: "美区价格基准", subtitle: "展开查看套餐标记参考。")
                }
            }
        }
    }

    private func settings(_ snapshot: DashboardQuotaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            AppleCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(title: "刷新", subtitle: "真实数据源按所选频率自动刷新；手动刷新仍会立即执行。")
                    SettingsRow(symbol: "clock.arrow.circlepath", color: AppleUI.purple,
                                title: "自动刷新频率", detail: selectedRefreshFrequency.detail) {
                        Picker("自动刷新频率", selection: refreshFrequencyBinding) {
                            ForEach(AutoRefreshFrequency.allCases) { frequency in
                                Text(frequency.label).tag(frequency.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                        .accessibilityLabel("自动刷新频率")
                    }
                }
            }
            AppleCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(title: "数据完整性", subtitle: "界面不会把估算或缓存数据当作实时数据。")
                    InfoRow(title: "当前模式", value: snapshot.status.label, symbol: snapshot.status.symbol)
                    InfoRow(title: "不可用数值", value: "显示为不可用，不会显示为 0", symbol: "number")
                    Button { openSettings(); NSApp.activate() } label: {
                        Label("打开应用设置", systemImage: "gearshape")
                    }
                    .buttonStyle(GlassButtonStyle())
                }
            }
        }
    }

    private func refreshFromDashboard() {
        Task { await monitor.refresh() }
    }

    private var notificationsBinding: Binding<Bool> {
        Binding {
            notificationsEnabled
        } set: { enabled in
            if enabled {
                Task {
                    notificationsEnabled = await interactionModel.setNotificationsEnabled(true)
                }
            } else {
                notificationsEnabled = false
            }
        }
    }

    private var alertStatusMessage: String {
        interactionModel.alertStatusMessage(notificationsEnabled: notificationsEnabled)
    }

    private var dashboardStatus: UsagePresentationState {
        UsagePresentationState(
            snapshot: monitor.snapshot,
            failure: monitor.lastFailure,
            isRefreshing: monitor.isRefreshing
        )
    }

    private var selectedRefreshFrequency: AutoRefreshFrequency {
        AutoRefreshFrequency(rawValue: autoRefreshSeconds) ?? .defaultValue
    }

    private var refreshFrequencyBinding: Binding<Int> {
        Binding {
            AutoRefreshFrequency.sanitizedSeconds(autoRefreshSeconds)
        } set: { newValue in
            autoRefreshSeconds = AutoRefreshFrequency.sanitizedSeconds(newValue)
            monitor.restartRefreshLoop()
        }
    }
}
