# IDEA Git Changes tree 展开/折叠控制 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 IDEA 风格的 Changes tree browser 增加 toolbar 级“全部展开 / 全部折叠”控制。

**Architecture:** 保持现有 `ChangeTreeNode / ChangeTreeBuilder` 负责树数据建模，但把视图层从不可程序化控制的 `OutlineGroup` 切换到显式递归 `DisclosureGroup`，并引入 App-only 的 `expandedDirectoryIDs` 作为当前 changes browser 的展开状态真相源。

**Tech Stack:** SwiftUI、source-based XCTest、现有 DevHavenCore Git Log 详情主链。

---

### Task 1: 写红灯测试锁定展开/折叠控制契约

**Files:**
- Modify: `macos/Tests/DevHavenAppTests/WorkspaceGitIdeaLogViewTests.swift`

**Step 1: 写失败测试**

新增断言：
- 存在 `expandedDirectoryIDs`
- 存在 `expandAllDirectories` / `collapseAllDirectories`
- toolbar 包含展开全部 / 折叠全部入口
- 目录节点不再只依赖 `OutlineGroup`

**Step 2: 跑测试确认红灯**

Run: `swift test --package-path macos --filter WorkspaceGitIdeaLogViewTests`
Expected: FAIL，提示缺少展开状态与全局控制 helper。

### Task 2: 实现可控 tree 展开状态

**Files:**
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitIdeaLogChangesView.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceGitIdeaLogViewTests.swift`

**Step 1: 新增展开状态**

加入 `expandedDirectoryIDs`。

**Step 2: 实现 expand/collapse helper**

增加：
- `expandAllDirectories(...)`
- `collapseAllDirectories()`
- `allDirectoryIDs(...)`

**Step 3: 替换树渲染**

用递归 `DisclosureGroup` 渲染目录节点，文件节点继续走现有 `fileRow`。

**Step 4: 默认展开当前提交的目录树**

在 detail 变化时同步默认展开目录。

**Step 5: 跑定向测试**

Run: `swift test --package-path macos --filter WorkspaceGitIdeaLogViewTests`
Expected: PASS

### Task 3: 扩大验证与记录

**Files:**
- Modify: `tasks/todo.md`
- Modify: `AGENTS.md`（若职责描述需要补充）

**Step 1: 跑扩大验证**

Run: `swift test --package-path macos --filter 'WorkspaceGitRootViewTests|WorkspaceGitIdeaLogViewTests|WorkspaceGitLogViewModelTests|WorkspaceShellViewGitModeTests|WorkspaceRootViewTests|WorkspaceChromeContainerViewTests'`
Expected: PASS

**Step 2: 质量检查**

Run: `git diff --check`
Expected: exit 0

**Step 3: 回填任务记录**

把直接原因、设计诱因、验证结果写回 `tasks/todo.md`。
