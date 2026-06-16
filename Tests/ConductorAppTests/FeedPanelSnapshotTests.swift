@testable import ConductorApp
import ConductorCore
import AppKit
import SwiftUI
import XCTest

@MainActor
final class FeedPanelSnapshotTests: XCTestCase {
    func testRenderSnapshot() throws {
        let center = FeedCenter(store: .inMemory)
        let r1 = FeedRequest(agent: "claude",
                             kind: .permission(tool: "Bash", category: .executeCommand,
                                               detail: "git push origin main --force"))
        let r2 = FeedRequest(agent: "codex",
                             kind: .exitPlan(plan: "1. 重构鉴权模块\n2. 补端到端测试\n3. 跑 CI 并修复"))
        Task { await center.submit(r1, timeout: 0) }
        Task { await center.submit(r2, timeout: 0) }

        // 泵主 runloop：让 submit 的 Task 跑起来把请求入队
        let deadline = Date().addingTimeInterval(3)
        while center.pending.count < 2, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertEqual(center.pending.count, 2)

        let view = FeedPanelView(feedCenter: center, onClose: {})
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 360, height: 560)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))   // 让 SwiftUI 渲染
        hosting.layoutSubtreeIfNeeded()

        let bounds = hosting.bounds
        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: bounds))
        hosting.cacheDisplay(in: bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("feed-panel-snapshot.png")
        try png.write(to: url)
        print("FEED_SNAPSHOT_PATH=\(url.path) bytes=\(png.count)")

        // 真断言：采样网格，确认面板确实画出了内容（按钮/文字比深色背景亮），不是空白板。
        var lit = 0
        let step = 4
        for x in stride(from: 0, to: rep.pixelsWide, by: step) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: step) {
                guard let color = rep.colorAt(x: x, y: y) else { continue }
                let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
                if brightness > 0.35 { lit += 1 }
            }
        }
        XCTAssertGreaterThan(lit, 300, "审批面板疑似空白渲染（亮像素过少）")

        center.resolve(id: r1.id, decision: .deny(.once))
        center.resolve(id: r2.id, decision: .deny(.once))
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
}
