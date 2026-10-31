import AppKit
import SwiftUI
import WebKit

struct LeaderboardDashboardView: View {
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Label("Token League · 日榜 / 周榜 / 月榜",systemImage:"trophy")
                Spacer()
                Button("连接与同步设置") {
                    UserDefaults.standard.set(SettingsSection.leaderboard.rawValue,forKey:SettingsSection.preferenceKey)
                    openSettings()
                    NSApp.activate()
                }
                Link("在浏览器打开",destination:LeaderboardConfiguration.siteURL)
            }.font(.subheadline)
            LeaderboardWebView().frame(height:760)
                .clipShape(RoundedRectangle(cornerRadius:14))
            Text("公开榜单只显示用户自定义 ID 和有效 Token；登录及设备授权在浏览器中完成。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct LeaderboardWebView: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context:Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame:.zero,configuration:configuration)
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url:LeaderboardConfiguration.siteURL))
        return view
    }
    func updateNSView(_ view:WKWebView, context:Context) {}
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if url.host != LeaderboardConfiguration.siteURL.host || url.path.hasPrefix("/signin-with-chatgpt") || action.targetFrame == nil {
                if let scheme = url.scheme, ["https","http"].contains(scheme) { NSWorkspace.shared.open(url) }
                decisionHandler(.cancel)
            } else { decisionHandler(.allow) }
        }
    }
}
