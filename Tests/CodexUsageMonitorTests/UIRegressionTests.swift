import SwiftUI
import XCTest
@testable import CodexUsageMonitor

@MainActor
final class NativeUISnapshotSmokeTests: XCTestCase {
    func testButtonPressFeedbackChangesOnlyLocalAppearance() {
        let idle = StableButtonPressFeedback(isPressed: false)
        let pressed = StableButtonPressFeedback(isPressed: true)

        XCTAssertLessThan(pressed.contentOpacity, idle.contentOpacity)
        XCTAssertGreaterThan(pressed.fillOpacity, idle.fillOpacity)
    }

    func testDesignSystemDoesNotApplyScaleEffects() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("CodexUsageMonitor/Shared/Components/AppleDesignSystem.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains(".scaleEffect("))
        XCTAssertTrue(source.contains("#if compiler(>=6.2)"),
                      "Liquid Glass APIs must remain compilable with the Xcode 16.4 CI toolchain.")
    }

    func testDashboardFollowsDesignChecklistStructure() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let dashboardDirectory = repositoryRoot
            .appendingPathComponent("CodexUsageMonitor/Features/Dashboard")
        var source = try ["DashboardView.swift", "DashboardComponents.swift", "DashboardModels.swift"]
            .map { try String(contentsOf: dashboardDirectory.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")
        source += try String(contentsOf: repositoryRoot
            .appendingPathComponent("CodexUsageMonitor/Domain/UsagePresentationState.swift"), encoding: .utf8)

        for destination in ["概览", "使用历史", "告警", "数据来源", "设置"] {
            XCTAssertTrue(source.contains(destination), "Missing dashboard destination: \(destination)")
        }
        for state in ["live", "loading", "cached", "estimated", "offline", "needsLogin", "failed", "unavailable", "exhausted"] {
            XCTAssertTrue(source.contains("case \(state)"), "Missing dashboard state: \(state)")
        }
        for plan in ["$0/月", "$8/月", "$20/月", "$100/月", "$200/月"] {
            XCTAssertTrue(source.contains(plan), "Missing US pricing baseline: \(plan)")
        }
        XCTAssertTrue(source.contains("自动刷新频率"))
        XCTAssertTrue(source.contains("AutoRefreshFrequency.allCases"))
        XCTAssertTrue(source.contains("真实刷新诊断"))
        XCTAssertTrue(source.contains("Label(\"OpenAI 登录\", systemImage: \"person.crop.circle\")"))
        XCTAssertTrue(source.contains("Label(\"刷新真实来源\", systemImage: \"arrow.clockwise\")"))
        XCTAssertTrue(source.contains(".buttonStyle(.bordered)"))
        XCTAssertTrue(source.contains("DashboardQuotaSnapshot.make(snapshot: monitor.snapshot"))
        XCTAssertTrue(source.contains("historyModel.points"))
        XCTAssertFalse(source.contains("GlassButtonStyle(tint: AppleUI.accent)"),
                       "Dashboard actions should use neutral glass instead of a saturated blue fill.")
        XCTAssertFalse(source.contains("DemoTrendPoint"))
        XCTAssertFalse(source.contains("DemoAlertRule"))
        XCTAssertFalse(source.contains("Picker(\"Demo 状态\""))
        XCTAssertFalse(source.contains("Demo 界面壳"))
        XCTAssertFalse(source.contains("Demo 数值"))
        XCTAssertFalse(source.contains(".glassEffect("), "Dashboard content must not apply glassEffect directly.")
    }

    func testEnabledLocalCodexMenuActionDoesNotStartLoginFlow() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("CodexUsageMonitor/Features/MenuBar/MenuBarViews.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("localCodexLogin ? \"刷新本机 Codex\" : \"启用本机 Codex\""))
        XCTAssertFalse(source.contains("try? await LocalCodexLoginProbe().startLogin()"))
    }

    func testMenuBarTitleUsesSystemLabelColor() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("CodexUsageMonitor/Features/MenuBar/MenuBarController.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains(".foregroundColor: NSColor.labelColor"))
        XCTAssertFalse(source.contains("MenuBarQuotaLevel(remainingPercentage: $0).color"))
        XCTAssertFalse(source.contains("NSColor(labelColor:"))
    }

    func testMenuPanelPositionUsesButtonBoundsConvertedToWindowCoordinates() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("CodexUsageMonitor/Features/MenuBar/MenuBarController.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("button.convert(button.bounds, to: nil)"))
        XCTAssertFalse(source.contains("buttonWindow.convertToScreen(button.frame)"))
    }

    func testMenuPanelRootBackgroundAvoidsOversaturatedFirstOpenMaterial() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("CodexUsageMonitor/Features/MenuBar/MenuBarViews.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("Color(red: 0.965, green: 0.960, blue: 0.955)"))
        XCTAssertFalse(source.contains("shape.fill(Color(nsColor: .windowBackgroundColor))"))
        XCTAssertFalse(source.contains("Color(nsColor: .windowBackgroundColor).opacity(0.94)"))
        XCTAssertFalse(source.contains("Color(nsColor: .windowBackgroundColor).opacity(0.82)"))
        XCTAssertFalse(source.contains("shape.fill(.regularMaterial)"))
        XCTAssertFalse(source.contains("shape.fill(.thinMaterial)"))
        XCTAssertFalse(source.contains("shape.fill(.ultraThinMaterial)"))
        XCTAssertFalse(source.contains("systemPink).opacity(0.16)"))
    }

    func testCardsKeepNeutralFillOverMaterial() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("CodexUsageMonitor/Shared/Components/AppleDesignSystem.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("Color(nsColor: .controlBackgroundColor).opacity(0.66)"))
        XCTAssertTrue(source.contains("Color(red: 0.985, green: 0.982, blue: 0.978)"))
        XCTAssertFalse(source.contains("shape.fill(Color(nsColor: .controlBackgroundColor))"))
    }

    func testMenuCompactCardsUseStableNonSamplingBackgrounds() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let menuSource = try String(contentsOf: repositoryRoot
            .appendingPathComponent("CodexUsageMonitor/Features/MenuBar/MenuBarViews.swift"), encoding: .utf8)
        let monitoringSource = try String(contentsOf: repositoryRoot
            .appendingPathComponent("CodexUsageMonitor/Shared/Components/MonitoringComponents.swift"), encoding: .utf8)
        let analyticsSource = try String(contentsOf: repositoryRoot
            .appendingPathComponent("CodexUsageMonitor/Shared/Components/AnalyticsComponents.swift"), encoding: .utf8)

        XCTAssertTrue(menuSource.contains("AppleCard(padding: 11, cornerRadius: AppleUI.cardRadius, material: nil)"))
        XCTAssertTrue(monitoringSource.contains("AppleCard(padding: 12, cornerRadius: AppleUI.cardRadius, material: nil)"))
        XCTAssertTrue(analyticsSource.contains("AppleCard(padding: 9, cornerRadius: AppleUI.cardRadius, material: nil)"))
    }

    func testCompactUsageSummaryRendersAtMenuWidth() throws {
        let snapshot = CodexUsageSnapshot(
            primaryWindow: UsageLimitWindow(kind: .primary, remainingPercentage: 64, usedPercentage: 36, resetsAt: .now.addingTimeInterval(3600), durationDescription: "5 小时"),
            secondaryWindow: UsageLimitWindow(kind: .secondary, remainingPercentage: 82, usedPercentage: 18, resetsAt: .now.addingTimeInterval(7200), durationDescription: "1 周"),
            resetAllowance: UsageResetAllowance(availableCount: 3),
            sourceKind: .officialWebPage, sourceDisplayName: "test", confidence: .high, fieldCompleteness: 0.75
        )
        let renderer = ImageRenderer(content: CompactUsageSummary(snapshot: snapshot, now: .now).frame(width: 354))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertGreaterThan(image.width, 350)
        XCTAssertGreaterThan(image.height, 100)
    }


    func testCompactAnalyticsKeepsStableHeightWhileSourceSwitches() throws {
        let fixtureURL = try XCTUnwrap(Bundle.module.url(forResource: "analytics-partial", withExtension: "json"))
        let analytics = try OfficialAnalyticsParser().parse(data: Data(contentsOf: fixtureURL))
        let emptyRenderer = ImageRenderer(content: CompactAnalyticsSummary(analytics: nil).frame(width: 354))
        let loadedRenderer = ImageRenderer(content: CompactAnalyticsSummary(analytics: analytics).frame(width: 354))
        emptyRenderer.scale = 1
        loadedRenderer.scale = 1
        let emptyImage = try XCTUnwrap(emptyRenderer.cgImage)
        let loadedImage = try XCTUnwrap(loadedRenderer.cgImage)
        XCTAssertEqual(emptyImage.height, loadedImage.height)
        XCTAssertGreaterThan(emptyImage.height, 60)
    }
}
