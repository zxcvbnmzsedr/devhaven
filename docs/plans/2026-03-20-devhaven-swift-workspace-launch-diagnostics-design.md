# DevHaven Swift 原生 workspace 进入命令行诊断设计

## 目标

给 Swift 原生 workspace 补一条**只读诊断链**，把“进入 workspace / 挂载 host / 创建 Ghostty surface”这三个阶段的数量与耗时打到日志里，帮助判断慢点到底落在：

- workspace 入口状态恢复
- 多 host / 多 tab / 多 pane 挂载
- Ghostty surface / shell 创建

本轮**不修改恢复策略**，也不提前做 lazy attach。

## 当前问题

现在只能靠体感判断“某个项目进入命令行慢”，但缺少最关键的证据：

- 本次进入时当前项目已有多少 tab / pane
- workspace 里总共有多少已打开项目会一起挂载
- 每个 host 是否都在这次进入时被重新挂载
- 每个 Ghostty surface 创建各花了多少时间

因此即使我们已经怀疑根因是“保活 topology 重新挂载太重”，也还没有代码内证据可以直接确认。

## 本轮边界

### 包含

- `enterWorkspace(_:)` 时记录入口诊断
- `WorkspaceShellView` / `WorkspaceHostView` 挂载时记录 host 恢复诊断
- `GhosttySurfaceHostModel.acquireSurfaceView()` 记录 surface 创建开始/结束及耗时
- 提供结构化诊断事件，便于单元测试和后续扩展

### 不包含

- 不改变 `openWorkspaceSessions` 保活语义
- 不做 pane lazy attach
- 不新增 UI 面板
- 不持久化诊断结果

## 方案

采用 **A：轻量诊断中心 + 关键路径埋点**。

### 诊断中心

在 `DevHavenCore` 新增 `WorkspaceLaunchDiagnostics.swift`，集中负责：

- 生成结构化诊断事件
- 按 `workspaceId` / `surfaceId` 追踪入口起点与 surface 创建起点
- 输出统一格式日志
- 在测试里允许注入事件回调，避免测试直接依赖控制台输出

### 埋点位置

1. `NativeAppViewModel.enterWorkspace(_:)`
   - 记录本次进入目标项目
   - 记录该项目当前已有 tab / pane 数
   - 记录当前 `openWorkspaceSessions.count`

2. `WorkspaceShellView`
   - 记录 workspace shell 本次展示时总共挂了多少已打开项目

3. `WorkspaceHostView`
   - 记录每个 host 挂载时的 `projectPath / workspaceId / tabCount / paneCount / isActive`

4. `GhosttySurfaceHostModel.acquireSurfaceView()`
   - 记录某个 pane 的 surface 创建开始
   - 记录创建结束、是否失败、耗时多少毫秒
   - 若命中复用已有 view，也单独记录“surface reused”，避免把复用误判成新建

## 设计取舍

### 为什么不直接做 lazy attach

因为用户这轮先要的是**证据**，不是立即改行为。  
如果现在直接改恢复策略，会把“诊断”和“修复”揉在一起，后面很难判断到底是哪一层起效。

### 为什么先做结构化事件，不只 `print`

只打裸字符串会让后续测试和扩展都很脆。  
先有结构化事件，再统一转日志文本，既能满足排查，又能让测试直接断言诊断内容。

## 影响文件

### 新增

- `macos/Sources/DevHavenCore/Diagnostics/WorkspaceLaunchDiagnostics.swift`
- `macos/Tests/DevHavenCoreTests/WorkspaceLaunchDiagnosticsTests.swift`
- `docs/plans/2026-03-20-devhaven-swift-workspace-launch-diagnostics-plan.md`

### 修改

- `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`
- `macos/Sources/DevHavenApp/WorkspaceShellView.swift`
- `macos/Sources/DevHavenApp/WorkspaceHostView.swift`
- `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceHost.swift`
- `AGENTS.md`
- `tasks/todo.md`

## 验证思路

1. 先补 `WorkspaceLaunchDiagnosticsTests`，锁定事件内容和摘要字段。
2. 再补 `NativeAppViewModelWorkspaceEntryTests`，锁定 `enterWorkspace(_:)` 会发入口诊断。
3. 跑定向测试。
4. 跑 `swift test --package-path macos`
5. 跑 `swift build --package-path macos`
6. 跑 `git diff --check`

