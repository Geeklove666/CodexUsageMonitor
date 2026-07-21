import AppKit
import Foundation
import Observation
import WebKit

enum OfficialPageConfiguration {
    static let usageURL = URL(string: "https://chatgpt.com/codex/settings/usage")!
    static let analyticsURL = URL(string: "https://chatgpt.com/codex/settings/analytics")!
    static let allowedExactHosts: Set<String> = ["chatgpt.com", "chat.openai.com", "auth.openai.com", "auth0.openai.com", "openai.com"]
    static let dataHosts: Set<String> = ["chatgpt.com", "chat.openai.com"]

    static func isAuthenticatedChatPage(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              dataHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) else { return false }
        let path = url.path.lowercased()
        return path.hasPrefix("/codex/settings/usage") || path.hasPrefix("/codex/settings/analytics")
    }

    static func isAllowedNavigationHost(_ host: String) -> Bool {
        allowedExactHosts.contains(host.lowercased())
    }
}

@MainActor
@Observable
final class WebViewSession: NSObject, WKNavigationDelegate {
    @ObservationIgnored private var retainedWebView: WKWebView?
    @ObservationIgnored private var hasStartedNavigation = false
    private(set) var lastError: String?
    private(set) var hasLoadedUsagePage = false
    private(set) var currentPagePath = "尚未加载"
    var onPageReady: (() -> Void)?

    var webView: WKWebView {
        if let retainedWebView { return retainedWebView }
        let value = makeWebView()
        retainedWebView = value
        return value
    }

    override init() {
        super.init()
    }

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.isElementFullscreenEnabled = false
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.analyticsCaptureScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        let value = WKWebView(frame: .zero, configuration: configuration)
        value.navigationDelegate = self
        return value
    }

    func openUsagePage(forceReload: Bool = false) {
        guard forceReload || !hasStartedNavigation else { return }
        hasStartedNavigation = true
        lastError = nil
        // Analytics also has same-origin access to the quota endpoint and loads the
        // additional first-party monitoring responses required by the dashboard.
        webView.load(URLRequest(url: OfficialPageConfiguration.analyticsURL, cachePolicy: .reloadRevalidatingCacheData))
    }

    func prepareForBackgroundFallback() {
        openUsagePage()
    }

    func usageJSON() async throws -> Data {
        guard hasLoadedUsagePage else { throw UsageMonitorError.authenticationRequired }
        let script = Self.usageFetchScript
        do {
            let result = try await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
            guard let json = result as? String, let data = json.data(using: .utf8), !data.isEmpty else {
                throw UsageMonitorError.unsupportedResponse
            }
            return data
        } catch {
            let message = error.localizedDescription
            if message.contains("AUTH_REQUIRED") { throw UsageMonitorError.authenticationExpired }
            throw UsageMonitorError.unsupportedResponse
        }
    }

    /// Kept internal so tests can guard against JavaScript declaration regressions.
    static let usageFetchScript = #"""
        const endpoints = [
          "/backend-api/wham/usage?supports_rewardless_invites=true",
          "/wham/usage?supports_rewardless_invites=true"
        ];
        var lastStatus = 0;
        for (const endpoint of endpoints) {
          try {
            const response = await fetch(endpoint, {
              method: "GET",
              credentials: "include",
              cache: "no-store",
              headers: { "Accept": "application/json" }
            });
            lastStatus = response.status;
            if (response.ok) {
              const contentType = response.headers.get("content-type") || "";
              if (!contentType.includes("json")) continue;
              return await response.text();
            }
            if (response.status === 401 || response.status === 403) {
              throw new Error("AUTH_REQUIRED");
            }
          } catch (error) {
            if (String(error).includes("AUTH_REQUIRED")) throw error;
          }
        }
        throw new Error("USAGE_ENDPOINT_UNAVAILABLE_" + lastStatus);
        """#

    func html() async throws -> String {
        guard hasLoadedUsagePage else { throw UsageMonitorError.authenticationRequired }
        let script = #"""
        const deadline = Date.now() + 5000;
        var text = "";
        while (Date.now() < deadline) {
          text = document.body?.innerText || "";
          if (/\d{1,3}(?:\.\d+)?\s*%/.test(text)) break;
          await new Promise(resolve => setTimeout(resolve, 250));
        }
        return text;
        """#
        let result = try await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
        guard let text = result as? String, !text.isEmpty else { throw UsageMonitorError.unsupportedResponse }
        return text
    }

    /// Returns only the JSON response bodies already loaded by Codex Analytics.
    /// The page's request headers, cookies and authorization values are never inspected.
    func analyticsJSON() async throws -> Data {
        guard hasLoadedUsagePage else { throw UsageMonitorError.authenticationRequired }
        let script = Self.analyticsReadScript
        let result = try await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
        guard let json = result as? String, let data = json.data(using: .utf8), data.count > 2 else {
            throw UsageMonitorError.unsupportedResponse
        }
        return data
    }

    static let analyticsReadScript = #"""
        const deadline = Date.now() + 4500;
        var previousCount = -1;
        var stableSince = Date.now();
        while (Date.now() < deadline) {
          const value = window.__codexUsageAnalytics || {};
          const count = Object.keys(value).length;
          if (count !== previousCount) {
            previousCount = count;
            stableSince = Date.now();
          } else if (count > 0 && Date.now() - stableSince >= 600) {
            return JSON.stringify(value);
          }
          await new Promise(resolve => setTimeout(resolve, 200));
        }
        return JSON.stringify(window.__codexUsageAnalytics || {});
        """#

    private static let analyticsCaptureScript = #"""
    (() => {
      if (window.__codexUsageCaptureInstalled) return;
      window.__codexUsageCaptureInstalled = true;
      window.__codexUsageAnalytics = {};
      const allowed = /\/backend-api\/wham\/(?:analytics\/(?:daily-plugin-usage-metrics|daily-skill-usage-metrics|daily-workspace-usage-counts)|usage\/(?:daily-token-usage-breakdown|credit-usage-events))/i;
      const capture = async (urlValue, response) => {
        try {
          const url = new URL(urlValue, location.origin);
          if (!allowed.test(url.pathname) || !response.ok) return;
          window.__codexUsageAnalytics[url.pathname] = await response.clone().json();
        } catch {}
      };
      const originalFetch = window.fetch.bind(window);
      window.fetch = async (...args) => {
        const response = await originalFetch(...args);
        const input = args[0];
        const url = typeof input === "string" ? input : input?.url || "";
        capture(url, response);
        return response;
      };
      const originalOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url, ...rest) {
        this.__codexUsageURL = url;
        this.addEventListener("load", function() {
          try {
            const parsed = new URL(this.__codexUsageURL, location.origin);
            if (!allowed.test(parsed.pathname) || this.status < 200 || this.status >= 300) return;
            const value = this.responseType === "json" ? this.response : JSON.parse(this.responseText);
            window.__codexUsageAnalytics[parsed.pathname] = value;
          } catch {}
        }, { once: true });
        return originalOpen.call(this, method, url, ...rest);
      };
    })();
    """#

    func clearLoginState() async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) { continuation.resume() }
        }
        hasLoadedUsagePage = false
        hasStartedNavigation = false
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url, let host = url.host?.lowercased() else { return .cancel }
        if OfficialPageConfiguration.isAllowedNavigationHost(host) {
            return .allow
        } else {
            if navigationAction.navigationType == .linkActivated { NSWorkspace.shared.open(url) }
            return .cancel
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        currentPagePath = "\(url.host ?? "unknown")\(url.path)"
        hasLoadedUsagePage = OfficialPageConfiguration.isAuthenticatedChatPage(url)
        if hasLoadedUsagePage {
            lastError = nil
            onPageReady?()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        lastError = SensitiveDataRedactor().redact(error.localizedDescription)
    }
}

struct OfficialWebViewDataSource: CodexUsageDataSource, CodexAnalyticsDataSource {
    let identifier = "official-web-page"
    let analyticsIdentifier = "official-web-analytics"
    let displayName = "Codex Usage 官方页面"
    let sourceKind = UsageSourceKind.officialWebPage
    var parserVersion: String? { apiParser.parserVersion }
    var analyticsParserVersion: String? { analyticsParser.parserVersion }
    let session: WebViewSession
    let apiParser: OfficialUsageAPIParser
    let analyticsParser = OfficialAnalyticsParser()
    let parser: any CodexUsageDOMParser

    func availability() async -> DataSourceAvailability {
        let loaded = await session.hasLoadedUsagePage
        if !loaded { await session.prepareForBackgroundFallback() }
        return loaded ? .available : .authenticationRequired
    }
    func analyticsAvailability() async -> DataSourceAvailability {
        await session.hasLoadedUsagePage ? .available : .authenticationRequired
    }

    func fetchAnalytics() async throws -> CodexAnalyticsSnapshot {
        let data = try await session.analyticsJSON()
        return try analyticsParser.parse(data: data)
    }

    func fetchUsage() async throws -> CodexUsageSnapshot {
        let parsed: ParsedCodexUsage
        do {
            let data = try await session.usageJSON()
            parsed = try apiParser.parse(data: data)
        } catch UsageMonitorError.authenticationExpired {
            throw UsageMonitorError.authenticationExpired
        } catch {
            let html = try await session.html()
            parsed = try parser.parse(html: html)
        }
        return CodexUsageSnapshot(sourceUpdatedAt: parsed.sourceUpdatedAt, planName: parsed.planName,
            primaryWindow: parsed.primaryWindow, secondaryWindow: parsed.secondaryWindow, credits: parsed.credits,
            resetAllowance: parsed.resetAllowance, analytics: nil,
            sourceKind: .officialWebPage, sourceDisplayName: displayName, confidence: .high,
            fieldCompleteness: parsed.fieldCompleteness, expiresAt: Date.now.addingTimeInterval(300))
    }
}
