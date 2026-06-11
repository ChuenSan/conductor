# 设计文档:类 conductor 的 macOS 原生多终端管理器(v1)

- 日期:2026-06-06
- 状态:设计待评审
- 对标:[manaflow-ai/conductor](https://github.com/manaflow-ai/conductor)(同款架构:原生 macOS + libghostty)

---

## 1. 概述与定位

打造一个**原生 macOS 多终端管理器**,以"工作区 / Tab / 自由分屏"的方式并行管理多个终端。

- **形态**:原生 macOS 应用,**非 Electron**。
- **终端内核**:**libghostty 全套**(仿真 + Metal GPU 渲染 + PTY + 输入),走 Ghostty 自家 macOS app 的嵌入路径(Zig 构建、钉死 commit)。
- **UI 框架**:**SwiftUI 优先**;SwiftUI 做不到或不好做的原生细节(终端 surface、窗口控制、第一响应者/焦点路由、菜单验证、复杂拖拽/分隔条)**桥接 AppKit**。
- **样式**:外观 **100% 自绘**,不沿用系统默认控件长相。
- **平台**:仅 macOS。
- **定位**:面向"做产品"的目标,v1 先把多终端体验本身做扎实。

## 2. v1 范围与非目标

### v1 做(In scope)
- 工作区(路径绑定)+ 顶部 Tab + tab 内自由分屏(可拖拽、可嵌套、记忆比例)。
- libghostty 终端渲染与交互(输入、输出、resize、标题/cwd 回调、进程退出处理)。
- 布局持久化:重启恢复"工作区 + 路径 + tab + 分屏结构",在原 cwd 重开**空白 shell**。
- 一套合理默认键位。

### v1 不做(Non-goals / 推迟)
- **AI agent 会话管理**(状态感知、resume hooks、完成通知、一键起 agent)→ v2+。
- **隔离/并行**(git worktree、SSH 远程运行时)→ v2+。
- **可编程**(CLI / socket API)→ v2+。
- **进程/scrollback 恢复**:明确不 checkpoint 活进程;scrollback 回填(原 C 选项)→ 后续。
- 富配置(主题/字体/键位自定义 UI)→ 后续(v1 给合理默认)。
- 多窗口:v1 单窗口;多窗口 → 后续。

## 3. 技术栈

| 关注点 | 选型 |
|---|---|
| 语言 | Swift 6.x |
| UI | SwiftUI 优先 + AppKit 桥接(按需) |
| 终端内核 | libghostty 全套(Zig 构建,钉死 Ghostty commit) |
| 终端 surface 宿主 | `NSViewRepresentable` 包 libghostty 的 `NSView` |
| 持久化 | JSON(Application Support),原子写,带 schema version |
| 平台 | macOS only,Apple Silicon 优先 |

## 4. 分层架构

依赖**只能向下**;上层不 import libghostty。

```
┌─ UI 层 (SwiftUI 优先 + AppKit 桥接) ────────────┐
│  RootScene / WindowGroup                         │
│   ├─ SidebarView      工作区列表(自绘)          │
│   ├─ TabBarView       当前工作区顶部 tab(自绘)   │
│   └─ SplitContainer    递归分屏(AppKit NSSplitView 桥接)│
│        └─ TerminalPaneView (NSViewRepresentable) │ ← 主要 AppKit 触点(另有 NSSplitView/窗口控制等)
└───────────────┬─────────────────────────────────┘
                │ 只依赖 ↓
┌─ 模型层 (纯 Swift,无 UI/无 libghostty,可单测) ─┐
│  Workspace / Tab / SplitNode(树) / PaneID / cwd  │
└───────────────┬─────────────────────────────────┘
                │
┌─ 终端抽象层 ─────────────────────────────────────┐
│  protocol TerminalSurface                         │
│   { start(cwd), write, resize, focus, close,      │
│     onTitleChange, onCwdChange, onExit }           │
│  └─ GhosttySurface : TerminalSurface  (唯一实现)  │
│  └─ FakeSurface : TerminalSurface     (测试替身)  │
└───────────────┬─────────────────────────────────┘
                │
┌─ libghostty 桥接 (CGhostty) ─────────────────────┐
│  C interop + Swift 薄封装;ghostty_app_t /         │
│  ghostty_surface_t 及回调;PTY 由 libghostty 内管   │
│  回调统一切回主线程后再碰模型/UI                    │
└───────────────┬─────────────────────────────────┘
                │
┌─ 持久化层 ───────────────────────────────────────┐
│  模型树 ↔ state.json;防抖保存 + 退出保存;          │
│  启动恢复 → 重建 UI → 原 cwd 起空白 shell           │
└──────────────────────────────────────────────────┘
```

贯穿的 **AppCoordinator**:生命周期、焦点、键位/命令分发、把用户操作翻译成对模型树的增删。

**核心原则:libghostty 被关在桥接层 + `TerminalSurface` 协议后。** 上层用协议编程,使 libghostty 的 alpha C API 不稳定性被隔离,且模型/协调逻辑可用 `FakeSurface` 单测。

## 5. 数据模型(模型层,纯 Swift)

```
Workspace { id, name, path:URL, tabs:[Tab], activeTabID }
Tab       { id, title, rootSplit:SplitNode, activePaneID }
SplitNode = .leaf(PaneID)
          | .split(axis: .horizontal|.vertical, ratio: Double,
                   first: SplitNode, second: SplitNode)   // 二叉树,嵌套即自由分屏
Pane      { id:PaneID, cwd:URL, title:String }            // 运行期持有 TerminalSurface 实例
WorkspaceStore { workspaces:[Workspace], activeWorkspaceID }
```

- 自由分屏 = 二叉 `SplitNode` 的嵌套;每个分隔条对应一个 `.split`,`ratio` 可拖拽调整并持久化。
- `Pane` 模型只存 `cwd/title`(可序列化);真正的 `TerminalSurface` 实例在运行期由协调器按 `PaneID` 关联,不进持久化。

## 6. 终端抽象层

```swift
protocol TerminalSurface: AnyObject {
    func start(cwd: URL)
    func write(_ data: Data)
    func resize(cols: Int, rows: Int)
    func focus()
    func close()
    var onTitleChange: ((String) -> Void)? { get set }
    var onCwdChange:   ((URL) -> Void)?    { get set }
    var onExit:        ((Int32) -> Void)?  { get set }   // 退出码
}
```

- `GhosttySurface`:唯一生产实现,封装 libghostty;**所有回调切回主线程**后再触发闭包。
- `FakeSurface`:测试替身,记录 `write`/`resize`,可手动触发 `onExit/onTitleChange/onCwdChange`。

## 7. UI 层

- **SwiftUI 优先**:侧栏、tab 栏、整体布局、状态展示用 SwiftUI;**样式全自绘**(配色/圆角/间距/hover/active/focus 态自定义),不吃系统默认控件外观。
- **AppKit 桥接(按需)**:
  - **终端 surface 宿主** → `TerminalPaneView: NSViewRepresentable`(物理必需:libghostty 给的是 `NSView`)。
  - **分屏容器** → 桥接 `NSSplitView`(分隔条拖拽/比例/嵌套手感取原生)。
  - **窗口控制、第一响应者/焦点路由、菜单验证、复杂拖拽/面板行为** → 按需下沉 AppKit。
- 焦点:点击或键位切换 active pane;active pane 自绘高亮;键盘事件路由到 active pane 的 surface。

## 8. 默认键位(v1,后续可配置)

- `⌘T` 新 tab · `⌘W` 关 pane(最后一个则关 tab)
- `⌘D` 向右竖分 · `⌘⇧D` 向下横分
- `⌘⌥←/→/↑/↓` 在分屏间移动焦点
- `⌘1…9` 切 tab · `⌃1…9` / 侧栏点击 切工作区
- 侧栏 `+` 新建工作区(选目录)

## 9. 持久化

- **存什么**:模型树 → `state.json`。叶子 `paneId + cwd + lastTitle`;分屏节点 `axis + ratio + 两子节点`;工作区 `name/path/activeTab`。**只存结构,不存 surface/进程/scrollback**。
- **存哪**:`~/Library/Application Support/<bundleid>/state.json`,顶层 `version` 字段供迁移。
- **何时存**:结构变更防抖合并(~500ms)+ `applicationWillTerminate`。**原子写**(temp + rename)。
- **怎么恢复**:解析 → 重建模型 → 建 UI → 每叶子在 `cwd` 起空白 shell。**cwd 失效兜底链**:`cwd → 工作区 path → $HOME`。

## 10. 错误处理

- **libghostty 起不来**:spike 先挡;运行时 `ghostty_app` 初始化失败 → 明确错误对话框,不静默崩。
- **单 pane 起 shell 失败**:该 pane 内联错误态("failed to start shell: …"),不连累整树/整 app。
- **state.json 损坏/不兼容**:捕获解析错误 → 备份坏文件 → 用 `$HOME` 空工作区启动。坏状态绝不锁死 app。
- **libghostty 回调线程**:回调可能非主线程 → 桥接层统一切主线程再碰 AppKit/模型(写进桥接层契约)。
- **版本漂移**:仓库钉死 Ghostty commit + Zig 版本,构建脚本校验。

## 11. 测试策略

- **模型层(纯 Swift,零 libghostty 依赖)= 主战场**:`SplitNode` 插入分屏 / 删除塌缩 / 焦点移动 / 比例调整;`WorkspaceStore` 变更;**序列化↔反序列化往返**;恢复兜底逻辑。
- **`FakeSurface` 替身**:协调器逻辑脱离真终端可测(新建/关闭 pane、退出塌缩、标题更新)。
- **持久化**:往返 + 损坏文件 + cwd 失效 三类用例。
- **`GhosttySurface`/桥接层**:尽量薄;手测 + spike 冒烟测试为主(GPU 渲染难单测)。
- **UI 层**:v1 轻测/手测,不在 UI 自动化上过度投入。

## 12. 头号风险与 Spike-First

**风险**:libghostty 的 **C 嵌入 API 官方明示"尚未就绪、不适合通用使用"**(2026-06),Zig API 可测试;完整嵌入 API 与 ABI 稳定的 `libghostty-vt` 预计后续才发布。

**对策**:实现计划的**第 0 步是一个 spike**,只验证:
1. 能用 Zig 从钉死的 Ghostty commit 构建出 libghostty 并链接进 macOS app;
2. 在一个 `NSView` 里渲染出能输入/输出的真实终端;
3. 能拿到 title/cwd/exit 回调,且回调能安全切回主线程。

参照:[ghostty-org/ghostling](https://github.com/ghostty-org/ghostling)(libghostty C API 的最小终端范例)、Ghostty 自家 macOS app。**spike 通过,才在其上盖楼。**

## 13. 实现里程碑(高层顺序)

0. **Spike**:libghostty 构建 + 单终端渲染 + 回调(见 §12)。
1. **模型层 + 持久化**(纯 Swift,TDD;此时用 `FakeSurface`):工作区/tab/分屏树、序列化、恢复兜底。
2. **UI 骨架**(SwiftUI):侧栏 + tab 栏 + 分屏容器(NSSplitView 桥接),挂 `FakeSurface` 跑通交互与自绘样式。
3. **接入 `GhosttySurface`**:把 spike 成果做成 `TerminalSurface` 实现,替换 `FakeSurface`。
4. **键位、焦点、退出塌缩、错误态**打磨。
5. **持久化端到端**:重启恢复布局 + 原 cwd 起 shell。

## 14. 参考链接

- 对标项目:[manaflow-ai/conductor](https://github.com/manaflow-ai/conductor) · [conductor.com](https://conductor.com/)
- libghostty 现状:[Mitchell《Libghostty Is Coming》](https://mitchellh.com/writing/libghostty-is-coming) · [libghostty C API 概览](https://mintlify.wiki/ghostty-org/ghostty/api/overview)
- 嵌入范例:[ghostty-org/ghostling](https://github.com/ghostty-org/ghostling)
- Ghostty 本体:[ghostty-org/ghostty](https://github.com/ghostty-org/ghostty)
- 另一架构参照(仅对照,非本路线):[coder/mux](https://github.com/coder/mux)(Electron/TS)· [Zed terminal.rs](https://github.com/zed-industries/zed/blob/main/crates/terminal/src/terminal.rs)(alacritty_terminal 内核 + 自渲染)
