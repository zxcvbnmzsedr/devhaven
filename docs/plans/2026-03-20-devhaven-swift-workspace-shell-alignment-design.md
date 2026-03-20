# DevHaven Swift 原生 workspace 外层壳对齐 Tauri 设计

## 目标

把 Swift 原生版进入 workspace 后的结构，从“单项目详情头 + 右侧整块终端”调整为 **左侧已打开项目列表 + 右侧终端区**，先对齐 Tauri 的信息架构，不在本轮强追 1:1 视觉细节，也不扩展 worktree / 控制面 / 文件侧栏。

## 当前问题

当前 Swift 版虽然已经有标签页 + 分屏窗格 MVP，但 workspace 仍只有单项目上下文：

- `NativeAppViewModel` 只跟踪一个 `activeWorkspaceProjectPath` + 一个 `activeWorkspaceState`
- `AppRootView` 进入 workspace 后只渲染单个 `WorkspaceHostView`
- 因此缺少 Tauri 版终端工作区最外层那一层“已打开项目列表”

这会导致两个问题：

1. 进入 workspace 后看不到“已打开项目”这一层信息架构
2. 若后续要切项目并保活 Ghostty 终端，只靠替换单个 `WorkspaceHostView` 会再次踩到卸载非激活终端导致 surface 释放的问题

## 本轮边界

### 本轮包含

- 进入 workspace 后改成 **左侧已打开项目列表 + 右侧终端区**
- 支持把多个项目加入“已打开项目”列表
- 支持在已打开项目之间切换当前激活项目
- 支持关闭已打开项目
- 右侧终端区继续复用当前标签页 + 分屏窗格 MVP
- 非激活项目的 workspace 继续保持挂载，仅隐藏并禁交互

### 本轮不包含

- worktree 子层级
- 控制面状态点 / 未读 badge / 最近消息
- 文件 / Git 侧边栏
- 布局持久化
- 运行配置
- Tauri 版 1:1 视觉像素级复刻

## 方案

采用 **A1：新增 workspace shell 外层壳，不推翻内部 terminal topology**。

### 状态层

把 workspace 状态从“单项目单状态”扩成“已打开项目会话集合 + 当前激活项目”：

- `openWorkspaceSessions: [OpenWorkspaceSessionState]`
- `activeWorkspaceProjectPath: String?`
- `activeWorkspaceState` 改为由当前激活项目派生
- `activeWorkspaceProject` 也改为由当前激活路径派生

每个 `OpenWorkspaceSessionState` 持有：

- `projectPath`
- `workspaceState: WorkspaceSessionState`

这样可以保持：

- 左侧列表有顺序
- 每个项目各自拥有独立的标签页 / 窗格 topology
- 切换项目时不丢失其内部 workspace 状态

### 视图层

新增 `WorkspaceShellView.swift`：

- 左侧：`WorkspaceProjectListView.swift`
- 右侧：所有 `WorkspaceHostView` 叠放挂载，只有当前激活项目可见

其中：

- `WorkspaceHostView` 退回为“单项目 workspace 主区”
- `AppRootView` 进入 workspace 时改为挂 `WorkspaceShellView`

### 生命周期约束

必须保持和之前 tab 保活同样的策略：

- 所有已打开项目对应的 `WorkspaceHostView` 都挂着
- 非激活项目只做：透明隐藏 + 禁交互 + accessibility hidden
- 绝不能因为切换激活项目而卸载非激活项目对应的 Ghostty 视图

否则 `GhosttySurfaceHost.onDisappear -> releaseSurface()` 会把终端直接销毁。

## 影响文件

### 主要修改

- `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`
- `macos/Sources/DevHavenApp/AppRootView.swift`
- `macos/Sources/DevHavenApp/WorkspaceHostView.swift`
- `macos/Tests/DevHavenCoreTests/NativeAppViewModelWorkspaceEntryTests.swift`

### 新增文件

- `macos/Sources/DevHavenCore/Models/OpenWorkspaceSessionState.swift`
- `macos/Sources/DevHavenApp/WorkspaceShellView.swift`
- `macos/Sources/DevHavenApp/WorkspaceProjectListView.swift`

## 验证思路

1. 先补 ViewModel 测试，锁定：
   - 连续打开多个项目时会加入已打开项目列表
   - 切换激活项目时保留各自 workspace topology
   - 关闭项目时 active fallback 正确
2. 跑既有 topology / Ghostty bridge / workspace entry 测试，确认未回归
3. 跑全量 `swift test --package-path macos`
4. 跑 `swift build --package-path macos`
5. 跑 `git diff --check`

## 风险

唯一需要特别注意的是：这轮如果把“项目切换”写成替换单个 `WorkspaceHostView`，会立即回归为“切项目就释放非激活 Ghostty surface”。因此挂载策略必须作为本轮一等约束。
