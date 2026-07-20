import Foundation

enum UsagePresentationState: String, Sendable, Equatable {
    case loading
    case live
    case cached
    case estimated
    case offline
    case needsLogin
    case failed
    case unavailable
    case exhausted

    init(snapshot: CodexUsageSnapshot, lastError: String?, isRefreshing: Bool) {
        if isRefreshing {
            self = .loading
        } else if (snapshot.primaryWindow?.remainingPercentage ?? 1) <= 0,
                  snapshot.sourceKind != .unavailable {
            self = .exhausted
        } else if let lastError, Self.looksOffline(lastError) {
            self = snapshot.sourceKind == .unavailable ? .offline : .failed
        } else {
            switch MonitoringStatus(snapshot: snapshot, lastError: lastError, isRefreshing: false) {
            case .refreshing: self = .loading
            case .live: self = .live
            case .cached: self = .cached
            case .estimated: self = .estimated
            case .needsLogin: self = .needsLogin
            case .degraded: self = .failed
            case .unavailable: self = .unavailable
            }
        }
    }

    var label: String {
        switch self {
        case .loading: "正在刷新"
        case .live: "数据正常"
        case .cached: "缓存数据"
        case .estimated: "本地估算"
        case .offline: "当前离线"
        case .needsLogin: "需要登录"
        case .failed: "刷新失败"
        case .unavailable: "数据不可用"
        case .exhausted: "额度已耗尽"
        }
    }

    func freshnessText(fetchedAt: Date?, now: Date) -> String {
        switch self {
        case .loading: "正在读取最新数据"
        case .live: "刚刚更新"
        case .cached: fetchedAt.map { "缓存 · \(RelativeFormatter.text($0, now: now))" } ?? "正在使用缓存"
        case .estimated: fetchedAt.map { "估算 · \(RelativeFormatter.text($0, now: now))" } ?? "根据本机活动估算"
        case .offline: "网络不可用"
        case .needsLogin: "需要完成登录或授权"
        case .failed: fetchedAt.map { "保留 \(RelativeFormatter.text($0, now: now)) 的数据" } ?? "未能读取最新数据"
        case .unavailable: "没有可用数据来源"
        case .exhausted: "等待额度重置"
        }
    }

    private static func looksOffline(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("网络") || normalized.contains("network")
            || normalized.contains("offline") || normalized.contains("internet")
    }
}
