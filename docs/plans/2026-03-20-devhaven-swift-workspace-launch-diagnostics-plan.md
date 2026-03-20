# DevHaven Swift workspace 进入命令行诊断实施计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 给 Swift 原生 workspace 补进入命令行诊断日志，明确 workspace 恢复、host 挂载和 Ghostty surface 创建分别花了多少时间。

**Architecture:** 新增一个轻量 `WorkspaceLaunchDiagnostics` 中心，在 `enterWorkspace`、`WorkspaceShellView`/`WorkspaceHostView` 和 `GhosttySurfaceHostModel.acquireSurfaceView()` 三段关键路径发结构化事件，再统一写到日志。主线只加证据，不改恢复语义。

**Tech Stack:** Swift 6、SwiftUI、Observation、OSLog、XCTest、Ghostty shared runtime

---

### Task 1: 先补失败测试锁定诊断事件

**Files:**
- Create: `macos/Tests/DevHavenCoreTests/WorkspaceLaunchDiagnosticsTests.swift`
- Modify: `macos/Tests/DevHavenCoreTests/NativeAppViewModelWorkspaceEntryTests.swift`

**Step 1: 写 `WorkspaceLaunchDiagnosticsTests` 失败测试**

- 断言入口事件会保留 `workspaceId / projectPath / openSessionCount / tabCount / paneCount`
- 断言 surface 完成事件会带 `surfaceId / paneId / durationMs / status`

**Step 2: 写 `NativeAppViewModelWorkspaceEntryTests` 失败测试**

- 断言 `enterWorkspace(_:)` 之后会发出一条入口诊断事件

**Step 3: 跑定向测试确认先红**

Run:

```bash
swift test --package-path macos --filter WorkspaceLaunchDiagnosticsTests
swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests
```

Expected:

- 编译失败或测试失败，提示缺少 `WorkspaceLaunchDiagnostics`

### Task 2: 落诊断中心

**Files:**
- Create: `macos/Sources/DevHavenCore/Diagnostics/WorkspaceLaunchDiagnostics.swift`

**Step 1: 新增结构化事件模型**

- 入口事件
- shell 挂载事件
- host 挂载事件
- surface 创建开始 / 结束 / 复用事件

**Step 2: 新增诊断中心**

- 提供 `shared`
- 支持测试注入事件回调
- 统一输出日志文本
- 追踪 `workspaceId` 与 `surfaceId` 的开始时间

**Step 3: 运行 `WorkspaceLaunchDiagnosticsTests` 转绿**

### Task 3: 接入 ViewModel 与 SwiftUI / Ghostty 链路

**Files:**
- Modify: `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceShellView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceHostView.swift`
- Modify: `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceHost.swift`

**Step 1: 在 `enterWorkspace(_:)` 发入口事件**

**Step 2: 在 `WorkspaceShellView` / `WorkspaceHostView` 发挂载事件**

**Step 3: 在 `GhosttySurfaceHostModel.acquireSurfaceView()` 发 surface 开始 / 结束 / 复用事件**

**Step 4: 跑 `NativeAppViewModelWorkspaceEntryTests` 转绿**

### Task 4: 文档与验证

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`

**Step 1: 更新文档，补充诊断入口说明**

**Step 2: 跑完整验证**

```bash
swift test --package-path macos --filter WorkspaceLaunchDiagnosticsTests
swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests
swift test --package-path macos
swift build --package-path macos
git diff --check
```

**Step 3: 在 `tasks/todo.md` 追加 Review**

