import Charts
import SwiftUI

struct DataSourceDiagnosticsCard: View {
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
                                attemptResult(attempt)
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
        Label("当前：\(activeSourceName)", systemImage: "externaldrive")
        Label("完整度：\(Int(diagnostic.fieldCompleteness * 100))%", systemImage: "checklist")
        if let duration = diagnostic.requestDuration {
            Label(String(format: "耗时 %.2fs", duration), systemImage: "timer")
        }
    }

    @ViewBuilder
    private func attemptResult(_ attempt: DataSourceAttemptDiagnostic) -> some View {
        if attempt.succeeded {
            Label("成功", systemImage: "checkmark.circle.fill").foregroundStyle(AppleUI.success)
        } else if attempt.error != nil {
            Label("失败", systemImage: "exclamationmark.triangle.fill").foregroundStyle(AppleUI.warning)
        } else {
            Label("未使用", systemImage: "minus.circle").foregroundStyle(.secondary)
        }
    }

    private var activeSourceName: String {
        diagnostic.attempts.first(where: { $0.sourceIdentifier == diagnostic.activeIdentifier })?.sourceLabel
            ?? (diagnostic.activeIdentifier == "none" ? "尚无" : diagnostic.activeIdentifier)
    }
}

struct QuotaSummaryCard: View {
    let snapshot: DashboardQuotaSnapshot
    let velocity: UsageVelocity?

    var body: some View {
        AppleCard {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 28) {
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
            if snapshot.status != .live && snapshot.status != .loading {
                StatusBadge(status: snapshot.status)
            }
            Text(snapshot.planDisplayName)
                .font(.headline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(snapshot.remainingText)
                    .font(.system(size: 42, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text("剩余")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Label(snapshot.resetText, systemImage: "arrow.counterclockwise")
                .font(.title3.monospacedDigit().weight(.semibold))
                .symbolRenderingMode(.hierarchical)
            if let velocity {
                Label(velocity.consumedText, systemImage: "speedometer")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .help(velocity.detailText)
            }
        }
        .frame(minWidth: 250, maxWidth: 320, alignment: .leading)
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

struct SecondaryAllowanceGrid: View {
    let allowances: [QuotaAllowance]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "其他额度", subtitle: "每个重置窗口单独展示。")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                ForEach(allowances) { allowance in
                    AppleCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                SymbolTile(symbol: allowance.kind == .percentage ? "gauge.with.dots.needle.50percent" : "number")
                                Text(allowance.name).font(.headline)
                                Spacer()
                                if allowance.status != .live && allowance.status != .loading {
                                    StatusBadge(status: allowance.status)
                                }
                            }
                            Text(allowance.remainingText)
                                .font(.title3.monospacedDigit().weight(.semibold))
                            if allowance.kind == .percentage {
                                Text(allowance.resetText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if allowance.showsProgress {
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
}

struct UsageTrendSection: View {
    @Binding var range: UsageHistoryRange
    let status: UsagePresentationState
    let points: [UsageTrendPoint]
    let errorMessage: String?
    var expanded = false
    @State private var selectedPoint: UsageTrendPoint?

    var body: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        SectionHeading(title: "使用趋势", subtitle: "来自这台 Mac 保存的真实额度快照。")
                        Spacer()
                        rangePicker
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeading(title: "使用趋势", subtitle: "来自这台 Mac 保存的真实额度快照。")
                        rangePicker
                    }
                }
                trendContent
                    .frame(height: expanded ? 300 : 210)
                Text(trendFootnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rangePicker: some View {
        Picker("范围", selection: $range) {
            ForEach(UsageHistoryRange.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 260)
        .help("选择历史范围")
    }

    @ViewBuilder
    private var trendContent: some View {
        if points.count >= 2 {
            Chart {
                ForEach(points) { point in
                    LineMark(
                        x: .value("时间", point.date),
                        y: .value("剩余额度", point.remainingPercentage)
                    )
                    .foregroundStyle(AppleUI.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    AreaMark(
                        x: .value("时间", point.date),
                        y: .value("剩余额度", point.remainingPercentage)
                    )
                    .foregroundStyle(AppleUI.accent.opacity(0.07))
                    if point.isReset {
                        RuleMark(x: .value("重置", point.date))
                            .foregroundStyle(.secondary.opacity(0.34))
                            .annotation(position: .top, alignment: .leading) {
                                Text("重置")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                    }
                    if point.id == points.last?.id {
                        PointMark(
                            x: .value("当前时间", point.date),
                            y: .value("当前剩余额度", point.remainingPercentage)
                        )
                        .symbolSize(38)
                        .foregroundStyle(status.progressColor)
                    }
                }
                if let selectedPoint {
                    RuleMark(x: .value("选中时间", selectedPoint.date))
                        .foregroundStyle(.secondary.opacity(0.28))
                    PointMark(
                        x: .value("选中时间", selectedPoint.date),
                        y: .value("选中额度", selectedPoint.remainingPercentage)
                    )
                    .symbolSize(44)
                    .foregroundStyle(AppleUI.accent)
                    .annotation(position: .top, spacing: 8) {
                        trendTooltip(selectedPoint)
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case let .active(location):
                                updateSelectedPoint(at: location, proxy: proxy, geometry: geometry)
                            case .ended:
                                selectedPoint = nil
                            }
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
            .accessibilityLabel("真实使用趋势")
            .accessibilityValue("\(points.count) 个历史快照，\(status.accessibilityText)")
        } else {
            ContentUnavailableView {
                Label(errorMessage == nil ? "历史样本不足" : "历史读取失败",
                      systemImage: errorMessage == nil ? "chart.xyaxis.line" : "exclamationmark.triangle")
            } description: {
                Text(errorMessage ?? "至少保存两个真实额度快照后才会绘制趋势。")
            }
        }
    }

    private func updateSelectedPoint(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geometry[plotFrame]
        let relativeX = location.x - frame.minX
        guard relativeX >= 0, relativeX <= frame.width,
              let date: Date = proxy.value(atX: relativeX)
        else {
            selectedPoint = nil
            return
        }
        selectedPoint = points.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    private func trendTooltip(_ point: UsageTrendPoint) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(point.date.formatted(date: .abbreviated, time: .shortened))
            Text("剩余 \(Int(point.remainingPercentage))%")
                .fontWeight(.semibold)
        }
        .font(.caption)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.separator.opacity(0.24), lineWidth: 0.5)
        }
    }

    private var trendFootnote: String {
        if points.count >= 2 {
            return "仅展示本机已保存的真实额度快照；重置标记表示检测到额度恢复和新窗口。"
        }
        return "不会使用模拟数据填充缺失的历史记录。"
    }
}

struct ResetAndAlertsSection: View {
    let snapshot: DashboardQuotaSnapshot
    let notificationsEnabled: Bool
    let notifyEvery20: Bool
    let notifyReset: Bool

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
                if !notificationsEnabled {
                    InfoRow(title: "额度通知", value: "已关闭", symbol: "bell.slash")
                } else {
                    if notifyEvery20 {
                        InfoRow(title: "每消耗 20%", value: "已启用", symbol: "20.circle")
                    }
                    if notifyReset {
                        InfoRow(title: "额度重置", value: "已启用", symbol: "arrow.counterclockwise")
                    }
                    if !notifyEvery20 && !notifyReset {
                        InfoRow(title: "通知规则", value: "尚未选择", symbol: "bell")
                    }
                }
            }
        }
    }
}

struct DataQualityNote: View {
    let snapshot: DashboardQuotaSnapshot

    var body: some View {
        InlineNotice(status: snapshot.status, message: snapshot.dataQualityText)
    }
}

struct AllowanceTable: View {
    let allowances: [QuotaAllowance]

    var body: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "额度表", subtitle: "按当前快照中的额度窗口展示。")
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                    GridRow {
                        Text("额度").foregroundStyle(.secondary)
                        Text("用量").foregroundStyle(.secondary)
                        Text("重置").foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    Divider().gridCellColumns(3)
                    ForEach(allowances) { allowance in
                        GridRow {
                            Text(allowance.name).font(.body)
                            Text(allowance.usageSummaryText).monospacedDigit()
                            Text(allowance.resetText)
                        }
                        .font(.body)
                    }
                }
            }
        }
    }
}

struct InlineNotice: View {
    let status: UsagePresentationState
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
        .background(status.color.opacity(0.08), in: RoundedRectangle(cornerRadius: AppleUI.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppleUI.controlRadius, style: .continuous)
                .strokeBorder(status.color.opacity(0.18), lineWidth: 0.75)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(status.label)。\(message)")
    }
}

struct LinearQuotaProgress: View {
    let value: Double?
    let status: UsagePresentationState
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

struct StatusBadge: View {
    let status: UsagePresentationState

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

struct InfoRow: View {
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

struct PlanPriceRow: View {
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
