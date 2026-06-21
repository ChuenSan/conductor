import ConductorCore
import SwiftUI

/// 「存为布局」：给布局命名 + 为每个终端填复原时自动跑的命令（你要的"自定义每个 pane 跑什么"）。
struct LayoutSaveSheet: View {
    let coordinator: AppCoordinator
    let workspaceID: WorkspaceID
    let onClose: () -> Void

    @State private var name = ""
    @State private var commands: [String: String] = [:]
    @FocusState private var nameFocused: Bool

    private var rows: [(pane: String, title: String, cwd: String)] {
        coordinator.layoutDraftPanes(for: workspaceID)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("存为布局"))
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
                    VStack(alignment: .leading, spacing: 8) {
                        AgentToolsFormLabel(L("布局名称"))
                        AgentToolsFormGroup {
                            TextField(L("给这套现场起个名字"), text: $name)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                                .foregroundStyle(AppStyle.textPrimary)
                                .focused($nameFocused)
                                .padding(.horizontal, 12)
                                .frame(height: 38)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        AgentToolsFormLabel(L("每个终端复原时跑什么（可选）"))
                        if rows.isEmpty {
                            Text(L("这个工作区还没有终端"))
                                .font(.system(size: 11.5))
                                .foregroundStyle(AppStyle.textTertiary)
                        } else {
                            AgentToolsFormGroup {
                                ForEach(Array(rows.enumerated()), id: \.element.pane) { index, row in
                                    if index > 0 { AgentToolsFormDivider() }
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(row.title)
                                                .font(.system(size: 11.5, weight: .semibold))
                                                .foregroundStyle(AppStyle.textSecondary)
                                                .lineLimit(1)
                                            Text(row.cwd)
                                                .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                                                .foregroundStyle(AppStyle.textTertiary)
                                                .lineLimit(1)
                                        }
                                        .frame(width: 120, alignment: .leading)
                                        TextField(L("命令，如 npm run dev（留空＝只 cd / 续聊）"), text: Binding(
                                            get: { commands[row.pane] ?? "" },
                                            set: { commands[row.pane] = $0 }))
                                            .textFieldStyle(.plain)
                                            .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                                            .foregroundStyle(AppStyle.textPrimary)
                                    }
                                    .padding(.horizontal, 12)
                                    .frame(height: 42)
                                }
                            }
                        }
                        Text(L("跑着 agent 的终端会自动存会话，复原时续聊；普通终端复原时 cd 回目录并跑上面的命令。"))
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(AppStyle.textTertiary)
                    }
                }
                .padding(18)
            }
            .scrollIndicators(.never)

            VStack(spacing: 0) {
                Rectangle().fill(AppStyle.separator.opacity(0.4)).frame(height: 1)
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    ToolActionButton(title: L("取消"), height: 28, fontSize: 11, horizontalPadding: 12, action: onClose)
                    ToolActionButton(title: L("保存"), systemImage: "checkmark", role: .primary,
                                     height: 28, fontSize: 11, horizontalPadding: 14) {
                        coordinator.saveLayout(named: name, startupCommands: commands, workspaceID: workspaceID)
                        onClose()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .frame(width: 480, height: 520)
        .background(AppStyle.windowBackground)
        .onAppear {
            if name.isEmpty {
                let wsName = coordinator.visibleWorkspaces.first { $0.id == workspaceID }?.name ?? L("工作区")
                name = wsName
            }
            DispatchQueue.main.async { nameFocused = true }
        }
    }
}
