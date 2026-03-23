# DevHaven Ghostty 搜索浮层右上角定位 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将 DevHaven 当前 Ghostty 搜索浮层从左上角改为固定显示在 terminal 区域右上角。

**Architecture:** 不改搜索行为，只在 `GhosttySurfaceHost` 中调整搜索浮层的宿主布局，使其使用 `topTrailing` 对齐。startup overlay 保持原位，搜索浮层单独右上角对齐。

**Tech Stack:** SwiftUI、XCTest、Swift Package Manager

---

### Task 1: 为右上角定位补失败测试

**Files:**
- Modify: `macos/Tests/DevHavenAppTests/GhosttySurfaceSearchOverlayTests.swift`

**Step 1: 写失败测试**

新增断言，要求 `GhosttySurfaceHost.swift` 中搜索浮层显式使用 `topTrailing` 对齐，而不是继续沿用默认左上角布局。

**Step 2: 运行测试验证确实失败**

Run:
```bash
swift test --package-path macos --filter GhosttySurfaceSearchOverlayTests
```

Expected: FAIL，提示搜索浮层尚未固定到右上角。

### Task 2: 实现最小定位调整

**Files:**
- Modify: `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceHost.swift`

**Step 1: 仅调整搜索浮层的宿主布局**

- 保持 `GhosttySurfaceSearchOverlay.swift` 内容不变；
- 让搜索浮层单独以 `topTrailing` 对齐；
- 不影响 startup overlay。

### Task 3: 运行验证并记录

**Files:**
- Modify: `tasks/todo.md`

**Step 1: 跑定向测试**

Run:
```bash
swift test --package-path macos --filter GhosttySurfaceSearchOverlayTests
```

Expected: PASS

**Step 2: 跑构建验证**

Run:
```bash
swift build --package-path macos
```

Expected: exit 0

**Step 3: 更新 Review**

记录：
- 直接原因
- 当前修复方案
- 验证证据
