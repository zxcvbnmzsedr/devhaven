# Typed Run Configurations Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 以破坏式升级方式移除 shared scripts / 默认模板体系，把 workspace run 配置改成 IDEA 风格的类型化运行配置，并先落地 `customShell` 与 `remoteLogViewer` 两类配置。

**Architecture:** 项目内只保留结构化 run configuration；`Settings` 不再承载模板管理，shared script / manifest / global root 全部退场。执行层新增 typed executable：`customShell` 继续走 shell，`remoteLogViewer` 直接生成 `ssh` 进程参数，避免再把配置语义压扁成 shell 模板文本。

**Tech Stack:** Swift 6, SwiftUI, DevHavenCore, XCTest, Process/Pipe

---

### Task 1: Core model / migration / workspace run state

**Files:**
- Modify: `macos/Sources/DevHavenCore/Models/AppModels.swift`
- Modify: `macos/Sources/DevHavenCore/Models/WorkspaceRunModels.swift`
- Modify: `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`
- Modify: `macos/Tests/DevHavenCoreTests/NativeAppViewModelWorkspaceRunTests.swift`
- Add/Modify: 相关 core model tests（如需要）

**Steps:**
1. 先写/改 failing tests，约束：
   - 项目运行配置来源改为结构化 configuration，而非 shared scripts
   - legacy `ProjectScript.start + paramSchema + templateParams` 能被一次性 flatten 成 `customShell`
   - `remoteLogViewer` 配置能出现在 workspace run 菜单中并给出正确显示/禁用状态
2. 运行定向测试，确认红灯。
3. 引入新的 run configuration kind / payload / legacy decode 逻辑。
4. 更新 `NativeAppViewModel`：
   - 读取/保存 `runConfigurations`
   - 生成 typed `WorkspaceRunConfiguration`
   - 删除 reveal shared scripts settings 相关路径
5. 运行定向测试转绿。

### Task 2: Typed executable / run manager / remote log viewer executor

**Files:**
- Modify: `macos/Sources/DevHavenCore/Models/WorkspaceRunModels.swift`
- Modify: `macos/Sources/DevHavenCore/Run/WorkspaceRunManager.swift`
- Modify: `macos/Tests/DevHavenCoreTests/WorkspaceRunManagerTests.swift`
- Add/Modify: remote log viewer 相关 core tests（如需要）

**Steps:**
1. 先写 failing tests，约束：
   - `customShell` 仍使用 `/bin/zsh -lc <command>`
   - `remoteLogViewer` 直接使用 `/usr/bin/ssh` + args，不再依赖 shared helper script
   - 命令头日志能区分 shell / process 两种执行方式
2. 运行定向测试，确认红灯。
3. 为 start request / session 引入 typed executable 描述。
4. 实现 remote log viewer args 渲染与日志显示。
5. 运行定向测试转绿。

### Task 3: App UI / settings cleanup / configuration editor

**Files:**
- Modify: `macos/Sources/DevHavenApp/WorkspaceHostView.swift`
- Replace: `macos/Sources/DevHavenApp/WorkspaceScriptConfigurationSheet.swift`
- Delete: `macos/Sources/DevHavenApp/SharedScriptsManagerView.swift`
- Modify: `macos/Sources/DevHavenApp/SettingsView.swift`
- Modify: `macos/Tests/DevHavenAppTests/WorkspaceHostViewRunConsoleTests.swift`
- Modify: `macos/Tests/DevHavenAppTests/WorkspaceScriptConfigurationSheetTests.swift`
- Modify: `macos/Tests/DevHavenAppTests/SettingsViewTests.swift`

**Steps:**
1. 先写/改 failing tests，约束：
   - workspace 配置入口改成运行配置编辑器，不再出现“插入通用脚本 / 管理通用脚本”
   - Settings 不再有“脚本”分类与 shared scripts UI
   - 新面板能新建 `customShell` / `remoteLogViewer`
2. 运行 app 定向测试，确认红灯。
3. 实现新的 typed configuration sheet 与 Settings 清理。
4. 删除 shared scripts 相关 UI 文件与引用。
5. 运行 app 定向测试转绿。

### Task 4: Legacy shared scripts cleanup / docs sync

**Files:**
- Modify/Delete: `macos/Sources/DevHavenCore/Storage/LegacyCompatStore.swift`
- Delete: `macos/Sources/DevHavenCore/Models/SharedScriptModels.swift`
- Modify: `macos/Tests/DevHavenCoreTests/LegacyCompatStoreTests.swift`
- Modify: `macos/Tests/DevHavenCoreTests/AppSettingsUpdatePreferencesTests.swift`
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`

**Steps:**
1. 先改 failing tests，约束：
   - AppSettings 不再暴露 `sharedScriptsRoot`
   - store 不再提供 shared scripts manifest / preset API
2. 删除 shared scripts store/model 代码，并清理过时测试。
3. 更新 `AGENTS.md`，把运行配置与设置边界改成新架构。
4. 运行受影响测试转绿。

### Task 5: Fresh verification

**Files:**
- 无新增源码；只做验证与 Review 记录

**Steps:**
1. 运行 core 定向测试。
2. 运行 app 定向测试。
3. 运行 `swift test --package-path macos` 全量回归。
4. 更新 `tasks/todo.md` Review，记录直接原因、设计层诱因、当前修复、长期建议、验证证据。
