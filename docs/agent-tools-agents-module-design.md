# Agent Tools 管理台：Agents 模块设计

## 定位

`Agents` 模块是 Agent Tools 管理台里的 Agent Registry。它不是右侧快捷面板，也不是 Settings 里的简陋 `AI 助手`配置行。

它统一回答四个问题：

- 本机有哪些 Agent 可以启动？
- 哪些 Agent 已经被加入 Conductor 的启动入口？
- 哪些 Agent 能接收 Skills 分发？
- 当前有哪些 Agent 正在运行、最近有哪些会话可以续聊？

## 概念拆分

### Launch Target

Launch Target 是“能在终端里启动的 Agent CLI”。

来源：

- `AgentCatalog.all`
- `CLIDetectionStore`
- `AgentCatalog.detectStatuses()`
- `ConfigStore.shared.config.terminal.aiAgents`
- `AppCoordinator.launchableAgents`

它关注：

- 命令：`codex`、`claude`、`cursor-agent` 等
- 是否安装
- 路径和版本
- 是否出现在新建 Agent 会话入口
- 能否启动到新标签或分屏

### Skill Target

Skill Target 是“能接收 Skills 的工具目录”。

来源：

- `SkillToolCatalog`
- `SkillManagerEngine.tools()`
- `ManagedSkill.targets`

它关注：

- Agent 工具的 Skills 目录
- 是否检测到对应工具目录
- 是否启用 Skills 分发
- 已同步 Skills 数量
- 是否有项目级 Skills 目录

### Runtime Agent

Runtime Agent 是“当前正在 pane 里跑的 Agent”。

来源：

- `AppCoordinator.paneAgents`
- `thinkingPanes`
- `unseenDonePanes`
- `paneQueues`

它关注：

- 当前有多少 pane 正在跑 Codex/Claude/其他 Agent
- 是否思考中
- 是否完成未读
- 是否有队列

### Session Agent

Session Agent 是“本机可续聊的历史会话”。

来源：

- `SessionManagerStore.shared.records`
- `AgentSessionCatalog`

它关注：

- 最近会话数量
- Codex / Claude 会话数量
- 可续聊命令
- 会话所在目录

## 合并模型

Agents 模块 UI 不直接暴露四套数据，而是合并成 `AgentToolsAgentRow`：

```swift
id
title
command
launchStatus
skillStatus
runtimeStatus
sessionStatus
cliTool
configuredAgent
launchableAgent
skillTool
syncedSkillCount
recentSessionCount
runningPaneCount
```

合并规则：

- 以 `AgentCatalog`、`terminal.aiAgents`、`SkillToolCatalog` 的并集为基础。
- `codex`、`claude`、`gemini` 等要能把 CLI 与 Skill 工具目录映射到同一行。
- 自定义 `terminal.aiAgents` 即使没有 CLI 检测结果，也必须显示。
- Skill-only 工具即使不能启动，也必须显示为“可接收 Skills”。
- 已停用的 Agent 不隐藏，只显示停用状态。

## ID 映射

CLI id 和 Skill tool key 不完全一致，需要显式映射：

| CLI / Agent id | Skill tool key |
| --- | --- |
| `codex` | `codex` |
| `claude` | `claude_code` |
| `gemini` | `gemini_cli` |
| `cursor` | `cursor` |
| `copilot` | `github_copilot` |
| `grok` | `grok` |
| `opencode` | `opencode` |
| `amp` | `amp` |
| `auggie` / `augment` | `augment` |
| `qwen` | `kimi` 暂不自动映射，避免错配 |

未知映射不猜，显示为两行或显示缺失能力。

## 页面布局

Agents 模块沿用管理台三栏骨架。

```text
┌─────────────────────────────────────────────────────────────────────┐
│ Agents                                                              │
│ [搜索 Agent / 命令 / 目录] [全部|可启动|可接收 Skill|运行中|未配置] [扫描] │
├─────────────────────────────────────────────────────────────────────┤
│ Status Strip                                                        │
│  可启动 6   已配置 4   Skill 目标 18   运行中 2   可续聊 120           │
├─────────────────────────────────────────────────────────────────────┤
│ Agent Registry                                                      │
│  Agent        启动      Skills      运行态      会话      操作         │
│  Codex        可启动    12 Skills   1 pane      80        启动/详情    │
│  Claude       可启动    8 Skills    思考中      40        启动/详情    │
│  Cursor       缺 CLI    可接收      -           -         配置/目录    │
└─────────────────────────────────────────────────────────────────────┘
```

## 中间工作区

### 顶部 Header

- 标题：`Agents`
- 副标题：`启动入口、Skill 目标、运行状态和可续聊会话`
- 动作：
  - `重新扫描 Agent`
  - `自动加入已检测`
  - `新增自定义 Agent`

### 状态条

- `可启动`：来自 `launchableAgents` 或安装 CLI 数
- `已配置`：来自 `terminal.aiAgents`
- `Skill 目标`：来自 `SkillToolInfo.enabled && (installed || isCustom || hasPathOverride)`
- `运行中`：来自 `paneAgents`
- `可续聊`：来自 `SessionManagerStore.records`

### Registry 表

字段：

- Agent logo / 名称 / command
- Launch：可启动、未安装、已停用、自定义
- Skills：可接收、已停用、未检测、已同步数量
- Runtime：运行 pane 数、思考中、完成未读、排队中
- Sessions：最近会话数、最近修改时间
- 操作：启动、打开详情、复制命令、显示目录

交互：

- 单击行：右侧 Inspector 显示详情。
- 双击可启动行：新标签启动 Agent。
- 右键：
  - 启动到新标签
  - 复制启动命令
  - 复制 CLI 路径
  - 显示 Skills 目录
  - 启用/停用启动入口
  - 启用/停用 Skill 目标
  - 打开会话列表

## 右侧 Inspector

未选中：

- Agents 模块说明
- 本机数据新鲜度
- 快捷动作：扫描、加入已检测、新增自定义

选中 Agent：

- 基础信息：名称、id、command、类型
- CLI：安装状态、版本、路径
- 配置：是否在 `terminal.aiAgents` 中，是否启用
- Skills：Skills 目录、启用状态、已同步 Skills 数
- Runtime：运行 pane 数、思考中/完成未读/排队中
- Sessions：最近会话、续聊入口
- 操作：
  - 启动到新标签
  - 复制命令
  - 复制诊断信息
  - 显示 CLI 路径
  - 显示 Skills 目录
  - 打开 Skills 模块并筛选该 Agent

## 新增自定义 Agent

第一版用轻量弹窗/内联编辑：

- 名称
- 命令
- 是否启用

写入：

- `AppConfig.terminal.aiAgents`
- 通过 `onApplyConfig` 调用 `AppCoordinator.applyConfig`

不在第一版做：

- 图标上传
- 环境变量模板
- 多命令 profile
- 参数模板

## 第一版开发范围

这次先做一个完整可用的 Agents 管理台基础版：

- 合并 Agent Registry 数据
- Agents 主表
- 搜索、筛选、排序
- 右键菜单
- Inspector
- 启动到新标签
- 复制命令/路径/诊断
- 自动加入已检测 Agent 到配置
- 启停配置中的 Agent
- 展示 Skill 目标和已同步 Skills 数
- 展示运行中 pane 和最近会话数

第一版不做：

- 复杂自定义 Agent 编辑器
- Skills 模块联动筛选路由
- 运行 pane 跳转
- 会话预览嵌入
- 批量操作

## 设计原则

- Agents 是统一注册表，不是配置表。
- 启动能力、Skill 分发能力、运行态、会话历史必须同屏建立关系。
- 不把 Skill 中心库降级成 Agents 的子功能。
- 未安装、未配置、停用都要显示，不能隐藏导致新人找不到入口。
- 所有联网动作必须手动触发；Agents 模块自身只读本机状态和配置。
