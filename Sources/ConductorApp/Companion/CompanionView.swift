import ConductorCore
import SwiftUI

/// 透明浮窗里的宠物全景：上方气泡 / 审批卡 + 底部精灵。
/// 交互分区：精灵区由原生 NSView 处理（拖拽/点击），气泡区里的审批按钮由 SwiftUI 处理。
struct CompanionView: View {
    @ObservedObject var controller: CompanionController
    @ObservedObject private var configStore = ConfigStore.shared
    @State private var pokeBounce = false

    private var showApproval: Bool {
        controller.mood == .needsYou && controller.config.inlineApproval
            && controller.pendingApproval != nil
    }

    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            if showApproval, let request = controller.pendingApproval {
                ApprovalCard(request: request,
                             onDecision: { controller.resolve($0) },
                             onMore: { controller.handleTap() })
                    .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
            } else if let result = controller.resultText {
                ResultBubble(text: result, onJump: { controller.handleTap() })
                    .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
            } else if let bubble = controller.bubble {
                SpeechBubble(text: bubble)
                    .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
            }
            // 点击/拖拽由承载它的原生 NSView 处理（CompanionPanelContentView）；SwiftUI 不挂手势。
            // 选中 Codex 图集宠物 → 图集渲染；否则程序化模版。
            Group {
                if let sheet = controller.atlasSheet {
                    AtlasPetSprite(sheet: sheet, mood: controller.mood)
                } else {
                    PetSprite(mood: controller.mood, template: controller.proceduralTemplate)
                }
            }
            .frame(width: 84, height: 84)
            .scaleEffect(pokeBounce ? 1.18 : 1.0)        // 点一下弹一下（反馈）
        }
        .padding(.bottom, 10)
        .frame(width: CompanionController.windowSize.width,
               height: CompanionController.windowSize.height, alignment: .bottom)
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: controller.mood)
        .animation(.easeOut(duration: 0.18), value: controller.bubble)
        .animation(.easeOut(duration: 0.18), value: controller.resultText)
        .animation(.easeOut(duration: 0.18), value: showApproval)
        .id(configStore.config.appearance.theme)
        .onChange(of: controller.pokeNonce) { _, _ in
            withAnimation(.spring(response: 0.15, dampingFraction: 0.45)) { pokeBounce = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.6)) { pokeBounce = false }
            }
        }
    }
}

// MARK: - 精灵本体（程序化，模版定形状/配色，PetMood 定表情）

/// 一只随心情变表情的小生物：身体形状 + 配色由 `PetTemplate` 决定；
/// 弹跳/眨眼/嘴形/头顶小标由 `PetMood` 决定（保证任何模版下状态都一眼可读）。
struct PetSprite: View {
    let mood: PetMood
    var template: PetTemplate = PetTemplateCatalog.default
    /// false = 静态单帧（无 TimelineView）。设置里的模版列表用它，避免一排宠物同时跑动画卡顿。
    var animated = true

    private static let slate = Color(red: 0.27, green: 0.29, blue: 0.34)

    private var bodyColor: Color { Color(hex: template.bodyHex) ?? Color(white: 0.96) }
    private var cheekColor: Color { Color(hex: template.cheekHex) ?? tint.opacity(0.3) }

    private var bodyShape: AnyShape {
        switch template.shape {
        case .blob: return AnyShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        case .round: return AnyShape(Ellipse())
        case .square: return AnyShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    var body: some View {
        if animated {
            TimelineView(.animation) { timeline in
                sprite(phase: timeline.date.timeIntervalSinceReferenceDate)
            }
        } else {
            sprite(phase: 0)        // 静态帧：bob=0、睁眼
        }
    }

    private func sprite(phase t: TimeInterval) -> some View {
        let bob = bobOffset(t)
        let eyesClosed = (mood == .sleeping) || (mood == .sad) || isBlinking(t)
        return ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.16))
                .frame(width: 50, height: 10)
                .offset(y: 40)
                .blur(radius: 3)

            ZStack {
                bodyShape
                    .fill(bodyColor)
                    .overlay(bodyShape.stroke(tint.opacity(0.95), lineWidth: 3))
                    .frame(width: 66, height: 60)
                    .shadow(color: .black.opacity(0.22), radius: 5, y: 2)

                HStack(spacing: 30) {
                    Circle().fill(cheekColor.opacity(0.55)).frame(width: 8, height: 8)
                    Circle().fill(cheekColor.opacity(0.55)).frame(width: 8, height: 8)
                }
                .offset(y: 6)

                HStack(spacing: 18) {
                    Eye(closed: eyesClosed, color: Self.slate)
                    Eye(closed: eyesClosed, color: Self.slate)
                }
                .offset(y: -4)

                Mouth(mood: mood)
                    .stroke(Self.slate, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(width: 16, height: 9)
                    .offset(y: 15)
            }
            .offset(y: bob)

            if let badge {
                Image(systemName: badge.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(Circle().fill(badge.color))
                    .offset(y: -34 + bob * 0.6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 84, height: 84)
    }

    private func bobOffset(_ t: TimeInterval) -> CGFloat {
        switch mood {
        case .sleeping: return 0
        case .celebrating: return -abs(sin(t * 6)) * 8
        case .needsYou: return sin(t * 5) * 3
        case .thinking: return sin(t * 2.2) * 2
        default: return sin(t * 1.6) * 2
        }
    }

    private func isBlinking(_ t: TimeInterval) -> Bool {
        let cycle = t.truncatingRemainder(dividingBy: 3.4)
        return cycle > 3.25
    }

    private var tint: Color {
        switch mood {
        case .idle, .thinking: return AppStyle.accent
        case .needsYou: return Color(red: 0.91, green: 0.62, blue: 0.20)
        case .celebrating: return Color(red: 0.27, green: 0.69, blue: 0.42)
        case .sad: return Color(red: 0.82, green: 0.38, blue: 0.46)
        case .sleeping: return Color(red: 0.56, green: 0.58, blue: 0.64)
        }
    }

    private var badge: (symbol: String, color: Color)? {
        switch mood {
        case .thinking: return ("ellipsis", AppStyle.accent)
        case .needsYou: return ("exclamationmark", Color(red: 0.91, green: 0.55, blue: 0.15))
        case .celebrating: return ("sparkles", Color(red: 0.24, green: 0.66, blue: 0.40))
        case .sleeping: return ("zzz", Color(red: 0.56, green: 0.58, blue: 0.64))
        case .sad, .idle: return nil
        }
    }
}

private struct Eye: View {
    let closed: Bool
    let color: Color
    var body: some View {
        Group {
            if closed {
                Capsule().fill(color).frame(width: 9, height: 2.4)
            } else {
                Capsule().fill(color).frame(width: 7, height: 9)
            }
        }
        .animation(.easeInOut(duration: 0.08), value: closed)
    }
}

private struct Mouth: Shape {
    let mood: PetMood
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let midY = rect.midY
        switch mood {
        case .celebrating:
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                           control: CGPoint(x: rect.midX, y: rect.maxY + 2))
        case .needsYou:
            p.addEllipse(in: CGRect(x: rect.midX - 3, y: midY - 3, width: 6, height: 6))
        case .sad:
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                           control: CGPoint(x: rect.midX, y: rect.minY))
        case .sleeping:
            p.move(to: CGPoint(x: rect.midX - 3, y: midY))
            p.addLine(to: CGPoint(x: rect.midX + 3, y: midY))
        default:
            p.move(to: CGPoint(x: rect.minX + 2, y: midY))
            p.addQuadCurve(to: CGPoint(x: rect.maxX - 2, y: midY),
                           control: CGPoint(x: rect.midX, y: midY + 3))
        }
        return p
    }
}

// MARK: - 气泡

/// 头顶说话气泡。复用 `AppStyle` token（不自造视觉：不发闷渐变/玻璃）。
private struct SpeechBubble: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppStyle.textPrimary)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 160)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(companionCardBackground())
    }
}

/// 气泡/审批卡的共用背衬。复用 `AppStyle` token（不自造视觉：不发闷渐变/玻璃）。
@MainActor private func companionCardBackground() -> some View {
    RoundedRectangle(cornerRadius: 11, style: .continuous)
        .fill(AppStyle.elevated)
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(AppStyle.textPrimary.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
}

// MARK: - 结果气泡（AI 完成 → 直接显示 agent 真实回复，可展开看全文）

private struct ResultBubble: View {
    let text: String
    var onJump: () -> Void = {}
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppStyle.accent)
                Text(L("回复"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppStyle.textSecondary)
                Spacer(minLength: 8)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppStyle.textTertiary)
            }
            if expanded {
                ScrollView {
                    Text(text)
                        .font(.system(size: 11))
                        .foregroundStyle(AppStyle.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 96)
            } else {
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(AppStyle.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action: onJump) {
                Text(L("去会话 →"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppStyle.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .frame(width: 200, alignment: .leading)
        .background(companionCardBackground())
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.16)) { expanded.toggle() } }
    }
}

// MARK: - 审批卡（气泡内联「允许/拒绝」）

/// 待审批时头顶弹出的紧凑卡：标题 + 可选命令 + 紧凑按钮（允许一次/拒绝 或 提问选项）。
/// 细粒度（总是允许某工具、多选项）点「更多」去右侧 Feed 面板。
struct ApprovalCard: View {
    let request: FeedRequest
    let onDecision: (FeedDecision) -> Void
    let onMore: () -> Void

    private var compact: CompanionApproval.Compact { CompanionApproval.compact(for: request) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(FeedPresentation.title(for: request))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppStyle.textPrimary)
                .lineLimit(1)
            if let body = FeedPresentation.body(for: request), !body.isEmpty {
                Text(body)
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(AppStyle.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            HStack(spacing: 6) {
                ForEach(compact.buttons) { button in
                    ApprovalButton(button: button) { onDecision(button.decision) }
                }
                if compact.hasMore {
                    Button(action: onMore) {
                        Text(L("更多"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppStyle.textSecondary)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: 200, alignment: .leading)
        .background(companionCardBackground())
    }
}

struct ApprovalButton: View {
    let button: FeedActionButton
    let action: () -> Void

    private var tint: Color {
        switch button.role {
        case .allow: return Color(red: 0.27, green: 0.69, blue: 0.42)
        case .deny: return Color(red: 0.82, green: 0.38, blue: 0.46)
        case .neutral: return AppStyle.accent
        }
    }

    var body: some View {
        Button(action: action) {
            Text(L(button.label))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Capsule().fill(tint))
        }
        .buttonStyle(.plain)
    }
}
