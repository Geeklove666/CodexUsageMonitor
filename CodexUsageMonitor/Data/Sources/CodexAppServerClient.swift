import Darwin
import Foundation

struct CodexAppServerResponses: Sendable {
    let account: Data
    let rateLimits: Data
}

struct CodexAppServerClient: Sendable {
    let executable: URL

    func readAccountAndRateLimits() async throws -> CodexAppServerResponses {
        let output = try await runAccountAndRateLimits()

        var account: Data?
        var rateLimits: Data?
        for line in output.split(separator: 0x0A) where !line.isEmpty {
            let data = Data(line)
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = (object["id"] as? NSNumber)?.intValue else { continue }
            if let error = object["error"] as? [String: Any] {
                throw Self.mappedProtocolError(error["message"] as? String ?? "未知服务错误")
            }
            if id == 2 {
                try Self.validateAccountResponse(data)
                account = data
            }
            if id == 3 { rateLimits = data }
        }

        guard let account, let rateLimits else { throw LocalCodexSessionError.invalidResponse }
        return CodexAppServerResponses(account: account, rateLimits: rateLimits)
    }

    private static func validateAccountResponse(_ data: Data) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any] else {
            throw LocalCodexSessionError.invalidResponse
        }
        if result["account"] == nil || result["account"] is NSNull {
            throw LocalCodexSessionError.openAIAuthRequired
        }
    }

    fileprivate static func mappedProtocolError(_ message: String) -> LocalCodexSessionError {
        let redacted = SensitiveDataRedactor().redact(message)
        let normalized = redacted.lowercased()
        if normalized.contains("authentication required") ||
            normalized.contains("requires openai auth") ||
            normalized.contains("not logged in") ||
            normalized.contains("login required") {
            return .openAIAuthRequired
        }
        return .protocolFailure(redacted)
    }

    private func runAccountAndRateLimits() async throws -> Data {
        let runner = CodexAppServerProcess(executable: executable)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        continuation.resume(returning: try runner.run())
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            runner.stop()
        }
    }

    func readAccountUsage() async throws -> Data {
        let runner = CodexAppServerProcess(executable: executable)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do { continuation.resume(returning: try runner.runAccountUsage()) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: {
            runner.stop()
        }
    }
}

private final class CodexAppServerProcess: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errorOutput = Pipe()
    private let lock = NSLock()
    private var stopped = false
    private var readBuffer = Data()
    private var stderrBuffer = Data()

    init(executable: URL) {
        process.executableURL = executable
        process.arguments = ["-s", "read-only", "-a", "untrusted", "app-server"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errorOutput
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        errorOutput.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            self.lock.lock()
            if self.stderrBuffer.count < 16_384 { self.stderrBuffer.append(data.prefix(16_384 - self.stderrBuffer.count)) }
            self.lock.unlock()
        }
    }

    func run() throws -> Data {
        try start()
        defer { finish() }
        // Refresh the persisted ChatGPT credential first. Sending rateLimits/read
        // concurrently can race the refresh and intermittently fail on cold sessions.
        try send(#"{"method":"account/read","id":2,"params":{"refreshToken":true}}"#)
        let account = try readResponse(id: 2)
        try send(#"{"method":"account/rateLimits/read","id":3}"#)
        let rateLimits = try readResponse(id: 3)
        let data = account + Data([0x0A]) + rateLimits + Data([0x0A])
        try checkCancellation()
        return data
    }

    func runAccountUsage() throws -> Data {
        try start()
        defer { finish() }
        // A proactive refresh is required on some persisted ChatGPT sessions;
        // without it account/usage/read can time out even though account/read succeeds.
        try send(#"{"method":"account/read","id":2,"params":{"refreshToken":true}}"#)
        _ = try readResponse(id: 2)
        try send(#"{"method":"account/usage/read","id":4}"#)
        let usage = try readResponse(id: 4)
        try checkCancellation()
        return usage
    }

    private func start() throws {
        lock.lock()
        let wasStopped = stopped
        lock.unlock()
        guard !wasStopped else { throw CancellationError() }

        try process.run()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let initialize = #"{"method":"initialize","id":1,"params":{"clientInfo":{"name":"codex_usage_monitor","title":"Codex Usage Monitor","version":"__VERSION__"},"capabilities":{"experimentalApi":true}}}"#
            .replacingOccurrences(of: "__VERSION__", with: version)
        try send(initialize)
        _ = try readResponse(id: 1)
        try send(#"{"method":"initialized"}"#)
    }

    private func finish() {
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        let deadline = Date.now.addingTimeInterval(1)
        while process.isRunning, Date.now < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning { process.interrupt() }
        errorOutput.fileHandleForReading.readabilityHandler = nil
    }

    private func checkCancellation() throws {
        lock.lock()
        let wasCancelled = stopped
        lock.unlock()
        if wasCancelled { throw CancellationError() }
    }

    private func send(_ message: String) throws {
        guard let data = (message + "\n").data(using: .utf8) else {
            throw LocalCodexSessionError.invalidResponse
        }
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    private func readResponse(id expectedID: Int) throws -> Data {
        for _ in 0..<100 {
            let line = try readLine()
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = (object["id"] as? NSNumber)?.intValue,
                  id == expectedID else { continue }
            if let error = object["error"] as? [String: Any] {
                throw CodexAppServerClient.mappedProtocolError(error["message"] as? String ?? "未知服务错误")
            }
            return line
        }
        throw LocalCodexSessionError.invalidResponse
    }

    private func readLine() throws -> Data {
        while readBuffer.count < 1_048_576 {
            if let newline = readBuffer.firstIndex(of: 0x0A) {
                let line = Data(readBuffer[..<newline])
                readBuffer.removeSubrange(...newline)
                return line
            }
            try checkCancellation()
            let descriptor = output.fileHandleForReading.fileDescriptor
            var pollState = pollfd(fd: descriptor, events: Int16(POLLIN | POLLHUP | POLLERR), revents: 0)
            let pollResult = Darwin.poll(&pollState, 1, 250)
            if pollResult < 0 {
                if errno == EINTR { continue }
                throw processFailure()
            }
            if pollResult == 0 { continue }

            var bytes = [UInt8](repeating: 0, count: 4096)
            let count = Darwin.read(descriptor, &bytes, bytes.count)
            if count < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                throw processFailure()
            }
            guard count > 0 else { throw processFailure() }
            readBuffer.append(contentsOf: bytes.prefix(count))
        }
        throw LocalCodexSessionError.invalidResponse
    }

    private func processFailure() -> LocalCodexSessionError {
        lock.lock()
        let captured = stderrBuffer
        lock.unlock()
        guard let message = String(data: captured, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else { return .serverFailure }
        return .protocolFailure(SensitiveDataRedactor().redact(String(message.prefix(500))))
    }

    func stop() {
        lock.lock()
        stopped = true
        let shouldTerminate = process.isRunning
        lock.unlock()
        if shouldTerminate { process.terminate() }
        try? input.fileHandleForWriting.close()
        try? output.fileHandleForReading.close()
    }
}
