import AppKit
import Observation
import SwiftUI

@MainActor @Observable
final class LeaderboardConnectionModel {
    var connected = false
    var connecting = false
    var code: String?
    var message: String?
    private var connectionTask: Task<Void,Never>?
    func load() async { connected = await LeaderboardSyncService.shared.isConnected() }
    func connect() {
        connectionTask?.cancel()
        connecting = true
        message = "正在获取设备连接码"
        connectionTask = Task { [weak self] in
            guard let self else { return }
            defer { self.connecting = false; self.code = nil }
            do {
                let start = try await LeaderboardSyncService.shared.startConnection()
                try Task.checkCancellation()
                guard start.verificationUri.scheme == "https",
                      start.verificationUri.host == LeaderboardConfiguration.siteURL.host else {
                    throw LeaderboardError.server("连接页面地址无效")
                }
                self.code = start.userCode
                self.message = "请在浏览器登录 ChatGPT，设置公开 ID 并确认设备连接"
                NSWorkspace.shared.open(start.verificationUri)
                let expires = Date.now.addingTimeInterval(Double(min(start.expiresIn,600)))
                while Date.now < expires {
                    try await Task.sleep(for: .seconds(max(5,start.interval)))
                    do {
                        let handle = try await LeaderboardSyncService.shared.finishConnection(deviceCode:start.deviceCode)
                        self.connected = true
                        self.message = "已连接 @\(handle)"
                        let result = await LeaderboardSyncService.shared.syncIfEnabled(force:true)
                        if let result { self.message = "已连接 @\(handle) · \(result)" }
                        return
                    } catch LeaderboardError.pending { continue }
                }
                throw LeaderboardError.expired
            } catch is CancellationError { self.message = "已取消连接" }
            catch { self.message = SensitiveDataRedactor().redact(error.localizedDescription) }
        }
    }
    func cancelConnection() { connectionTask?.cancel() }
    func disconnect() {
        connectionTask?.cancel()
        Task { await LeaderboardSyncService.shared.disconnect(); connected = false; message = "已停止同步并移除本机设备授权；历史排名可在网页隐藏" }
    }
    func sync() { Task { message = await LeaderboardSyncService.shared.syncIfEnabled(force:true) ?? "请先连接设备并启用同步" } }
}

struct LeaderboardSettingsView: View {
    let monitor: UsageMonitoringService
    @State private var model = LeaderboardConnectionModel()
    @State private var showsConsent = false
    @AppStorage(LeaderboardConfiguration.enabledKey) private var enabled = false
    @AppStorage(LeaderboardConfiguration.handleKey) private var handle = ""
    @AppStorage(LocalRealtimeTokenAuthorization.preferenceKey) private var localUsage = false

    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            AppleCard {
                VStack(alignment:.leading,spacing:14) {
                    SectionHeading(title:"Token League",subtitle:"把本机 Codex 有效 Token 记入日榜、周榜、月榜。")
                    Text("通过浏览器使用 ChatGPT 账号登录；Plus 用户可直接使用。设置公开 ID 后，只同步每日日期和有效 Token，不上传邮箱、对话、代码或 OpenAI 登录凭据。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if model.connected { Label("已连接 @\(handle)",systemImage:"checkmark.circle.fill").foregroundStyle(AppleUI.success) }
                    if let code = model.code { Text("连接码：\(code)").font(.title2.monospaced()) }
                    HStack {
                        Button(model.connecting ? "等待浏览器确认" : model.connected ? "更换连接账号" : "登录并连接排行榜") { showsConsent = true }
                            .buttonStyle(.borderedProminent).disabled(model.connecting)
                        if model.connecting { Button("取消") { model.cancelConnection() } }
                        Link("打开排行榜",destination:LeaderboardConfiguration.siteURL)
                    }
                    if let message = model.message { Text(message).font(.caption).foregroundStyle(.secondary).accessibilityLabel(message) }
                }
            }
            AppleCard {
                VStack(alignment:.leading,spacing:14) {
                    Toggle("自动同步我的每日有效 Token",isOn:$enabled).disabled(!model.connected)
                    Text("默认关闭。开启后每 5 分钟至多同步一次，首次补传最近 7 天的本机计数。榜单统一使用北京时间，重复同步不会累加。一个账号同时连接一台上传设备。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("立即同步") { model.sync() }.disabled(!model.connected || !enabled)
                        if model.connected { Button("断开设备",role:.destructive) { model.disconnect() } }
                    }
                    Text("关闭自动同步会停止后续上传；如需隐藏现有排名，请在网页选择“退出榜单”。本机上报不是 OpenAI 官方认证数据。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .task { await model.load() }
        .onDisappear { model.cancelConnection() }
        .alert("参与公开 Token 排行榜？",isPresented:$showsConsent) {
            Button("继续连接") { localUsage = true; monitor.updateLocalUsageMonitoring(); model.connect() }
            Button("取消",role:.cancel) {}
        } message: {
            Text("连接后会按北京时间读取这台 Mac 最近 7 天的结构化 Token 计数，并将日期和有效 Token 数上传至 Token League。网页只展示你设置的公开 ID 与用量。请在浏览器确认是你希望关联的 ChatGPT 账号；可随时关闭同步、撤销授权或退出榜单。")
        }
    }
}
