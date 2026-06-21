import ConductorCore
import SwiftUI

/// ③ 联动规则：某终端命令完成/成功/失败时，自动通知我 / 跳过去 / 在某终端跑一条命令。
/// 规则是窗口级（pane 每次启动都重生，持久化指向具体 pane 没意义），用来给当前工作现场接线。
struct ChoreographyRulesSheet: View {
    @ObservedObject var coordinator: AppCoordinator
    let onClose: () -> Void

    private enum ActionKind: String, CaseIterable, Identifiable {
        case notify, focus, run
        var id: String { rawValue }
        var label: String {
            switch self {
            case .notify: return L("通知我")
            case .focus:  return L("跳到该终端")
            case .run:    return L("在某终端运行命令")
            }
        }
    }

    @State private var trigger: ChoreoTrigger = .failure
    @State private var sourceID: String = ""        // "" = 任意终端
    @State private var actionKind: ActionKind = .notify
    @State private var targetID: String = ""
    @State private var command: String = ""

    private var panes: [(id: PaneID, title: String)] { coordinator.livePanesForChoreography() }
    private var canAdd: Bool {
        if actionKind == .run {
            return !targetID.isEmpty && !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "bolt.horizontal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppStyle.accent)
                Text(L("联动规则"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppStyle.textPrimary)
                Spacer()
                IconOnlyButton(systemName: "xmark", help: L("关闭"), size: 28, symbolSize: 12, weight: .bold, action: onClose)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    existingRules
                    builder
                }
                .padding(18)
            }
            .scrollIndicators(.never)

            VStack(spacing: 0) {
                Rectangle().fill(AppStyle.separator.opacity(0.4)).frame(height: 1)
                HStack {
                    Text(L("命令完成信号来自 shell 集成，已自包含。"))
                        .font(.system(size: 10))
                        .foregroundStyle(AppStyle.textTertiary)
                    Spacer(minLength: 0)
                    ToolActionButton(title: L("完成"), systemImage: "checkmark", role: .primary,
                                     height: 28, fontSize: 11, horizontalPadding: 14, action: onClose)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .frame(width: 500, height: 540)
        .background(AppStyle.windowBackground)
        .onAppear {
            if targetID.isEmpty { targetID = panes.first?.id.value ?? "" }
        }
    }

    // MARK: 已有规则

    @ViewBuilder private var existingRules: some View {
        VStack(alignment: .leading, spacing: 8) {
            AgentToolsFormLabel(L("已有规则"))
            if coordinator.choreographyRules.isEmpty {
                Text(L("还没有规则。下面加一条，比如「任意终端命令失败 → 通知我」。"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppStyle.textTertiary)
                    .padding(.vertical, 4)
            } else {
                AgentToolsFormGroup {
                    ForEach(Array(coordinator.choreographyRules.enumerated()), id: \.element.id) { index, rule in
                        if index > 0 { AgentToolsFormDivider() }
                        HStack(spacing: 10) {
                            Toggle("", isOn: Binding(
                                get: { rule.enabled },
                                set: { coordinator.setChoreographyRuleEnabled(rule.id, $0) }))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                            Text(coordinator.describeChoreography(rule))
                                .font(.system(size: 11.5))
                                .foregroundStyle(rule.enabled ? AppStyle.textPrimary : AppStyle.textTertiary)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                            IconOnlyButton(systemName: "trash", help: L("删除规则"),
                                           size: 24, symbolSize: 11, tint: AppStyle.textTertiary) {
                                coordinator.removeChoreographyRule(rule.id)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    // MARK: 新建规则

    @ViewBuilder private var builder: some View {
        VStack(alignment: .leading, spacing: 8) {
            AgentToolsFormLabel(L("新建规则"))
            AgentToolsFormGroup {
                pickerRow(L("当")) {
                    Picker("", selection: $sourceID) {
                        Text(L("任意终端")).tag("")
                        ForEach(panes, id: \.id.value) { pane in
                            Text(pane.title).tag(pane.id.value)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu)
                }
                AgentToolsFormDivider()
                pickerRow(L("发生")) {
                    Picker("", selection: $trigger) {
                        ForEach(ChoreoTrigger.allCases, id: \.self) { t in
                            Text(t.label).tag(t)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu)
                }
                AgentToolsFormDivider()
                pickerRow(L("就")) {
                    Picker("", selection: $actionKind) {
                        ForEach(ActionKind.allCases) { k in
                            Text(k.label).tag(k)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu)
                }
                if actionKind == .run {
                    AgentToolsFormDivider()
                    pickerRow(L("在")) {
                        Picker("", selection: $targetID) {
                            ForEach(panes, id: \.id.value) { pane in
                                Text(pane.title).tag(pane.id.value)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu)
                    }
                    AgentToolsFormDivider()
                    HStack(spacing: 10) {
                        Text(L("运行"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(AppStyle.textSecondary)
                            .frame(width: 52, alignment: .leading)
                        TextField(L("命令，如 npm run deploy"), text: $command)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(AppStyle.textPrimary)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                }
            }
            HStack {
                Spacer(minLength: 0)
                ToolActionButton(title: L("添加规则"), systemImage: "plus", role: .tinted(AppStyle.accent),
                                 height: 26, fontSize: 11, horizontalPadding: 12, action: addRule)
                    .disabled(!canAdd)
                    .opacity(canAdd ? 1 : 0.5)
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder private func pickerRow(_ label: String, @ViewBuilder _ control: () -> some View) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(AppStyle.textSecondary)
                .frame(width: 52, alignment: .leading)
            control()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }

    private func addRule() {
        let source = sourceID.isEmpty ? nil : PaneID(sourceID)
        let action: ChoreoAction
        switch actionKind {
        case .notify: action = .notify
        case .focus:  action = .focusSource
        case .run:
            guard !targetID.isEmpty else { return }
            action = .runCommand(target: PaneID(targetID),
                                 command: command.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        coordinator.addChoreographyRule(ChoreographyRule(trigger: trigger, source: source, action: action))
        command = ""
    }
}
