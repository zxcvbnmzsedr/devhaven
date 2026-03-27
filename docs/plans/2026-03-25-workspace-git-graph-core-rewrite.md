# Workspace Git Graph Core Rewrite Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 废弃当前基于 `graphPrefix` 行级字符串反推的 commit graph 实现，改为 JetBrains `PermanentGraph / VisibleGraph / PrintElement` 风格的结构化 graph core，正确支持 merge 迁入、迁出、lane 复用与连续渲染。

**Architecture:** Core 层新增独立的 graph core：先把 commit 列表建成 permanent DAG，再基于当前可见提交集生成 visible rows 和 print elements，最后由 App 层纯消费 print elements 做 SwiftUI/Canvas 渲染。现有 `WorkspaceGitCommitGraphModels` 与 `WorkspaceGitCommitGraphView` 只保留为临时过渡实现，最终以新的 graph core 输出替代。

**Tech Stack:** Swift 6、SwiftUI、Canvas、Observation、XCTest。

---

### Task 1: 建立新的 graph core 设计映射

**Files:**
- Reference: `/Users/zhaotianzeng/Documents/business/tianzeng/intellij-community/platform/vcs-log/graph-api/src/com/intellij/vcs/log/graph/PermanentGraph.kt`
- Reference: `/Users/zhaotianzeng/Documents/business/tianzeng/intellij-community/platform/vcs-log/graph-api/src/com/intellij/vcs/log/graph/VisibleGraph.kt`
- Reference: `/Users/zhaotianzeng/Documents/business/tianzeng/intellij-community/platform/vcs-log/graph-api/src/com/intellij/vcs/log/graph/PrintElement.kt`
- Reference: `/Users/zhaotianzeng/Documents/business/tianzeng/intellij-community/platform/vcs-log/graph/src/com/intellij/vcs/log/graph/impl/permanent/GraphLayoutBuilder.kt`
- Reference: `/Users/zhaotianzeng/Documents/business/tianzeng/intellij-community/platform/vcs-log/graph/src/com/intellij/vcs/log/graph/impl/print/PrintElementGeneratorImpl.kt`
- Modify: `tasks/todo.md`

**Step 1: 明确本地映射模型**
- `PermanentGraph` -> `WorkspaceGitCommitGraphPermanentModel`
- `VisibleGraph` -> `WorkspaceGitCommitGraphVisibleModel`
- `PrintElement` -> `WorkspaceGitCommitGraphPrintElement`
- `recommendedWidth` -> `preferredGraphWidth`

**Step 2: 记录 checklist**
Run: `sed -n '1,80p' tasks/todo.md`
Expected: 新任务 checklist 已落盘。

### Task 2: 先补 graph core 红灯测试

**Files:**
- Create: `macos/Tests/DevHavenCoreTests/WorkspaceGitCommitGraphCoreTests.swift`
- Modify: `macos/Tests/DevHavenAppTests/WorkspaceGitIdeaLogViewTests.swift`

**Step 1: 写最小失败测试**
- 约束 merge 迁入时同一 row 可同时存在 node 与多条 edge print elements。
- 约束 merge 迁出时 lane 不会被上一行字符串解析误判。
- 约束 visible rows 能给出 `recommendedWidth`，且比当前简单 lane 数推导更稳定。

**Step 2: 跑红灯**
Run: `swift test --package-path macos --filter 'WorkspaceGitCommitGraphCoreTests|WorkspaceGitIdeaLogViewTests'`
Expected: FAIL，提示缺少新的 graph core / print element 输出主链。

### Task 3: 实现 Core graph core

**Files:**
- Create: `macos/Sources/DevHavenCore/Models/WorkspaceGitCommitGraphCoreModels.swift`
- Create: `macos/Sources/DevHavenCore/Models/WorkspaceGitCommitGraphCoreBuilder.swift`
- Modify: `macos/Sources/DevHavenCore/Models/WorkspaceGitLogTableModels.swift`
- Modify: `macos/Sources/DevHavenCore/ViewModels/WorkspaceGitLogViewModel.swift`

**Step 1: 定义 permanent / visible / print element 模型**
- 明确 node、edge、lane、row、print element 类型。
- 不再让 `graphPrefix` 参与最终绘制决策，只允许它作为过渡期验证对照或回退输入。

**Step 2: 实现 graph builder**
- 基于 `hash + parentHashes + visible order` 构建 lane 布局。
- 输出每行 node/edge print elements 与 recommended width。

**Step 3: 接入 ViewModel**
- `WorkspaceGitLogViewModel` 暴露新的 rows/printElements/width。
- 旧 `WorkspaceGitCommitGraphTableLayout` 退出主链。

**Step 4: 跑定向测试**
Run: `swift test --package-path macos --filter 'WorkspaceGitCommitGraphCoreTests|WorkspaceGitLogViewModelTests'`
Expected: PASS

### Task 4: 替换 App 渲染主链

**Files:**
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitCommitGraphView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitIdeaLogTableView.swift`

**Step 1: graph view 改消费 print elements**
- 只画结构化 node/edge，不再读旧 glyph 模型。
- 支持 merge 迁入/迁出的同 row 多 edge 输出。

**Step 2: table 改消费新 core 输出**
- 行宽、graph 区宽度、行高均由 graph core + renderer metrics 控制。

**Step 3: 跑 UI 定向验证**
Run: `swift test --package-path macos --filter 'WorkspaceGitIdeaLogViewTests|WorkspaceGitRootViewTests|WorkspaceShellViewGitModeTests'`
Expected: PASS

### Task 5: 文档同步与全量验证

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`
- Modify: `tasks/lessons.md`

**Step 1: 更新架构说明**
- 记录旧思路为何废弃。
- 记录新的 graph core 边界与 renderer 边界。

**Step 2: 运行验证**
Run:
- `swift test --package-path macos --filter 'WorkspaceGitCommitGraphCoreTests|WorkspaceGitLogViewModelTests|WorkspaceGitIdeaLogViewTests|WorkspaceGitRootViewTests|WorkspaceShellViewGitModeTests'`
- `swift test --package-path macos`
- `git diff --check`

Expected:
- 定向 / 全量通过
- diff 检查通过

**Step 3: 回填 Review**
- 记录直接原因、设计诱因、当前方案、长期建议与证据。
