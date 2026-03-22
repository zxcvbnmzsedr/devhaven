# DevHaven Codex 展示态修正 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 修复交互式 Codex 在当前回合完成后仍显示“正在运行”的问题，使其在回到输入态时显示“等待输入”，并去除重复摘要文案。

**Architecture:** 保持现有 wrapper/signal store 的进程态链路不变，只在 App 内存层为 `codex + running` 增加可见文本启发式展示态修正。新增一个纯字符串 heuristic 模块，`WorkspaceShellView` 轻量轮询打开 pane 的可见文本，`NativeAppViewModel` 保存 pane 级 display override，UI 优先消费 override，未命中时退回底层 signal。

**Tech Stack:** Swift, SwiftUI, GhosttyKit, XCTest

---

### Task 1: 写出 Codex 展示态 heuristic 的失败测试

**Files:**
- Create: `macos/Tests/DevHavenAppTests/CodexAgentDisplayHeuristicsTests.swift`
- Create: `macos/Sources/DevHavenApp/CodexAgentDisplayHeuristics.swift`

**Step 1: Write the failing test**

覆盖至少三类样本：
- 包含 `Working (13s • esc to interrupt)` -> `.running`
- 包含输入提示 `Improve documentation in @filename` 且不含 `Working (` -> `.waiting`
- 无法可靠判断的普通文本 -> `nil`

**Step 2: Run test to verify it fails**

Run: `swift test --package-path macos --filter CodexAgentDisplayHeuristicsTests`
Expected: FAIL，提示缺少 heuristic 类型或行为未实现。

**Step 3: Write minimal implementation**

在 `CodexAgentDisplayHeuristics.swift` 中新增纯函数，例如：
- `static func displayState(for visibleText: String) -> WorkspaceAgentState?`

实现最小规则：
- 含 `Working (` -> `.running`
- 含输入占位词且不含 `Working (` -> `.waiting`
- 否则 `nil`

**Step 4: Run test to verify it passes**

Run: `swift test --package-path macos --filter CodexAgentDisplayHeuristicsTests`
Expected: PASS

### Task 2: 为 ViewModel 展示态 override 写失败测试

**Files:**
- Modify: `macos/Tests/DevHavenCoreTests/NativeAppViewModelWorkspaceEntryTests.swift`
- Modify: `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`

**Step 1: Write the failing test**

新增测试覆盖：
- 底层 signal 为 `codex + running`
- 当给 pane 注入 display override `.waiting` 后
- `workspaceSidebarGroups.first?.worktrees.first?.agentState == .waiting`
- `agentKind == .codex`

并补一个“清空 override 后退回 signal 原值”的测试。

**Step 2: Run test to verify it fails**

Run: `swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests/testWorkspaceCodexDisplayOverridePrefersWaitingOverRunningSignal`
Expected: FAIL，说明当前 ViewModel 仍直接消费 signal 原值。

**Step 3: Write minimal implementation**

在 `NativeAppViewModel` 中：
- 新增 pane 级 agent display override 的运行时内存存储；
- 提供设置/清除 override 的方法；
- 侧边栏 group / worktree 聚合优先消费 override，再退回原 signal。

**Step 4: Run test to verify it passes**

Run: `swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests/testWorkspaceCodexDisplayOverridePrefersWaitingOverRunningSignal`
Expected: PASS

### Task 3: 为 Codex waiting 文案与重复摘要去重写失败测试

**Files:**
- Modify: `macos/Tests/DevHavenAppTests/WorkspaceAgentStatusAccessoryTests.swift`
- Modify: `macos/Tests/DevHavenAppTests/WorkspaceProjectListViewTests.swift`（若不存在则创建最小测试文件）
- Modify: `macos/Sources/DevHavenApp/WorkspaceAgentStatusAccessory.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceProjectListView.swift`

**Step 1: Write the failing test**

测试点：
- `agentState = .waiting, agentKind = .codex` 时 label 为 `Codex 等待输入`；
- 当 summary 与 label 完全一致时，不重复拼成 `label：summary`。

**Step 2: Run test to verify it fails**

Run: `swift test --package-path macos --filter WorkspaceAgentStatusAccessoryTests`
Expected: FAIL，当前 Codex waiting 仍是通用文案。

如果新增列表视图测试：
Run: `swift test --package-path macos --filter WorkspaceProjectListViewTests`
Expected: FAIL，当前重复摘要未去重。

**Step 3: Write minimal implementation**

- 在 `WorkspaceAgentStatusAccessory` 中为 Codex waiting 特判文案；
- 在 `WorkspaceProjectListView` 中提取 summary 展示文本，对和 label 相同的 summary 返回 `nil`。

**Step 4: Run test to verify it passes**

Run: `swift test --package-path macos --filter WorkspaceAgentStatusAccessoryTests`
Run: `swift test --package-path macos --filter WorkspaceProjectListViewTests`
Expected: PASS

### Task 4: 为 pane 可见文本轮询与 display override 接线写失败测试

**Files:**
- Modify: `macos/Sources/DevHavenApp/WorkspaceShellView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceTerminalSessionStore.swift`
- Modify: `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceHost.swift`
- Modify: `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceView.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceShellViewTests.swift`（若需要）

**Step 1: Write the failing test**

尽量覆盖一个可单元测试的最小入口，而不是直接测定时器：
- 暴露一个同步刷新函数，例如“根据当前打开 pane 的可见文本刷新 Codex 展示态”；
- 注入假的 pane visible text 提供器；
- 验证 running -> waiting override 会被写入 ViewModel。

**Step 2: Run test to verify it fails**

Run: `swift test --package-path macos --filter WorkspaceShellViewTests`
Expected: FAIL，当前无刷新入口或无 override 写入。

**Step 3: Write minimal implementation**

- 给 `GhosttySurfaceHostModel` 暴露只读可见文本读取方法；
- 在 `WorkspaceTerminalSessionStore` 增加按 pane ID 取 model 的能力；
- 在 `WorkspaceShellView` 新增低频定时刷新逻辑，只扫描 `codex + running` pane；
- 调用 heuristic 结果，写入/清除 `NativeAppViewModel` 的 display override。

**Step 4: Run test to verify it passes**

Run: `swift test --package-path macos --filter WorkspaceShellViewTests`
Expected: PASS

### Task 5: 同步文档与 AGENTS，并做定向验证

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`
- Modify: `tasks/lessons.md`（如形成可复用教训）

**Step 1: Update docs**

补充：
- Codex 当前采用“signal 进程态 + 可见文本展示态修正”的双层语义；
- display override 仅属于 App/UI 运行时，不回写 signal store。

**Step 2: Run focused verification**

Run:
- `swift test --package-path macos --filter CodexAgentDisplayHeuristicsTests`
- `swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests/testWorkspaceCodexDisplayOverridePrefersWaitingOverRunningSignal`
- `swift test --package-path macos --filter WorkspaceAgentStatusAccessoryTests`
- `swift test --package-path macos --filter WorkspaceProjectListViewTests`
- `swift test --package-path macos --filter WorkspaceShellViewTests`

Expected: 全部 PASS

**Step 3: Run broader verification**

Run: `swift test --package-path macos`
Expected: PASS

**Step 4: Update Review**

在 `tasks/todo.md` 追加：
- 直接原因
- 是否存在设计层诱因
- 当前修复方案
- 长期改进建议
- 验证证据
