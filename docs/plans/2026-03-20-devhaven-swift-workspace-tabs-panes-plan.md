# DevHaven Swift Workspace Tab + Pane Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在当前 Swift 原生 workspace 的单一 Ghostty shell pane 基础上，完成可用的多 Tab + Split Pane MVP。

**Architecture:** 保持 Ghostty app 级共享 runtime 与单 surface host 主线不变，在 `DevHavenCore` 新增 workspace topology 真相层，在 `DevHavenApp` 新增 tab bar / split tree / pane wrapper，并扩展 `GhosttySurfaceBridge` 将 Ghostty action 回推到 topology。

**Tech Stack:** SwiftUI, AppKit, GhosttyKit, Observation, XCTest

---

### Task 1: 建立 workspace topology 纯模型

**Files:**
- Create: `macos/Sources/DevHavenCore/Models/WorkspaceTopologyModels.swift`
- Test: `macos/Tests/DevHavenCoreTests/WorkspaceTopologyTests.swift`

**Step 1: Write the failing test**
- 锁定初始 workspace 会创建单 tab 单 pane
- 锁定 create tab / split pane / close pane / close last tab replacement / move tab / goto tab / zoom / equalize 的核心行为

**Step 2: Run test to verify it fails**
Run: `swift test --package-path macos --filter WorkspaceTopologyTests`

**Step 3: Write minimal implementation**
- 新增 `WorkspaceSessionState / WorkspaceTabState / WorkspacePaneTree / WorkspacePaneState / WorkspaceSplitState`
- 实现 topology helper 与 focus/close/resize/equalize 逻辑

**Step 4: Run test to verify it passes**
Run: `swift test --package-path macos --filter WorkspaceTopologyTests`

### Task 2: 将 NativeAppViewModel 接到 workspace topology

**Files:**
- Modify: `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`
- Modify: `macos/Sources/DevHavenCore/Models/WorkspaceModels.swift`
- Modify: `macos/Tests/DevHavenCoreTests/NativeAppViewModelWorkspaceEntryTests.swift`
- Modify: `macos/Tests/DevHavenCoreTests/WorkspaceSubsystemTests.swift`

**Step 1: Write the failing test**
- 锁定 enter workspace 后会生成 workspace session state
- 锁定 create/select/close/move/split/focus tab/pane 的 view model action

**Step 2: Run test to verify it fails**
Run: `swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests`
Run: `swift test --package-path macos --filter WorkspaceSubsystemTests`

**Step 3: Write minimal implementation**
- 将 `activeWorkspaceLaunchRequest` 升级为 `activeWorkspaceState`
- 新增 workspace action methods，并保留系统 Terminal 打开入口

**Step 4: Run test to verify it passes**
Run: `swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests`
Run: `swift test --package-path macos --filter WorkspaceSubsystemTests`

### Task 3: 扩展 Ghostty bridge 与 host

**Files:**
- Modify: `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceBridge.swift`
- Modify: `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceHost.swift`
- Modify: `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceView.swift`
- Create: `macos/Tests/DevHavenAppTests/GhosttySurfaceBridgeTabPaneTests.swift`

**Step 1: Write the failing test**
- 锁定 bridge 会把 new/close/goto/move tab 和 split action 转发给闭包
- 锁定 host 能把 focus / shell exit 回推给 workspace

**Step 2: Run test to verify it fails**
Run: `swift test --package-path macos --filter GhosttySurfaceBridgeTabPaneTests`

**Step 3: Write minimal implementation**
- 给 bridge 增加 tab/split 闭包
- 给 surface view 增加 focus callback / requestFocus
- 给 host 增加 workspace action 注入点

**Step 4: Run test to verify it passes**
Run: `swift test --package-path macos --filter GhosttySurfaceBridgeTabPaneTests`

### Task 4: 落地 workspace tab bar / split tree / pane UI

**Files:**
- Modify: `macos/Sources/DevHavenApp/AppRootView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceHostView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceTerminalPaneView.swift`
- Create: `macos/Sources/DevHavenApp/WorkspaceTabBarView.swift`
- Create: `macos/Sources/DevHavenApp/WorkspaceSplitTreeView.swift`
- Create: `macos/Sources/DevHavenApp/WorkspaceSplitView.swift`

**Step 1: Write the failing test or behavior lock**
- 优先依赖 Task 1-3 的行为测试锁定状态机；本任务以最小 UI 集成为主

**Step 2: Write minimal implementation**
- `WorkspaceHostView` 渲染 tab bar + selected tab split tree
- `WorkspaceTerminalPaneView` 包装单一 pane UI 与 pane 按钮
- `AppRootView` 改为把整个 workspace state 交给 host 渲染

**Step 3: Verify**
Run: `swift test --package-path macos`

### Task 5: 同步文档并完成验证闭环

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`
- Modify: `tasks/lessons.md`

**Step 1: Sync docs**
- 更新原生客户端段落，说明 workspace 已进入 tab + pane MVP
- 在 `tasks/todo.md` 记录 Review 与验证证据
- 若本轮有可复用教训，写入 `tasks/lessons.md`

**Step 2: Run final verification**
Run: `DEVHAVEN_RUN_GHOSTTY_SMOKE=1 DEVHAVEN_PROJECT_PATH="$PWD" swift test --package-path macos --filter GhosttySurfaceHostTests`
Run: `swift test --package-path macos`
Run: `swift build --package-path macos`
Run: `git diff --check`
