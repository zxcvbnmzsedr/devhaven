# DevHaven Swift Workspace Tab + Pane 设计

> 状态：用户已确认按本方案直接实施

## 目标

在当前 Swift 原生 workspace 已接入 **Ghostty app 级共享 runtime + 单一 shell pane** 的基础上，继续完成一个可用的 **Tab + Pane MVP**：

- 一个 workspace 支持多个 terminal tabs；
- 每个 tab 支持左右 / 上下 split；
- Ghostty 内部 action（new tab / goto tab / close tab / split / focus split / resize split / equalize / zoom）能回推到原生 workspace 拓扑层；
- 继续保持 `GhosttyRuntime` 只负责 app/runtime 与 surface 生命周期，不把 tab/pane 真相塞回 runtime 或 SwiftUI host。

## 不变的边界

本轮不改变以下主线：

1. `GhosttyAppRuntime` 仍负责 bundle 资源定位与一次性 `ghostty_init(...)`。
2. `GhosttyRuntime` 仍是 app 级共享对象，负责 `ghostty_app_t` / `ghostty_config_t` / observer / surface 创建。
3. `GhosttySurfaceView` 仍负责 AppKit surface、键盘、IME、鼠标与文本输入链。
4. `GhosttySurfaceHost` 仍只负责单一 pane 的 UI 宿主与 surface 生命周期；**不直接维护 tab/pane 树**。

## 本轮范围

### 包含
- tab：新建、切换、关闭、Ghostty action 驱动的跳转与移动
- pane：左右/上下 split、focus 切换、关闭 pane、resize、equalize、zoom
- workspace 最后一个 pane / tab 关闭后的兜底：自动补一个新的空 shell tab，避免 workspace 进入死态
- workspace 顶部 tab bar 与基础 pane 操作按钮
- 纯逻辑 topology 测试 + bridge action 测试 + 现有 Ghostty smoke 回归

### 不包含
- tabs / panes 持久化到磁盘
- tab 拖拽排序 UI
- detached window / 多窗口
- run panel、文件侧边栏、Git 侧边栏、worktree/control plane 原生投影
- 多项目 workspace 编排

## 方案对比

### 方案 A：直接整体平移 supacode terminal 子系统
- 优点：最贴近参考实现
- 缺点：会把 `supacode` 的 worktree manager、通知、command palette、运行状态等一整套假设一起带进来，超出当前 DevHaven Swift worktree 的实际边界

### 方案 B：保留共享 runtime，新增轻量 workspace topology 层（采用）
- 优点：能复用当前已稳定的 Ghostty shared runtime 主线；tab/pane 真相与 Ghostty surface 生命周期职责清晰；方便逐步继续补控制面 / worktree / 持久化
- 缺点：需要新建一套最小 topology 模型和递归 split UI

### 方案 C：只在 `WorkspaceHostView` 里堆本地 SwiftUI 状态
- 优点：表面改动少
- 缺点：tab、pane、focus、resize、close fallback 逻辑会重新散落在 View 内，重复走回“当前集成过于复杂”的老路

## 目标结构

```text
NativeAppViewModel
  -> activeWorkspaceState: WorkspaceSessionState
  -> workspace action methods (tab/pane topology)

WorkspaceSessionState
  -> tabs: [WorkspaceTabState]
  -> selectedTabID
  -> tab/pane topology 真相

WorkspacePaneTree
  -> leaf(pane)
  -> split(direction, ratio, left, right)
  -> focus / remove / resize / equalize / spatial navigation helper

GhosttySurfaceBridge
  -> 负责把 Ghostty action 翻译成 workspace action 闭包

WorkspaceHostView
  -> Header
  -> WorkspaceTabBarView
  -> WorkspaceSplitTreeView
  -> WorkspaceTerminalPaneView(leaf)
```

## 数据模型

新增一层 workspace 拓扑模型：

- `WorkspaceSessionState`
  - `workspaceId`
  - `projectPath`
  - `tabs`
  - `selectedTabId`
  - 内部计数器（用于生成 tab/pane/surface/session id）
- `WorkspaceTabState`
  - `id`
  - `title`
  - `root: WorkspacePaneTree`
  - `focusedPaneId`
- `WorkspacePaneTree`
  - `root: Node?`
  - `zoomedPaneId`
  - `Node.leaf(WorkspacePaneState)`
  - `Node.split(WorkspaceSplitState)`
- `WorkspacePaneState`
  - `id`
  - `request: WorkspaceTerminalLaunchRequest`
- `WorkspaceSplitState`
  - `direction`
  - `ratio`
  - `left / right`

这层模型放在 `DevHavenCore`，方便做纯逻辑测试，不把拓扑真相绑定到 SwiftUI。

## Ghostty action 对接

扩展 `GhosttySurfaceBridge`，补齐：

- `onNewTab`
- `onCloseTab`
- `onGotoTab`
- `onMoveTab`
- `onSplitAction`

其中 `onSplitAction` 统一表达：

- `newSplit(direction)`
- `gotoSplit(direction)`
- `resizeSplit(direction, amount)`
- `equalizeSplits`
- `toggleSplitZoom`

这样 Ghostty action -> bridge -> workspace topology 的链路清晰，而 runtime / host 继续保持轻量。

## 关闭与焦点规则

### Pane 关闭
- 如果当前 tab 还有其它 pane：移除当前 pane，并把焦点切到邻近 pane
- 如果当前 tab 只剩最后一个 pane：关闭该 tab
- 如果整个 workspace 也因此没有 tab：自动补一个新的空 shell tab

### Tab 关闭
- 关闭当前 tab 后，焦点优先落到左侧相邻 tab；没有左侧则落到新的第一个 tab
- 若关闭的是最后一个 tab，则自动补一个新的空 shell tab

### Focus
- UI 主动切换 tab / pane 时，调用 Ghostty surface first responder 聚焦
- Ghostty surface 自身因点击获得焦点时，再回推更新 workspace 的 focused pane id

## UI 结构

### WorkspaceHostView
- 保留现有项目标题、返回列表、外部 Terminal、查看详情动作
- Header 下方新增 `WorkspaceTabBarView`
- 主内容区渲染当前选中 tab 的 `WorkspaceSplitTreeView`

### WorkspaceTabBarView
- 横向 tab 列表
- tab close 按钮
- trailing actions：新建 tab、横/纵 split

### WorkspaceSplitTreeView
- 递归渲染 split tree
- split 节点使用可拖拽 ratio 的 `WorkspaceSplitView`
- leaf 节点渲染 `WorkspaceTerminalPaneView`

### WorkspaceTerminalPaneView
- leaf pane 外层容器
- 显示 focused 态边框
- 提供 pane 级按钮：split 水平/垂直、zoom、close
- 内部继续复用 `GhosttySurfaceHost`

## 验证策略

### 纯逻辑测试
锁定：
- 初始 workspace 自动创建单 tab 单 pane
- 新建 tab
- split focused pane
- close pane fallback
- close last tab 自动补默认 tab
- goto/move tab
- resize/equalize/zoom
- spatial focus

### bridge 测试
锁定：
- `GHOSTTY_ACTION_NEW_TAB`
- `GHOSTTY_ACTION_CLOSE_TAB`
- `GHOSTTY_ACTION_GOTO_TAB`
- `GHOSTTY_ACTION_MOVE_TAB`
- `GHOSTTY_ACTION_NEW_SPLIT`
- `GHOSTTY_ACTION_GOTO_SPLIT`
- `GHOSTTY_ACTION_RESIZE_SPLIT`
- `GHOSTTY_ACTION_EQUALIZE_SPLITS`
- `GHOSTTY_ACTION_TOGGLE_SPLIT_ZOOM`

### 回归验证
继续保留并重跑：
- `GhosttySurfaceHostTests`
- `swift test --package-path macos`
- `swift build --package-path macos`
- `git diff --check`

## 风险与对策

### 风险 1：复杂度重新回流到 `GhosttySurfaceHost`
- 对策：tab/pane 真相全部放在 workspace topology；host 只继续管理单 surface

### 风险 2：SwiftUI 递归 split view 容易引入状态更新混乱
- 对策：ratio/path 更新只通过 `NativeAppViewModel` 对 topology 做显式变更，不把 split 树变成本地 `@State`

### 风险 3：Ghostty 焦点与 workspace focused pane 状态源分裂
- 对策：surface 点击 -> 回推 focused pane；workspace 主动切换 -> 请求 surface 成为 first responder，形成双向对齐
