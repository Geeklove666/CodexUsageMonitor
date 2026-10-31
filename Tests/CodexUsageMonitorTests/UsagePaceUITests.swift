import AppKit
import SwiftUI
import XCTest
@testable import CodexUsageMonitor

@MainActor
final class UsagePaceUITests: XCTestCase {
    func testPaceCardRendersAtNarrowAndWideWidthsInBothColorSchemes() throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let reset = now.addingTimeInterval(4 * 3600)
        let snapshot = CodexUsageSnapshot(
            fetchedAt: now,
            primaryWindow: UsageLimitWindow(kind: .primary, remainingPercentage: 20,
                usedPercentage: 80, resetsAt: reset, durationDescription: nil),
            sourceKind: .localCodexSession, sourceDisplayName: "测试来源", confidence: .high, fieldCompleteness: 1
        )
        let samples = [UsageHistorySample(
            recordedAt: now.addingTimeInterval(-3600), remainingPercentage: 30,
            resetsAt: reset, isCached: false, sourceKind: .localCodexSession
        )]
        let assessment = UsagePaceBuilder.assess(snapshot: snapshot, samples: samples, now: now)
        XCTAssertNotNil(assessment.projection)
        for width in [420.0, 880.0] {
            for scheme in [ColorScheme.light, .dark] {
                let renderer = ImageRenderer(content: UsagePaceCard(assessment: assessment)
                    .frame(width: width)
                    .environment(\.colorScheme, scheme))
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.cgImage)
                XCTAssertEqual(image.width, Int(width))
                XCTAssertGreaterThan(image.height, 250)
                XCTAssertLessThan(image.height, 700, "Card should wrap without excessive vertical growth.")
                if let directory = ProcessInfo.processInfo.environment["PACE_PREVIEW_DIR"] {
                    let root = URL(fileURLWithPath: directory, isDirectory: true)
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                    let name = "pace-\(Int(width))-\(scheme == .light ? "light" : "dark").png"
                    try data.write(to: root.appendingPathComponent(name))
                }
            }
        }
    }

    func testUnavailablePaceCardRendersExplanationWithoutForecast() throws {
        let assessment = UsagePaceAssessment.unavailable("同一额度周期内需要至少 30 分钟的连续真实记录；继续观察后会显示预测。")
        let renderer = ImageRenderer(content: UsagePaceCard(assessment: assessment).frame(width: 420))
        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertGreaterThan(image.height, 60)
        XCTAssertLessThan(image.height, 250)
    }
}
