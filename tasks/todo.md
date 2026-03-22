# TODO

- [x] 梳理 DevHaven 当前工作区/终端状态流，确认通知增强切入点与受影响文件
- [x] 补齐设计文档、实现计划文档与 tasks/todo.md 执行清单
- [x] 按 TDD 为 Bridge/运行时状态/侧边栏通知体验编写失败测试并验证失败
- [x] 实现通知事件采集、运行状态聚合、设置项与 UI 交互
- [x] 更新相关文档与 AGENTS.md，同步任务状态与 Review
- [x] 运行测试/构建验证并整理结果
- [x] 复跑提交前验证并整理本次通知增强提交

## Review

- 结果：已为 DevHaven 引入工作区通知增强链路，覆盖 Ghostty desktop notification / progress / bell 事件、ViewModel 运行时注意力状态、侧边栏 bell / spinner / popover、系统通知与提示音设置、通知回跳对应 tab / pane。
- 直接原因：原实现只桥接标题、路径、渲染状态等基础终端信息，缺少通知事件与任务活动状态的应用层收口。
- 设计层诱因：工作区运行时注意力状态此前未集中建模，导致侧边栏、系统通知与 pane 聚焦之间缺少统一的数据流。
- 当前修复方案：新增 `WorkspaceNotificationModels.swift`、`WorkspaceNotificationPresenter.swift`、`WorkspaceNotificationPopover.swift`，扩展 `GhosttySurfaceBridge` / `GhosttySurfaceHostModel` / `NativeAppViewModel` / `WorkspaceProjectListView` / `SettingsView`，并同步更新 `AGENTS.md` 与计划文档。
- 长期改进建议：后续可补系统通知点击深链回跳、关闭 pane 时更细粒度清理运行态、以及通知历史持久化或 AI 语义归纳，但当前未发现明显系统设计缺陷。
- 验证证据：
  - 2026-03-22 `swift test --package-path macos` → 156 tests，5 skipped，0 failures，exit 0
  - 2026-03-22 `swift build --package-path macos` → Build complete，exit 0

## 2026-03-22 已打开项目列表显示分支

- [x] 探查“已打开项目”列表现状，确认当前分支数据来源与现有 UI 落点
- [x] 与用户逐步确认展示范围与交互预期
- [ ] 提出可选方案，完成设计并获得确认
- [ ] 补设计文档 / 实现计划，按 TDD 落地修改
- [ ] 运行验证并补充 Review 证据

## 2026-03-22 屏蔽 Command+N 默认新建窗口

- [x] 探查当前菜单 / 快捷键实现并确认 `⌘N` 来源
- [x] 按 TDD 补失败测试并验证默认 `newItem` 尚未被覆盖
- [x] 实现命令组覆盖，移除“新建窗口”菜单入口并屏蔽 `⌘N`
- [x] 运行验证并在 Review 记录证据

## Review（2026-03-22 屏蔽 Command+N 默认新建窗口）

- 结果：已在 `DevHavenApp.swift` 中显式使用 `CommandGroup(replacing: .newItem)` 覆盖系统默认 New Window 命令组，移除菜单中的默认“新建窗口”入口，并阻断 `⌘N` 继续触发新顶层窗口。
- 直接原因：当前 `WindowGroup` 默认暴露了 macOS 的 New Window 行为，但 DevHaven 当前产品模型是单主窗口 + 内部标签页 / 分屏，不应继续继承系统默认多窗口语义。
- 设计层诱因：窗口层与工作区 tab 层的职责边界此前没有在菜单命令层显式收口，导致系统默认“新建窗口”语义泄漏到当前单窗口产品模型中。
- 当前修复方案：补充 `DevHavenAppCommandTests` 先验证缺少 `newItem` 覆盖时测试失败，再以最小改动覆盖默认命令组；不改绑 `⌘N`，也不改动现有“新建标签页”入口与 Ghostty `new-tab` 链路。
- 长期改进建议：若未来要正式支持多主窗口，应单独设计窗口恢复、焦点、工作区归属与状态同步策略；当前未发现明显系统设计缺陷，但菜单语义需要继续与单窗口模型保持一致。
- 验证证据：
  - 2026-03-22 `swift test --package-path macos --filter DevHavenAppCommandTests` → 1 test，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos` → 157 tests，5 skipped，0 failures，exit 0
  - 2026-03-22 `swift build --package-path macos` → Build complete，exit 0

