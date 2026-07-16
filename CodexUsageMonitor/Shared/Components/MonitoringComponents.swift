import SwiftUI

struct UsageRing: View {
    let percentage: Double?
    let warning: Bool
    var lineWidth: CGFloat = 5
    var showsValue = false
    var isEstimated = false
    var subtitle = "剩余"
    var showsWarningGlyph = true
    var valueFont: Font = .title2
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(.primary.opacity(0.10), style: StrokeStyle(lineWidth: lineWidth, dash: percentage == nil ? [2, 3] : []))
            if let percentage {
                Circle()
                    .trim(from: 0, to: max(0.015, percentage / 100))
                    .stroke(ringStyle, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.12), value: percentage)
            }
            if showsValue {
                VStack(spacing: 1) {
                    Text(percentage.map { "\(isEstimated ? "≈" : "")\(Int($0))%" } ?? "--")
                        .font(valueFont.monospacedDigit().weight(.bold))
                    Text(subtitle).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                }
            } else if warning && showsWarningGlyph {
                Image(systemName: "exclamationmark")
                    .font(.system(size: max(7, lineWidth * 2), weight: .bold))
                    .foregroundStyle(AppleUI.warning)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("剩余额度")
        .accessibilityValue(percentage.map { "\(isEstimated ? "约" : "")\(Int($0))%" } ?? "未知")
    }

    private var ringStyle: AnyShapeStyle {
        guard let percentage else { return AnyShapeStyle(.secondary) }
        let color = MenuBarQuotaLevel(remainingPercentage: percentage).color
        return AnyShapeStyle(AngularGradient(
            colors: [color.opacity(0.78), color, color.opacity(0.88)],
            center: .center
        ))
    }
}

struct CompactUsageSummary: View {
    let snapshot: CodexUsageSnapshot
    let now: Date

    var body: some View {
        AppleCard(padding: 12, cornerRadius: 16, shadowRadius: 12, shadowY: 3, material: .regularMaterial) {
            HStack(spacing: 12) {
                UsageRing(
                    percentage: snapshot.primaryWindow?.remainingPercentage,
                    warning: isWarning(snapshot.primaryWindow),
                    lineWidth: 7,
                    showsValue: true,
                    isEstimated: snapshot.isEstimated,
                    valueFont: .title3
                )
                .frame(width: 82, height: 82)

                VStack(spacing: 0) {
                    UsageMetricLine(title: "主额度剩余", value: percentageText(snapshot.primaryWindow?.remainingPercentage), color: quotaColor(snapshot.primaryWindow))
                    if let secondary = snapshot.secondaryWindow {
                        Divider().opacity(0.24)
                        UsageMetricLine(title: "次级额度剩余", value: percentageText(secondary.remainingPercentage), color: AppleUI.purple)
                    }
                    if snapshot.credits != nil {
                        Divider().opacity(0.24)
                        UsageMetricLine(title: "Credits", value: CreditsDisplay.value(snapshot.credits), color: AppleUI.purple)
                    }
                    if let allowance = snapshot.resetAllowance {
                        Divider().opacity(0.24)
                        UsageMetricLine(
                            title: "使用限额重置",
                            value: allowance.availableCount > 0 ? "可用 \(allowance.availableCount) 次" : "暂无可用",
                            color: allowance.availableCount > 0 ? AppleUI.success : .secondary
                        )
                    }
                    if snapshot.secondaryWindow == nil && snapshot.credits == nil && snapshot.resetAllowance == nil {
                        Divider().opacity(0.24)
                        UsageMetricLine(title: "其他额度", value: "暂无数据", color: .secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func percentageText(_ value: Double?) -> String {
        value.map { "\(snapshot.isEstimated ? "≈" : "")\(Int($0))%" } ?? "--"
    }

    private func isWarning(_ window: UsageLimitWindow?) -> Bool {
        guard let value = window?.remainingPercentage else { return false }
        return value <= 20
    }

    private func quotaColor(_ window: UsageLimitWindow?) -> Color {
        window?.remainingPercentage.map { MenuBarQuotaLevel(remainingPercentage: $0).color } ?? AppleUI.accent
    }
}

private struct UsageMetricLine: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 9) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).font(.subheadline.monospacedDigit().weight(.semibold))
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

struct UsageProgressRow: View {
    let title: String
    let window: UsageLimitWindow?
    let now: Date
    var color: Color = AppleUI.accent
    var isEstimated = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(title).font(.subheadline.weight(.semibold))
                if let duration = window?.durationDescription {
                    Text(duration).font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
                Text(remainingText).font(.subheadline.monospacedDigit().weight(.semibold))
                Text(resetText).font(.caption).foregroundStyle(.secondary)
            }
            progressTrack
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(remainingText)，\(resetText)")
    }

    @ViewBuilder private var progressTrack: some View {
        if let remaining = window?.remainingPercentage {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [color.opacity(0.82), color], startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * max(0, min(1, remaining / 100)))
                }
            }
            .frame(height: 6)
        } else {
            Capsule()
                .stroke(.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(height: 6)
        }
    }

    private var remainingText: String {
        window?.remainingPercentage.map { "\(isEstimated ? "≈" : "")\(Int($0))% 剩余" } ?? "-- 剩余"
    }

    private var resetText: String {
        guard let reset = window?.resetsAt else { return "重置 --" }
        return reset > now ? "· \(DurationFormatter.compactChinese(reset.timeIntervalSince(now))) 后重置" : "· 等待重置"
    }
}

struct MonitoringStatusBar: View {
    let snapshot: CodexUsageSnapshot
    let lastError: String?
    let isRefreshing: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(message)
            Spacer(minLength: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }

    private var message: String {
        switch status {
        case .refreshing: return "正在读取 Codex 数据"
        case .live: return "数据正常 · \(RelativeFormatter.text(snapshot.fetchedAt))"
        case .cached: return "缓存数据 · \(RelativeFormatter.text(snapshot.fetchedAt))"
        case .estimated: return "本地估算 · \(RelativeFormatter.text(snapshot.fetchedAt))"
        case .needsLogin: return lastError ?? "需要登录后读取额度"
        case .degraded: return "刷新失败 · 保留 \(RelativeFormatter.text(snapshot.fetchedAt)) 的数据"
        case .unavailable: return lastError ?? "当前没有可用数据"
        }
    }

    private var symbol: String {
        switch status {
        case .refreshing: return "arrow.triangle.2.circlepath"
        case .live: return "checkmark.circle.fill"
        case .cached: return "externaldrive.fill.badge.checkmark"
        case .estimated: return "function"
        case .needsLogin: return "person.crop.circle.badge.exclamationmark"
        case .degraded, .unavailable: return "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .live: return AppleUI.success
        case .cached, .estimated: return AppleUI.purple
        case .refreshing: return AppleUI.accent
        case .needsLogin, .degraded, .unavailable: return AppleUI.warning
        }
    }

    private var status: MonitoringStatus {
        MonitoringStatus(snapshot: snapshot, lastError: lastError, isRefreshing: isRefreshing)
    }
}

struct UsageHeroCard: View {
    let snapshot: CodexUsageSnapshot
    let now: Date

    var body: some View {
        AppleCard(cornerRadius: AppleUI.heroRadius, shadowRadius: 18, shadowY: 5, material: .regularMaterial) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) {
                    heroMetric.frame(minWidth: 300)
                    summaryTiles
                }
                VStack(alignment: .leading, spacing: 18) {
                    heroMetric
                    summaryTiles
                }
            }
        }
    }

    private var heroMetric: some View {
        HStack(spacing: 18) {
            UsageRing(
                percentage: snapshot.primaryWindow?.remainingPercentage,
                warning: (snapshot.primaryWindow?.remainingPercentage ?? 101) <= 20,
                lineWidth: 12,
                showsValue: true,
                isEstimated: snapshot.isEstimated
            )
            .frame(width: 140, height: 140)
            VStack(alignment: .leading, spacing: 7) {
                Text("主额度").font(.title3.weight(.semibold))
                Text(usedDescription).font(.body.monospacedDigit().weight(.medium))
                Text(resetDescription(snapshot.primaryWindow)).font(.subheadline).foregroundStyle(.secondary)
                if let duration = snapshot.primaryWindow?.durationDescription {
                    Label(duration, systemImage: "clock").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var summaryTiles: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
            if let secondary = snapshot.secondaryWindow {
                HeroSupplementaryMetric(title: "次级额度", value: percent(secondary.remainingPercentage), detail: "剩余", symbol: "calendar.badge.clock", color: AppleUI.purple)
            }
            if snapshot.credits != nil {
                Divider().opacity(0.25)
                HeroSupplementaryMetric(title: "Credits", value: CreditsDisplay.value(snapshot.credits), detail: CreditsDisplay.detail(snapshot.credits), symbol: "sparkles", color: AppleUI.purple)
            }
            if let allowance = snapshot.resetAllowance {
                Divider().opacity(0.25)
                HeroSupplementaryMetric(
                    title: "使用限额重置",
                    value: allowance.availableCount > 0 ? "可用 \(allowance.availableCount) 次" : "暂无可用",
                    detail: resetAllowanceDetail(allowance),
                    symbol: "arrow.counterclockwise.circle.fill",
                    color: allowance.availableCount > 0 ? AppleUI.success : .secondary
                )
            }
            if snapshot.secondaryWindow == nil && snapshot.credits == nil && snapshot.resetAllowance == nil {
                HeroSupplementaryMetric(title: "其他额度", value: "--", detail: "当前数据源未提供", symbol: "ellipsis.circle", color: .secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func percent(_ value: Double?) -> String {
        value.map { "\(snapshot.isEstimated ? "≈" : "")\(Int($0))%" } ?? "--"
    }

    private var primaryQuotaColor: Color {
        snapshot.primaryWindow?.remainingPercentage
            .map { MenuBarQuotaLevel(remainingPercentage: $0).color } ?? AppleUI.accent
    }

    private var usedDescription: String {
        guard let used = snapshot.primaryWindow?.usedPercentage else { return "已使用 --" }
        return "已使用 \(snapshot.isEstimated ? "≈" : "")\(Int(used))%"
    }

    private func resetDescription(_ window: UsageLimitWindow?) -> String {
        guard let reset = window?.resetsAt else { return "重置时间暂无数据" }
        return reset > now ? "\(DurationFormatter.short(reset.timeIntervalSince(now))) 后重置" : "等待额度重置"
    }

    private func resetAllowanceDetail(_ allowance: UsageResetAllowance) -> String {
        guard let expiration = allowance.credits.compactMap(\.expiresAt).filter({ $0 > now }).min() else {
            return "由当前数据源返回"
        }
        return "最近一次将在 \(DurationFormatter.short(expiration.timeIntervalSince(now))) 后到期"
    }
}

struct UsageMetricTile: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SymbolTile(symbol: symbol, color: color)
                Spacer()
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(value).font(.title3.monospacedDigit().weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
            Text(detail).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(.primary.opacity(0.032), in: RoundedRectangle(cornerRadius: AppleUI.smallRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppleUI.smallRadius, style: .continuous)
                .strokeBorder(.primary.opacity(0.045), lineWidth: 0.6)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HeroSupplementaryMetric: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            SymbolTile(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Text(detail).font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 16)
            Text(value).font(.title3.monospacedDigit().weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }
}

struct DashboardAdaptiveColumns<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) {
                leading.frame(minWidth: 400, maxWidth: .infinity)
                trailing.frame(minWidth: 230, idealWidth: 280, maxWidth: 320)
            }
            VStack(spacing: 18) {
                leading
                trailing
            }
        }
    }
}

enum CreditsDisplay {
    static func value(_ credits: CreditsUsage?) -> String {
        switch credits?.currencyOrUnit {
        case "无限": return "无限"
        case "Unlimited": return "无限"
        case "Unavailable": return "未启用"
        default: return credits?.remaining.map { String(describing: $0) } ?? "--"
        }
    }

    static func detail(_ credits: CreditsUsage?) -> String {
        guard let credits else { return "暂无数据" }
        if credits.currencyOrUnit == "Unlimited" || credits.currencyOrUnit == "无限" { return "套餐无限额度" }
        if credits.currencyOrUnit == "Unavailable" { return "账户未启用" }
        return credits.currencyOrUnit ?? "Credits"
    }
}
