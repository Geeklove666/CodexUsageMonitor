import SwiftUI

struct AdditionalProviderUsageCard: View {
    let snapshots: [AIProviderID: AIProviderUsageSnapshot]
    let failures: [AIProviderID: String]

    var body: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(
                    title: "其他 AI 服务",
                    subtitle: "仅展示已授权的本机结构化用量；不会伪装成套餐剩余额度。"
                )
                ForEach(snapshots.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { id in
                    if let snapshot = snapshots[id] {
                        providerRow(snapshot)
                    }
                }
                ForEach(failures.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { id in
                    if let failure = failures[id] {
                        Label("\(id.rawValue)：\(failure)", systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(AppleUI.warning)
                    }
                }
            }
        }
    }

    private func providerRow(_ snapshot: AIProviderUsageSnapshot) -> some View {
        let total = snapshot.dailyUsage.reduce(Int64(0)) { $0 + $1.tokens }
        let today = snapshot.dailyUsage.first { Calendar.current.isDateInToday($0.date) }?.tokens
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                providerIdentity(snapshot)
                Spacer(minLength: 20)
                metric("今日", today.map(CountFormatter.compact) ?? "--")
                metric("最近 7 天", CountFormatter.compact(total))
            }
            VStack(alignment: .leading, spacing: 12) {
                providerIdentity(snapshot)
                HStack(spacing: 24) {
                    metric("今日", today.map(CountFormatter.compact) ?? "--")
                    metric("最近 7 天", CountFormatter.compact(total))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snapshot.provider.displayName)，今日 \(today.map(CountFormatter.compact) ?? "无记录") Token，最近七天 \(CountFormatter.compact(total)) Token")
    }

    private func providerIdentity(_ snapshot: AIProviderUsageSnapshot) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.provider.displayName).font(.headline)
                Text(snapshot.sourceDisplayName).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "sparkles.rectangle.stack")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppleUI.purple)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit())
        }
    }
}

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
                        Text("用量")
                        Text("数据类型")
                        Text("重置次数")
                        Text("相对消耗")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Divider().gridCellColumns(5)

                    ForEach(summary.days) { day in
                        GridRow {
                            dateCell(day.date)
                            Text(usageValue(day))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .foregroundStyle(day.measurement == nil ? .secondary : .primary)
                            usageType(day)
                            Text(day.resetCount.map(String.init) ?? "--")
                                .monospacedDigit()
                                .foregroundStyle(day.resetCount == nil ? .secondary : .primary)
                            usageBar(day)
                        }
                        .font(.body)
                        .padding(.vertical, 4)
                        .background(
                            calendar.isDateInToday(day.date)
                                ? Color(nsColor: .systemBlue).opacity(0.055)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .opacity(day.measurement == nil ? 0.72 : 1)
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
            title: "每日套餐消耗",
            subtitle: summary.sourceName.map {
                weeklySourceText($0)
            } ?? "最近 7 天 · 尚无套餐消耗记录"
        )
    }

    private var metrics: some View {
        HStack(spacing: 20) {
            metric("Token 合计", summary.knownDays.isEmpty ? "--" : CountFormatter.compact(summary.totalTokens))
            metric("记录日均", summary.averageTokens.map(CountFormatter.compact) ?? "--")
            metric("峰值", summary.peakTokens.map(CountFormatter.compact) ?? "--")
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .contentTransition(.numericText())
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
        .frame(minWidth: 104, alignment: .leading)
    }

    private func numericDateText(_ date: Date) -> String {
        date.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
    }

    private func weekdayText(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }

    private func weeklySourceText(_ source: String) -> String {
        let estimate = summary.estimatedCreditDays.isEmpty
            ? ""
            : " · \(summary.estimatedCreditDays.count) 天为 Credits 估算"
        return "最近 7 天 · \(summary.knownDays.count) 天有 Token 记录\(estimate) · 来源：\(source)"
    }

    private func usageValue(_ day: DailyTokenUsage) -> String {
        switch day.measurement {
        case let .some(.tokens(tokens)): CountFormatter.compact(tokens)
        case let .some(.estimatedCredits(credits)): CalculatedCreditsFormatter.value(credits)
        case .none: "无记录"
        }
    }

    @ViewBuilder
    private func usageType(_ day: DailyTokenUsage) -> some View {
        switch day.measurement {
        case .some(.tokens):
            Text("Token").foregroundStyle(.secondary)
        case .some(.estimatedCredits):
            Label("Credits 估算", systemImage: "function")
                .foregroundStyle(AppleUI.warning)
        case .none:
            Text("--").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func usageBar(_ day: DailyTokenUsage) -> some View {
        if let tokens = day.tokens, let peak = summary.peakTokens, peak > 0 {
            ProgressView(value: Double(tokens), total: Double(peak))
                .progressViewStyle(.linear)
                .tint(Color(nsColor: .systemBlue).opacity(0.72))
                .frame(minWidth: 120)
                .accessibilityHidden(true)
        } else if let credits = day.estimatedCredits,
                  let peak = summary.peakEstimatedCredits,
                  peak > 0 {
            ProgressView(value: credits, total: peak)
                .progressViewStyle(.linear)
                .tint(AppleUI.warning.opacity(0.72))
                .frame(minWidth: 120)
                .accessibilityHidden(true)
        } else {
            Text("--").foregroundStyle(.secondary)
        }
    }

    private func accessibilityText(_ day: DailyTokenUsage) -> String {
        let resets = day.resetCount.map { "，使用重置 \($0) 次" } ?? "，重置次数无历史记录"
        switch day.measurement {
        case let .some(.tokens(tokens)):
            return "\(dateText(day.date))，\(tokens) 有效 Token\(resets)"
        case let .some(.estimatedCredits(credits)):
            return "\(dateText(day.date))，Token 无记录，估算消耗 \(CalculatedCreditsFormatter.labeled(credits))\(resets)"
        case .none:
            return "\(dateText(day.date))，没有用量记录\(resets)"
        }
    }
}
