# Workspace Run Console Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 workspace 顶部新增轻量 Run/Stop/Logs 控制区，并在底部提供支持多 session 切换的 Run Console，命令来源直接复用 `Project.scripts`。

**Architecture:** 运行命令不复用 Ghostty pane，而是在 Core 层新增 `WorkspaceRunManager` 用 `Process + Pipe` 启动 shell command、收集日志、维护 session 生命周期；`NativeAppViewModel` 维护每个 workspace 的 run console 状态并向 App 层暴露操作；App 层只负责把 `WorkspaceTabBarView` 和 `WorkspaceHostView` 接到新的状态和事件。

**Tech Stack:** Swift 6、SwiftUI、Foundation `Process`/`Pipe`、XCTest。

---

### Task 1: 搭建 Core 层运行模型与日志存储

**Files:**
- Create: `macos/Sources/DevHavenCore/Models/WorkspaceRunModels.swift`
- Create: `macos/Sources/DevHavenCore/Run/WorkspaceRunLogStore.swift`
- Test: `macos/Tests/DevHavenCoreTests/WorkspaceRunLogStoreTests.swift`

- [ ] **Step 1: 写日志路径与状态模型测试**
- [ ] **Step 2: 运行 `swift test --package-path macos --filter WorkspaceRunLogStoreTests`，确认先失败**
- [ ] **Step 3: 实现 run session / run console state / log store 最小代码**
- [ ] **Step 4: 再跑 `swift test --package-path macos --filter WorkspaceRunLogStoreTests`，确认通过**

### Task 2: 搭建 `WorkspaceRunManager` 并打通真实命令执行/停止

**Files:**
- Create: `macos/Sources/DevHavenCore/Run/WorkspaceRunManager.swift`
- Test: `macos/Tests/DevHavenCoreTests/WorkspaceRunManagerTests.swift`

- [ ] **Step 1: 先写真实命令输出、结束态、stop 语义测试**
- [ ] **Step 2: 运行 `swift test --package-path macos --filter WorkspaceRunManagerTests`，确认先失败**
- [ ] **Step 3: 实现 `Process + Pipe` 启动、日志追加、结束态、stop 语义**
- [ ] **Step 4: 再跑 `swift test --package-path macos --filter WorkspaceRunManagerTests`，确认通过**

### Task 3: 把运行状态接入 `NativeAppViewModel`

**Files:**
- Modify: `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`
- Modify: `macos/Sources/DevHavenCore/Storage/LegacyCompatStore.swift`
- Test: `macos/Tests/DevHavenCoreTests/NativeAppViewModelWorkspaceRunTests.swift`

- [ ] **Step 1: 先写 ViewModel 测试，覆盖 script 选择、session 新建、多 session 切换、stop 当前 session、logs 面板显隐**
- [ ] **Step 2: 运行 `swift test --package-path macos --filter NativeAppViewModelWorkspaceRunTests`，确认先失败**
- [ ] **Step 3: 注入 `WorkspaceRunManager` 与 run log 目录，补 ViewModel API 与事件桥接**
- [ ] **Step 4: 再跑 `swift test --package-path macos --filter NativeAppViewModelWorkspaceRunTests`，确认通过**

### Task 4: 接入 SwiftUI 顶部控制区与底部 Run Console

**Files:**
- Create: `macos/Sources/DevHavenApp/WorkspaceRunToolbarView.swift`
- Create: `macos/Sources/DevHavenApp/WorkspaceRunConsolePanel.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceTabBarView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceHostView.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceRunToolbarViewTests.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceHostViewRunConsoleTests.swift`

- [ ] **Step 1: 先写 source-based UI 测试，约束右上角 Run/Stop/Logs + script 选择器 + 底部 panel 挂载**
- [ ] **Step 2: 运行 `swift test --package-path macos --filter WorkspaceRunToolbarViewTests` 与 `swift test --package-path macos --filter WorkspaceHostViewRunConsoleTests`，确认先失败**
- [ ] **Step 3: 实现 toolbar 与 console panel，并接上 ViewModel**
- [ ] **Step 4: 再跑上述两个测试，确认通过**

### Task 5: 文档与回归验证

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`

- [ ] **Step 1: 更新 `AGENTS.md`，补充 run console 模块与 `~/.devhaven/run-logs/` 目录说明**
- [ ] **Step 2: 跑完整验证：`swift test --package-path macos`**
- [ ] **Step 3: 如需编译验证，再跑 `swift build --package-path macos`**
- [ ] **Step 4: 回写 `tasks/todo.md` Review，记录验证证据与验收步骤**
