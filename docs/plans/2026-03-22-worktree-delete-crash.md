# Worktree Delete Crash Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 修复删除 worktree 时 Ghostty 晚到回调命中已释放 bridge 导致的闪退，并补齐回归测试。

**Architecture:** 保持现有 `WorkspaceShellView -> WorkspaceTerminalSessionStore -> GhosttySurfaceHostModel -> GhosttyRuntime` 主链不变，只把 surface userdata 从裸 bridge 指针升级为稳定的 callback context。runtime 跨线程时只传递 context，主线程执行时再解析 active bridge；teardown 开始后立即 invalidation，让晚到 callback 统一 no-op。

**Tech Stack:** Swift、XCTest、SwiftUI/AppKit、GhosttyKit、Foundation、Dispatch

---

### Task 1: 为 callback context 生命周期补失败测试

**Files:**
- Create: `macos/Tests/DevHavenAppTests/GhosttySurfaceCallbackContextTests.swift`
- Test: `macos/Tests/DevHavenAppTests/GhosttySurfaceCallbackContextTests.swift`

**Step 1: Write the failing test**
- 新增测试 1：创建 `GhosttySurfaceBridge` 与 `GhosttySurfaceCallbackContext`，断言 context 在 active 状态下可以返回 bridge；`invalidate()` 后应返回 `nil`。
- 新增测试 2：把 context 捕获进 `DispatchQueue.main.async`，在 block 执行前先 `invalidate()`；断言异步 hop 到主线程后拿不到 active bridge。

**Step 2: Run test to verify it fails**
Run: `swift test --package-path macos --filter GhosttySurfaceCallbackContextTests`
Expected: FAIL，当前代码还没有 callback context 类型与对应行为。

**Step 3: Write minimal implementation**
- 新增 `GhosttySurfaceCallbackContext`，只提供线程安全的 `activeBridge()` / `invalidate()` 能力；
- 不在这一轮引入更大的 actor / queue 重构。

**Step 4: Run test to verify it passes**
Run: `swift test --package-path macos --filter GhosttySurfaceCallbackContextTests`
Expected: PASS

### Task 2: 把 Ghostty runtime / surface 切到 callback context

**Files:**
- Create: `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceCallbackContext.swift`
- Modify: `macos/Sources/DevHavenApp/Ghostty/GhosttyRuntime.swift`
- Modify: `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceView.swift`

**Step 1: Wire userdata through context**
- 在 `GhosttyTerminalSurfaceView` 创建 bridge 后同步创建 callback context；
- `GhosttyTerminalSurfaceConfiguration.withCValue(...)` 的 `userdata` 改为 context，而不是 bridge。

**Step 2: Keep context alive with the surface**
- 调整 `GhosttyRuntime.SurfaceReference` / `registerSurface(...)`，让 surface 存活期间 context 也有稳定强引用；
- `tearDown()` 开始时先 invalidation，再继续 unregister/free surface。

**Step 3: Update runtime callbacks**
- `handleAction(...)`、`handleCloseSurface(...)`、clipboard 相关回调统一从 userdata 解析 callback context；
- 跨线程时捕获 context，主线程执行时再读取 active bridge；
- 若 context 已失效，则安全 no-op。

**Step 4: Run focused Ghostty tests**
Run: `swift test --package-path macos --filter 'GhosttySurface(CallbackContext|BridgeTabPane|Host)Tests'`
Expected: PASS

### Task 3: 同步文档并完成验证闭环

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`

**Step 1: Update architecture note**
- 在 `AGENTS.md` 补充 Ghostty callback context 的职责边界：surface userdata 不再直接暴露 bridge，跨线程回调必须经由稳定 context。

**Step 2: Run full verification**
Run: `swift test --package-path macos`
Expected: PASS；若失败，必须记录真实失败点，不能直接宣称修复完成。

**Step 3: Update task review**
- 在 `tasks/todo.md` 回填 Review，记录：
  1. 直接原因；
  2. 是否存在设计层诱因；
  3. 当前修复方案；
  4. 长期改进建议；
  5. 验证证据。
