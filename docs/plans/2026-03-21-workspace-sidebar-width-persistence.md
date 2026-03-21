# Workspace Sidebar Width Persistence Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 把工作区左侧侧边栏宽度持久化到全局设置，并在再次进入工作区时恢复上次宽度。

**Architecture:** 在 `AppSettings` 增加全局 `workspaceSidebarWidth` 字段，`WorkspaceShellView` 从 settings 读取初始值，并在拖拽结束后通过 `NativeAppViewModel.saveSettings` 写回。继续复用 `WorkspaceSidebarLayoutPolicy` 作为唯一宽度约束入口，保证旧配置兼容与主内容区最小宽度不被破坏。

**Tech Stack:** Swift 6、SwiftUI、AppKit、Codable、XCTest。

---

### Task 1: 为设置模型增加全局侧边栏宽度字段

**Files:**
- Modify: `macos/Sources/DevHavenCore/Models/AppModels.swift`
- Test: `macos/Tests/DevHavenCoreTests/AppSettingsWorkspaceSidebarWidthTests.swift`

**Step 1: Write the failing test**
- 新建测试，断言：
  - 默认 `AppSettings()` 的 `workspaceSidebarWidth == 280`
  - 当解码缺少该字段时仍回退到 280

**Step 2: Run test to verify it fails**
Run: `swift test --package-path macos --filter AppSettingsWorkspaceSidebarWidthTests`
Expected: FAIL，因为字段尚不存在。

**Step 3: Write minimal implementation**
- 在 `AppSettings` 增加 `workspaceSidebarWidth: Double`
- 更新 init、CodingKeys 与 `init(from:)`

**Step 4: Run test to verify it passes**
Run: `swift test --package-path macos --filter AppSettingsWorkspaceSidebarWidthTests`
Expected: PASS

### Task 2: 让 WorkspaceShellView 从 settings 读取并写回宽度

**Files:**
- Modify: `macos/Sources/DevHavenApp/WorkspaceShellView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceSplitView.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceShellViewTests.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceSidebarLayoutPolicyTests.swift`

**Step 1: Write the failing test**
- 补测试约束：
  - `WorkspaceShellView` 应从 `viewModel.snapshot.appState.settings.workspaceSidebarWidth` 读取初始宽度
  - `WorkspaceSplitView` 应提供拖拽结束回调，供 settings 持久化使用

**Step 2: Run test to verify it fails**
Run: `swift test --package-path macos --filter 'Workspace(ShellView|SidebarLayoutPolicy)Tests'`
Expected: FAIL，因为当前只保存在本地状态中。

**Step 3: Write minimal implementation**
- `WorkspaceSplitView` 新增可选拖拽结束回调
- `WorkspaceShellView`：
  - 根据 settings 初始化/同步本地宽度
  - 在拖拽结束时通过 `viewModel.saveSettings(...)` 写回 settings

**Step 4: Run test to verify it passes**
Run: `swift test --package-path macos --filter 'Workspace(ShellView|SidebarLayoutPolicy)Tests'`
Expected: PASS

### Task 3: 做回归验证并记录结果

**Files:**
- Modify: `tasks/todo.md`

**Step 1: Run full verification**
Run: `swift test --package-path macos`
Expected: PASS

**Step 2: Update task record**
- 在 `tasks/todo.md` 勾选完成项
- 追加 Review，记录根因、修复方案、验证命令
