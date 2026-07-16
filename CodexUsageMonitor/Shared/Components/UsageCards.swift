import SwiftUI

struct UsageCard: View {
    let title: String
    let window: UsageLimitWindow?
    let snapshot: CodexUsageSnapshot
    let now: Date

    var body: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    SymbolTile(symbol: title.contains("主") ? "bolt.fill" : "calendar.badge.clock",
                               color: title.contains("主") ? AppleUI.accent : AppleUI.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.headline)
                        Text(window?.durationDescription ?? "周期暂无数据")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ConfidenceBadge(confidence: snapshot.confidence, estimated: snapshot.isEstimated, cached: snapshot.isCached)
                }

                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(remainingValue).font(.title.monospacedDigit().weight(.bold))
                    Text("剩余").font(.subheadline).foregroundStyle(.secondary)
                }

                UsageProgressRow(title: "额度进度", window: window, now: now,
                                 color: window?.remainingPercentage.map { MenuBarQuotaLevel(remainingPercentage: $0).color }
                                    ?? (title.contains("主") ? AppleUI.accent : AppleUI.purple),
                                 isEstimated: snapshot.isEstimated)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 12)], alignment: .leading, spacing: 12) {
                    DetailMetric(title: "已使用", value: percentage(window?.usedPercentage), symbol: "chart.bar.fill")
                    DetailMetric(title: "周期", value: window?.durationDescription ?? "--", symbol: "clock.fill")
                    DetailMetric(title: "重置", value: resetValue, symbol: "arrow.counterclockwise")
                }
            }
        }
    }

    private var remainingValue: String {
        window?.remainingPercentage.map { "\(snapshot.isEstimated ? "≈" : "")\(Int($0))%" } ?? "--"
    }

    private func percentage(_ value: Double?) -> String { value.map { "\(Int($0))%" } ?? "--" }

    private var resetValue: String {
        guard let reset = window?.resetsAt else { return "--" }
        return reset > now ? DurationFormatter.short(reset.timeIntervalSince(now)) : "等待重置"
    }
}

private struct DetailMetric: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.caption).foregroundStyle(.secondary).symbolRenderingMode(.hierarchical)
            Text(value).font(.subheadline.monospacedDigit().weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ConfidenceBadge: View {
    let confidence: UsageConfidence
    let estimated: Bool
    let cached: Bool

    var body: some View {
        Label(label, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.10), in: Capsule())
            .accessibilityLabel("数据状态：\(label)")
    }

    private var label: String {
        if cached { return "缓存" }
        if estimated { return "估算" }
        switch confidence {
        case .verified: return "已验证"
        case .high: return "高可信"
        case .medium: return "中可信"
        case .low: return "低可信"
        case .unavailable: return "不可用"
        }
    }

    private var symbol: String {
        if cached { return "externaldrive.fill" }
        if estimated { return "function" }
        return confidence == .unavailable ? "exclamationmark.triangle.fill" : "checkmark.shield.fill"
    }

    private var color: Color {
        confidence == .unavailable ? AppleUI.warning : estimated || cached ? AppleUI.purple : AppleUI.success
    }
}

struct CreditsCard: View {
    let credits: CreditsUsage?

    var body: some View {
        AppleCard {
            HStack(spacing: 15) {
                SymbolTile(symbol: "sparkles", color: AppleUI.purple)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Credits").font(.headline)
                    Text(CreditsDisplay.value(credits)).font(.title3.monospacedDigit().weight(.bold))
                    Text(CreditsDisplay.detail(credits)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }
}
