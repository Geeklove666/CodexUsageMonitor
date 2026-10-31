import Foundation
import Security

private enum LeaderboardKeychain {
    static let service = "local.codex-usage-monitor.leaderboard"
    static let account = "device-credential"
    static func load() -> LeaderboardCredential? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(LeaderboardCredential.self, from: data)
    }
    static func save(_ value: LeaderboardCredential) throws {
        let data = try JSONEncoder().encode(value)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account]
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw LeaderboardError.keychain }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw LeaderboardError.keychain }
    }
    static func clear() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
    }
}

actor LeaderboardSyncService {
    static let shared = LeaderboardSyncService()
    private let session: URLSession
    private let reader: LocalRealtimeTokenUsageReader
    private var lastAttempt: Date?
    private var syncing = false

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration)
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("local.codex-usage-monitor/leaderboard-shanghai-scan-v1.plist")
        reader = LocalRealtimeTokenUsageReader(cacheStorageURL: cache, calendar: LeaderboardConfiguration.calendar)
    }

    func isConnected() -> Bool { LeaderboardKeychain.load() != nil }

    func startConnection() async throws -> LeaderboardDeviceStart {
        let data = try await post("/api/device/start", body: ["label":"Codex Usage Monitor · Mac"])
        return try JSONDecoder().decode(LeaderboardDeviceStart.self, from: data)
    }

    func finishConnection(deviceCode: String) async throws -> String {
        let data = try await post("/api/device/token", body: ["deviceCode":deviceCode])
        try Task.checkCancellation()
        let credential = try JSONDecoder().decode(LeaderboardCredential.self, from: data)
        guard credential.accessToken.count == 64 else { throw LeaderboardError.server("设备授权响应无效") }
        try LeaderboardKeychain.save(credential)
        UserDefaults.standard.set(credential.profile.handle, forKey: LeaderboardConfiguration.handleKey)
        UserDefaults.standard.set(true, forKey: LeaderboardConfiguration.enabledKey)
        return credential.profile.handle
    }

    func syncIfEnabled(force: Bool = false) async -> String? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: LeaderboardConfiguration.enabledKey),
              defaults.bool(forKey: LocalRealtimeTokenAuthorization.preferenceKey),
              let credential = LeaderboardKeychain.load() else { return nil }
        guard !syncing else { return nil }
        if !force, let lastAttempt, Date.now.timeIntervalSince(lastAttempt) < 300 { return nil }
        syncing = true
        lastAttempt = .now
        defer { syncing = false }
        guard let analytics = await reader.currentAnalyticsSnapshot(),
              let upload = LeaderboardUpload.make(analytics: analytics) else { return "暂无可同步的本机 Token 记录" }
        // Opt-out may occur while the scanner is running. Check immediately before transmission.
        guard defaults.bool(forKey: LeaderboardConfiguration.enabledKey),
              LeaderboardKeychain.load()?.deviceId == credential.deviceId else { return nil }
        do {
            _ = try await postData("/api/usage", data: JSONEncoder().encode(upload), token: credential.accessToken)
            defaults.set(Date.now, forKey: LeaderboardConfiguration.lastSyncKey)
            return "同步完成，排行榜将在下次刷新时更新"
        } catch { return SensitiveDataRedactor().redact(error.localizedDescription) }
    }

    func disconnect() async {
        UserDefaults.standard.set(false, forKey: LeaderboardConfiguration.enabledKey)
        let credential = LeaderboardKeychain.load()
        LeaderboardKeychain.clear()
        UserDefaults.standard.removeObject(forKey: LeaderboardConfiguration.handleKey)
        if let credential { _ = try? await postData("/api/device/disconnect", data: Data("{}".utf8), token: credential.accessToken) }
    }

    private func post(_ path: String, body: [String:String]) async throws -> Data {
        try await postData(path, data: JSONEncoder().encode(body))
    }
    private func postData(_ path: String, data: Data, token: String? = nil) async throws -> Data {
        let url = LeaderboardConfiguration.siteURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data,response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw LeaderboardError.server("排行榜服务响应无效") }
        if response.statusCode == 428 { throw LeaderboardError.pending }
        if response.statusCode == 410 { throw LeaderboardError.expired }
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONDecoder().decode(ServerError.self,from:data))?.error ?? "排行榜暂时无法同步，请稍后重试"
            throw LeaderboardError.server(message)
        }
        return data
    }
    private struct ServerError: Decodable { let error: String }
}
