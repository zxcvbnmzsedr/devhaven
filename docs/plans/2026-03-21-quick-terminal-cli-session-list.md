# Quick Terminal CLI 会话列表 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 把左侧“CLI 会话”区块改成真实 quick terminal 会话列表，并让 workspace 左侧 quick terminal group 不再暴露错误的 worktree 操作。

**Architecture:** 保持单 quick terminal session 模型不变，继续以 `openWorkspaceSessions` 作为 session 真相源。通过在 `NativeAppViewModel` 收口 quick terminal session 列表，再分别更新全局 sidebar 与 workspace sidebar 的展示逻辑，实现“会话状态一致 + 错误按钮下线”。

**Tech Stack:** SwiftUI、Swift Package、DevHavenCore ViewModel / Models、XCTest

---

### Task 1: 收口 quick terminal 会话真相源

**Files:**
- Modify: `macos/Sources/DevHavenCore/Models/AppModels.swift`
- Modify: `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`
- Test: `macos/Tests/DevHavenCoreTests/NativeAppViewModelWorkspaceEntryTests.swift`

**Step 1: Write the failing test**

- 新增 quick terminal session 列表相关断言：
  - quick terminal item 来自 `openWorkspaceSessions`
  - 重复调用 `openQuickTerminal()` 不应重复创建 session
  - `exitWorkspace()` 后 item 仍保留且状态为“可恢复”

**Step 2: Run test to verify it fails**

Run:

```bash
swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests
```

Expected:
- 新增断言失败，说明当前 `cliSessionItems` 仍不是基于 quick terminal session 构建

**Step 3: Write minimal implementation**

- 为 `Project` 增加 quick terminal 判定；
- 让 `cliSessionItems` 改为从 `openWorkspaceSessions.filter(\.isQuickTerminal)` 构建；
- 让 `openQuickTerminal()` 在已有 session 时只激活，不重复创建。

**Step 4: Run test to verify it passes**

Run:

```bash
swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests
```

Expected:
- PASS

### Task 2: 更新全局 sidebar 的 CLI 会话区块

**Files:**
- Modify: `macos/Sources/DevHavenApp/ProjectSidebarView.swift`
- Test: `macos/Tests/DevHavenAppTests/ProjectSidebarViewTests.swift`

**Step 1: Write the failing test**

- 增加源码级断言，锁定：
  - “CLI 会话”区块继续读取 `viewModel.cliSessionItems`
  - item 卡片应能激活 quick terminal session
  - item 卡片应提供关闭 quick terminal session 的入口

**Step 2: Run test to verify it fails**

Run:

```bash
swift test --package-path macos --filter ProjectSidebarViewTests
```

Expected:
- FAIL，说明当前 sidebar 尚未提供真实 quick terminal 会话交互

**Step 3: Write minimal implementation**

- 把 CLI 会话 item 改成真实可点击卡片；
- 提供恢复/激活与关闭按钮；
- 空状态文案改为真实 session 语义。

**Step 4: Run test to verify it passes**

Run:

```bash
swift test --package-path macos --filter ProjectSidebarViewTests
```

Expected:
- PASS

### Task 3: 隐藏 quick terminal 的 worktree 错误按钮

**Files:**
- Modify: `macos/Sources/DevHavenApp/WorkspaceProjectListView.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceProjectListViewTests.swift`

**Step 1: Write the failing test**

- 新增源码级断言，锁定 quick terminal group 不应显示：
  - `arrow.clockwise`
  - `plus`
  这两个 worktree 相关按钮

**Step 2: Run test to verify it fails**

Run:

```bash
swift test --package-path macos --filter WorkspaceProjectListViewTests
```

Expected:
- FAIL，说明 quick terminal 仍被当普通项目渲染

**Step 3: Write minimal implementation**

- 在 `WorkspaceProjectListView` 中基于 quick terminal 判定隐藏错误按钮；
- 保留激活与关闭。

**Step 4: Run test to verify it passes**

Run:

```bash
swift test --package-path macos --filter WorkspaceProjectListViewTests
```

Expected:
- PASS

### Task 4: 运行回归验证并同步任务记录

**Files:**
- Modify: `tasks/todo.md`
- Modify: `tasks/lessons.md`

**Step 1: Run focused verification**

Run:

```bash
swift test --package-path macos --filter 'NativeAppViewModelWorkspaceEntryTests|ProjectSidebarViewTests|WorkspaceProjectListViewTests'
```

Expected:
- PASS

**Step 2: Run dev entry verification if needed**

Run:

```bash
./dev --no-log
```

Expected:
- 能进入运行态；确认后手动结束

**Step 3: Update task records**

- 在 `tasks/todo.md` 追加 Review，写明根因、设计层诱因、当前修复、长期建议、验证证据；
- 如有通用教训，同步写入 `tasks/lessons.md`。
