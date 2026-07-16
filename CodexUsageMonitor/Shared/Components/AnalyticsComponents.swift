import Charts
import SwiftUI

struct CompactAnalyticsSummary: View {
    let analytics: CodexAnalyticsSnapshot?
    var realtimeAuthorizationRequired = false

    var body: some View {
        AppleCard(padding: 9, cornerRadius: 17, shadowRadius: 14, shadowY: 4) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("今日 Token", systemImage: "chart.bar.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(analytics?.compactSourceDisplayName ?? (realtimeAuthorizationRequired ? "等待授权" : "本次未读取"))
                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
                HStack(spacing: 0) {
                    metric("Token", analytics?.todayTokens.map(CountFormatter.compact) ?? "--")
                        .frame(width: 78, alignment: .leading)
                    if let todayTokens = analytics?.todayTokens {
                        tokenMilestone(tokens: todayTokens)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Label(realtimeAuthorizationRequired ? "需授权本机实时 Token" : "今天尚未返回 Token 记录",
                              systemImage: realtimeAuthorizationRequired ? "lock.circle" : "minus.circle")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.subheadline.monospacedDigit().weight(.semibold)).lineLimit(1)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func tokenMilestone(tokens: Int64) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "scope")
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppleUI.purple)
                .frame(width: 26, height: 26)
                .background(AppleUI.purple.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(TokenMilestoneFormatter.todayMessage(tokens: tokens))
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(TokenMilestoneFormatter.explanation)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, 8)
        .accessibilityElement(children: .combine)
    }

}

struct AnalyticsOverviewCard: View {
    let analytics: CodexAnalyticsSnapshot
    let showDetails: () -> Void

    var body: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SectionHeading(title: "Codex 使用分析", subtitle: rangeText)
                    Spacer()
                    Button("查看全部") { showDetails() }
                        .buttonStyle(GlassButtonStyle())
                        .help("查看完整 Codex 使用分析")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
                    if analytics.has(.tokenUsage) {
                        UsageMetricTile(title: "Token", value: CountFormatter.compact(analytics.totalTokens), detail: "近 30 天", symbol: "text.word.spacing", color: AppleUI.accent)
                    }
                    if analytics.has(.activity) {
                        UsageMetricTile(title: "线程", value: analytics.totalThreads.formatted(), detail: "\(analytics.activeDays) 个活跃日", symbol: "bubble.left.and.bubble.right.fill", color: AppleUI.purple)
                        UsageMetricTile(title: "轮次", value: analytics.totalTurns.formatted(), detail: "真实活动", symbol: "arrow.triangle.2.circlepath", color: AppleUI.accent)
                    }
                    if analytics.has(.skills) {
                        UsageMetricTile(title: "Skills", value: analytics.totalSkillInvocations.formatted(), detail: "调用次数", symbol: "wand.and.stars", color: AppleUI.purple)
                    }
                }
                if !missingSections.isEmpty {
                    Label("另有 \(missingSections) 需要已授权的工作区 Analytics", systemImage: "lock.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var rangeText: String {
        guard let start = analytics.rangeStart, let end = analytics.rangeEnd else { return analytics.sourceDisplayName }
        return "\(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted)) · \(analytics.sourceDisplayName)"
    }

    private var missingSections: String {
        let labels: [(CodexAnalyticsSection, String)] = [(.activity, "线程/轮次"), (.skills, "Skills"), (.plugins, "Plugins")]
        return labels.filter { !analytics.has($0.0) }.map(\.1).joined(separator: "、")
    }
}

struct AnalyticsDashboard: View {
    let analytics: CodexAnalyticsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            summary
            if analytics.hasAccountUsageSummary { accountUsageSection }
            if analytics.has(.tokenUsage) { tokenSection }
            if analytics.has(.tokenUsage), !analytics.dailyActivity.isEmpty { dailyTokenDetailSection }
            if analytics.has(.activity) { activitySection }
            if analytics.has(.skills) || analytics.has(.plugins) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                    if analytics.has(.skills) {
                        namedUsageCard(title: "Skills", subtitle: "按调用次数", symbol: "wand.and.stars", items: analytics.topSkills, section: .skills)
                    }
                    if analytics.has(.plugins) {
                        namedUsageCard(title: "Plugins", subtitle: "按调用次数", symbol: "puzzlepiece.extension.fill", items: analytics.topPlugins, section: .plugins)
                    }
                }
            }
            if analytics.has(.activity) {
                DashboardAdaptiveColumns {
                    activityBreakdownCard(title: "客户端", symbol: "macbook.and.iphone", items: analytics.clientBreakdown)
                } trailing: {
                    activityBreakdownCard(title: "模型", symbol: "cpu.fill", items: analytics.modelBreakdown)
                }
            }
            if analytics.has(.productUsage) {
                DashboardAdaptiveColumns {
                    productSurfaceCard
                } trailing: {
                    modelCreditCard
                }
            }
            if !unsupportedSections.isEmpty { unsupportedCapabilityCard }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "分析概览", subtitle: rangeText)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                if analytics.has(.tokenUsage) {
                    tile("Token", CountFormatter.compact(analytics.totalTokens), "近 30 天", "text.word.spacing", AppleUI.accent)
                    tile("活跃日", analytics.activeDays.formatted(), "近 30 天", "calendar.badge.checkmark", AppleUI.accent)
                }
                if analytics.has(.activity) {
                    tile("线程", analytics.totalThreads.formatted(), "创建", "bubble.left.and.bubble.right.fill", AppleUI.purple)
                    tile("轮次", analytics.totalTurns.formatted(), "交互", "arrow.triangle.2.circlepath", AppleUI.accent)
                    tile("Credits 消耗", CountFormatter.decimal(analytics.totalCredits), "历史消耗", "sparkles", AppleUI.purple)
                }
                if analytics.has(.skills) { tile("Skills", analytics.totalSkillInvocations.formatted(), "调用", "wand.and.stars", AppleUI.purple) }
                if analytics.has(.plugins) { tile("Plugins", analytics.totalPluginInvocations.formatted(), "调用", "puzzlepiece.extension.fill", AppleUI.accent) }
                if analytics.has(.creditEvents), let count = analytics.creditEventCount {
                    tile("Credit 事件", count.formatted(), "记录", "list.bullet.rectangle", AppleUI.purple)
                }
            }
        }
    }

    private var tokenSection: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(title: "Token 使用", subtitle: "按日统计；构成仅在来源实际返回时显示")
                HStack(spacing: 12) {
                    composition("未缓存输入", analytics.has(.activity) ? analytics.uncachedInputTokens : nil, AppleUI.accent)
                    composition("缓存输入", analytics.has(.activity) ? analytics.cachedInputTokens : nil, AppleUI.purple)
                    composition("输出", analytics.has(.activity) ? analytics.outputTokens : nil, AppleUI.success)
                }
                if !analytics.has(.tokenUsage) || analytics.dailyActivity.isEmpty {
                    ContentUnavailableView(analytics.has(.tokenUsage) ? "暂无 Token 数据" : "本次未读取 Token 数据", systemImage: "text.word.spacing")
                        .frame(height: 180)
                } else {
                    Chart(analytics.dailyActivity) { day in
                        AreaMark(x: .value("日期", day.date), y: .value("Token", day.totalTokens))
                            .foregroundStyle(LinearGradient(colors: [AppleUI.accent.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("日期", day.date), y: .value("Token", day.totalTokens))
                            .foregroundStyle(AppleUI.accent)
                            .lineStyle(.init(lineWidth: 2.5, lineCap: .round))
                            .interpolationMethod(.catmullRom)
                    }
                    .chartYAxis { AxisMarks(position: .leading) { AxisGridLine().foregroundStyle(.primary.opacity(0.06)); AxisValueLabel() } }
                    .chartXAxis { AxisMarks { AxisGridLine().foregroundStyle(.clear); AxisValueLabel(format: .dateTime.month().day()) } }
                    .frame(height: 240)
                    .accessibilityLabel("每日 Token 使用趋势")
                }
            }
        }
    }

    private var accountUsageSection: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(title: "账户使用摘要", subtitle: "由本机 Codex 登录通过官方 app-server 返回")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                    if let value = analytics.lifetimeTokens {
                        tile("累计 Token", value.formatted(), "账户累计", "sum", AppleUI.accent)
                    }
                    if let value = analytics.peakDailyTokens {
                        tile("单日峰值", value.formatted(), "Token", "chart.line.uptrend.xyaxis", AppleUI.purple)
                    }
                    if let value = analytics.currentStreakDays {
                        tile("当前连续", "\(value) 天", "活跃记录", "flame.fill", AppleUI.warning)
                    }
                    if let value = analytics.longestStreakDays {
                        tile("最长连续", "\(value) 天", "活跃记录", "calendar.badge.checkmark", AppleUI.success)
                    }
                    if let value = analytics.longestRunningTurnSeconds {
                        tile("最长任务", DurationFormatter.activityDuration(value), "运行时长", "timer", AppleUI.accent)
                    }
                }
            }
        }
    }

    private var activitySection: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(title: "线程与轮次", subtitle: "官方分析中的每日活动")
                if !analytics.has(.activity) || analytics.dailyActivity.isEmpty {
                    ContentUnavailableView(analytics.has(.activity) ? "暂无活动数据" : "本次未读取活动数据", systemImage: "chart.bar.xaxis").frame(height: 180)
                } else {
                    Chart(analytics.dailyActivity) { day in
                        BarMark(x: .value("日期", day.date), y: .value("数量", day.turns))
                            .foregroundStyle(by: .value("指标", "轮次"))
                        LineMark(x: .value("日期", day.date), y: .value("数量", day.threads))
                            .foregroundStyle(by: .value("指标", "线程"))
                            .symbol(by: .value("指标", "线程"))
                    }
                    .chartForegroundStyleScale(["轮次": AppleUI.accent, "线程": AppleUI.purple])
                    .chartYAxis { AxisMarks(position: .leading) { AxisGridLine().foregroundStyle(.primary.opacity(0.06)); AxisValueLabel() } }
                    .frame(height: 220)
                    .accessibilityLabel("每日线程与轮次")
                }
            }
        }
    }

    private var dailyTokenDetailSection: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(
                    title: "每日 Token 明细",
                    subtitle: "数据源实际返回的 \(analytics.dailyActivity.count) 条记录 · 未返回日期不会补零"
                )
                Divider().opacity(0.3)
                ForEach(Array(analytics.dailyActivity.sorted { $0.date > $1.date }.enumerated()), id: \.element.id) { index, day in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(day.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(day.totalTokens.formatted())
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                        Text("Token").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 5)
                    .accessibilityElement(children: .combine)
                    if index < analytics.dailyActivity.count - 1 { Divider().opacity(0.22) }
                }
            }
        }
    }

    private func namedUsageCard(title: String, subtitle: String, symbol: String, items: [CodexNamedUsage], section: CodexAnalyticsSection) -> some View {
        AnalyticsListCard(title: title, subtitle: subtitle, symbol: symbol) {
            if !analytics.has(section) {
                emptyRow("本次未读取到\(title)数据")
            } else if items.isEmpty {
                emptyRow("官方分析当前没有返回\(title)记录")
            } else {
                ForEach(items) { item in
                    metricRow(item.displayName, value: item.invocations.formatted(), detail: "次")
                }
            }
        }
    }

    private func activityBreakdownCard(title: String, symbol: String, items: [CodexActivityBreakdown]) -> some View {
        AnalyticsListCard(title: title, subtitle: "轮次、线程与 Credits", symbol: symbol) {
            if !analytics.has(.activity) { emptyRow("本次未读取到\(title)数据") }
            else if items.isEmpty { emptyRow("暂无\(title)分布") }
            else {
                ForEach(items) { item in
                    metricRow(displayName(item.name), value: item.turns.formatted(), detail: "轮次 · \(item.threads) 线程 · \(CountFormatter.decimal(item.credits)) Credits")
                }
            }
        }
    }

    private var productSurfaceCard: some View {
        AnalyticsListCard(title: "产品入口", subtitle: "每日占比的区间平均值", symbol: "square.grid.2x2.fill") {
            if !analytics.has(.productUsage) { emptyRow("本次未读取到产品入口数据") }
            else if analytics.productSurfaceAverages.isEmpty { emptyRow("暂无产品入口分布") }
            else {
                ForEach(Array(analytics.productSurfaceAverages.enumerated()), id: \.offset) { _, item in
                    metricRow(displayName(item.name), value: item.percentage.formatted(.number.precision(.fractionLength(0...1))) + "%", detail: "平均占比")
                }
            }
        }
    }

    private var modelCreditCard: some View {
        AnalyticsListCard(title: "模型与速度", subtitle: "Token 分析中的 Credits", symbol: "speedometer") {
            if !analytics.has(.productUsage) { emptyRow("本次未读取到模型速度数据") }
            else if analytics.modelCreditBreakdown.isEmpty { emptyRow("暂无模型速度分布") }
            else {
                ForEach(analytics.modelCreditBreakdown) { item in
                    metricRow(item.model, value: CountFormatter.decimal(item.credits), detail: "\(displayName(item.speed)) · Credits")
                }
            }
        }
    }

    private func tile(_ title: String, _ value: String, _ detail: String, _ symbol: String, _ color: Color) -> some View {
        UsageMetricTile(title: title, value: value, detail: detail, symbol: symbol, color: color)
    }

    private func composition(_ title: String, _ value: Int64?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) { Circle().fill(color).frame(width: 7, height: 7); Text(title).font(.caption).foregroundStyle(.secondary) }
            Text(value.map(CountFormatter.compact) ?? "--").font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var unsupportedSections: [CodexAnalyticsSection] {
        CodexAnalyticsSection.allCases.filter { !analytics.has($0) }
    }

    private var unsupportedCapabilityCard: some View {
        AppleCard {
            HStack(alignment: .top, spacing: 12) {
                SymbolTile(symbol: "lock.shield.fill", color: AppleUI.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text("当前数据源的能力边界").font(.headline)
                    Text("未提供：\(unsupportedSections.map(sectionName).joined(separator: "、"))。本机 Codex 登录不会虚构工作区指标；如账户具备权限，可在设置中启用官方页面 Analytics 补充读取。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func sectionName(_ section: CodexAnalyticsSection) -> String {
        switch section {
        case .tokenUsage: "Token"
        case .activity: "线程、轮次与 Credits 消耗"
        case .productUsage: "产品入口与模型"
        case .skills: "Skills"
        case .plugins: "Plugins"
        case .creditEvents: "Credit 事件"
        }
    }

    private func metricRow(_ title: String, value: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(.subheadline.weight(.medium)).lineLimit(1)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value).font(.subheadline.monospacedDigit().weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }

    private func emptyRow(_ text: String) -> some View {
        Label(text, systemImage: "minus.circle").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 16)
    }

    private var rangeText: String {
        guard let start = analytics.rangeStart, let end = analytics.rangeEnd else { return analytics.sourceDisplayName }
        return "\(analytics.sourceDisplayName) · \(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))"
    }

    private func displayName(_ raw: String) -> String {
        let names = ["desktop_app": "Desktop", "CODEX_DESKTOP_APP": "Desktop", "work_desktop": "工作区 Desktop", "vscode": "VS Code", "cli": "CLI", "web": "Web", "work_web": "工作区 Web", "mobile": "Mobile", "work_mobile": "工作区 Mobile", "jetbrains": "JetBrains", "github_code_review": "GitHub Code Review", "agent_identity": "Agent", "unknown": "其他", "standard": "标准", "fast": "快速"]
        return names[raw] ?? raw.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private struct AnalyticsListCard<Content: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 11) {
                    SymbolTile(symbol: symbol, color: AppleUI.purple)
                    SectionHeading(title: title, subtitle: subtitle)
                }
                Divider().opacity(0.3)
                content
            }
        }
    }
}
