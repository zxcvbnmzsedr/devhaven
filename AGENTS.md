# 项目概览（DevHaven）

DevHaven 当前仓库已经收口为 **纯 macOS 原生主线**：唯一保留的应用源码位于 `macos/`，技术栈为 **SwiftUI + AppKit + Swift Package + GhosttyKit**。

## 当前目录结构

- `macos/Package.swift`
  - 原生子工程入口
- `macos/Sources/DevHavenApp/`
  - 原生 UI、窗口壳、GhosttyKit 宿主、设置页、终端工作区视图
- `macos/Sources/DevHavenCore/`
  - 数据模型、兼容存储、Git/worktree 服务、ViewModel
- `macos/Tests/`
  - 原生 UI / Core 测试
- `macos/scripts/build-native-app.sh`
  - 原生 `.app` 本地打包脚本
- `macos/scripts/setup-ghostty-framework.sh`
  - 准备 `macos/Vendor` 的 Ghostty framework / resources
- `macos/Resources/AppMetadata.json`
  - 原生打包元数据真相源（`productName` / `bundleIdentifier` / `version`）
- `macos/Resources/DevHaven.icns`
  - 原生 App 图标
- `docs/releases/`
  - 发布说明
- `tasks/todo.md`
  - 当前任务记录与 Review
- `tasks/lessons.md`
  - 可复用教训

## 模块边界

### 1) 原生 App 壳
- 入口：`macos/Sources/DevHavenApp/DevHavenApp.swift`
- 主界面壳：`AppRootView.swift`、`MainContentView.swift`、`ProjectDetailRootView.swift`
- 终端工作区壳：`WorkspaceShellView.swift`、`WorkspaceHostView.swift`、`WorkspaceProjectListView.swift`
- Ghostty 集成：`Ghostty/` 目录下的 runtime / surface / host / view 相关文件

### 2) 原生业务与兼容层
- ViewModel：`macos/Sources/DevHavenCore/ViewModels/`
- Git / worktree：`NativeGitWorktreeService.swift`
- 数据兼容：`LegacyCompatStore.swift`
- 模型：`macos/Sources/DevHavenCore/Models/`
- 本地数据目录：`~/.devhaven/`
  - `app_state.json`
  - `projects.json`
  - `PROJECT_NOTES.md`
  - `PROJECT_TODO.md`
  - `~/.devhaven/scripts/*`

### 3) 原生发布主链
- 本地测试：`swift test --package-path macos`
- 本地打包：`bash macos/scripts/build-native-app.sh --release`
- GitHub Release：`.github/workflows/release.yml`
- 3.0.0 起 release workflow **不再依赖 Node / pnpm / Tauri**
- release workflow 当前固定跑在 `macos-26` runner 上，并先打印 `xcodebuild -version`，避免和本地 / GitHub runner 的 Xcode 主版本再度漂移
- release workflow 会先 `git fetch` 固定 commit 的 Ghostty 源码（当前 pin：`da10707f93104c5466cd4e64b80ff48f789238a0`），运行 `setup-ghostty-framework.sh` 准备临时 `macos/Vendor/`，再执行 `swift test` / 原生打包

## 当前关键事实

- 仓库内旧的 React / Vite / Tauri / Rust 兼容源码已删除；后续不要再按 `src/`、`src-tauri/`、`package.json`、`vite.config.ts` 这些入口排查问题。
- `macos/Vendor/` 不是版本库真相源，只是本机开发时通过 `setup-ghostty-framework.sh` 准备的 Ghostty vendor 目录；该目录由 `.gitignore` 忽略，不应提交。
- 由于 `macos/Package.swift` 的 `GhosttyKit` 是本地 binary target，任何干净 checkout（包括 CI）在跑 `swift test --package-path macos` 前都必须先把有效的 `macos/Vendor/GhosttyKit.xcframework` 准备好。
- 原生打包脚本只依赖：
  - `macos/Resources/AppMetadata.json`
  - `macos/Resources/DevHaven.icns`
  - `macos/Vendor/`（本机准备）
  - `swift build` 产物

## 修改约束

- 如果改动涉及目录结构、模块职责、打包链路或版本真相源，必须同步更新本文件。
- 新的架构说明只记录当前仍然存在并参与主链的模块；不要把已删除的旧栈重新写回本文件。
- 做删除类改动时，优先同时删除对应的构建入口、文档入口和设置入口，避免留下“代码没了但说明还在”的半残状态。
