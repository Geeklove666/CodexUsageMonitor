import Charts
import SwiftUI

struct UsagePaceCard: View {
    let assessment: UsagePaceAssessment

    var body: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(title: "额度能否用至重置", subtitle: "根据本机保存的主额度快照估算。")
                switch assessment {
                case let .projected(projection):
                    projectionContent(projection)
                case let .unavailable(message):
                    Label(message, systemImage: "clock.badge.questionmark")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func projectionContent(_ projection: UsagePaceProjection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(projection.headline, systemImage: projection.runsOutBeforeReset ? "exclamationmark.triangle" : "checkmark.circle")
                .font(.headline)
                .foregroundStyle(projection.runsOutBeforeReset ? AppleUI.warning : AppleUI.success)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 28) { metrics(projection) }
                VStack(alignment: .leading, spacing: 12) { metrics(projection) }
            }
            projectionChart(projection)
                .frame(height: 160)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) { legend }
                VStack(alignment: .leading, spacing: 6) { legend }
            }
            Text("基于近 \(DurationFormatter.compactChinese(projection.observationHours * 3600)) 的连续记录，最多观察 24 小时；最近读取 \(projection.observedAt.formatted(date: .omitted, time: .shortened))。虚线为本地估算，后续消耗速度变化会影响结果。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func metrics(_ projection: UsagePaceProjection) -> some View {
        metric("当前速度", "\(CountFormatter.decimal(projection.percentagePointsPerHour)) 个百分点 / 时")
        if projection.runsOutBeforeReset {
            metric("预计耗尽", projection.projectedExhaustionAt.formatted(date: .abbreviated, time: .shortened))
        } else {
            metric("预计重置前剩余", "\(CountFormatter.decimal(projection.projectedRemainingAtReset))%")
        }
        metric("用至重置的平均速度上限", "\(CountFormatter.decimal(projection.sustainablePercentagePointsPerHour)) 个百分点 / 时")
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.medium).monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }

    private var legend: some View {
        Group {
            Label("真实快照", systemImage: "line.diagonal").foregroundStyle(AppleUI.accent)
            Label("按当前速度（估算）", systemImage: "ellipsis").foregroundStyle(AppleUI.warning)
            Label("均匀用至重置", systemImage: "ellipsis").foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private func projectionChart(_ projection: UsagePaceProjection) -> some View {
        Chart {
            ForEach(projection.samples) { sample in
                LineMark(
                    x: .value("时间", sample.recordedAt),
                    y: .value("真实剩余额度", sample.remainingPercentage),
                    series: .value("曲线", "真实快照")
                )
                .foregroundStyle(AppleUI.accent)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            ForEach(0..<2) { endpoint in
                LineMark(
                    x: .value("时间", endpoint == 0 ? projection.observedAt : projection.projectionEnd),
                    y: .value("预测剩余额度", endpoint == 0 ? projection.remainingPercentage : projection.projectedRemainingAtReset),
                    series: .value("曲线", "按当前速度")
                )
                .foregroundStyle(AppleUI.warning)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                LineMark(
                    x: .value("时间", endpoint == 0 ? projection.observedAt : projection.resetsAt),
                    y: .value("均匀用至重置", endpoint == 0 ? projection.remainingPercentage : 0),
                    series: .value("曲线", "均匀用至重置")
                )
                .foregroundStyle(.secondary.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
            }
            RuleMark(x: .value("服务方重置时间", projection.resetsAt))
                .foregroundStyle(.secondary.opacity(0.4))
                .annotation(position: .top, alignment: .trailing) {
                    Text("重置").font(.caption2).foregroundStyle(.secondary)
                }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.16))
                AxisValueLabel { if let number = value.as(Int.self) { Text("\(number)%") } }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("额度预测图")
        .accessibilityValue("\(projection.headline)，当前速度每小时消耗 \(CountFormatter.decimal(projection.percentagePointsPerHour)) 个百分点，重置时间 \(projection.resetsAt.formatted(date: .abbreviated, time: .shortened))。")
    }
}
