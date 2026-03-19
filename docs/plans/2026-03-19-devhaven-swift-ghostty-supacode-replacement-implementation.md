# DevHaven Swift Ghostty Supacode Replacement Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 用 supacode 风格的 app 级 Ghostty runtime 替换当前 bootstrap/path-locator/pane-runtime 主线。

**Architecture:** 将 Ghostty 资源切到 SwiftPM bundle，启动期统一做一次 `ghostty_init(...)` 并创建共享 runtime；surface 端拆成 runtime / bridge / state / view / representable 五层，workspace 层只消费终端宿主，不再承担资源探测与 runtime 生命周期。

**Tech Stack:** Swift 6、SwiftPM、SwiftUI、AppKit、GhosttyKit。

---

### Task 1: 先锁定 bundle 资源与共享 runtime 行为

**Files:**
- Create: `macos/Tests/DevHavenAppTests/GhosttyAppRuntimeTests.swift`
- Modify: `macos/Package.swift`

**Step 1: 写失败测试**

- 断言 `GhosttyAppRuntime` 能从 bundle 解析 GhosttyResources 路径。
- 断言共享 runtime 为单例语义，重复获取不会创建多个实例。

**Step 2: 运行测试确认失败**

Run: `swift test --package-path macos --filter GhosttyAppRuntimeTests`

**Step 3: 最小实现**

- 为 `DevHavenApp` target 声明 `Vendor/GhosttyResources` bundle resources。
- 新建 `GhosttyAppRuntime.swift`，提供 bundle 资源路径与全局初始化入口。

**Step 4: 重跑测试确认转绿**

Run: `swift test --package-path macos --filter GhosttyAppRuntimeTests`

### Task 2: 拆出 supacode 风格 Ghostty runtime / bridge / state

**Files:**
- Create: `macos/Sources/DevHavenApp/Ghostty/GhosttyRuntime.swift`
- Create: `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceBridge.swift`
- Create: `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceState.swift`
- Modify: `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceView.swift`

**Step 1: 写失败测试**

- 新增或扩展 `GhosttySurfaceHostTests`，锁定共享 runtime 下仍能创建 surface、更新标题/PWD、正确处理 process exit。

**Step 2: 运行测试确认失败**

Run: `DEVHAVEN_RUN_GHOSTTY_SMOKE=1 GHOSTTY_RESOURCES_DIR="$PWD/macos/Vendor/GhosttyResources/ghostty" DEVHAVEN_PROJECT_PATH="$PWD" swift test --package-path macos --filter GhosttySurfaceHostTests`

**Step 3: 最小实现**

- 把 runtime 级 callback 与 observer 从 `GhosttySurfaceHost.swift` 移到 `GhosttyRuntime.swift`。
- 用 `GhosttySurfaceBridge` 承接 action callback，对 host 暴露 title/pwd/renderer/appearance/close 等闭包。
- `GhosttySurfaceView.swift` 改为只负责 surface 与输入链路，不再直接依赖 host model。

**Step 4: 重跑测试确认转绿**

Run: 同上。

### Task 3: 让 workspace 直接使用共享 runtime 主线

**Files:**
- Modify: `macos/Sources/DevHavenApp/DevHavenApp.swift`
- Modify: `macos/Sources/DevHavenApp/AppRootView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceHostView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceTerminalPaneView.swift`
- Delete or stop using: `macos/Sources/DevHavenApp/WorkspacePlaceholderView.swift`
- Delete or stop using: `macos/Sources/DevHavenApp/GhosttyPathLocator.swift`
- Delete or stop using: `macos/Sources/DevHavenCore/Terminal/GhosttyBootstrap.swift`

**Step 1: 写失败测试**

- 让 `WorkspaceHost` / `AppRootView` 相关测试锁定：进入 workspace 后直接走 Ghostty host，不再因为 bootstrap 分支展示 placeholder。

**Step 2: 运行测试确认失败**

Run: `swift test --package-path macos --filter Workspace`

**Step 3: 最小实现**

- `DevHavenApp` 启动时改为直接 bootstrap app 级 Ghostty runtime。
- 移除 `ghosttyBootstrap` 在根视图与 workspace 之间的传递。
- workspace 主路径直接渲染 Ghostty host；初始化失败由 host 内部显示错误卡片。

**Step 4: 重跑测试确认转绿**

Run: `swift test --package-path macos --filter Workspace`

### Task 4: 收口文档、验证与任务记录

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`
- Modify: `/Users/zhaotianzeng/.codex/memories/MEMORY.md`

**Step 1: 运行完整验证**

Run:
- `swift test --package-path macos`
- `swift build --package-path macos`
- `git diff --check`

**Step 2: 同步文档**

- 更新 AGENTS 中 Ghostty 架构说明。
- 在 tasks/todo.md 追加 Review 与验证证据。
- 回写 MEMORY.md，标记 bootstrap/path-locator 已退出运行主链。

**Step 3: 最终自检**

- 逐项核对设计目标与验收标准。
