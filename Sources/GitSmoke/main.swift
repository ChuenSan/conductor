import ConductorGit
import Foundation

// 临时运行时冒烟检查（无 XCTest 环境下用）。对真实临时仓库跑各命令并断言。
// 用法：swift run GitSmoke

var failures = 0
func check(_ cond: Bool, _ label: String) {
    if cond {
        print("  ✓ \(label)")
    } else {
        print("  ✗ \(label)")
        failures += 1
    }
}

@discardableResult
func sh(_ args: [String], cwd: URL) -> String {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: GitExecutable.resolve() ?? "/usr/bin/git")
    proc.arguments = args
    proc.currentDirectoryURL = cwd
    proc.environment = GitExecutable.environment()
    let out = Pipe()
    proc.standardOutput = out
    proc.standardError = Pipe()
    try? proc.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

func makeRepo() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("gitsmoke-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    sh(["init", "-b", "main"], cwd: dir)
    sh(["config", "user.email", "smoke@conductor.local"], cwd: dir)
    sh(["config", "user.name", "Smoke"], cwd: dir)
    sh(["config", "commit.gpgsign", "false"], cwd: dir)
    return dir
}

func write(_ dir: URL, _ rel: String, _ s: String) {
    let f = dir.appendingPathComponent(rel)
    try? FileManager.default.createDirectory(
        at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? s.write(to: f, atomically: true, encoding: .utf8)
}

func main() async {
    print("== P0: GitProcess / discovery ==")
    let version = try? await GitProcess(repository: nil, ["--version"]).run()
    check(version?.stdout.hasPrefix("git version") ?? false, "git --version")

    let repoDir = makeRepo()
    defer { try? FileManager.default.removeItem(at: repoDir) }
    let discovered = await GitRepository.discover(at: repoDir.path)
    check(discovered != nil, "discover toplevel")

    await SmokeP1.run(repoDir: repoDir, check: check, write: write)
    await SmokeP2.run(check: check, makeRepo: makeRepo, write: write, sh: sh)
    await SmokeP4.run(check: check, makeRepo: makeRepo, write: write, sh: sh)
    await SmokeP6.run(check: check, makeRepo: makeRepo, write: write, sh: sh)

    print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURE(S)")
    exit(failures == 0 ? 0 : 1)
}

await main()
