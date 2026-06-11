import SwiftUI

/// 片段管理面板：增删改命令片段，一键发送到当前终端。
/// 「执行」开关决定发送后是否直接回车（关掉则摆在提示符上可先编辑）。
struct SnippetsManagerView: View {
    let coordinator: AppCoordinator
    @ObservedObject private var store = SnippetStore.shared
    @State private var editing: Snippet?
    @State private var isCreating = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L("命令片段"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppStyle.textPrimary)
                    Spacer()
                    Button {
                        isCreating = true
                        editing = Snippet(name: "", command: "")
                    } label: {
                        Label(L("新增片段"), systemImage: "plus")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppStyle.accent)
                }

                Text(L("点击片段发送到当前终端；也可在命令面板（⌘K）里直接搜索片段名。"))
                    .font(.system(size: 11))
                    .foregroundStyle(AppStyle.textTertiary)

                if let editing {
                    SnippetEditor(
                        snippet: editing,
                        isNew: isCreating,
                        onSave: { saved in
                            if isCreating { store.add(saved) } else { store.update(saved) }
                            self.editing = nil
                        },
                        onCancel: { self.editing = nil }
                    )
                }

                if store.snippets.isEmpty, editing == nil {
                    Text(L("还没有片段，点右上角「新增片段」创建一个。"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppStyle.textTertiary)
                        .padding(.top, 8)
                } else {
                    VStack(spacing: 4) {
                        ForEach(store.snippets) { snippet in
                            SnippetRow(
                                snippet: snippet,
                                onSend: { coordinator.sendSnippet(snippet) },
                                onEdit: {
                                    isCreating = false
                                    editing = snippet
                                },
                                onDelete: { store.remove(snippet.id) }
                            )
                        }
                    }
                }
            }
            .padding(16)
        }
        .scrollIndicators(.never)
    }
}

private struct SnippetRow: View {
    let snippet: Snippet
    let onSend: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onSend) {
            HStack(spacing: 10) {
                Image(systemName: snippet.autoRun ? "bolt.fill" : "text.cursor")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(snippet.autoRun ? AppStyle.accent : AppStyle.textTertiary)
                    .frame(width: 16)
                    .help(snippet.autoRun ? L("发送后直接执行") : L("发送后摆在提示符上，可编辑"))
                VStack(alignment: .leading, spacing: 2) {
                    Text(snippet.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppStyle.textPrimary)
                        .lineLimit(1)
                    Text(snippet.command)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if hovering {
                    HStack(spacing: 2) {
                        iconButton("paperplane", help: L("发送到当前终端"), action: onSend)
                        iconButton("pencil", help: L("编辑"), action: onEdit)
                        iconButton("trash", help: L("删除"), destructive: true, action: onDelete)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? AppStyle.hoverFill : AppStyle.activeFill.opacity(0.5)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private func iconButton(_ icon: String, help: String,
                            destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(destructive ? Color(red: 0.92, green: 0.34, blue: 0.34) : AppStyle.textSecondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(AppStyle.hoverFill))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct SnippetEditor: View {
    @State var snippet: Snippet
    let isNew: Bool
    let onSave: (Snippet) -> Void
    let onCancel: () -> Void

    private var valid: Bool {
        !snippet.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !snippet.command.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isNew ? L("新增片段") : L("编辑片段"))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(AppStyle.textSecondary)
            TextField(L("名称（如：提交全部改动）"), text: $snippet.name)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 7).fill(AppStyle.activeFill))
            TextField(L("命令（如：git add -A && git commit）"), text: $snippet.command, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1...4)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 7).fill(AppStyle.activeFill))
            Toggle(isOn: $snippet.autoRun) {
                Text(L("发送后直接执行（关掉则摆在提示符上，可编辑后再回车）"))
                    .font(.system(size: 11))
                    .foregroundStyle(AppStyle.textSecondary)
            }
            .toggleStyle(.checkbox)
            HStack {
                Spacer()
                Button(L("取消"), action: onCancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppStyle.textSecondary)
                Button(L("保存")) { onSave(snippet) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(valid ? AppStyle.accent : AppStyle.textTertiary)
                    .disabled(!valid)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppStyle.separator, lineWidth: 1))
    }
}
