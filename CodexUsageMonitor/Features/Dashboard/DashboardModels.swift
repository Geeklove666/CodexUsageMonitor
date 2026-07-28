import Foundation

enum DashboardSection: String, CaseIterable, Identifiable {
    case summary
    case overview
    case usageHistory
    case alerts
    case dataSource
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .summary: "总结"
        case .overview: "额度详情"
        case .usageHistory: "使用历史"
        case .alerts: "告警"
        case .dataSource: "数据来源"
        case .settings: "设置"
        }
    }

    var subtitle: String {
        switch self {
        case .summary: "一页查看核心额度、消耗速度与最近一周 Token；缺失时显示 Credits 估算。"
        case .overview: "查看额度窗口、子额度与历史变化。"
        case .usageHistory: "带可访问趋势图和表格视图的本地历史。"
        case .alerts: "额度变化的阈值与提醒规则。"
        case .dataSource: "来源状态、时间戳与套餐价格上下文。"
        case .settings: "调整刷新行为与数据完整性偏好。"
        }
    }

    var symbol: String {
        switch self {
        case .summary: "rectangle.grid.2x2"
        case .overview: "gauge.with.dots.needle.50percent"
        case .usageHistory: "chart.xyaxis.line"
        case .alerts: "bell.badge"
        case .dataSource: "externaldrive.connected.to.line.below"
        case .settings: "gearshape"
        }
    }
}

struct DashboardQuotaSnapshot {
    let status: UsagePresentationState
    let planDisplayName: String
    let remainingPercent: Double?
    let usedPercent: Double?
    let resetText: String
    let statusMessage: String
    let dataQualityText: String
    let secondaryAllowances: [QuotaAllowance]

    var remainingText: String {
        guard let remainingPercent else { return "不可用" }
        return "\(Int(remainingPercent))%"
    }

    var allAllowances: [QuotaAllowance] {
        [
            QuotaAllowance(id: "primary", name: "主额度", remainingPercent: remainingPercent, usedPercent: usedPercent, resetText: resetText, status: status)
        ] + secondaryAllowances
    }

    static func make(snapshot: CodexUsageSnapshot, status: UsagePresentationState, now: Date) -> DashboardQuotaSnapshot {
        let primary = snapshot.primaryWindow
        let remaining = primary?.remainingPercentage
        let resetText = primary?.resetsAt.map { DurationFormatter.short($0.timeIntervalSince(now)) + " 后重置" }
            ?? primary?.durationDescription
            ?? "重置时间不可用"
        let sourcePrefix = snapshot.isEstimated ? "估算" : (snapshot.isCached ? "缓存" : snapshot.sourceDisplayName)
        return DashboardQuotaSnapshot(
            status: status,
            planDisplayName: SubscriptionTierFormatter.displayName(snapshot.planName),
            remainingPercent: remaining,
            usedPercent: primary?.usedPercentage,
            resetText: resetText,
            statusMessage: snapshot.diagnosticMessage ?? "\(sourcePrefix) · \(status.freshnessText(fetchedAt: snapshot.fetchedAt, now: now))",
            dataQualityText: dataQualityText(snapshot: snapshot, status: status, now: now),
            secondaryAllowances: secondary(snapshot: snapshot, status: status, now: now)
        )
    }

    private static func secondary(snapshot: CodexUsageSnapshot, status: UsagePresentationState, now: Date) -> [QuotaAllowance] {
        var values: [QuotaAllowance] = []
        if let secondary = snapshot.secondaryWindow {
            values.append(QuotaAllowance(
                id: "secondary",
                name: "其他额度",
                remainingPercent: secondary.remainingPercentage,
                usedPercent: secondary.usedPercentage,
                resetText: secondary.resetsAt.map { DurationFormatter.short($0.timeIntervalSince(now)) + " 后重置" }
                    ?? secondary.durationDescription
                    ?? "重置时间不可用",
                status: status
            ))
        }
        if let credits = snapshot.credits {
            values.append(QuotaAllowance(
                id: "credits",
                name: "Credits",
                remainingPercent: nil,
                usedPercent: nil,
                resetText: CreditsDisplay.value(credits),
                status: status,
                valueOverride: "剩余 \(CreditsDisplay.value(credits))",
                kind: .value
            ))
        }
        if let resetAllowance = snapshot.resetAllowance {
            values.append(QuotaAllowance(
                id: "reset-allowance",
                name: "使用限额重置",
                remainingPercent: nil,
                usedPercent: nil,
                resetText: "可用 \(resetAllowance.availableCount) 次",
                status: status,
                valueOverride: "可用 \(resetAllowance.availableCount) 次",
                kind: .value
            ))
        }
        return values
    }

    private static func dataQualityText(snapshot: CodexUsageSnapshot, status: UsagePresentationState, now: Date) -> String {
        if snapshot.isCached { return "当前显示缓存数据，界面会保留来源和新鲜度。" }
        if snapshot.isEstimated { return "当前显示本地估算，数值会保留估算标识。" }
        switch status {
        case .live: return "当前显示真实数据源返回的最新快照。"
        case .loading: return "正在读取数据，已有快照会暂时保留。"
        case .needsLogin: return "当前需要登录或授权，已有数据会安全保留。"
        case .failed: return "最新刷新未完成，当前保留上一次有效数据。"
        case .unavailable: return "当前没有可用数据，未知值不会显示为 0。"
        case .exhausted: return "当前额度已耗尽，等待服务方定义的重置窗口。"
        case .cached, .estimated, .offline:
            return status.freshnessText(fetchedAt: snapshot.fetchedAt, now: now)
        }
    }
}

enum QuotaAllowanceKind {
    case percentage
    case value
}

struct QuotaAllowance: Identifiable {
    let id: String
    let name: String
    let remainingPercent: Double?
    let usedPercent: Double?
    let resetText: String
    let status: UsagePresentationState
    var valueOverride: String?
    var kind: QuotaAllowanceKind = .percentage

    var remainingText: String { valueOverride ?? remainingPercent.map { "剩余 \(Int($0))%" } ?? "不可用" }
    var usedText: String { usedPercent.map { "已用 \(Int($0))%" } ?? "不可用" }
    var usageSummaryText: String {
        kind == .percentage ? "\(usedText) / \(remainingText)" : remainingText
    }
    var showsProgress: Bool { kind == .percentage }
}

struct ChatGPTPlan: Identifiable {
    let name: String
    let price: String
    let codexAllowance: String
    var id: String { name }

    static let usBaseline = [
        ChatGPTPlan(name: "Free", price: "$0/月", codexAllowance: "有限 Codex 访问"),
        ChatGPTPlan(name: "Go", price: "$8/月", codexAllowance: "轻量 Codex 任务"),
        ChatGPTPlan(name: "Plus", price: "$20/月", codexAllowance: "更高 Codex 用量"),
        ChatGPTPlan(name: "Pro 5x", price: "$100/月", codexAllowance: "约为 Plus 的 5x 用量"),
        ChatGPTPlan(name: "Pro 20x", price: "$200/月", codexAllowance: "约为 Plus 的 20x 用量"),
        ChatGPTPlan(name: "Business", price: "$20/用户/月（年付）", codexAllowance: "团队套餐；月付 $25/用户/月"),
        ChatGPTPlan(name: "Enterprise / Edu", price: "联系销售", codexAllowance: "工作区管理的限制")
    ]
}
