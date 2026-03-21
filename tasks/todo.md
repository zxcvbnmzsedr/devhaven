# Todo

- [x] 定位工作区左侧侧边栏宽度无法拖拽的问题与根因
- [x] 先补充能稳定复现该问题的测试或验证手段
- [x] 实施最小修复并更新相关注释/文档（如需要）
- [x] 运行验证并在本文件追加 Review 证据
- [x] 设计侧边栏宽度持久化方案并确认写入位置
- [x] 先补充失败测试，约束侧边栏宽度能从设置读取并写回
- [x] 实现侧边栏宽度持久化到设置
- [x] 运行验证并追加新的 Review 证据

## Review

- 直接原因：`WorkspaceShellView` 原先使用 `HStack + .frame(width: 280)` 固定左侧项目栏宽度，界面没有任何可拖拽分栏容器，因此侧边栏宽度无法通过拖拽改变。
- 修复方案：改为在 `WorkspaceShellView` 中使用 `WorkspaceSplitView` 承载左侧项目栏与右侧工作区内容，并新增 `WorkspaceSidebarLayoutPolicy` 负责默认宽度、最小/最大宽度以及最小内容区宽度的约束。
- 新增验证：
  - `macos/Tests/DevHavenAppTests/WorkspaceShellViewTests.swift`
  - `macos/Tests/DevHavenAppTests/WorkspaceSidebarLayoutPolicyTests.swift`
- 验证证据：
  - `swift test --package-path macos --filter 'Workspace(ShellView|SidebarLayoutPolicy)Tests'`
  - `swift test --package-path macos`


## Review（侧边栏宽度持久化）

- 直接原因：侧边栏虽然已经支持拖拽，但宽度只存在 `WorkspaceShellView` 的运行时 `@State` 中，没有写回 `AppSettings`，因此重新进入 workspace 或重启应用后会恢复默认值。
- 设计层诱因：UI 布局状态没有接入现有全局 settings 真相源；另外 `SettingsView.nextSettings` 手工重建 `AppSettings` 时，如果不显式透传新字段，会把后续新增设置悄悄丢掉。
- 当前修复方案：
  - 在 `AppSettings` 中新增 `workspaceSidebarWidth`，默认值 280，兼容旧配置缺省回退。
  - 在 `NativeAppViewModel` 中新增 `workspaceSidebarWidth` 读取入口与 `updateWorkspaceSidebarWidth(_:)` 写回入口。
  - 在 `WorkspaceSplitView` 中新增拖拽结束回调，使 `WorkspaceShellView` 能在拖拽结束后把最终宽度持久化到 settings。
  - 在 `SettingsView` 中透传 `workspaceSidebarWidth`，避免保存其他设置时覆盖该值。
- 新增/更新验证：
  - `macos/Tests/DevHavenCoreTests/AppSettingsWorkspaceSidebarWidthTests.swift`
  - `macos/Tests/DevHavenCoreTests/NativeAppViewModelWorkspaceSidebarWidthTests.swift`
  - `macos/Tests/DevHavenAppTests/WorkspaceShellViewTests.swift`
  - `macos/Tests/DevHavenAppTests/WorkspaceSplitViewTests.swift`
  - `macos/Tests/DevHavenAppTests/SettingsViewTests.swift`
- 验证证据：
  - `swift test --package-path macos --filter '(AppSettingsWorkspaceSidebarWidthTests|NativeAppViewModelWorkspaceSidebarWidthTests|WorkspaceShellViewTests|WorkspaceSplitViewTests|SettingsViewTests)'`
  - `swift test --package-path macos`
- 长期建议：后续如果 `AppSettings` 继续增长，建议把 workspace UI 布局相关设置抽成更聚合的 settings 子结构，避免 `SettingsView.nextSettings` 这类手工构造点持续膨胀。
