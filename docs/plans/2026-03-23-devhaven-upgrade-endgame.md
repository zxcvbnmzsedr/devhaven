# DevHaven Upgrade Endgame Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 DevHaven 落地完整的 macOS 升级基础设施，包括 Sparkle 运行时、更新设置、Sparkle vendor、发布脚本与 stable/nightly appcast workflow。

**Architecture:** 继续复用现有 `DevHavenCore` / `DevHavenApp` Swift Package 主线，在 App 层新增 updater runtime 封装，在脚本层新增 Sparkle vendor / appcast 工具链，在 release workflow 中引入 staged appcast 与 nightly channel。保持开发态 `./dev` 可运行，但默认禁用 updater。

**Tech Stack:** Swift Package Manager、SwiftUI/AppKit、Sparkle.xcframework、bash、GitHub Actions、GhosttyKit vendor。

---

### Task 1: 更新设置模型与版本元数据

**Files:**
- Modify: `macos/Sources/DevHavenCore/Models/AppModels.swift`
- Create: `macos/Sources/DevHavenCore/Models/AppUpdateModels.swift`
- Test: `macos/Tests/DevHavenCoreTests/AppSettingsUpdatePreferencesTests.swift`

**Step 1: Write the failing test**

- 断言 `AppSettings` 包含 `updateChannel`、`updateAutomaticallyChecks`、`updateAutomaticallyDownloads`，且旧配置缺省时能回退默认值。

**Step 2: Run test to verify it fails**

Run: `swift test --package-path macos --filter AppSettingsUpdatePreferencesTests`
Expected: FAIL，提示新字段/新类型尚不存在。

**Step 3: Write minimal implementation**

- 新增 `UpdateChannel`
- 新增设置字段与默认值
- 补齐 Codable 兼容层

**Step 4: Run test to verify it passes**

Run: `swift test --package-path macos --filter AppSettingsUpdatePreferencesTests`
Expected: PASS

### Task 2: SettingsView 与菜单入口接入更新能力

**Files:**
- Modify: `macos/Sources/DevHavenApp/SettingsView.swift`
- Modify: `macos/Sources/DevHavenApp/AppRootView.swift`
- Modify: `macos/Sources/DevHavenApp/DevHavenApp.swift`
- Test: `macos/Tests/DevHavenAppTests/SettingsViewTests.swift`
- Test: `macos/Tests/DevHavenAppTests/DevHavenAppCommandTests.swift`

**Step 1: Write the failing test**

- 断言设置页存在升级通道/自动检查/自动下载/立即检查更新文案
- 断言应用菜单新增“检查更新”入口

**Step 2: Run test to verify it fails**

Run: `swift test --package-path macos --filter 'SettingsViewTests|DevHavenAppCommandTests'`
Expected: FAIL

**Step 3: Write minimal implementation**

- 在设置页增加升级设置卡片
- 在菜单中增加检查更新命令
- 保存更新偏好到 `AppSettings`

**Step 4: Run test to verify it passes**

Run: `swift test --package-path macos --filter 'SettingsViewTests|DevHavenAppCommandTests'`
Expected: PASS

### Task 3: 新增 updater runtime 封装

**Files:**
- Create: `macos/Sources/DevHavenApp/Update/DevHavenBuildMetadata.swift`
- Create: `macos/Sources/DevHavenApp/Update/DevHavenUpdateController.swift`
- Create: `macos/Sources/DevHavenApp/Update/DevHavenUpdateDiagnostics.swift`
- Test: `macos/Tests/DevHavenAppTests/DevHavenBuildMetadataTests.swift`

**Step 1: Write the failing test**

- 断言 metadata 解析 stable/nightly feed 与非 `.app` 禁用策略正确

**Step 2: Run test to verify it fails**

Run: `swift test --package-path macos --filter DevHavenBuildMetadataTests`
Expected: FAIL

**Step 3: Write minimal implementation**

- 封装 Bundle 元数据读取
- 用 Sparkle 标准 updater controller 包装检查/设置/诊断
- 开发态禁用 updater

**Step 4: Run test to verify it passes**

Run: `swift test --package-path macos --filter DevHavenBuildMetadataTests`
Expected: PASS

### Task 4: Sparkle vendor 与本地打包链路

**Files:**
- Modify: `macos/Package.swift`
- Create: `macos/scripts/setup-sparkle-framework.sh`
- Modify: `macos/scripts/build-native-app.sh`
- Modify: `dev`
- Modify: `.gitignore`
- Test: `macos/Tests/DevHavenCoreTests/NativeBuildScriptUpdateSupportTests.swift`

**Step 1: Write the failing test**

- 断言 Package.swift 已依赖 Sparkle binary target
- 断言 build 脚本会写入 `CFBundleVersion` / `SUFeedURL` / `SUPublicEDKey`
- 断言 `.app` 组装时会嵌入 `Contents/Frameworks/Sparkle.framework`

**Step 2: Run test to verify it fails**

Run: `swift test --package-path macos --filter NativeBuildScriptUpdateSupportTests`
Expected: FAIL

**Step 3: Write minimal implementation**

- 接入 Sparkle binary target
- 新增 setup script
- 更新打包脚本与 `dev`

**Step 4: Run test to verify it passes**

Run: `swift test --package-path macos --filter NativeBuildScriptUpdateSupportTests`
Expected: PASS

### Task 5: stable / nightly appcast 发布基础设施

**Files:**
- Modify: `.github/workflows/release.yml`
- Create: `.github/workflows/nightly.yml`
- Create: `macos/scripts/generate-appcast.sh`
- Create: `macos/scripts/promote-appcast.sh`
- Test: `macos/Tests/DevHavenCoreTests/ReleaseWorkflowUpdateInfrastructureTests.swift`

**Step 1: Write the failing test**

- 断言 stable workflow 包含 staged appcast/promote
- 断言新增 nightly workflow
- 断言 workflow 会准备 Sparkle vendor/tooling

**Step 2: Run test to verify it fails**

Run: `swift test --package-path macos --filter 'ReleaseWorkflowTests|ReleaseWorkflowUpdateInfrastructureTests'`
Expected: FAIL

**Step 3: Write minimal implementation**

- stable workflow 引入 appcast staged/promote
- nightly workflow 引入 nightly appcast
- appcast 生成脚本接 Sparkle `generate_appcast`

**Step 4: Run test to verify it passes**

Run: `swift test --package-path macos --filter 'ReleaseWorkflowTests|ReleaseWorkflowUpdateInfrastructureTests'`
Expected: PASS

### Task 6: 文档与架构说明同步

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`

**Step 1: Update docs**

- 同步新增 Sparkle vendor、更新设置、release/nightly appcast 发布边界

**Step 2: Verify docs reference the new flow**

Run: `rg -n "Sparkle|nightly|appcast|CFBundleVersion|setup-sparkle-framework" README.md AGENTS.md`
Expected: 返回新增说明

**Step 3: Commit**

```bash
git add README.md AGENTS.md docs/plans/2026-03-23-devhaven-upgrade-endgame-design.md docs/plans/2026-03-23-devhaven-upgrade-endgame.md tasks/todo.md
```
