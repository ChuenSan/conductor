# conductor 克隆 · 功能路线图与设计

> 本文是**规划文档**:盘点剩余功能、分阶段排布、每个特性给出设计草图(目标 / 交互 / 实现思路 / 风险 / 粗略工作量)。
> 真正动工某个特性时，再为它单独写一份详细 spec(`docs/superpowers/specs/`)。
> 维护约定:做完一项就在这里打勾并标注落地 commit。

最后更新:2026-06-07

---

## 指导原则(贯穿主题)

**所有设计决策都按这三条评判**——每写一份特性 spec 都要显式回应:

1. **高性能**:不阻塞主线程、不做无谓全量重建/反复重渲染;后台活(截图/索引)轻量异步;pane/tab/工作区数量增长时线性可扩。终端已走 GPU(libghostty/Metal)是基线。
2. **高扩展**:能力**可注册 / 数据驱动**，不硬编码——命令走中央命令表、配置走 schema 化 `AppConfig`、主题数据驱动、pane 内容做成可插拔"内容提供者"协议(给 v2 Agent pane 留口)。`ConductorCore` 保持引擎无关。
3. **高商用**:商业级品质——零崩溃、有错误处理与空状态、统一精致视觉、设置/主题/键位可定制，可演进到自动更新/授权/无障碍/i18n。

> 这正是为什么**基建(配置系统 + 命令表)排在最前**:它们是"高扩展"的地基，后面一半特性都挂在上面。

---

## 已完成(基线)

- libghostty 真终端(GPU 渲染 + PTY)，预编译 GhosttyKit.xcframework 绕开 Zig 链接问题
- 工作区(侧栏，绑目录) / 每工作区多 Tab / Tab 内自由分屏(二叉树 SplitNode)
- 持久化 B 级(恢复布局结构 + 在 cwd 重开空 shell，不恢复进程/scrollback)
- 深色统一主题 + 圆角终端卡片，无分割线
- 终端滚动；pane 拖拽重排(落点高亮、并排/堆叠)
- 顶部紧凑布局
- **分屏 Tab → 分组胶囊 + 悬停真实预览**(点击穿透浮层；截 Metal 像素缓存)
- Tab 关闭(X) / 重排；工作区 重命名 / 删除 / 重排(右键菜单)
- 手势冲突修复(点击 vs 拖拽)、单 item 不可拖

**现有键位**:⌘T 新 Tab · ⌘D 左右分 · ⌘⇧D 上下分 · ⌘W 关闭活动 pane · ⌘⌥←/→ 切换 pane

**核心架构**:`ConductorCore`(纯逻辑 + reducer `WorkspaceCommand` → `SessionEffect`，可单测) · `AppCoordinator`(协调命令/副作用/重建) · `GhosttySurface`/`TerminalHostView`(libghostty 桥) · SwiftUI 外壳。

---

## 贯穿性基建(多个特性共用，建议先打底)

这几块是后面多个特性的地基，优先级靠前:

### B1. 配置系统 `AppConfig` + 持久化
- **目标**:把散落在 `GhosttyRuntime` 里的硬编码(字号、配色、padding、shell)收敛成一个可读写的 `AppConfig`，存到 `~/Library/Application Support/conductor/config.json`(或 `~/.config/conductor/`)。
- **实现**:`ConductorCore` 加 `AppConfig: Codable`(字段:font、fontSize、theme、shell、keybindings、behavior)。`GhosttyRuntime.ensureStarted` 从 config 生成 ghostty 配置串。改字号/主题时重建 ghostty config 并刷新所有 surface。
- **依赖方**:字号缩放、设置面板、主题切换、工作区默认 shell。
- **风险**:ghostty 配置改了要不要重启 surface？多数项可 `ghostty_surface_set_*` 或重载，少数需重建。先做"重开生效"，再优化热更新。
- **工作量**:中。

### B2. 命令注册表 `Command` + 中央分发
- **目标**:把 `main.swift` 里 if/else 的键位监听，换成"命令表"(id、标题、默认快捷键、作用域、handler)。
- **实现**:`AppCoordinator` 暴露 `[Command]`；`main.swift` 的 keyMonitor 查表分发。命令面板(P2)和键位设置(P3)都读这张表。
- **依赖方**:命令面板、键位帮助浮层、自定义键位。
- **工作量**:中(重构现有键位)。

---

## Phase 1 — 终端体验补全

让它达到"日常能当主力终端用"的完整度。

### 1.1 字号缩放 ⌘+ / ⌘- / ⌘0
- **交互**:⌘= 放大、⌘- 缩小、⌘0 复位；作用于当前 pane(或全局，二选一，建议全局统一)。
- **实现**:依赖 B1。改 `AppConfig.fontSize` → 重新生成 ghostty 配置 → 对所有 surface 应用(`ghostty_surface_set_font_size` 若可用，否则重载 config)。
- **风险**:逐 surface vs 全局；ghostty C API 是否有运行时设字号接口(需查 `ghostty.h`)。
- **工作量**:小~中。

### 1.2 终端内搜索(scrollback search)
- **交互**:⌘F 唤起搜索条(自绘，叠在 pane 顶部)，输入即高亮，回车/⌘G 跳下一个，Esc 关闭。
- **实现**:查 libghostty 是否暴露搜索 API(`ghostty_surface_*search*`)。若有→桥接 + 自绘搜索条 UI;若无→这是个大坑(要自己读 scrollback)，降级为"先不做/只做可视区"。
- **风险**:**高**——取决于 libghostty 是否给搜索能力。需先 spike 翻头文件。
- **工作量**:未知(看 API)。

### 1.3 复制/粘贴/全选 + URL 点击
- **交互**:⌘C 复制选区、⌘V 粘贴、⌘A 全选;⌘+点击 或 悬停高亮 URL 点击打开(注意:⌘+拖已用于拖 pane，URL 点击改用普通点击或 ⌘+单击需消歧)。
- **实现**:复制/粘贴回调已有(剪贴板 cb)。补 ⌘C/⌘V/⌘A 键位 → ghostty 对应动作。URL:查 ghostty 的 link/osc8 动作(`GHOSTTY_ACTION_OPEN_URL`?)。
- **风险**:⌘+点击 与现有 ⌘+拖 pane 冲突，需重新设计 pane 拖拽触发(见 2.2 用专门抓手)。
- **工作量**:中。

### 1.4 清空 scrollback
- **交互**:⌘K 清屏(或菜单)。
- **实现**:ghostty clear 动作 / 发送 reset。查 API。
- **工作量**:小。

### 1.5 可见滚动条
- **交互**:右侧细滚动条，滚动/有内容时淡出现，悬停变粗，可拖。
- **实现**:监听 `GHOSTTY_ACTION_SCROLLBAR`(若 ghostty 上报滚动位置/比例)，自绘一个覆盖在 pane 右缘的滑块(注意 Metal 兄弟视图白屏的坑——滚动条必须是 frameView 的兄弟、非 Metal 兄弟)。
- **风险**:Metal 兄弟视图约束;ghostty 是否上报滚动信息。
- **工作量**:中。

### 1.6 关闭确认(有运行进程时)
- **交互**:关 pane/tab/窗口时若子进程非 shell(在跑命令)，弹确认。
- **实现**:跟踪 child-exited / 前台进程(ghostty 是否给前台进程名?)。先简单:总是不确认(当前)→ 可配置。
- **工作量**:小~中。

---

## Phase 2 — 导航与管理

### 2.1 命令面板 / 快速切换 ⌘K(或 ⌘P)
- **目标**:conductor/VSCode 式的模糊面板:切 Tab、切工作区、聚焦 pane、跑命令(新建/分屏/关闭/重命名…)。
- **交互**:⌘K 弹居中浮层 + 搜索框 + 模糊匹配结果(工作区/Tab/命令)，↑↓ 选、回车执行、Esc 关。
- **实现**:依赖 B2(命令表) + 一个 fuzzy 匹配。SwiftUI 自绘浮层(可复用预览面板的浮窗思路;注意点击/键盘焦点要进面板，与预览的"穿透"相反)。
- **工作量**:中~大。

### 2.2 pane 关闭按钮 + pane 放大/缩放
- **交互**:pane 头条 hover 出 X(关该 pane);双击头条或 ⌘Enter 把该 pane 放大到占满 Tab(再按还原);其余 pane 暂时隐藏。
- **实现**:关闭→`closeActivePane`(已具备，补按钮)。放大→模型加"zoomed pane"态(或临时只渲染该 pane 的视图，不改 SplitNode)，`AppCoordinator.rebuild` 读该态决定渲染整棵树还是单 pane。顺便把 pane 拖拽触发收敛到"头条抓手"(解决 1.3 的 ⌘+点击冲突)。
- **工作量**:中。

### 2.3 Tab / pane 手动重命名
- **交互**:双击 Tab 标题行内编辑(像工作区重命名);重命名后锁定，不再被 cwd 自动覆盖。
- **实现**:`Tab` 加 `customTitle: String?`;有则显示它，否则显示 cwd 派生名。行内 TextField(复用侧栏重命名模式)。
- **工作量**:小~中。

### 2.4 预览深化
- **目标**:把已做的悬停预览变得可操作。
- **交互**:① 点预览里某一格 → 直接切到该 Tab 并聚焦那个 pane;② 从预览/终端把一个 pane 拖出分组 → 成为新 Tab。
- **实现**:① 预览面板要可点(与当前"穿透"矛盾)——做法:面板默认穿透，悬停进面板时临时关穿透并高亮格子，点击→`selectTab + focusPane`。② 拖出成新 Tab:movePane 的扩展(目标为"空"=新建 Tab)。
- **风险**:穿透/可点的状态切换易抖动;需细调。
- **工作量**:中。

### 2.5 键位帮助浮层 ⌘/
- **交互**:⌘/ 弹出当前所有快捷键速查(读 B2 命令表)。
- **工作量**:小。

---

## Phase 3 — 设置与个性化

### 3.1 设置面板
- **目标**:GUI 改 字体 / 字号 / 主题 / 默认 shell / 行为 / 键位。
- **交互**:⌘, 打开设置窗(SwiftUI 表单)，改完即时生效(依赖 B1 热更新)。
- **实现**:读写 `AppConfig`;分区:外观、终端、键位、工作区默认。
- **工作量**:中~大。

### 3.2 主题 / 配色
- **目标**:多套内置主题(深/浅/几款配色) + 自定义。
- **实现**:`AppConfig.theme` → 一组色(背景/前景/光标/选区/ANSI 16 色) → 喂 ghostty 配置 + 同步 SwiftUI 外壳 token(`AppStyle` 改为从 theme 派生)。
- **工作量**:中。

### 3.3 工作区个性化
- **交互**:工作区右键 → 设置:颜色/图标、默认启动命令(如 `nvim .`)、默认 shell、是否新 Tab 自动 cd。
- **实现**:`Workspace` 加 `color/icon/startupCommand/shell` 字段;新建 pane 时按工作区配置起 shell/跑命令。
- **工作量**:中。

---

## Phase 4 — 窗口与会话

### 4.1 多窗口
- **目标**:开多个窗口,各看不同工作区/Tab。
- **实现**:**大重构**——当前 `AppCoordinator` 是单例式持有全局 store + 单 `containerView`。要么:窗口共享同一 store、各自渲染不同 active(轻);要么:每窗口独立 coordinator(重)。建议先做"共享 store、多窗口各自选 active 工作区"。
- **风险**:高(架构)。SessionRegistry/快照/键位都要按窗口区分。
- **工作量**:大。

### 4.2 Tab 拆分到新窗口(detach)
- **交互**:拖 Tab 出栏 / 右键"移到新窗口"。
- **依赖**:4.1。
- **工作量**:中(在多窗口基础上)。

### 4.3 全屏 / 专注模式
- **交互**:F11 原生全屏;专注模式 = 隐藏侧栏 + Tab 栏，只剩终端(⌘⏎ 或快捷键)。
- **工作量**:小~中。

### 4.4 命名布局 / 预设
- **目标**:保存当前分屏布局为模板，一键在新工作区重建(如"编辑器+服务器+日志"三分屏)。
- **实现**:序列化 SplitNode 结构(去掉具体 paneID)成模板,应用时实例化新 pane。
- **工作量**:中。

### 4.5 状态栏(footer)
- **交互**:底部细条:当前 pane 的 cwd 全路径 / git 分支 / 前台进程 / 时间。
- **实现**:cwd 已有(cwd 事件);git 分支需读 `.git/HEAD`;前台进程需 ghostty 提供或读 PTY。
- **工作量**:中。

---

## Phase 5 — v2:AI Agent 集成(核心差异化，需单独深度 brainstorm)

> 这是 conductor 的灵魂(把终端管理器变成"AI 工作台")。本节只列**架构骨架与待决问题**，正式做之前要专门开一轮 brainstorm + 独立 spec。

### 5.1 形态:Agent 作为一种特殊 pane
- 一个 pane 可以是"终端"或"Agent 会话"。Agent pane = 对话视图(prompt/流式输出/工具调用/审批) + 绑定一个工作目录(常配 git worktree)。
- `SplitNode.leaf` 的内容从"纯 PaneID"扩展为"PaneID + 类型(terminal | agent)"。

### 5.2 会话与执行模型
- Agent 跑一个 agentic loop(读取任务 → 规划 → 调工具/跑命令 → 观察 → 迭代)。
- 命令在关联的终端/worktree 里执行(可视化:Agent pane 旁挂一个终端 pane 显示它跑的命令)。
- 审批门:危险操作(写文件/删除/推送)需用户确认。

### 5.3 任务管理
- 多个 Agent 任务并行(每个一个 worktree/分支),侧栏或面板列任务 + 状态(运行/等待审批/完成)。
- 这正好复用现有 worktree 思路(项目已知 `using-git-worktrees`)。

### 5.4 后端
- 用 Claude(Agent SDK / Messages API)。需要:模型调用、工具定义(读写文件/跑命令/搜索)、流式、上下文管理。
- 待决:进程内 SDK 还是子进程跑 claude-code?密钥管理?成本控制?

### 5.5 待决问题(brainstorm 输入)
- Agent 与终端共享 PTY 还是各自独立?
- 任务隔离用 worktree 的粒度(每任务一分支)?
- 审批/diff 的 UI 形态?
- 离线/取消/重试语义?

---

## 下一批功能计划（含 libghostty API 可行性，2026-06-08 spike 确认）

libghostty 暴露的能力比预想丰富——以下均**可行**：

### N1. 终端滚动条（自绘）
- ghostty 通过 `GHOSTTY_ACTION_SCROLLBAR`(`ghostty_action_scrollbar_s`)上报视口位置/比例。
- 在每个 pane 右缘自绘细滚动条（**必须是 frameView 的兄弟、非 Metal 兄弟**，遵守白屏约束），滚动/有内容时淡现、悬停变粗、可拖。
- 风险：低。工作量：中。

### N2. 终端内搜索 ⌘F（上下文搜索）
- ghostty 有 `START_SEARCH/END_SEARCH/SEARCH_TOTAL/SEARCH_SELECTED` actions：ghostty 负责匹配/高亮，我们渲染搜索条（输入框 + 匹配计数 + 上/下一个 + Esc）。
- 路由这些 action 到自绘搜索条 UI；输入回传给 ghostty。
- 风险：中（需理清驱动方式）。工作量：中~大。

### N3. 复制/粘贴/全选/清屏/URL
- 选择：`ghostty_surface_has_selection/read_selection/clear_selection`；剪贴板回调已具备。
- ⌘C/⌘V/⌘A 注册为命令（命令表）；清屏发送序列。
- URL：`MOUSE_OVER_LINK`(悬停高亮) + `OPEN_URL` action（点击打开）。注意与 ⌘+拖 pane 消歧。
- 风险：低~中。工作量：中。

### N4. 设置面板扩充（全自绘，已有控件库）
- **键位自定义**：列出命令表 + 可编辑快捷键（录制）。
- **自定义配色**：theme=custom 时给 background/foreground/cursor/selection/ansi 的取色器。
- **字体选择器**：系统等宽字体下拉。
- **窗口透明度/背景模糊**（`TOGGLE_BACKGROUND_OPACITY`）。
- 风险：低。工作量：中。

### N5. 右键菜单扩充
- 终端内容右键：复制/粘贴/全选/清屏（N3）。
- pane 右键加：放大/缩放(zoom)、复制 cwd、在 Finder 打开。
- tab 右键加：重命名标签、左移/右移。
- 风险：低。工作量：小~中。

### N6. pane 放大/缩放 ⌘Enter
- 临时只渲染当前 pane 占满 tab（模型加 zoomed 态，rebuild 读它）。或用 ghostty `TOGGLE_SPLIT_ZOOM`。
- 风险：低。工作量：中。

### N7. Tab 手动重命名
- 双击 tab 标题行内编辑；`Tab.customTitle` 有则显示、不再被 cwd 覆盖。
- 风险：低。工作量：小。

> 建议起步顺序：**N1 滚动条**(可见、独立) → **N4 设置扩充 / N5 右键扩充**(纯自控) → **N3 复制粘贴/URL** → **N2 搜索**(最复杂) → N6/N7。

## 建议优先级(可调)

1. **基建 B1(配置)+ B2(命令表)** — 后面一半特性的地基
2. **Phase 1 终端体验**(字号、复制粘贴、URL、清屏、滚动条)— 立刻提升日常可用性
3. **Phase 2 导航**(命令面板、pane 关闭/放大、重命名、预览深化)
4. **Phase 3 设置/主题**
5. **Phase 4 多窗口/会话**(大重构，按需)
6. **Phase 5 v2 AI**(单独立项)

> 每项动工前转成 `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` 详细 spec + 单测先行。
