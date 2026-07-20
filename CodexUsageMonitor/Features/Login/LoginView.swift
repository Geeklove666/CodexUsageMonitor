import SwiftUI
import WebKit

struct LoginView: View {
    @Environment(WebViewSession.self) private var session
    var body: some View {
        VStack(spacing: 0) {
            loginHeader
            Divider().opacity(0.3)
            WebViewRepresentable(webView: session.webView)
        }
        .background { AppBackground() }
        .onAppear { session.openUsagePage() }
    }

    private var loginHeader: some View {
        HStack(spacing: 12) {
            SymbolTile(symbol: "lock.shield.fill", color: AppleUI.success)
            VStack(alignment: .leading, spacing: 2) {
                Text("在 OpenAI 官方页面安全登录").font(.headline)
                Text("请在此窗口登录；外部浏览器会话不会同步到应用")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { session.openUsagePage(forceReload: true) } label: {
                Label("重新加载", systemImage: "arrow.clockwise")
            }
            .buttonStyle(GlassButtonStyle())
            .help("重新加载官方登录与分析页面")
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 72)
        .liquidGlassSurface(cornerRadius: 20)
        .padding(10)
    }
}

struct WebViewRepresentable: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
