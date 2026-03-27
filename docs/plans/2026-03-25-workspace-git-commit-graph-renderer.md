# Workspace Git Commit Graph Renderer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将 Workspace Git 标准 IDEA Log 的提交图谱从字符假图谱升级为真正连续的矢量 graph renderer，解决线条分段、宽度裁切与复杂分支显示不完整的问题。

**Architecture:** 在 Core 层新增可测试的 graph row layout 构建器，把 `git log --graph` 的 `graphPrefix` 转成结构化绘制指令；在 App 层新增独立的 SwiftUI `Canvas` graph view，并让 `WorkspaceGitIdeaLogTableView` 改用结构化 row model + 动态 graph 宽度渲染，而不是继续 `Text(graphPrefix)`。

**Tech Stack:** Swift 6、SwiftUI、Canvas、Observation、XCTest。

---

### Task 1: 登记任务与红灯契约

**Files:**
- Modify: `tasks/todo.md`
- Create: `macos/Tests/DevHavenCoreTests/WorkspaceGitCommitGraphLayoutTests.swift`
- Modify: `macos/Tests/DevHavenAppTests/WorkspaceGitIdeaLogViewTests.swift`

**Step 1: 写 Core 红灯测试**
- 约束线性历史下 `*` 节点会生成上下连续的纵向连线。
- 约束 `| *`、`|/`、`|\` 这类分支/合并前缀能生成多 lane 布局。
- 约束 graph 宽度根据可见 graphPrefix 动态增长，而不是固定 28pt。

**Step 2: 跑红灯**
Run: `swift test --package-path macos --filter 'WorkspaceGitCommitGraphLayoutTests|WorkspaceGitIdeaLogViewTests'`
Expected: FAIL，提示缺少 graph layout / Canvas renderer / 动态 graph 宽度契约。

### Task 2: 实现 Core graph layout

**Files:**
- Create: `macos/Sources/DevHavenCore/Models/WorkspaceGitCommitGraphModels.swift`
- Modify: `macos/Sources/DevHavenCore/Models/WorkspaceGitLogTableModels.swift`
- Modify: `macos/Sources/DevHavenCore/ViewModels/WorkspaceGitLogViewModel.swift`

**Step 1: 新增 graph 结构化模型**
- 定义 row layout、segment、node、宽度计算模型。
- 让 row layout 能基于 `previous/current/next graphPrefix` 产出连续绘制指令。

**Step 2: 接入 table rows**
- 让 `WorkspaceGitLogViewModel` 暴露 table rows / graph width，避免 View 内临时拼装图谱逻辑。

**Step 3: 跑定向测试**
Run: `swift test --package-path macos --filter 'WorkspaceGitCommitGraphLayoutTests|WorkspaceGitLogViewModelTests'`
Expected: PASS

### Task 3: 实现 App Canvas renderer 并替换旧假图谱

**Files:**
- Create: `macos/Sources/DevHavenApp/WorkspaceGitCommitGraphView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitIdeaLogTableView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitIdeaLogView.swift` (如需表格密度或 split 配合微调)

**Step 1: 写最小 renderer**
- 用 `Canvas` 绘制 vertical / slash / backslash / horizontal / node。
- 节点与连线分层绘制，避免被 badge / padding 破坏。

**Step 2: 替换 `Text(graphPrefix)`**
- `subjectCell` 改为 graph view + subject/badges。
- 图谱区域宽度改由结构化 layout 动态决定，不再写死 `frame(width: 28)`。

**Step 3: 跑 App 定向测试**
Run: `swift test --package-path macos --filter 'WorkspaceGitIdeaLogViewTests|WorkspaceGitRootViewTests|WorkspaceShellViewGitModeTests'`
Expected: PASS

### Task 4: 文档同步与全量验证

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`

**Step 1: 更新架构文档**
- 记录新的 `WorkspaceGitCommitGraphView.swift` 与 Core graph model 职责。

**Step 2: 运行验证**
Run:
- `swift test --package-path macos --filter 'WorkspaceGitCommitGraphLayoutTests|WorkspaceGitLogViewModelTests|WorkspaceGitIdeaLogViewTests|WorkspaceGitRootViewTests|WorkspaceShellViewGitModeTests'`
- `swift test --package-path macos`
- `git diff --check`

Expected:
- 定向与全量测试通过
- diff 检查通过

**Step 3: 回填 Review**
- 在 `tasks/todo.md` 追加直接原因 / 设计诱因 / 当前方案 / 长期建议 / 证据。
