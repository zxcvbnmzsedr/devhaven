# Workspace 打开项目快捷键 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 workspace 新增可配置的“打开项目”菜单快捷键（默认 `⌘K`），并让项目选择弹窗默认聚焦搜索输入框。

**Architecture:** 在 `AppSettings` 中增加单条菜单快捷键配置，命令层通过新的 `WorkspaceProjectCommands` + `FocusedValue` 路由到 `WorkspaceShellView` 的 project picker 展示态。弹窗焦点由 `WorkspaceProjectPickerView` 在 View 层显式管理，不把 UI 焦点职责下沉到 Core。

**Tech Stack:** SwiftUI, AppKit, Swift Package, XCTest

---

### Task 1: 为快捷键配置补模型与回归测试

**Files:**
- Modify: `macos/Sources/DevHavenCore/Models/AppModels.swift`
- Test: `macos/Tests/DevHavenCoreTests/AppSettingsUpdatePreferencesTests.swift`

- [ ] Step 1: 写失败测试，约束默认值与旧配置回退到 `⌘K`
- [ ] Step 2: 运行 `swift test --package-path macos --filter AppSettingsUpdatePreferencesTests`，确认红灯
- [ ] Step 3: 以最小改动实现 `workspaceOpenProjectShortcut` 模型与解码默认值
- [ ] Step 4: 再跑 `swift test --package-path macos --filter AppSettingsUpdatePreferencesTests`，确认绿灯

### Task 2: 为设置页与命令入口补失败测试

**Files:**
- Create: `macos/Sources/DevHavenApp/WorkspaceProjectCommands.swift`
- Modify: `macos/Sources/DevHavenApp/SettingsView.swift`
- Modify: `macos/Sources/DevHavenApp/DevHavenApp.swift`
- Test: `macos/Tests/DevHavenAppTests/SettingsViewTests.swift`
- Test: `macos/Tests/DevHavenAppTests/DevHavenAppCommandTests.swift`

- [ ] Step 1: 写失败测试，约束设置页暴露“打开项目”快捷键配置，并且应用菜单接入 `WorkspaceProjectCommands`
- [ ] Step 2: 运行 `swift test --package-path macos --filter 'SettingsViewTests|DevHavenAppCommandTests'`，确认红灯
- [ ] Step 3: 实现快捷键设置卡片、命令文件与 App 命令挂接
- [ ] Step 4: 再跑 `swift test --package-path macos --filter 'SettingsViewTests|DevHavenAppCommandTests'`，确认绿灯

### Task 3: 为 project picker 焦点行为补失败测试并修复

**Files:**
- Modify: `macos/Sources/DevHavenApp/WorkspaceShellView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceProjectPickerView.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceShellViewTests.swift`
- Create: `macos/Tests/DevHavenAppTests/WorkspaceProjectPickerViewTests.swift`

- [ ] Step 1: 写失败测试，约束 WorkspaceShellView 提供打开项目 focused action，project picker 默认聚焦搜索框且关闭按钮不抢焦点
- [ ] Step 2: 运行 `swift test --package-path macos --filter 'WorkspaceShellViewTests|WorkspaceProjectPickerViewTests'`，确认红灯
- [ ] Step 3: 以最小改动实现 focused action 与焦点修复
- [ ] Step 4: 再跑 `swift test --package-path macos --filter 'WorkspaceShellViewTests|WorkspaceProjectPickerViewTests'`，确认绿灯

### Task 4: 文档、回归与收尾

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`

- [ ] Step 1: 更新 AGENTS，记录 `WorkspaceProjectCommands.swift` 的职责与边界
- [ ] Step 2: 运行 `swift test --package-path macos --filter 'AppSettingsUpdatePreferencesTests|SettingsViewTests|DevHavenAppCommandTests|WorkspaceShellViewTests|WorkspaceProjectPickerViewTests'`
- [ ] Step 3: 运行 `swift build --package-path macos`
- [ ] Step 4: 在 `tasks/todo.md` 追加 Review，记录直接原因、设计层诱因、修复方案、长期建议、验证证据
