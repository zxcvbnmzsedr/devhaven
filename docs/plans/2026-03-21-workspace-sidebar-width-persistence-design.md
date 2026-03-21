# 工作区侧边栏宽度持久化设计

## 背景
当前工作区左侧侧边栏已经支持拖拽调整宽度，但宽度只保存在运行时状态中。应用重启或重新进入 workspace 后，宽度会回退到默认值 280，导致用户每次都要重新拖拽。

## 目标
- 将工作区左侧侧边栏宽度持久化到现有 `AppSettings`。
- 宽度作为**全局一份设置**共享，而不是按项目分别保存。
- 保持对旧配置文件的向后兼容：历史 `app_state.json` 没有该字段时仍能正常读取，并回退到默认值。

## 方案对比
### 方案 A：写入 `AppSettings.workspaceSidebarWidth`（推荐）
- 优点：沿用现有设置真相源；兼容 `LegacyCompatStore.updateSettings` 的深合并逻辑；改动最小。
- 缺点：UI 布局参数继续增长到 `AppSettings`，需要保持字段命名收敛。

### 方案 B：单独写一个 workspace UI 状态文件
- 优点：布局参数与业务设置解耦。
- 缺点：新增第二套持久化入口、读取路径和兼容逻辑，不符合最少修改原则。

### 方案 C：按项目保存宽度
- 优点：不同项目可以记住不同宽度。
- 缺点：状态复杂度明显上升，用户已确认不需要。

## 最终设计
1. 在 `AppSettings` 中新增 `workspaceSidebarWidth: Double`，默认值为 `280`。
2. `WorkspaceShellView` 初始显示时，从 `viewModel.snapshot.appState.settings.workspaceSidebarWidth` 读取宽度，并通过既有 `WorkspaceSidebarLayoutPolicy` 做 clamp。
3. 用户拖拽侧边栏时，仍先更新本地 `@State sidebarWidth`，保证拖拽流畅。
4. 在拖拽结束时，把最终宽度写回 `viewModel.saveSettings(...)`，避免拖拽过程中频繁落盘。
5. 如果设置页或其他路径修改了该值，`WorkspaceShellView` 通过 `onChange` 同步本地状态。

## 影响文件
- `macos/Sources/DevHavenCore/Models/AppModels.swift`
- `macos/Sources/DevHavenApp/WorkspaceShellView.swift`
- `macos/Sources/DevHavenApp/WorkspaceSplitView.swift`
- 相关测试文件

## 验证策略
- 先写失败测试，覆盖：
  - `AppSettings` 缺省回退默认宽度；
  - `WorkspaceShellView` 不再只使用运行时默认值，而是接入 settings；
  - 拖拽提交时会写回设置。
- 运行针对性测试与全量 `swift test --package-path macos` 回归。
