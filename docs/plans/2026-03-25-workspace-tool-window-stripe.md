# Workspace Tool Window Stripe Placement Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 把 Git 工具窗入口从 `WorkspaceShellView` 底部按钮栏迁移到 `WorkspaceChromeContainerView` 左侧 stripe，并保持底部工具窗内容逻辑不变。

**Architecture:** 保持 `WorkspaceRootView` 的“项目导航 | Workspace chrome” split 结构不变，只把右侧 `WorkspaceChromeContainerView` 扩展为 `stripe + 主内容区` 双列布局。`WorkspaceShellView` 删除底部按钮栏，只保留 terminal 主区与 bottom tool window host；stripe 上的 Git icon 按钮继续调用现有 `toggleWorkspaceToolWindow(.git)`。

**Tech Stack:** Swift 6、SwiftUI、Observation、XCTest。

---

### Task 1: 先写红灯测试锁定 stripe 正确层级

**Files:**
- Modify: `tasks/todo.md`
- Modify: `macos/Tests/DevHavenAppTests/WorkspaceChromeContainerViewTests.swift`
- Modify: `macos/Tests/DevHavenAppTests/WorkspaceShellViewGitModeTests.swift`
- Modify: `macos/Tests/DevHavenAppTests/WorkspaceRootViewTests.swift`

**Step 1: 写失败测试**

- `WorkspaceChromeContainerViewTests`
  - 断言 chrome 容器不再只包 `content()`
  - 断言存在左侧 stripe / stripe button
  - 断言仍不承载 `WorkspaceModeSwitcherView`
- `WorkspaceShellViewGitModeTests`
  - 断言移除 `bottomToolWindowBar`
  - 断言 shell 仍保留 `terminalModeContent` 与 `bottomToolWindowHost`
- `WorkspaceRootViewTests`
  - 断言 root 仍只是“项目导航 | 右侧 chrome”
  - 不把 stripe 提升到 root 最外层

**Step 2: 跑红灯**

Run: `swift test --package-path macos --filter 'WorkspaceChromeContainerViewTests|WorkspaceShellViewGitModeTests|WorkspaceRootViewTests'`

Expected: FAIL，提示当前 stripe 还没出现在 chrome 容器内，且 shell 仍保留底部按钮栏。

### Task 2: 最小改动迁移 Git 入口到 chrome stripe

**Files:**
- Modify: `macos/Sources/DevHavenApp/WorkspaceChromeContainerView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceShellView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceRootView.swift`

**Step 1: 在 `WorkspaceChromeContainerView` 内加入 stripe**

- 新增左侧竖向 stripe 容器
- stripe 内只放 Git icon-only 按钮
- Git 按钮继续调用 `viewModel.toggleWorkspaceToolWindow(.git)`

**Step 2: 从 `WorkspaceShellView` 删除底部按钮栏**

- 删除 `bottomToolWindowBar`
- 保留 `terminalModeContent`
- 保留 `bottomToolWindowHost`

**Step 3: 确认 `WorkspaceRootView` 层级不被错误上提**

- 继续保持 root 只负责项目导航与右侧 chrome split
- 不把 stripe 变成最外层导航

**Step 4: 跑定向测试**

Run: `swift test --package-path macos --filter 'WorkspaceChromeContainerViewTests|WorkspaceShellViewGitModeTests|WorkspaceRootViewTests|WorkspaceShellViewTests|WorkspaceTerminalCommandsTests'`

Expected: PASS

### Task 3: 文档同步与最终验证

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`

**Step 1: 更新 AGENTS**

- 把 stripe 的正确层级更新为：
  - `[项目导航] | [左侧 stripe | 主内容区]`
- 删除或修正任何把 stripe 说成“整个窗口最外缘”的描述
- 明确 `WorkspaceShellView` 不再负责入口按钮

**Step 2: 跑完整验证**

Run: `swift test --package-path macos --filter 'WorkspaceGitViewModelTests|WorkspaceShellViewGitModeTests|WorkspaceChromeContainerViewTests|WorkspaceRootViewTests|WorkspaceShellViewTests|WorkspaceTerminalCommandsTests|WorkspaceGitRootViewTests|WorkspaceGitLogViewModelTests'`

Expected: PASS

**Step 3: 跑质量检查**

Run: `git diff --check`

Expected: exit 0

**Step 4: 回填 Review**

- 记录：
  - 直接原因
  - 设计层诱因
  - 当前修复方案
  - 长期建议
  - 验证证据
