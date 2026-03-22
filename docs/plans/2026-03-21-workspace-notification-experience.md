# Workspace Notification Experience Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 DevHaven 增加接近 Supacode 的完整工作区通知体验，包括运行中状态、未读 bell、通知 popover、系统通知与声音开关。

**Architecture:** 通过 Ghostty bridge 捕获终端事件，在 `GhosttySurfaceHostModel` 做 pane 级状态桥接，在 `NativeAppViewModel` 维护 project/worktree 级运行时注意力状态，再由侧边栏与 workspace UI 统一消费。系统通知与声音保留在 App 层 presenter，Core 只维护状态与路由。

**Tech Stack:** SwiftUI、AppKit、Observation、GhosttyKit、DevHavenCore。

---

### Task 1: 建立运行时通知模型与设置项

**Files:**
- Modify: `macos/Sources/DevHavenCore/Models/AppModels.swift`
- Modify: `macos/Sources/DevHavenCore/Models/NativeWorktreeModels.swift`
- Create: `macos/Sources/DevHavenCore/Models/WorkspaceNotificationModels.swift`
- Test: `macos/Tests/DevHavenCoreTests/LegacyCompatStoreTests.swift`

**Step 1: Write the failing test**
- 为新增通知设置默认值与持久化兼容补测试。

**Step 2: Run test to verify it fails**
Run: `swift test --package-path macos --filter LegacyCompatStoreMutationTests`
Expected: 因缺少通知设置字段而失败。

**Step 3: Write minimal implementation**
- 为 `AppSettings` 增加通知相关开关。
- 为侧边栏模型增加通知/运行状态字段。
- 新增运行时通知模型。

**Step 4: Run test to verify it passes**
Run: `swift test --package-path macos --filter LegacyCompatStoreMutationTests`
Expected: PASS。

### Task 2: 让 Ghostty bridge 产出通知 / 运行 / bell 事件

**Files:**
- Modify: `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceState.swift`
- Modify: `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceBridge.swift`
- Test: `macos/Tests/DevHavenAppTests/GhosttySurfaceBridgeTabPaneTests.swift`

**Step 1: Write the failing test**
- 新增 desktop notification、progress report、ring bell 的 bridge 单测。

**Step 2: Run test to verify it fails**
Run: `swift test --package-path macos --filter GhosttySurfaceBridgeTabPaneTests`
Expected: 因 bridge 未处理这些 action 而失败。

**Step 3: Write minimal implementation**
- 扩展 state 字段。
- bridge 新增事件处理与 closure。

**Step 4: Run test to verify it passes**
Run: `swift test --package-path macos --filter GhosttySurfaceBridgeTabPaneTests`
Expected: PASS。

### Task 3: 建立 ViewModel 级工作区注意力状态

**Files:**
- Modify: `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`
- Modify: `macos/Sources/DevHavenCore/ViewModels/GhosttyWorkspaceController.swift`
- Test: `macos/Tests/DevHavenCoreTests/NativeAppViewModelWorkspaceEntryTests.swift`
- Create: `macos/Tests/DevHavenCoreTests/NativeAppViewModelWorkspaceNotificationTests.swift`

**Step 1: Write the failing test**
- 为记录通知、标记已读、聚焦 pane、运行中排序、新通知置顶补测试。

**Step 2: Run test to verify it fails**
Run: `swift test --package-path macos --filter NativeAppViewModelWorkspaceNotificationTests`
Expected: 因 ViewModel 还没有对应 API 与状态而失败。

**Step 3: Write minimal implementation**
- 引入注意力状态字典与更新 API。
- 为 controller 增加通知回跳所需的定位/跳转能力。
- 调整 `workspaceSidebarGroups` 生成逻辑。

**Step 4: Run test to verify it passes**
Run: `swift test --package-path macos --filter NativeAppViewModelWorkspaceNotificationTests`
Expected: PASS。

### Task 4: 连接 HostModel、Workspace UI 与通知展示

**Files:**
- Modify: `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceHost.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceHostView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceProjectListView.swift`
- Create: `macos/Sources/DevHavenApp/WorkspaceNotificationPopover.swift`
- Create: `macos/Sources/DevHavenApp/WorkspaceNotificationPresenter.swift`
- Test: `macos/Tests/DevHavenAppTests/GhosttySurfaceHostTests.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceProjectListViewTests.swift`
- Test: `macos/Tests/DevHavenAppTests/SettingsViewTests.swift`

**Step 1: Write the failing test**
- host model 事件透传测试
- 侧边栏视图源码断言测试（bell / 通知 popover / 设置入口）

**Step 2: Run test to verify it fails**
Run: `swift test --package-path macos --filter GhosttySurfaceHostTests`
Run: `swift test --package-path macos --filter WorkspaceProjectListViewTests`
Run: `swift test --package-path macos --filter SettingsViewTests`
Expected: 因为 UI/host model 还未提供通知体验而失败。

**Step 3: Write minimal implementation**
- host model 转发 bridge 事件
- workspace host 连接 viewModel 与 presenter
- 侧边栏显示 bell / spinner / popover
- presenter 支持系统通知与声音提示

**Step 4: Run test to verify it passes**
Run: `swift test --package-path macos --filter GhosttySurfaceHostTests`
Run: `swift test --package-path macos --filter WorkspaceProjectListViewTests`
Run: `swift test --package-path macos --filter SettingsViewTests`
Expected: PASS。

### Task 5: 更新文档与验证

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`

**Step 1: Update docs**
- 记录新通知架构、关键文件与边界。

**Step 2: Run verification**
Run: `swift test --package-path macos`
Run: `swift build --package-path macos`
Expected: 全部通过。
