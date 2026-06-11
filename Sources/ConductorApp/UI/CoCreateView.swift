import AppKit
import SwiftUI

/// 「共创计划」面板：项目内的宣传位——讲清玩法、给现成的坑位、一键去 GitHub 发 Issue。
/// 全部原生动效：逐项错峰入场、呼吸光点、跑马灯、卡片 hover 弹性、CTA 辉光脉冲。
struct CoCreateView: View {
    /// GitHub 仓库与预填好骨架的新 Issue 链接。
    static let repoURL = URL(string: "https://github.com/zhengzizhe/conductor")!
    static var newIssueURL: URL {
        var components = URLComponents(string: "https://github.com/zhengzizhe/conductor/issues/new")!
        components.queryItems = [
            URLQueryItem(name: "title", value: "[共创] "),
            URLQueryItem(name: "body", value: """
            ### 我想做的方向
            （功能 / 动效 / 主题 / 性能 / 文档 / 脑洞）

            ### 一句话点子

            ### 为什么值得做

            ### 我打算怎么做（可选）

            """),
        ]
        return components.url!
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero.coCreateReveal(0)
                FeatureMarquee().coCreateReveal(0.1)
                steps.coCreateReveal(0.18)
                ideaMenu.coCreateReveal(0.26)
                footer.coCreateReveal(0.34)
            }
            .padding(16)
        }
        .scrollIndicators(.never)
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                BreathingDot()
                Text(L("共创计划 · 开放中"))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(AppStyle.accent)
            }
            Text(L("一起把终端\n调教成 Agent 指挥台"))
                .font(.system(size: 23, weight: .heavy))
                .lineSpacing(3)
                .foregroundStyle(AppStyle.textPrimary)
            Text(L("下一个让人尖叫的功能由你来点菜：点子、设计稿、键位吐槽、性能抓包、一段让你心动的动效参考——都算贡献，不要求会 Swift。"))
                .font(.system(size: 11.5))
                .lineSpacing(4)
                .foregroundStyle(AppStyle.textSecondary)

            HStack(spacing: 8) {
                GlowCTAButton(title: L("发 Issue 入伙"), systemImage: "arrow.up.forward.app.fill") {
                    NSWorkspace.shared.open(Self.newIssueURL)
                }
                Button {
                    NSWorkspace.shared.open(Self.repoURL)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "star")
                            .font(.system(size: 10, weight: .semibold))
                        Text(L("先去仓库看看"))
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(AppStyle.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(AppStyle.hoverFill))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppStyle.accent.opacity(0.10), AppStyle.accent.opacity(0.02)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppStyle.accent.opacity(0.25), lineWidth: 1))
    }

    // MARK: - 三步入伙

    private var steps: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(L("入伙只要三步"), mono: "// HOW IT WORKS")
            CoCreateStepCard(index: 1, icon: "lightbulb.max.fill", title: L("抛点子"),
                             detail: L("点上面的按钮，标题带 [共创]，模板已帮你搭好骨架：方向、一句话点子、为什么值得做。"))
            CoCreateStepCard(index: 2, icon: "person.2.fill", title: L("认领或共谋"),
                             detail: L("在 Issue 里讨论方案：自己动手，或挂出来等人捡。会定期从中挑选直接排进开发。"))
            CoCreateStepCard(index: 3, icon: "trophy.fill", title: L("上贡献者墙"),
                             detail: L("被采纳的点子随版本发布并在发布说明里鸣谢；提 PR 合并的，名字永久进 Contributors。"))
        }
    }

    // MARK: - 点子菜单

    private var ideaMenu: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(L("不知道做什么？现成的坑"), mono: "// IDEA MENU")
            VStack(spacing: 6) {
                CoCreateIdeaRow(emoji: "🏁", tag: "FEATURE", title: L("任务赛马"),
                                detail: L("一个需求 → N 个 worktree，Claude / Codex 同题并跑，diff 选优一键合并"))
                CoCreateIdeaRow(emoji: "✨", tag: "MOTION", title: L("高级动效"),
                                detail: L("pane 入场、完成闪绿都有动效基建，来一段更讲究的 spring 或粒子彩蛋"))
                CoCreateIdeaRow(emoji: "🎨", tag: "THEME", title: L("主题配色"),
                                detail: L("设计一套让人想截图的终端 + 外壳主题，进 config.yaml 即热切换"))
                CoCreateIdeaRow(emoji: "📊", tag: "INSIGHT", title: L("成本仪表盘"),
                                detail: L("每个任务花了多少 token / 多少钱，按 pane 归因"))
                CoCreateIdeaRow(emoji: "📱", tag: "WILD", title: L("手机批准"),
                                detail: L("下班路上收到「等你回复」推送，手机上直接 ⏎ 放行 agent 继续干"))
                CoCreateIdeaRow(emoji: "🧩", tag: "DOCS", title: L("文档与演示"),
                                detail: L("把 hook、键位、工作区讲明白，或录一段 30 秒的演示 GIF"))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AppStyle.accent)
            Text(L("越野越好——「跨越时代」的功能，往往一开始听起来像玩笑。"))
                .font(.system(size: 10.5))
                .foregroundStyle(AppStyle.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, 6)
    }

    private func sectionLabel(_ title: String, mono: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(mono)
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(AppStyle.accent.opacity(0.75))
            Text(title)
                .font(.system(size: 14.5, weight: .bold))
                .foregroundStyle(AppStyle.textPrimary)
        }
        .padding(.bottom, 2)
    }
}

// MARK: - 动效部件

/// 错峰入场：透明度 + 上浮 + 轻弹簧（跟随系统减少动态偏好）。
private struct CoCreateReveal: ViewModifier {
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 16)
            .onAppear {
                guard !shown else { return }
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    shown = true
                    return
                }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(delay)) {
                    shown = true
                }
            }
    }
}

private extension View {
    func coCreateReveal(_ delay: Double) -> some View { modifier(CoCreateReveal(delay: delay)) }
}

/// 呼吸光点：磷光绿 + 外圈扩散。
private struct BreathingDot: View {
    @State private var on = false

    var body: some View {
        ZStack {
            Circle()
                .fill(AppStyle.accent.opacity(0.35))
                .frame(width: 13, height: 13)
                .scaleEffect(on ? 1.25 : 0.7)
                .opacity(on ? 0 : 0.9)
            Circle()
                .fill(AppStyle.accent)
                .frame(width: 6.5, height: 6.5)
                .shadow(color: AppStyle.accent.opacity(0.8), radius: on ? 6 : 2)
        }
        .onAppear {
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) { on = true }
        }
    }
}

/// 主 CTA：辉光呼吸 + 按压弹性。
private struct GlowCTAButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var glowing = false
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(.system(size: 11.5, weight: .bold))
            }
            .foregroundStyle(AppStyle.theme.isDark ? Color.black.opacity(0.85) : .white)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(AppStyle.accent))
            .shadow(color: AppStyle.accent.opacity(glowing ? 0.55 : 0.22),
                    radius: glowing ? 14 : 7, y: 1)
            .scaleEffect(hovering ? 1.04 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { inside in
            withAnimation(Motion.snappy) { hovering = inside }
        }
        .onAppear {
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) { glowing = true }
        }
        .help(L("打开 GitHub，标题已带 [共创]，正文骨架已填好"))
    }
}

/// 功能关键词跑马灯：内容复制两份做无缝循环；hover 不停（保持简单）。
private struct FeatureMarquee: View {
    @State private var offsetX: CGFloat = 0
    @State private var halfWidth: CGFloat = 0

    private let items = [
        "⌘⇧M Mission Control", "✋ 等你回复收件箱", "⏱ 思考活计时", "⚡ 完成闪绿",
        "⌘⇧⏎ 任务队列", "🔍 二次意见", "⌘/ 键位速查", "🏁 worktree 赛马 · 你来？",
    ]

    var body: some View {
        // 两份内容首尾相接，滚动半程后从头开始 → 无缝
        HStack(spacing: 22) {
            marqueeContent
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                    guard halfWidth == 0, width > 0 else { return }
                    halfWidth = width + 22   // 自身宽 + 间距
                    startScroll()
                }
            marqueeContent
        }
        .offset(x: offsetX)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .padding(.vertical, 7)
        .overlay(alignment: .top) { Rectangle().fill(AppStyle.separator).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(AppStyle.separator).frame(height: 1) }
    }

    private var marqueeContent: some View {
        HStack(spacing: 22) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppStyle.textTertiary)
                    .fixedSize()
            }
        }
    }

    private func startScroll() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        offsetX = 0
        withAnimation(.linear(duration: 26).repeatForever(autoreverses: false)) {
            offsetX = -halfWidth
        }
    }
}

/// 一步卡片：编号描边数字 + 图标，hover 上浮。
private struct CoCreateStepCard: View {
    let index: Int
    let icon: String
    let title: String
    let detail: String
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppStyle.accent)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(AppStyle.accent.opacity(0.10)))
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
            Text("0\(index)")
                .font(.system(size: 22, weight: .heavy, design: .monospaced))
                .foregroundStyle(AppStyle.accent.opacity(hovering ? 0.45 : 0.16))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hovering ? AppStyle.activeFill : AppStyle.hoverFill))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(hovering ? AppStyle.accent.opacity(0.35) : Color.clear, lineWidth: 1))
        .offset(y: hovering ? -2 : 0)
        .animation(Motion.snappy, value: hovering)
        .onHover { hovering = $0 }
    }
}

/// 一条点子坑位：emoji + 标签 + 标题 + 描述，hover 提亮，点击直接去发 Issue（带上坑位名）。
private struct CoCreateIdeaRow: View {
    let emoji: String
    let tag: String
    let title: String
    let detail: String
    @State private var hovering = false

    var body: some View {
        Button {
            var components = URLComponents(
                url: CoCreateView.newIssueURL, resolvingAgainstBaseURL: false)!
            components.queryItems = components.queryItems?.map {
                $0.name == "title" ? URLQueryItem(name: "title", value: "[共创] \(title)：") : $0
            }
            NSWorkspace.shared.open(components.url ?? CoCreateView.newIssueURL)
        } label: {
            HStack(spacing: 10) {
                Text(emoji).font(.system(size: 14))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(AppStyle.textPrimary)
                        Text(tag)
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(AppStyle.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(AppStyle.accent.opacity(0.10)))
                    }
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hovering ? AppStyle.accent : AppStyle.textTertiary.opacity(0.5))
                    .offset(x: hovering ? 2 : 0, y: hovering ? -2 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovering ? AppStyle.activeFill : AppStyle.hoverFill.opacity(0.6)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Motion.hover, value: hovering)
        .onHover { hovering = $0 }
        .help(L("点击去 GitHub 认领这个坑（标题已带上坑位名）"))
    }
}
