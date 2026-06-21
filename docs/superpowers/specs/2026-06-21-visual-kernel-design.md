# Visual Kernel 设计

日期：2026-06-21

## 背景

Cowart 证明了一个轻量画布可以让 Codex 参与视觉工作流，但它的核心能力仍然接近“大提示词 + 画布 + 图片插入工具”。用户真正想要的是一个更高维度的 AI 原生视觉编辑系统：不是让 AI 模仿人类去点 Photoshop，而是给 AI 一个可寻址、可约束、可验证、可回滚的视觉世界模型。

Photoshop 的图层是面向人类鼠标和眼睛的 UI 抽象。Visual Kernel 保留图层作为导出和兼容格式，但系统本体不是 layer，而是 `Entity + Constraint + Transaction`。

## 产品论点

Visual Kernel 是一个 AI 原生视觉编辑内核。

它不把图像模型当成最终编辑器，而是把图像模型当成候选内容生成器。最终写入必须经过确定性合成器和验证器。

核心原则：

- AI 可以提出修改，但不能直接提交修改。
- 每次编辑必须声明目标、可写区域、锁定对象和验证规则。
- 未授权区域的稳定性由系统保证，而不是由提示词保证。
- 图层、PSD、ORA、Canvas、tldraw shape 都是 Visual State Graph 的投影视图，不是核心本体。

## v0.1 目标

v0.1 只证明一个闭环：

1. 导入一张图。
2. 建立最小 Visual State Graph。
3. 识别或手动指定目标实体和可编辑区域。
4. 创建编辑事务。
5. 调用一个模型 adapter 生成候选 patch。
6. 使用 mask 做确定性合成。
7. 验证未授权区域没有变化。
8. 生成 preview。
9. 支持 commit 和 rollback。

v0.1 的成功标准不是“什么都能改”，而是“能证明 AI 没有改它不该改的地方”。

## 非目标

v0.1 不做以下事情：

- 不做完整 Photoshop 替代。
- 不做完整图层面板、画笔系统、滤镜系统。
- 不训练自有大模型。
- 不承诺扁平 JPEG/PNG 一键完美分层。
- 不实现完整 PSD 写入兼容。
- 不让模型输出直接覆盖最终画面。
- 不把 Codex skill 当作核心能力层；skill 只负责教 agent 调用 MCP。

## 架构

系统采用 kernel-first、MCP-first、UI-later 的架构。

```text
Agent Layer
  Codex / Claude / Cursor / ChatGPT-compatible clients

MCP Server
  Stable tool contract for agent access

Visual Kernel
  Visual State Graph, transaction engine, storage, validation

Model Worker
  Segmentation, OCR, image editing model adapters

Renderer
  Deterministic compositor, preview render, export views
```

### 模块边界

- `graph`：定义 `VisualProject`、`Asset`、`Entity`、`Mask`、`Constraint`、`Relation`。
- `transaction`：定义 `EditTransaction` 生命周期和状态迁移。
- `compositor`：把 base image、candidate patch、mask 合成为 preview，不调用生成模型。
- `validators`：验证 mask 外像素、锁定实体、OCR 文本和画布属性。
- `storage`：管理项目目录、assets、masks、transactions、previews、history。
- `model-router`：把统一请求路由到 OpenAI、Gemini、Qwen、FLUX 或本地 worker。
- `mcp-server`：暴露 Visual Kernel 能力给 Codex/Claude。
- `preview-web`：显示 before/after、mask overlay、验证结果和 commit/rollback 状态。
- `vision-worker`：Python 服务，负责模型侧任务；v0.1 可以先接一个远程图像编辑模型和一个 OCR 工具。

## Visual State Graph

`VisualProject` 是所有状态的根对象。

```json
{
  "schemaVersion": 1,
  "projectId": "proj_001",
  "canvas": {
    "width": 2048,
    "height": 1536,
    "colorSpace": "srgb",
    "background": "transparent"
  },
  "assets": {
    "asset_base": {
      "kind": "image",
      "path": "assets/base.png",
      "sha256": "hex",
      "width": 2048,
      "height": 1536
    }
  },
  "entities": {
    "ent_cup": {
      "kind": "object",
      "label": "cup",
      "description": "red ceramic cup on the table",
      "sourceAssetId": "asset_base",
      "bbox": [420, 610, 220, 310],
      "visibleMaskId": "mask_cup_visible",
      "editableMaskId": "mask_cup_editable",
      "locked": false,
      "relations": [
        {
          "type": "on_top_of",
          "targetEntityId": "ent_table"
        }
      ]
    }
  },
  "masks": {
    "mask_cup_editable": {
      "path": "masks/mask_cup_editable.png",
      "semanticRole": "editable",
      "source": "manual_or_model",
      "bbox": [420, 610, 220, 310]
    }
  },
  "transactions": [],
  "history": []
}
```

## Entity 模型

`Entity` 是 AI 和用户都能指代的视觉对象。它可以映射到一个传统 layer，也可以只是扁平图中的一个区域。

必需字段：

- `id`：稳定实体 ID。
- `kind`：`object`、`text`、`logo`、`person`、`background`、`region` 之一。
- `label`：短标签，例如 `cup`。
- `description`：可读描述，供 agent 推理。
- `bbox`：实体在 canvas 中的边界框。
- `visibleMaskId`：当前可见区域。
- `editableMaskId`：默认可写区域。
- `locked`：是否禁止写入。

v0.1 中，实体来源可以是：

- 用户手动画框或传入 mask。
- agent 基于图像说明创建粗粒度实体。
- vision worker 生成候选实体，用户或 agent 选择确认。

## Mask 模型

Mask 是写权限边界，不只是视觉选择。

Mask 分为三类：

- `visible`：实体当前可见像素。
- `editable`：本次允许模型修改的区域。
- `spill`：允许为了阴影、反射、边缘融合产生轻微变化的扩展区域。

v0.1 默认只使用 `editable`。如果没有明确 `spill`，验证器必须把 `editable` 外的像素视为锁定。

## 编辑事务生命周期

所有编辑都必须通过 `EditTransaction`。

```json
{
  "id": "txn_001",
  "status": "draft",
  "intent": "change the cup to blue",
  "targetEntityIds": ["ent_cup"],
  "readEntityIds": ["ent_cup", "ent_table", "ent_background"],
  "lockedEntityIds": ["ent_logo", "ent_title"],
  "writeMaskIds": ["mask_cup_editable"],
  "validators": [
    {
      "type": "outside_write_mask_pixel_diff",
      "maxChangedPixels": 0
    },
    {
      "type": "locked_entity_pixel_diff",
      "maxChangedPixels": 0
    }
  ],
  "candidates": []
}
```

状态迁移：

```text
draft
-> candidate_generated
-> verified
-> previewed
-> committed
```

失败状态：

```text
candidate_failed
verification_failed
rolled_back
```

规则：

- `draft` 事务不能修改项目渲染结果。
- `candidate_generated` 只保存候选 patch 和合成 preview。
- `verified` 表示所有验证器通过。
- `previewed` 表示用户或 agent 已获得可检查 preview。
- `committed` 才会更新项目当前 render state。
- 任意未提交事务都必须能删除，不影响项目当前状态。

## 合成器

Compositor 只做确定性像素操作。

输入：

- base render。
- candidate patch。
- write mask。
- patch placement。
- blend mode，v0.1 只支持 `normal`。

输出：

- preview image。
- changed-pixel map。
- write-mask coverage report。

v0.1 合成规则：

- mask 内使用 candidate patch。
- mask 外必须保留 base render 原像素。
- 如果 candidate patch 尺寸不匹配，先按事务中声明的 bbox 进行裁剪或缩放。
- 合成器不能调用图像生成模型。

## 验证器

v0.1 必须实现以下验证器。

### outside_write_mask_pixel_diff

验证 write mask 外的像素是否变化。

默认阈值：

- `maxChangedPixels`: `0`
- `maxPerChannelDelta`: `0`

如果未来支持色彩管理或有损中间格式，可以在事务中显式放宽阈值；v0.1 默认不放宽。

### locked_entity_pixel_diff

验证锁定实体区域是否变化。

输入：

- base render。
- preview render。
- locked entity visible mask。

默认阈值与 mask 外 diff 相同。

### ocr_text_unchanged

验证锁定文字实体的 OCR 内容未变化。

v0.1 中 OCR 验证只用于 demo 3。验证器需要返回：

- before text。
- after text。
- changed text spans。
- pass/fail。

### canvas_properties_unchanged

验证画布宽高、色彩空间和背景设置未被事务改变。

## MCP 工具契约

v0.1 MCP server 暴露以下工具。

### visual.create_project

创建项目目录和空 graph。

输入：

```json
{
  "projectDir": "/absolute/path/to/project",
  "name": "poster-edit"
}
```

输出：

```json
{
  "projectId": "proj_001",
  "projectPath": "/absolute/path/to/project/.visual-kernel/poster-edit",
  "graphPath": "/absolute/path/to/project/.visual-kernel/poster-edit/graph.json"
}
```

### visual.import_image

导入 base image，创建 base asset。

输入：

```json
{
  "projectId": "proj_001",
  "imagePath": "/absolute/path/to/input.png"
}
```

输出：

```json
{
  "assetId": "asset_base",
  "width": 2048,
  "height": 1536,
  "sha256": "hex"
}
```

### visual.analyze_scene

生成实体候选。v0.1 允许返回粗粒度实体，用户或 agent 后续选择目标。

输入：

```json
{
  "projectId": "proj_001",
  "assetId": "asset_base"
}
```

输出：

```json
{
  "entities": [
    {
      "entityId": "ent_cup",
      "label": "cup",
      "kind": "object",
      "bbox": [420, 610, 220, 310],
      "confidence": 0.82
    }
  ]
}
```

### visual.create_transaction

创建编辑事务。

输入：

```json
{
  "projectId": "proj_001",
  "intent": "change the cup to blue",
  "targetEntityIds": ["ent_cup"],
  "lockedEntityIds": ["ent_logo", "ent_title"],
  "writeMaskIds": ["mask_cup_editable"]
}
```

输出：

```json
{
  "transactionId": "txn_001",
  "status": "draft"
}
```

### visual.generate_candidate

调用 model-router 生成候选 patch。

输入：

```json
{
  "projectId": "proj_001",
  "transactionId": "txn_001",
  "modelPreference": "auto"
}
```

输出：

```json
{
  "candidateId": "cand_001",
  "patchPath": "transactions/txn_001/candidates/cand_001/patch.png",
  "previewPath": "transactions/txn_001/candidates/cand_001/preview.png",
  "status": "candidate_generated"
}
```

### visual.verify_candidate

运行事务验证器。

输入：

```json
{
  "projectId": "proj_001",
  "transactionId": "txn_001",
  "candidateId": "cand_001"
}
```

输出：

```json
{
  "status": "verified",
  "passed": true,
  "reports": [
    {
      "type": "outside_write_mask_pixel_diff",
      "passed": true,
      "changedPixels": 0
    }
  ]
}
```

### visual.render_preview

返回 preview 图和验证报告路径。

输入：

```json
{
  "projectId": "proj_001",
  "transactionId": "txn_001",
  "candidateId": "cand_001"
}
```

输出：

```json
{
  "previewPath": "/absolute/path/to/preview.png",
  "diffMapPath": "/absolute/path/to/diff.png",
  "reportPath": "/absolute/path/to/report.json"
}
```

### visual.commit_transaction

只允许提交已验证候选。

输入：

```json
{
  "projectId": "proj_001",
  "transactionId": "txn_001",
  "candidateId": "cand_001"
}
```

输出：

```json
{
  "status": "committed",
  "renderPath": "/absolute/path/to/renders/current.png",
  "historyEntryId": "hist_001"
}
```

### visual.rollback_transaction

放弃未提交事务，或把已提交事务回滚到前一个 render state。

输入：

```json
{
  "projectId": "proj_001",
  "transactionId": "txn_001"
}
```

输出：

```json
{
  "status": "rolled_back",
  "renderPath": "/absolute/path/to/renders/current.png"
}
```

## 存储布局

每个项目存储在用户项目目录下的 `.visual-kernel/<project-name>/`。

```text
.visual-kernel/poster-edit/
  graph.json
  assets/
    asset_base.png
  masks/
    mask_cup_visible.png
    mask_cup_editable.png
  transactions/
    txn_001/
      transaction.json
      candidates/
        cand_001/
          patch.png
          preview.png
          diff.png
          report.json
  renders/
    current.png
    history/
      hist_001.png
```

规则：

- `assets/` 中的原始导入文件不可被覆盖。
- `renders/current.png` 只在 commit 后更新。
- `transactions/` 中的候选文件不可被复用到其他事务。
- 所有文件路径在 graph 中以项目根相对路径保存，MCP 输出使用绝对路径。

## 模型路由

v0.1 的 model-router 使用统一接口：

```json
{
  "baseImagePath": "/absolute/path/to/current.png",
  "targetCropPath": "/absolute/path/to/crop.png",
  "writeMaskPath": "/absolute/path/to/mask.png",
  "instruction": "change the cup to blue",
  "constraints": [
    "preserve background",
    "do not change text",
    "return only the edited patch"
  ]
}
```

输出：

```json
{
  "patchPath": "/absolute/path/to/patch.png",
  "modelId": "adapter-id",
  "metadata": {
    "seed": null,
    "latencyMs": 12000
  }
}
```

第一版只需要一个可用 adapter。后续可以增加：

- OpenAI GPT Image。
- Gemini image editing。
- Qwen-Image-Edit。
- FLUX Kontext。
- 本地 ComfyUI 或 Diffusers 工作流。

## Preview UI

v0.1 preview UI 只承担检查功能，不承担完整编辑器功能。

必需视图：

- base / preview before-after。
- write mask overlay。
- changed-pixel map。
- validator report。
- commit / rollback 状态。

不做：

- 图层面板。
- 完整画笔。
- 复杂 canvas 工具栏。
- 多页面项目管理。

## 验收 Demo

### Demo 1：局部改色

输入：一张包含杯子、背景、logo 或文字的图。

用户指令：

```text
把杯子变蓝，不要动背景、logo 和文字。
```

验收：

- 目标区域发生可见变化。
- write mask 外 `changedPixels` 为 `0`。
- 锁定 logo 或文字区域 `changedPixels` 为 `0`。
- 事务可以 preview、commit、rollback。

### Demo 2：对象删除

输入：一张桌面图，包含手机和旁边杯子。

用户指令：

```text
删除桌上的手机，不要动旁边杯子。
```

验收：

- 手机区域被补全。
- 杯子实体区域通过锁定实体 diff。
- 背景非目标区域不发生变化。
- 如果候选失败，事务停留在 `verification_failed`，不能 commit。

### Demo 3：文字修正

输入：一张含多段文字的海报。

用户指令：

```text
把目标错字改成正确文字，其他文字不要变。
```

验收：

- 目标文字 OCR 变成期望内容。
- 非目标文字 OCR 内容不变。
- 非目标文字区域 pixel diff 为 `0`。
- Preview 能显示 OCR before/after report。

## 里程碑

### Milestone 1：Graph 和存储

实现 `VisualProject` schema、项目目录创建、图片导入、graph 持久化和 current render 初始化。

完成标准：

- 能创建 `.visual-kernel/<name>/graph.json`。
- 能导入图片到 `assets/`。
- 能生成 `renders/current.png`。

### Milestone 2：事务和合成

实现 `EditTransaction`、candidate 文件结构、mask 合成和事务状态迁移。

完成标准：

- 能创建 draft transaction。
- 能用手工 patch + mask 生成 preview。
- preview 不修改 current render。

### Milestone 3：验证器

实现 mask 外 diff、锁定实体 diff 和 canvas property diff。

完成标准：

- mask 外变化会导致 `verification_failed`。
- 已验证 candidate 才能 commit。

### Milestone 4：MCP Server

实现 v0.1 MCP 工具，让 Codex/Claude 能跑完整闭环。

完成标准：

- `visual.create_project` 到 `visual.rollback_transaction` 全部可调用。
- 工具返回稳定 JSON。

### Milestone 5：一个模型 Adapter

接入一个图像编辑模型 adapter，生成真实 candidate patch。

完成标准：

- Demo 1 能产生真实候选图。
- 候选必须经过 compositor 和 validator。

### Milestone 6：Preview UI

实现最小 Web preview。

完成标准：

- 能打开 before/after。
- 能显示 mask overlay、diff map、验证报告。

## 风险与处理

### 模型不遵守 mask

处理：模型输出只作为 patch 候选；合成器强制 mask 外保留原像素；验证器阻止外溢提交。

### 自动实体识别不准

处理：v0.1 支持手工 bbox/mask 输入；自动识别只作为候选，不自动获得写权限。

### OCR 误判

处理：OCR 验证报告只影响文字 demo；文字编辑失败时不 commit。后续可加入多 OCR 引擎投票。

### 色彩管理导致 diff 不稳定

处理：v0.1 全流程使用 PNG 和 sRGB；默认像素级零容忍。未来有损格式和色彩 profile 需要显式放宽阈值。

### 产品范围膨胀

处理：v0.1 只接受服务于可验证编辑闭环的功能。UI、PSD、自动分层和多模型路由都不能阻塞核心闭环。

## 后续方向

v0.1 稳定后再进入三条扩展线：

1. 智能分解：引入 referring layer decomposition、Qwen-Image-Layered、LASAGNA 类模型，把 flat image 转成更可靠的实体图。
2. 专业导出：把 Visual State Graph 投影为 PSD、OpenRaster、SVG/HTML 或 tldraw canvas。
3. Agent 协作：让 Codex/Claude 能以多步事务方式规划、验证和回滚复杂视觉修改。

## 设计结论

Visual Kernel 的第一性原理是：AI 不直接编辑图片，AI 编辑一个受约束的视觉状态图。

图像模型负责生成候选内容；Visual Kernel 负责可寻址性、写权限、确定性合成、验证、预览、提交和回滚。

只要这个闭环成立，它就不是 Photoshop 的 AI 外壳，而是一个面向 AI agent 的新视觉编辑底座。
