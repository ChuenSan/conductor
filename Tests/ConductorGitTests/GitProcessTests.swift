import XCTest
@testable import ConductorGit

final class GitProcessTests: XCTestCase {
    func testResolvesGitExecutable() {
        XCTAssertNotNil(GitExecutable.resolve(), "测试环境应能找到 git")
    }

    func testRunVersionSucceeds() async throws {
        let result = try await GitProcess(repository: nil, ["--version"]).run()
        XCTAssertTrue(result.isSuccess)
        XCTAssertTrue(result.stdout.hasPrefix("git version"))
    }

    func testNonZeroExitThrows() async {
        do {
            _ = try await GitProcess(repository: nil, ["definitely-not-a-command"]).run()
            XCTFail("非法子命令应抛错")
        } catch let GitError.failed(code, _) {
            XCTAssertNotEqual(code, 0)
        } catch {
            XCTFail("应是 GitError.failed，实际：\(error)")
        }
    }

    func testAllowFailureReturnsResult() async throws {
        let result = try await GitProcess(repository: nil, ["definitely-not-a-command"])
            .run(allowFailure: true)
        XCTAssertFalse(result.isSuccess)
    }

    func testDiscoverFindsToplevel() async throws {
        let repo = try TempGitRepo()
        // 从子目录也应能发现仓库根。
        try FileManager.default.createDirectory(
            at: repo.url.appendingPathComponent("sub/dir"), withIntermediateDirectories: true)
        let discovered = await GitRepository.discover(at: repo.url.appendingPathComponent("sub/dir").path)
        XCTAssertNotNil(discovered)
        // macOS 临时目录可能含 /private 前缀软链，比较 standardized 后的真实路径。
        XCTAssertEqual(
            discovered.map { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path },
            URL(fileURLWithPath: repo.path).resolvingSymlinksInPath().path)
    }

    func testDiscoverReturnsNilOutsideRepo() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("conductor-git-nonrepo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let discovered = await GitRepository.discover(at: tmp.path)
        XCTAssertNil(discovered)
    }

    func testCleanErrorStripsNoise() {
        let raw = """
        hint: do this
        remote: Counting objects: 100% done
        Receiving objects:  42% (3/7)
        fatal: real error here
        """
        XCTAssertEqual(GitProcess.cleanError(raw), "fatal: real error here")
    }
}
