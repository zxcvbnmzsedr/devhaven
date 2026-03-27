# Workspace Git / Terminal 一体化与通用 Bottom Tool Window Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将 Workspace 从 Terminal/Git 一级模式切换重构为“terminal 主区 + 通用 bottom tool window 宿主”，并以 Git 作为首个接入的 bottom tool window。

**Architecture:** 废弃 `WorkspacePrimaryMode` 主模式抽象，在 Core 层建立 `WorkspaceToolWindowKind / Placement / State / FocusedArea` 运行时模型，在 App 层将 `WorkspaceShellView` 改造成 terminal 主区 + bottom tool window host + bottom bar 的垂直布局。Git 继续复用 `WorkspaceGitViewModel` / `WorkspaceGitRootView` 作为业务内容，不把“面板是否展开”塞回 Git ViewModel。

**Tech Stack:** Swift 6、SwiftUI、Observation、XCTest。

---

### Task 1: 用红灯测试锁定新模型与旧模式退场

**Files:**
- Modify: `tasks/todo.md`
- Modify: `macos/Tests/DevHavenCoreTests/WorkspaceGitViewModelTests.swift`
- Modify: `macos/Tests/DevHavenAppTests/WorkspaceShellViewGitModeTests.swift`
- Modify: `macos/Tests/DevHavenAppTests/WorkspaceChromeContainerViewTests.swift`

**Step 1: 写失败测试**

- 为 `NativeAppViewModel` 新增或调整 source / behavior 测试，约束：
  - 不再依赖 `workspacePrimaryMode`
  - 存在新的 tool window runtime state / toggle 入口
- 为 `WorkspaceShellView` 测试改写断言，约束：
  - 不再 `switch viewModel.workspacePrimaryMode`
  - terminal 主区始终存在
  - Git 通过 bottom tool window host 路由
- 为 `WorkspaceChromeContainerView` 测试改写断言，约束：
  - 移除 left rail mode switcher
  - 不再引用 `WorkspaceModeSwitcherView`

**Step 2: 跑红灯**

Run: `swift test --package-path macos --filter 'WorkspaceGitViewModelTests|WorkspaceShellViewGitModeTests|WorkspaceChromeContainerViewTests'`

Expected: FAIL，提示仍然依赖 `workspacePrimaryMode`、视图仍是主模式切换、chrome 仍保留旧 rail。

### Task 2: 引入通用 Tool Window 模型与 ViewModel 接线

**Files:**
- Modify: `macos/Sources/DevHavenCore/Models/WorkspaceGitModels.swift`
- Modify: `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`
- Test: `macos/Tests/DevHavenCoreTests/WorkspaceGitViewModelTests.swift`

**Step 1: 加入最小通用模型**

- 新增 `WorkspaceToolWindowKind`
- 新增 `WorkspaceToolWindowPlacement`
- 新增 `WorkspaceToolWindowState`
- 新增 `WorkspaceFocusedArea`

**Step 2: 在 `NativeAppViewModel` 建立宿主状态**

- 删除 `workspacePrimaryMode`
- 增加 tool window runtime state 与最小操作入口：
  - `toggleWorkspaceToolWindow(_:)`
  - `showWorkspaceToolWindow(_:)`
  - `hideWorkspaceToolWindow()`
  - 高度更新 / focused area 更新
- 让 `prepareActiveWorkspaceGitViewModel()` 不再依赖“当前是 Git 模式”才准备

**Step 3: 跑定向测试**

Run: `swift test --package-path macos --filter WorkspaceGitViewModelTests`

Expected: PASS

### Task 3: 改造 Workspace 布局为 terminal 主区 + bottom tool window host

**Files:**
- Modify: `macos/Sources/DevHavenApp/WorkspaceShellView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceChromeContainerView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceModeSwitcherView.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceShellViewGitModeTests.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceChromeContainerViewTests.swift`

**Step 1: 重写 `WorkspaceShellView` 主布局**

- 移除 terminal/git 主模式二选一逻辑
- 让 terminal 主区永远存在
- 新增 bottom tool window host 与 bottom bar
- 把 Git 内容路由为 tool window content，而不是主区内容

**Step 2: 精简 `WorkspaceChromeContainerView`**

- 移除 left rail 与 `WorkspaceModeSwitcherView`
- 保持外层 chrome 容器与 central content 包裹职责

**Step 3: 处理旧 mode switcher**

- 若 `WorkspaceModeSwitcherView` 已无使用方，删除文件或将其退役为非导出实现；实现时按最小改动选择其一，但不得保留旧主链引用

**Step 4: 跑定向测试**

Run: `swift test --package-path macos --filter 'WorkspaceShellViewGitModeTests|WorkspaceChromeContainerViewTests|WorkspaceRootViewTests|WorkspaceShellViewTests'`

Expected: PASS

### Task 4: 接入 Git tool window 内容、空态、焦点守门

**Files:**
- Modify: `macos/Sources/DevHavenApp/WorkspaceShellView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitRootView.swift`
- Modify: `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceShellViewGitModeTests.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceTerminalCommandsTests.swift`

**Step 1: Git 内容接入 bottom host**

- 当 active tool window 为 `.git` 时，在 bottom host 中挂载 `WorkspaceGitRootView`
- 若 active project 非 Git 仓库或是 Quick Terminal，保留并复用明确空态文案

**Step 2: 收口 focused area**

- terminal 搜索类 `FocusedValue` / action 仅在 focused area 为 terminal 时暴露
- 当 tool window 交互激活时，focused area 更新为 `.toolWindow(.git)`

**Step 3: 跑定向测试**

Run: `swift test --package-path macos --filter 'WorkspaceShellViewGitModeTests|WorkspaceTerminalCommandsTests|WorkspaceGitRootViewTests'`

Expected: PASS

### Task 5: 架构文档同步与完整验证

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`

**Step 1: 更新架构文档**

- 把 Workspace 描述从“Terminal/Git 一级模式切换”更新为“terminal 主区 + 通用 bottom tool window”
- 说明 Git 是首个 tool window 接入者，不再是 primary mode
- 说明 focused area 与命令路由边界

**Step 2: 跑完整验证**

Run: `swift test --package-path macos --filter 'WorkspaceGitViewModelTests|WorkspaceShellViewGitModeTests|WorkspaceChromeContainerViewTests|WorkspaceRootViewTests|WorkspaceShellViewTests|WorkspaceTerminalCommandsTests|WorkspaceGitRootViewTests|WorkspaceGitLogViewModelTests'`

Expected: PASS

**Step 3: 跑质量检查**

Run: `git diff --check`

Expected: exit 0

**Step 4: 回填 Review**

- 在 `tasks/todo.md` 记录：
  - 直接原因
  - 是否存在设计层诱因
  - 当前修复方案
  - 长期改进建议
  - 验证证据
