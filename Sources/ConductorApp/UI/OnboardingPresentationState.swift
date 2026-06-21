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
            id: "command-center",
            screenshotName: "onboarding-workspace",
            screenshotFocus: .workspace,
            accent: .blue,
            eyebrow: "欢迎来到 Conductor",
            title: "把终端变成 Agent 指挥台",
            body: "Conductor 不只是打开 shell。它把终端、AI 会话、任务状态和项目上下文放到同一个可控空间里。",
            beats: ["一个窗口管理多个工作区", "命令、会话、工具统一入口", "从第一分钟就能继续工作"]
        ),
        OnboardingPage(
            id: "workspace",
            screenshotName: "onboarding-workspace",
            screenshotFocus: .workspace,
            accent: .violet,
            eyebrow: "空间感",
            title: "Tab、分屏和布局都记得你在做什么",
            body: "每个项目可以保留自己的分屏树、标签和当前目录。你切换的不是窗口，而是一整个工作现场。",
            beats: ["左右/上下分屏", "恢复最近关闭", "保存常用布局"]
        ),
        OnboardingPage(
            id: "agents",
            screenshotName: "onboarding-tools",
            screenshotFocus: .rightPanel,
            accent: .mint,
            eyebrow: "Agent 协作",
            title: "让不同 Agent 像团队成员一样排队干活",
            body: "会话可以续聊，任务可以排队，完成状态会回到通知和任务卡里。你不用盯着每个 pane 等结果。",
            beats: ["续聊历史会话", "任务队列", "完成提醒和活动记录"]
        ),
        OnboardingPage(
            id: "tools",
            screenshotName: "onboarding-tools",
            screenshotFocus: .rightPanel,
            accent: .amber,
            eyebrow: "工具台",
            title: "Skills、Hooks、MCP 放在一个控制面板里",
            body: "Conductor 把 Agent 能力拆成可管理的工具面板：配置、启停、检查、修复，都不用离开主窗口。",
            beats: ["Skills 管理", "MCP Workbench", "Hooks 自动化"]
        ),
        OnboardingPage(
            id: "visibility",
            screenshotName: "onboarding-settings",
            screenshotFocus: .settingsPanel,
            accent: .rose,
            eyebrow: "可见性",
            title: "知道谁在工作、花了多少、哪里卡住了",
            body: "状态栏、用量面板和活动中心会把后台运行、成本趋势、完成记录变成可扫读的信息。",
            beats: ["用量与成本", "状态栏信号", "通知中心"]
        ),
    ]
}
