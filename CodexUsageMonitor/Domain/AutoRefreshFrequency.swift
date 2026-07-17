import Foundation

enum AutoRefreshFrequency: Int, CaseIterable, Identifiable {
    case oneMinute = 60
    case fiveMinutes = 300
    case tenMinutes = 600

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .oneMinute: "1 分钟"
        case .fiveMinutes: "5 分钟"
        case .tenMinutes: "10 分钟"
        }
    }

    var detail: String {
        switch self {
        case .oneMinute: "高频监控，适合正在密集使用 Codex"
        case .fiveMinutes: "均衡模式，兼顾及时性和资源占用"
        case .tenMinutes: "低频刷新，适合只看大致趋势"
        }
    }

    static let defaultValue: AutoRefreshFrequency = .fiveMinutes

    static func sanitizedSeconds(_ value: Int) -> Int {
        AutoRefreshFrequency(rawValue: value)?.rawValue ?? defaultValue.rawValue
    }
}
