# DevHaven 主界面初始焦点修复 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让 DevHaven 进入主界面时默认把键盘焦点放到顶部搜索框，而不是让左侧“目录操作”按钮抢到初始焦点。

**Architecture:** 在 `MainContentView` 内增加显式搜索框 focus state，并在主界面出现时异步请求搜索框焦点。同时给 `ProjectSidebarView` 的“目录操作”按钮增加 `.focusable(false)`，避免它继续参与默认焦点竞争。该修复只调整主界面焦点语义，不改窗口激活或工作区终端焦点链路。

**Tech Stack:** SwiftUI、AppKit、XCTest、Swift Package Manager

---

### Task 1: 为搜索框补焦点策略测试

**Files:**
- Modify: `macos/Tests/DevHavenAppTests/MainContentViewTests.swift`
- Test: `macos/Tests/DevHavenAppTests/MainContentViewTests.swift`

**Step 1: 写失败测试**

在 `MainContentViewTests` 中新增断言，要求：
- `MainContentView.swift` 中声明 `@FocusState`；
- 搜索框 `TextField("搜索项目...", ...)` 绑定 `.focused(...)`；
- 主界面会请求把焦点设到搜索框。

**Step 2: 运行测试验证确实失败**

Run:
```bash
swift test --package-path macos --filter MainContentViewTests/testMainContentRequestsInitialFocusForSearchField
```

Expected: FAIL，提示主界面还没有为搜索框声明显式初始焦点策略。

### Task 2: 为目录操作按钮补防抢焦点测试

**Files:**
- Modify: `macos/Tests/DevHavenAppTests/ProjectSidebarViewTests.swift`
- Test: `macos/Tests/DevHavenAppTests/ProjectSidebarViewTests.swift`

**Step 1: 写失败测试**

新增一个源码级测试，断言 `ProjectSidebarView.swift` 中目录操作 `Menu` 的 label/button 使用了 `.focusable(false)`。

**Step 2: 运行测试验证确实失败**

Run:
```bash
swift test --package-path macos --filter ProjectSidebarViewTests
```

Expected: FAIL，提示目录操作按钮仍可能参与默认焦点竞争。

### Task 3: 实现最小焦点修复

**Files:**
- Modify: `macos/Sources/DevHavenApp/MainContentView.swift`
- Modify: `macos/Sources/DevHavenApp/ProjectSidebarView.swift`

**Step 1: 在主界面增加焦点字段**

- 新增 `MainContentFocusableField`（或等价轻量枚举）；
- 使用 `@FocusState` 绑定到搜索框。

**Step 2: 在主界面出现时请求搜索框焦点**

- 以最小方式在 `MainContentView` 中触发一次异步焦点请求；
- 只在主界面语义下生效，不扩散到 workspace / sheet。

**Step 3: 给目录操作按钮加 `.focusable(false)`**

- 仅处理“目录操作”按钮，避免无关扩散。

### Task 4: 运行验证

**Files:**
- Test: `macos/Tests/DevHavenAppTests/MainContentViewTests.swift`
- Test: `macos/Tests/DevHavenAppTests/ProjectSidebarViewTests.swift`

**Step 1: 跑定向测试**

Run:
```bash
swift test --package-path macos --filter MainContentViewTests
swift test --package-path macos --filter ProjectSidebarViewTests
```

Expected: PASS

**Step 2: 跑相关构建验证**

Run:
```bash
swift build --package-path macos
```

Expected: Build complete，exit 0

### Task 5: 更新任务记录

**Files:**
- Modify: `tasks/todo.md`

**Step 1: 勾选 checklist 并追加 Review**

记录：
- 直接原因
- 是否存在设计层诱因
- 当前修复方案
- 长期改进建议
- 测试 / 构建证据
