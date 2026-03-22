# Agent Signal Store Hardening Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 修复 Agent signal store 的 completed/failed 状态回落失效与坏文件拖垮整批 reload 的问题，并补齐回归测试。

**Architecture:** 保持 `WorkspaceAgentSignalStore` 作为 signal 扫描与短生命周期状态归一化入口，不扩展新的持久化层。通过最小改动把“定时归一化”从“是否删除 stale active signal”解耦，并让单文件解码失败局部化，避免拖垮整批 snapshot 刷新。

**Tech Stack:** Swift、XCTest、Foundation、DispatchSource

---

### Task 1: 为 completed/failed retention 回落补失败测试

**Files:**
- Modify: `macos/Tests/DevHavenCoreTests/WorkspaceAgentSignalStoreTests.swift`
- Test: `macos/Tests/DevHavenCoreTests/WorkspaceAgentSignalStoreTests.swift`

**Step 1: Write the failing test**
- 新增一个测试：写入 `completed` signal，先 `reloadForTesting()`，再调用 `sweepStaleSignals(now:)`。
- 断言：超过 retention 后状态应回落为 `idle`，并清空 summary/detail/pid。

**Step 2: Run test to verify it fails**
Run: `swift test --package-path macos --filter WorkspaceAgentSignalStoreTests/testCompletedSignalFallsBackToIdleAfterRetentionDuringSweep`
Expected: FAIL，当前实现会继续保留 `completed`。

**Step 3: Write minimal implementation**
- 调整 `WorkspaceAgentSignalStore.sweepStaleSignals(...)`，让每次 sweep 都执行 snapshot 归一化，而不是只在删除 stale active signal 时归一化。

**Step 4: Run test to verify it passes**
Run: `swift test --package-path macos --filter WorkspaceAgentSignalStoreTests/testCompletedSignalFallsBackToIdleAfterRetentionDuringSweep`
Expected: PASS

### Task 2: 为坏 signal 文件容错补失败测试

**Files:**
- Modify: `macos/Tests/DevHavenCoreTests/WorkspaceAgentSignalStoreTests.swift`
- Test: `macos/Tests/DevHavenCoreTests/WorkspaceAgentSignalStoreTests.swift`

**Step 1: Write the failing test**
- 新增一个测试：目录中同时写入一个合法 signal 和一个损坏的 JSON 文件。
- 断言：`reloadForTesting()` 不抛错，合法 signal 仍然能被加载。

**Step 2: Run test to verify it fails**
Run: `swift test --package-path macos --filter WorkspaceAgentSignalStoreTests/testReloadSkipsMalformedSignalFilesAndKeepsValidSnapshots`
Expected: FAIL，当前实现会抛 `DecodingError`。

**Step 3: Write minimal implementation**
- 在 `WorkspaceAgentSignalStore.reload(now:)` 中改为逐文件解码；单文件失败时跳过该文件，避免整批 reload 失败。
- 不在这一轮引入 quarantine 或额外持久化日志，保持最小改动。

**Step 4: Run test to verify it passes**
Run: `swift test --package-path macos --filter WorkspaceAgentSignalStoreTests/testReloadSkipsMalformedSignalFilesAndKeepsValidSnapshots`
Expected: PASS

### Task 3: 运行定向回归与必要全量验证

**Files:**
- Modify: `tasks/todo.md`

**Step 1: Run focused regression tests**
Run: `swift test --package-path macos --filter WorkspaceAgentSignalStoreTests`
Expected: PASS

**Step 2: Run broader verification**
Run: `swift test --package-path macos`
Expected: 尽可能拿到新的全量结论；若仍失败，必须记录失败位置与证据，不能直接声称全部通过。

**Step 3: Update task record**
- 在 `tasks/todo.md` 回填 Review，记录直接原因、设计层诱因、修复方案、长期建议与验证证据。
