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
                        .contentTransition(.numericText())
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
        AppleCard(padding: 12, cornerRadius: AppleUI.cardRadius, material: nil) {
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
                .contentTransition(.numericText())
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
                    .contentTransition(.numericText())
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
    let failure: UsageFailure?
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
        switch presentationState {
        case .loading: return "正在读取 Codex 数据"
        case .live: return "数据正常 · \(RelativeFormatter.text(snapshot.fetchedAt))"
        case .cached: return "缓存数据 · \(RelativeFormatter.text(snapshot.fetchedAt))"
        case .estimated: return "本地估算 · \(RelativeFormatter.text(snapshot.fetchedAt))"
        case .offline: return failure?.userMessage ?? "当前网络不可用 · 保留旧数据"
        case .needsLogin: return failure?.userMessage ?? "需要登录后读取额度"
        case .failed:
            if let failure { return "刷新失败：\(failure.userMessage) · 保留旧数据" }
            return "刷新失败 · 保留 \(RelativeFormatter.text(snapshot.fetchedAt)) 的数据"
        case .unavailable: return failure?.userMessage ?? "当前没有可用数据"
        case .exhausted: return "主额度已耗尽 · 等待重置"
        }
    }

    private var symbol: String { presentationState.symbol }

    private var color: Color { presentationState.color }

    private var presentationState: UsagePresentationState {
        UsagePresentationState(snapshot: snapshot, failure: failure, isRefreshing: isRefreshing)
    }
}

enum CreditsDisplay {
    static func value(_ credits: CreditsUsage?) -> String {
        switch credits?.currencyOrUnit {
        case "无限": return "无限"
        case "Unlimited": return "无限"
        case "Unavailable": return "未启用"
        default: return credits?.remaining.map { decimalFormatter.string(from: $0 as NSDecimalNumber) ?? String(describing: $0) } ?? "--"
        }
    }

    static func detail(_ credits: CreditsUsage?) -> String {
        guard let credits else { return "暂无数据" }
        if credits.currencyOrUnit == "Unlimited" || credits.currencyOrUnit == "无限" { return "套餐无限额度" }
        if credits.currencyOrUnit == "Unavailable" { return "账户未启用" }
        return credits.currencyOrUnit ?? "Credits"
    }

    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        return formatter
    }()
}
