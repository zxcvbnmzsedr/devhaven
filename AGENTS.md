# 项目概览（DevHaven）

DevHaven 当前仓库已经收口为 **纯 macOS 原生主线**：唯一保留的应用源码位于 `macos/`，技术栈为 **SwiftUI + AppKit + Swift Package + GhosttyKit + Sparkle**。

## 当前目录结构

- `dev`
  - 本机开发态入口；负责确保 `macos/Vendor` 可用（必要时复用同仓库其他 worktree 的 vendor）、接入 unified log 并运行 `swift run --package-path macos DevHavenApp`
- `release`
  - 本机 release 打包入口；固定委托 `bash macos/scripts/build-native-app.sh --release`，并透传其余参数
- `macos/Package.swift`
  - 原生子工程入口
- `macos/Sources/DevHavenApp/`
  - 原生 UI、窗口壳、GhosttyKit 宿主、设置页、终端工作区视图、Sparkle updater 运行时
- `macos/Sources/DevHavenApp/Update/`
  - Sparkle 相关的 bundle 元数据解析、appcast 手动检查、更新诊断与 updater controller
- `macos/Sources/DevHavenApp/AgentResources/`
  - 随 App bundle 分发的 Claude / Codex wrapper、Claude hook 与 signal emit 脚本
  - `shell/devhaven-agent-path.{zsh,bash}` 负责在用户 shell startup 可能重写 PATH 后重新把 Agent wrapper bin 目录归一化到 PATH 首位；不能只判断“路径是否存在”，因为用户 rc 可能把 Node / npm bin 再次顶到最前面
- `macos/Sources/DevHavenApp/DevHavenAppResourceLocator.swift`
  - App bundle 资源定位器；统一解析 `DevHavenNative_DevHavenApp.bundle`、`GhosttyResources` 与 `AgentResources`
- `macos/Sources/DevHavenApp/WorkspaceAgentStatusAccessory.swift`
  - 侧边栏 Agent 状态图标 / 文案映射；只负责展示语义，不负责状态聚合
- `macos/Sources/DevHavenApp/WorkspaceRunToolbarView.swift`
  - workspace 顶部右侧的轻量运行控制区；负责展示当前项目 `Project.runConfigurations` 运行配置菜单，以及 Run / Stop / Logs / 配置按钮，不直接持有进程或日志真相源
- `macos/Sources/DevHavenApp/WorkspaceRunConsolePanel.swift`
  - workspace 底部 Run Console；只负责按运行配置复用 tab、日志文本展示与“清空显示 / 打开日志 / 收起”入口，不直接启动或停止进程
- `macos/Sources/DevHavenApp/WorkspaceScriptConfigurationSheet.swift`
  - 当前项目的 typed 运行配置面板（`WorkspaceRunConfigurationSheet`）；负责编辑 `Project.runConfigurations`，首批支持 `customShell` 与 `remoteLogViewer`，不再依赖 Settings 里的通用脚本模板入口
- `macos/Sources/DevHavenApp/WorkspaceTerminalCommands.swift`
  - 工作区 terminal 的查找类菜单命令与 FocusedValue key；只负责把 App 菜单动作桥接到当前 focused pane，不持有 pane/runtime 真相源
- `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceCallbackContext.swift`
  - Ghostty surface callback 的稳定 userdata 宿主；负责在 surface teardown 与跨线程 hop 场景下安全暴露/失效当前 bridge
- `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceSearchOverlay.swift`
  - Ghostty 搜索浮层；只负责终端搜索 UI、输入与 next/previous/close binding action，不负责 pane 选择与菜单分发
- `macos/Sources/DevHavenApp/CodexAgentDisplayHeuristics.swift`
  - Codex 交互可见文本 -> 展示态结构特征（running / waiting）启发式规则；只做纯字符串判断，不读写 signal，供混合状态机 fallback 使用
- `macos/Sources/DevHavenApp/CodexAgentDisplayStateRefresher.swift`
  - 轮询打开 pane 的可见文本并维护 pane 级活动度观测，基于 `signal + notify + activity fallback` 生成 Codex 展示态 override；只作用于 App 运行时内存，不回写 signal store
- `macos/Sources/DevHavenCore/`
  - 数据模型、兼容存储、Git/worktree 服务、ViewModel
- `macos/Sources/DevHavenCore/Models/AppUpdateModels.swift`
  - 更新通道模型（stable / nightly）与设置层共享枚举
- `macos/Sources/DevHavenCore/Models/WorkspaceAgentSessionModels.swift`
  - Claude / Codex 会话 signal schema、状态优先级与编码兼容层
- `macos/Sources/DevHavenCore/Storage/WorkspaceAgentSignalStore.swift`
  - 监听 `~/.devhaven/agent-status/sessions/` signal 文件、清理陈旧状态并向 ViewModel 推送快照
- `macos/Sources/DevHavenCore/Storage/WorkspaceRestoreStore.swift`
  - 工作区恢复快照存储；负责 `~/.devhaven/session-restore/manifest{,.prev}.json` 与 `panes/*.txt` 的主/回退 manifest、pane 文本分文件读写，并保证 current/prev 两代快照引用的 pane 文本同时可回退
- `macos/Sources/DevHavenCore/Restore/WorkspaceRestoreCoordinator.swift`
  - 工作区恢复协调器；负责启动 hydrate、自动保存节流、pane 上下文 merge 与空工作区时清理恢复快照
- `macos/Sources/DevHavenApp/WorkspaceNotificationPresenter.swift`
  - 工作区系统通知 / 声音提醒 presenter；统一处理通知权限与本地提醒
- `macos/Sources/DevHavenApp/WorkspaceNotificationPopover.swift`
  - 工作区通知 popover 与 bell 入口视图
- `macos/Sources/DevHavenCore/Models/WorkspaceNotificationModels.swift`
  - 工作区运行时通知、未读状态与任务状态模型
- `macos/Sources/DevHavenCore/Models/WorkspaceRunModels.swift`
  - workspace run configuration / reused session / console state / manager event 模型；描述运行配置、typed executable（shell/process）、按配置复用的会话槽位与底部 console 展示态，不直接执行命令
- `macos/Sources/DevHavenCore/Run/WorkspaceRunLogStore.swift`
  - Run Console 日志文件存储；统一负责 `~/.devhaven/run-logs/` 下的日志文件创建与追加
- `macos/Sources/DevHavenCore/Run/WorkspaceRunManager.swift`
  - workspace 运行命令管理器；负责 `Process + Pipe` 启动脚本命令、实时输出桥接、停止进程与 session 生命周期事件，不参与 SwiftUI 布局
- `macos/Tests/`
  - 原生 UI / Core 测试
- `macos/scripts/build-native-app.sh`
  - 原生 `.app` 本地打包脚本；负责嵌入 Sparkle.framework，并写入 `CFBundleVersion` / `SUFeedURL` / `DevHavenUpdateDeliveryMode` / 下载页 URL / `SUPublicEDKey`
- `macos/scripts/setup-ghostty-framework.sh`
  - 准备 `macos/Vendor` 的 Ghostty framework / resources
- `macos/scripts/setup-sparkle-framework.sh`
  - 准备 `macos/Vendor` 的 Sparkle.xcframework 与 SparkleTools
- `macos/scripts/create-universal-app.sh`
  - 把 arm64 / x86_64 `.app` 合成 universal `.app`，供 Sparkle feed 发布使用
- `macos/scripts/generate-appcast.sh`
  - Sparkle `generate_appcast` 的统一封装，负责生成 stable/nightly appcast
- `macos/scripts/promote-appcast.sh`
  - 将 staged appcast 提升到固定 alias release（如 `stable-appcast` / `nightly`）
- `macos/Resources/AppMetadata.json`
  - 原生打包元数据真相源（`productName` / `bundleIdentifier` / `version` / `buildNumber` / `stableFeedURL` / `nightlyFeedURL` / `updateDeliveryMode` / stable/nightly 下载页）
- `macos/Resources/DevHaven.icns`
  - 原生 App 图标
- `.github/workflows/release.yml`
  - stable release / staged appcast / universal updater 资产发布链路
- `.github/workflows/nightly.yml`
  - nightly 独立构建、独立 appcast feed 与 alias promote 链路
- `docs/releases/`
  - 发布说明
- `tasks/todo.md`
  - 当前任务记录与 Review
- `tasks/lessons.md`
  - 可复用教训

## 模块边界

### 1) 原生 App 壳
- 入口：`macos/Sources/DevHavenApp/DevHavenApp.swift`
- 退出保护：`macos/Sources/DevHavenApp/AppQuitGuard.swift`
- 主界面壳：`AppRootView.swift`、`MainContentView.swift`、`ProjectDetailRootView.swift`
- 终端工作区壳：`WorkspaceShellView.swift`、`WorkspaceHostView.swift`、`WorkspaceProjectListView.swift`
  - `DevHavenApp.swift` 还负责单主窗口生命周期与 App 级命令收口：通过 `NSApplicationDelegateAdaptor` 阻止“最后一个窗口关闭即退出”，并在应用重新激活 / dock reopen 时恢复主窗口；`CommandGroup(replacing: .appTermination)` 也在这里接管
  - `AppQuitGuard.swift` 负责 `⌘Q` / “退出 DevHaven” 的双击退出保护、1.5 秒确认窗口与轻提示 toast；第一次请求不应直接 terminate，第二次才允许退出
  - `AppRootView` 负责在 scene 进入 `inactive/background` 与 `willTerminate` 时同步 flush 工作区恢复快照；不要把退出时保存散落到多个 view
  - `AppRootView` 还负责注入 `⌘W` 关闭级联：先关闭当前浮层，再按 pane -> tab -> 退出 workspace -> 主页关闭窗口 的顺序收口；只有已经回到主页时，主窗口关闭提醒桥才应参与；同一层还负责承载 `⌘Q` 的 toast 轻提示展示
  - `WorkspaceShellView` 负责把已加载 pane 的 cwd/title/可见文本快照桥接给 `NativeAppViewModel`；Core 层只接收 `WorkspaceTerminalRestoreContext`，不要反向依赖 App 侧 `GhosttySurfaceHostModel`
- 工作区通知 / Agent 体验：`WorkspaceNotificationPopover.swift`、`WorkspaceNotificationPresenter.swift`、`WorkspaceAgentStatusAccessory.swift`
- 工作区运行体验：`WorkspaceRunToolbarView.swift`、`WorkspaceRunConsolePanel.swift`、`WorkspaceScriptConfigurationSheet.swift`
  - `WorkspaceHostView` 负责把当前 workspace/project 的 run state 接到顶部 `WorkspaceRunToolbarView` 与底部 `WorkspaceRunConsolePanel`；顶部 `配置` 入口只打开当前项目的 typed 运行配置面板，Settings 不再承载脚本模板管理；App 层只做按钮桥接与日志展示，不要在 SwiftUI 里直接 new `Process`
- 更新体验：`Update/DevHavenBuildMetadata.swift`、`Update/DevHavenUpdateDiagnostics.swift`、`Update/DevHavenUpdateController.swift`
  - `DevHavenBuildMetadata` 只负责从 bundle 解析 `CFBundleVersion`、stable/nightly feed URL、下载页 URL、交付模式与 `SUPublicEDKey`；开发态 `swift run` 或缺失 feed 时必须禁用检查更新
  - `DevHavenUpdateController` 负责把设置页 / 菜单动作桥接到 Sparkle 或 appcast 手动检查，并维护可复制的升级诊断文本；默认 manual-download 模式下只能“检查更新 + 打开下载页”，Sparkle delegate 回调不能直接跨进 `@MainActor` conformance，需通过独立 bridge 回主线程更新状态
- Ghostty 集成：`Ghostty/` 目录下的 runtime / surface / host / view 相关文件
  - 剪贴板与路径粘贴语义由 `Ghostty/GhosttyPasteboard.swift` 收口，`GhosttyRuntime` 只负责把解析结果桥接给 libghostty
  - `GhosttySurfaceBridge` 现在同时桥接 desktop notification / progress report / bell / search 状态；Bridge 只翻译终端事件，不做排序、已读、系统通知、菜单分发等应用决策
  - `GhosttySurfaceCallbackContext` 是 Ghostty C callback 的 userdata 真相源；跨线程回调必须先拿稳定 context，再在真正执行时解析 active bridge，不能继续把 `GhosttySurfaceBridge` 的裸指针直接跨队列传递
  - `GhosttyRuntimeEnvironmentBuilder` / `GhosttySurfaceHostModel` 负责把 `DEVHAVEN_AGENT_SIGNAL_DIR`、`DEVHAVEN_AGENT_RESOURCES_DIR` 与 wrapper `PATH` 注入内嵌终端；`GhosttySurfaceHostModel` 还负责把当前 pane 的搜索命令收口为最小动作入口（start / selection / next / previous / end），但不持有第二套搜索真相源；终端环境注入在 host 层收口，不要把 bundle 解析散落到 view / script / ViewModel 多处
  - `GhosttySurfaceHostModel.currentVisibleText()` 只用于 App 内部读取 pane 当前可见文本，给 Codex 展示态修正做只读输入；不要把它升级成 signal 主链或写回存储
  - 搜索 UI 的展示条件以 `GhosttySurfaceState.searchNeedle` 为唯一真相源；不要再在 `WorkspaceShellView` / `DevHavenApp` 复制一份“是否显示搜索栏”的平行状态
  - App 菜单的搜索动作必须经由 `WorkspaceTerminalCommands` + `FocusedValue` 路由到当前 focused pane；不要在 `DevHavenApp.swift` 里直接查 pane/store/runtime，避免把场景态耦合回全局菜单层
  - 对 zsh / bash 这类会继续加载用户 rc 文件的 shell，不能假设“进程启动时注入的 PATH”会一直保留；如果 Agent wrapper 依赖 PATH 前缀，必须在 shell integration 的 prompt/precmd 阶段再补一次，并把 wrapper bin 归一化到 PATH 首位，避免被用户 `.zshrc` / `.bashrc` 覆盖后直接绕过 wrapper
  - `DevHavenAppResourceBundleLocator` 是非 actor 的 bundle candidate 真相源；`GhosttyAppRuntime` 与 `DevHavenAppResourceLocator` 都应复用它，不要在非 UI 资源查找逻辑里直接耦合 `@MainActor` runtime
  - `AgentResources/bin/claude` 负责给 Claude 注入 hooks 与 session id；`AgentResources/hooks/devhaven-claude-hook` 把结构化 hook 事件写成 signal；`AgentResources/bin/codex` 负责写 running/completed/failed signal，并通过单次 CLI config override 给真实 Codex 注入 `notify`；`AgentResources/bin/devhaven-codex-notify` 负责把 `agent-turn-complete` payload 写成 waiting signal；`devhaven-agent-emit` 是唯一 signal 落盘入口
  - split/tree 重排后的 pane 复用必须等 `GhosttySurfaceScrollView` 真正完成 attach/layout，再由 `GhosttySurfaceHostModel.surfaceViewDidAttach(...)` 重放 `occlusion / focus` 等 attachment-sensitive 状态；不要在 `acquireSurfaceView()` 这种“容器还没换完”的阶段提前 replay
  - 如果 surface 在复用前已经拿到窗口真实焦点，`GhosttyTerminalSurfaceView.prepareForContainerReuse()` / `tearDown()` 必须先释放 owned `firstResponder`，再清本地 focus/cache；不要让带着旧 responder 身份的 surface 直接挂到新的 split 容器
  - `GhosttyTerminalSurfaceView` 的焦点补偿必须是**可取消**的；任何延迟 focus retry 在 view detach / tearDown / becomeFirstResponder 后都要取消，避免后台 Task 跨 pane / 跨测试继续操作旧 window

### 2) 原生业务与兼容层
- ViewModel：`macos/Sources/DevHavenCore/ViewModels/`
- Git / worktree：`NativeGitWorktreeService.swift`
- 数据兼容：`LegacyCompatStore.swift`
- 模型：`macos/Sources/DevHavenCore/Models/`
- `AppSettings` 现在额外持久化 `updateChannel`、`updateAutomaticallyChecks`、`updateAutomaticallyDownloads`；默认值必须兼容旧配置回退，不能因为新增字段破坏现有 `app_state.json` 读取
- `Project.isGitRepository` 是项目是否为 Git 仓库的**轻量真相源**；目录刷新阶段只能基于 `.git` / worktree 做便宜判定，不能再把 `gitCommits > 0` 当成 repo 类型判断
- `NativeAppViewModel.refreshProjectCatalog()` 现在只负责目录发现、目录元数据更新与 worktree 过滤；不要在目录刷新链路里再执行 `git rev-list` / `git log` 这类昂贵 Git 子进程
- `NativeAppViewModel.refreshGitStatistics{Async}` 现在统一负责 `gitCommits`、`gitLastCommit`、`gitLastCommitMessage` 与 `gitDaily` 的刷新；目标集应基于 `isGitRepository`，而不是旧的 commitCount 缓存
- `LegacyCompatStore.updateProjectsGitMetadata(...)` 是 Git 元数据的局部写回入口；它必须按 path 保留未知字段，避免为了更新 Git 统计而重写整份项目对象
- `NativeAppViewModel` 现在额外维护按 `projectPath` 组织的运行时工作区注意力状态（通知列表、未读数、pane 任务状态、pane Agent 状态 / 摘要 / 类型）；这部分只存在内存，不写回 `projects.json`
- `NativeAppViewModel` 现在还维护按 `projectPath` 组织的 workspace run console 状态（已创建 sessions、当前选中 session、当前选中脚本、底部 console 显隐）；这部分只存在内存，不写回 `projects.json` / `app_state.json`
- workspace Run Console 的运行配置来源固定由当前项目 `Project.runConfigurations` 推导；首批类型只有 `customShell` 与 `remoteLogViewer`，其中 `remoteLogViewer` 直接渲染为 `/usr/bin/ssh` 结构化进程参数，不再依赖 shared scripts / manifest / helper 模板体系；同一配置重复 Run 时必须复用同一个 console tab，而不是无限累积 execution history；真正的执行与停止必须经由 `WorkspaceRunManager`，不要让 `WorkspaceRunToolbarView` / `WorkspaceRunConsolePanel` 自己直接持有 `Process`
- `WorkspaceAgentSignalStore` 只负责读取 / 归一化 signal 文件与目录监听；sidebar 排序、group 聚合、显示文案仍属于 `NativeAppViewModel` / App UI，避免把 UI 规则塞回存储层
- `NativeAppViewModel` 现在还负责工作区快照恢复的接线：仅在首轮 `load()` 且当前没有打开会话时应用 `WorkspaceRestoreCoordinator.loadSnapshot()`；后续 catalog refresh / 普通 reload 不得再次覆盖运行中 workspace
- 工作区恢复边界明确是 **workspace snapshot**，不是 live terminal：只恢复已打开项目、tab/pane 拓扑，以及 pane 的 cwd/标题/文本提示；绝不恢复原 shell/PTY 进程
- pane 快照文本只能存到 `~/.devhaven/session-restore/panes/*.txt`，不要把大段终端文本塞进 `app_state.json` / `projects.json`
- Codex 的“等待输入”仍属于**展示态语义**而不是新协议字段，但当前主链已升级为 `wrapper 进程态 + official notify turn-complete + App 活动度 fallback`：signal store 继续收口运行时 signal，`NativeAppViewModel` / App UI 再按活动度与可见文本做运行时修正
- workspace 侧边栏里 **root project 卡片的 Agent 状态只反映 root project 自己的 pane**；worktree 的 Agent 状态只显示在各自 worktree 行，不要再向父级卡片冒泡，避免把子 worktree 活动误读成父项目整体状态
- signal 文件名不是原始 `terminalSessionId`，而是其稳定安全编码；因为 workspace/session 标识可能包含 `/`，脚本与 store 必须复用同一命名规则，不能直接把原始 session id 当文件名
- 本地数据目录：`~/.devhaven/`
  - `app_state.json`
  - `projects.json`
  - `agent-status/sessions/*.json`
- `session-restore/manifest.json`
- `session-restore/manifest.prev.json`
- `session-restore/panes/*.txt`
- `run-logs/*.log`
- `PROJECT_NOTES.md`
- `PROJECT_TODO.md`

### 3) 原生发布主链
- 本地测试：`swift test --package-path macos`
- 本地打包：`./release`（内部调用 `bash macos/scripts/build-native-app.sh --release`）
- GitHub Release：`.github/workflows/release.yml`
- Nightly 发布：`.github/workflows/nightly.yml`
- 3.0.0 起 release/nightly workflow **不再依赖 Node / pnpm / Tauri**
- stable / nightly 都通过 matrix 同时构建 `arm64` 与 `x86_64` 两个 macOS 产物，二者都跑在 `macos-26`：
  - `arm64`：原生 runner 架构直接构建，并执行 `swift test --package-path macos`
  - `x86_64`：通过 `DEVHAVEN_NATIVE_TRIPLE=x86_64-apple-macosx14.0` 交叉构建，并额外执行一次 `swift build --package-path macos -c debug --triple x86_64-apple-macosx14.0` 做编译验证
- matrix 产物会先各自上传架构 zip，再由后置 job 用 `create-universal-app.sh` 合成 `DevHaven-macos-universal.zip`；Sparkle appcast 只指向 universal 安装包，避免客户端升级链路再做架构分叉判断
- release / nightly workflow 都会先打印 `xcodebuild -version`，并固定 `git fetch` Ghostty 源码（当前 pin：`da10707f93104c5466cd4e64b80ff48f789238a0`）+ `setup-ghostty-framework.sh` / `setup-sparkle-framework.sh` 准备 vendor，再执行测试、打包、appcast 生成
- stable feed 采用 staged appcast：先上传 immutable release assets 与 `appcast-staged.xml`，最后通过 `promote-appcast.sh` 把 feed 提升到 `stable-appcast/appcast.xml`；nightly 同理维护 `nightly/appcast.xml`
- Sparkle appcast 生成脚本会优先复用 alias release 上已发布的旧 appcast，保留历史条目；当前 `maximum-deltas=0`，先以完整包升级为主，后续再扩展 delta 更新

## 当前关键事实

- 仓库内旧的 React / Vite / Tauri / Rust 兼容源码已删除；后续不要再按 `src/`、`src-tauri/`、`package.json`、`vite.config.ts` 这些入口排查问题。
- 根目录 `./dev` 是推荐的本机原生开发态入口；它默认会先确保 `macos/Vendor/` 可用（Ghostty + Sparkle，当前 worktree 缺失时会优先复用同仓库其他 worktree 已准备好的 vendor），再用 macOS unified log 观察 `DevHavenNative` / `com.mitchellh.ghostty`，最后启动 `swift run --package-path macos DevHavenApp`。
- 由于 `./dev` 走的是 `swift run` 直接启动可执行文件而不是 `.app` bundle，macOS `UserNotifications` 在这种开发态下不可安全初始化；`WorkspaceNotificationPresenter` 必须先判断当前进程是否真的是 `.app` bundle，再决定是否调用 `UNUserNotificationCenter`，否则只能降级为提示音 / 应用内通知。
- 根目录 `./release` 是推荐的本机 release 打包入口；它只负责把仓库根作为工作目录，并固定调用 `bash macos/scripts/build-native-app.sh --release`，不要在这里复制第二套打包逻辑。
- DevHaven 内嵌 Ghostty 终端会**优先**读取 `~/.devhaven/ghostty/config` 与 `~/.devhaven/ghostty/config.ghostty`；如果这里还没有 DevHaven 专属配置，则会回退到独立 Ghostty App 的现有全局配置（如 `~/Library/Application Support/com.mitchellh.ghostty/config*`），避免升级后突然丢失用户已有的主题 / 键位 / 字体设置。
- `macos/Vendor/` 不是版本库真相源，只是本机开发时通过 `setup-ghostty-framework.sh` / `setup-sparkle-framework.sh` 准备的本地 vendor 目录；该目录由 `.gitignore` 忽略，不应提交。linked worktree 默认也不会自动继承该目录，需要通过脚本准备或复用现有 vendor。
- 由于 `macos/Package.swift` 的 `GhosttyKit` 是本地 binary target，任何干净 checkout（包括 CI）在跑 `swift test --package-path macos` 前都必须先把有效的 `macos/Vendor/GhosttyKit.xcframework` 准备好。
- 原生打包脚本只依赖：
  - `macos/Resources/AppMetadata.json`
  - `macos/Resources/DevHaven.icns`
  - `macos/Vendor/`（Ghostty + Sparkle，本机准备）
  - `swift build` 产物
- `swift build` 产出的 `DevHavenNative_DevHavenApp.bundle` 会在组装 `.app` 时被复制到 `DevHaven.app/Contents/Resources/`；`GhosttyAppRuntime` 会显式从这个资源 bundle 中解析 `GhosttyResources/ghostty`，不要再假设 release 产物里直接依赖 `Bundle.module` 就一定能找到资源。
- `build-native-app.sh` 现在还会把 `Sparkle.framework` 嵌入 `Contents/Frameworks/`，并在主可执行文件上注入 `@executable_path/../Frameworks` 运行时 `rpath`，避免 release `.app` 启动时找不到 Sparkle；同时写入 `CFBundleVersion`、`SUFeedURL`、`DevHavenStableFeedURL`、`DevHavenNightlyFeedURL`、`DevHavenUpdateDeliveryMode`、stable/nightly 下载页与 `SUPublicEDKey` 到 `Info.plist`；当前默认交付模式为 `manualDownload`。
- `DevHavenBuildMetadata` 现在区分 `supportsUpdateChecks` 与 `supportsAutomaticUpdates`：前者只要求当前进程运行于 `.app` bundle 且 stable/nightly feed 存在；后者还要求交付模式为 `automatic` 且 `SUPublicEDKey` 非空。开发态 `swift run` 与测试态应默认禁用检查更新。
- `app_state.json` 的 `settings` 现在额外包含升级通道、自动检查更新、自动下载更新；设置页保存时必须透传这些字段，避免被旧 UI 重建逻辑覆盖。
- release workflow / nightly workflow 的 Sparkle feed 固定别名分别是 `stable-appcast/appcast.xml` 与 `nightly/appcast.xml`；真正的安装包仍挂在不可变的版本 tag / nightly 时间戳 tag 上，客户端永远先看 feed、再下载 immutable asset。
- `AgentResources/` 也随同 `DevHavenNative_DevHavenApp.bundle` 一起打包；wrapper / hook 只在内嵌终端显式注入的环境变量存在时生效，外部 shell 直接调用真实 `claude` / `codex` 不应被 DevHaven 强耦合。
- Claude 会话状态主链是 `wrapper -> hooks -> signal JSON -> WorkspaceAgentSignalStore -> NativeAppViewModel -> Sidebar`；Codex 当前主链已升级为 `wrapper running/completed/failed -> official notify 写 waiting -> signal JSON -> Store -> NativeAppViewModel -> Sidebar`，App 只在 `running/waiting` 两态之间做活动度 / 可见文本 fallback 修正。不要把终端内容分析当主真相源，也不要把 heuristic 结果反写回 signal。
- `WorkspaceAgentSessionSignal.updatedAt` 需要兼容 App 侧编码与脚本 ISO8601 落盘；读取 signal 时必须接受 Unix 时间戳与 ISO8601 字符串两种格式。
- `app_state.json` 的 `settings` 现在包含工作区通知开关：应用内通知、提示音、系统通知、收到通知后 worktree 置顶；通知内容本身不持久化。
- Agent signal 文件属于运行时临时状态：`running / waiting` 会按 pid + 超时清理，`completed / failed` 只保留短暂摘要后回落为 idle；不要把这类瞬时状态写回 `projects.json` / `app_state.json`。
- 工作区恢复快照使用 `manifest.json` + `manifest.prev.json` 回退；pane 文本按 **每次保存唯一的 `snapshotTextRef`** 单独落盘，`prune` 只能在新 manifest 成功写入后执行，且必须同时保留 current/prev 两代 manifest 引用的 pane 文本。恢复后始终新起 shell，但不额外弹出“已恢复上下文快照”的提示 UI。

## 本次变更原因

- 为 DevHaven 建立完整的 macOS 升级基础设施：客户端新增 stable / nightly 更新偏好、appcast 手动检查 / Sparkle runtime 与可复制诊断，发布侧补齐 Sparkle vendor、通用安装包、staged appcast 与 alias feed promote。
- 解决“当前仓库只有原生打包，没有长期可演进升级主链”的缺口：后续 stable/nightly 都必须沿 `immutable asset -> appcast-staged -> alias promote` 这条单主链演进，避免资产未就绪就让客户端看到新 feed。
- 补齐 DevHaven 内嵌 Ghostty 的宿主搜索能力：当前需要通过宿主侧菜单命令、focused pane 路由、search action bridge 与搜索浮层形成完整闭环，不能误以为 libghostty 会自动提供可见 find bar。
- 补齐 DevHaven 的非 live 工作区恢复链路：用户关闭 App 后，下次启动需要优先恢复已打开项目、tab/pane 布局和 pane 上下文快照，但不引入 daemon / PTY 保活。
- 收口 DevHaven 的单主窗口关闭语义：`⌘W` 误关整个主窗口时必须先提醒用户，同时 last-window close 不应直接把应用判定为“彻底退出”，应用再次激活时应能恢复主窗口。

## 修改约束

- 如果改动涉及目录结构、模块职责、打包链路或版本真相源，必须同步更新本文件。
- 新的架构说明只记录当前仍然存在并参与主链的模块；不要把已删除的旧栈重新写回本文件。
- 做删除类改动时，优先同时删除对应的构建入口、文档入口和设置入口，避免留下“代码没了但说明还在”的半残状态。
