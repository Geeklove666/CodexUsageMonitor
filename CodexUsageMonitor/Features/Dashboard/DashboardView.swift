import AppKit
import Charts
import SwiftUI

struct DashboardView: View {
    @Bindable var monitor: UsageMonitoringService
    let history: UsageHistoryStore
    @State private var selection: DashboardSection = .overview
    @State private var chartRange: DemoHistoryRange = .week
    @AppStorage(UsageMonitoringService.refreshIntervalPreferenceKey) private var autoRefreshSeconds = AutoRefreshFrequency.defaultValue.rawValue
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(WebViewSession.self) private var webSession

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
                    VStack(alignment: .leading, spacing: 24) {
                        pageHeader
                        content
                    }
                    .padding(24)
                    .frame(maxWidth: 1080, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .navigationTitle(selection.title)
            .toolbar { toolbarContent }
        }
        .task { monitor.start() }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button { refreshFromDashboard() } label: {
                Label(monitor.isRefreshing ? "刷新中" : "刷新", systemImage: "arrow.clockwise")
            }
            .disabled(monitor.isRefreshing)
            .help("刷新额度来源，并同步刷新今日 Token")
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
        .liquidGlassSurface(cornerRadius: 12)
        .padding([.horizontal, .bottom], 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("数据状态，\(dashboardStatus.accessibilityText)")
    }

    private var pageHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                headerCopy
                Spacer(minLength: 24)
                StatusBadge(status: dashboardStatus)
            }
            VStack(alignment: .leading, spacing: 10) {
                headerCopy
                StatusBadge(status: dashboardStatus)
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
        let snapshot = DemoQuotaSnapshot.make(snapshot: monitor.snapshot, status: dashboardStatus, now: monitor.now)
        switch selection {
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

    private func overview(_ snapshot: DemoQuotaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            if snapshot.status == .offline || snapshot.status == .unavailable {
                InlineNotice(status: snapshot.status, message: snapshot.statusMessage)
            }
            DemoQuotaSummaryCard(snapshot: snapshot)
            SecondaryAllowanceGrid(allowances: snapshot.secondaryAllowances)
            UsageTrendSection(range: $chartRange, status: snapshot.status)
            ResetAndAlertsSection(snapshot: snapshot)
            DataQualityNote(snapshot: snapshot)
        }
    }

    private func usageHistory(_ snapshot: DemoQuotaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            UsageTrendSection(range: $chartRange, status: snapshot.status, expanded: true)
            DemoAllowanceTable(allowances: snapshot.allAllowances)
        }
    }

    private func alerts(_ snapshot: DemoQuotaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            InlineNotice(status: (snapshot.remainingPercent ?? 100) <= 5 ? .exhausted : .cached,
                         message: "告警规则使用与额度数据一致的状态语言。")
            ForEach(DemoAlertRule.examples) { rule in
                AppleCard {
                    HStack(spacing: 14) {
                        Image(systemName: rule.symbol)
                            .foregroundStyle(rule.enabled ? rule.color : .secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rule.title).font(.headline)
                            Text(rule.detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("已启用", isOn: .constant(rule.enabled))
                            .labelsHidden()
                    }
                }
            }
        }
    }

    private func dataSource(_ snapshot: DemoQuotaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            AppleCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "数据来源", subtitle: "当前完整面板使用真实监控快照。")
                    InfoRow(title: "额度来源", value: monitor.snapshot.sourceDisplayName, symbol: "externaldrive")
                    InfoRow(title: "新鲜度", value: snapshot.status.freshnessText, symbol: "clock")
                    InfoRow(title: "来源状态", value: snapshot.status.label, symbol: snapshot.status.symbol)
                    InfoRow(title: "真实会话", value: webSession.hasLoadedUsagePage ? "OpenAI 页面已加载" : "OpenAI 页面未加载", symbol: "person.crop.circle")
                    Divider()
                    HStack {
                        Button { openWindow(id: "login"); webSession.openUsagePage(); NSApp.activate() } label: {
                            Label("OpenAI 登录", systemImage: "person.crop.circle")
                        }
                        .buttonStyle(GlassButtonStyle(tint: AppleUI.accent))
                        Button { Task { await monitor.refresh() } } label: {
                            Label("刷新真实来源", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(GlassButtonStyle())
                    }
                }
            }

            DataSourceDiagnosticsCard(diagnostic: monitor.diagnostic)

            AppleCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(title: "美区价格基准", subtitle: "用于套餐标记的参考。")
                    ForEach(ChatGPTPlan.usBaseline) { plan in
                        PlanPriceRow(plan: plan)
                    }
                }
            }
        }
    }

    private func settings(_ snapshot: DemoQuotaSnapshot) -> some View {
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
                    SectionHeading(title: "显示", subtitle: "使用带可访问性标签的原生控件。")
                    Toggle("在菜单栏显示状态", isOn: .constant(true))
                    Toggle("减少非必要动画", isOn: .constant(false))
                    Toggle("使用紧凑菜单栏标签", isOn: .constant(true))
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

    private var dashboardStatus: DemoDataStatus {
        switch monitor.status {
        case .refreshing:
            return .loading
        case .live:
            if (monitor.snapshot.primaryWindow?.remainingPercentage ?? 100) <= 0 { return .exhausted }
            return .live
        case .cached:
            return .cached
        case .estimated:
            return .estimated
        case .needsLogin:
            return .unavailable
        case .degraded:
            return monitor.snapshot.primaryWindow == nil ? .unavailable : .cached
        case .unavailable:
            return .unavailable
        }
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

private struct DataSourceDiagnosticsCard: View {
    let diagnostic: DataSourceDiagnostic

    var body: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(title: "真实刷新诊断", subtitle: "最近一次真实刷新链路，已脱敏。")
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
                    GridRow {
                        Text("来源").foregroundStyle(.secondary)
                        Text("状态").foregroundStyle(.secondary)
                        Text("耗时").foregroundStyle(.secondary)
                        Text("结果").foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    Divider().gridCellColumns(4)
                    if diagnostic.attempts.isEmpty {
                        GridRow {
                            Text("尚无刷新记录")
                                .foregroundStyle(.secondary)
                                .gridCellColumns(4)
                        }
                    } else {
                        ForEach(diagnostic.attempts) { attempt in
                            GridRow {
                                Text(attempt.sourceLabel)
                                Text(attempt.availability)
                                    .foregroundStyle(.secondary)
                                Text(attempt.duration.map { String(format: "%.2fs", $0) } ?? "--")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                Label(attempt.succeeded ? "成功" : (attempt.error ?? "跳过"),
                                      systemImage: attempt.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(attempt.succeeded ? AppleUI.success : AppleUI.warning)
                            }
                            .font(.subheadline)
                        }
                    }
                }

                Divider().opacity(0.28)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 18) { diagnosticSummaryRows }
                    VStack(alignment: .leading, spacing: 8) { diagnosticSummaryRows }
                }
            }
        }
    }

    @ViewBuilder
    private var diagnosticSummaryRows: some View {
        Label("触发：\(diagnostic.lastRefreshReason ?? "尚无")", systemImage: "bolt")
        Label("当前：\(diagnostic.activeIdentifier)", systemImage: "externaldrive")
        Label("完整度：\(Int(diagnostic.fieldCompleteness * 100))%", systemImage: "checklist")
        if let duration = diagnostic.requestDuration {
            Label(String(format: "耗时 %.2fs", duration), systemImage: "timer")
        }
    }
}

private struct DemoQuotaSummaryCard: View {
    let snapshot: DemoQuotaSnapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AppleCard {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 24) {
                    primaryCopy
                    progressColumn
                }
                VStack(alignment: .leading, spacing: 16) {
                    primaryCopy
                    progressColumn
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var primaryCopy: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                StatusBadge(status: snapshot.status)
            }
            Text(snapshot.planDisplayName)
                .font(.headline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(snapshot.remainingText)
                    .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                Text("剩余")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Text(snapshot.resetText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 270, alignment: .leading)
    }

    private var progressColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            LinearQuotaProgress(value: snapshot.remainingPercent,
                                status: snapshot.status,
                                label: "主额度",
                                resetText: snapshot.resetText)
            Text(snapshot.statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SecondaryAllowanceGrid: View {
    let allowances: [DemoAllowance]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "其他额度", subtitle: "每个重置窗口单独展示。")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                ForEach(allowances) { allowance in
                    AppleCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(allowance.name).font(.headline)
                                Spacer()
                                StatusBadge(status: allowance.status)
                            }
                            Text(allowance.remainingText)
                                .font(.title3.monospacedDigit().weight(.semibold))
                            Text(allowance.resetText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            LinearQuotaProgress(value: allowance.remainingPercent,
                                                status: allowance.status,
                                                label: allowance.name,
                                                resetText: allowance.resetText)
                        }
                    }
                }
            }
        }
    }
}

private struct UsageTrendSection: View {
    @Binding var range: DemoHistoryRange
    let status: DemoDataStatus
    var expanded = false

    var body: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        SectionHeading(title: "使用趋势", subtitle: "基于当前状态的趋势示意。")
                        Spacer()
                        rangePicker
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeading(title: "使用趋势", subtitle: "基于当前状态的趋势示意。")
                        rangePicker
                    }
                }
                Chart(DemoTrendPoint.points(for: range, status: status)) { point in
                    LineMark(x: .value("时间", point.date), y: .value("剩余额度", point.remaining))
                        .foregroundStyle(AppleUI.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.25, lineCap: .round, dash: status == .estimated ? [5, 4] : []))
                    AreaMark(x: .value("时间", point.date), y: .value("剩余额度", point.remaining))
                        .foregroundStyle(AppleUI.accent.opacity(0.12))
                    if point.isReset {
                        RuleMark(x: .value("重置", point.date))
                            .foregroundStyle(.secondary.opacity(0.45))
                            .annotation(position: .top, alignment: .leading) {
                                Text("重置")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.16))
                        AxisValueLabel { if let number = value.as(Int.self) { Text("\(number)%") } }
                    }
                }
                .frame(height: expanded ? 320 : 220)
                .accessibilityLabel("使用趋势")
                .accessibilityValue(status.accessibilityText)
                Text("趋势用于辅助观察当前状态；重置标记表示服务方定义的新窗口开始。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rangePicker: some View {
        Picker("范围", selection: $range) {
            ForEach(DemoHistoryRange.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 260)
        .help("选择历史范围")
    }
}

private struct ResetAndAlertsSection: View {
    let snapshot: DemoQuotaSnapshot

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                resetCard
                alertCard
            }
            VStack(spacing: 16) {
                resetCard
                alertCard
            }
        }
    }

    private var resetCard: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(title: "重置计划")
                ForEach(snapshot.allAllowances) { allowance in
                    InfoRow(title: allowance.name, value: allowance.resetText, symbol: "arrow.counterclockwise")
                }
            }
        }
    }

    private var alertCard: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(title: "启用中的告警")
                InfoRow(title: "20% 预警", value: (snapshot.remainingPercent ?? 100) <= 20 ? "已触发" : "已待命", symbol: "exclamationmark.triangle")
                InfoRow(title: "5% 紧急", value: (snapshot.remainingPercent ?? 100) <= 5 ? "已触发" : "已待命", symbol: "xmark.octagon")
            }
        }
    }
}

private struct DataQualityNote: View {
    let snapshot: DemoQuotaSnapshot

    var body: some View {
        InlineNotice(status: snapshot.status, message: snapshot.dataQualityText)
    }
}

private struct DemoAllowanceTable: View {
    let allowances: [DemoAllowance]

    var body: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "额度表", subtitle: "按当前快照中的额度窗口展示。")
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                    GridRow {
                        Text("额度").foregroundStyle(.secondary)
                        Text("已用 / 剩余").foregroundStyle(.secondary)
                        Text("重置").foregroundStyle(.secondary)
                        Text("状态").foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    Divider().gridCellColumns(4)
                    ForEach(allowances) { allowance in
                        GridRow {
                            Text(allowance.name).font(.body)
                            Text("\(allowance.usedText) / \(allowance.remainingText)").monospacedDigit()
                            Text(allowance.resetText)
                            StatusBadge(status: allowance.status)
                        }
                        .font(.body)
                    }
                }
            }
        }
    }
}

private struct InlineNotice: View {
    let status: DemoDataStatus
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: status.symbol)
                .foregroundStyle(status.color)
                .frame(width: 20)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .background(status.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(status.color.opacity(0.18), lineWidth: 0.75)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(status.label)。\(message)")
    }
}

private struct LinearQuotaProgress: View {
    let value: Double?
    let status: DemoDataStatus
    let label: String
    let resetText: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(value.map { "\(Int($0))%" } ?? "不可用")
                    .font(.caption.monospacedDigit().weight(.semibold))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.secondary.opacity(0.16))
                    if let value {
                        Capsule()
                            .fill(status.progressColor)
                            .frame(width: proxy.size.width * min(max(value / 100, 0), 1))
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: value)
                    }
                }
            }
            .frame(height: 7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value.map { "剩余 \(Int($0))%；\(resetText)；\(status.accessibilityText)" } ?? "数据不可用；\(status.accessibilityText)")
    }
}

private struct StatusBadge: View {
    let status: DemoDataStatus

    var body: some View {
        Label(status.label, systemImage: status.symbol)
            .font(.caption.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.10), in: Capsule())
            .accessibilityLabel(status.accessibilityText)
    }
}

private struct InfoRow: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(title)
            Spacer(minLength: 16)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .font(.body)
        .accessibilityElement(children: .combine)
    }
}

private struct PlanPriceRow: View {
    let plan: ChatGPTPlan

    var body: some View {
        HStack(spacing: 12) {
            Text(plan.name)
                .font(.body.weight(.semibold))
                .frame(width: 92, alignment: .leading)
            Text(plan.price)
                .font(.body.monospacedDigit())
                .frame(width: 120, alignment: .leading)
            Text(plan.codexAllowance)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text("美区基准")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private enum DashboardSection: String, CaseIterable, Identifiable {
    case overview
    case usageHistory
    case alerts
    case dataSource
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "概览"
        case .usageHistory: "使用历史"
        case .alerts: "告警"
        case .dataSource: "数据来源"
        case .settings: "设置"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: "集中查看额度、重置窗口与数据新鲜度。"
        case .usageHistory: "带可访问趋势图和表格视图的本地历史。"
        case .alerts: "额度变化的阈值与提醒规则。"
        case .dataSource: "来源状态、时间戳与套餐价格上下文。"
        case .settings: "第一版界面的显示与数据完整性偏好。"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.50percent"
        case .usageHistory: "chart.xyaxis.line"
        case .alerts: "bell.badge"
        case .dataSource: "externaldrive.connected.to.line.below"
        case .settings: "gearshape"
        }
    }
}

private enum DemoDataStatus: String {
    case live
    case loading
    case cached
    case estimated
    case offline
    case unavailable
    case exhausted

    var label: String {
        switch self {
        case .live: "数据正常"
        case .loading: "加载中"
        case .cached: "4 分钟前更新"
        case .estimated: "估算"
        case .offline: "离线"
        case .unavailable: "数据不可用"
        case .exhausted: "已耗尽"
        }
    }

    var freshnessText: String {
        switch self {
        case .live: "刚刚更新"
        case .loading: "正在加载初始数据"
        case .cached: "4 分钟前更新"
        case .estimated: "根据本机活动估算"
        case .offline: "离线 · 显示缓存数据"
        case .unavailable: "没有可用数据来源"
        case .exhausted: "额度已耗尽"
        }
    }

    var accessibilityText: String { label }

    var symbol: String {
        switch self {
        case .live: "checkmark.circle.fill"
        case .loading: "arrow.triangle.2.circlepath"
        case .cached: "externaldrive.fill.badge.checkmark"
        case .estimated: "function"
        case .offline: "wifi.slash"
        case .unavailable: "questionmark.folder"
        case .exhausted: "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .live: AppleUI.success
        case .loading: AppleUI.accent
        case .cached: .secondary
        case .estimated: AppleUI.warning
        case .offline: AppleUI.warning
        case .unavailable: .secondary
        case .exhausted: AppleUI.danger
        }
    }

    var progressColor: Color {
        switch self {
        case .live: AppleUI.accent
        case .exhausted: AppleUI.danger
        case .estimated, .offline: AppleUI.warning
        case .unavailable: .secondary
        default: AppleUI.accent
        }
    }
}

private struct DemoQuotaSnapshot {
    let status: DemoDataStatus
    let planDisplayName: String
    let remainingPercent: Double?
    let usedPercent: Double?
    let resetText: String
    let statusMessage: String
    let dataQualityText: String
    let secondaryAllowances: [DemoAllowance]

    var remainingText: String {
        guard let remainingPercent else { return "不可用" }
        return "\(Int(remainingPercent))%"
    }

    var allAllowances: [DemoAllowance] {
        [
            DemoAllowance(name: "主额度", remainingPercent: remainingPercent, usedPercent: usedPercent, resetText: resetText, status: status)
        ] + secondaryAllowances
    }

    static func make(snapshot: CodexUsageSnapshot, status: DemoDataStatus, now: Date) -> DemoQuotaSnapshot {
        let primary = snapshot.primaryWindow
        let remaining = primary?.remainingPercentage
        let resetText = primary?.resetsAt.map { DurationFormatter.short($0.timeIntervalSince(now)) + " 后重置" }
            ?? primary?.durationDescription
            ?? "重置时间不可用"
        let sourcePrefix = snapshot.isEstimated ? "估算" : (snapshot.isCached ? "缓存" : snapshot.sourceDisplayName)
        return DemoQuotaSnapshot(
            status: status,
            planDisplayName: SubscriptionTierFormatter.displayName(snapshot.planName),
            remainingPercent: remaining,
            usedPercent: primary?.usedPercentage,
            resetText: resetText,
            statusMessage: snapshot.diagnosticMessage ?? "\(sourcePrefix) · \(status.freshnessText)",
            dataQualityText: dataQualityText(snapshot: snapshot, status: status),
            secondaryAllowances: secondary(snapshot: snapshot, status: status, now: now)
        )
    }

    private static func secondary(snapshot: CodexUsageSnapshot, status: DemoDataStatus, now: Date) -> [DemoAllowance] {
        var values: [DemoAllowance] = []
        if let secondary = snapshot.secondaryWindow {
            values.append(DemoAllowance(
                name: "其他额度",
                remainingPercent: secondary.remainingPercentage,
                usedPercent: secondary.usedPercentage,
                resetText: secondary.resetsAt.map { DurationFormatter.short($0.timeIntervalSince(now)) + " 后重置" }
                    ?? secondary.durationDescription
                    ?? "重置时间不可用",
                status: status
            ))
        }
        if let credits = snapshot.credits {
            values.append(DemoAllowance(
                name: "Credits",
                remainingPercent: nil,
                usedPercent: nil,
                resetText: CreditsDisplay.value(credits),
                status: status,
                valueOverride: "剩余 \(CreditsDisplay.value(credits))"
            ))
        }
        if let resetAllowance = snapshot.resetAllowance {
            values.append(DemoAllowance(
                name: "使用限额重置",
                remainingPercent: nil,
                usedPercent: nil,
                resetText: "可用 \(resetAllowance.availableCount) 次",
                status: status,
                valueOverride: "可用 \(resetAllowance.availableCount) 次"
            ))
        }
        return values
    }

    private static func dataQualityText(snapshot: CodexUsageSnapshot, status: DemoDataStatus) -> String {
        if snapshot.isCached { return "当前显示缓存数据，界面会保留来源和新鲜度。" }
        if snapshot.isEstimated { return "当前显示本地估算，数值会保留估算标识。" }
        switch status {
        case .live: return "当前显示真实数据源返回的最新快照。"
        case .loading: return "正在读取数据，已有快照会暂时保留。"
        case .unavailable: return "当前没有可用数据，未知值不会显示为 0。"
        case .exhausted: return "当前额度已耗尽，等待服务方定义的重置窗口。"
        case .cached, .estimated, .offline:
            return status.freshnessText
        }
    }
}

private struct DemoAllowance: Identifiable {
    let id = UUID()
    let name: String
    let remainingPercent: Double?
    let usedPercent: Double?
    let resetText: String
    let status: DemoDataStatus
    var valueOverride: String?

    var remainingText: String { valueOverride ?? remainingPercent.map { "剩余 \(Int($0))%" } ?? "不可用" }
    var usedText: String { usedPercent.map { "已用 \(Int($0))%" } ?? "不可用" }
}

private enum DemoHistoryRange: String, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: Self { self }
    var label: String {
        switch self {
        case .day: "24 小时"
        case .week: "7 天"
        case .month: "30 天"
        }
    }
}

private struct DemoTrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let remaining: Double
    let isReset: Bool

    static func points(for range: DemoHistoryRange, status: DemoDataStatus) -> [DemoTrendPoint] {
        let count = range == .day ? 12 : range == .week ? 14 : 18
        let step: TimeInterval = range == .day ? 7_200 : range == .week ? 43_200 : 144_000
        let base = Date.now.addingTimeInterval(-step * Double(count - 1))
        return (0..<count).map { index in
            let reset = index == count / 2
            let raw = reset ? 92 : 92 - Double((index * 6) % 74)
            let adjusted: Double
            switch status {
            case .live: adjusted = raw
            case .exhausted: adjusted = max(0, raw - 90)
            case .unavailable: adjusted = 0
            case .loading: adjusted = 50
            case .estimated: adjusted = max(12, raw - 18)
            case .offline: adjusted = max(18, raw - 32)
            case .cached: adjusted = raw
            }
            return DemoTrendPoint(date: base.addingTimeInterval(step * Double(index)), remaining: adjusted, isReset: reset)
        }
    }
}

private struct DemoAlertRule: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let symbol: String
    let color: Color
    let enabled: Bool

    static let examples = [
        DemoAlertRule(title: "剩余 20% 预警", detail: "主额度低于 20% 时提醒。", symbol: "exclamationmark.triangle.fill", color: AppleUI.warning, enabled: true),
        DemoAlertRule(title: "剩余 5% 紧急提醒", detail: "额度耗尽前提醒。", symbol: "xmark.octagon.fill", color: AppleUI.danger, enabled: true),
        DemoAlertRule(title: "重置完成", detail: "服务方定义的重置窗口刷新后提醒。", symbol: "arrow.counterclockwise.circle.fill", color: AppleUI.accent, enabled: false)
    ]
}

private struct ChatGPTPlan: Identifiable {
    let id = UUID()
    let name: String
    let price: String
    let codexAllowance: String

    static let usBaseline = [
        ChatGPTPlan(name: "Free", price: "$0/月", codexAllowance: "有限 Codex 访问"),
        ChatGPTPlan(name: "Go", price: "$8/月", codexAllowance: "轻量 Codex 任务"),
        ChatGPTPlan(name: "Plus", price: "$20/月", codexAllowance: "更高 Codex 用量"),
        ChatGPTPlan(name: "Pro 5x", price: "$100/月", codexAllowance: "约为 Plus 的 5x 用量"),
        ChatGPTPlan(name: "Pro 20x", price: "$200/月", codexAllowance: "约为 Plus 的 20x 用量"),
        ChatGPTPlan(name: "Business", price: "$20/用户/月（年付）", codexAllowance: "团队套餐；月付 $25/用户/月"),
        ChatGPTPlan(name: "Enterprise / Edu", price: "联系销售", codexAllowance: "工作区管理的限制")
    ]
}
