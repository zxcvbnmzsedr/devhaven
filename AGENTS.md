# 项目概览（DevHaven）

DevHaven 当前仓库已经收口为 **纯 macOS 原生主线**：唯一保留的应用源码位于 `macos/`，技术栈为 **SwiftUI + AppKit + Swift Package + GhosttyKit**。

## 当前目录结构

- `dev`
  - 本机开发态入口；负责确保 `macos/Vendor` 可用（必要时复用同仓库其他 worktree 的 vendor）、接入 unified log 并运行 `swift run --package-path macos DevHavenApp`
- `release`
  - 本机 release 打包入口；固定委托 `bash macos/scripts/build-native-app.sh --release`，并透传其余参数
- `macos/Package.swift`
  - 原生子工程入口
- `macos/Sources/DevHavenApp/`
  - 原生 UI、窗口壳、GhosttyKit 宿主、设置页、终端工作区视图
- `macos/Sources/DevHavenCore/`
  - 数据模型、兼容存储、Git/worktree 服务、ViewModel
- `macos/Sources/DevHavenApp/WorkspaceNotificationPresenter.swift`
  - 工作区系统通知 / 声音提醒 presenter；统一处理通知权限与本地提醒
- `macos/Sources/DevHavenApp/WorkspaceNotificationPopover.swift`
  - 工作区通知 popover 与 bell 入口视图
- `macos/Sources/DevHavenCore/Models/WorkspaceNotificationModels.swift`
  - 工作区运行时通知、未读状态与任务状态模型
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
- 工作区通知体验：`WorkspaceNotificationPopover.swift`、`WorkspaceNotificationPresenter.swift`
- Ghostty 集成：`Ghostty/` 目录下的 runtime / surface / host / view 相关文件
  - 剪贴板与路径粘贴语义由 `Ghostty/GhosttyPasteboard.swift` 收口，`GhosttyRuntime` 只负责把解析结果桥接给 libghostty
  - `GhosttySurfaceBridge` 现在同时桥接 desktop notification / progress report / bell；Bridge 只翻译终端事件，不做排序、已读、系统通知等应用决策
  - split/tree 重排后的 pane 复用必须等 `GhosttySurfaceScrollView` 真正完成 attach/layout，再由 `GhosttySurfaceHostModel.surfaceViewDidAttach(...)` 重放 `occlusion / focus` 等 attachment-sensitive 状态；不要在 `acquireSurfaceView()` 这种“容器还没换完”的阶段提前 replay
  - 如果 surface 在复用前已经拿到窗口真实焦点，`GhosttyTerminalSurfaceView.prepareForContainerReuse()` / `tearDown()` 必须先释放 owned `firstResponder`，再清本地 focus/cache；不要让带着旧 responder 身份的 surface 直接挂到新的 split 容器

### 2) 原生业务与兼容层
- ViewModel：`macos/Sources/DevHavenCore/ViewModels/`
- Git / worktree：`NativeGitWorktreeService.swift`
- 数据兼容：`LegacyCompatStore.swift`
- 模型：`macos/Sources/DevHavenCore/Models/`
- `NativeAppViewModel` 现在额外维护按 `projectPath` 组织的运行时工作区注意力状态（通知列表、未读数、pane 任务状态）；这部分只存在内存，不写回 `projects.json`
- 本地数据目录：`~/.devhaven/`
  - `app_state.json`
  - `projects.json`
  - `PROJECT_NOTES.md`
  - `PROJECT_TODO.md`
  - `~/.devhaven/scripts/*`

### 3) 原生发布主链
- 本地测试：`swift test --package-path macos`
- 本地打包：`./release`（内部调用 `bash macos/scripts/build-native-app.sh --release`）
- GitHub Release：`.github/workflows/release.yml`
- 3.0.0 起 release workflow **不再依赖 Node / pnpm / Tauri**
- release workflow 当前通过 matrix 同时构建 `arm64` 与 `x86_64` 两个 macOS 产物，二者都跑在 `macos-26`：
  - `arm64`：原生 runner 架构直接构建，并执行 `swift test --package-path macos`
  - `x86_64`：通过 `DEVHAVEN_NATIVE_TRIPLE=x86_64-apple-macosx14.0` 交叉构建，并额外执行一次 `swift build --package-path macos -c debug --triple x86_64-apple-macosx14.0` 做编译验证
- 每个 release job 都会先打印 `xcodebuild -version`，避免和本地 / GitHub runner 的 Xcode 主版本再度漂移
- release workflow 会先 `git fetch` 固定 commit 的 Ghostty 源码（当前 pin：`da10707f93104c5466cd4e64b80ff48f789238a0`），运行 `setup-ghostty-framework.sh` 准备临时 `macos/Vendor/`，再执行 `swift test` / 原生打包
- GitHub release asset 名称按架构区分，当前为 `DevHaven-macos-arm64.zip` 与 `DevHaven-macos-x86_64.zip`，避免 matrix job 互相覆盖

## 当前关键事实

- 仓库内旧的 React / Vite / Tauri / Rust 兼容源码已删除；后续不要再按 `src/`、`src-tauri/`、`package.json`、`vite.config.ts` 这些入口排查问题。
- 根目录 `./dev` 是推荐的本机原生开发态入口；它默认会先确保 `macos/Vendor/` 可用（当前 worktree 缺失时会优先复用同仓库其他 worktree 已准备好的 vendor），再用 macOS unified log 观察 `DevHavenNative` / `com.mitchellh.ghostty`，最后启动 `swift run --package-path macos DevHavenApp`。
- 根目录 `./release` 是推荐的本机 release 打包入口；它只负责把仓库根作为工作目录，并固定调用 `bash macos/scripts/build-native-app.sh --release`，不要在这里复制第二套打包逻辑。
- DevHaven 内嵌 Ghostty 终端会**优先**读取 `~/.devhaven/ghostty/config` 与 `~/.devhaven/ghostty/config.ghostty`；如果这里还没有 DevHaven 专属配置，则会回退到独立 Ghostty App 的现有全局配置（如 `~/Library/Application Support/com.mitchellh.ghostty/config*`），避免升级后突然丢失用户已有的主题 / 键位 / 字体设置。
- `macos/Vendor/` 不是版本库真相源，只是本机开发时通过 `setup-ghostty-framework.sh` 准备的 Ghostty vendor 目录；该目录由 `.gitignore` 忽略，不应提交。linked worktree 默认也不会自动继承该目录，需要通过脚本准备或复用现有 vendor。
- 由于 `macos/Package.swift` 的 `GhosttyKit` 是本地 binary target，任何干净 checkout（包括 CI）在跑 `swift test --package-path macos` 前都必须先把有效的 `macos/Vendor/GhosttyKit.xcframework` 准备好。
- 原生打包脚本只依赖：
  - `macos/Resources/AppMetadata.json`
  - `macos/Resources/DevHaven.icns`
  - `macos/Vendor/`（本机准备）
  - `swift build` 产物
- `swift build` 产出的 `DevHavenNative_DevHavenApp.bundle` 会在组装 `.app` 时被复制到 `DevHaven.app/Contents/Resources/`；`GhosttyAppRuntime` 会显式从这个资源 bundle 中解析 `GhosttyResources/ghostty`，不要再假设 release 产物里直接依赖 `Bundle.module` 就一定能找到资源。
- `app_state.json` 的 `settings` 现在包含工作区通知开关：应用内通知、提示音、系统通知、收到通知后 worktree 置顶；通知内容本身不持久化。

## 本次变更原因

- 为 DevHaven 引入接近 Supacode 的完整工作区通知体验：终端事件可进入应用运行时状态层，在侧边栏显示 bell / spinner、通过 popover 回跳对应 pane，并按设置决定是否发送系统通知或播放提示音。

## 修改约束

- 如果改动涉及目录结构、模块职责、打包链路或版本真相源，必须同步更新本文件。
- 新的架构说明只记录当前仍然存在并参与主链的模块；不要把已删除的旧栈重新写回本文件。
- 做删除类改动时，优先同时删除对应的构建入口、文档入口和设置入口，避免留下“代码没了但说明还在”的半残状态。
