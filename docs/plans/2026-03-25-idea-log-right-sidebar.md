# IDEA Log 右侧信息栏回归与错误底部面板删除 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 把 `.log` 从错误的底部 changes/details/diff preview 布局，改回更接近 IDEA 截图的 `左 branches | 中 log table | 右信息栏` 结构。

**Architecture:** 保留现有左侧 branches panel 与中间 `WorkspaceGitIdeaLogTableView`。新增 `WorkspaceGitIdeaLogRightSidebarView` 承接右侧信息栏，内部以纵向 split 承接 `changes tree + commit details`；同时把 `WorkspaceGitIdeaLogBottomPaneView` 和 `WorkspaceGitIdeaLogDiffPreviewView` 从 `.log` 主链移除，toolbar 不再承担 details/diff preview 显隐切换。

**Tech Stack:** SwiftUI、Observation、Swift Package、XCTest（源码契约测试）

---

### Task 1: 补红灯测试，锁定 `.log` 右侧信息栏结构

**Files:**
- Modify: `macos/Tests/DevHavenAppTests/WorkspaceGitIdeaLogViewTests.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceGitIdeaLogViewTests.swift`

**Step 1: 写失败测试**

新增 / 修改断言：
- `WorkspaceGitIdeaLogView.swift` 必须包含右侧 `WorkspaceGitIdeaLogRightSidebarView`
- `.log` 主链不应再挂 `WorkspaceGitIdeaLogBottomPaneView` 与 `WorkspaceGitIdeaLogDiffPreviewView`
- toolbar 不应继续保留 `toggleDetails` / `toggleDiffPreview`
- 右侧 sidebar 内必须同时承接 `WorkspaceGitIdeaLogChangesView` 与 `WorkspaceGitIdeaLogDetailsView`

**Step 2: 运行测试确认红灯**

Run:
```bash
swift test --package-path macos --filter WorkspaceGitIdeaLogViewTests
```

Expected:
- FAIL，且失败原因直接指向错误的底部 pane 结构尚未移除

### Task 2: 重构 `.log` 主容器与 toolbar

**Files:**
- Create: `macos/Sources/DevHavenApp/WorkspaceGitIdeaLogRightSidebarView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitIdeaLogView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitIdeaLogToolbarView.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceGitIdeaLogViewTests.swift`

**Step 1: 为 `.log` 新增右侧 sidebar 容器**

新增 `WorkspaceGitIdeaLogRightSidebarView.swift`，内部使用纵向 split 承接：
- `WorkspaceGitIdeaLogChangesView`
- `WorkspaceGitIdeaLogDetailsView`

**Step 2: 修改 `WorkspaceGitIdeaLogView.swift`**

把 `.log` 主结构从：
- table + bottom pane/diff preview

改成：
- table + right sidebar

**Step 3: 修改 `WorkspaceGitIdeaLogToolbarView.swift`**

删除：
- details toggle
- diff preview toggle

仅保留过滤与刷新入口。

**Step 4: 运行测试确认转绿**

Run:
```bash
swift test --package-path macos --filter WorkspaceGitIdeaLogViewTests
```

Expected:
- PASS

### Task 3: 同步文档与定向验证

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`
- Modify: `docs/plans/2026-03-25-idea-log-right-sidebar-design.md`
- Modify: `docs/plans/2026-03-25-idea-log-right-sidebar.md`

**Step 1: 更新 AGENTS.md**

补充 `.log` 右侧 sidebar 职责，并明确底部 changes/details/diff preview 已不在 `.log` 主链。

**Step 2: 更新 tasks/todo.md**

勾选任务并追加 Review。

**Step 3: 运行定向验证**

Run:
```bash
swift test --package-path macos --filter 'WorkspaceGitIdeaLogViewTests|WorkspaceGitRootViewTests|WorkspaceGitLogViewModelTests'
```

Expected:
- PASS

**Step 4: 运行质量检查**

Run:
```bash
git diff --check
```

Expected:
- exit 0
