# DevHaven Agent 会话状态感知 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 DevHaven 增加 Claude / Codex 的 pane 级会话状态感知，至少能可靠识别 running、waiting（Claude）、completed / failed，并把结果映射到现有 workspace 侧边栏运行时状态中。

**Architecture:** 采用“wrapper / hooks -> signal 文件 -> App 监听”的最小链路。Claude 以 hooks 为真相源；Codex 以 wrapper 生命周期为主、后续再补 notify。App 侧新增统一 agent signal store，把 session JSON 聚合进 `NativeAppViewModel` 和现有 `WorkspaceAttentionState`，UI 只消费统一状态，不直接感知 Claude/Codex 实现差异。

**Tech Stack:** Swift 6、SwiftUI、Observation、Foundation、GhosttyKit、Shell scripts（bash / zsh）、本地 JSON 文件监听。

---

### Task 1: 定义 Agent 会话模型与运行时聚合字段

**Files:**
- Create: `macos/Sources/DevHavenCore/Models/WorkspaceAgentSessionModels.swift`
- Modify: `macos/Sources/DevHavenCore/Models/WorkspaceNotificationModels.swift`
- Modify: `macos/Sources/DevHavenCore/Models/NativeWorktreeModels.swift`
- Test: `macos/Tests/DevHavenCoreTests/NativeAppViewModelWorkspaceEntryTests.swift`

**Step 1: Write the failing test**

在 `NativeAppViewModelWorkspaceEntryTests.swift` 增加一个失败用例，验证 worktree 行除了普通 `taskStatus` 之外，还能表现 `agentState` 与 `agentSummary`：

```swift
func testWorkspaceAgentStatePrefersWaitingOverRunningInSidebar() throws {
    let viewModel = makeViewModel()
    let worktree = makeWorktree(path: "/tmp/devhaven-agent", branch: "feature/agent")
    let project = makeProject(worktrees: [worktree])
    viewModel.snapshot.projects = [project]
    viewModel.enterWorkspace(project.path)
    viewModel.openWorkspaceWorktree(worktree.path, from: project.path)

    let controller = try XCTUnwrap(
        viewModel.openWorkspaceSessions.first(where: { $0.projectPath == worktree.path })?.controller
    )
    let paneID = try XCTUnwrap(controller.selectedPane?.id)

    viewModel.recordAgentSignal(
        .fixture(projectPath: worktree.path, paneId: paneID, state: .running, summary: "Reading file")
    )
    viewModel.recordAgentSignal(
        .fixture(projectPath: worktree.path, paneId: paneID, state: .waiting, summary: "Waiting for approval")
    )

    XCTAssertEqual(viewModel.workspaceSidebarGroups.first?.worktrees.first?.agentState, .waiting)
    XCTAssertEqual(viewModel.workspaceSidebarGroups.first?.worktrees.first?.agentSummary, "Waiting for approval")
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests/testWorkspaceAgentStatePrefersWaitingOverRunningInSidebar`

Expected: 编译失败或断言失败，因为当前还没有 `WorkspaceAgentState`、`recordAgentSignal`、`agentState` / `agentSummary` 字段。

**Step 3: Write minimal implementation**

新增统一模型，并把 agent 字段挂到现有 sidebar 模型上：

```swift
public enum WorkspaceAgentKind: String, Codable, Equatable, Sendable {
    case claude
    case codex
}

public enum WorkspaceAgentState: String, Codable, Equatable, Sendable {
    case unknown
    case running
    case waiting
    case idle
    case completed
    case failed
}

public struct WorkspaceAgentSessionSignal: Codable, Equatable, Sendable {
    public var projectPath: String
    public var workspaceId: String
    public var tabId: String
    public var paneId: String
    public var surfaceId: String
    public var terminalSessionId: String
    public var agentKind: WorkspaceAgentKind
    public var sessionId: String
    public var pid: Int32?
    public var state: WorkspaceAgentState
    public var summary: String?
    public var detail: String?
    public var updatedAt: Date
}
```

并在：
- `WorkspaceAttentionState`
- `WorkspaceSidebarWorktreeItem`
- `WorkspaceSidebarProjectGroup`

补充：
- `agentStateByPaneID`
- `agentSummaryByPaneID`
- `agentKindByPaneID`
- `agentState`
- `agentSummary`

**Step 4: Run test to verify it passes**

Run: `swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests/testWorkspaceAgentStatePrefersWaitingOverRunningInSidebar`

Expected: PASS。

**Step 5: Commit**

```bash
git add macos/Sources/DevHavenCore/Models/WorkspaceAgentSessionModels.swift \
  macos/Sources/DevHavenCore/Models/WorkspaceNotificationModels.swift \
  macos/Sources/DevHavenCore/Models/NativeWorktreeModels.swift \
  macos/Tests/DevHavenCoreTests/NativeAppViewModelWorkspaceEntryTests.swift
git commit -m "feat: add workspace agent session models"
```

---

### Task 2: 新增 signal 文件存储与 stale sweep

**Files:**
- Create: `macos/Sources/DevHavenCore/Storage/WorkspaceAgentSignalStore.swift`
- Modify: `macos/Sources/DevHavenCore/Storage/LegacyCompatStore.swift`
- Test: `macos/Tests/DevHavenCoreTests/WorkspaceAgentSignalStoreTests.swift`

**Step 1: Write the failing test**

新增 `WorkspaceAgentSignalStoreTests.swift`，覆盖三件事：
1. 从 `agent-status/sessions/*.json` 读取并 decode signal；
2. 目录中多个文件时，按 `terminalSessionId` 形成当前态字典；
3. `updatedAt` 过旧且 pid 已不存在时，会被 sweep 清理。

```swift
func testStoreLoadsSignalsFromSessionDirectory() throws {
    let root = try makeHomeDirectory()
    let store = WorkspaceAgentSignalStore(baseDirectoryURL: root)
    try writeSignal(root, terminalSessionId: "session:1", state: .running)

    let snapshots = try store.reloadForTesting()

    XCTAssertEqual(snapshots.count, 1)
    XCTAssertEqual(snapshots["session:1"]?.state, .running)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path macos --filter WorkspaceAgentSignalStoreTests`

Expected: 编译失败，因为 store 与目录 helper 尚不存在。

**Step 3: Write minimal implementation**

- 在 `LegacyCompatStore` 增加 `agentStatusDirectoryURL` helper，指向 `~/.devhaven/agent-status/sessions`。
- 实现 `WorkspaceAgentSignalStore`：
  - `ensureDirectoryExists()`
  - `reloadForTesting()`
  - `start()` / `stop()`
  - `sweepStaleSignals(now:processAlive:)`
- 先使用最小目录扫描 + 定时 sweep；目录级 `DispatchSourceFileSystemObject` 监听可在同一任务内补上。

关键实现骨架：

```swift
final class WorkspaceAgentSignalStore {
    private let baseDirectoryURL: URL
    private(set) var snapshotsByTerminalSessionID: [String: WorkspaceAgentSessionSignal] = [:]

    func reloadForTesting() throws -> [String: WorkspaceAgentSessionSignal] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: baseDirectoryURL,
            includingPropertiesForKeys: nil
        )
        let signals = try urls
            .filter { $0.pathExtension == "json" }
            .map(loadSignal)
        snapshotsByTerminalSessionID = Dictionary(uniqueKeysWithValues: signals.map { ($0.terminalSessionId, $0) })
        return snapshotsByTerminalSessionID
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --package-path macos --filter WorkspaceAgentSignalStoreTests`

Expected: PASS。

**Step 5: Commit**

```bash
git add macos/Sources/DevHavenCore/Storage/WorkspaceAgentSignalStore.swift \
  macos/Sources/DevHavenCore/Storage/LegacyCompatStore.swift \
  macos/Tests/DevHavenCoreTests/WorkspaceAgentSignalStoreTests.swift
git commit -m "feat: add workspace agent signal store"
```

---

### Task 3: 让 App 资源 bundle 暴露 AgentResources，并把运行时环境注入终端

**Files:**
- Modify: `macos/Package.swift`
- Create: `macos/Sources/DevHavenApp/AgentResources/bin/claude`
- Create: `macos/Sources/DevHavenApp/AgentResources/bin/codex`
- Create: `macos/Sources/DevHavenApp/AgentResources/bin/devhaven-agent-emit`
- Create: `macos/Sources/DevHavenApp/AgentResources/hooks/devhaven-claude-hook`
- Create: `macos/Sources/DevHavenApp/DevHavenAppResourceLocator.swift`
- Modify: `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceHost.swift`
- Test: `macos/Tests/DevHavenAppTests/DevHavenAppResourceLocatorTests.swift`
- Test: `macos/Tests/DevHavenAppTests/GhosttySurfaceHostTests.swift`

**Step 1: Write the failing test**

新增两个失败测试：

1. `DevHavenAppResourceLocatorTests.swift`：验证能从 app bundle / test bundle sibling 解析 `AgentResources` 目录；
2. `GhosttySurfaceHostTests.swift`：验证 `GhosttySurfaceHostModel` 给 terminal 注入了：
   - `DEVHAVEN_AGENT_SIGNAL_DIR`
   - `DEVHAVEN_AGENT_RESOURCES_DIR`
   - 前置过 `AgentResources/bin` 的 PATH

```swift
func testResolveAgentResourcesURLPrefersAppContentsResourcesBundle() throws {
    let rootURL = try makeTemporaryDirectory()
    let appURL = rootURL.appending(path: "DevHaven.app", directoryHint: .isDirectory)
    let bundleURL = appURL
        .appending(path: "Contents/Resources", directoryHint: .isDirectory)
        .appending(path: DevHavenAppResourceLocator.resourceBundleName, directoryHint: .isDirectory)
    let agentURL = bundleURL.appending(path: "AgentResources", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: agentURL, withIntermediateDirectories: true)

    let resolved = DevHavenAppResourceLocator.resolveAgentResourcesURL(mainBundle: try XCTUnwrap(Bundle(path: appURL.path)))
    XCTAssertEqual(resolved?.path, agentURL.path)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path macos --filter DevHavenAppResourceLocatorTests`

Expected: 编译失败，因为 locator 与 AgentResources 尚不存在。

**Step 3: Write minimal implementation**

- `Package.swift` 添加：

```swift
resources: [
    .copy("GhosttyResources"),
    .copy("AgentResources"),
]
```

- 新建 `DevHavenAppResourceLocator`，复用资源 bundle 定位逻辑，但专门解析 `AgentResources`。
- 在 `GhosttySurfaceHostModel.acquireSurfaceView()` 中把 `request.environment` 扩展成：

```swift
var environment = request.environment
environment["DEVHAVEN_AGENT_SIGNAL_DIR"] = agentSignalDirectory.path
environment["DEVHAVEN_AGENT_RESOURCES_DIR"] = agentResourcesDirectory.path
environment["PATH"] = "\(agentResourcesDirectory.appending(path: "bin").path):\(existingPath)"
```

- 先只把 wrapper 放进 PATH，不改任何 shell integration。

**Step 4: Run test to verify it passes**

Run: `swift test --package-path macos --filter DevHavenAppResourceLocatorTests`

Run: `swift test --package-path macos --filter GhosttySurfaceHostTests`

Expected: PASS。

**Step 5: Commit**

```bash
git add macos/Package.swift \
  macos/Sources/DevHavenApp/AgentResources \
  macos/Sources/DevHavenApp/DevHavenAppResourceLocator.swift \
  macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceHost.swift \
  macos/Tests/DevHavenAppTests/DevHavenAppResourceLocatorTests.swift \
  macos/Tests/DevHavenAppTests/GhosttySurfaceHostTests.swift
git commit -m "feat: inject agent resources into terminal environment"
```

---

### Task 4: 打通 Claude / Codex wrapper 到 signal 文件

**Files:**
- Modify: `macos/Sources/DevHavenApp/AgentResources/bin/claude`
- Modify: `macos/Sources/DevHavenApp/AgentResources/bin/codex`
- Modify: `macos/Sources/DevHavenApp/AgentResources/bin/devhaven-agent-emit`
- Modify: `macos/Sources/DevHavenApp/AgentResources/hooks/devhaven-claude-hook`
- Create: `macos/Tests/DevHavenAppTests/WorkspaceAgentWrapperScriptTests.swift`

**Step 1: Write the failing test**

新增脚本级集成测试，模拟：
1. Claude hook 写出 `running` / `waiting` / `completed`；
2. Codex wrapper 在子进程结束后写出 `completed`；
3. wrapper 在非 DevHaven 环境中应完全透传，不写 signal。

```swift
func testClaudeHookWritesWaitingSignalJSON() throws {
    let fixture = try makeWrapperFixture()
    let output = try runScript(
        fixture.hookPath,
        environment: fixture.environment,
        stdin: fixture.notificationPayload
    )

    XCTAssertTrue(output.contains("OK"))
    let signal = try fixture.readSignal(terminalSessionId: "session:test")
    XCTAssertEqual(signal.agentKind, .claude)
    XCTAssertEqual(signal.state, .waiting)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path macos --filter WorkspaceAgentWrapperScriptTests`

Expected: 失败，因为脚本还只是占位或不存在。

**Step 3: Write minimal implementation**

`devhaven-agent-emit` 负责把标准 JSON 落到 signal 目录：

```bash
#!/usr/bin/env bash
set -euo pipefail

cat > "$signal_file" <<JSON
{
  "projectPath": "$DEVHAVEN_PROJECT_PATH",
  "workspaceId": "$DEVHAVEN_WORKSPACE_ID",
  "tabId": "$DEVHAVEN_TAB_ID",
  "paneId": "$DEVHAVEN_PANE_ID",
  "surfaceId": "$DEVHAVEN_SURFACE_ID",
  "terminalSessionId": "$DEVHAVEN_TERMINAL_SESSION_ID",
  "agentKind": "$agent_kind",
  "sessionId": "$session_id",
  "pid": $pid,
  "state": "$state",
  "summary": $summary_json,
  "detail": $detail_json,
  "updatedAt": "$iso_now"
}
JSON
```

Claude wrapper / hook：
- 注入 session-id 与 hooks；
- `UserPromptSubmit` -> `running`
- `Notification` -> `waiting`
- `Stop` -> `completed`

Codex wrapper：
- 启动前 emit `running`
- `real_codex "$@"`; `status=$?`
- 退出后按 `$status` emit `completed` / `failed`

**Step 4: Run test to verify it passes**

Run: `swift test --package-path macos --filter WorkspaceAgentWrapperScriptTests`

Expected: PASS。

**Step 5: Commit**

```bash
git add macos/Sources/DevHavenApp/AgentResources/bin/claude \
  macos/Sources/DevHavenApp/AgentResources/bin/codex \
  macos/Sources/DevHavenApp/AgentResources/bin/devhaven-agent-emit \
  macos/Sources/DevHavenApp/AgentResources/hooks/devhaven-claude-hook \
  macos/Tests/DevHavenAppTests/WorkspaceAgentWrapperScriptTests.swift
git commit -m "feat: emit claude and codex session signals"
```

---

### Task 5: 把 signal store 接入 NativeAppViewModel，并映射到侧边栏 UI

**Files:**
- Modify: `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceShellView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceProjectListView.swift`
- Modify: `macos/Tests/DevHavenCoreTests/NativeAppViewModelWorkspaceEntryTests.swift`
- Modify: `macos/Tests/DevHavenAppTests/WorkspaceProjectListViewTests.swift`

**Step 1: Write the failing test**

为 `NativeAppViewModel` 增加失败测试，验证：
- ingest signal 后，`workspaceSidebarGroups` 中 worktree 的 `agentState` / `agentSummary` 会更新；
- `waiting` 优先级高于 `running`；
- 当前 project 关闭后，对应 agent 状态会被清理。

为 `WorkspaceProjectListViewTests.swift` 增加现有风格的断言，验证源码中新增了 agent 状态入口：

```swift
func testWorktreeRowsRenderAgentStateAccessory() throws {
    let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)
    XCTAssertTrue(source.contains("agentState"), "worktree 行应显式消费 agentState")
    XCTAssertTrue(source.contains("agentSummary"), "worktree 行应能展示 agent 摘要")
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests`

Run: `swift test --package-path macos --filter WorkspaceProjectListViewTests`

Expected: FAIL。

**Step 3: Write minimal implementation**

- 在 `NativeAppViewModel.init` 中注入 / 持有 `WorkspaceAgentSignalStore`。
- 在 `WorkspaceShellView.onAppear` 时启动监听，在 session/path 变化时同步当前打开项目集合。
- 新增：

```swift
public func recordAgentSignal(_ signal: WorkspaceAgentSessionSignal) {
    var attention = attentionStateByProjectPath[signal.projectPath] ?? WorkspaceAttentionState()
    attention.setAgentState(signal.state, kind: signal.agentKind, summary: signal.summary, for: signal.paneId)
    attentionStateByProjectPath[signal.projectPath] = attention
}
```

- `WorkspaceProjectListView` 增加最小 UI：
  - `waiting` -> 红色 `exclamationmark.circle.fill`
  - `running` -> `bolt.fill` 或 `ProgressView`
  - tooltip / caption 使用 `agentSummary`

**Step 4: Run test to verify it passes**

Run: `swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests`

Run: `swift test --package-path macos --filter WorkspaceProjectListViewTests`

Expected: PASS。

**Step 5: Commit**

```bash
git add macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift \
  macos/Sources/DevHavenApp/WorkspaceShellView.swift \
  macos/Sources/DevHavenApp/WorkspaceProjectListView.swift \
  macos/Tests/DevHavenCoreTests/NativeAppViewModelWorkspaceEntryTests.swift \
  macos/Tests/DevHavenAppTests/WorkspaceProjectListViewTests.swift
git commit -m "feat: surface agent session state in workspace sidebar"
```

---

### Task 6: 文档同步与最终验证

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`
- Modify: `docs/plans/2026-03-22-agent-session-status-design.md`
- Modify: `docs/plans/2026-03-22-agent-session-status.md`

**Step 1: Update docs**
- 在 `AGENTS.md` 中补充：
  - AgentResources 资源目录
  - signal 文件目录
  - Claude/Codex 状态感知链路
  - “Claude hooks 主链、Codex wrapper 主链、文本分析仅 fallback” 边界
- 在 `tasks/todo.md` 回填 Review 与验证证据。

**Step 2: Run verification**

Run: `swift test --package-path macos`

Expected: 所有测试通过。

Run: `swift build --package-path macos`

Expected: `Build complete!`

**Step 3: Smoke check wrappers**

Run: `swift run --package-path macos DevHavenApp`

Expected: 从 DevHaven 内部 terminal 启动 `claude` / `codex` 时，侧边栏能看到 agent 状态变化；若当前机型不适合自动 smoke，则至少记录手动验证步骤与结果。

**Step 4: Commit**

```bash
git add AGENTS.md tasks/todo.md docs/plans/2026-03-22-agent-session-status-design.md docs/plans/2026-03-22-agent-session-status.md
git commit -m "docs: document agent session status architecture"
```
