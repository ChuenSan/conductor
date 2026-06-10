# 基建:YAML 配置系统 + 命令注册表 + pane 内容抽象

日期:2026-06-07 · 状态:待评审

> 这是后面一半特性的地基。对照三条主题([[cmux-design-principles]])设计:
> **高性能**(分发 O(1)、配置增量热更新)、**高扩展**(命令可注册、配置数据驱动、pane 内容可插拔)、
> **高商用**(YAML 人可手编、损坏优雅回退、向后兼容、首启生成带注释模板)。

## 目标与范围

1. **B1 配置系统**:`config.yaml`(YAML)→ `AppConfig`(Codable)，热更新、优雅回退。
2. **B2 命令注册表**:命令(id/标题/默认键位/canRun/handler)集中注册，键位查表 O(1) 分发;`main.swift` 的 if/else 退役。
3. **pane 内容抽象**(本期只设计接口、实现留 v2):为 Agent pane 预留"可插拔 pane 内容"的口子。

非目标:设置 GUI(P3)、自定义键位编辑 UI(P3)、Agent pane 的实现(v2)。

---

## B1. 配置系统

### YAML schema(自拟，分层)

`~/.config/cmux/config.yaml`(首启自动写入带注释的默认模板):

```yaml
# cmux 配置 — 改完保存即时生效

appearance:
  theme: dark               # 内置主题名(dark/light/...) 或 custom
  font:
    family: "SF Mono"
    size: 13
  padding: { x: 14, y: 12 }
  cursorStyle: bar          # bar | block | underline
  # theme: custom 时生效（其余时候忽略）
  colors:
    background: "#1b1c22"
    foreground: "#d7d8e0"
    cursor: "#8aa9ff"
    selection: "#33406b"
    # ansi: ["#…", … 16 个]

terminal:
  shell: null               # null = 用户登录 shell；或绝对路径
  scrollback: 10000
  copyOnSelect: false
  confirmCloseRunning: true

behavior:
  restoreLayoutOnLaunch: true
  newTabCwd: workspace      # workspace | activePane | home

keybindings:                # 命令 id → 键位；缺省则用命令内置默认
  newTab: "cmd+t"
  splitRight: "cmd+d"
  splitDown: "cmd+shift+d"
  closePane: "cmd+w"
  focusNextPane: "cmd+alt+right"
  focusPrevPane: "cmd+alt+left"
  commandPalette: "cmd+k"

workspaceDefaults:          # 可被单个工作区覆盖(P3)
  shell: null
  startupCommand: null      # 新 pane 起来自动跑的命令
```

### 模型(CmuxCore，纯 Codable，无第三方依赖)

- `AppConfig: Codable, Equatable`，嵌套 `Appearance / Terminal / Behavior / WorkspaceDefaults` 与 `keybindings: [String:String]`。
- `AppConfig.default` 提供全套默认值。
- **容错解码**:自定义 `init(from:)`，逐字段 `decodeIfPresent(...) ?? 默认`——**缺字段用默认、未知字段忽略**(向后/向前兼容)。
- **校验**:`validated()` 夹紧非法值(字号范围、枚举回退、颜色格式)，越界写日志不崩。
- 为什么放 Core:保持纯逻辑、可单测;YAML 解析不在这层。

### 加载器(CmuxApp，依赖 Yams)

- 新增 SwiftPM 依赖 **Yams**(Swift 事实标准 YAML，支持 Codable);**只加到 CmuxApp target**，CmuxCore 保持零依赖。
- `ConfigLoader`:
  - 定位 `~/.config/cmux/config.yaml`;不存在 → 写入带注释的默认模板(模板是手写字符串，不是 Yams 编码，以保留注释)。
  - 读 → `YAMLDecoder().decode(AppConfig.self)` → `.validated()`。
  - **损坏**(YAML 语法错/类型错)→ 记日志 + 用 `AppConfig.default` + 非致命提示(不崩)。
- `ConfigStore: ObservableObject`，`@Published var config: AppConfig`，供 SwiftUI/coordinator 观察。

### 热更新(高性能:增量)

- 用 `DispatchSource`(或 FSEvents)监听 config.yaml 变更 → 防抖重载 → 与旧值 diff → **只应用受影响部分**:
  - 外观(字号/主题/padding/cursor)→ 重新生成 ghostty 配置串 → 对每个 surface 应用(优先 `ghostty_surface_set_*` 运行时接口，无则标记"下次重开生效")。
  - 键位 → 重建命令表的键位索引(见 B2)。
  - 行为/默认 → 下次新建时生效。
- 不做全量 rebuild、不重渲染整棵树。

### ghostty 翻译 & 主题数据驱动

- `GhosttyRuntime` 不再硬编码:从 `AppConfig.appearance/terminal` 生成 `key = value` 配置串。
- 主题=一组色 token;`AppStyle`(SwiftUI 外壳色)改为**从当前主题派生**，使深色外壳与终端配色一致 —— 为 P3 主题切换留口。

---

## B2. 命令注册表

### KeyChord(CmuxCore，纯、可单测)

- `KeyChord: Hashable`:`modifiers`(cmd/shift/alt/ctrl 位集) + 归一化 `key`(字符或特殊键如 left/right/enter)。
- `KeyChord(parsing: "cmd+shift+d")` 解析键位串;非法串返回 nil(写日志)。
- App 层把 `NSEvent` 归一成 `KeyChord` 做匹配 —— 匹配逻辑在 Core，可单测。

### Command(CmuxApp)

```
struct Command {
  let id: String                 // "newTab"
  let title: String              // "新建标签"
  let defaultKeybinding: String? // "cmd+t"
  let canRun: () -> Bool         // 上下文是否可用(置灰/过滤)
  let run: () -> Void            // 调 AppCoordinator
}
```

### CommandRegistry(CmuxApp)

- 持有 `[Command]`(在 AppCoordinator 注册 newTab/split/close/focus/commandPalette/… 全部动作)。
- **有效键位** = `config.keybindings[id]` ?? `command.defaultKeybinding`。
- 维护 `[KeyChord: Command]` 索引;config 键位变了就重建索引(便宜)。
- `dispatch(_ chord) -> Bool`:查索引 → `canRun` → `run`。**O(1)**。
- `main.swift` 的 keyMonitor:`NSEvent → KeyChord → registry.dispatch`;命中返回 nil 吃掉事件，否则放行。
- 命令面板(P2)、键位帮助(P2.5)、自定义键位(P3)都读这张表 —— 这是"高扩展"的核心。

---

## pane 内容抽象(本期只设计，实现留 v2)

为 v2 的 Agent pane 留口，避免到时改动核心:

- 现状 `SplitNode.leaf(PaneID)` 只认终端。目标:一个 leaf 的内容是**可插拔的 pane 类型**。
- 设计(低侵入):新增 `PaneKind`(`.terminal`，未来 `.agent(...)`)，在 `Tab` 上挂 `paneKinds: [PaneID: PaneKind]`(默认 `.terminal`)，**不改 SplitNode 的 Codable 形状**(向后兼容旧存档)。
- `SessionRegistry.factory` 由"恒造 GhosttySurface"改为**按 kind 分发**的提供者;`AppCoordinator.container(for:)` 按 kind 决定渲染终端视图还是(未来)Agent 视图。
- 本期落地范围:把 factory/渲染改成"按 kind 分发，但只注册 terminal 一种";`PaneKind` 进 Core。Agent 实现走 v2。

---

## 依赖与结构改动

- `Package.swift`:CmuxApp target 加 `Yams`(`.package(url: "https://github.com/jpsim/Yams", from: "5.x")`)。CmuxCore 不动(零依赖)。
- 新增:Core `AppConfig.swift`、`KeyChord.swift`、`PaneKind.swift`;App `ConfigLoader.swift`、`ConfigStore.swift`、`Command.swift`、`CommandRegistry.swift`。
- 改:`GhosttyRuntime`(读 config)、`AppStyle`(主题派生)、`main.swift`(命令分发)、`AppCoordinator`(注册命令、按 kind 造 surface)。

## 测试(TDD，先写失败用例)

CmuxCore(纯，可单测):
- `AppConfig`:完整 YAML→解码正确;**缺字段→默认**;未知字段→忽略;非法值→`validated()` 夹紧。
- `KeyChord`:各种键位串解析(含特殊键、大小写、非法串)。
- 命令键位解析、`PaneKind` 默认。
App 层:`CommandRegistry.dispatch` 命中/未命中/canRun 置灰;config 键位覆盖默认。
(注:Yams 解码用一两个 fixture YAML 串做集成测试。)

## 风险

- ghostty 运行时改字号/配色的接口是否齐全 → 先翻 `ghostty.h`;不全则"重开生效"兜底。
- FSEvents/DispatchSource 文件监听的边界(编辑器原子写=重命名)→ 监听目录而非 inode。
- Yams 引入 libyaml(C)依赖 → 评估构建/体积(可接受)。

## 三主题自检

- **高性能**:分发 O(1);配置增量热更新、不全量重建;YAML 仅加载/变更时解析。
- **高扩展**:命令可注册、配置数据驱动、主题数据驱动、pane 内容按 kind 分发可插拔。
- **高商用**:YAML 人可手编 + 注释模板;损坏/缺字段优雅回退不崩;向前向后兼容;校验夹紧。

## 落地步骤(建议顺序)

1. Core:`AppConfig` + 容错解码 + `validated()` + 单测。
2. App:Yams 依赖 + `ConfigLoader`(读/写默认模板/回退) + `ConfigStore`。
3. `GhosttyRuntime` 改读 config;`AppStyle` 主题派生。
4. Core:`KeyChord` + 单测;App:`Command` + `CommandRegistry` + 单测;`main.swift` 改查表分发。
5. 热更新(文件监听 + 增量应用)。
6. `PaneKind` + factory 按 kind 分发(只注册 terminal)。
