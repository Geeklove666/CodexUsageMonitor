import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let history: UsageHistoryStore
    let monitor: UsageMonitoringService
    @Environment(WebViewSession.self) private var session
    @Environment(\.openWindow) private var openWindow
    @AppStorage(AppPreferences.Key.showDockIcon) private var showDockIcon = false
    @AppStorage(AppPreferences.Key.autoRefreshSeconds) private var autoRefreshSeconds = AutoRefreshFrequency.defaultValue.rawValue
    @AppStorage(AppPreferences.Key.notificationsEnabled) private var notifications = false
    @AppStorage(AppPreferences.Key.retentionDays) private var retentionDays = AppConfiguration.Persistence.defaultRetentionDays
    @AppStorage(AppPreferences.Key.debugMode) private var debugMode = false
    @AppStorage(AppPreferences.Key.notifyEvery20) private var notifyEvery20 = true
    @AppStorage(AppPreferences.Key.notifyReset) private var notifyReset = true
    @AppStorage(LocalCodexSessionAuthorization.preferenceKey) private var localCodexLogin = false
    @AppStorage(LocalRealtimeTokenAuthorization.preferenceKey) private var localRealtimeTokenUsage = false
    @AppStorage(LocalClaudeUsageAuthorization.preferenceKey) private var localClaudeUsage = false
    @State private var model = SettingsModel()
    @State private var selection: SettingsSection = .general
    @State private var showsLocalCodexConsent = false
    @State private var showsRealtimeTokenConsent = false
    @State private var showsClearAllConfirmation = false
    @State private var showsClaudeUsageConsent = false
    @State private var exportPayload: UsageExportPayload?
    @State private var showsExporter = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                SettingsNavigationBar(selection: $selection)
                ScrollView {
                    VStack(alignment: .leading, spacing: AppleUI.spacingL) {
                        SectionHeading(title: selection.title, subtitle: selection.subtitle)
                        Group {
                            switch selection {
                            case .general: generalSettings
                            case .dataSources: dataSourceSettings
                            case .notifications: notificationSettings
                            case .privacy: privacySettings
                            }
                        }
                    }
                    .padding(AppleUI.contentPadding)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 500, idealHeight: 560)
        .alert("允许读取本机实时 Token 事件？", isPresented: $showsRealtimeTokenConsent) {
            Button("授权并启用") {
                localRealtimeTokenUsage = true
                monitor.updateLocalUsageMonitoring()
                Task { await monitor.refresh() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("应用只扫描 ~/.codex/sessions 中最近 7 天结构化 token_count 事件的时间戳、总量与缓存命中量；每日有效 Token 会扣除缓存输入。不会提取或保存提示词、代码、工具输出、文件路径或消息正文，可随时撤销授权。")
        }
        .alert("允许使用本机 Codex 登录读取额度？", isPresented: $showsLocalCodexConsent) {
            Button("授权并刷新") {
                localCodexLogin = true
                Task {
                    await model.refreshLocalCodexStatus()
                    await monitor.refresh()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("应用会调用 OpenAI 签名的本机 codex 命令，通过 Codex 登录会话读取额度数据；不会直接读取 auth.json，也不会保存 Token。该链路依赖 Codex app-server，本应用会在界面中标明数据来源并保留官方网页登录作为回退。")
        }
        .alert("清除全部本地数据？", isPresented: $showsClearAllConfirmation) {
            Button("确认清除", role: .destructive) {
                Task {
                    await session.clearLoginState()
                    try? history.clear()
                    clearOrdinarySettings()
                    model.message = "本地数据与数据源授权已清除"
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会清除历史、OpenAI 网页登录状态、本机 Codex 授权、实时 Token 授权与 Claude Code 本机用量授权。下次刷新需要重新登录或重新授权。")
        }
        .alert("允许读取本机 Claude Code 用量？", isPresented: $showsClaudeUsageConsent) {
            Button("授权并启用") {
                localClaudeUsage = true
                monitor.updateLocalUsageMonitoring()
                Task { await monitor.refreshLocalUsage(reason: "启用 Claude Code 本机用量") }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("应用只读取 ~/.claude/projects 中结构化的 Token 数量、消息 ID 与时间戳，用于汇总最近 7 天本机用量；不会读取或保存提示词、回复、代码、工具输出和认证凭据。该数据不代表 Claude 套餐剩余额度。")
        }
        .fileExporter(
            isPresented: $showsExporter,
            document: exportPayload?.document,
            contentType: exportPayload?.contentType ?? .json,
            defaultFilename: exportPayload?.defaultFilename
        ) { result in
            switch result {
            case .success: model.message = "导出完成"
            case let .failure(error): model.message = "导出失败：\(SensitiveDataRedactor().redact(error.localizedDescription))"
            }
            exportPayload = nil
        }
        .task {
            await model.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshLaunchAtLoginState()
        }
    }

    private var generalSettings: some View {
        AppleCard {
            VStack(spacing: 0) {
                SettingsRow(symbol: "macwindow", color: AppleUI.accent, title: "显示 Dock 图标", detail: "重启应用后生效") {
                    Toggle("", isOn: $showDockIcon).labelsHidden()
                }
                rowDivider
                SettingsRow(symbol: "clock.arrow.circlepath", color: AppleUI.purple,
                            title: "自动刷新频率", detail: selectedRefreshFrequency.detail) {
                    Picker("自动刷新频率", selection: refreshFrequencyBinding) {
                        ForEach(AutoRefreshFrequency.allCases) { frequency in
                            Text(frequency.label).tag(frequency.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
                rowDivider
                SettingsRow(symbol: "power.circle.fill", color: AppleUI.success,
                            title: "随 Codex 使用自动启动",
                            detail: "通过 macOS 登录项静默启动，打开 Codex 时监控已就绪") {
                    Toggle("", isOn: launchAtLoginBinding).labelsHidden()
                        .help("在登录 Mac 后自动启动 Codex Usage Monitor")
                }
                if model.launchAtLoginState == .requiresApproval || model.launchAtLoginState == .unavailable || model.launchAtLoginError != nil {
                    HStack(spacing: 8) {
                        Label(model.launchAtLoginError ?? model.launchAtLoginState.message, systemImage: model.launchAtLoginState.symbol)
                            .font(.caption)
                            .foregroundStyle(AppleUI.warning)
                        Spacer()
                        if model.launchAtLoginState == .requiresApproval {
                            Button("打开登录项设置") { LaunchAtLoginService().openSystemSettings() }
                                .buttonStyle(.link)
                                .help("在系统设置中允许 Codex Usage Monitor 登录项")
                        }
                    }
                    .padding(.leading, 43)
                    .padding(.vertical, 5)
                }
                rowDivider
                SettingsRow(symbol: "calendar", color: AppleUI.warning, title: "历史保留") {
                    Picker("历史保留", selection: $retentionDays) {
                        Text("7 天").tag(7); Text("30 天").tag(30); Text("90 天").tag(90)
                    }
                    .labelsHidden().frame(width: 110)
                }
                rowDivider
                SettingsRow(symbol: "ladybug.fill", color: AppleUI.purple, title: "调试模式", detail: "记录额外刷新流程；所有日志均经过敏感信息脱敏") {
                    Toggle("", isOn: $debugMode).labelsHidden()
                }
            }
        }
    }

    private var notificationSettings: some View {
        VStack(spacing: 14) {
            AppleCard {
                SettingsRow(symbol: "bell.badge.fill", color: AppleUI.danger, title: "额度通知", detail: "每消耗 20% 或额度重置时提醒") {
                    Toggle("", isOn: $notifications).labelsHidden().onChange(of: notifications) { _, enabled in
                        if enabled {
                            Task {
                                let granted = await model.requestNotificationAuthorization()
                                if !granted { notifications = false }
                            }
                        }
                    }
                }
            }

            Label(model.notificationAuthorization.label,
                  systemImage: model.notificationAuthorization.canDeliver ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundStyle(model.notificationAuthorization.canDeliver ? AppleUI.success : AppleUI.warning)
                .frame(maxWidth: .infinity, alignment: .leading)
            AppleCard {
                VStack(spacing: 0) {
                    notificationRow("每消耗 20%", symbol: "20.circle.fill", binding: $notifyEvery20)
                    rowDivider
                    notificationRow("额度重置", symbol: "arrow.counterclockwise.circle.fill", binding: $notifyReset)
                }
                .disabled(!notifications)
                .opacity(notifications ? 1 : 0.48)
            }
        }
    }

    private var dataSourceSettings: some View {
        VStack(spacing: 14) {
            AppleCard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 14) {
                        SymbolTile(symbol: "terminal.fill", color: AppleUI.accent)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("本机 Codex 登录").font(.body.weight(.semibold))
                            Text("优先使用这台 Mac 已登录的 Codex 额度数据；仅调用 OpenAI 签名的 codex 命令，不直接读取或保存 Token。")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        Toggle("", isOn: localCodexAuthorizationBinding)
                            .labelsHidden()
                            .help("授权或撤销本机 Codex 额度读取")
                    }

                    Divider().opacity(0.28).padding(.vertical, 13)

                    Label(model.localCodexStatus.label, systemImage: localCodexStatusSymbol)
                        .font(.subheadline)
                        .foregroundStyle(localCodexStatusColor)
                        .accessibilityLabel(model.localCodexStatus.label)

                    Divider().opacity(0.28).padding(.vertical, 13)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { localCodexButtons }
                        VStack(spacing: 10) { localCodexButtons }
                    }
                }
            }

            AppleCard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 14) {
                        SymbolTile(symbol: "safari.fill", color: AppleUI.accent)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("OpenAI 官方页面登录").font(.body.weight(.semibold))
                            Text("额度与工作区分析均由本应用隔离的 WebKit 会话读取；登录 Cookie 和凭据不会暴露给应用代码。")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        Button("打开登录") {
                            openWindow(id: "login")
                            session.openUsagePage()
                            NSApp.activate()
                        }
                        .buttonStyle(GlassButtonStyle())
                    }

                    Divider().opacity(0.28).padding(.vertical, 13)

                    Label(officialPageStatusText, systemImage: officialPageStatusSymbol)
                        .font(.subheadline)
                        .foregroundStyle(officialPageStatusColor)
                        .accessibilityLabel(officialPageStatusText)

                    Divider().opacity(0.28).padding(.vertical, 13)

                    SettingsRow(symbol: "bolt.horizontal.circle.fill", color: AppleUI.accent,
                                title: "本机每日有效 Token", detail: "汇总最近 7 天 token_count 并扣除缓存输入；不读取会话正文") {
                        Toggle("", isOn: realtimeTokenAuthorizationBinding).labelsHidden()
                            .help("授权或撤销本机实时 Token 统计")
                    }
                }
            }

            AppleCard {
                SettingsRow(
                    symbol: "sparkles.rectangle.stack",
                    color: AppleUI.purple,
                    title: "本机 Claude Code 用量",
                    detail: "最近 7 天结构化 Token 统计；不读取会话正文，不代表套餐额度"
                ) {
                    Toggle("", isOn: localClaudeUsageBinding).labelsHidden()
                        .help("授权或撤销本机 Claude Code 用量统计")
                }
            }

            Text("启用本机 Codex 后会优先读取这台 Mac 的 Codex 额度；不可用时回退到 OpenAI 官方页面、最近有效缓存与本地趋势估算。Codex 与 Claude Code 的本机 Token 统计均为独立授权，不参与登录。")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }

    private var privacySettings: some View {
        VStack(spacing: 18) {
            AppleCard {
                HStack(alignment: .top, spacing: 14) {
                    SymbolTile(symbol: "hand.raised.fill", color: AppleUI.success)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("隐私优先").font(.headline)
                        Text("用量历史完全保存在本机。网页登录状态只存在于本应用隔离的 WebKit 数据存储中。")
                            .font(.body).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            AppleCard {
                VStack(spacing: 12) {
                    privacyButton("导出用量数据（JSON）", symbol: "square.and.arrow.up", destructive: false) {
                        prepareExport { try UsageExportService().usageJSON(
                            current: monitor.snapshot,
                            providers: monitor.providerSnapshots,
                            history: history
                        ) }
                    }
                    privacyButton("导出历史记录（CSV）", symbol: "tablecells", destructive: false) {
                        prepareExport { try UsageExportService().historyCSV(history: history) }
                    }
                    privacyButton("导出脱敏诊断报告", symbol: "stethoscope", destructive: false) {
                        prepareExport { try UsageExportService().diagnosticJSON(
                            snapshot: monitor.snapshot,
                            providers: monitor.providerSnapshots,
                            providerFailures: monitor.providerFailures,
                            diagnostic: monitor.diagnostic,
                            persistenceWarning: monitor.persistenceWarning
                        ) }
                    }
                    privacyButton("清除网页登录状态", symbol: "person.crop.circle.badge.xmark", destructive: false) {
                        Task { await session.clearLoginState(); model.message = "登录状态已清除" }
                    }
                    privacyButton("清除历史记录", symbol: "clock.badge.xmark", destructive: true) {
                        do { try history.clear(); model.message = "历史已清除" } catch { model.message = "清除失败" }
                    }
                    privacyButton("清除全部本地数据", symbol: "trash.fill", destructive: true) {
                        showsClearAllConfirmation = true
                    }
                }
            }
            if let message = model.message {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.subheadline).foregroundStyle(AppleUI.success)
                    .transition(.opacity)
            }
        }
    }

    private var rowDivider: some View { Divider().opacity(0.35).padding(.leading, 45) }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding {
            model.launchAtLoginState.isSelected
        } set: { enabled in
            model.setLaunchAtLogin(enabled)
        }
    }

    private var selectedRefreshFrequency: AutoRefreshFrequency {
        AutoRefreshFrequency(rawValue: autoRefreshSeconds) ?? .defaultValue
    }

    private var refreshFrequencyBinding: Binding<Int> {
        Binding {
            AutoRefreshFrequency.sanitizedSeconds(autoRefreshSeconds)
        } set: { newValue in
            autoRefreshSeconds = AutoRefreshFrequency.sanitizedSeconds(newValue)
            monitor.restartRefreshLoop()
        }
    }

    private var realtimeTokenAuthorizationBinding: Binding<Bool> {
        Binding {
            localRealtimeTokenUsage
        } set: { enabled in
            if enabled {
                showsRealtimeTokenConsent = true
            } else {
                localRealtimeTokenUsage = false
                monitor.updateLocalUsageMonitoring()
                Task { await monitor.refresh() }
            }
        }
    }

    private var localCodexAuthorizationBinding: Binding<Bool> {
        Binding {
            localCodexLogin
        } set: { enabled in
            if enabled {
                showsLocalCodexConsent = true
            } else {
                localCodexLogin = false
                Task {
                    await model.refreshLocalCodexStatus()
                    await monitor.refresh()
                }
            }
        }
    }

    private var localClaudeUsageBinding: Binding<Bool> {
        Binding {
            localClaudeUsage
        } set: { enabled in
            if enabled {
                showsClaudeUsageConsent = true
            } else {
                localClaudeUsage = false
                monitor.updateLocalUsageMonitoring()
                Task { await monitor.refreshLocalUsage(reason: "撤销 Claude Code 本机用量") }
            }
        }
    }

    @ViewBuilder private var localCodexButtons: some View {
        Button {
            Task { await model.refreshLocalCodexStatus() }
        } label: {
            Label("检查登录状态", systemImage: "checkmark.shield")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(GlassButtonStyle())

        Button {
            Task { await model.startLocalCodexLogin() }
        } label: {
            Label("打开 Codex 登录", systemImage: "person.crop.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(GlassButtonStyle())
    }

    private var localCodexStatusSymbol: String {
        switch model.localCodexStatus {
        case .loggedIn: "checkmark.shield.fill"
        case .loggedOut: "person.crop.circle.badge.exclamationmark"
        case .unavailable: "exclamationmark.triangle.fill"
        }
    }

    private var localCodexStatusColor: Color {
        switch model.localCodexStatus {
        case .loggedIn: AppleUI.success
        case .loggedOut, .unavailable: AppleUI.warning
        }
    }

    private var officialPageStatusText: String {
        if session.hasLoadedUsagePage { return "已登录 · OpenAI 官方页面数据可用" }
        return "需要在应用内完成 OpenAI 登录"
    }

    private var officialPageStatusSymbol: String {
        session.hasLoadedUsagePage ? "checkmark.shield.fill" : "person.crop.circle.badge.exclamationmark"
    }

    private var officialPageStatusColor: Color {
        session.hasLoadedUsagePage ? AppleUI.success : AppleUI.warning
    }

    private func notificationRow(_ title: String, symbol: String, binding: Binding<Bool>) -> some View {
        SettingsRow(symbol: symbol, color: AppleUI.accent, title: title) {
            Toggle("", isOn: binding).labelsHidden()
        }
    }

    private func privacyButton(_ title: String, symbol: String, destructive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).symbolRenderingMode(.hierarchical)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
            .foregroundStyle(destructive ? AppleUI.danger : AppleUI.accent)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .frame(height: 46)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: AppleUI.smallRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func clearOrdinarySettings() {
        UserDefaults.standard.removeObject(forKey: LocalCodexSessionAuthorization.preferenceKey)
        UserDefaults.standard.removeObject(forKey: LocalRealtimeTokenAuthorization.preferenceKey)
        UserDefaults.standard.removeObject(forKey: LocalClaudeUsageAuthorization.preferenceKey)
        monitor.updateLocalUsageMonitoring()
        for key in UserDefaults.standard.dictionaryRepresentation().keys
            where key.hasPrefix("notified.") || key.hasPrefix("consumption.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }


    private func prepareExport(_ builder: () throws -> UsageExportPayload) {
        do {
            exportPayload = try builder()
            showsExporter = true
        } catch {
            model.message = "导出失败：\(SensitiveDataRedactor().redact(error.localizedDescription))"
        }
    }
}
