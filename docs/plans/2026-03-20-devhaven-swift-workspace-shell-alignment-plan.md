# DevHaven Swift workspace 外层壳对齐 Tauri 实施计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 把 Swift 原生 workspace 改成左侧已打开项目列表 + 右侧终端区，并保留每个项目独立的标签页/分屏状态。

**Architecture:** 在 ViewModel 层把 workspace 状态从单项目扩成“已打开项目会话集合 + 当前激活项目”，再新增 `WorkspaceShellView` 承接左侧列表与右侧多 workspace 保活挂载。现有 `WorkspaceHostView` 继续作为单项目右侧终端主区，不重新发明 tab/pane topology。

**Tech Stack:** SwiftUI、Observation、DevHavenCore、Ghostty shared runtime

---

### Task 1: 先补失败测试锁定多已打开项目状态

**Files:**
- Modify: `macos/Tests/DevHavenCoreTests/NativeAppViewModelWorkspaceEntryTests.swift`

**Steps:**
1. 写测试：连续 `enterWorkspace(A)`、`enterWorkspace(B)` 后，已打开项目列表应包含 A/B，active 应切到 B。
2. 写测试：在 A 内创建 tab/split，再切到 B、再切回 A，A 的 workspace topology 应保持不变。
3. 写测试：关闭当前已打开项目后，active 应回退到剩余项目；最后一个关闭后应退出 workspace。
4. 跑定向测试确认先红。

### Task 2: 扩展 ViewModel 成多 workspace 会话模型

**Files:**
- Create: `macos/Sources/DevHavenCore/Models/OpenWorkspaceSessionState.swift`
- Modify: `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`

**Steps:**
1. 新增 `OpenWorkspaceSessionState`。
2. 把 `NativeAppViewModel` 改成持有已打开项目会话集合。
3. 让 `activeWorkspaceState` / `activeWorkspaceProject` / `activeWorkspaceLaunchRequest` 改为派生值。
4. 新增 `activateWorkspaceProject`、`closeWorkspaceProject` 等方法。
5. 跑 ViewModel 定向测试转绿。

### Task 3: 新增 workspace shell，并把 AppRoot 接过去

**Files:**
- Create: `macos/Sources/DevHavenApp/WorkspaceShellView.swift`
- Create: `macos/Sources/DevHavenApp/WorkspaceProjectListView.swift`
- Modify: `macos/Sources/DevHavenApp/AppRootView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceHostView.swift`

**Steps:**
1. 新增左侧项目列表视图，包含“已打开项目”标题、返回、项目切换、关闭入口。
2. 新增 workspace shell，把左侧列表和右侧主区拼起来。
3. 右侧主区用 `ZStack + ForEach(open sessions)` 保活所有 `WorkspaceHostView`，只让当前 active 可见。
4. 精简 `WorkspaceHostView` 中已经重复的返回逻辑。
5. 确认编译通过。

### Task 4: 跑回归验证并同步文档

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`
- Modify: `tasks/lessons.md`
- Modify: `/Users/zhaotianzeng/.codex/memories/MEMORY.md`
- Modify: `/Users/zhaotianzeng/.codex/memories/memory_summary.md`

**Steps:**
1. 跑 `swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests`
2. 跑 `swift test --package-path macos --filter WorkspaceTopologyTests`
3. 跑 `swift test --package-path macos --filter GhosttySurfaceBridgeTabPaneTests`
4. 跑 `DEVHAVEN_RUN_GHOSTTY_SMOKE=1 DEVHAVEN_PROJECT_PATH="$PWD" swift test --package-path macos --filter GhosttySurfaceHostTests`
5. 跑 `swift test --package-path macos`
6. 跑 `swift build --package-path macos`
7. 跑 `git diff --check`
8. 同步 AGENTS / tasks / lessons / memory
