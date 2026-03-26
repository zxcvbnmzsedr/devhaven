# Codex Display Activity Window Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 把 Codex 展示态 fallback 从“每秒整屏读回终端可见文本”改为“按内容失效脉冲维护 pane 级最近文本窗口”，降低长期内存占用并保留 running / waiting 展示修正能力。

**Architecture:** `GhosttyRuntime.tick()` 之后仅向活跃 surface 广播内容失效脉冲；`GhosttySurfaceHostModel` 在 Codex tracking 开启时 debounce 更新最近文本窗口；`CodexAgentDisplayStateRefresher` 与 `WorkspaceShellView` 只消费内存中的轻量 snapshot，不再在展示刷新链路触发 `debugVisibleText()`。

**Tech Stack:** Swift 6, SwiftUI, GhosttyKit, DevHavenCore, XCTest

---

### Task 1: 为 Codex 展示态定义轻量 snapshot 与窗口更新规则

**Files:**
- Create: `macos/Sources/DevHavenApp/CodexAgentDisplaySnapshot.swift`
- Modify: `macos/Sources/DevHavenApp/CodexAgentDisplayStateRefresher.swift`
- Test: `macos/Tests/DevHavenAppTests/CodexAgentDisplayStateRefresherTests.swift`

**Steps:**
1. 先写 failing tests，约束：
   - refresher 改为消费 pane snapshot，而不是直接消费全文字符串；
   - waiting / running 的现有 heuristic 在 snapshot 输入下保持不变；
   - runtime observation 只依赖窗口文本与活动时间。
2. 运行定向测试，确认红灯。
3. 新增 `CodexAgentDisplaySnapshot`（最近文本窗口 + 最近活动时间）。
4. 更新 refresher 测试与实现，使其读取 snapshot。
5. 运行定向测试转绿。

### Task 2: 在 Ghostty host/runtime 链路上接入内容失效脉冲与窗口缓存

**Files:**
- Modify: `macos/Sources/DevHavenApp/Ghostty/GhosttyRuntime.swift`
- Modify: `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceBridge.swift`
- Modify: `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceHost.swift`
- Test: `macos/Tests/DevHavenAppTests/GhosttySurfaceHostModelSnapshotTests.swift`
- Add/Modify: `macos/Tests/DevHavenAppTests/GhosttySurfaceBridge...` 相关测试（如需要）

**Steps:**
1. 先写 failing tests，约束：
   - HostModel 可在 tracking 开启时维护最近文本窗口；
   - 关闭 tracking / releaseSurface 会清空窗口并取消 pending refresh；
   - 内容失效脉冲不会直接暴露整屏文本。
2. 运行定向测试，确认红灯。
3. 在 runtime tick 后广播内容失效回调。
4. 在 bridge / host model 上接入 debounce 更新与窗口裁剪逻辑。
5. 运行定向测试转绿。

### Task 3: 用 snapshot 替换 WorkspaceShellView 中的全文本读取

**Files:**
- Modify: `macos/Sources/DevHavenApp/WorkspaceShellView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceTerminalSessionStore.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceShellViewTests.swift`

**Steps:**
1. 先写 failing tests，约束：
   - `WorkspaceShellView` 刷新 Codex 展示态时不再调用 `currentVisibleText()`；
   - 会为当前 Codex 展示候选 pane 打开/关闭 tracking；
   - refresher 输入改成 snapshot provider。
2. 运行定向测试，确认红灯。
3. 更新 shell/store 接线，使 refresher 读取 `codexDisplaySnapshot()`。
4. 保持刷新入口轻量，不在 UI 刷新链路触发整屏读回。
5. 运行定向测试转绿。

### Task 4: 文档与回归验证

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`

**Steps:**
1. 更新 `AGENTS.md`，记录 Codex 展示态 fallback 已改为“signal + notify 主链 + host 内存窗口 fallback”，并强调不能在 sidebar 刷新链路读取整屏可见文本。
2. 运行定向测试：
   - `swift test --package-path macos --filter 'CodexAgentDisplayStateRefresherTests|GhosttySurfaceHostModelSnapshotTests|WorkspaceShellViewTests|WorkspaceAgentStatusAccessoryTests|NativeAppViewModelWorkspaceEntryTests'`
3. 运行 `swift build --package-path macos`。
4. 在 `tasks/todo.md` 回填直接原因、设计层诱因、当前修复、长期建议、验证证据。
