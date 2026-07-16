import Foundation

/// Conservative fallback for visible page text. Structured `/wham/usage` data is
/// preferred; this parser is retained for accounts where that endpoint is absent.
struct OfficialPageDOMParser: CodexUsageDOMParser {
    let parserVersion = "2026.07-visible-text-2"

    func parse(html: String) throws -> ParsedCodexUsage {
        let text = visibleText(from: html)
        let primaryMatch = firstMatch(in: text, patterns: [
            #"(?i)(?:5\s*[- ]?\s*(?:hour|hours|hr|hrs|h)|five\s*hour|主额度|5\s*小时)[^%]{0,120}?(\d{1,3}(?:\.\d+)?)\s*%\s*(used|remaining|left|已使用|剩余)"#,
            #"(?i)(?:usage|额度)[^%]{0,100}?(\d{1,3}(?:\.\d+)?)\s*%\s*(used|remaining|left|已使用|剩余)"#,
            #"(?i)(?<![0-9])(\d{1,3}(?:\.\d+)?)\s*%\s*(used|remaining|left|已使用|剩余)"#
        ])
        let secondaryMatch = firstMatch(in: text, patterns: [
            #"(?i)(?:weekly|week|7\s*[- ]?\s*day|周额度|每周|7\s*天)[^%]{0,120}?(\d{1,3}(?:\.\d+)?)\s*%\s*(used|remaining|left|已使用|剩余)"#
        ])
        guard let primaryMatch else { throw UsageMonitorError.pageStructureChanged }

        let primary = makeWindow(primaryMatch, kind: .primary)
        let secondary = secondaryMatch.flatMap { makeWindow($0, kind: .secondary) }
        let resetAllowance = resetAllowance(in: text)
        guard primary != nil else { throw UsageMonitorError.pageStructureChanged }

        return ParsedCodexUsage(
            planName: planName(in: text),
            primaryWindow: primary,
            secondaryWindow: secondary,
            credits: nil,
            resetAllowance: resetAllowance,
            sourceUpdatedAt: nil,
            fieldCompleteness: (secondary == nil ? 0.25 : 0.45) + (resetAllowance == nil ? 0 : 0.1)
        )
    }

    private func resetAllowance(in text: String) -> UsageResetAllowance? {
        let patterns = [
            #"使用限额重置[^0-9]{0,40}可用\s*(\d+)\s*次"#,
            #"(?i)usage\s+limit\s+reset[^0-9]{0,40}(\d+)\s*(?:available|remaining)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text),
                  let count = Int(text[range]) else { continue }
            return UsageResetAllowance(availableCount: count)
        }
        return nil
    }

    private func visibleText(from html: String) -> String {
        html
            .replacingOccurrences(of: #"(?is)<script[^>]*>.*?</script>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<style[^>]*>.*?</style>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func firstMatch(in text: String, patterns: [String]) -> PercentageMatch? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let valueRange = Range(match.range(at: 1), in: text),
                  let modeRange = Range(match.range(at: 2), in: text),
                  let value = Double(text[valueRange]), (0...100).contains(value) else { continue }
            return PercentageMatch(value: value, mode: String(text[modeRange]).lowercased())
        }
        return nil
    }

    private func makeWindow(_ match: PercentageMatch, kind: UsageWindowKind) -> UsageLimitWindow? {
        let isUsed = match.mode == "used" || match.mode == "已使用"
        let used = isUsed ? match.value : 100 - match.value
        let remaining = isUsed ? 100 - match.value : match.value
        return UsageLimitWindow(kind: kind, remainingPercentage: remaining, usedPercentage: used,
                                resetsAt: nil, durationDescription: nil)
    }

    private func planName(in text: String) -> String? {
        for plan in ["Enterprise", "Business", "Team", "Pro", "Plus", "Edu", "Free"] {
            if text.range(of: "Codex \(plan)", options: .caseInsensitive) != nil ||
                text.range(of: "ChatGPT \(plan)", options: .caseInsensitive) != nil { return plan }
        }
        return nil
    }
}

private struct PercentageMatch {
    let value: Double
    let mode: String
}
