# Hide Worktree Count Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 删除工作区侧栏项目卡片右侧的 worktree 数量徽标，同时保留下方的 worktree 列表和交互。

**Architecture:** 本次改动只触及 `WorkspaceProjectListView` 的根项目卡片视图，不调整 `WorkspaceSidebarProjectGroup`、`Project` 或 worktree 数据流。由于数量徽标位于私有 SwiftUI 视图内部，回归测试直接锁定 `WorkspaceProjectListView.swift` 不再使用 `group.worktrees.count` 渲染徽标，并同时确认 `ForEach(group.worktrees)` 列表逻辑仍在。

**Tech Stack:** SwiftUI、XCTest、Swift Package Manager

---

### Task 1: 记录任务与设计文档

**Files:**
- Modify: `tasks/todo.md`
- Create: `docs/plans/2026-03-21-hide-worktree-count-design.md`
- Create: `docs/plans/2026-03-21-hide-worktree-count.md`

**Step 1: 写入任务 checklist**
- 在 `tasks/todo.md` 新增本次任务条目。

**Step 2: 记录最小设计**
- 写入删除徽标的范围、约束和推荐方案。

**Step 3: 保存实施计划**
- 明确待修改文件、测试方式和验证命令。

### Task 2: 先写失败测试

**Files:**
- Create: `macos/Tests/DevHavenAppTests/WorkspaceProjectListViewTests.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceProjectListView.swift`（后续实现）

**Step 1: 写最小失败测试**
- 直接读取 `WorkspaceProjectListView.swift` 源码。
- 断言 `ForEach(group.worktrees)` 仍存在，避免误删 worktree 列表。
- 断言不应再出现 `group.worktrees.count` 这一数量徽标渲染逻辑。

**Step 2: 运行测试确认失败**
Run: `swift test --package-path macos --filter WorkspaceProjectListViewTests/testProjectCardDoesNotRenderWorktreeCountBadge`
Expected: FAIL，因为当前实现仍会显示 `group.worktrees.count`。

### Task 3: 以最小改动删除数量徽标

**Files:**
- Modify: `macos/Sources/DevHavenApp/WorkspaceProjectListView.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceProjectListViewTests.swift`

**Step 1: 删除徽标视图**
- 从 `ProjectGroupView.projectCard` 中移除 `if !group.worktrees.isEmpty { Text("\\(group.worktrees.count)") ... }` 整段。

**Step 2: 保持其余交互不变**
- 不改 hover 按钮、卡片样式、worktree 列表渲染。

**Step 3: 跑定向测试确认通过**
Run: `swift test --package-path macos --filter WorkspaceProjectListViewTests/testProjectCardDoesNotRenderWorktreeCountBadge`
Expected: PASS。

### Task 4: 做收尾验证并更新 Review

**Files:**
- Modify: `tasks/todo.md`

**Step 1: 跑差异校验**
Run: `git diff --check`
Expected: 无格式错误。

**Step 2: 回填 Review**
- 记录直接原因、设计层判断、当前修复和验证证据。
