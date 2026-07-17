import Foundation

enum DurationFormatter {
    static func short(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "已到期" }
        let totalMinutes = Int(seconds) / 60
        let days = totalMinutes / 1440, hours = totalMinutes % 1440 / 60, minutes = totalMinutes % 60
        if days > 0 { return "\(days)d\(hours)h" }
        if hours > 0 { return "\(hours)h\(minutes)m" }
        return "\(minutes)m"
    }

    static func compactChinese(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "已到期" }
        let totalMinutes = Int(seconds) / 60
        let days = totalMinutes / 1440, hours = totalMinutes % 1440 / 60, minutes = totalMinutes % 60
        if days > 0 { return hours > 0 ? "\(days)天\(hours)时" : "\(days)天" }
        if hours > 0 { return minutes > 0 ? "\(hours)时\(minutes)分" : "\(hours)小时" }
        return "\(minutes)分钟"
    }

    static func activityDuration(_ seconds: Int) -> String {
        let hours = max(0, seconds) / 3600
        let minutes = max(0, seconds) % 3600 / 60
        let remainingSeconds = max(0, seconds) % 60
        if hours > 0 { return "\(hours)时\(minutes)分" }
        if minutes > 0 { return "\(minutes)分\(remainingSeconds)秒" }
        return "\(remainingSeconds)秒"
    }
}

enum RelativeFormatter {
    static func text(_ date: Date, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "刚刚更新" }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟前更新" }
        return "\(Int(seconds / 3600)) 小时前更新"
    }
}

enum SubscriptionTierFormatter {
    static func displayName(_ planName: String?) -> String {
        guard let planName else { return "用量监控" }
        let normalized = planName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        switch normalized {
        case "free": return "$0 Free"
        case "go": return "$8 Go 订阅"
        case "plus": return "$20 Plus 订阅"
        case "pro", "prolite", "pro 5x": return "$100 Pro 5x 订阅"
        case "pro 20x": return "$200 Pro 20x 订阅"
        default:
            if let multiplier = proMultiplier(in: normalized) {
                if multiplier >= 20 { return "$200 Pro 20x 订阅" }
                if multiplier >= 5 { return "$100 Pro 5x 订阅" }
                return "Pro \(multiplier)x 订阅"
            }
            let readable = planName.replacingOccurrences(of: "_", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !readable.isEmpty else { return "用量监控" }
            return "\(readable.capitalized) 订阅"
        }
    }

    private static func proMultiplier(in value: String) -> Int? {
        let parts = value.split(whereSeparator: { $0 == " " })
        guard parts.first == "pro" else { return nil }
        for part in parts.dropFirst() where part.hasSuffix("x") {
            if let multiplier = Int(part.dropLast()) { return multiplier }
        }
        return nil
    }
}

enum CountFormatter {
    static func compact(_ value: Int64) -> String {
        let magnitude = abs(Double(value))
        if magnitude >= 1_000_000_000 { return decimal(Double(value) / 1_000_000_000) + "B" }
        if magnitude >= 1_000_000 { return decimal(Double(value) / 1_000_000) + "M" }
        if magnitude >= 1_000 { return decimal(Double(value) / 1_000) + "K" }
        return value.formatted()
    }

    static func compact(_ value: Int) -> String { compact(Int64(value)) }

    static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 1)))
    }
}

enum TokenMilestoneFormatter {
    static let smallGoal: Int64 = 100_000_000

    static func message(tokens: Int64) -> String {
        let safeTokens = max(0, tokens)
        if safeTokens >= smallGoal {
            let completed = Double(safeTokens) / Double(smallGoal)
            let value = completed.formatted(.number.precision(.fractionLength(0...2)))
            return "目前已经花掉了 \(value) 个小目标"
        }
        return "距离花掉 1 个小目标（Token）还差 \(CountFormatter.compact(smallGoal - safeTokens))"
    }

    static func todayMessage(tokens: Int64) -> String {
        let goals = Double(max(0, tokens)) / Double(smallGoal)
        let value = goals.formatted(.number.precision(.fractionLength(0...3)))
        return "今天已经花掉了 \(value) 个小目标"
    }

    static let explanation = "1 个小目标 = 1 亿 Token"
}
