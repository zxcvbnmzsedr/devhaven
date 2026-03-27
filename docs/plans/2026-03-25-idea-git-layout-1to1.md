# IDEA Git 布局 1:1 复刻 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 把 DevHaven Git 工具窗主布局调整为更接近 IntelliJ IDEA 的 `Git / Log / Console` 顶层结构，以及 IntelliJ 风格的 Log 主壳层级。

**Architecture:** 保持 `WorkspaceGitLogViewModel` 与现有 Git 数据链路不变，只在 App 层重排根布局、顶层 tab strip、branches 外壳与 MainFrame 归属。`Console` 先做 runtime-only 占位，避免本轮把范围扩展到真实 Git 命令日志后端。

**Tech Stack:** SwiftUI、现有 source-based XCTest、DevHavenCore ViewModel。

---

### Task 1: 锁定 Git 工具窗顶层结构红灯

**Files:**
- Modify: `macos/Tests/DevHavenAppTests/WorkspaceGitRootViewTests.swift`
- Modify: `macos/Tests/DevHavenAppTests/WorkspaceGitIdeaLogViewTests.swift`

**Step 1: 写失败测试**

补 source-based 断言，要求：
- `WorkspaceGitRootView` 存在 `Git / Log / Console` 顶层 tab strip；
- `WorkspaceGitIdeaLogView` 把 toolbar 放进 MainFrame 左侧而非整个页面顶层；
- `WorkspaceGitRootView` 存在 Console 占位视图路由。

**Step 2: 跑测试确认红灯**

Run: `swift test --package-path macos --filter 'WorkspaceGitRootViewTests|WorkspaceGitIdeaLogViewTests'`
Expected: FAIL，提示缺少顶层 tab strip / Console 路由 / MainFrame 结构契约。

**Step 3: 最小实现范围确认**

确认本轮仅实现：
- 顶层 tab strip；
- Log 主壳层重排；
- Console 占位视图。

**Step 4: 提交点前不写生产代码以外内容**

保持红灯结果可复现，再进入实现。

### Task 2: 实现 Git / Log / Console 根路由

**Files:**
- Modify: `macos/Sources/DevHavenCore/Models/WorkspaceGitModels.swift`
- Modify: `macos/Sources/DevHavenCore/ViewModels/WorkspaceGitViewModel.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitRootView.swift`
- Create: `macos/Sources/DevHavenApp/WorkspaceGitConsoleView.swift`

**Step 1: 新增顶层 tab 模型**

在 Core 层新增 Git 工具窗顶层 tab 枚举，区分：
- `git`
- `log`
- `console`

**Step 2: 在 ViewModel 暴露顶层 tab 状态**

给 `WorkspaceGitViewModel` 增加：
- 当前顶层 tab
- 切换顶层 tab 的 API
- 让现有 `section` 仅服务于 `Git` 顶层 tab 的二级内容

**Step 3: 在 RootView 实现顶层 tab strip**

把 `WorkspaceGitRootView` 改为：
- 顶层 tab strip
- 主体路由到 Git / Log / Console

**Step 4: 增加 Console 占位视图**

新增 `WorkspaceGitConsoleView`，提供明确中文空态。

**Step 5: 运行测试确认转绿**

Run: `swift test --package-path macos --filter 'WorkspaceGitRootViewTests|WorkspaceGitIdeaLogViewTests'`
Expected: PASS

### Task 3: 重排 IDEA Log 主壳

**Files:**
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitIdeaLogView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitIdeaLogToolbarView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitIdeaLogRightSidebarView.swift`

**Step 1: 写最小重排实现**

把 `.log` 改成：
- 左侧 stripe
- 可展开 branches panel
- MainFrame（左 toolbar+table，右 sidebar）

**Step 2: 明确 toolbar 归属**

让 toolbar 只出现在 MainFrame 左列顶部，不再是整个 `.log` 顶层通栏。

**Step 3: 保持 right sidebar 联动不变**

不要改动 `WorkspaceGitLogViewModel` 的 commit/file selection 主链。

**Step 4: 跑定向测试**

Run: `swift test --package-path macos --filter 'WorkspaceGitIdeaLogViewTests|WorkspaceGitRootViewTests|WorkspaceGitLogViewModelTests'`
Expected: PASS

### Task 4: 回归验证与文档同步

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`

**Step 1: 若有新增文件/职责变更，更新 AGENTS.md**

记录：
- Git 工具窗顶层 tab 结构
- `WorkspaceGitConsoleView` 的职责边界
- `WorkspaceGitRootView` 新的层级关系

**Step 2: 更新任务记录**

把实现 checklist、Review、验证证据回填到 `tasks/todo.md`。

**Step 3: 跑最终验证**

Run: `swift test --package-path macos --filter 'WorkspaceGitRootViewTests|WorkspaceGitIdeaLogViewTests|WorkspaceGitLogViewModelTests|WorkspaceGitRootViewTests|WorkspaceShellViewGitModeTests'`
Expected: 全绿

Run: `git diff --check`
Expected: exit 0

**Step 4: 整理验收说明**

输出：
- 变更摘要
- 直接原因 / 设计层诱因
- 验证证据
- 后续可继续抠视觉的点
