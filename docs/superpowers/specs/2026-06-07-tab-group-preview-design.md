# 分屏 Tab → 分组 + 悬浮真实预览

日期:2026-06-07 · 状态:已批准,实施中

## 目标

当一个 tab 被分屏(含 ≥2 个终端 pane)时,它在顶部 Tab 栏自动呈现为"分组"样式;
鼠标悬停该分组胶囊时,弹出一张按真实分屏布局排列的**真像素缩略图**预览,让用户不切换就能看到组里每个终端当前的画面。

## 关键约束(架构现状)

- 所有 tab 的终端 surface 常驻存活(PTY 一直跑),但 `AppCoordinator.rebuild()` 只把**当前 active tab** 的分屏树挂进窗口;
  后台 tab 的 Metal 层不在屏上 → **不渲染**。
- 因此后台分组的预览**必然是"上次可见时"缓存的画面**,无法实时;可见 tab 的预览是新鲜的。
- 截图可行性已验证:ConductorApp 自己调 `CGWindowListCreateImage(.optionIncludingWindow, 自身 windowID)`
  能正确抓到 libghostty 的 Metal 渲染像素,无需额外权限(已在真机确认,见 spike)。

## 设计

### 1. 分组判定(ConductorCore,纯逻辑)
- `Tab` 增加派生属性 `var isGroup: Bool { rootSplit.leaves().count > 1 }`。不新增存储状态。
- 分屏后自动成组,关到只剩 1 个 pane 自动退回普通 tab。

### 2. 缩略图采集(ConductorApp 层,不污染 Core)
- 新增 `PaneSnapshotStore`(`@MainActor`):`[PaneID: Snapshot]`,`Snapshot = (image: NSImage, capturedAt)`。
- 采集:一次 `CGWindowListCreateImage` 截整窗 → 按每个可见 `PaneContainerView` 的窗口坐标裁剪 →
  降采样(长边 ≤ 320pt)→ 存入 store。坐标换算需处理 AppKit(左下原点)↔ CGImage(左上原点)翻转与 backing scale。
- 触发:① 切走某 tab **前**先截一遍它当前可见的 pane;② 窗口为 key 时每 ~2s 轻量刷新当前可见 pane;
  ③ tab 切换稳定后补一张。
- 回退:从没截过的 pane → 结构占位(深色卡片 + 标题文字)。
- 弃用提示:`CGWindowListCreateImage` 在 macOS 14 标记 deprecated 但仍可用;v1 接受,后续可换 ScreenCaptureKit。

### 3. 分组胶囊(TabBarView)
- 单 pane:维持现状(终端图标 + 标题胶囊)。
- 分组(≥2):分组样式——分屏小图标 + 代表标题 + 数量角标 `N`,视觉上与单终端区分。
  具体观感在真机迭代(截图调)。

### 4. 悬浮预览(SwiftUI 自绘浮层)
- 悬停胶囊约 0.35s 后,在其下方弹出预览卡。移开后短延迟隐藏。
- 内容:按 `tab.rootSplit` 递归布局的小地图(沿用真实 axis/ratio),每个叶子格放该 pane 的缓存缩略图 + 标题叠字;
  active pane 高亮。单 pane tab = 1 格大图。
- 交互:点预览 = 切到该 tab(v1)。"点某格直接聚焦那个 pane"留作后续增强。

### 5. 接线
- `AppCoordinator` 持有 `PaneSnapshotStore`,暴露 `@Published` 快照供 SwiftUI 读取;
  在 `rebuild()`/tab 切换/定时器处驱动采集。
- `TabBarView` 读 `tab.rootSplit` + 快照渲染分组胶囊与悬浮预览。

## 非目标(YAGNI)
- 不做后台 pane 的实时离屏渲染(架构不支持,代价过高)。
- 不做预览内点击直达某 pane(留后续)。
- 不引入 ScreenCaptureKit(用现成 CGWindowListCreateImage)。

## 风险
- 后台分组预览为"上次可见"快照,可能略旧 —— 已与用户确认接受。
- 窗口↔图像坐标换算、retina scale 易出错 —— 实现时单独验证裁剪对齐。
