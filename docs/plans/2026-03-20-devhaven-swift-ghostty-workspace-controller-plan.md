# DevHaven Swift Ghostty workspace controller 实施计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 把项目内终端布局 owner 从 `NativeAppViewModel.swift` 中抽到 `GhosttyWorkspaceController.swift`，让 workspace 壳只消费 projection。

**Architecture:** 新增单项目 dedicated owner `GhosttyWorkspaceController`，由它统一维护 `WorkspaceSessionState` projection 与 tab/pane 变更；`OpenWorkspaceSessionState` 改成“项目路径 + controller”，`NativeAppViewModel` 降级为项目级编排层，`WorkspaceHostView` / `WorkspaceShellView` 直接调用 controller。

**Tech Stack:** Swift 6、Observation、SwiftUI、XCTest、Ghostty shared runtime

---

### Task 1: 先补 dedicated owner 测试

**Files:**
- Create: `macos/Tests/DevHavenCoreTests/GhosttyWorkspaceControllerTests.swift`

**Steps:**
1. 锁定 controller 初始会生成单 tab / 单 pane projection。
2. 锁定 controller 的 create tab / split pane / close pane fallback。
3. 锁定 runtime title 不能覆盖稳定 `终端N` 标题。
4. 跑 `swift test --package-path macos --filter GhosttyWorkspaceControllerTests`。

### Task 2: 落 `GhosttyWorkspaceController` 与会话模型调整

**Files:**
- Create: `macos/Sources/DevHavenCore/ViewModels/GhosttyWorkspaceController.swift`
- Modify: `macos/Sources/DevHavenCore/Models/OpenWorkspaceSessionState.swift`
- Modify: `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`

**Steps:**
1. 新增单项目 owner，统一持有 `WorkspaceSessionState` projection 与所有 tab/pane mutation。
2. 让 `OpenWorkspaceSessionState` 改为 `projectPath + controller`。
3. 让 `NativeAppViewModel` 改成只维护 open sessions / active project / diagnostics / system terminal，并把旧 workspace action 收口成 controller 转发。
4. 跑 `swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests`。

### Task 3: 让 workspace 壳直接消费 controller

**Files:**
- Modify: `macos/Sources/DevHavenApp/WorkspaceShellView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceHostView.swift`
- Modify: `macos/Sources/DevHavenApp/DevHavenApp.swift`

**Steps:**
1. `WorkspaceShellView.swift` 改成把 `session.controller` 传给 `WorkspaceHostView.swift`。
2. `WorkspaceHostView.swift` 的 tab/pane/Ghostty action 闭包直接调用 controller。
3. `DevHavenApp.swift` 的 `⌘D` 入口直接使用 `activeWorkspaceController`。
4. 跑定向测试确认未回归。

### Task 4: 文档与验证闭环

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`
- Modify: `tasks/lessons.md`

**Steps:**
1. 更新 AGENTS，明确 dedicated owner / projection 的新边界。
2. 在 tasks/lessons 记录不要再把 pane tree 留在全局 ViewModel 的教训。
3. 跑 `swift test --package-path macos`。
4. 跑 `swift build --package-path macos`。
5. 跑 `git diff --check`。
