# 修复关闭右侧项目详情面板导致未响应 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 修复点击关闭右侧项目详情面板后应用未响应的问题，并补上可复现的自动化回归测试。

**Architecture:** 先定位项目详情面板的关闭入口、所依赖的状态源，以及是否存在 SwiftUI / AppKit 双向联动导致的重入或主线程阻塞。随后以测试先行锁定“关闭面板后主界面仍可继续响应”的边界，只对根因所在模块做最小修改，避免扩散到无关工作区或终端逻辑。

**Tech Stack:** SwiftUI、AppKit、Swift Package Manager、XCTest

---

### Task 1: 复现与根因定位

**Files:**
- Inspect: `macos/Sources/DevHavenApp/ProjectDetailRootView.swift`
- Inspect: `macos/Sources/DevHavenApp/MainContentView.swift`
- Inspect: `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`
- Test: `macos/Tests/DevHavenAppTests/*`

**Step 1: 找到关闭项目详情面板的 UI 入口**

用符号搜索 / 文本搜索确认右侧详情面板由哪个视图控制显示与关闭，以及按钮 action 最终落到哪个状态字段。

**Step 2: 复盘数据流与线程边界**

检查关闭动作是否同步触发了：
- 选中项目清空
- 列表/详情双向绑定
- `NavigationSplitView` / `HSplitView` / `NSSplitView` 重新布局
- 与终端工作区或 project detail 相关的副作用

**Step 3: 写下单一根因假设**

明确记录“我认为 root cause 是 X，因为 Y”。如果当前证据不足，先继续加日志/测试，不进入修复。

### Task 2: 先写失败测试

**Files:**
- Modify: `macos/Tests/DevHavenAppTests/...`（定位后填入具体测试文件）

**Step 1: 写最小失败测试**

优先选择已有 ViewModel / UI policy 测试文件，写出“关闭详情面板后不会出现递归状态震荡 / 选中状态能安全清空 / 视图构建不死循环”的最小用例。

**Step 2: 运行定向测试确认 RED**

Run: `swift test --package-path macos --filter <具体测试名>`
Expected: 因当前实现缺陷而失败，而不是编译错误或无关异常。

### Task 3: 最小实现修复

**Files:**
- Modify: `macos/Sources/DevHavenApp/...` 或 `macos/Sources/DevHavenCore/...`（以根因定位结果为准）

**Step 1: 只修根因，不顺手改别处**

例如若问题是选中状态清空时触发了重入，则只收口状态同步边界；若问题是关闭按钮与详情面板生命周期相互递归，则只打断递归链路。

**Step 2: 运行同一条测试确认 GREEN**

Run: `swift test --package-path macos --filter <具体测试名>`
Expected: PASS

### Task 4: 回归验证与文档同步

**Files:**
- Modify: `tasks/todo.md`
- Modify: `AGENTS.md`（仅当模块职责/架构事实发生变化时）

**Step 1: 运行相关回归**

Run: `swift test --package-path macos --filter <相关测试集合>`
Expected: PASS

**Step 2: 运行必要全量验证**

Run: `swift test --package-path macos`
Expected: PASS

**Step 3: 记录 Review**

把直接原因、设计层诱因、当前修复、长期建议、验证证据写入 `tasks/todo.md`。
