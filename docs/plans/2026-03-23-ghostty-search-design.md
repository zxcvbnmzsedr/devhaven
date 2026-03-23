# DevHaven Ghostty 搜索功能设计

## 背景
当前 DevHaven 已经把 libghostty 作为内嵌终端引擎接入，但终端内“查找”能力尚未暴露给用户。对比 Supacode 可知，Ghostty 搜索并不是宿主打开某个开关后自动出现，而是需要宿主 App 自己完成以下闭环：

1. 提供菜单 / 快捷键入口；
2. 把查找动作路由到当前 focused terminal pane；
3. 处理 libghostty 回调的搜索状态；
4. 叠加宿主搜索 UI，并继续通过 binding action 回发给 libghostty。

因此，DevHaven 当前“没有搜索”并非底层库不支持，而是宿主侧还未补齐搜索桥接层。

## 目标
1. 在 DevHaven 内嵌 Ghostty 终端中支持搜索；
2. 支持 `查找…`、`查找下一个`、`查找上一个`、`隐藏查找栏`、`使用所选内容查找`；
3. 在当前 focused pane 上显示轻量搜索浮层，支持输入关键字和查看命中计数；
4. 保持对现有 tab / split / agent 状态链路的最小侵入；
5. 优先复用现有 `ghostty_surface_binding_action(...)` 发送能力。

## 非目标
- 不在本次实现中重做 DevHaven 全局命令系统；
- 不新增跨项目的统一 command palette 架构；
- 不改写 GhosttyKit / libghostty；
- 不实现比 Supacode 更复杂的搜索 UX（如持久化浮层位置、全局搜索历史等）。

## 方案比较

### 方案 A：只补 `Cmd+F -> start_search`
- 优点：改动最小；
- 缺点：只有“打开搜索”的入口，没有结果计数、关闭、上下一个与 selection 搜索，体验不完整。

### 方案 B：对齐 Supacode 的轻量宿主桥接方案（推荐）
- 做法：
  1. 在 `GhosttySurfaceState` 补搜索状态；
  2. 在 `GhosttySurfaceBridge` 处理 search action；
  3. 新增搜索浮层视图；
  4. 在当前 focused pane 上暴露搜索命令入口；
  5. 在 App Commands 中挂接查找菜单；
  6. 所有真正发往 libghostty 的行为仍通过 `performBindingAction(_:)`。
- 优点：功能闭环完整，和现有 Ghostty 集成模式一致；
- 缺点：需要新增一组 focused command / overlay 代码，但复杂度可控。

### 方案 C：等待 Ghostty 宿主层未来自动提供原生 find bar
- 优点：理论上宿主代码最少；
- 缺点：当前 GhosttyKit 暴露的是 action / binding 接口，而不是可直接嵌入的宿主查找栏；等待该能力不现实。

## 最终设计
采用 **方案 B**。

### 1. 搜索状态收口到 `GhosttySurfaceState`
在 `GhosttySurfaceState` 新增：

- `searchNeedle`
- `searchTotal`
- `searchSelected`
- `searchFocusCount`

其中：
- `searchNeedle != nil` 表示宿主应展示搜索栏；
- `searchFocusCount` 用于强制把焦点重新落回搜索输入框；
- `searchTotal` / `searchSelected` 用于命中计数展示和导航逻辑。

### 2. `GhosttySurfaceBridge` 处理 libghostty 搜索回调
在 `GhosttySurfaceBridge.handleAction(...)` 中新增：

- `GHOSTTY_ACTION_START_SEARCH`
- `GHOSTTY_ACTION_END_SEARCH`
- `GHOSTTY_ACTION_SEARCH_TOTAL`
- `GHOSTTY_ACTION_SEARCH_SELECTED`

职责边界：
- Bridge 只负责把 libghostty action 翻译成宿主搜索状态；
- 不在 Bridge 中实现菜单逻辑或浮层 UI。

### 3. 搜索 UI 作为 terminal 宿主 overlay
新增 `GhosttySurfaceSearchOverlay.swift`，参考 Supacode 但收口到 DevHaven 当前代码风格。

浮层行为：
- 显示搜索输入框；
- 输入关键字后通过 `search:<needle>` 发给当前 surface；
- 支持上一个 / 下一个 / 关闭；
- 支持显示 `current/total`；
- Esc 关闭浮层后，把焦点还给 terminal surface。

### 4. 搜索命令通过 FocusedValue 路由到当前 pane
由于 `DevHavenApp.swift` 本身拿不到 `WorkspaceTerminalStoreRegistry`，因此不能直接在 App 层硬编码“当前 pane 搜索”逻辑。  
本次采用和 Supacode 相同的 SwiftUI `FocusedValue` 模式：

- `WorkspaceShellView` 提供当前 active workspace 的搜索 action；
- `DevHavenApp.swift` 通过 `Commands` 读取 focused action；
- 执行时只作用于当前 focused pane 对应的 `GhosttySurfaceHostModel`。

### 5. `GhosttySurfaceHostModel` 暴露最小搜索入口
在 model 层新增轻量方法：

- `startSearch()`
- `searchSelection()`
- `navigateSearchNext()`
- `navigateSearchPrevious()`
- `endSearch()`

这些方法内部只负责调用当前 `GhosttyTerminalSurfaceView` 的 binding action，不持有额外状态真相源。

### 6. 搜索浮层显示位置
优先放在 `GhosttySurfaceHost` 的 terminal 区域上层，而不是放在 `WorkspaceTerminalPaneView` 外层。  
这样可以直接复用 `GhosttySurfaceHostModel.currentSurfaceView` 与 terminal appearance，减少跨层依赖。

## 影响范围
- `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceState.swift`
- `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceBridge.swift`
- `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceHost.swift`
- `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceView.swift`
- `macos/Sources/DevHavenApp/WorkspaceShellView.swift`
- `macos/Sources/DevHavenApp/DevHavenApp.swift`
- 新增：`macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceSearchOverlay.swift`
- 新增：`macos/Sources/DevHavenApp/WorkspaceTerminalCommands.swift`
- `macos/Tests/DevHavenAppTests/GhosttySurfaceBridgeTabPaneTests.swift`
- `macos/Tests/DevHavenAppTests/DevHavenAppCommandTests.swift`
- 新增搜索相关测试文件
- `AGENTS.md`
- `tasks/todo.md`

## 风险与控制

### 风险 1：搜索浮层显隐和 Ghostty 回调不同步
控制：以 `searchNeedle != nil` 作为唯一展示条件，并在 `START_SEARCH / END_SEARCH` action 中显式维护状态。

### 风险 2：App 菜单找不到当前 pane
控制：采用 `FocusedValue` 让当前 workspace 场景提供 action，而不是在 App 全局单例里硬编码 pane 查找。

### 风险 3：搜索输入框抢走 terminal 焦点后无法返回
控制：浮层关闭时显式调用 `surfaceView.requestFocus()`，保持当前 pane 焦点链路可恢复。

### 风险 4：为了搜索引入过多宿主层状态
控制：所有搜索运行时状态仍然挂在 `GhosttySurfaceState`，`GhosttySurfaceHostModel` 只暴露方法，不复制真相源。

## 验证策略
1. 先写失败测试，覆盖：
   - Bridge 能处理 search action；
   - App Commands 暴露查找菜单；
   - Workspace/Host 层挂接搜索 overlay / focused action；
2. 跑定向测试，确认红灯；
3. 实现最小代码让测试转绿；
4. 追加至少一轮相关构建验证，确保没有破坏现有 App 编译。
