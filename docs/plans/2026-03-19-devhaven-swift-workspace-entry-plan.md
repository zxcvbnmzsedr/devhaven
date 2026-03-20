# DevHaven Swift Workspace Entry Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让 Swift 原生版恢复一条可进入 workspace 的主路径，并在 workspace 页面提供可用的系统 Terminal 入口。

**Architecture:** 保持当前“单击开详情抽屉”语义不变，新增“双击进入 workspace 页面”作为并行入口。workspace 页面先复用现有 `WorkspacePlaceholderView`，并通过 `NativeAppViewModel` 承载进入/退出与系统 Terminal 打开动作。

**Tech Stack:** SwiftUI, AppKit/Foundation Process, XCTest

---

### Task 1: 锁定 workspace 状态机

**Files:**
- Modify: `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`
- Test: `macos/Tests/DevHavenCoreTests/NativeAppViewModelWorkspaceEntryTests.swift`

**Step 1: Write the failing test**
- 断言 `enterWorkspace(path)` 会记录当前 workspace 项目
- 断言 `exitWorkspace()` 会清空 workspace 状态

**Step 2: Run test to verify it fails**
Run: `swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests`

**Step 3: Write minimal implementation**
- 在 view model 新增 workspace 选中状态与进入/退出方法

**Step 4: Run test to verify it passes**
Run: `swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests`

### Task 2: 落地系统 Terminal 打开动作

**Files:**
- Modify: `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`
- Test: `macos/Tests/DevHavenCoreTests/NativeAppViewModelWorkspaceEntryTests.swift`

**Step 1: Write the failing test**
- 断言打开 Terminal 时会构造 `/usr/bin/open -a Terminal <path>`
- 断言失败时会写入 `errorMessage`

**Step 2: Run test to verify it fails**
Run: `swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests`

**Step 3: Write minimal implementation**
- 注入轻量 process runner，默认执行 `open -a Terminal`

**Step 4: Run test to verify it passes**
Run: `swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests`

### Task 3: 挂回 workspace 页面

**Files:**
- Modify: `macos/Sources/DevHavenApp/AppRootView.swift`
- Modify: `macos/Sources/DevHavenApp/MainContentView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspacePlaceholderView.swift`

**Step 1: Write the failing test or behavior lock**
- 如无视图测试基础，先通过 Task 1/2 锁定状态机，再做最小 UI 改动

**Step 2: Write minimal implementation**
- `AppRootView` 中央区域按 workspace 状态切换
- `MainContentView` 支持双击进入 workspace
- `WorkspacePlaceholderView` 提供打开 Terminal / 返回列表 / 查看详情按钮

**Step 3: Verify**
Run: `swift test --package-path macos`
Run: `swift build --package-path macos`
Run: `git diff --check`
