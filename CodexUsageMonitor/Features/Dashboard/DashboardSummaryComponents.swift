import SwiftUI

struct WeeklyTokenUsageCard: View {
    let summary: WeeklyTokenUsageSummary
    @Environment(\.calendar) private var calendar

    var body: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top) {
                        heading
                        Spacer(minLength: 24)
                        metrics
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        heading
                        metrics
                    }
                }

                Divider().opacity(0.28)

                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                    GridRow {
                        Text("日期")
                        Text("Token 用量")
                        Text("小目标")
                        Text("重置次数")
                        Text("相对用量")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Divider().gridCellColumns(5)

                    ForEach(summary.days) { day in
                        GridRow {
                            dateCell(day.date)
                            Text(day.tokens.map(CountFormatter.compact) ?? "无记录")
                                .monospacedDigit()
                                .foregroundStyle(day.tokens == nil ? .secondary : .primary)
                            Text(goalText(day.tokens))
                                .monospacedDigit()
                                .foregroundStyle(day.tokens == nil ? .secondary : .primary)
                            Text(day.resetCount.map(String.init) ?? "--")
                                .monospacedDigit()
                                .foregroundStyle(day.resetCount == nil ? .secondary : .primary)
                            tokenBar(day.tokens)
                        }
                        .font(.body)
                    }
                }
                .accessibilityHidden(true)

                Color.clear
                    .frame(height: 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(summary.days.map(accessibilityText).joined(separator: "；"))
            }
        }
    }

    private var heading: some View {
        SectionHeading(
            title: "每日 Token 用量",
            subtitle: summary.sourceName.map {
                "最近 7 天 · \(summary.knownDays.count) 天有记录 · 来源：\($0)"
            } ?? "最近 7 天 · 尚无 Token 历史"
        )
    }

    private var metrics: some View {
        HStack(spacing: 20) {
            metric("合计", summary.knownDays.isEmpty ? "--" : CountFormatter.compact(summary.totalTokens))
            metric("有记录日均", summary.averageTokens.map(CountFormatter.compact) ?? "--")
            metric("峰值", summary.peakTokens.map(CountFormatter.compact) ?? "--")
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit())
        }
    }

    private func dateText(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "今天" }
        return "\(numericDateText(date))，\(weekdayText(date))"
    }

    private func dateCell(_ date: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(calendar.isDateInToday(date) ? "今天" : numericDateText(date))
                .monospacedDigit()
                .fontWeight(calendar.isDateInToday(date) ? .semibold : .regular)
            Text(calendar.isDateInToday(date) ? numericDateText(date) : weekdayText(date))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 112, alignment: .leading)
    }

    private func numericDateText(_ date: Date) -> String {
        date.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
    }

    private func weekdayText(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }

    private func goalText(_ tokens: Int64?) -> String {
        guard let tokens else { return "--" }
        return String(format: "%.2f", Double(tokens) / Double(TokenMilestoneFormatter.smallGoal))
    }

    @ViewBuilder
    private func tokenBar(_ tokens: Int64?) -> some View {
        if let tokens, let peak = summary.peakTokens, peak > 0 {
            ProgressView(value: Double(tokens), total: Double(peak))
                .progressViewStyle(.linear)
                .tint(AppleUI.accent)
                .frame(minWidth: 120)
                .accessibilityHidden(true)
        } else {
            Text("--").foregroundStyle(.secondary)
        }
    }

    private func accessibilityText(_ day: DailyTokenUsage) -> String {
        let resets = day.resetCount.map { "，使用重置 \($0) 次" } ?? "，重置次数无历史记录"
        guard let tokens = day.tokens else { return "\(dateText(day.date))，没有 Token 记录\(resets)" }
        return "\(dateText(day.date))，\(tokens) Token，\(goalText(tokens)) 个小目标\(resets)"
    }
}
