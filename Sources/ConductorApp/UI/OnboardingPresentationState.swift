import Foundation
import SwiftUI

struct OnboardingPresentationState: Equatable {
    private(set) var isPresented = false
    private(set) var pageIndex = 0
    let pageCount: Int

    var canGoBack: Bool { pageIndex > 0 }
    var isLastPage: Bool { pageIndex >= max(0, pageCount - 1) }

    init(pageCount: Int) {
        self.pageCount = max(1, pageCount)
    }

    mutating func open(pageIndex: Int = 0) {
        isPresented = true
        selectPage(pageIndex)
    }

    mutating func close() {
        isPresented = false
        pageIndex = 0
    }

    mutating func next() {
        selectPage(pageIndex + 1)
    }

    mutating func previous() {
        selectPage(pageIndex - 1)
    }

    mutating func selectPage(_ index: Int) {
        pageIndex = min(max(0, index), pageCount - 1)
    }
}

struct OnboardingLaunchPolicy {
    static let seenVersionKey = "onboarding.seenVersion"
    static let currentVersion = "2026.06.introduction"

    var currentVersion: String = Self.currentVersion

    func shouldPresent(using defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: Self.seenVersionKey) != currentVersion
    }

    func markSeen(using defaults: UserDefaults = .standard) {
        defaults.set(currentVersion, forKey: Self.seenVersionKey)
    }
}

enum OnboardingAccent: Equatable {
    case blue
    case violet
    case mint
    case amber
    case rose

    var color: Color {
        switch self {
        case .blue: .blue
        case .violet: .purple
        case .mint: .mint
        case .amber: .orange
        case .rose: .pink
        }
    }

    var secondaryColor: Color {
        switch self {
        case .blue: .cyan
        case .violet: .indigo
        case .mint: .green
        case .amber: .yellow
        case .rose: .red
        }
    }
}

struct OnboardingScreenshotFocus: Equatable {
    let scale: CGFloat
    let offset: CGSize

    static let workspace = OnboardingScreenshotFocus(scale: 1.10, offset: CGSize(width: 26, height: 16))
    static let rightPanel = OnboardingScreenshotFocus(scale: 1.16, offset: CGSize(width: -58, height: 8))
    static let settingsPanel = OnboardingScreenshotFocus(scale: 1.16, offset: CGSize(width: -66, height: 8))
}

struct OnboardingPage: Identifiable, Equatable {
    let id: String
    let screenshotName: String
    let screenshotFocus: OnboardingScreenshotFocus
    let accent: OnboardingAccent
    let eyebrow: String
    let title: String
    let body: String
    let beats: [String]
}

enum OnboardingCatalog {
    static let pages: [OnboardingPage] = [
        OnboardingPage(
            id: "stage",
            screenshotName: "onboarding-workspace",
            screenshotFocus: .workspace,
            accent: .blue,
            eyebrow: "工作区",
            title: "从一个项目舞台开始",
            body: "每个工作区都是一个项目现场：目录、标签、分屏、最近会话和布局都围绕这个现场组织。",
            beats: ["选择项目舞台", "保留分屏现场", "恢复最近上下文"]
        ),
        OnboardingPage(
            id: "voices",
            screenshotName: "onboarding-workspace",
            screenshotFocus: .workspace,
            accent: .violet,
            eyebrow: "面板",
            title: "把每个面板当成一个声部",
            body: "面板负责具体执行：Shell、Agent、命令记录、搜索、分屏和放大都留在当前声部里。",
            beats: ["分屏组织工作", "面板本地控制", "双击放大/还原"]
        ),
        OnboardingPage(
            id: "assign",
            screenshotName: "onboarding-tools",
            screenshotFocus: .rightPanel,
            accent: .mint,
            eyebrow: "任务",
            title: "把任务甩给正确的执行者",
            body: "任务卡片是一段可复用的乐谱。拖到某个面板，就交给那个 Shell 或 Agent 执行。",
            beats: ["拖到面板执行", "变量按需填写", "当前上下文运行"]
        ),
        OnboardingPage(
            id: "attention",
            screenshotName: "onboarding-workspace",
            screenshotFocus: .workspace,
            accent: .rose,
            eyebrow: "注意力",
            title: "只看真正需要你指挥的地方",
            body: "完成、等待、审批和后台运行都会回到状态栏、工作区、标签或伙伴层，提醒你下一步该看哪里。",
            beats: ["完成未读", "活动记录", "跳回相关面板"]
        ),
        OnboardingPage(
            id: "capabilities",
            screenshotName: "onboarding-tools",
            screenshotFocus: .rightPanel,
            accent: .amber,
            eyebrow: "能力库",
            title: "把能力收进能力库",
            body: "CLI、Skills、MCP、Hooks 和供应商用量都归到能力库。这里管理能力，工作区和面板只使用能力。",
            beats: ["Skills / MCP / Hooks", "CLI 检测", "供应商与用量"]
        ),
    ]
}
