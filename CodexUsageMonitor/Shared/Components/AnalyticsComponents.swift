import SwiftUI

struct CompactAnalyticsSummary: View {
    let analytics: CodexAnalyticsSnapshot?
    var realtimeAuthorizationRequired = false

    var body: some View {
        AppleCard(padding: 9, cornerRadius: AppleUI.cardRadius, material: nil) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("今日 Token", systemImage: "chart.bar.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(analytics?.compactSourceDisplayName ?? (realtimeAuthorizationRequired ? "等待授权" : "本次未读取"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
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

    private func tokenMilestone(tokens: Int64) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "scope")
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: AppleUI.iconRadius, style: .continuous))
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
