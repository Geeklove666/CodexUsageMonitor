import SwiftUI

struct CompactAnalyticsSummary: View {
    let analytics: CodexAnalyticsSnapshot?
    let measurement: DailyUsageMeasurement?
    var realtimeAuthorizationRequired = false

    init(
        analytics: CodexAnalyticsSnapshot?,
        measurement: DailyUsageMeasurement? = nil,
        realtimeAuthorizationRequired: Bool = false
    ) {
        self.analytics = analytics
        self.measurement = measurement
            ?? DailyTokenUsageBuilder.make(analytics: analytics).days.last?.measurement
        self.realtimeAuthorizationRequired = realtimeAuthorizationRequired
    }

    var body: some View {
        AppleCard(padding: 9, cornerRadius: AppleUI.cardRadius, material: nil) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label(cardTitle, systemImage: "chart.bar.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(analytics?.compactSourceDisplayName ?? (realtimeAuthorizationRequired ? "等待授权" : "本次未读取"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                HStack(spacing: 0) {
                    metric(unitTitle, primaryValue)
                        .frame(width: 78, alignment: .leading)
                    if let measurement {
                        usageExplanation(measurement)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Label(realtimeAuthorizationRequired ? "需授权本机用量" : "今天尚无可计价记录",
                              systemImage: realtimeAuthorizationRequired ? "lock.circle" : "minus.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .lineLimit(1)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var cardTitle: String {
        if measurement?.isEstimated == true { return "今日估算消耗" }
        return "今日 Token"
    }

    private var unitTitle: String {
        switch measurement {
        case .some(.tokens): "Token"
        case .some(.estimatedCredits): "Credits"
        case .none: "Token"
        }
    }

    private var primaryValue: String {
        switch measurement {
        case let .some(.tokens(tokens)): CountFormatter.compact(tokens)
        case let .some(.estimatedCredits(credits)): CalculatedCreditsFormatter.value(credits)
        case .none: "--"
        }
    }

    private func usageExplanation(_ measurement: DailyUsageMeasurement) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "scope")
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: AppleUI.iconRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(explanationTitle(measurement))
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(explanationSubtitle(measurement))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, 8)
        .accessibilityElement(children: .combine)
    }

    private func explanationTitle(_ measurement: DailyUsageMeasurement) -> String {
        switch measurement {
        case let .tokens(tokens):
            return "今日已使用 \(CountFormatter.compact(tokens)) Token"
        case let .estimatedCredits(credits):
            return "今日估算消耗 \(CalculatedCreditsFormatter.labeled(credits))"
        }
    }

    private func explanationSubtitle(_ measurement: DailyUsageMeasurement) -> String {
        switch measurement {
        case let .tokens(tokens):
            let targets = (Double(tokens) / 100_000_000)
                .formatted(.number.precision(.fractionLength(2)))
            return "约 \(targets) 个小目标 · 已扣除缓存输入"
        case .estimatedCredits:
            return "Token 无记录 · 根据 Credits 变化估算"
        }
    }
}
