@testable import ConductorApp
import ConductorCore
import XCTest

final class CompanionNotificationTests: XCTestCase {
    func testNoticeTextKeepsFullReply() {
        // 要的是 agent 真实回复全文（可展开），不截断、不洗成通用句。
        XCTAssertEqual(
            CompanionController.noticeText(title: "Claude · repo", body: "已经改好啦\n第二行细节"),
            "已经改好啦\n第二行细节")
    }

    func testNoticeTextFallsBackToTitleWhenBodyEmpty() {
        XCTAssertEqual(CompanionController.noticeText(title: "Codex 跑完", body: "   "), "Codex 跑完")
    }

    func testNoticeTextKeepsLongReplyIntact() {
        let long = String(repeating: "字", count: 200)
        XCTAssertEqual(CompanionController.noticeText(title: "T", body: long), long)  // 不截断
    }

    /// 宠物气泡里的「允许/拒绝」走的就是 FeedCenter.resolve——验它真能解阻塞一条待审批。
    @MainActor
    func testInlineApprovalResolvesPendingRequest() async {
        let center = FeedCenter()
        let req = FeedRequest(kind: .permission(tool: "bash", category: .executeCommand, detail: "ls"))
        let task = Task { await center.submit(req) }

        // 等 submit 把请求挂进 pending（同 actor，靠 yield 让出）。
        var spins = 0
        while center.pending.first(where: { $0.id == req.id }) == nil, spins < 1000 {
            await Task.yield(); spins += 1
        }
        XCTAssertNotNil(center.pending.first(where: { $0.id == req.id }), "请求应进入待审批队列")

        let ok = center.resolve(id: req.id, decision: .allow(.once))
        XCTAssertTrue(ok)
        let decision = await task.value
        XCTAssertEqual(decision, .allow(.once))            // 解阻塞、决策回灌
        XCTAssertNil(center.pending.first(where: { $0.id == req.id }))  // 已出队
    }
}
