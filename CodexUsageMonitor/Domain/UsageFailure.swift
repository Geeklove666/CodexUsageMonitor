import Foundation

enum UsageFailureKind: String, Sendable, Equatable {
    case authentication
    case network
    case timeout
    case parsing
    case unavailable
    case persistence
    case cancelled
    case unknown
}

protocol UsageFailureClassifying: Error {
    var usageFailureKind: UsageFailureKind { get }
}

struct UsageFailure: Sendable, Equatable {
    let kind: UsageFailureKind
    let userMessage: String
    let diagnosticMessage: String

    var requiresLogin: Bool { kind == .authentication }
    var isOffline: Bool { kind == .network }
    var isRetryable: Bool {
        switch kind {
        case .authentication, .parsing, .cancelled: false
        case .network, .timeout, .unavailable, .persistence, .unknown: true
        }
    }

    init(kind: UsageFailureKind, userMessage: String, diagnosticMessage: String? = nil) {
        self.kind = kind
        self.userMessage = userMessage
        self.diagnosticMessage = diagnosticMessage ?? userMessage
    }

    init(error: Error) {
        let redacted = SensitiveDataRedactor().redact(error.localizedDescription)
        let kind: UsageFailureKind
        if let classified = error as? any UsageFailureClassifying {
            kind = classified.usageFailureKind
        } else if error is CancellationError {
            kind = .cancelled
        } else if let urlError = error as? URLError {
            kind = urlError.code == .timedOut ? .timeout : .network
        } else {
            let nsError = error as NSError
            kind = nsError.domain == NSURLErrorDomain
                ? (nsError.code == NSURLErrorTimedOut ? .timeout : .network)
                : .unknown
        }
        self.init(kind: kind, userMessage: redacted, diagnosticMessage: redacted)
    }

    func appendingUserContext(_ suffix: String) -> UsageFailure {
        UsageFailure(kind: kind, userMessage: "\(userMessage)；\(suffix)", diagnosticMessage: diagnosticMessage)
    }
}
