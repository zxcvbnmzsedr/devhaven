# Workspace Snapshot Restore Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 DevHaven 增加非 live 的工作区快照恢复：恢复已打开项目、tab/pane 布局，以及 pane 的 cwd/标题/文本快照提示。

**Architecture:** 保持现有 `NativeAppViewModel -> GhosttyWorkspaceController -> WorkspaceSessionState` 作为运行时真相源，新增 `WorkspaceRestoreStore + WorkspaceRestoreCoordinator` 负责持久化与恢复。恢复后的 pane 始终启动 fresh shell，并带上恢复的 cwd / 标题 / 文本快照上下文，但不额外展示恢复提示弹窗。

**Tech Stack:** Swift / SwiftUI / Observation / Codable / DevHavenCore 持久化层 / GhosttySurfaceHostModel 可见文本读取

---

### Task 1: 恢复模型与存储层

**Files:**
- Create: `macos/Sources/DevHavenCore/Models/WorkspaceRestoreModels.swift`
- Create: `macos/Sources/DevHavenCore/Storage/WorkspaceRestoreStore.swift`
- Test: `macos/Tests/DevHavenCoreTests/WorkspaceRestoreStoreTests.swift`

**Step 1: 写失败测试**

覆盖快照 round-trip、pane 文本分文件存储、version 不匹配、`manifest.prev.json` 回退。

**Step 2: 运行测试确认红灯**

Run: `swift test --package-path macos --filter WorkspaceRestoreStoreTests`
Expected: FAIL

**Step 3: 写最小实现**

实现 restore snapshot 模型、store 主/回退 manifest 读写、pane 文本按安全文件名存储。

**Step 4: 运行测试确认绿灯**

Run: `swift test --package-path macos --filter WorkspaceRestoreStoreTests`
Expected: PASS

### Task 2: 工作区拓扑导出与恢复

**Files:**
- Modify: `macos/Sources/DevHavenCore/Models/WorkspaceModels.swift`
- Modify: `macos/Sources/DevHavenCore/Models/WorkspaceTopologyModels.swift`
- Modify: `macos/Sources/DevHavenCore/ViewModels/GhosttyWorkspaceController.swift`
- Test: `macos/Tests/DevHavenCoreTests/GhosttyWorkspaceRestoreSnapshotTests.swift`

**Step 1: 写失败测试**

覆盖 tab 顺序、pane tree、focused pane、zoom、split ratio、稳定 ID、下一个计数器。

**Step 2: 运行测试确认红灯**

Run: `swift test --package-path macos --filter GhosttyWorkspaceRestoreSnapshotTests`
Expected: FAIL

**Step 3: 写最小实现**

让 controller/session 可导出恢复快照，并从恢复快照重建运行时拓扑。

**Step 4: 运行测试确认绿灯**

Run: `swift test --package-path macos --filter GhosttyWorkspaceRestoreSnapshotTests`
Expected: PASS

### Task 3: pane 快照采集与恢复提示

**Files:**
- Modify: `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceHost.swift`
- Modify: `macos/Sources/DevHavenApp/Ghostty/GhosttyRuntime.swift`
- Test: `macos/Tests/DevHavenAppTests/GhosttySurfaceHostModelSnapshotTests.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceRestorePresentationTests.swift`

**Step 1: 写失败测试**

覆盖 cwd/title/visibleText 快照导出，以及 fresh shell cwd 恢复。

**Step 2: 运行测试确认红灯**

Run: `swift test --package-path macos --filter 'GhosttySurfaceHostModelSnapshotTests|WorkspaceRestorePresentationTests'`
Expected: FAIL

**Step 3: 写最小实现**

为 pane 增加 restore context，恢复后的 pane 用快照 cwd 启动 shell，但不额外展示恢复提示弹窗。

**Step 4: 运行测试确认绿灯**

Run: `swift test --package-path macos --filter 'GhosttySurfaceHostModelSnapshotTests|WorkspaceRestorePresentationTests'`
Expected: PASS

### Task 4: 启动恢复与自动保存协调

**Files:**
- Create: `macos/Sources/DevHavenCore/Restore/WorkspaceRestoreCoordinator.swift`
- Modify: `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`
- Modify: `macos/Sources/DevHavenApp/AppRootView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceShellView.swift`
- Test: `macos/Tests/DevHavenCoreTests/WorkspaceRestoreCoordinatorTests.swift`
- Test: `macos/Tests/DevHavenCoreTests/NativeAppViewModelWorkspaceRestoreTests.swift`

**Step 1: 写失败测试**

覆盖启动恢复顺序、缺失项目跳过、自动保存节流、退出 flush、关闭最后会话后清空快照。

**Step 2: 运行测试确认红灯**

Run: `swift test --package-path macos --filter 'WorkspaceRestoreCoordinatorTests|NativeAppViewModelWorkspaceRestoreTests'`
Expected: FAIL

**Step 3: 写最小实现**

实现 coordinator，并把 load / open / close / tab/pane 变更接到 autosave，App 生命周期触发同步 flush。

**Step 4: 运行测试确认绿灯**

Run: `swift test --package-path macos --filter 'WorkspaceRestoreCoordinatorTests|NativeAppViewModelWorkspaceRestoreTests'`
Expected: PASS

### Task 5: 文档与总验证

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`

**Step 1: 更新架构文档**

补充 `session-restore` 存储职责、恢复边界与“不恢复原终端进程”的约束。

**Step 2: 跑定向与全量验证**

Run:
- `swift test --package-path macos --filter 'WorkspaceRestoreStoreTests|GhosttyWorkspaceRestoreSnapshotTests|GhosttySurfaceHostModelSnapshotTests|WorkspaceRestorePresentationTests|WorkspaceRestoreCoordinatorTests|NativeAppViewModelWorkspaceRestoreTests'`
- `swift test --package-path macos`
- `swift build --package-path macos`

Expected: 全部通过
