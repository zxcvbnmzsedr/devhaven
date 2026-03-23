# DevHaven Ghostty 搜索功能 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 DevHaven 内嵌 Ghostty 终端补齐可用的搜索闭环，支持查找、上下一个、隐藏查找栏和使用所选内容查找。

**Architecture:** 复用现有 `ghostty_surface_binding_action(...)` 通道，在 `GhosttySurfaceState` / `GhosttySurfaceBridge` 中补搜索状态与 action 翻译；在 `GhosttySurfaceHost` 上层叠加轻量搜索浮层；通过 `FocusedValue + Commands` 把 App 菜单动作路由到当前 focused pane 的 `GhosttySurfaceHostModel`。

**Tech Stack:** SwiftUI、AppKit、GhosttyKit/libghostty、XCTest、Swift Package Manager

---

### Task 1: 为搜索 bridge 状态补失败测试

**Files:**
- Modify: `macos/Tests/DevHavenAppTests/GhosttySurfaceBridgeTabPaneTests.swift`

**Step 1: 写失败测试**

新增断言，要求：
- `GHOSTTY_ACTION_START_SEARCH` 会设置 `searchNeedle` 并刷新 `searchFocusCount`；
- `GHOSTTY_ACTION_SEARCH_TOTAL` / `SEARCH_SELECTED` 会更新计数；
- `GHOSTTY_ACTION_END_SEARCH` 会清空搜索状态。

**Step 2: 运行测试验证确实失败**

Run:
```bash
swift test --package-path macos --filter GhosttySurfaceBridgeTabPaneTests
```

Expected: FAIL，提示 `GhosttySurfaceState` 尚无搜索字段或 `GhosttySurfaceBridge` 尚未处理相关 action。

### Task 2: 为菜单与场景入口补失败测试

**Files:**
- Modify: `macos/Tests/DevHavenAppTests/DevHavenAppCommandTests.swift`
- Create: `macos/Tests/DevHavenAppTests/WorkspaceTerminalCommandsTests.swift`

**Step 1: 写失败测试**

新增断言，要求：
- `DevHavenApp.swift` 暴露“查找… / 查找下一个 / 查找上一个 / 隐藏查找栏 / 使用所选内容查找”；
- Workspace 场景提供 focused search action，并把动作路由到当前 active pane。

**Step 2: 运行测试验证确实失败**

Run:
```bash
swift test --package-path macos --filter DevHavenAppCommandTests
swift test --package-path macos --filter WorkspaceTerminalCommandsTests
```

Expected: FAIL，提示当前没有查找菜单与 focused action 挂接。

### Task 3: 为搜索浮层补失败测试

**Files:**
- Create: `macos/Tests/DevHavenAppTests/GhosttySurfaceSearchOverlayTests.swift`

**Step 1: 写失败测试**

新增源码级测试，要求：
- 存在 `GhosttySurfaceSearchOverlay.swift`；
- `GhosttySurfaceHost.swift` 会在搜索激活时叠加 overlay；
- overlay 内部通过 `search:<needle>`、`navigate_search:*`、`end_search` 调用 surface binding action。

**Step 2: 运行测试验证确实失败**

Run:
```bash
swift test --package-path macos --filter GhosttySurfaceSearchOverlayTests
```

Expected: FAIL，提示搜索浮层文件或 overlay 挂接尚不存在。

### Task 4: 实现最小搜索状态与导航能力

**Files:**
- Modify: `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceState.swift`
- Modify: `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceBridge.swift`
- Modify: `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceHost.swift`
- Modify: `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceView.swift`
- Create: `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceSearchOverlay.swift`

**Step 1: 在 `GhosttySurfaceState` 中增加搜索字段**

- `searchNeedle`
- `searchTotal`
- `searchSelected`
- `searchFocusCount`

**Step 2: 在 `GhosttySurfaceBridge` 中处理 4 个 search action**

- `START_SEARCH`
- `END_SEARCH`
- `SEARCH_TOTAL`
- `SEARCH_SELECTED`

**Step 3: 在 `GhosttySurfaceView` / `GhosttySurfaceHostModel` 中补最小搜索方法**

- `performBindingAction(...)` 继续作为唯一出口；
- 新增 next/previous 导航辅助方法；
- Model 暴露搜索入口给菜单动作复用。

**Step 4: 新增搜索浮层并挂到 host 上**

- 浮层内支持输入、上下一个、关闭；
- 关闭时恢复 terminal 焦点。

### Task 5: 实现菜单 / FocusedValue 路由

**Files:**
- Create: `macos/Sources/DevHavenApp/WorkspaceTerminalCommands.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceShellView.swift`
- Modify: `macos/Sources/DevHavenApp/DevHavenApp.swift`

**Step 1: 定义搜索相关 FocusedValue key**

- `startSearch`
- `searchSelection`
- `navigateSearchNext`
- `navigateSearchPrevious`
- `endSearch`

**Step 2: 在 `WorkspaceShellView` 暴露当前 active pane 的 action**

- 通过 `viewModel.activeWorkspaceController` + `terminalStoreRegistry` 获取当前 pane model；
- action 不可用时返回 `nil`。

**Step 3: 在 `DevHavenApp.swift` 挂接查找菜单**

- 把查找命令放到 `.textEditing` 后；
- 补快捷键；
- action 不可用时禁用。

### Task 6: 更新文档与验证

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`

**Step 1: 更新 AGENTS**

补充搜索相关关键文件与模块职责，避免文档滞后。

**Step 2: 跑定向测试**

Run:
```bash
swift test --package-path macos --filter GhosttySurfaceBridgeTabPaneTests
swift test --package-path macos --filter DevHavenAppCommandTests
swift test --package-path macos --filter WorkspaceTerminalCommandsTests
swift test --package-path macos --filter GhosttySurfaceSearchOverlayTests
```

Expected: PASS

**Step 3: 跑相关构建验证**

Run:
```bash
swift build --package-path macos
```

Expected: exit 0

**Step 4: 更新 Review**

在 `tasks/todo.md` 记录：
- 直接原因
- 设计层诱因
- 当前修复方案
- 长期改进建议
- 测试 / 构建证据
