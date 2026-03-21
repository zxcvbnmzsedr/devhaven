# Todo

- [x] 收集 GitHub workflow 失败 run 的日志与错误位置

- [x] 根据日志定位直接原因与是否存在设计层诱因

- [x] 先补充能覆盖该失败场景的测试/验证，再实施最小修复

- [x] 运行本地验证并更新 tasks/todo.md Review

- [x] 核对当前本地/远端 3.0.0 与 v3.0.0 tag 状态
- [x] 删除错误的 3.0.0 tag，创建并推送正确的 v3.0.0 tag
- [x] 验证远端 v3.0.0 指向正确提交，并记录 lessons / review

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


## Review（GitHub release workflow 故障）

- 直接原因：最新 release workflow run `23379991100` 失败在 `Publish native release asset`，日志报错 `Validation Failed: already_exists, field: tag_name`。进一步核对 GitHub Release 发现同一个 `v3.0.0` 同时存在一个 published pre-release 和一个重复 draft release，`softprops/action-gh-release@v2` 在 arm64 matrix job 里 finalizing release 时与这个重复 draft 冲突。
- 设计层诱因：当前 `.github/workflows/release.yml` 让每个 matrix job 都直接调用 `action-gh-release` 去创建/更新/最终化 release 元数据；当仓库里存在 stale draft release 时，发布逻辑既要上传 asset 又要处理 release 状态，导致同 tag 元数据冲突被放大。
- 当前修复方案：
  - 在 release workflow 中新增 `prepare-release` job，先统一解析 tag、清理同 tag 的重复 draft release，并确保目标 release 已存在。
  - 让 `build-macos-native` matrix job `needs: prepare-release`，并改为只用 `gh release upload --clobber` 上传架构资产，不再由 matrix job 自己 finalizing release。
  - 手动删除远端重复 draft release，随后对失败 run `23379991100` 执行 rerun，成功补齐 `DevHaven-macos-arm64.zip`。
- 新增/更新验证：
  - `macos/Tests/DevHavenCoreTests/ReleaseWorkflowTests.swift`
- 验证证据：
  - `swift test --package-path macos --filter ReleaseWorkflowTests`
  - `swift test --package-path macos`
  - `gh run view 23379991100 --json status,conclusion,jobs,url` => `conclusion: success`
  - `gh release view v3.0.0 --json assets --jq '.assets[].name'` => 同时包含 `DevHaven-macos-arm64.zip` 与 `DevHaven-macos-x86_64.zip`
- 长期建议：对 release workflow 继续保持“单 job 管 release 元数据，matrix job 只传 artifact”的边界，不要再回到每个 matrix job 都直接 finalizing release 的模式。
