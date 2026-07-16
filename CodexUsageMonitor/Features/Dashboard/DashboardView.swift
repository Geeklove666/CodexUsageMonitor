import AppKit
import Charts
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Bindable var monitor: UsageMonitoringService
    let history: UsageHistoryStore
    @State private var range: HistoryRange = .day
    @State private var points: [UsageSnapshotEntity] = []
    @State private var selection: DashboardSection = .overview
    @State private var showsTechnicalDiagnostics = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(WebViewSession.self) private var webSession

    var body: some View {
        NavigationSplitView {
            List(DashboardSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.body.weight(selection == section ? .semibold : .regular))
                    .padding(.vertical, 5)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle("Codex Usage")
            .safeAreaInset(edge: .bottom) { sidebarStatus }
        } detail: {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        dashboardHeader
                        Group {
                            switch selection {
                            case .overview: overview
                            case .analytics: analyticsContent
                            case .history: historyContent
                            case .diagnostics: diagnosticsContent
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    .padding(22)
                    .frame(maxWidth: 1040, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.36, bounce: 0.08), value: selection)
        }
        .task { monitor.start(); loadPoints() }
        .onChange(of: monitor.historyRevision) { loadPoints() }
    }

    private var sidebarStatus: some View {
        HStack(spacing: 9) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(monitor.status.label)
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .accessibilityElement(children: .combine)
    }

    private var dashboardHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                dashboardTitle
                Spacer(minLength: 20)
                headerActions
            }
            VStack(alignment: .leading, spacing: 12) {
                dashboardTitle
                headerActions
            }
        }
    }

    private var dashboardTitle: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(selection.title).font(.system(size: 30, weight: .bold))
            Text("\(SubscriptionTierFormatter.displayName(monitor.snapshot.planName)) · \(RelativeFormatter.text(monitor.snapshot.fetchedAt))")
                .font(.subheadline).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 7) { sourceMetadata }
                VStack(alignment: .leading, spacing: 6) { sourceMetadata }
            }
        }
    }

    private var headerActions: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).opacity(monitor.isRefreshing ? 1 : 0).frame(width: 16)
            Button {
                Task { await monitor.refresh(); loadPoints() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(GlassButtonStyle())
            .disabled(monitor.isRefreshing)
            .help("立即刷新额度数据与历史趋势")
        }
    }

    @ViewBuilder private var sourceMetadata: some View {
        SourceBadge(snapshot: monitor.snapshot, compact: true)
        if let analytics = monitor.snapshot.analytics {
            AnalyticsSourceBadge(analytics: analytics, compact: true)
        }
    }

    @ViewBuilder private var overview: some View {
        UsageHeroCard(snapshot: monitor.snapshot, now: monitor.now)

        if let analytics = monitor.snapshot.analytics {
            AnalyticsOverviewCard(analytics: analytics) { selection = .analytics }
        }

        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "额度详情", subtitle: "周期、重置时间与数据可信状态")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 18)], spacing: 18) {
                UsageCard(title: "主额度", window: monitor.snapshot.primaryWindow, snapshot: monitor.snapshot, now: monitor.now)
                if let secondary = monitor.snapshot.secondaryWindow {
                    UsageCard(title: "次级额度", window: secondary, snapshot: monitor.snapshot, now: monitor.now)
                }
            }
        }

        DashboardAdaptiveColumns {
            overviewTrend
        } trailing: {
            OverviewStatusCard(snapshot: monitor.snapshot, lastError: monitor.lastError) {
                selection = .diagnostics
            }
        }
    }

    @ViewBuilder private var analyticsContent: some View {
        if let analytics = monitor.snapshot.analytics {
            AnalyticsDashboard(analytics: analytics)
        } else {
            AppleCard {
                ContentUnavailableView("暂无分析数据", systemImage: "chart.bar.xaxis",
                    description: Text("登录后打开 Codex 分析页面并刷新，应用会读取官方页面已经加载的真实统计。"))
            }
        }
    }

    private var overviewTrend: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    SectionHeading(title: "额度趋势", subtitle: "本机保存的真实历史快照")
                    Spacer()
                    Button("查看历史") { selection = .history }
                        .buttonStyle(GlassButtonStyle())
                        .help("打开完整历史趋势")
                }
                UsageTrendChart(points: points).frame(height: 220)
            }
        }
    }

    @ViewBuilder private var historyContent: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 20) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center) {
                        historyHeading
                        Spacer(minLength: 20)
                        rangePicker
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        historyHeading
                        rangePicker
                    }
                }
                UsageTrendChart(points: points).frame(minHeight: 300, idealHeight: 360)
            }
        }
    }

    private var historyHeading: some View {
        SectionHeading(title: "额度历史", subtitle: "主额度与次级额度，仅保存在这台 Mac 上")
    }

    private var rangePicker: some View {
        Picker("范围", selection: $range) {
            ForEach(HistoryRange.allCases) { Text($0.label).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(maxWidth: 270)
        .onChange(of: range) { loadPoints() }
        .help("选择历史趋势时间范围")
    }

    @ViewBuilder private var diagnosticsContent: some View {
        AppleCard {
            VStack(spacing: 0) {
                DiagnosticRow(symbol: "network", color: AppleUI.accent, title: "数据来源", value: monitor.snapshot.sourceKind.label)
                diagnosticDivider
                DiagnosticRow(symbol: "chart.bar.xaxis", color: AppleUI.purple, title: "分析数据", value: analyticsStateLabel)
                if let identifier = monitor.diagnostic.analyticsIdentifier {
                    diagnosticDivider
                    DiagnosticRow(symbol: "link", color: AppleUI.purple, title: "分析连接", value: identifier)
                }
                diagnosticDivider
                DiagnosticRow(symbol: "checkmark.shield.fill", color: confidenceColor, title: "可信度", value: confidenceLabel)
                diagnosticDivider
                DiagnosticRow(symbol: "chart.bar.fill", color: AppleUI.purple, title: "字段完整度", value: "\(Int(monitor.snapshot.fieldCompleteness * 100))%")
                if let parserVersion = monitor.diagnostic.parserVersion {
                    diagnosticDivider
                    DiagnosticRow(symbol: "curlybraces", color: AppleUI.accent, title: "解析器", value: parserVersion)
                }
                diagnosticDivider
                DiagnosticRow(symbol: "externaldrive.fill", color: AppleUI.warning, title: "数据状态", value: dataStateLabel)
                if let sourceUpdatedAt = monitor.snapshot.sourceUpdatedAt {
                    diagnosticDivider
                    DiagnosticRow(symbol: "clock.fill", color: AppleUI.accent, title: "来源更新时间", value: RelativeFormatter.text(sourceUpdatedAt))
                }
            }
        }
        Button {
            showsTechnicalDiagnostics.toggle()
        } label: {
            Label(showsTechnicalDiagnostics ? "收起技术详情" : "显示技术详情",
                  systemImage: showsTechnicalDiagnostics ? "chevron.up.circle" : "chevron.down.circle")
        }
        .buttonStyle(GlassButtonStyle())
        .help("显示解析器、逐数据源状态与字段来源")

        if showsTechnicalDiagnostics && (!monitor.diagnostic.analyticsAvailability.isEmpty || !monitor.diagnostic.analyticsFailures.isEmpty) {
            AppleCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeading(title: "逐数据源状态", subtitle: "明确区分不支持、未授权与读取失败")
                    ForEach(monitor.diagnostic.analyticsAvailability.keys.sorted(), id: \.self) { identifier in
                        DiagnosticRow(symbol: "server.rack", color: AppleUI.accent,
                                      title: identifier, value: monitor.diagnostic.analyticsAvailability[identifier] ?? "未知")
                    }
                    ForEach(monitor.diagnostic.analyticsFailures.keys.sorted(), id: \.self) { identifier in
                        DiagnosticRow(symbol: "exclamationmark.triangle.fill", color: AppleUI.warning,
                                      title: "\(identifier) 错误", value: monitor.diagnostic.analyticsFailures[identifier] ?? "未知错误")
                    }
                }
            }
        }
        if showsTechnicalDiagnostics, let analytics = monitor.snapshot.analytics,
           !analytics.sectionSources.isEmpty || !analytics.warnings.isEmpty {
            AppleCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeading(title: "字段来源与兼容性", subtitle: "每个模块均保留自己的真实来源")
                    ForEach(analytics.sectionSources.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { section in
                        DiagnosticRow(symbol: "point.3.connected.trianglepath.dotted", color: AppleUI.purple,
                                      title: analyticsSectionName(section), value: analytics.sectionSources[section] ?? "未知")
                    }
                    ForEach(analytics.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline).foregroundStyle(AppleUI.warning).textSelection(.enabled)
                    }
                }
            }
        }
        if let message = monitor.persistenceWarning ?? monitor.snapshot.diagnosticMessage ?? monitor.lastError {
            AppleCard {
                HStack(alignment: .top, spacing: 13) {
                    SymbolTile(symbol: "exclamationmark.triangle.fill", color: AppleUI.warning)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("需要关注").font(.headline)
                        Text(message).font(.body).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                }
            }
        }
        diagnosticActions
    }

    private var diagnosticDivider: some View { Divider().opacity(0.35).padding(.leading, 45) }
    private var statusColor: Color {
        switch monitor.status {
        case .live: AppleUI.success
        case .cached, .estimated: AppleUI.purple
        case .refreshing: AppleUI.accent
        case .needsLogin, .degraded, .unavailable: AppleUI.warning
        }
    }
    private var confidenceColor: Color { monitor.snapshot.confidence == .unavailable ? AppleUI.warning : AppleUI.success }
    private var confidenceLabel: String {
        switch monitor.snapshot.confidence {
        case .verified: "已验证"
        case .high: "高"
        case .medium: "中"
        case .low: "低"
        case .unavailable: "不可用"
        }
    }
    private var dataStateLabel: String {
        if monitor.snapshot.isCached { return "缓存数据" }
        if monitor.snapshot.isEstimated { return "本地估算" }
        return monitor.snapshot.sourceKind == .unavailable ? "不可用" : "实时数据"
    }
    private var analyticsStateLabel: String {
        guard let analytics = monitor.snapshot.analytics else { return "本次未读取" }
        return "\(analytics.sourceDisplayName) · \(analytics.availableSections.count)/\(CodexAnalyticsSection.allCases.count) 模块"
    }

    private func analyticsSectionName(_ section: CodexAnalyticsSection) -> String {
        switch section {
        case .tokenUsage: "Token"
        case .activity: "线程、轮次与 Credits 消耗"
        case .productUsage: "产品入口与模型"
        case .skills: "Skills"
        case .plugins: "Plugins"
        case .creditEvents: "Credit 事件"
        }
    }

    private func loadPoints() {
        let cutoff = Date.now.addingTimeInterval(-range.seconds)
        points = (try? history.points(since: cutoff)) ?? []
    }

    private var diagnosticActions: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "恢复操作", subtitle: "根据当前状态重新建立数据连接")
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { recoveryButtons }
                    VStack(spacing: 10) { recoveryButtons }
                }
            }
        }
    }

    @ViewBuilder private var recoveryButtons: some View {
        Button { Task { await monitor.refresh() } } label: {
            Label("重新刷新", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
        }
        .buttonStyle(GlassButtonStyle(tint: AppleUI.accent))
        .disabled(monitor.isRefreshing)
        .help("重新读取额度与分析数据")

        Button {
            openWindow(id: "login"); webSession.openUsagePage(); NSApp.activate()
        } label: {
            Label("应用内登录", systemImage: "person.crop.circle").frame(maxWidth: .infinity)
        }
        .buttonStyle(GlassButtonStyle())
        .help("打开 OpenAI 官方登录页面")

        Button { openSettings(); NSApp.activate() } label: {
            Label("数据源设置", systemImage: "externaldrive.connected.to.line.below").frame(maxWidth: .infinity)
        }
        .buttonStyle(GlassButtonStyle())
        .help("管理网页登录与实验性数据源")

        Button { copyDiagnostics() } label: {
            Label("复制诊断", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
        }
        .buttonStyle(GlassButtonStyle())
        .help("复制不含 Token、Cookie 和邮箱的脱敏诊断摘要")
    }

    private func copyDiagnostics() {
        let analyticsAvailability = monitor.diagnostic.analyticsAvailability.keys.sorted()
            .map { "\($0): \(monitor.diagnostic.analyticsAvailability[$0] ?? "未知")" }
            .joined(separator: "\n")
        let analyticsFailures = monitor.diagnostic.analyticsFailures.keys.sorted()
            .map { "\($0): \(monitor.diagnostic.analyticsFailures[$0] ?? "未知")" }
            .joined(separator: "\n")
        let text = """
        Codex Usage Monitor \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development")
        额度来源: \(monitor.snapshot.sourceKind.label)
        分析来源: \(monitor.snapshot.analytics?.sourceDisplayName ?? "未读取")
        状态: \(monitor.status.label)
        完整度: \(Int(monitor.snapshot.fieldCompleteness * 100))%
        解析器: \(monitor.diagnostic.parserVersion ?? "未知")
        数据源状态:
        \(analyticsAvailability)
        失败摘要:
        \(analyticsFailures)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(SensitiveDataRedactor().redact(text), forType: .string)
    }
}

private struct OverviewStatusCard: View {
    let snapshot: CodexUsageSnapshot
    let lastError: String?
    let showDetails: () -> Void

    var body: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 12) {
                    SymbolTile(symbol: statusSymbol, color: statusColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.label).font(.headline)
                        Text(RelativeFormatter.text(snapshot.fetchedAt)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider().opacity(0.3)
                statusLine("来源", snapshot.sourceKind.label)
                statusLine("完整度", "\(Int(snapshot.fieldCompleteness * 100))%")
                statusLine("模式", stateLabel)
                MonitoringStatusBar(snapshot: snapshot, lastError: lastError, isRefreshing: false)
                Button("查看诊断") { showDetails() }
                    .buttonStyle(GlassButtonStyle())
                    .help("查看数据源诊断详情")
            }
        }
    }

    private func statusLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.weight(.semibold)).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var stateLabel: String {
        if snapshot.isCached { return "缓存" }
        if snapshot.isEstimated { return "估算" }
        return snapshot.sourceKind == .unavailable ? "不可用" : "实时"
    }

    private var status: MonitoringStatus {
        MonitoringStatus(snapshot: snapshot, lastError: lastError, isRefreshing: false)
    }

    private var statusSymbol: String {
        switch status {
        case .live: "checkmark.shield.fill"
        case .cached: "externaldrive.fill.badge.checkmark"
        case .estimated: "function"
        case .refreshing: "arrow.triangle.2.circlepath"
        case .needsLogin: "person.crop.circle.badge.exclamationmark"
        case .degraded, .unavailable: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .live: AppleUI.success
        case .cached, .estimated: AppleUI.purple
        case .refreshing: AppleUI.accent
        case .needsLogin, .degraded, .unavailable: AppleUI.warning
        }
    }
}

private struct UsageTrendChart: View {
    let points: [UsageSnapshotEntity]

    var body: some View {
        if !hasPrimary && !hasSecondary {
            ContentUnavailableView("暂无趋势数据", systemImage: "chart.xyaxis.line",
                                   description: Text("成功读取真实额度后，会在本机安静地记录趋势。"))
        } else {
            Chart(points) { point in
                if let value = point.primaryRemaining {
                    AreaMark(x: .value("时间", point.fetchedAt), y: .value("剩余", value))
                        .foregroundStyle(LinearGradient(colors: [AppleUI.accent.opacity(0.20), .clear], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("时间", point.fetchedAt), y: .value("剩余", value), series: .value("额度", "主额度"))
                        .foregroundStyle(by: .value("额度", "主额度"))
                        .lineStyle(lineStyle(estimated: point.isEstimated))
                        .interpolationMethod(.catmullRom)
                }
                if let value = point.secondaryRemaining {
                    LineMark(x: .value("时间", point.fetchedAt), y: .value("剩余", value), series: .value("额度", "次级额度"))
                        .foregroundStyle(by: .value("额度", "次级额度"))
                        .lineStyle(lineStyle(estimated: point.isEstimated))
                        .interpolationMethod(.catmullRom)
                }
            }
            .chartForegroundStyleScale(["主额度": AppleUI.accent, "次级额度": AppleUI.purple])
            .chartLegend(hasSecondary ? .visible : .hidden)
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine().foregroundStyle(.primary.opacity(0.06))
                    AxisValueLabel { if let number = value.as(Int.self) { Text("\(number)%") } }
                }
            }
            .chartXAxis { AxisMarks { AxisGridLine().foregroundStyle(.clear); AxisValueLabel() } }
            .accessibilityLabel("额度历史趋势")
        }
    }

    private var hasPrimary: Bool { points.contains { $0.primaryRemaining != nil } }
    private var hasSecondary: Bool { points.contains { $0.secondaryRemaining != nil } }
    private func lineStyle(estimated: Bool) -> StrokeStyle {
        StrokeStyle(lineWidth: estimated ? 1.5 : 2.5, lineCap: .round, dash: estimated ? [5, 4] : [])
    }
}

private struct DiagnosticRow: View {
    let symbol: String
    let color: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 13) {
            SymbolTile(symbol: symbol, color: color)
            Text(title).font(.body)
            Spacer()
            Text(value).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

enum DashboardSection: String, CaseIterable, Identifiable {
    case overview, analytics, history, diagnostics
    var id: Self { self }
    var title: String { switch self { case .overview: "概览"; case .analytics: "使用分析"; case .history: "历史趋势"; case .diagnostics: "数据源诊断" } }
    var symbol: String { switch self { case .overview: "gauge.with.dots.needle.50percent"; case .analytics: "chart.bar.xaxis"; case .history: "chart.xyaxis.line"; case .diagnostics: "stethoscope" } }
}

enum HistoryRange: String, CaseIterable, Identifiable {
    case fiveHours, day, week
    var id: Self { self }
    var label: String { switch self { case .fiveHours: "5 小时"; case .day: "24 小时"; case .week: "7 天" } }
    var seconds: TimeInterval { switch self { case .fiveHours: 18_000; case .day: 86_400; case .week: 604_800 } }
}
