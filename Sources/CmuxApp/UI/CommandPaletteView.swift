import SwiftUI

/// 命令面板的一项：命令 / 标签 / 工作区。
struct PaletteItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    let run: () -> Void
}

/// 命令面板（自绘，跟主题）：搜索框 + 模糊过滤列表，↑↓选、回车执行、Esc 关。
struct CommandPaletteView: View {
    let items: [PaletteItem]
    let onClose: () -> Void

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var fieldFocused: Bool

    private var filtered: [PaletteItem] {
        guard !query.isEmpty else { return items }
        return items
            .compactMap { item -> (PaletteItem, Int)? in
                CommandPaletteView.fuzzy(query, item.title).map { (item, $0) }
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppStyle.textTertiary)
                TextField(L("搜索命令、标签、工作区…"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(AppStyle.textPrimary)
                    .focused($fieldFocused)
                    .onSubmit { runSelected() }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            Rectangle().fill(AppStyle.separator).frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, item in
                            row(item, selected: index == selection)
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture { selection = index; runSelected() }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: selection) { _, new in
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(new, anchor: .center) }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 540, height: 420)
        .cmuxFloatingPanel(cornerRadius: Radius.xl)
        .padding(Space.xl)   // 给阴影留出扩散空间，不被窗口裁掉
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.escape) { onClose(); return .handled }
        .onChange(of: query) { _, _ in selection = 0 }
        .onAppear { fieldFocused = true }
    }

    private func row(_ item: PaletteItem, selected: Bool) -> some View {
        HStack(spacing: 11) {
            Image(systemName: item.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? AppStyle.accent : AppStyle.textTertiary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(AppStyle.textPrimary)
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? AppStyle.activeFill : Color.clear))
    }

    private func move(_ d: Int) {
        let n = filtered.count
        guard n > 0 else { return }
        selection = min(max(selection + d, 0), n - 1)
    }

    private func runSelected() {
        guard filtered.indices.contains(selection) else { return }
        let item = filtered[selection]
        onClose()
        item.run()
    }

    /// 子序列模糊匹配：query 的字符按序出现在 text 中即命中；连续命中加分。无命中返回 nil。
    static func fuzzy(_ query: String, _ text: String) -> Int? {
        let q = Array(query.lowercased())
        let t = Array(text.lowercased())
        guard !q.isEmpty else { return 0 }
        var qi = 0, score = 0, last = -2
        for (ti, ch) in t.enumerated() where qi < q.count && ch == q[qi] {
            score += (ti == last + 1) ? 4 : 1
            if ti == 0 { score += 3 }   // 开头命中加分
            last = ti
            qi += 1
        }
        return qi == q.count ? score : nil
    }
}
