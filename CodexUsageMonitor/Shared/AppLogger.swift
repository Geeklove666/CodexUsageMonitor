import Foundation
import OSLog

struct AppLogger: Sendable {
    enum Category: String, Sendable {
        case app
        case monitoring
        case repository
        case localCodex
        case webSession
        case persistence
    }

    private let logger: Logger

    init(_ category: Category) {
        logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "local.codex-usage-monitor",
            category: category.rawValue
        )
    }

    func debug(_ message: @autoclosure () -> String) {
        guard UserDefaults.standard.bool(forKey: AppPreferences.Key.debugMode) else { return }
        let value = sanitized(message())
        logger.debug("\(value, privacy: .public)")
    }

    func info(_ message: @autoclosure () -> String) {
        let value = sanitized(message())
        logger.info("\(value, privacy: .public)")
    }

    func warning(_ message: @autoclosure () -> String) {
        let value = sanitized(message())
        logger.warning("\(value, privacy: .public)")
    }

    func error(_ message: @autoclosure () -> String) {
        let value = sanitized(message())
        logger.error("\(value, privacy: .public)")
    }

    private func sanitized(_ message: String) -> String {
        SensitiveDataRedactor().redact(message)
    }
}
