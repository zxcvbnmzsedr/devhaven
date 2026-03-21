# DevHaven Ghostty Scroll Input Alignment Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 修复 Ghostty 终端滚动过快的问题，让 DevHaven 的滚轮/触控板输入语义与 Ghostty 原生和 Supacode 对齐。

**Architecture:** 保持现有 `GhosttySurfaceScrollView` scrollbar wrapper 不动，只修 `GhosttySurfaceView.scrollWheel(with:)` 这一层输入桥。通过新增一个最小的 scroll input helper，把 precise scroll 的 delta 调整与 `precision + momentumPhase` 的 mods 编码收口成可测试逻辑，再让 `scrollWheel(with:)` 调用该 helper。

**Tech Stack:** Swift, SwiftPM, AppKit, XCTest, GhosttyKit C bridge

---

### Task 1: 对齐 Ghostty scrollWheel 输入桥

**Files:**
- Create: `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceScrollInput.swift`
- Modify: `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceView.swift`
- Test: `macos/Tests/DevHavenAppTests/GhosttySurfaceScrollInputTests.swift`

**Step 1: Write the failing test**

新增测试覆盖两件事：
1. precise scrolling 时 delta 需要按 Ghostty/Supacode 规则乘 2；
2. `ghostty_input_scroll_mods_t` 必须编码 `precision` 与 `momentumPhase`，而不是复用键盘 modifiers。

**Step 2: Run test to verify it fails**

Run: `swift test --package-path macos --filter GhosttySurfaceScrollInputTests`
Expected: FAIL，原因是 helper 尚不存在或行为未实现。

**Step 3: Write minimal implementation**

新增 `GhosttySurfaceScrollInput` helper，提供：
- delta 调整
- scroll mods 编码

然后让 `GhosttySurfaceView.scrollWheel(with:)` 改为使用该 helper。

**Step 4: Run test to verify it passes**

Run: `swift test --package-path macos --filter GhosttySurfaceScrollInputTests`
Expected: PASS

**Step 5: Run broader verification**

Run: `swift test --package-path macos`
Expected: 全绿

**Step 6: Update task tracking**

同步更新 `tasks/todo.md` 的 checklist 和 Review，写清：
- 直接原因
- 是否存在设计层诱因
- 当前修复
- 验证证据
