# DevHaven Swift Ghostty workspace controller 设计

## 目标

把项目内终端布局层从 `NativeAppViewModel.swift` 中抽出，收口成一个 dedicated workspace owner：`GhosttyWorkspaceController.swift`。

本轮的目标不是重写 Ghostty surface/runtime，而是把“多项目导航”和“单项目内 tab/pane 布局”真正拆层：

- `NativeAppViewModel` 只负责项目级导航、详情面板、已打开项目列表与系统 Terminal 打开动作；
- `GhosttyWorkspaceController` 负责单项目内 tab/pane 布局、Ghostty action 对接和 `WorkspaceSessionState` projection 输出；
- SwiftUI workspace 壳层直接消费 controller，不再让全局 ViewModel 直接维护 pane tree。

## 当前问题

虽然前几轮已经把 root 常驻挂载、进入命令行诊断链、左侧已打开项目列表和右侧 tab/pane MVP 都补上了，但单项目内终端布局真相仍然散落在 `NativeAppViewModel.swift`：

- `openWorkspaceSessions` 里直接塞 `WorkspaceSessionState`；
- 新建 tab / 关闭 tab / 分屏 / 缩放 / 标题同步都由 ViewModel 直接改 value state；
- `WorkspaceHostView.swift` 虽然是 workspace 主区，但所有 Ghostty action 最终还是回流到全局 ViewModel。

这会继续带来两个诱因：

1. 项目级导航状态和项目内终端布局状态还没有真正拆开；
2. 后续如果继续接 Ghostty 布局 manager / inherited config / 侧边栏等能力，复杂度还会继续堆回 ViewModel。

## 方案

采用 **A：单项目 dedicated owner + projection 输出**。

### 1. 新增 `GhosttyWorkspaceController`

位置：`macos/Sources/DevHavenCore/ViewModels/GhosttyWorkspaceController.swift`

职责：

- 持有单项目 `WorkspaceSessionState` projection；
- 统一处理 `create/select/move/close/goto tab`；
- 统一处理 `split/focus/resize/equalize/zoom/close pane`；
- 统一处理 runtime title -> stable tab title 的同步；
- 对外暴露只读 projection（`tabs / selectedTab / selectedPane / sessionState`）。

### 2. `OpenWorkspaceSessionState` 只保留“项目路径 + controller”

`OpenWorkspaceSessionState.swift` 不再把 `WorkspaceSessionState` 当成真正的会话 owner，而是保存：

- `projectPath`
- `controller: GhosttyWorkspaceController`

这样 `WorkspaceShellView.swift` 仍能继续管理多项目打开列表，但右侧单项目终端主区已经能直接拿到 controller。

### 3. `NativeAppViewModel` 降级为项目级编排层

`NativeAppViewModel.swift` 保留：

- `openWorkspaceSessions` 集合
- `activeWorkspaceProjectPath`
- `activeWorkspaceController` / `activeWorkspaceState` 只读派生
- `enterWorkspace / activateWorkspaceProject / closeWorkspaceProject / exitWorkspace`
- `openWorkspaceInTerminal`
- 进入命令行诊断日志

但不再直接持有和改写 pane tree；原有 workspace action 仅保留为 controller 转发兼容层。

### 4. SwiftUI workspace 壳直接对 controller 编程

`WorkspaceHostView.swift` 现在直接消费 `GhosttyWorkspaceController`：

- tab bar 按钮直接调 controller
- Ghostty action 闭包直接调 controller
- `WorkspaceShellView.swift` 把 `session.controller` 传给 `WorkspaceHostView.swift`
- `DevHavenApp.swift` 的 `⌘D` 入口直接派发到 `activeWorkspaceController`

## 设计取舍

### 为什么这轮先做 dedicated owner，而不是直接把所有 split 语义交给 Ghostty C API

因为当前最重的结构性问题不是“某个 Ghostty API 没调到”，而是 **布局 owner 的边界还没收口**。

如果不先把项目级导航和项目内布局层拆开，后面无论是继续接 `ghostty_surface_split(...)`，还是继续做 inherited config / 懒 attach，复杂度都会继续回流到 `NativeAppViewModel.swift`。

先把 owner 抽出来，后续再替换 owner 内部实现，风险和范围都更可控。

## 影响文件

### 新增

- `macos/Sources/DevHavenCore/ViewModels/GhosttyWorkspaceController.swift`
- `macos/Tests/DevHavenCoreTests/GhosttyWorkspaceControllerTests.swift`
- `docs/plans/2026-03-20-devhaven-swift-ghostty-workspace-controller-plan.md`

### 修改

- `macos/Sources/DevHavenCore/Models/OpenWorkspaceSessionState.swift`
- `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`
- `macos/Sources/DevHavenApp/WorkspaceShellView.swift`
- `macos/Sources/DevHavenApp/WorkspaceHostView.swift`
- `macos/Sources/DevHavenApp/DevHavenApp.swift`
- `AGENTS.md`
- `tasks/todo.md`
- `tasks/lessons.md`

## 验证思路

1. 先补 `GhosttyWorkspaceControllerTests.swift`，锁定 owner 的初始态、tab/pane 变更和标题策略。
2. 继续跑 `NativeAppViewModelWorkspaceEntryTests.swift`，确认 ViewModel 降级后多项目打开/切换/回退不回归。
3. 跑全量 `swift test --package-path macos`。
4. 跑 `swift build --package-path macos`。
5. 跑 `git diff --check`。
