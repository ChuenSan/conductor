import AppKit
import SwiftUI

private let sharePlanAccent = Color(red: 0.12, green: 0.63, blue: 0.55)

/// 「共享计划」面板：收集真实使用场景、可验证材料和适合拆分落地的贡献方向。
struct CoCreateView: View {
    /// GitHub 仓库与预填好模板的新 Issue 链接。
    static let repoURL = URL(string: "https://github.com/zhengzizhe/conductor")!
    static var newIssueURL: URL {
        var components = URLComponents(string: "https://github.com/zhengzizhe/conductor/issues/new")!
        components.queryItems = [
            URLQueryItem(name: "title", value: "\(L("[共享]")) "),
            URLQueryItem(name: "body", value: """
            ### 使用场景
            我正在用 conductor 做...

            ### 遇到的问题 / 想改进的地方

            ### 希望的结果

            ### 可以提供的材料
            截图 / 录屏 / 日志 / 配置 / PR（可选）

            """),
        ]
        return components.url!
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero.coCreateReveal(0)
                contributionScope.coCreateReveal(0.08)
                steps.coCreateReveal(0.16)
                ideaMenu.coCreateReveal(0.24)
                footer.coCreateReveal(0.32)
            }
            .padding(16)
        }
        .scrollIndicators(.never)
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(L("共享计划"))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(sharePlanAccent)
            Text(L("把真实工作流放进下一版"))
                .font(.system(size: 23, weight: .heavy))
                .foregroundStyle(AppStyle.textPrimary)
            Text(L("这里收集你在使用 conductor 时遇到的阻塞、绕路和好想法。可以只写一句话，也可以带截图、日志或 PR；重点是让需求来自真实项目。"))
                .font(.system(size: 11.5))
                .lineSpacing(4)
                .foregroundStyle(AppStyle.textSecondary)

            HStack(spacing: 8) {
                SharePlanPrimaryButton(title: L("提交想法")) {
                    NSWorkspace.shared.open(Self.newIssueURL)
                }
                SharePlanSecondaryButton(title: L("查看仓库")) {
                    NSWorkspace.shared.open(Self.repoURL)
                }
            }
            .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [sharePlanAccent.opacity(0.13), sharePlanAccent.opacity(0.025)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(sharePlanAccent.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Scope

    private var contributionScope: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(L("适合提交什么"), mono: "// SCOPE")
            VStack(spacing: 6) {
                SharePlanScopeRow(
                    title: L("真实场景"),
                    detail: L("你正在做什么、哪一步不顺、现在怎么绕过去。")
                )
                SharePlanScopeRow(
                    title: L("可验证材料"),
                    detail: L("截图、录屏、日志、配置片段或对比产品都可以。")
                )
                SharePlanScopeRow(
                    title: L("小步落地"),
                    detail: L("先把范围收窄，再决定是进路线图还是拆成 PR。")
                )
            }
        }
    }

    // MARK: - Steps

    private var steps: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(L("怎么参与"), mono: "// FLOW")
            SharePlanStepCard(
                index: 1,
                title: L("写清场景"),
                detail: L("说明你的工作流、期望结果和当前成本；一句话也可以，别等完整方案。")
            )
            SharePlanStepCard(
                index: 2,
                title: L("补充线索"),
                detail: L("有截图、日志、命令输出、配置片段就贴上；没有也没关系，先把问题留下。")
            )
            SharePlanStepCard(
                index: 3,
                title: L("跟进落地"),
                detail: L("采纳后会在 Issue 里同步进展；如果你想实现，我们一起把范围收窄到可合并。")
            )
        }
    }

    // MARK: - Idea Menu

    private var ideaMenu: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(L("可以从这些方向开始"), mono: "// THREADS")
            VStack(spacing: 6) {
                SharePlanIdeaRow(
                    tag: "FLOW",
                    title: L("多 Agent 对照"),
                    detail: L("同一任务开多个 worktree，保留命令、diff 和结论，方便选一个继续。")
                )
                SharePlanIdeaRow(
                    tag: "INBOX",
                    title: L("等待处理"),
                    detail: L("把需要确认、授权或补充信息的卡点收拢成一张清单。")
                )
                SharePlanIdeaRow(
                    tag: "STATE",
                    title: L("工作区记忆"),
                    detail: L("恢复布局时带回目录、Agent、分屏和最近上下文。")
                )
                SharePlanIdeaRow(
                    tag: "COST",
                    title: L("成本与用量"),
                    detail: L("按任务查看 token、时长和大致成本，帮助判断一次探索值不值。")
                )
                SharePlanIdeaRow(
                    tag: "MOBILE",
                    title: L("移动确认"),
                    detail: L("离开电脑时也能处理关键确认，让长任务不中断。")
                )
                SharePlanIdeaRow(
                    tag: "DOCS",
                    title: L("文档案例"),
                    detail: L("用真实项目写一段教程、录屏或故障排查记录。")
                )
            }
        }
    }

    private var footer: some View {
        Text(L("不用写完整方案；真实场景和取舍比口号更有用。"))
            .font(.system(size: 10.5))
            .foregroundStyle(AppStyle.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 6)
    }

    private func sectionLabel(_ title: String, mono: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(mono)
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(sharePlanAccent.opacity(0.78))
            Text(title)
                .font(.system(size: 14.5, weight: .bold))
                .foregroundStyle(AppStyle.textPrimary)
        }
        .padding(.bottom, 2)
    }
}

// MARK: - Motion

/// 错峰入场：透明度 + 上浮，跟随系统减少动态偏好。
private struct CoCreateReveal: ViewModifier {
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 12)
            .onAppear {
                guard !shown else { return }
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    shown = true
                    return
                }
                withAnimation(.spring(response: 0.46, dampingFraction: 0.88).delay(delay)) {
                    shown = true
                }
            }
    }
}

private extension View {
    func coCreateReveal(_ delay: Double) -> some View { modifier(CoCreateReveal(delay: delay)) }
}

// MARK: - Components

private struct SharePlanPrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(AppStyle.theme.isDark ? Color.black.opacity(0.86) : Color.white)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(sharePlanAccent)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .help(L("打开 GitHub，新 Issue 已带上简短模板"))
    }
}

private struct SharePlanSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(AppStyle.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(AppStyle.hoverFill)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
    }
}

private struct SharePlanScopeRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(sharePlanAccent)
                .frame(width: 3, height: 29)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                Text(detail)
                    .font(.system(size: 10.3))
                    .lineSpacing(2)
                    .foregroundStyle(AppStyle.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppStyle.hoverFill.opacity(0.62))
        )
    }
}

private struct SharePlanStepCard: View {
    let index: Int
    let title: String
    let detail: String
    @State private var hovering = false

    private var indexText: String { index < 10 ? "0\(index)" : "\(index)" }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Text(indexText)
                .font(.system(size: 16, weight: .heavy, design: .monospaced))
                .foregroundStyle(sharePlanAccent)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(sharePlanAccent.opacity(0.11))
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(AppStyle.textPrimary)
                Text(detail)
                    .font(.system(size: 10.5))
                    .lineSpacing(3)
                    .foregroundStyle(AppStyle.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hovering ? AppStyle.activeFill : AppStyle.hoverFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(hovering ? sharePlanAccent.opacity(0.32) : Color.clear, lineWidth: 1)
        )
        .offset(y: hovering ? -1 : 0)
        .animation(Motion.snappy, value: hovering)
        .onHover { hovering = $0 }
    }
}

private struct SharePlanIdeaRow: View {
    let tag: String
    let title: String
    let detail: String
    @State private var hovering = false

    var body: some View {
        Button {
            var components = URLComponents(
                url: CoCreateView.newIssueURL,
                resolvingAgainstBaseURL: false
            )!
            components.queryItems = components.queryItems?.map {
                $0.name == "title" ? URLQueryItem(name: "title", value: "\(L("[共享]")) \(title)：") : $0
            }
            NSWorkspace.shared.open(components.url ?? CoCreateView.newIssueURL)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(tag)
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .tracking(0.9)
                            .foregroundStyle(sharePlanAccent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(sharePlanAccent.opacity(0.11)))
                        Text(title)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(AppStyle.textPrimary)
                    }
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Text("ISSUE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(hovering ? sharePlanAccent : AppStyle.textTertiary.opacity(0.55))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovering ? AppStyle.activeFill : AppStyle.hoverFill.opacity(0.58))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Motion.hover, value: hovering)
        .onHover { hovering = $0 }
        .help(L("点击提交这个方向，标题已带上方向名"))
    }
}
