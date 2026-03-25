# Git Log 行高与线条连贯度调整 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 消除标准 IDEA Log 中 commit graph 与选中行上下留缝的问题，让竖线在相邻行之间看起来更连贯。

**Architecture:** 不改 graph core，只在 App 层收口高度真相源：把 `WorkspaceGitCommitGraphView.rowHeight` 调整到更接近 table 可见行盒的值，并让 `WorkspaceGitIdeaLogTableView.subjectCell` 以固定 `height` 复用这一真相源。同时小幅微调 graph renderer 的视觉 metrics，避免新高度下线条显得漂浮。

**Tech Stack:** Swift 6、SwiftUI、Canvas、XCTest。

---

### Task 1: 补红灯测试锁定高度契约

**Files:**
- Modify: `tasks/todo.md`
- Modify: `macos/Tests/DevHavenAppTests/WorkspaceGitIdeaLogViewTests.swift`

**Step 1: 写失败测试**
- 新增测试约束 `WorkspaceGitCommitGraphView.rowHeight` 使用新的目标高度。
- 新增测试约束 `WorkspaceGitIdeaLogTableView.subjectCell` 使用固定 `height`，不再继续使用 `minHeight`。

**Step 2: 跑红灯**

Run: `swift test --package-path macos --filter WorkspaceGitIdeaLogViewTests`

Expected: FAIL，提示 rowHeight 仍是旧值，且 table 仍在使用 `minHeight`。

### Task 2: 实现最小高度对齐修复

**Files:**
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitCommitGraphView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitIdeaLogTableView.swift`

**Step 1: 调整 graph rowHeight**
- 把 `WorkspaceGitCommitGraphView.rowHeight` 提升到新的目标值。
- 必要时同步微调 `verticalOverflow`、`strokeWidth`、`nodeRadius`，保持线条观感连贯。

**Step 2: 收口 subject cell 高度**
- graph 容器与 subject cell 统一复用 `WorkspaceGitCommitGraphView.rowHeight`。
- `subjectCell` 的内容 frame 改为固定 `height`，不再依赖 `minHeight`。

**Step 3: 跑红绿测试**

Run: `swift test --package-path macos --filter WorkspaceGitIdeaLogViewTests`

Expected: PASS

### Task 3: 定向验证与回填 Review

**Files:**
- Modify: `tasks/todo.md`

**Step 1: 跑定向验证**

Run: `swift test --package-path macos --filter 'WorkspaceGitIdeaLogViewTests|WorkspaceGitRootViewTests|WorkspaceShellViewGitModeTests|WorkspaceGitLogViewModelTests'`

Expected: PASS

**Step 2: 跑质量检查**

Run: `git diff --check`

Expected: exit 0

**Step 3: 回填 Review**
- 记录直接原因、设计层诱因、当前方案、长期建议与验证证据。
