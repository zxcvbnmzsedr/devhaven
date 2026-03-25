# IDEA Git 布局验收纠偏（二轮） Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 修正上一轮验收中暴露的两处结构偏差：把左上角 `Git` 改为不可点击标题，并把右侧 `Changes` 改成树形 changes browser + toolbar 入口布局。

**Architecture:** 保持现有 `WorkspaceGitLogViewModel` 与 Git 数据主链不变，只在 App 层重排 Git 工具窗顶部标题/次级入口关系，以及 `WorkspaceGitIdeaLogChangesView` 的容器结构。Changes tree 先用目录树 + 文件节点方案承接结构心智，toolbar 小操作先摆对位置和入口。

**Tech Stack:** SwiftUI、source-based XCTest、现有 DevHavenCore Git Log 状态层。

---

### Task 1: 锁定 Git 标题与 Changes tree 红灯

**Files:**
- Modify: `macos/Tests/DevHavenAppTests/WorkspaceGitRootViewTests.swift`
- Modify: `macos/Tests/DevHavenAppTests/WorkspaceGitIdeaLogViewTests.swift`

**Step 1: 写失败测试**

新增断言：
- `WorkspaceGitRootView` 不应继续使用 `topTabButton(.git)`；
- 必须存在 `gitToolWindowTitle` 一类不可点击标题 helper；
- `WorkspaceGitIdeaLogChangesView` 必须有 changes toolbar；
- `WorkspaceGitIdeaLogChangesView` 不应继续使用 `List(detail.files)` 扁平列表。

**Step 2: 跑测试确认红灯**

Run: `swift test --package-path macos --filter 'WorkspaceGitRootViewTests|WorkspaceGitIdeaLogViewTests'`
Expected: FAIL，提示 Git 仍是按钮、Changes 仍是扁平列表。

### Task 2: 修正 Git 工具窗顶部层级

**Files:**
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitRootView.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceGitRootViewTests.swift`

**Step 1: 把 Git 从按钮改成标题**

引入 `gitToolWindowTitle`，替换 `topTabButton(.git)`。

**Step 2: 保留 Log / Console 次级入口**

仅渲染 `Log` / `Console` 两个入口，并为返回 Git 主内容提供最小切换逻辑。

**Step 3: 跑定向测试**

Run: `swift test --package-path macos --filter WorkspaceGitRootViewTests`
Expected: PASS

### Task 3: 把 Changes 升级为 tree changes browser

**Files:**
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitIdeaLogChangesView.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceGitIdeaLogViewTests.swift`

**Step 1: 先加 changes toolbar**

用最小 icon-only toolbar 对齐一排小操作入口布局。

**Step 2: 引入目录树节点模型**

按文件路径构建目录树，替换 `List(detail.files)`。

**Step 3: 让文件节点继续复用现有文件展示 helper**

保留 `primaryFileName / secondaryPathSubtitle / icon / color` 等 helper，不重写文件文案语义。

**Step 4: 跑定向测试**

Run: `swift test --package-path macos --filter WorkspaceGitIdeaLogViewTests`
Expected: PASS

### Task 4: 扩大验证与文档同步

**Files:**
- Modify: `AGENTS.md`（若职责边界发生变化）
- Modify: `tasks/todo.md`

**Step 1: 跑扩大验证**

Run: `swift test --package-path macos --filter 'WorkspaceGitRootViewTests|WorkspaceGitIdeaLogViewTests|WorkspaceGitLogViewModelTests|WorkspaceShellViewGitModeTests|WorkspaceRootViewTests|WorkspaceChromeContainerViewTests'`
Expected: PASS

**Step 2: 质量检查**

Run: `git diff --check`
Expected: exit 0

**Step 3: 回填任务记录**

把红灯、绿灯、直接原因、设计诱因、长期建议写回 `tasks/todo.md`。
