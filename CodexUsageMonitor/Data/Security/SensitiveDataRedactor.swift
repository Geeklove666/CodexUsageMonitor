import Foundation

struct SensitiveDataRedactor: Sendable {
    private let rules: [(String, String)] = [
        (#"(?i)(authorization\s*[:=]\s*)([^\s,;]+(?:\s+[^\s,;]+)?)"#, "$1[REDACTED]"),
        (#"(?i)((?:set-)?cookie\s*[:=]\s*)([^\r\n]+)"#, "$1[REDACTED]"),
        (#"(?i)((?:access|refresh)[_-]?token|session[_-]?id)\s*[:=]\s*[\"']?([^\s,;\"']+)"#, "$1=[REDACTED]"),
        (#"(?i)[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, "[REDACTED_EMAIL]"),
        (#"(?i)([?&](?:token|key|session|code)=)[^&#\s]+"#, "$1[REDACTED]")
    ]

    func redact(_ value: String) -> String {
        rules.reduce(value) { result, rule in
            result.replacingOccurrences(of: rule.0, with: rule.1, options: .regularExpression)
        }
    }
}
