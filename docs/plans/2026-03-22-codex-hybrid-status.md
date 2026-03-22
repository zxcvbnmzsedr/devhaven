# DevHaven Codex 混合状态机 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 把 Codex 状态判定从“wrapper 进程态 + 纯屏幕 heuristic”升级为“official notify + 进程态 + App 活动度 fallback”的混合状态机，减少长输出/交互会话中的误判。

**Architecture:** wrapper 继续负责 running/completed/failed，额外通过 CLI config override 注入 Codex 官方 notify，让 `agent-turn-complete` 直接写 waiting signal。App 侧只把可见文本与最近活动度作为补偿层：waiting 时可临时提升回 running，running 时仅在 idle 且长时间无变化时才降级为 waiting。

**Tech Stack:** Swift, SwiftUI, XCTest, Bash, Python 3

---

### Task 1: 为 Codex notify 脚本写失败测试

**Files:**
- Create: `macos/Tests/DevHavenAppTests/WorkspaceCodexNotifyScriptTests.swift`
- Create: `macos/Sources/DevHavenApp/AgentResources/bin/devhaven-codex-notify`

**Step 1: Write the failing test**

覆盖：
- payload 为 `{"type":"agent-turn-complete", ...}` 时写出 `codex + waiting`
- 优先提取 `last-assistant-message` 作为 summary
- 未知事件不会破坏已有 signal

**Step 2: Run test to verify it fails**

Run: `swift test --package-path macos --filter WorkspaceCodexNotifyScriptTests`
Expected: FAIL，缺少 notify 脚本或行为未实现。

**Step 3: Write minimal implementation**

实现 `devhaven-codex-notify`：
- 从 argv 读取 JSON payload
- 宽松解析 `type / session_id / last-assistant-message / msg`
- `agent-turn-complete` -> 调 `devhaven-agent-emit --state waiting`

**Step 4: Run test to verify it passes**

Run: `swift test --package-path macos --filter WorkspaceCodexNotifyScriptTests`
Expected: PASS

### Task 2: 为 wrapper 注入 notify 写失败测试

**Files:**
- Modify: `macos/Tests/DevHavenAppTests/WorkspaceAgentWrapperScriptTests.swift`
- Modify: `macos/Sources/DevHavenApp/AgentResources/bin/codex`

**Step 1: Write the failing test**

覆盖：
- wrapper 在 DevHaven 环境里会给真实 Codex 追加 notify override
- notify override 至少包含：
  - `-c notify=["...devhaven-codex-notify"]`
  - `-c tui.notifications=true`
- wrapper 退出后 completed/failed 逻辑仍存在

**Step 2: Run test to verify it fails**

Run: `swift test --package-path macos --filter WorkspaceAgentWrapperScriptTests`
Expected: FAIL，当前 wrapper 尚未注入 notify。

**Step 3: Write minimal implementation**

更新 `bin/codex`：
- 导出 `DEVHAVEN_AGENT_SESSION_ID`
- 构造 notify override 参数
- 继续调用真实 Codex，并保留 running/completed/failed emit

**Step 4: Run test to verify it passes**

Run: `swift test --package-path macos --filter WorkspaceAgentWrapperScriptTests`
Expected: PASS

### Task 3: 为混合状态机写失败测试

**Files:**
- Modify: `macos/Tests/DevHavenAppTests/CodexAgentDisplayHeuristicsTests.swift`
- Create or Modify: `macos/Tests/DevHavenAppTests/CodexAgentDisplayStateRefresherTests.swift`
- Modify: `macos/Sources/DevHavenApp/CodexAgentDisplayHeuristics.swift`
- Modify: `macos/Sources/DevHavenApp/CodexAgentDisplayStateRefresher.swift`

**Step 1: Write the failing test**

至少覆盖：
- waiting signal + running marker -> override running
- running signal + waiting marker + 长时间无变化 -> override waiting
- running signal + waiting marker 但近期文本仍变化 -> 保持 running
- 未命中规则 -> 保持 signal 原值

**Step 2: Run test to verify it fails**

Run: `swift test --package-path macos --filter CodexAgentDisplayStateRefresherTests`
Expected: FAIL，当前 refresher 还不支持活动度状态机。

**Step 3: Write minimal implementation**

在 refresher 中引入 pane 级观测状态：
- `lastVisibleText`
- `lastChangedAt`

并按设计文档的规则决定 override。

**Step 4: Run test to verify it passes**

Run: `swift test --package-path macos --filter CodexAgentDisplayStateRefresherTests`
Expected: PASS

### Task 4: 接线到 ViewModel / WorkspaceShellView

**Files:**
- Modify: `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceShellView.swift`

**Step 1: Write or adapt failing test**

最小覆盖：
- `codexDisplayCandidates` 会纳入 running + waiting pane
- `WorkspaceShellView` 使用 refresher state 持续刷新

**Step 2: Run tests to verify they fail**

Run:
- `swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests`
- `swift test --package-path macos --filter WorkspaceShellViewTests`

Expected: FAIL，当前仅扫描 running pane，且无观测 state。

**Step 3: Write minimal implementation**

- ViewModel 暴露新的 Codex 展示态候选 pane 集合；
- `WorkspaceShellView` 持有 refresher runtime state 并在 timer 中复用；
- 刷新时把 override 写回 ViewModel。

**Step 4: Run tests to verify they pass**

Run:
- `swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests`
- `swift test --package-path macos --filter WorkspaceShellViewTests`

Expected: PASS

### Task 5: 同步文档并做定向验证

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`
- Modify: `tasks/lessons.md`

**Step 1: Update docs**

补充：
- Codex 当前主链已升级为 `wrapper + notify + signal + App fallback`
- App 可见文本 heuristic 仅为 fallback，不是主真相源

**Step 2: Run focused verification**

Run:
- `swift test --package-path macos --filter WorkspaceCodexNotifyScriptTests`
- `swift test --package-path macos --filter WorkspaceAgentWrapperScriptTests`
- `swift test --package-path macos --filter CodexAgentDisplayHeuristicsTests`
- `swift test --package-path macos --filter CodexAgentDisplayStateRefresherTests`
- `swift test --package-path macos --filter WorkspaceShellViewTests`
- `swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests`

Expected: PASS

**Step 3: Run build verification**

Run: `swift build --package-path macos`
Expected: PASS

**Step 4: Update Review**

在 `tasks/todo.md` 回填：
- 直接原因
- 设计层诱因
- 当前修复方案
- 长期建议
- 验证证据
