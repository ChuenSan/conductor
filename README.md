# Conductor

一个原生 macOS 多终端管理器：工作区 / Tab / 自由分屏，每个分屏是一个真 **libghostty** 终端。
对标 [manaflow-ai/cmux](https://github.com/manaflow-ai/cmux)。Swift + SwiftUI + AppKit，仅 macOS。

## 构建与运行

需要 macOS 14+ 与 Xcode（Swift 6 工具链）。

```bash
# 1. 拉取预编译的 GhosttyKit.xcframework（~536MB，不入 git）
./Scripts/prepare-ghosttykit.sh

# 2. 构建 + 运行
swift run ConductorApp
```

`swift test` 运行 ConductorCore（模型 + 持久化）的单元测试。

### 打包成 .app（启用系统通知）

完成通知（agent 答完发 macOS 通知、点击跳回对应 pane）依赖 **app 有 bundle id**，
所以要用打包后的 `Conductor.app` 运行，而不是 `swift run`：

```bash
# 打包（默认 release）并启动
./Scripts/make-app.sh && open Conductor.app
```

首次运行后，到 CLI 面板（Tab 栏右侧）的「完成通知」卡片里点「安装通知 hook」，
会写入 `~/.conductor/bin/conductor-notify` 并配置 Codex / Claude。若系统把通知拦了（ad-hoc 签名常见），
卡片里点「去系统设置授权」打开「系统设置 › 通知 › Conductor」手动开启即可恢复点击跳转；
否则会自动回退成普通横幅（看得到、点了不跳转）。

## 功能

- **工作区**：左侧栏，每个工作区绑定一个目录（`+` 选目录新建）。
- **Tab**：每个工作区顶部多个 tab，标签显示当前目录名。
- **自由分屏**：tab 内水平/竖直分屏，可拖分隔条调大小。
- **真终端**：每个分屏是一个 libghostty surface（GPU 渲染 + PTY）。
- **拖放重排**：`⌘ + 拖动`某个终端到另一个终端上松手，把它移到那一侧。
- **持久化**：退出/重开恢复工作区 / tab / 分屏布局，每个 pane 回到上次的目录；分屏新 pane 继承当前 pane 的目录。
- **内容恢复**：正常退出时给每个 pane 拍「屏幕+回滚」文本快照（截尾 2000 行 / 256KB），下次启动在新终端里回放（可滚动可复制，末尾有分隔线提示）；进程本身不复活，crash 退出无快照。
- **误关恢复**：`⌘⇧T` 弹栈恢复最近关闭的 tab/pane（分屏结构、目录、关闭前的终端内容一并回来，最多 10 条，会话内有效）。
- **Agent 会话续聊**：关闭/退出时若 pane 里在跑 claude/codex，会按 cwd 记下最近的会话 ID；恢复该 pane 时把 `claude --resume <id>` / `codex resume <id>` 预输入到提示符上，按 Enter 即可接着聊（不会自动执行）。
- **会话管理**：侧边栏「会话」虚拟列表列出当前工作区全部 Claude/Codex 历史（悬停 0.3s 弹出毛玻璃预览浮层，虚拟滚动浏览完整对话；点击新标签续聊）；每个 pane 右键可「续聊会话」或「管理会话」；右侧管理面板点开展开完整 transcript（LazyVStack 虚拟滚动、可选中复制）。
- 选字即复制、`⌘V` 粘贴、macOS 浅色主题。

### 工具面板（Tab 栏右侧按钮）

右侧工具面板分四个分段：

- **CLI**：检测本机 Codex / Claude / Gemini / Cursor / Copilot / Grok，显示版本、用量配额、一键启动到新终端，以及「完成通知」hook 安装。
- **用量**：扫描 `~/.claude/projects` 与 `~/.codex/sessions` 的会话日志（ccusage 思路，价目表见 `ModelPricing`），含：今日/区间成本、总 token、会话数；按来源堆叠的每日成本图（点柱子看单日 Claude/Codex 明细）；token 构成（输入/输出/缓存读写）；**按项目**排行（取会话 cwd）；按模型占比明细。7/30/90 天切换；启动时后台预扫 + 磁盘缓存，面板秒开。
- **Skills**：扫描 Claude / Codex / Cursor 的 `SKILL.md`，按来源筛选 + 搜索；行展开看完整描述/作者/路径，可在 Finder 显示、打开 SKILL.md、拷贝路径；开关即启用/禁用（重命名 `SKILL.md.disabled`，可逆）。
- **Hooks**：已配置 hooks 按事件分组展示（点命令展开全文），市场配方显示 Claude/Codex 双端安装状态，一键安装/移除（完成通知 / 提示音 / 横幅 / 完成日志）；可直接打开两侧配置文件。安装的命令带 `$CONDUCTOR_PANE_ID` 网关，只对 conductor 启动的 agent 生效，其它配置原样保留。

## 键位

| 键 | 作用 |
|---|---|
| `⌘T` | 新建 tab |
| `⌘D` / `⌘⇧D` | 向右竖分 / 向下横分 |
| `⌘W` | 关闭当前 pane（最后一个则关 tab）|
| `⌘⇧T` | 恢复最近关闭的 tab/pane（回到原目录与原分屏位置，tab 右键菜单也有入口）|
| `⌘⌥← / →` | 在分屏间切换焦点 |
| `⌘ + 拖动终端` | 把该 pane 拖到别处重排 |

## 架构

- **`ConductorCore`**（纯 Swift 库，单测覆盖）：数据模型（`SplitNode` 分屏树 / `Tab` / `Workspace` / `WorkspaceStore`）、命令 reducer（`WorkspaceCommand`）、`SessionRegistry`、持久化（`StateStore`），以及引擎无关的 `TerminalSurface` 协议。
- **`ConductorApp`**（可执行）：SwiftUI 外壳（侧栏 / Tab 栏，自绘）+ AppKit 终端区；`GhosttySurface` 封装 libghostty（`TerminalSurface` 的实现），`AppCoordinator` 把命令应用到状态并重建视图。
- **GhosttyKit**：预编译的 libghostty C API（vendored，非源码构建），用 Apple 工具链链接。

> ⚠️ 渲染坑：libghostty 终端视图（`CAMetalLayer`）的容器里**不能放非 Metal 的 layer-backed 兄弟视图，父级也不能重写 `draw()`**，否则会破坏 Metal 呈现导致非聚焦 pane 白屏。pane 容器因此只放终端视图本身，chrome（焦点环用图层边框）另行处理。
