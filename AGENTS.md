# 项目概览（DevHaven）

DevHaven 是一个基于 **Tauri + React** 的桌面应用，并已新增 **Web 运行时（浏览器 + 本机 Rust HTTP/WS 服务）**：前端负责 UI/交互（React + Vite + UnoCSS），后端负责本地能力（Rust + Tauri Commands / Web API：文件扫描、Git 读取、存储、PTY 终端等）。

当前仓库还新增了一条 **macOS 原生重写主线（`macos/` Swift Package）**：`DevHavenApp` 负责原生窗口与 SwiftUI 内容视图，`DevHavenCore` 负责兼容读取 `~/.devhaven/*` 与项目文档，并为后续 Rust Core / 原生终端子系统继续预留边界。当前 Phase A 已落地项目列表 / 详情 / 备注 / Todo / 设置 / 回收站 / 自动化只读视图的原生骨架，**终端工作区仍未迁入该子工程**。

## 1) 开发语言 + 框架

### 前端（UI）
- 语言：TypeScript
- 框架：React（见 `package.json`）
- 构建：Vite（见 `vite.config.ts`）
- 样式：UnoCSS（见 `unocss.config.ts`，入口 `src/main.tsx` 引入 `uno.css`）
- 入口：`src/main.tsx` → `src/App.tsx`

### 桌面/后端（Tauri）
- 语言：Rust
- 框架：Tauri v2（见 `src-tauri/`、`src-tauri/tauri.conf.json`、`src-tauri/Cargo.toml`）
- 前后端通信：前端统一命令层 `src/platform/commandClient.ts`（Tauri 下走 `invoke`）↔ 后端 `#[tauri::command]`（集中在 `src-tauri/src/lib.rs`）
- 插件：dialog/opener/clipboard/log（在 `src-tauri/src/lib.rs` 初始化）

### Web 后端（Browser Runtime Bridge）
- 语言：Rust
- 框架：Axum（见 `src-tauri/src/web_server.rs`、`src-tauri/Cargo.toml`）
- 通信：前端 `src/platform/commandClient.ts`（Web 下 `POST /api/cmd/:command`）+ `src/platform/eventClient.ts`（`GET /api/ws`）
- 事件总线：`src-tauri/src/web_event_bus.rs`（统一事件封装 `{event,payload,ts}`）

### 本地数据落盘位置（便于排查）
- 应用数据目录：`~/.devhaven/`（实现：`src-tauri/src/storage.rs`）
  - `app_state.json`：应用状态（目录、直接添加项目路径 `directProjectPaths`、标签、回收站、收藏项目、设置等）
  - `projects.json`：项目缓存列表
  - `heatmap_cache.json`：热力图缓存
  - `terminal_workspaces.json`：终端工作区/布局缓存

### 开发环境注意（不要入库）
- `.beads/`：bd/beads 本地工作区目录（可能由本地 git hooks 触发）；项目运行不依赖该目录，仓库应忽略/不提交。若 `git commit` 因 bd flush 报错，删除 `.beads/` 或移除本地 `.git/hooks/pre-commit` 中 bd 段落即可。

## 2) 功能列表 + 对应位置（功能地图）

下面按“用户功能 → 前端入口/UI → 前端服务层 → Rust 后端”给出快速定位点。

### A. 工作目录/项目扫描与项目列表
- 侧边栏「目录」区：`src/components/Sidebar.tsx`
- 主列表渲染（卡片/列表模式切换）：`src/components/MainContent.tsx`、`src/components/ProjectCard.tsx`、`src/components/ProjectListRow.tsx`
- 主列表快捷命令入口（卡片/列表直接运行 `Project.scripts`）：`src/components/ProjectCard.tsx`、`src/components/ProjectListRow.tsx`、`src/App.tsx`
- 主列表多选批量操作（批量复制路径/刷新/打标/移入回收站）：`src/components/MainContent.tsx`、`src/App.tsx`、`src/state/useDevHaven.ts`
- App 顶层编排已拆分（主文件仅做组合与渲染）：`src/App.tsx` + `src/hooks/useAppViewState.ts` + `src/hooks/useAppActions.ts` + `src/hooks/useProjectSelection.ts` + `src/hooks/useProjectFilter.ts` + `src/hooks/useTerminalWorkspace.ts` + `src/hooks/useWorktreeManager.ts` + `src/hooks/useCodexIntegration.ts` + `src/hooks/useCommandPalette.ts` + `src/hooks/useDisableInputCorrections.ts`（全局关闭输入自动纠错/首字母自动大写）；其中 `useCodexIntegration.ts` 现在同时负责 **控制面通知 -> toast / 系统通知桥接** 与 **通知点击后的工作区跳转**，项目/Worktree 解析收口到 `src/utils/controlPlaneNotificationRouting.ts`
- 核心状态与动作（刷新/扫描/合并/持久化）：`src/state/useDevHaven.ts`、`src/state/DevHavenContext.tsx`；其中 `DevHavenContext` 已拆为 **state/actions 双 Provider**，终端窗口不再直接消费整包全局 Context，新增状态消费时优先走最小 hook（`useDevHavenState` / `useDevHavenActions`）
- “直接添加为项目”持久化：`src/components/Sidebar.tsx`（入口）→ `src/state/useDevHaven.ts`（`addProjects` 写入 `appState.directProjectPaths`，`refresh` 合并 `directories + directProjectPaths`）↔ `src-tauri/src/models.rs`（`AppStateFile.direct_project_paths`）/`src-tauri/src/web_server.rs`（Web 模式路径校验与 allow roots）
- 调用后端命令：`src/services/appStorage.ts`（`discoverProjects/buildProjects/load/save`）→ `src/platform/commandClient.ts`（Tauri `invoke` / Web HTTP）
- 扫描与构建项目元数据（是否 Git 仓库、提交数、最后提交时间）：`src-tauri/src/project_loader.rs`
- Command 注册处：`src-tauri/src/lib.rs`（`discover_projects`、`build_projects`、`load_projects`、`save_projects`）
- 列表模式备注预览（批量读取 `PROJECT_NOTES.md` 首行）：`src/services/notes.ts`（`readProjectNotesPreviews`） ↔ `src-tauri/src/notes.rs`（`read_notes_previews`） ↔ `src-tauri/src/lib.rs`（`read_project_notes_previews`）
- 列表行最近提交摘要（展示 `git log -1 --format=%s`，非 Git 项目显示占位）：`src/components/ProjectListRow.tsx`、`src/components/MainContent.tsx`、`src-tauri/src/project_loader.rs`

### B. 筛选（标签/目录/搜索/时间范围/Git 状态）
- 筛选状态与组合逻辑（搜索词、目录、标签、日期、Git Filter 等）：`src/hooks/useProjectFilter.ts`、`src/App.tsx`
- 筛选模型与选项：`src/models/filters.ts`
- 搜索输入组件：`src/components/SearchBar.tsx`
- 全局命令面板（`⌘K/Ctrl+K`，支持项目跳转/脚本运行/筛选切换）：`src/components/CommandPalette.tsx`、`src/hooks/useCommandPalette.ts`、`src/App.tsx`

### C. 标签管理（新建/编辑/隐藏/颜色/批量打标）
- 标签列表与入口：`src/components/Sidebar.tsx`
- 标签编辑弹窗：`src/components/TagEditDialog.tsx`
- 标签/批量操作回调聚合：`src/hooks/useAppActions.ts`（供 `src/App.tsx` 注入 `Sidebar`/`MainContent`）
- 颜色工具：`src/utils/tagColors.ts`、`src/utils/colors.ts`
- 标签持久化与变更动作：`src/state/useDevHaven.ts`（写入 `app_state.json`）

### D. 项目详情面板（备注/分支/Markdown/快捷操作）
- 详情面板现为右侧 overlay 抽屉：`src/App.tsx` 负责挂载与开关，`src/components/DetailPanel.tsx` 负责状态编排与 Tab 切换
- 详情面板展示已拆分为 3 个子区：`src/components/DetailOverviewTab.tsx`（基础信息/标签/Todo）、`src/components/DetailEditTab.tsx`（备注/README fallback/Markdown）、`src/components/DetailAutomationTab.tsx`（快捷命令/分支）
- 项目卡片：`src/components/ProjectCard.tsx`（通常在主列表中触发打开详情）
- 项目快捷命令（配置/编辑/删除/运行/停止）：`src/components/DetailAutomationTab.tsx`（入口 UI）→ `src/components/DetailPanel.tsx`（脚本弹窗/参数编排）→ `src/hooks/useTerminalWorkspace.ts`（派发 `quickCommandDispatch`）→ `src/components/terminal/TerminalWorkspaceView.tsx`（执行与会话管理）→ `src/services/quickCommands.ts` ↔ `src-tauri/src/quick_command_manager.rs`（作业状态）；不再配置“停止命令”文本，停止为运行态终止；持久化在 `projects.json`（字段：`Project.scripts`，模型：`src/models/types.ts`，当前仅 `name/start/paramSchema/templateParams`）
- 快捷命令 v2（已切流）：前端类型/服务 `src/models/quickCommands.ts` + `src/services/quickCommands.ts`（`quick_command_start/quick_command_stop/quick_command_finish/quick_command_list/quick_command_runtime_snapshot` + `quick-command-state-changed`）；写入/状态迁移由 `src-tauri/src/quick_command_manager.rs` 负责，`quick_command_runtime_snapshot` 读取已切到 `src-tauri/src/terminal_runtime/*` 的 runtime registry；Command 注册：`src-tauri/src/lib.rs`（`quick_command_start/quick_command_stop/quick_command_finish/quick_command_list/quick_command_runtime_snapshot`）
- 通用脚本中心（跨项目复用 + 参数化）：默认目录 `~/.devhaven/scripts`（设置页不再提供动态路径配置）→ 读取共享脚本 `src/services/sharedScripts.ts` ↔ `src-tauri/src/shared_scripts.rs`（Command：`list_shared_scripts`，优先 `manifest.json`，回退目录扫描；目录首次为空时自动注入内置脚本：Jenkins 部署 `jenkins-depoly`、远程日志查看 `remote_log_viewer.sh`）→ 详情面板为快捷命令填充模板与参数快照（`src/components/DetailPanel.tsx`，`ProjectScript.paramSchema/templateParams`）→ 执行前在终端渲染模板参数（`src/components/terminal/TerminalWorkspaceView.tsx`、`src/utils/scriptTemplate.ts`）
- 通用脚本可视化编辑：设置页“脚本”分类内嵌 `src/components/SharedScriptsManagerModal.tsx`，可编辑清单字段（id/路径/命令模板/参数）并直接编辑脚本文件内容；支持“一键恢复内置预设（仅补齐缺失项）”；前端 `src/services/sharedScripts.ts` ↔ 后端 `src-tauri/src/shared_scripts.rs`（Commands：`save_shared_scripts_manifest`、`restore_shared_script_presets`、`read_shared_script_file`、`write_shared_script_file`）
- Git 分支列表：
  - UI：`src/components/DetailAutomationTab.tsx`
  - 前端：`src/services/git.ts`
  - 后端：`src-tauri/src/git_ops.rs`（`list_branches`）
  - Command：`src-tauri/src/lib.rs`（`list_branches`）
- 项目备注 `PROJECT_NOTES.md`：
  - UI：`src/components/DetailEditTab.tsx`（备注为空时自动读取项目根 `README.md` 作为只读参考，可一键“用 README 初始化”）
  - 前端：`src/services/notes.ts`
  - README 回退读取：`src/services/markdown.ts`（`read_project_markdown_file`）
  - 后端：`src-tauri/src/notes.rs`
  - Command：`src-tauri/src/lib.rs`（`read_project_notes/read_project_notes_previews/write_project_notes`）
- 项目 Todo `PROJECT_TODO.md`（详情面板可勾选、增删、自动保存）：
  - UI：`src/components/DetailOverviewTab.tsx`
  - 前端：`src/services/notes.ts`
  - 后端：`src-tauri/src/notes.rs`
  - Command：`src-tauri/src/lib.rs`（`read_project_todo/write_project_todo`）
- 项目内 Markdown 文件浏览/预览：
  - UI：`src/components/DetailEditTab.tsx`、`src/components/ProjectMarkdownSection.tsx`
  - 前端：`src/services/markdown.ts`
  - 后端：`src-tauri/src/markdown.rs`
  - Command：`src-tauri/src/lib.rs`（`list_project_markdown_files/read_project_markdown_file`）
- 系统快捷操作（打开目录/复制路径/外部编辑器）：
  - 前端：`src/services/system.ts`
  - 后端：`src-tauri/src/system.rs`
  - Command：`src-tauri/src/lib.rs`（`open_in_finder/open_in_editor/copy_to_clipboard/send_system_notification`）

### E. Git 活跃度统计与热力图/仪表盘
- Git 每日提交统计（批量）：`src/services/gitDaily.ts` ↔ `src-tauri/src/git_daily.rs`（Command：`collect_git_daily`）
- 热力图数据管理（缓存/加载/计算）：`src/state/useHeatmapData.ts`、`src/services/heatmap.ts`
- 侧边栏热力图组件：`src/components/Heatmap.tsx`（在 `src/components/Sidebar.tsx` 使用）
- 热力图日期下钻（点击日期展示当天活跃项目清单，并一键定位到项目）：`src/hooks/useProjectFilter.ts`、`src/App.tsx`、`src/components/Sidebar.tsx`、`src/utils/gitDaily.ts`
- 仪表盘弹窗：`src/components/DashboardModal.tsx`（数据模型：`src/models/dashboard.ts`）

### F. 回收站（隐藏项目/恢复）
- UI：`src/components/RecycleBinModal.tsx`
- 数据与动作：`src/state/useDevHaven.ts`（`appState.recycleBin`，持久化在 `app_state.json`）

### G. 终端工作区（内置终端 + 布局持久化）
- 终端窗口管理：`src/services/terminalWindow.ts`、`src/components/terminal/TerminalWorkspaceWindow.tsx`；窗口组件仅消费父层显式下发的 `terminalTheme/sharedScriptsRoot/terminalUseWebglRenderer`，不再直接读取全局 Context。**当前会保持所有已打开项目的 `TerminalWorkspaceView` 挂载**，仅把非激活项目隐藏并禁交互，避免项目切换后后台运行任务被过早回收/误判结束。
- 关闭已打开项目（并删除该项目的终端工作区布局快照）：`src/components/terminal/TerminalWorkspaceWindow.tsx`、`src/hooks/useTerminalWorkspace.ts` → `src/services/terminalWorkspace.ts`（`deleteTerminalLayout`） ↔ `src-tauri/src/lib.rs`（Command：`delete_terminal_layout_snapshot`，先删 runtime snapshot，再异步刷写 `src-tauri/src/storage.rs` / `terminal_workspaces.json`）
- 应用重启恢复终端“已打开项目”列表（按 `updatedAt` 恢复最近活跃项目）：`src/hooks/useTerminalWorkspace.ts`（恢复入口） → `src/services/terminalWorkspace.ts`（`listTerminalLayoutSummaries`） ↔ `src-tauri/src/lib.rs`（Command：`list_terminal_layout_snapshot_summaries`，从 runtime snapshot registry 返回摘要；首次访问会从 `src-tauri/src/storage.rs` 导入 `terminal_workspaces.json`）
- 终端 UI（xterm、分屏、标签）：主编排 `src/components/terminal/TerminalWorkspaceView.tsx`，渲染 shell 已拆到 `src/components/terminal/TerminalWorkspaceShell.tsx`，顶部栏 `src/components/terminal/TerminalWorkspaceHeader.tsx`；`TerminalWorkspaceView` 顶层持有 `TerminalLayoutSnapshot`，窗口/标签/Pane 渲染优先走 snapshot projection 与最小 props（如 `sharedScriptsRoot`、`terminalUseWebglRenderer`），并通过 `src/components/terminal/terminalWorkspaceShellModel.ts` 统一派生 header tabs、active tab projection、run panel、sidebar、preview、git diff、run configuration 选择态，减少大文件内散落的视图模型计算
- `src/models/terminal.ts` 已新增一批 snapshot 原生 helper（append/activate/split/remove/update-ratios），供终端工作区逐步脱离 legacy workspace 编辑链；对应单测在 `src/models/terminal.snapshot.test.mjs`
- 终端头部快捷命令运行区（IDEA 风格固定在右上角：运行配置下拉 + 运行/停止 + 配置菜单）+ 底部 Run 面板：`src/components/terminal/TerminalWorkspaceHeader.tsx`（UI） + `src/components/terminal/TerminalWorkspaceView.tsx`（配置选择、删除确认、**全量“运行配置”弹窗**：左侧配置列表/新建，右侧字段编辑与参数配置，底部应用/确定/运行；运行时会在底部 `TerminalRunPanel` 展示会话与状态，不再新建主终端 tab；支持 Run 面板内多运行 tab 切换/收起/关闭） + `src/components/terminal/TerminalRunPanel.tsx`（底部运行输出与 run tabs） + `src/components/terminal/TerminalWorkspaceWindow.tsx` / `src/App.tsx`（脚本新增/更新/删除回调透传） + `src/hooks/useQuickCommandRuntime.ts`（运行时状态机） + `src/hooks/useQuickCommandDispatch.ts`（外部派发）；运行/停止状态统一走 `src/services/quickCommands.ts` + `src-tauri/src/quick_command_manager.rs`；配置新增/编辑/删除复用项目脚本持久化（`addProjectScript/updateProjectScript/removeProjectScript`，落盘 `projects.json`）；选中配置持久化写入 `terminal_workspaces.json` 的 `workspace.ui.runConfiguration.selectedScriptId`，Run 面板布局持久化写入 `workspace.ui.runPanel`（类型：`src/models/terminal.ts`；默认/兼容处理：`src/utils/terminalLayout.ts`）
- pane 容器分发：`src/components/terminal/PaneHost.tsx` 现统一承载 `terminal/run/filePreview/gitDiff/overlay` 五类 pane；`TerminalWorkspaceShell.tsx`、`TerminalRunPanel.tsx`、`TerminalRightSidebar.tsx` 均复用该 host，避免不同区域各自维护一套 pane 装配逻辑
- 终端工作区已按 **cmux 风格 primitive-only** 收口：`src/utils/terminalLayout.ts::createDefaultLayoutSnapshot`、`src/models/terminal.ts` 的 fallback/new tab 现默认直接创建 shell terminal，不再把 provider 选择作为主路径；`src/components/terminal/TerminalWorkspaceView.tsx` 已移除“创建 tab/split 后向 PTY 注入 provider-specific 命令”的主线；旧 `usePaneAgentRuntime`、`src/agents/*`、`TerminalPendingPane.tsx` 已删除。为了兼容历史快照，`src/utils/terminalLayout.ts::normalizeLayoutSnapshotForShellPrimitives` 会在加载时把 legacy `pendingTerminal` 归一化为普通 shell terminal。
- 终端右侧侧边栏（可拖拽调整宽度，Tabs：文件/Git）：`src/components/terminal/TerminalRightSidebar.tsx`、`src/components/terminal/ResizablePanel.tsx`、`src/components/terminal/TerminalWorkspaceView.tsx`；面板状态持久化：`terminal_workspaces.json` 的 `workspace.ui.rightSidebar`（open/width/tab；类型：`src/models/terminal.ts`；默认/兼容：`src/utils/terminalLayout.ts`）；其中 right sidebar 的 open/tab/width 已开始直接写回 `TerminalLayoutSnapshot.ui`
- 终端右侧文件（文件树 + 预览/编辑：Markdown 渲染、源码语法高亮、自动保存 + ⌘/Ctrl+S 保存）：`src/components/terminal/TerminalFileExplorerPanel.tsx`、`src/components/terminal/TerminalFilePreviewPanel.tsx`、`src/components/terminal/TerminalMonacoEditor.tsx`、`src/components/terminal/TerminalRightSidebar.tsx`；前端：`src/services/filesystem.ts`（`listProjectDirEntries/readProjectFile/writeProjectFile`）+ `src/utils/fileTypes.ts`/`src/utils/detectLanguage.ts` ↔ 后端：`src-tauri/src/filesystem.rs`；Command：`src-tauri/src/lib.rs`（`list_project_dir_entries/read_project_file/write_project_file`）；隐藏文件开关仍持久化在 `workspace.ui.fileExplorerPanel.showHidden`，文件预览路径/dirty 状态已收口到 `TerminalLayoutSnapshot.panes[filePreview]`
- 终端 Git 管理（仅对 `projectPath/.git` 存在的项目显示；状态/变更列表/文件查看编辑/对比/暂存/取消暂存/丢弃未暂存/提交/切分支）：`src/components/terminal/TerminalGitPanel.tsx`（左侧列表/操作）、`src/components/terminal/TerminalGitFileViewPanel.tsx`（右侧文件/对比视图）、`src/components/terminal/TerminalRightSidebar.tsx`；前端：`src/services/gitManagement.ts`（`gitIsRepo/gitGetStatus/gitGetDiffContents/gitStageFiles/gitUnstageFiles/gitDiscardFiles/gitCommit/gitCheckoutBranch`）+ `src/services/git.ts`（`listBranches`）↔ 后端：`src-tauri/src/git_ops.rs`；Command：`src-tauri/src/lib.rs`（`git_is_repo/git_get_status/git_get_diff_contents/git_stage_files/git_unstage_files/git_discard_files/git_commit/git_checkout_branch`）；面板状态持久化：`terminal_workspaces.json` 的 `workspace.ui.rightSidebar.tab`，当前 Git 选中文件/对比目标已收口到 `TerminalLayoutSnapshot.panes[gitDiff]`，不再依赖 `TerminalRightSidebar` 内部本地状态
- 终端 worktree 创建/打开/删除/同步（在“已打开项目”列表为父项目创建并展示 worktree 子项，支持已有/新建分支、打开仓库已存在 worktree、可选创建后打开；“新建分支”支持显式 `baseBranch`（基线分支），创建时按“远端 `origin/<base>` 优先、本地 `<base>` 回退”解析起点；创建任务改为同项目 FIFO 排队，可取消排队任务；目标目录固定为 `~/.devhaven/worktrees/<project>/<branch>`，创建后会自动复制主仓库 `.devhaven` 到 worktree（如缺失）并按 `.devhaven/config.json` 的 `setup` 命令初始化环境（失败仅告警，不阻断创建）；创建采用**非阻塞创建命令 + 全局交互锁遮罩**（`worktree_init_create` / `worktree_init_create_blocking`，事件 `interaction-lock` / `worktree-init-progress`），确保遮罩立即显示并实时展示进度；打开时默认继承父项目 tags/scripts；删除会执行 `git worktree remove` 并在受管创建分支场景下额外执行本地 `git branch -d`，随后移除记录；终端打开或点击“刷新 worktree”会从 `git worktree list` 同步 `Project.worktrees` 记录）：`src/components/terminal/TerminalWorkspaceWindow.tsx`（入口/子项列表/刷新/删除/失败重试）+ `src/components/terminal/WorktreeCreateDialog.tsx`（创建弹窗，默认“新建分支”+基线分支，含排队/执行进度与失败诊断复制）+ `src/hooks/useWorktreeManager.ts`（创建/恢复/重试/删除全生命周期编排）+ `src/components/InteractionLockOverlay.tsx`（全局交互锁遮罩 + 初始化进度展示）；前端：`src/services/gitWorktree.ts`（`gitWorktreeList/gitWorktreeRemove/gitDeleteBranch`）+ `src/services/worktreeInit.ts`（`worktreeInitCreate/worktreeInitCreateBlocking/worktreeInitCancel/worktreeInitRetry/worktreeInitStatus` + `worktree-init-progress` 监听）+ `src/services/interactionLock.ts`（`getInteractionLockState`）+ `src/state/useDevHaven.ts`（`syncProjectWorktrees`）↔ 后端：`src-tauri/src/interaction_lock.rs`（全局交互锁状态/事件）+ `src-tauri/src/worktree_init.rs`（后台初始化任务、项目内队列、取消/重试/状态查询）+ `src-tauri/src/worktree_setup.rs`（`.devhaven` 配置复制与 setup 命令执行）+ `src-tauri/src/git_ops.rs`（`add_worktree/resolve_create_branch_start_point/list_worktrees/remove_worktree/delete_branch`）/`src-tauri/src/project_loader.rs`（扫描过滤 worktree 顶层目录）；Command：`src-tauri/src/lib.rs`（`worktree_init_create/worktree_init_create_blocking/worktree_init_cancel/worktree_init_retry/worktree_init_status` + `get_interaction_lock_state` + `git_worktree_add/git_worktree_list/git_worktree_remove/git_delete_branch`）；持久化：`projects.json` 的 `Project.worktrees`（含 `baseBranch/status/initStep/initError/initJobId` 等创建态字段）
- 终端工作区显示 Codex CLI 运行状态（按项目/Worktree 路径归属聚合会话）：`src/utils/codexProjectStatus.ts`、`src/hooks/useCodexIntegration.ts`、`src/App.tsx` → `src/components/terminal/TerminalWorkspaceWindow.tsx`/`src/components/terminal/TerminalWorkspaceView.tsx`
- 新增 **控制平面真相层**：Rust 侧 `src-tauri/src/agent_control.rs` 持有 terminal binding / agent session / notification registry，并通过命令 `devhaven_identify`、`devhaven_tree`、`devhaven_notify`、`devhaven_notify_target`、`devhaven_agent_session_event`、`devhaven_mark_notification_read`、`devhaven_mark_notification_unread` 与事件 `devhaven-control-plane-changed` 暴露给前端/外部；其中 notification record 已升级为**结构化通知**（`title/subtitle/body/level/message` + pane/surface/workspace 归属），`message` 继续作为兼容展示文本。`src-tauri/src/terminal.rs::terminal_create_session` 会注入 `DEVHAVEN_WORKSPACE_ID / DEVHAVEN_PANE_ID / DEVHAVEN_SURFACE_ID / DEVHAVEN_TERMINAL_SESSION_ID` 等环境变量，供外部 agent wrapper/hook 自行上报状态。前端对应模型/服务为 `src/models/controlPlane.ts`、`src/services/controlPlane.ts`、`src/utils/controlPlaneProjection.ts`、`src/utils/controlPlaneAutoRead.ts`、`src/utils/controlPlaneNotificationRouting.ts`，当前 UI 已在 `src/components/terminal/TerminalWorkspaceWindow.tsx` / `TerminalWorkspaceHeader.tsx` 展示 unread / latest message / attention 投影。外部进程接入路径已补齐：terminal shell 现在会拿到 `DEVHAVEN_CONTROL_ENDPOINT`，并可直接复用 `scripts/devhaven-control.mjs`、`scripts/devhaven-agent-hook.mjs`、`scripts/devhaven-claude-hook.mjs`、`scripts/devhaven-codex-hook.mjs` 调用控制面命令。交互式 Claude / Codex 主路径已继续收口为 **shell integration -> `scripts/bin/{claude,codex}` shim -> `scripts/devhaven-{claude,codex}-wrapper.mjs` -> hook/notify -> control plane**；`agent_spawn/agent_stop/agent_runtime_diagnose` 保留为后端显式命令面/诊断工具，不作为交互式主路径。当前通知消费策略已收口为：Rust `devhaven_notify` / `devhaven_notify_target` 负责写入 control plane 与发出结构化通知事件，不再直接用 `osascript` 代发通知；`useCodexIntegration.ts` 会在 Tauri/Web 两侧统一消费 `devhaven-control-plane-changed` 中附带的结构化 notification payload，桥接为 toast + Web Notification API，并通过通知点击回调直接打开对应项目/Worktree 工作区；`src/services/system.ts` 保留后端 `send_system_notification` 作为 Notification API 不可用时的兜底命令；`TerminalWorkspaceView.tsx` 只会对 active pane/surface 对应的 unread notifications 自动已读，不再在 workspace 激活时整批清空。
- 控制平面已新增 **provider-neutral primitive 层**：Rust / Web / Tauri 命令现支持 `devhaven_notify_target`、`devhaven_set_status`、`devhaven_clear_status`、`devhaven_set_agent_pid`、`devhaven_clear_agent_pid`；对应 durable 记录位于 `src-tauri/src/agent_control.rs` 的 `statuses / agent_pids`，前端类型与最小投影位于 `src/models/terminalPrimitives.ts`、`src/utils/terminalPrimitiveProjection.ts`。当前 Codex / Claude wrapper/hook 已迁到这层 primitive adapter，但仍保留 legacy `devhaven_notify / devhaven_agent_session_event` 兼容双写；后续若继续调整 wrapper，请优先复用 primitive adapter，不要重新绕过中间层直写 UI 语义。
- 终端 shell integration 已开始按 **bootstrap 分层** 收口：`scripts/shell-integration/zsh/.zshenv/.zprofile/.zshrc/.zlogin` 只负责桥接到用户真实 shell 语义，公共 PATH 注入收口在 `scripts/shell-integration/devhaven-wrapper-path.sh`，zsh/bash 启动增强分别收口到 `scripts/shell-integration/zsh/devhaven-zsh-bootstrap.zsh` 与 `scripts/shell-integration/bash/devhaven-bash-bootstrap.sh`。`src-tauri/src/terminal.rs` 对 zsh 不再强制注入 `HISTFILE/ZSH_COMPDUMP`，避免把用户 history / ZDOTDIR 状态源切到 DevHaven integration 目录；后续若继续调整 shell integration，必须优先保证“用户 shell 状态源归用户自己、DevHaven 只负责轻量注入”的边界。
- 终端 wrapper / shell integration 资源已开始对齐 **cmux 式 bundle resource 模式**：`src-tauri/tauri.conf.json` 现会把 `scripts/bin/`、`scripts/shell-integration/` 与 `devhaven-*.mjs` 打进 app bundle；`src-tauri/src/terminal.rs` 解析 wrapper / hook / shell integration 时会优先走 `app.path().resource_dir()/scripts/*`，只有在 dev/资源缺失时才回退到仓库 `scripts/*`。后续如果再改这条链路，禁止重新依赖 `current_dir()` 作为 build 主路径。
- 终端快捷键（iTerm2/浏览器风格）：`src/components/terminal/TerminalWorkspaceView.tsx`（⌘T 新建 Tab、⌘W 关闭 Pane/Tab、⌘↑/⌘↓/⌘←/⌘→ 上一/下一 Tab、⌘⇧[ / ⌘⇧] 上一/下一 Tab、⌘1..⌘9 快速切换 Tab、⌘D 分屏）
- 终端高级能力（仅当前 Pane 搜索 + 修饰键点击链接）：`src/components/terminal/TerminalPane.tsx`（Search/WebLinks addons，mac `⌘F`、Win/Linux `Ctrl+Shift+F` 打开搜索，`Enter/Shift+Enter/Esc` 导航/关闭；链接需 `Cmd/Ctrl+点击`，支持 `http/https/mailto` 与本地路径 `/Users/...`、`Users/...`、`~/...`）→ URL 用 `@tauri-apps/plugin-opener` 的 `openUrl`，本地路径优先走 `src/services/system.ts` 的 `openInFinder`（失败回退 `openPath`）↔ `src-tauri/capabilities/terminal.json`（`opener:default` 权限）
- 终端尺寸收口（避免 viewport/rows 轻微失配导致“已滚到底但最后几行仍被裁掉”）：`src/components/terminal/TerminalPane.tsx`（`fitAddon.fit()` 后按真实 viewport 高度二次 clamp rows）+ `src/components/terminal/terminalViewportFit.ts` / `src/components/terminal/terminalViewportFit.test.mjs`
- 终端连接期输出缓冲裁剪（避免切换项目恢复时把 `CSI/OSC` 控制序列从中间截断并显示成裸文本）：`src/components/terminal/terminalEscapeTrim.ts`（前端 escape-aware tail trim helper） + `src/components/terminal/TerminalPane.tsx`（`bufferedOutput` 超限裁剪） + `src/components/terminal/terminalEscapeTrim.test.mjs`（Node 内建 test 覆盖 plain text / OSC / CSI）
- 终端内存优化（Ghostty 风格轻量休眠）：前端移除 `SerializeAddon`/`cachedState` 双缓存，仅保留 Rust replay；Rust 侧 `src-tauri/src/terminal.rs` 现使用**有界输出队列** + 分层 replay 缓冲（活跃 PTY 约 2MiB、后台保活 PTY 约 256KiB，`terminal_set_replay_mode` 能切到 parked，但**项目切换 preserve unmount 默认不主动降级**，避免切回项目时历史输出被过早回收）；前端 `src/components/terminal/TerminalPane.tsx` 将 xterm `scrollback` 收口到 1000 行、连接期缓冲收口到 128KB；`src/components/terminal/terminalMemoryPolicy.ts` + `src/components/terminal/TerminalWorkspaceView.tsx` 负责“仅单一可见 terminal/run pane 启用 WebGL”，`src/components/terminal/TerminalRunPanel.tsx` 仅挂载活动 run tab，降低多开终端时的常驻内存。
- 终端 runtime 已收口到 mux-lite 主路径：Rust 侧 `src-tauri/src/terminal_runtime/*` 当前保留 `runtime/session_registry/quick_command_registry/events/types`，负责 session 生命周期、quick command 状态与 JSON layout snapshot registry；其中 `session_registry` / `quick_command_registry` 已加容量上限与 finished/exited 记录回收，避免长时间运行后 registry 只增不减；早期未接线的 typed layout registry 骨架已移除，主路径不再分裂成两套 layout 真相源。
- 会话/PTY 通信：
  - macOS shell 启动链路：`src-tauri/src/terminal.rs` 中 `terminal_create_session` 使用 login shell 风格启动（`/usr/bin/login -flp <user> /bin/bash --noprofile --norc -c "exec -l <shell>"`），以对齐 Ghostty 并加载用户 login 环境（例如 `~/.zprofile` 的 PATH）。
  - 跨端会话复用：后端按 `sessionId` 复用已有 PTY；前端附带 `clientId` 进行附着，`terminal_kill` 在默认模式下按客户端引用释放，仅最后一个附着客户端离开时才真正结束 PTY（`force=true` 可强制结束）。
  - 事件模型已切到 scoped 消费：`src/services/terminal.ts` 只监听 `terminal-pane-output:{sessionId}` / `terminal-pane-exit:{sessionId}`；Rust 侧 `src-tauri/src/terminal_runtime/events.rs` 负责 scoped 事件名与 payload，`src-tauri/src/terminal.rs` 在输出/退出时同步 runtime seq。
  - 前端：`src/services/terminal.ts`、`src/terminal-runtime-client/subscriptions.ts`
  - 后端：`src-tauri/src/terminal.rs`、`src-tauri/src/terminal_runtime/events.rs`
  - Command：`src-tauri/src/lib.rs`（`terminal_create_session/terminal_write/terminal_resize/terminal_kill`）
- 工作区持久化正迁向 LayoutSnapshot：
  - 前端：`src/services/terminalWorkspace.ts` + `src/terminal-runtime-client/{runtimeClient,selectors,subscriptions}.ts`，统一走 `load/save/delete/listTerminalLayoutSnapshot*` 新接口，不再回退 legacy workspace command；窗口/Tab/Pane projection 统一复用 `src/models/terminal.ts` 与 `src/terminal-runtime-client/selectors.ts`。
  - 前端模型：`src/models/terminal.ts` 已收敛到 `TerminalLayoutSnapshot/TerminalPaneDescriptor/TerminalWindowProjection` 主模型；旧 `TerminalWorkspace/SplitNode` 前端类型已移除。
  - 前端清理：未使用的 legacy hook `src/hooks/useQuickCommandPanel.ts` 已移除；`quickCommandsPanel` 目前仅作为兼容字段保留在模型/存储层，不再有独立交互入口。
  - 后端：`src-tauri/src/storage.rs` 已把 `terminal_workspaces.json` 的主语义切到 **LayoutSnapshot JSON**；旧 `load/save/list_terminal_workspace*` API 已删除，legacy 记录只在首次读盘时做一次性归一化导入并异步回写；当前 `load/save/delete_terminal_layout_snapshot*` 命令读写先走 `src-tauri/src/terminal_runtime/runtime.rs` 的 snapshot registry，再由 storage 负责持久化；**但 `list_terminal_layout_snapshot_summaries` 已改为 storage 直出 summary，不再因为启动期恢复“已打开项目”而把全部 snapshot 导入 runtime。**
  - 新 Command：`src-tauri/src/lib.rs` / `src-tauri/src/command_catalog.rs`（`load_terminal_layout_snapshot/save_terminal_layout_snapshot/delete_terminal_layout_snapshot/list_terminal_layout_snapshot_summaries`、`quick_command_runtime_snapshot`）。
  - 新事件：`terminal-window-layout-changed`、`terminal-workspace-restored`、`quick-command-state-changed`；WebSocket 侧由 `src-tauri/src/web_server.rs` 仅向显式订阅的事件名推送。

### H. 悬浮监控窗（Monitor，已移除）
- 该功能已下线，不再创建 `cli-monitor` 子窗口，也不再提供 `set_window_fullscreen_auxiliary` 相关能力。
- Codex 运行态与通知仍保留在主界面/终端控制面（见下一节 I）。

### I. Codex 控制面集成（已移除 ~/.codex/sessions 监控）
- 前端：`src/hooks/useCodexIntegration.ts`、`src/App.tsx`、`src/components/terminal/TerminalWorkspaceWindow.tsx`、`src/components/terminal/TerminalWorkspaceView.tsx`、`src/components/terminal/TerminalWorkspaceHeader.tsx`、`src/utils/controlPlaneProjection.ts`
- 当前 Codex 状态源已统一为 **adapter / wrapper 直写 control plane**：终端项目列表、工作区头部与 pane attention 只读取 control plane；`useCodexIntegration.ts` 现在负责消费 notification 事件里的结构化摘要，并统一桥接为 toast + 系统通知 + 点击跳转，不再依赖前端回拉整棵 tree 才决定通知内容。
- 当前系统通知策略：`src/services/system.ts` 会优先走 Web Notification API（Tauri 由 `tauri-plugin-notification` 提供原生通知能力），从而保留通知点击回调并直接跳到对应工作区；若运行环境缺少 Notification API 或权限未授予，再回退到后端 `send_system_notification` 命令。Toast 仍由 `src/App.tsx` 顶层统一渲染，但样式已调整为右上角高对比提示卡，确保终端工作区内更容易观察。
- 后端：`src-tauri/src/agent_control.rs` + `src-tauri/src/web_event_bus.rs` + `scripts/devhaven-codex-hook.mjs`
- Tauri / Web Command：`src-tauri/src/lib.rs` / `src-tauri/src/command_catalog.rs` 中的 `devhaven_tree`、`devhaven_notify`、`devhaven_agent_session_event`
- 删除说明：仓库内已不再保留 `codex_monitor.rs`、`get_codex_monitor_snapshot`、`useCodexMonitor`、`CodexSessionSection` 等基于文件扫描的兼容链路；若未来需要恢复离线会话发现能力，必须重新设计为 control plane 持久化，而不是重新接回 `~/.codex/sessions` 轮询。

### J. 更新检查
- GitHub Releases latest 检查：`src/services/update.ts`

### K. 设置（更新/浏览器访问端口/终端渲染/脚本管理/Git 身份）
- UI：`src/components/SettingsModal.tsx`
- 设置分类：`常规`（版本/更新/浏览器访问端口）、`终端`（渲染/主题）、`脚本`（通用脚本管理）、`协作`（Git 身份）
- 设置模型：`src/models/types.ts`（`AppSettings`）
- 保存入口：`src/App.tsx`（打开/关闭设置弹窗 + 保存设置）与 `src/state/useDevHaven.ts`（`updateSettings` 持久化到 `app_state.json`）
- 浏览器访问端口配置（`AppSettings.viteDevPort`，默认 `1420`，保存后 toast 提示“重启应用后生效（开发态请重启 dev）”）：`src/components/SettingsModal.tsx`、`src/hooks/useAppActions.ts`、`src/state/useDevHaven.ts`、`src/models/types.ts`、`vite.config.ts`
- `pnpm tauri dev` 启动对齐：通过 `scripts/tauri-cli-wrapper.mjs` 在启动前同步 `src-tauri/tauri.conf.json` 的 `build.devUrl` 到当前 `viteDevPort`，避免 tauri 固定等待旧端口
- Web 服务绑定配置：开发态默认 `0.0.0.0:3210`，打包态默认跟随 `AppSettings.viteDevPort`；可通过环境变量 `DEVHAVEN_WEB_ENABLED/DEVHAVEN_WEB_HOST/DEVHAVEN_WEB_PORT` 覆盖：`src-tauri/src/web_server.rs`、`vite.config.ts`、`src-tauri/src/lib.rs`
- 设置保存与视图模式切换回调：`src/hooks/useAppActions.ts`
- 通用脚本目录：`AppSettings.sharedScriptsRoot`（默认 `~/.devhaven/scripts`，设置页固定使用默认目录；共享脚本列表由 `list_shared_scripts` 提供）
- 通用脚本可视化管理入口：`src/components/SettingsModal.tsx` → `src/components/SharedScriptsManagerModal.tsx`（清单与脚本文件编辑 + “恢复内置预设”）
- 终端主题配色（Ghostty 风格 `light:xxx,dark:yyy`）：`src/themes/terminalThemes.ts`、`src/hooks/useSystemColorScheme.ts`、`src/components/terminal/*`
- 主内容视图模式持久化（卡片/列表）：`AppSettings.projectListViewMode`（`src/models/types.ts`、`src/state/useDevHaven.ts`、`src/App.tsx`、`src-tauri/src/models.rs`）

### L. 全局 Skills 管理（独立页面）
- 入口/UI：`src/components/MainContent.tsx`（标题栏独立按钮）→ `src/components/GlobalSkillsModal.tsx`
- 展示：`src/components/GlobalSkillsModal.tsx` 采用「Skill × Agent」矩阵表格，左侧 Skill 列 sticky 固定，右侧按 Agent 标记启用状态；矩阵单元可点击直接切换「安装/卸载」
- 安装：`src/components/GlobalSkillsModal.tsx`（来源/skill 名/agent 选择）→ `src/services/skills.ts`（`installGlobalSkill`）→ `src-tauri/src/lib.rs`（`install_global_skill`）→ `src-tauri/src/skills.rs`（参考开源 skills 的发现/安装流程，在应用内完成 clone + 安装，不依赖外部 skills CLI）
- 卸载：`src/components/GlobalSkillsModal.tsx`（矩阵单元点击）→ `src/services/skills.ts`（`uninstallGlobalSkill`）→ `src-tauri/src/lib.rs`（`uninstall_global_skill`）→ `src-tauri/src/skills.rs`（按 Agent 目录定点删除该 skill）
- 扫描：`src/services/skills.ts`（`listGlobalSkills`）→ `src-tauri/src/lib.rs`（`list_global_skills`）→ `src-tauri/src/skills.rs`（固定扫描 `~/.agents/skills` 与常见 Agent 全局目录并聚合，不暴露扫描范围配置）

### M. Web 运行时桥接（HTTP/WS + 浏览器兜底）
- 运行时探测与能力兜底：`src/platform/runtime.ts`（`isTauriRuntime`、`resolveRuntimeWindowLabel`、`resolveRuntimeClientId`、目录选择/confirm/openUrl/homeDir/version 的浏览器 fallback）
- 命令桥接：`src/platform/commandClient.ts`（统一 `invokeCommand`；Web 下调用 `POST /api/cmd/{command}`，按 HTTP status + 结构化错误体解析失败）
- 命令目录与 Web 协议收口：`src-tauri/src/command_catalog.rs`（统一 Tauri/Web 命令清单、Web payload 解包、路径校验与结构化错误）；`src-tauri/src/lib.rs` 的 `invoke_handler` 与 `src-tauri/src/web_server.rs` 的 `/api/cmd/{command}` 共同消费该目录，避免命令漂移
- 事件桥接：`src/platform/eventClient.ts`（统一 `listenEvent`；Web 下连接 `/api/ws`，并在浏览器模式向服务端同步当前订阅事件集合，便于 scoped terminal/runtime event 逐步切流）
- Rust Web 服务入口：`src-tauri/src/web_server.rs`（`/api/health`、`/api/cmd/{command}`、`/api/ws` + 前端静态资源路由 `/`、`/{*path}`）
- 开发态单端口体感：`vite.config.ts` 配置 `/api` 代理到 Web API（优先 `DEVHAVEN_WEB_API_TARGET`，默认 `http://127.0.0.1:3210`），并从 `~/.devhaven/app_state.json` 读取 `settings.viteDevPort` 作为 Vite 端口（可由 `DEVHAVEN_VITE_PORT` 覆盖，需重启 Vite 生效）；`src/platform/runtime.ts` 在 `import.meta.env.DEV` 下走 `window.location.origin`
- WebSocket 事件分发：浏览器端通过 `src/platform/eventClient.ts` 先声明订阅事件集合，`src-tauri/src/web_server.rs` 仅按已订阅事件名推送；终端/快捷命令已不再广播 legacy `terminal-output` / `terminal-exit` / `quick-command-event`。
- 事件镜像：`src-tauri/src/web_event_bus.rs` + `src-tauri/src/{terminal.rs,quick_command_manager.rs,worktree_init.rs,interaction_lock.rs,agent_control.rs}`
- 新增 command：`resolve_home_dir`（`src-tauri/src/lib.rs`），供 Web 模式路径展开使用

### N. macOS 原生客户端（Phase A，Swift Package）
- 原生子工程入口：`macos/Package.swift`
- 原生 App 壳：`macos/Sources/DevHavenApp/DevHavenApp.swift`、`AppRootView.swift`
- 原生主界面已从系统三栏收口为**接近 Tauri 版的信息架构**：左侧 `ProjectSidebarView.swift`、中间 `MainContentView.swift`、右侧 overlay 抽屉 `ProjectDetailRootView.swift`，并统一走 `NativeTheme.swift` 深色主题
- 原生 Git 统计：左侧 Sidebar 已支持 `GitHeatmapGridView.swift` 的 3 个月热力图、日期筛选与活跃项目列表；顶部波形按钮会打开 `GitDashboardView.swift` 仪表盘，展示时间范围切换、统计卡片、热力图与活跃日期/项目排行；Dashboard 已按窗口宽度切换统计卡片列数与底部区块堆叠方式，月份标签与热力图共享同一横向滚动坐标；“更新统计”现通过 `NativeAppViewModel.refreshGitStatisticsAsync()` 在后台执行 `git log --date=short` 聚合并写回 `projects.json`，`GitDashboardView` 头部会显示阶段/进度文案（扫描仓库数、写入、刷新列表），底层 `GitDailyCollector.swift` 默认以最多 4 仓并发扫描并对单仓 `git log` 加超时保护，同时该窗口配置了更宽的默认尺寸与可手动拖拽缩放能力
- 原生设置 / 回收站：`macos/Sources/DevHavenApp/SettingsView.swift`、`RecycleBinSheetView.swift`；设置页已改成**左侧分类 + 右侧卡片区**，分类为 `常规 / 终端 / 脚本 / 协作`；脚本分类现已内嵌 `SharedScriptsManagerView.swift`，直接兼容 `~/.devhaven/scripts/manifest.json` 与脚本文件内容的读写
- 数据兼容层：`macos/Sources/DevHavenCore/Storage/LegacyCompatStore.swift`（直接兼容 `~/.devhaven/app_state.json`、`projects.json`、`PROJECT_NOTES.md`、`PROJECT_TODO.md`、`~/.devhaven/scripts/*`；`app_state.json` / `projects.json` 写回时保留未知字段）
- 原生状态编排：`macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`（负责搜索、目录/标签/Git/日期筛选、热力图日期筛选、Dashboard 聚合、原生 Git 统计更新、详情抽屉开关、回收站/收藏/设置写回）；当前已补一层**项目文档缓存 + 局部状态更新**，避免筛选点击重复读 `PROJECT_NOTES.md/PROJECT_TODO.md/README.md`，以及避免收藏/回收站/设置保存后立刻整份 `load()` 重载；未命中文档缓存时会以后台任务异步读取项目文档，并用 `isProjectDocumentLoading + revision guard` 防止快速切换项目时旧结果回写串屏，详情抽屉 `ProjectDetailRootView.swift` 会显示轻量 loading 提示；Git 统计聚合类型/辅助函数位于 `macos/Sources/DevHavenCore/Models/GitStatisticsModels.swift`，共享脚本模型位于 `macos/Sources/DevHavenCore/Models/SharedScriptModels.swift`
- Todo 语义：`macos/Sources/DevHavenCore/Models/TodoModels.swift`（继续沿用 `- [ ]` / `- [x]` Markdown checklist）
- 测试：`swift test --package-path macos`；当前测试位于 `macos/Tests/DevHavenCoreTests/LegacyCompatStoreTests.swift`
- 当前边界：此子工程**暂不覆盖终端工作区 / PTY / pane-tab-split / control plane 原生投影**；侧栏里的“CLI 会话”目前仅做布局占位，`WorkspacePlaceholderView.swift` 保留为后续终端子系统预研文件，但不再挂在主界面主路径

## 3) 回写（维护）AGENTS.md 的逻辑

本文件是“给 LLM/新同学看的项目索引”，要求随代码演进同步更新（回写）。

### 触发回写的场景（满足任一就需要更新本文件）
- 新增/删除/重命名用户可见功能（UI、弹窗、窗口、入口按钮、菜单项等）。
- 新增/删除/重命名 Tauri Command（`src-tauri/src/lib.rs` 的 `#[tauri::command]` 或 `invoke_handler!` 列表变更）。
- 新增/删除/重命名前端 service（`src/services/*` 的 `invoke(...)` 包装、事件名、窗口 label）。
- 变更本地存储结构/文件名/目录（`src-tauri/src/storage.rs`、`~/.devhaven/*`）。
- 变更核心状态模型或持久化字段（`src/models/types.ts`、`src/state/useDevHaven.ts`）。
- 引入新的语言/框架/构建系统/关键依赖（例如新增后端服务、数据库、状态库、路由方案等）。

### 回写原则（怎么写）
- **不修改**受管块：`<!-- OPENSPEC:START --> ... <!-- OPENSPEC:END -->`（只允许在块外补充内容）。
- 以“功能 → 入口/UI → services → Rust 后端/Command”的链路补齐定位信息，至少给出 1 个关键文件路径。
- 新功能优先补到现有 A~K 模块；确实不适配再新增字母段落（保持顺序、命名清晰）。
- 涉及 Tauri 调用时，尽量在描述中点出 command 名称（例如 `collect_git_daily`），便于全局搜索对齐。
- 保持简洁：只写“能快速找到代码”的信息，不写大段实现细节；实现细节在对应源码内补注释/README。

### 快速定位约定（让回写更一致）
- 前端入口通常从 `src/App.tsx`（全局状态/弹窗/窗口联动）和 `src/components/*`（具体 UI）开始找。
- “调用后端”的入口优先在 `src/services/*` 搜 `invokeCommand` / `listenEvent`，再去 `src/platform/*` 判断是 Tauri 还是 Web 链路，最后到 `src-tauri/src/lib.rs` / `src-tauri/src/web_server.rs` 对齐 command。
- “数据怎么落盘/缓存”优先看 `src-tauri/src/storage.rs`，前端只负责触发（`src/services/appStorage.ts`、`src/services/heatmap.ts`、`src/services/terminalWorkspace.ts` 等）。
