# 本次任务清单

## 改善更新统计耗时感知与执行效率（2026-03-19）

- [x] 检查更新统计长时间“更新中”的真实执行链，确认是顺序扫描慢还是缺少进度提示
- [x] 为更新统计补充阶段/进度反馈，并对 Git 仓库扫描做必要提速与防卡保护
- [x] 同步 tasks / lessons / AGENTS（如涉及可见行为）并完成验证闭环

## Review（改善更新统计耗时感知与执行效率）

- 直接原因：你看到“等了好久还是在更新”，根因其实有两层。第一层是**它确实在干活**：会遍历所有可见 Git 项目，对每个仓库执行一次 `git log --date=short` 来重建 `git_daily`；在你当前这份数据里，截图已经显示 Git 项目数是 109，所以这不是瞬时任务。第二层是此前 UI 只会显示一个笼统的“更新中...”，既没有阶段提示，也没有进度；再加上底层最开始是完全串行扫描，所以用户体感就像“按钮一直在转，但不知道它在干嘛”。
- 是否存在设计层诱因：存在。之前我们虽然把“更新统计”从主线程卡死里拆出来了，但还停留在“后台执行就算完事”的阶段，没有把**长任务可观测性**和**多仓库扫描吞吐**同时收口。因此功能 technically 在跑，但用户侧仍然缺少“当前扫到哪儿了、是不是卡住了”的反馈。除此之外，未发现新的明显系统设计缺陷。
- 当前修复方案：
  1. `GitDashboardView.swift` 头部现在会在刷新期间显示明确阶段文案，而不再只有“更新中...”按钮：例如 `正在扫描 X/Y 个 Git 仓库...`、`正在写入统计结果...`、`正在刷新项目列表...`。
  2. `NativeAppViewModel.swift` 新增 `gitStatisticsProgressText`，并在 `refreshGitStatisticsAsync()` 中驱动这条状态文案；刷新完成或失败后会自动清空。
  3. `GitDailyCollector.swift` 新增异步 `collectGitDailyAsync(...)`：默认最多 4 个仓库并发扫描，不再完全串行。
  4. 同时给单仓库 `git log` 加了超时保护（当前 8 秒），避免个别异常仓库把整轮统计无限拖住。
- 长期改进建议：下一步如果你仍觉得总耗时偏长，我建议继续做两件事：一是把 `store.updateProjectsGitDaily(...) + load()` 这段写盘/重载也进一步拆出细粒度进度；二是把 Git 统计改成“增量刷新 + 失败仓库列表 + 可取消任务”，而不是每次都对所有仓库做全量重扫。
- 验证证据：
  - 根因定位：当前代码可直接确认 `collectGitDaily(...)` 会对所有路径逐仓运行 `git log`，而你的截图也明确显示 Git 项目数为 109；这解释了为什么任务本身会持续一段时间。
  - 红/绿灯约束：`NativeAppViewModelTests/testRefreshGitStatisticsAsyncMarksRefreshingImmediatelyAndAppliesResults` 已扩展为验证刷新启动后会立刻进入 `isRefreshingGitStatistics == true` 且出现 `gitStatisticsProgressText`，并在完成后正确清空状态与写回结果；定向测试通过。
  - 全量验证：`swift test --package-path macos`（17/17 通过）、`swift build --package-path macos`（通过）、`git diff --check`（通过）。

## 修复项目仪表板布局错误（2026-03-19）

- [x] 结合截图检查 Dashboard 布局与热力图标签实现，确认直接原因
- [x] 修复窄宽度下的仪表板裁切、统计卡片空白与月份标签截断问题
- [x] 同步 tasks / lessons 并完成验证闭环

## Review（修复项目仪表板布局错误）

- 直接原因：当前原生 `GitDashboardView.swift` 仍按“宽屏仪表盘”硬编码布局，包含 `minWidth: 980`、固定 3 列统计卡片、底部双栏并排；当 sheet 实际宽度远小于 980 时，左侧内容会直接被裁掉，所以看起来就像“左边卡片空白”“范围按钮缺一截”“热力图被顶歪了”。另外，`GitHeatmapGridView.swift` 里月份标签每列只给了 `cellSize` 宽度，像 `10月/11月/12月` 会被压成 `1...`。
- 是否存在设计层诱因：存在。此前实现更偏“把宽屏视觉大体搭出来”，但没有把 sheet 实际宽度和热力图标签渲染当成一等约束，所以固定宽度/固定列数/固定并排布局把 SwiftUI 的默认裁切直接暴露给了用户。除此之外，未发现新的明显系统设计缺陷。
- 当前修复方案：
  1. 在 `GitStatisticsModels.swift` 新增 `GitDashboardLayoutPlan` 与 `buildGitDashboardLayoutPlan(width:)`，把仪表板布局从“写死 3 列”改为按可用宽度切换：窄宽度走 2 列统计卡片 + 底部纵向堆叠，宽宽度才保持 3 列 + 双栏并排。
  2. `GitDashboardView.swift` 改为基于 `GeometryReader` 读取实际宽度，不再写死 `minWidth: 980`；时间范围按钮也改成横向可滚动，避免窄宽度下直接被裁掉。
  3. `GitHeatmapGridView.swift` 把月份标签移到和热力图本体同一条横向滚动内容里，并把每周标签槽位改成“固定占位 + 文本可向右自然展开”，不再把 `10月/11月/12月` 硬塞进 18pt 宽度里。
- 长期改进建议：如果后面继续打磨 Dashboard，建议把“统计卡片、热力图、底部榜单”的断点策略统一沉成可复用 dashboard primitive，而不是各视图各自写 `HStack/LazyVGrid`；这样后续再补筛选、悬浮提示、卡片交互时，不会重复踩固定宽度与窄窗口裁切的问题。
- 验证证据：
  - 根因定位：从代码可直接确认 `GitDashboardView.swift` 使用了 `minWidth: 980`、固定 3 列 `LazyVGrid`、底部固定 `HStack`，而 `GitHeatmapGridView.swift` 的月份标签槽位宽度只有 `style.cellSize`，与截图里的“左侧裁切 + 月份标签变成 1...” 完全一致。
  - 红/绿灯约束：新增 `NativeAppViewModelTests/testGitDashboardLayoutPlanAdaptsToWindowWidth`，锁住 560 / 920 / 1280 宽度下的布局切换规则，定向测试通过。
  - 全量验证：`swift test --package-path macos`（16/16 通过）、`swift build --package-path macos`（通过）、`git diff --check`（通过）。

## 仪表板默认尺寸、异步刷新与手动缩放（2026-03-19）

- [x] 检查 Dashboard 默认尺寸、刷新统计主线程阻塞与窗口缩放约束
- [x] 将“更新统计”改成后台异步执行，并保留刷新状态与结果提示
- [x] 放大 Dashboard 默认宽度，并让该窗口支持手动拖拽放大缩小
- [x] 同步 AGENTS / tasks / lessons 并完成验证闭环

## Review（仪表板默认尺寸、异步刷新与手动缩放）

- 直接原因：
  1. Dashboard 当前 attached sheet 没有单独配置窗口尺寸，默认会按内容拟合成较窄宽度，所以用户直观感受就是“宽度还是不够”。
  2. “更新统计”按钮直接同步调用 `NativeAppViewModel.refreshGitStatistics()`，而它内部会在 `@MainActor` 上串行跑完整个 `git log` 聚合，所以仓库一多，整个项目就会卡死、按钮一直转圈。
  3. 当前 Dashboard 也没有显式收口 sheet/window 的最小尺寸与可缩放能力，所以就算布局已经开始响应式，用户仍然缺少“手动拖大/拖小”的控制。
- 是否存在设计层诱因：存在。此前原生 Dashboard 主要先追平静态视觉，没有把“统计刷新是重任务”“sheet 在 macOS 上本质也是一个 window，需要单独配置尺寸/缩放策略”当作一等约束，因此同步重任务和默认窗口行为直接暴露到了用户层。除此之外，未发现新的明显系统设计缺陷。
- 当前修复方案：
  1. `NativeAppViewModel.swift` 新增 `gitDailyCollector` 注入点，并补 `refreshGitStatisticsAsync()`：重的 `collectGitDaily` 聚合改为 `Task.detached(priority: .userInitiated)` 后台执行，写盘与 `load()` 仍回到主线程做最终状态同步。
  2. `GitDashboardView.swift` 的“更新统计”改为通过 `Task` 调用异步刷新，不再同步卡住整个 SwiftUI 主线程；刷新期间仍复用 `isRefreshingGitStatistics` 控制按钮文案与禁用态。
  3. Dashboard 本体加大默认内容尺寸，并通过 `DashboardWindowConfigurator` 显式把该窗口设为可缩放：默认尺寸调到更宽、更高，同时保留合理 `minSize`，支持用户手动拖拽放大缩小。
- 长期改进建议：后续如果继续做 Git 统计体验，建议把刷新状态从“按钮转圈 + 顶部文案”进一步收口成可取消任务 / 仓库级进度；同时把 Settings / RecycleBin 这些原生窗口也统一接到同一套 window sizing primitive，避免每个面板各自踩一遍 macOS 默认窗口行为。
- 验证证据：
  - 红灯阶段：从代码可确认 `GitDashboardView.refreshStatistics()` 直接同步调用 `viewModel.refreshGitStatistics()`，而 `NativeAppViewModel.refreshGitStatistics()` 内部在 `@MainActor` 上直接执行 `collectGitDaily(...)`，这和“点击更新统计整个项目卡死一直在转圈”的现象完全一致。
  - 红/绿灯约束：新增 `NativeAppViewModelTests/testRefreshGitStatisticsAsyncMarksRefreshingImmediatelyAndAppliesResults`，锁住异步刷新会立即进入 `isRefreshingGitStatistics == true`，并在完成后把统计结果写回 snapshot；定向测试通过。
  - 全量验证：`swift test --package-path macos`（17/17 通过）、`swift build --package-path macos`（通过）、`git diff --check`（通过）。

## 修复启动时统计图标误显选中态（2026-03-19）

- [x] 检查顶部工具栏图标的选中态与焦点来源，确认直接原因
- [x] 修复启动时统计图标误显蓝色高亮的问题，保持与 Tauri 版一致
- [x] 同步 tasks / lessons 并完成验证闭环

## Review（修复启动时统计图标误显选中态）

- 直接原因：这个蓝色效果不是业务上的“统计页已选中”，而是 macOS 在窗口启动后把顶部工具栏里的**第一个可聚焦 Button** 当成了当前键盘焦点，所以 `waveform.path.ecg` 图标看起来像选中态。代码里它本来没有任何 `isDashboardPresented` 或 active 条件样式。
- 是否存在设计层诱因：存在轻微的原生控件默认行为外露问题。当前工具栏图标为了快速复刻 Tauri 版，直接用了 `Button + .buttonStyle(.plain)`，但没有显式收口“这些图标是否应该参与初始焦点链”，于是 macOS 原生焦点高亮泄漏成了产品视觉。除此之外，未发现新的明显系统设计缺陷。
- 当前修复方案：在 `MainContentView.swift` 的 `toolbarIcon(...)` 上补 `.focusable(false)`，让这些顶部纯图标按钮不再抢启动时的初始键盘焦点，从而去掉那种“像被选中”的蓝色高亮，视觉上更接近 Tauri 版。
- 长期改进建议：后续如果工具栏继续扩展，最好把“图标按钮 / 筛选 chip / 输入框”的焦点策略收口成单独的 toolbar primitive，明确哪些控件应该参与键盘焦点、哪些只作为点击入口，避免再出现系统默认 focus ring 混进产品态。
- 验证证据：
  - 根因定位：检查 `MainContentView.swift` 可确认统计按钮只是 `toolbarIcon("waveform.path.ecg", action: { viewModel.revealDashboard() })`，没有任何选中态判断，因此蓝色高亮只能来自系统焦点而非业务状态。
  - 构建验证：`swift build --package-path macos`（通过）。
  - 全量验证：`swift test --package-path macos`（15/15 通过）、`git diff --check`（通过）。

## 原生项目详情异步文档加载（2026-03-19）

- [x] 通过失败测试锁定项目详情首次点击仍阻塞主线程的缺口
- [x] 将项目详情文档读取改为后台异步加载，并补齐缓存命中 / 防串结果 / loading 状态
- [x] 视情况补充详情抽屉 loading 提示，避免旧项目内容串屏
- [x] 同步 AGENTS / lessons / memory 并完成验证闭环

## Review（原生项目详情异步文档加载）

- 直接原因：第一轮性能修复已经消掉“筛选重复读文档”“收藏/设置保存后整份 reload”两条高频卡顿链，但**首次点开未缓存项目时**，`NativeAppViewModel` 仍会在 `@MainActor` 上同步读取 `PROJECT_NOTES.md / PROJECT_TODO.md / README.md`，导致点击项目时仍有一次可感知的主线程停顿。
- 是否存在设计层诱因：存在。原生详情抽屉此前把“切换选中态”和“读取磁盘文档”绑成同一个同步步骤，因此 UI 无法先响应、再补数据；快速切换多个项目时，也缺少“只接受最新请求结果”的保护。除此之外，未发现新的明显系统设计缺陷。
- 当前修复方案：
  1. `NativeAppViewModel.swift` 新增 `isProjectDocumentLoading`、文档加载 revision 和后台任务编排；点项目时先立即更新 `selectedProjectPath` / 打开详情抽屉，再按需异步读取项目文档。
  2. 继续保留 `projectDocumentCache`：命中缓存时直接同步展示，未命中时先清空旧项目的备注 / Todo / README 回显，再在后台任务里读取磁盘文档，避免旧内容串屏。
  3. 后台任务完成后只在 **revision 仍是最新** 时才回写 UI；这样 Alpha -> Beta -> Gamma 快速切换时，Beta 的慢结果不会覆盖 Gamma 的当前详情。
  4. `ProjectDetailRootView.swift` 新增轻量 `ProgressView("正在加载项目文档…")` 提示，让抽屉在异步读取期间有明确反馈，而不是看起来像“点了没反应”。
- 长期改进建议：下一步若还要继续优化点击手感，可把 `loadSnapshot()` / `projects.json` 读取与 Git 统计刷新也逐步拆离主线程，再把首页派生聚合做成更细粒度的后台缓存，而不是继续让 `@MainActor` 兜底承接所有 IO。
- 验证证据：
  - 红灯阶段：`swift test --package-path macos --filter 'NativeAppViewModelTests/testSelectingAnotherProjectStartsAsyncDocumentLoad|NativeAppViewModelTests/testSelectingProjectOpensDetailDrawerAndLoadsNotes'` 初次运行编译失败，明确暴露 `NativeAppViewModel` 尚缺 `isProjectDocumentLoading` 与异步文档加载能力。
  - 绿灯阶段：定向测试 `swift test --package-path macos --filter 'NativeAppViewModelTests/testSelectingAnotherProjectStartsAsyncDocumentLoad|NativeAppViewModelTests/testSelectingProjectOpensDetailDrawerAndLoadsNotes|NativeAppViewModelTests/testFilterChangeDoesNotReloadProjectDocumentWhenSelectionStaysSame|NativeAppViewModelTests/testLatestAsyncProjectDocumentResultWinsWhenSelectionsRace'` 通过，覆盖抽屉即时打开、后台加载、缓存复用与快速切项目防串结果。
  - 全量验证：`swift test --package-path macos`（15/15 通过）、`swift build --package-path macos`（通过）、`git diff --check`（通过）。

## 原生首页点击卡顿修复（2026-03-19）

- [x] 通过失败测试锁定筛选点击与收藏点击的主线程卡顿根因
- [x] 为项目文档加入缓存，并避免筛选不变更选中项目时重复读文档
- [x] 将收藏 / 回收站 / 设置保存改为局部状态更新，避免整份 snapshot reload
- [x] 同步文档 / lessons 并完成验证闭环

## Review（原生首页点击卡顿修复）

- 直接原因：原生首页当前把点击后的很多真实工作都放在 `@MainActor` 的 `NativeAppViewModel` 上执行，尤其是两条高频路径：一条是**筛选点击后无条件重读当前项目文档**，另一条是**收藏 / 回收站 / 设置保存后立即调用 `load()` 触发整份 snapshot 重载**。这会把同步文件读取、JSON 解码和派生状态重算都塞进主线程，所以用户点击时会感知到明显“闷一下”。
- 是否存在设计层诱因：存在。当前原生 Phase A 里，UI 状态编排与兼容层同步 IO 仍耦合得比较紧；轻交互动作（筛选、收藏）不该默认升级成“重新读文档”或“整份状态快照重建”。除此之外，未发现新的明显系统设计缺陷。
- 当前修复方案：
  1. 给 `NativeAppViewModel.swift` 加入项目文档缓存，`refreshSelectedProjectDocument()` 优先命中缓存，避免同一个选中项目被反复同步读取。
  2. `reconcileSelectionAfterFilterChange()` 改成只有在**筛选真的导致选中项目变化**时，才刷新项目文档；如果选中的还是同一个项目，就不再重复读取 `PROJECT_NOTES.md / PROJECT_TODO.md / README.md`。
  3. `toggleProjectFavorite`、`moveProjectToRecycleBin`、`restoreProjectFromRecycleBin`、`saveSettings` 改成**写磁盘成功后直接局部更新内存快照**，不再立刻 `load()` 全量重建 `snapshot`。
  4. `saveNotes` / `saveTodo` 现在会同步更新文档缓存，保证后续切筛选或切详情时能复用最新内容，而不会再次从磁盘读回旧值。
  5. `load()` 开始时会清空文档缓存，避免用户主动刷新后继续看到过期缓存。
- 长期改进建议：这轮修掉的是最伤点击手感的两条同步链，但当前“首次点击某个未缓存项目时同步读文档”“Dashboard 更新统计仍是显式重任务入口”这两类路径仍可继续优化。下一步建议把**项目详情文档加载改成后台任务**，再把首页派生数据（尤其热力图）做增量缓存或后台聚合。
- 验证证据：
  - 红灯阶段：`swift test --package-path macos --filter 'NativeAppViewModelTests/testFilterChangeDoesNotReloadProjectDocumentWhenSelectionStaysSame|NativeAppViewModelTests/testToggleFavoriteDoesNotNeedSnapshotReloadForImmediateUiState'` 初次运行失败，分别暴露“筛选点击仍会重读损坏的备注文件”和“收藏点击仍会因为 `load()` 读取损坏的 `projects.json` 而报错”。
  - 绿灯阶段：同一条定向测试通过，说明这两条高频点击路径已不再依赖同步重复读文档 / 全量 reload。
  - 全量验证：`swift test --package-path macos`（13/13 通过）、`swift build --package-path macos`（通过）、`git diff --check`（通过）。

## 原生复刻 Git 统计与设置页（2026-03-19）

- [x] 对照 Tauri 版共享脚本与 Git 统计更新主链，确认原生复用边界
- [x] 先补共享脚本与 Git 统计更新相关失败测试
- [x] 实现 DevHavenCore 的共享脚本存储与 Git 统计更新写回
- [x] 在原生设置页接入内嵌脚本中心，并让 Dashboard 更新统计走真实链路
- [x] 对照 Tauri 版 Sidebar 热力图 / SettingsModal，收口本轮复刻范围
- [x] 先补 Git 统计筛选与聚合相关失败测试
- [x] 实现原生 ViewModel 的热力图日期筛选、活跃项目聚合与统计文案
- [x] 重做 Sidebar 的 Git 统计区与 Settings 页面结构样式
- [x] 更新 AGENTS.md / tasks 文档并完成验证闭环

## Review（原生复刻 Git 统计与设置页）

- 直接原因：用户确认首页整体视觉已经满意，下一步明确要求继续复刻 **Git 统计** 与 **设置页面**，因此本轮聚焦把原生 Phase A 从“主壳好看”推进到“关键侧边能力与设置结构也贴近 Tauri 版”。
- 是否存在设计层诱因：存在轻微的“结构已像、关键子页仍停留在骨架态”的收口缺口。此前原生侧边栏热力图只有静态方块，设置页仍是系统 `Form` 风格且暴露了 Tauri 版并未提供的字段，导致视觉与交互信息架构仍和现有产品不一致。除此之外，未发现新的明显系统设计缺陷。
- 当前修复方案：
  1. 在 `DevHavenCore` 新增 `GitStatisticsModels.swift`，把热力图日期、活跃项目、Dashboard 汇总、最近活跃日期与最活跃项目排行的聚合逻辑从视图里抽离，保持可测试。
  2. `NativeAppViewModel.swift` 新增热力图日期筛选、活跃项目列表、Dashboard 统计接口，并让热力图筛选优先级对齐 Tauri：**热力图日期筛选生效时覆盖标签筛选**；同时补了过滤后选中项目与文档草稿的重新对齐，避免详情抽屉内容滞后。
  3. 原生首页左侧 `ProjectSidebarView.swift` 改成更接近 Tauri 的 Git 统计区：3 个月热力图、日期筛选状态条、清除按钮、当天活跃项目列表；新增可复用 `GitHeatmapGridView.swift` 供 Sidebar 与 Dashboard 共用。
  4. `MainContentView.swift` 顶部波形按钮已接线到新的 `GitDashboardView.swift`，可打开原生仪表盘：时间范围切换、统计卡片、热力图、最近活跃日期、最活跃项目。
  5. `SettingsView.swift` 已从系统表单重写为 **左侧分类 + 右侧卡片区**，分类对齐 `常规 / 终端 / 脚本 / 协作`；同时去掉 Tauri 版没有的 `webEnabled/webBindHost/webBindPort/sharedScriptsRoot` 编辑入口，只保留真实支持的端口、终端主题/WebGL、Git 身份，以及脚本目录只读入口，避免伪造能力。
  6. 在用户继续要求“B. 1 2”后，`LegacyCompatStore.swift` 已补齐共享脚本主链：直接读写 `~/.devhaven/scripts/manifest.json`、脚本文件内容，并支持恢复内置预设；`SettingsView.swift` 的脚本分类现已内嵌 `SharedScriptsManagerView.swift`，可在原生设置页里管理脚本清单、参数与脚本文件。
  7. 原生 Git 仪表盘的“更新统计”已不再只是刷新 UI：`GitDailyCollector.swift` 会在本地直接执行 `git log --date=short`，按 `gitIdentities` 过滤后写回 `projects.json` 的 `git_daily` 字段，同时保留项目对象未知字段，和 Tauri 的 `collect_git_daily -> updateGitDaily -> heatmap refresh` 语义对齐。
- 长期改进建议：下一步如果继续追平设置页，可把共享脚本管理继续打磨成更接近 Tauri 的自动保存与更细的错误提示；Git 统计侧则可继续补 `heatmap_cache.json` 的 lastUpdated 真值与更明确的仓库失败列表。
- 验证证据：
  - 红灯阶段：`swift test --package-path macos --filter NativeAppViewModelTests` 初次运行失败，明确暴露原生 ViewModel 尚缺 `selectHeatmapDate` / `heatmapActiveProjects` / `gitDashboardSummary` 等接口。
  - 绿灯阶段：`swift test --package-path macos --filter NativeAppViewModelTests` 通过，覆盖热力图筛选覆盖标签、Dashboard 汇总等新增行为。
  - 第二轮红灯阶段：`swift test --package-path macos --filter 'SharedScriptsStoreTests|NativeAppViewModelTests/testRefreshGitStatisticsReadsRealGitLogAndPreservesUnknownProjectFields'` 初次运行失败，暴露 `saveSharedScriptsManifest` / `listSharedScripts` / `restoreSharedScriptPresets` / `refreshGitStatistics` 等真实主链尚未落地。
  - 第二轮绿灯阶段：同一条定向测试通过，覆盖共享脚本清单 round-trip、恢复内置预设、真实 Git 仓库 `git log` 聚合写回 `projects.json` 且保留未知字段。
  - 全量验证：`swift test --package-path macos`（11/11 通过）、`swift build --package-path macos`（通过）、`git diff --check`（通过）。

## 发布 2.8.3（2026-03-18）

- [x] 核对当前分支 / 版本 / 现有 tag / 工作区状态
- [x] 记录本轮发布计划并锁定变更范围
- [x] 更新版本号到 2.8.3
- [x] 汇总上个版本 `v2.8.2` 以来的变更说明
- [x] 运行发布前验证
- [x] 提交 release commit、创建 `v2.8.3` tag 并 push
- [x] 回写 Review（包含验证证据与发布结果）


## Review（发布 2.8.3）

- 发布结果：已将版本从 `2.8.2` 升级到 `2.8.3`，同步更新 `package.json`、`package-lock.json`、`src-tauri/Cargo.toml`、`src-tauri/Cargo.lock`、`src-tauri/tauri.conf.json`；发布提交为 `6ed1e50 fix: route control-plane notifications back to workspace`，并已创建/推送 tag `v2.8.3`。
- 本次 release 直接原因：上一版之后控制面/通知主线连续收口，当前工作区剩余未发布的核心改动集中在“通知点击回到 DevHaven 正确工作区”这一闭环，因此本轮在补齐版本号后，将通知桥接修复与版本升级一并发布。
- 是否存在设计层诱因：未发现新的系统性阻塞，但确认了一个已经被修正的诱因——此前系统通知仍依赖 `osascript display notification`，通知来源会落到“脚本编辑器”，点击后也拿不回 `projectPath/workspaceId` 导航上下文；本次发布已把通知真相源和点击跳转重新收口到 DevHaven 主链。
- `v2.8.2 -> v2.8.3` 主要变更摘要：
  1. **控制面与通知链路继续收口**：移除旧 monitor 依赖，增强 durable control plane / agent wrapper / primitive-first terminal 主线，补齐 `notificationId`、completed 已读后清理、结构化通知消费。
  2. **通知点击闭环补齐**：Tauri 侧接入 `tauri-plugin-notification`，前端 `useCodexIntegration.ts` 统一桥接 toast + 系统通知；新增 `resolveNotificationProject(...)`，支持点击通知后按 `projectPath/workspaceId` 直接打开对应项目或 Worktree。
  3. **终端与资源解析稳定性提升**：终端代理资源优先从 bundle resource 解析，减少打包后资源定位漂移；终端项目列表点击热区扩大，降低误触/点不中。
  4. **启动与运行态体验优化**：收口启动与终端内存占用、同步 quick command runtime 状态、降低 git daily 自动统计日志噪声。
- 验证证据：
  - `node --test src/utils/controlPlaneAutoRead.test.mjs src/utils/controlPlaneProjection.test.mjs src/utils/controlPlaneLifecycle.test.mjs src/utils/controlPlaneNotificationRouting.test.mjs scripts/devhaven-control.test.mjs src/services/system.test.mjs` → `37/37` 通过。
  - `node node_modules/typescript/bin/tsc --noEmit` → 通过，无输出。
  - `cargo check --manifest-path src-tauri/Cargo.toml` → 通过，`Finished 'dev' profile ...`。
  - `cargo test agent_control_registry_preserves_structured_notification_fields --manifest-path src-tauri/Cargo.toml` → `1 passed; 0 failed`。
  - `git diff --check` → 通过，无输出。
  - `git push origin main` → `a769e44..6ed1e50  main -> main`；`git push origin v2.8.3` → `[new tag] v2.8.3 -> v2.8.3`。

## 说明当前 Codex 目前推送内容（2026-03-18）

- [x] 读取技能、记忆与仓库约束，建立本轮 checklist
- [x] 定位 Codex wrapper / hook / control plane 的推送实现
- [x] 整理当前实际推送字段、触发点与前端消费位置
- [x] 回写 Review，并向用户说明结论与证据

## Review（说明当前 Codex 目前推送内容）

- 结论：当前 DevHaven 里的 Codex **不会把整段对话或整屏终端输出推到 control plane**；主线推送的是几类**结构化状态/通知元数据**，并统一挂上 `projectPath/workspaceId/paneId/surfaceId/terminalSessionId` 等上下文。实际入口是 `shell integration -> scripts/bin/codex -> scripts/devhaven-codex-wrapper.mjs -> scripts/devhaven-codex-hook.mjs -> scripts/devhaven-agent-hook.mjs -> Rust control plane`。
- 当前实际推送内容分 4 类：
  1. **通知（`devhaven_notify_target`）**：字段是 `title/subtitle/body/message/level + agentSessionId + 上下文 IDs`。Codex notify payload 会优先从 `message/summary/body/text/last-assistant-message/last_assistant_message/lastAssistantMessage` 里挑一条正文；`type/event/kind` 含 `complete` 时标成 completed/info，含 `error/fail` 时标成 failed/error，否则按 waiting/attention。
  2. **状态 primitive（`devhaven_set_status` / `clear_status`）**：当前 key 固定为 `codex`，value 主要是 `Running / Waiting / Completed / Failed / Stopped`，并附 `icon/color`，供 workspace attention 与徽标投影直接消费。
  3. **会话事件（`devhaven_agent_session_event`）**：字段是 `provider=status/message/agentSessionId/cwd + 上下文 IDs`，当前 provider 固定为 `codex`，状态会写 `running / waiting / completed / failed / stopped`。
  4. **进程 PID primitive（`devhaven_set_agent_pid` / `clear_agent_pid`）**：字段是 `key=codex`、`pid` 加上下文 IDs，用来标记当前 pane/workspace 里哪个 Codex 进程还活着。
- 触发时机：
  1. **启动真实 Codex 前**：wrapper 先推 `set_status(key=codex,value=Running)`，再推 `agent_session_event(status=running,message=\"Codex 已启动\")`。
  2. **spawn 成功拿到子进程 PID 后**：再推 `set_agent_pid(key=codex,pid=<child pid>)`。
  3. **Codex notify hook 触发时**：每次会推一组三连——`notify_target + set_status + agent_session_event`；例如需要用户确认时，会把摘要消息同时写成通知正文、Waiting 状态和值得注意的 session message。
  4. **退出或异常时**：先 `clear_agent_pid`，再把状态改成 `Stopped` 或 `Failed`，同时写一条 `agent_session_event`（例如 `Codex 已退出` 或退出异常信息）。
- 前端消费方式：`useCodexIntegration.ts` 监听 `devhaven-control-plane-changed`，对 notification 事件弹 toast / 系统通知；工作区 attention、latest message、active count 等则由 `projectControlPlaneWorkspace` / `projectControlPlaneSurface` 从 `notifications + agentSession + statuses + agentPids` 投影出来。
- 设计层判断：未发现新的明显系统设计缺陷；当前“只推结构化通知/状态，不推整段会话文本”的边界是清楚的，也是前面清理 monitor 后保留下来的低开销主线。
- 证据：
  - `scripts/devhaven-codex-wrapper.mjs`：启动/退出时推 `set_status`、`agent_session_event`、`set/clear_agent_pid`。
  - `scripts/devhaven-codex-hook.mjs`：notify 时推 `notify_target`、`set_status`、`agent_session_event`，并从 `last-assistant-message` 等字段抽正文。
  - `scripts/devhaven-agent-hook.mjs`：定义了实际 POST 到 control plane 的 payload 结构。
  - `src-tauri/src/lib.rs` + `src-tauri/src/agent_control.rs`：Rust 侧落盘 notification/status/agent_pid/session record，并发 `devhaven-control-plane-changed` 事件。


## 修复通知点击跳错目标（2026-03-18）

- [x] 读取技能、记忆与仓库约束，建立本轮 checklist
- [x] 定位系统通知点击链路与直接原因
- [x] 先补失败测试或最小复现，再实现最小修复
- [x] 运行验证并回写 Review

## Review（修复通知点击跳错目标）

- 直接原因：当前 Tauri/macOS 通知主链仍停留在 Rust `send_system_notification -> osascript display notification`。这类通知的来源应用会显示为“脚本编辑器”，点击后只会把系统带到 Script Editor，既没有 DevHaven 自己的点击回调，也没有任何“打开对应工作区”的跳转链路，所以用户看到的就是“点通知弹出脚本编辑器”。
- 是否存在设计层诱因：存在。通知真相源已经收口到 control plane，但“通知展示”和“通知点击后的导航”仍被拆在两套世界里：Rust 侧只会发一个无上下文的 AppleScript 通知，前端 `useCodexIntegration.ts` 只管 toast，不掌握系统通知点击事件，导致 control plane 明明知道 `projectPath/workspaceId/paneId`，最终外显通知却丢掉了这些导航语义。除此之外，未发现新的明显系统设计缺陷。
- 当前修复方案：
  1. 保留 control plane 作为通知真相源，但取消 `agent_control.rs` 在写入 notification 后直接走 `osascript` 发通知的主路径。
  2. 在 Tauri 侧接入 `tauri-plugin-notification`，并把 `src/services/system.ts` 改成**优先使用 Web Notification API** 发送系统通知，这样通知来源回到 DevHaven 本体，同时可以保留 `onclick` 回调；只有 Notification API 不可用时才回退到原后端命令。
  3. `useCodexIntegration.ts` 现在会在收到结构化 control-plane notification 时，统一发 toast + 系统通知，并在通知点击后通过 `resolveNotificationProject` 把 `projectPath/workspaceId` 解析为真实项目/Worktree，再直接调用 `openTerminalWorkspace` 跳到对应工作区。
  4. 新增 `src/utils/controlPlaneNotificationRouting.ts`，把“普通项目路径优先、Worktree 路径回退、workspaceId 兜底”的解析规则收口成单独 helper，避免点击跳转逻辑散落在 hook 里。
  5. 同步更新 `AGENTS.md` 中 control-plane / system-notification 职责说明，明确当前通知主链已改成“Rust 负责结构化事件，前端负责可点击系统通知桥接”。
- 长期改进建议：后续如果继续强化通知体验，最好把“通知点击后不仅打开工作区，还能精确定位 pane/surface/terminal session”也做成统一路由协议，而不是在 hook 里逐步堆条件；同时如果未来真的恢复多窗口终端模式，需要再补一层“只有主窗口负责外显系统通知”的单点桥，避免重复通知。
- 验证证据：
  - 红灯阶段：`node --test src/utils/controlPlaneNotificationRouting.test.mjs src/services/system.test.mjs` 初次运行失败，暴露出“通知路由 helper 缺失”和“系统通知服务没有 click callback / 仍走旧 Tauri 路径”两处缺口。
  - 绿灯阶段：`node --test src/utils/controlPlaneAutoRead.test.mjs src/utils/controlPlaneProjection.test.mjs src/utils/controlPlaneLifecycle.test.mjs src/utils/controlPlaneNotificationRouting.test.mjs scripts/devhaven-control.test.mjs src/services/system.test.mjs`（37/37 通过）；`node node_modules/typescript/bin/tsc --noEmit`（通过，无输出）；`cargo check --manifest-path src-tauri/Cargo.toml`（通过，含 `tauri-plugin-notification` 新依赖）；`git diff --check`（通过）。

## 实施 Codex 通知完整修复（2026-03-18）

- [x] 读取技能、计划与当前工作区状态，建立本轮 checklist
- [x] 先补通知模型 / payload / auto-read 相关失败测试
- [x] 实现结构化通知、Rust 主投递与 pane/surface 级已读修复
- [x] 同步更新计划文档与 AGENTS.md 中的职责说明
- [x] 运行验证并回写 Review

## Review（实施 Codex 通知完整修复）

- 直接原因：当前 DevHaven 的 Codex 通知效果不佳，核心卡在三处：Codex 常见 `last-assistant-message` 字段未兼容导致正文经常退化成兜底文案；系统通知主链依赖前端 `useCodexIntegration -> loadControlPlaneTree` 二次转发；workspace 一激活就批量 auto-read，导致其它 pane 的提醒被过早清掉。
- 是否存在设计层诱因：存在。控制面通知职责原先分散在 hook / Rust control plane / React hook / workspace view 四层，且 notification model 只有扁平 `message`，导致正文兼容、通知投递和已读语义彼此耦合。除此之外，未发现新的明显系统设计缺陷。
- 当前修复方案：
  1. `scripts/devhaven-codex-hook.mjs` 兼容 `last-assistant-message` / `last_assistant_message` / `lastAssistantMessage`，并在 primitive-only 通知路径显式透传 `body`。
  2. Rust `src-tauri/src/agent_control.rs` 把 notification record 升级为结构化字段（`title/subtitle/body/level/message`），`devhaven_notify` / `devhaven_notify_target` 落盘后直接发送系统通知，并在 `devhaven-control-plane-changed` 里附带结构化 notification payload。
  3. 前端 `useCodexIntegration.ts` 改为优先消费事件里的结构化 notification 来弹 toast，只有兼容场景才回退 tree pull；Tauri 运行时不再重复发系统通知。
  4. `collectNotificationIdsToMarkRead` 与 `TerminalWorkspaceView.tsx` 改成按 active pane/surface/session 精准 auto-read；`projectControlPlaneSurface` 改为读取真实匹配 notification，保证 pane latest message 在 read 后仍正确保留。
  5. 同步写入 `docs/plans/2026-03-18-codex-notification-fix-plan.md`，并更新 `AGENTS.md` 中 control-plane 通知职责说明。
- 长期改进建议：后续如果继续追平 cmux 体验，下一步应考虑“通知列表/跳转到最新未读”这类产品能力，但前提依然是继续保住当前这条低开销主线——结构化 notification、Rust 主投递、pane/surface 级已读，不要退回 monitor 扫描或前端主通知链。
- 验证证据：
  - 红灯阶段：`node --test src/utils/controlPlaneAutoRead.test.mjs src/utils/controlPlaneLifecycle.test.mjs scripts/devhaven-control.test.mjs` 初次运行按预期失败（hyphen-case payload、workspace 级 auto-read、pane latest message 三类用例）；`cargo test agent_control_registry_preserves_structured_notification_fields --manifest-path src-tauri/Cargo.toml` 初次运行因 `NotificationInput` / `NotificationRecord` 缺字段而编译失败。
  - 绿灯阶段：`node --test src/utils/controlPlaneAutoRead.test.mjs src/utils/controlPlaneProjection.test.mjs src/utils/controlPlaneLifecycle.test.mjs scripts/devhaven-control.test.mjs`（33/33 通过）；`cargo test agent_control_registry_preserves_structured_notification_fields --manifest-path src-tauri/Cargo.toml`（通过）；`node node_modules/typescript/bin/tsc --noEmit`（通过，无输出）；`cargo check --manifest-path src-tauri/Cargo.toml`（通过）；`git diff --check`（通过）。

## 产出 Codex 通知完整修复方案（2026-03-18）

- [x] 基于上一轮对照结果收敛本轮计划目标与边界
- [x] 明确完整修复目标、非目标与验收标准
- [x] 设计分阶段实施方案（数据模型 / 后端 / 前端 / hook / 验证）
- [x] 识别风险、迁移顺序与回滚策略
- [x] 回写 Review，并向用户交付完整修复方案

## Review（产出 Codex 通知完整修复方案）

- 直接原因：用户要求的是“完整修复方案”，不是只指出 1~2 个表面差异，因此本轮把 Codex 通知问题重新收口为一条完整主线：**payload 兼容、通知模型、Rust 投递职责、前端消费职责、pane/surface 级已读生命周期、验证闭环** 必须一起设计，不能继续只修单点。
- 是否存在设计层诱因：存在，且较明显。当前 DevHaven 的通知职责分散在 `scripts/devhaven-codex-hook.mjs`、`src-tauri/src/agent_control.rs`、`src/hooks/useCodexIntegration.ts`、`src/components/terminal/TerminalWorkspaceView.tsx` 四层；同时通知记录还是单 `message` 扁平模型，导致字段兼容、通知投递、已读策略彼此耦合。除此之外，未发现新的系统设计缺陷源头。
- 当前完整方案结论：采用 **四阶段修复** 最稳妥——Phase 0 先补 payload 兼容与回归测试；Phase 1 升级 control plane 通知模型为结构化通知，并保持旧字段兼容；Phase 2 把系统通知主投递前移到 Rust/control-plane 侧，前端降级为 UI 投影；Phase 3 把 auto-read 从 workspace 级批量已读收紧为 pane/surface 级焦点已读，并补齐 attention / latestMessage 投影测试。
- 风险与迁移策略：本轮明确不做“大爆炸重写”。先保证现有 wrapper/hook 不断，结构化字段先增量兼容，再切通知主投递位置，最后才调整已读语义；这样每一步都可独立验证和回滚，避免再次出现“通知没了但不知道是 hook、Rust 还是前端哪层断掉”。
- 验证证据：本轮方案依据来自真实代码与本地实测，而非纯记忆推断——包括 `scripts/devhaven-codex-hook.mjs` / `src/hooks/useCodexIntegration.ts` / `src/utils/controlPlaneAutoRead.ts` / `src-tauri/src/agent_control.rs` 的当前实现，对照 cmux 的 `docs/notifications.md` / `CLI/cmux.swift` / `Sources/TerminalNotificationStore.swift` / `Sources/TabManager.swift` / `Sources/AppDelegate.swift`，以及 `node --input-type=module` 对 Codex hyphen 字段丢失的实测输出。


## 对照 cmux 排查 Codex 通知差异（2026-03-18）

- [x] 读取技能、记忆与仓库约束，建立本轮 checklist
- [x] 梳理 DevHaven 当前 Codex 通知 / attention / control-plane 链路
- [x] 梳理 cmux 中对应的 Codex 通知实现与触发链路
- [x] 逐点对比两边差异并定位主要问题
- [x] 回写 Review、证据与后续建议

## Review（对照 cmux 排查 Codex 通知差异）

- 直接原因：DevHaven 当前 Codex 通知链路与 cmux 相比有两处最硬的差异。其一，`scripts/devhaven-codex-hook.mjs` 只识别 `last_assistant_message` / `lastAssistantMessage`，**没有兼容 Codex 常见的 `last-assistant-message` 字段**，导致不少通知正文会退化成兜底文案“Codex 需要你的关注”；其二，DevHaven 的系统通知/Toast 不在 Rust 收到通知时直接投递，而是要先写 control plane、发 `devhaven-control-plane-changed` 事件，再由前端 `useCodexIntegration` 异步回拉整棵 tree 后二次转发，因此链路比 cmux 多一跳、也更脆弱。
- 设计层诱因：存在明显的“通知真相源与通知投递职责分裂”。cmux 的 `cmux notify -> notify_target -> TerminalNotificationStore.addNotification` 是同进程直接闭环；DevHaven 则把“记录通知”“决定是否属于 Codex”“真正弹 Toast/系统通知”“自动已读”拆散在 hook、Rust control plane、React hook、workspace view 四处，导致字段兼容、事件粒度、已读时机任何一处变粗都会影响最终效果。
- 当前建议修复方案：
  1. 先补齐 Codex payload 兼容：`summarizeNotifyPayload` 至少同时支持 `last-assistant-message` / `last_assistant_message` / `lastAssistantMessage`，避免正文丢失。
  2. 再收紧通知投递路径：尽量让 Rust 在收到 `notify_target` 时就具备“可直接投递系统通知”的能力，前端只负责补充 UI 投影，不要把真正的通知投递完全依赖 `useCodexIntegration -> loadControlPlaneTree` 这条异步链路。
  3. 最后重做已读策略：不要像现在这样“工作区一激活就把该 workspace 下所有 unread 全部标记已读”，至少要收紧到当前 pane / 当前 surface 级别，向 cmux 的 focus-aware 语义看齐。
- 长期改进建议：如果目标真的是“参照 cmux 的通知体验”，后续不应只模仿 hook 命令，而应补齐 cmux 真正高价值的那层基础设施：**pane/surface 级 unread 生命周期、直接投递、按焦点抑制外部通知、以及结构化 title/subtitle/body**。否则即使 control plane 事件正确，最终体验仍会显得“有通知链路，但提醒不够准也不够稳”。
- 验证证据：
  - `node --input-type=module` 导入 `summarizeNotifyPayload` 后实测：输入 `{"last-assistant-message":"来自 hyphen 字段的消息"}` 会返回兜底文案 `Codex 需要你的关注`；而输入 `last_assistant_message` 才会正确取正文，证明当前 DevHaven 确实漏了 Codex 常见字段。
  - `printf '{"last-assistant-message":"来自 cmux 文档的消息"}' | jq -r '."last-assistant-message" // "Turn complete"'` 输出真实消息，和 `cmux/docs/notifications.md` 中 Codex 示例一致。
  - 代码对照：DevHaven `src/hooks/useCodexIntegration.ts` 需要在收到事件后再 `loadControlPlaneTree` 并调用 `sendSystemNotification`；cmux `Sources/TerminalNotificationStore.swift` 则在 `addNotification` 后直接 `scheduleUserNotification`，没有再经过前端回拉。
  - 已读语义对照：DevHaven `src/utils/controlPlaneAutoRead.ts` + `TerminalWorkspaceView.tsx` 会在 workspace 处于 active 时批量 `markControlPlaneNotificationRead`；cmux 只会在当前 tab+surface 真正处于焦点交互时调用 `markRead(forTabId:surfaceId:)`。

## 提交工作区左侧项目点击区域扩大改动（2026-03-18）

- [x] 重新运行提交前验证并确认结果
- [x] 暂存本轮改动并执行 commit
- [x] 回写提交 Review 与结果

## Review（提交工作区左侧项目点击区域扩大改动）

- 提交范围：本轮提交包含左侧项目列表整行点击热区修复、对应实施计划文档，以及 `tasks/todo.md` 中的任务与审查记录。
- 直接原因：用户明确要求“进行 git commit”，因此在实现完成后重新执行了一轮新鲜验证，再将本轮 3 个目标文件暂存并提交。
- 是否存在设计层诱因：本次提交针对的核心问题仍是“视觉上是整行列表项，但实际只有局部文字按钮可点”的交互边界不一致；除此之外，未发现新的明显系统设计缺陷。
- 提交结果：已执行 `git commit -m "fix: 扩大终端项目列表点击区域"`，当前以本轮最新 `fix: 扩大终端项目列表点击区域` 提交为准，可用 `git log --oneline -1` 核对最终提交号。
- 验证证据：`git status --short`（提交前 staged 文件为 `docs/plans/2026-03-18-terminal-sidebar-hit-area.md`、`src/components/terminal/TerminalWorkspaceWindow.tsx`、`tasks/todo.md`）；`node node_modules/typescript/bin/tsc --noEmit`（通过，无输出）；`pnpm build`（通过，Vite build succeeded）；`git diff --check`（通过）。

## 工作区左侧项目点击区域扩大（2026-03-18）

- [x] 读取技能、记忆与仓库约束，建立本轮 checklist
- [x] 定位左侧项目列表的点击命中区域实现与约束
- [x] 给出最小改动方案并与用户确认
- [x] 实现改动、完成定向验证并回写 Review

## Review（工作区左侧项目点击区域扩大）

- 直接原因：`src/components/terminal/TerminalWorkspaceWindow.tsx` 里左侧“已打开项目”的根项目行与 worktree 行，主选择动作都只绑在文字按钮本身，导致行容器、状态点、未读数周围留白都不算命中区域，用户会感知为“点击区域有点小”。
- 是否存在设计层诱因：存在轻微的交互入口分裂——视觉上整行都像一个列表项，但实现上只有局部文字按钮可选中，导致命中区域与视觉边界不一致；除此之外，未发现明显系统设计缺陷。
- 当前修复方案：把根项目行与可打开的 worktree 行都改成**整行可点**，并保留右侧刷新 / 创建 worktree / 关闭 / 重试 / 删除按钮的独立行为（继续 `stopPropagation()`）；同时补了 `role="button"`、`tabIndex` 与 `Enter / Space` 键盘激活，避免扩大热区后可访问性退化。
- 长期改进建议：这类终端侧边栏列表项后续可抽成统一的“可整行激活 + trailing actions”模式组件，避免项目行、worktree 行、未来其他侧栏列表再次各写一套命中区域逻辑。
- 验证证据：`node node_modules/typescript/bin/tsc --noEmit`（通过，无输出）；`pnpm build`（通过，Vite build succeeded）；`git diff --check`（通过，无 whitespace/冲突类问题）；`git status --short`（本轮改动文件为 `src/components/terminal/TerminalWorkspaceWindow.tsx`、`tasks/todo.md`，新增 `docs/plans/2026-03-18-terminal-sidebar-hit-area.md`）。

## 提交当前工作区改动（2026-03-17）

- [x] 记录本轮提交范围与待办
- [x] 重新运行提交前验证并确认结果
- [x] 暂存当前改动并执行 commit
- [x] 回写 Review 与提交结果

## Review（提交当前工作区改动）

- 提交范围：本轮将控制面通知竞态修复链路与相应任务沉淀一并提交，包含 Rust `notification_id` 事件字段补齐、前端 `notificationId` 类型/消费逻辑同步、`controlPlaneAutoRead` 过滤逻辑与回归测试，以及 `tasks/lessons.md` / `tasks/todo.md` 记录更新。
- 直接原因：用户要求“直接 commit”，因此在前一轮 diff 审阅基础上，按仓库约束重新执行了一轮新鲜验证，再提交当前工作区全部 8 个改动文件。
- 是否存在设计层诱因：本次提交针对的核心问题仍是“控制面变更事件粒度过粗，前端需要回拉全量 tree 再猜本次通知”，修复方向是把 notification 主键直接下沉到事件 payload；除此之外，未发现新的明显系统设计缺陷。
- 提交结果：已执行 `git commit -m "fix: 控制面通知事件携带 notificationId"`，当前提交为 `c902021`。
- 验证证据：`git status --short`（提交前 8 个目标文件均为已修改）；`node --test src/utils/controlPlaneAutoRead.test.mjs`（4/4 通过）；`node node_modules/typescript/bin/tsc --noEmit`（通过，无输出）；`cargo check --manifest-path src-tauri/Cargo.toml`（通过）；`git diff --check`（通过）。

## 未暂存改动分析（2026-03-17）

- [x] 记录本轮未暂存 diff 分析范围与待办
- [x] 查看未暂存文件清单、摘要与关键 diff
- [x] 总结主要改动意图、潜在风险与建议
- [x] 回写 Review 与证据

## Review（未暂存改动分析）

- 本轮未暂存改动的**主线非常集中**：真正的功能代码都围绕“控制面 notification 事件要显式携带 `notificationId`，前端消费时优先按主键精确取通知，避免后续通知被时间窗口竞态提前吞掉”这一处修复展开。涉及链路完整：Rust `ControlPlaneChangedPayload` → TS payload 类型 → `useCodexIntegration` 订阅消费 → `collectNewControlPlaneNotifications` 过滤逻辑 → 对应回归测试。
- 代码改动之间是自洽的：`src-tauri/src/agent_control.rs` 为 notification / read / unread 事件补 `notification_id`，并把其它 reason 显式设为 `None`；`src-tauri/src/agent_launcher.rs` 也同步补齐字段，避免 Rust 结构体新增字段后遗漏编译入口；前端 `src/models/controlPlane.ts`、`src/hooks/useCodexIntegration.ts`、`src/utils/controlPlaneAutoRead.ts` 与测试文件同步消费该字段，说明这不是半截改动。
- 审阅判断：**未发现明显阻塞问题**。当前实现保留了“无 `notificationId` 时按 `since` 回退”的兼容路径，同时新增测试准确覆盖“显式 ID 优先于时间窗口”的关键竞态场景；轻量验证也已通过。
- 需要注意的非功能性风险：`tasks/todo.md` 与 `tasks/lessons.md` 里混有两类内容——一类是本轮通知修复的 Review/教训，一类是本次/此前的分析记录（包括暂存区/未暂存区分析与 Swift 可行性评估）。如果你后续想做一个**只包含通知修复**的干净 commit，这两个文件会让提交主题变宽，最好在提交前确认是否要拆分。
- 验证证据：`git diff --stat`（8 files changed, 154 insertions(+), 2 deletions(-)）；`node --test src/utils/controlPlaneAutoRead.test.mjs`（4/4 通过）；`node node_modules/typescript/bin/tsc --noEmit`（通过，无输出）；`cargo check --manifest-path src-tauri/Cargo.toml`（通过）；`git diff --check`（通过）。

## 暂存区内容分析（2026-03-17）

- [x] 记录本轮暂存区分析范围与待办
- [x] 查看暂存文件清单、摘要与关键 diff
- [x] 总结主要改动意图、潜在风险与建议
- [x] 回写 Review 与证据

## Review（暂存区内容分析）

- 结论：当前 **暂存区为空**，`git diff --cached --stat` 与 `git diff --cached --name-status` 都没有输出，因此没有可供逐文件审阅的 staged diff。
- 当前工作区存在 **未暂存** 修改，主要文件为 `src-tauri/src/agent_control.rs`、`src-tauri/src/agent_launcher.rs`、`src/hooks/useCodexIntegration.ts`、`src/models/controlPlane.ts`、`src/utils/controlPlaneAutoRead.test.mjs`、`src/utils/controlPlaneAutoRead.ts`、`tasks/lessons.md`、`tasks/todo.md`；其中 `tasks/todo.md` 包含本轮为满足仓库流程新增的分析记录。
- 风险判断：如果你原本以为这些改动已经 `git add`，那当前实际上还没有进入待提交集合；此时直接 `git commit` 不会带上这些文件。
- 建议：若你要我继续审阅“准备提交但还没 add 的改动”，下一步应改看 `git diff`（未暂存）；若你只是想确认 staged 状态，那么本轮结论就是“暂无 staged 内容”。
- 验证证据：`git status --short`（仅看到工作区 ` M`，没有 `M  / A  / D  / R` 等 index 侧标记）；`git diff --cached --stat`（无输出）；`git diff --cached --name-status`（无输出）。

## Codex 通知一两轮后不再弹出排查（2026-03-16）

- [x] 记录用户反馈现象、建立本轮排查 checklist
- [x] 梳理 Codex 通知生产/消费链路并定位根因
- [x] 先补失败测试，再做最少修改修复
- [x] 运行定向验证并补充 Review 结论与证据

## Review（Codex 通知一两轮后不再弹出排查）

- 直接原因：`useCodexIntegration` 当前是收到 `devhaven-control-plane-changed(reason=notification)` 后，再去加载**整棵** control-plane tree，并用 `updatedAt >= payload.updatedAt` 的时间窗口筛通知。这个实现把“当前这条通知事件”和“树里后来才写入的通知”混在了一起；如果后续几轮通知在前一次异步 `loadControlPlaneTree` 返回前就已经落盘，前一次回调会把这些**未来通知**提前记进 `seenNotificationIdsRef`，导致它们自己的事件到来时被误判成“已处理”，用户就会感知为“通知一两轮后就不再弹了”。
- 设计层诱因：控制面变更事件只带了 `projectPath/workspaceId/updatedAt`，没带 **具体 notificationId**，前端只能靠“重新拉全量树 + 时间窗口”猜测本次是哪条通知；这是事件语义过粗导致的消费竞态。除此之外，未发现明显系统设计缺陷。
- 当前修复方案：给 `ControlPlaneChangedPayload` 增加可选 `notificationId`，Rust 在 `reason=notification` / `notification-read` / `notification-unread` 时把具体通知 ID 一并带上；前端 `collectNewControlPlaneNotifications` 优先按显式 `notificationIds` 精确挑选通知，仅在缺少 ID 的兼容场景下才退回旧的 `since` 逻辑。
- 长期改进建议：后续若继续扩展控制面通知，优先坚持“**事件 payload 直接带主键，消费侧按主键处理**”的原则，避免再次走“收到事件后回拉整棵树再猜是谁”的路径；如果还要做更多通知聚合，可继续把 toast/system-notify 消费逻辑下沉为纯函数并补独立回归测试。
- 验证证据：`node --test src/utils/controlPlaneAutoRead.test.mjs src/utils/controlPlaneLifecycle.test.mjs src/utils/controlPlaneProjection.test.mjs scripts/devhaven-control.test.mjs`（30/30 通过）；`node node_modules/typescript/bin/tsc --noEmit`（通过，无输出）；`cargo check --manifest-path src-tauri/Cargo.toml`（通过）；`git diff --check`（通过）。

## 工作区改动检查与提交（2026-03-16）

- [x] 记录本次检查范围与待办，建立 Review 占位
- [x] 审阅当前工作区改动与关键 diff，确认是否存在明显问题
- [x] 按改动范围执行必要验证并记录证据
- [x] 若验证通过且未发现阻塞问题，则完成 commit 并回写 Review

## Review（工作区改动检查与提交）

- 本次工作区改动集中在 `src/utils/controlPlaneProjection.ts`、`src/utils/controlPlaneLifecycle.test.mjs`、`tasks/lessons.md`、`tasks/todo.md`；核心代码变更是把 workspace 级 `completed` attention 收口为“**仅在仍有未读通知时显示**”，与 2026-03-15 的用户反馈“已读后绿点不应继续保留”一致。
- 直接原因已在前一条修复记录中确认：项目列表里的绿点来自 `controlPlaneProjection.attention === "completed"`，不是 unread badge；已读流程只会清 notification，不会自动清状态点。本次 diff 用最少修改把 `completed` 状态展示与未读通知重新绑定，未改动 `failed / waiting / running` 优先级。
- 审阅结果：未发现新的明显阻塞问题，也未发现额外系统设计缺陷；`latestMessage` 仍会保留最近完成消息，项目列表/Header 的未读 badge 继续只由 `unreadCount` 决定，行为与预期一致。
- 验证证据：`node --test src/utils/controlPlaneProjection.test.mjs src/utils/controlPlaneAutoRead.test.mjs src/utils/controlPlaneLifecycle.test.mjs scripts/devhaven-control.test.mjs`（29/29 通过）；`node node_modules/typescript/bin/tsc --noEmit`（通过，无输出）；`git diff --check`（通过，无 whitespace/冲突类问题）。
- 提交说明：本轮检查通过后按 `fix: 已读后不再保留 completed 控制面状态点` 提交当前工作区改动。

## Codex 消息通知分析（2026-03-15）

- [x] 梳理 Codex 通知写入入口与触发场景
- [x] 梳理通知消失时机、已读/未读状态与自动清理逻辑
- [x] 梳理前端状态展示位置与投影视图
- [x] 汇总结论、补充 Review 与验证证据

## Review（Codex 消息通知分析）

- 当前 **真正会触发 UI 级“消息通知”** 的不是 Codex 启动/退出本身，而是 `scripts/devhaven-codex-hook.mjs` 的 `notify` 生命周期：外部 payload 会先被归一化为 `waiting / completed / failed` 三类，再写入 `devhaven_notify_target`、`devhaven_set_status(key=codex)`、`devhaven_agent_session_event(provider=codex)`；其中只有 `devhaven_notify_target` 会生成控制面 notification 记录并触发前端 toast / 系统通知。
- Codex wrapper 启动与退出只会改 **状态**，不会直接发 UI 消息：启动时写 `Running + "Codex 已启动"`，正常退出写 `Stopped + "Codex 已退出"`，异常退出写 `Failed + 异常信息`；这些会影响“运行中/状态点/最新文案”，但不会走 `useCodexIntegration` 的 popup 通知链路。
- 通知记录在 Rust 控制面里创建后默认 `read=false`，会落盘到 `~/.devhaven/agent_control_plane.json`；目前未发现自动删除/过期清理逻辑，只有“标记已读/未读”，因此**最新消息文本可长期保留**，直到被新的 notification / session message / primitive status 覆盖。
- “消失”分三层：1) 顶层 toast 由 `useToast` 固定 1600ms 自动消失；2) 系统通知交给操作系统管理，代码未控制停留时长；3) 终端内未读角标会在工作区处于 active 时被 `TerminalWorkspaceView` 自动批量标记已读后消失，但最新消息文本与部分状态点不会因此自动清空。
- 状态展示当前至少有三处：终端左侧项目列表（最新消息 + 状态点 + 未读数 + Codex 运行点）、终端 Header（控制面 attention + 未读 badge + 最近消息 + Codex 运行中胶囊）、顶层全局 toast（右上角绿色/红色浮层）；其中颜色语义为 error=红、waiting=黄、completed=绿、running=蓝。
- 额外注意：`useCodexIntegration` 判断是否“Codex 树”是按 workspace 级别粗粒度判断的，只要该 tree 内存在 codex session/status/pid 或通知文案含 `Codex`，后续新 notification 就会被当作 Codex 通知转成 toast / 系统通知；混合 provider 场景下这里有潜在误归类空间。
- 验证证据：`/usr/local/bin/node --test scripts/devhaven-control.test.mjs`（17/17 通过，覆盖 Codex/Claude wrapper 与 notification lifecycle）；`/usr/local/bin/node node_modules/typescript/bin/tsc --noEmit`（通过，无输出）。

## Codex completed 角标已读后仍保留修复（2026-03-15）

- [x] 复核 completed 绿点未消失的直接原因与影响范围
- [x] 先补回归测试，覆盖 completed 状态在已读后不再保留 workspace attention
- [x] 按最少修改原则修复 control plane workspace 投影
- [x] 运行定向验证并补充 Review 记录

## Review（Codex completed 角标已读后仍保留修复）

- 直接原因已确认：项目列表里的绿色点走的是 `controlPlaneProjection.attention === "completed"` 状态展示，而不是 unread badge；已读链路只会把 notification 标成 `read=true`，不会自动清除 workspace attention。
- 本轮先按 TDD 补了回归测试 `workspace projection clears completed attention after notifications are read`，锁定“completed 消息已读后，workspace attention 应回落到 idle，但 latestMessage 仍保留”的目标行为，避免以后再把状态点和未读角标混淆。
- 修复采用最少修改原则：仅调整 `src/utils/controlPlaneProjection.ts::projectControlPlaneWorkspace`，让 `completed` attention 只有在当前 workspace 仍有未读 notification 时才显示；`failed / waiting / running` 的优先级与行为保持不变。
- 修复后效果：用户读完 completed 通知后，项目列表/终端 Header 的 completed 绿色状态点会消失；最近消息文本仍会保留，Codex 运行中点与其他错误/等待态不受影响。
- 验证证据：`$HOME/.nvm/versions/node/v22.22.0/bin/node --test src/utils/controlPlaneProjection.test.mjs src/utils/controlPlaneAutoRead.test.mjs src/utils/controlPlaneLifecycle.test.mjs scripts/devhaven-control.test.mjs`（29/29 通过）；`$HOME/.nvm/versions/node/v22.22.0/bin/node node_modules/typescript/bin/tsc --noEmit`（通过，无输出）。

## 终端工作区过快回收修复（2026-03-13）

- [x] 定位“工作区一会没看就被回收，运行中的任务被结束”的直接原因
- [x] 先补回归测试，覆盖切项目/非激活工作区时运行中 session 不应被自动结束
- [x] 按最少修改原则修复错误回收链路，并同步必要经验记录
- [x] 运行定向验证并补充 Review 记录

## pane 类型选择回退修复（2026-03-13）

- [x] 定位“打开项目/最后一个 session 退出后直接变 shell”与 pending pane 设计不一致的根因
- [x] 先补回归测试，覆盖默认打开项目与最后一个 session/tab 关闭后的 pending pane 行为
- [x] 按最少修改原则修复默认快照与 fallback tab 的 pane 类型
- [x] 运行定向验证并补充 Review 记录

## DevHaven Agent MVP（2026-03-13）

- [x] 读取实现前必须遵循的技能与当前仓库约束
- [x] 确定「pane 级 shell|agent 双态」MVP 的范围与接入点
- [x] 写入设计文档与实施计划
- [x] 先补前端 helper / 状态流测试，再实现 pane 级 Agent 状态流
- [x] 将 Agent 入口收回到 pane-local overlay，并完成本地验证
- [x] 按用户新反馈回滚错误方向，并重做“pane 本身就是 agent”的方案
- [x] 将 pane 级 agent 实现升级为多 provider adapter（Claude Code / Codex / iFlow）
- [x] 将“创建后切换”改为“创建 pane 时先选 shell/agent 身份”
- [x] 将“创建前选类型”重做为“pane 先出现，再在 pane 内选择 shell/agent”

## OpenCove Agent 代理探索（2026-03-13）

- [x] 读取会话技能、经验与 opencove 项目约束
- [x] 扫描 opencove 中 agent 代理相关入口、核心模块与调用链
- [ ] 提炼 agent 代理的架构模式、状态模型与运行机制
- [ ] 结合当前项目给出可迁移实现方案与风险建议

## 内存优化第一轮实施（2026-03-13）

- [x] 为 Codex monitor 按需启动补失败用例并完成实现
- [x] 为终端输出队列背压补失败用例并完成实现
- [x] 为 replay 缓冲分层预算补失败用例并完成实现
- [x] 更新文档/索引并完成构建、测试、审查结论

## Review（内存优化第一轮实施）

- 已把 Codex monitor 从“冷启动默认拉起”改为**按需启用**：`src/App.tsx` 新增启用门控，`src/hooks/useCodexMonitor.ts` 支持 `enabled` 模式，`src/components/Sidebar.tsx` / `src/components/CodexSessionSection.tsx` 在未启用时展示轻量占位与“启用”按钮；同时进入终端工作区会自动启用监控，保留终端侧 Codex 状态联动。
- 已把 PTY 输出链路从无界 `mpsc::channel` 改成**有界 `sync_channel`**，并补充 `terminal_output_channel_is_bounded` 回归测试，防止高吞吐终端继续通过无界字符串队列顶高 RSS。
- 已把 Rust replay 缓冲改为**分层预算**：活跃 PTY 约 2MiB、后台保活 PTY 约 256KiB；新增 `TerminalReplayMode` 与 `terminal_set_replay_mode` 命令，前端 `TerminalPane` 在 preserve unmount 时主动把后台会话切到 parked 预算。
- 本轮验证通过：`node --test src/utils/codexMonitorActivation.test.mjs src/components/terminal/terminalMemoryPolicy.test.mjs`、`cargo test command_catalog_keeps_web_subset_of_tauri --manifest-path src-tauri/Cargo.toml`、`cargo test terminal_ --manifest-path src-tauri/Cargo.toml`、`cargo check --manifest-path src-tauri/Cargo.toml`、`pnpm build`。

## 内存优化第二轮实施（2026-03-13）

- [x] 为 Codex monitor 扫描链路瘦身补失败用例并完成实现
- [x] 为 terminal / quick-command registry 回收补失败用例并完成实现
- [x] 为终端布局快照启动加载成本收口补失败用例并完成实现
- [x] 更新文档/索引并完成构建、测试、审查结论

## Review（内存优化第二轮实施）

- 已继续瘦身 `src-tauri/src/codex_monitor.rs`：新增 rollout 文件数量上限，避免历史会话很多时一次监控全量处理过多 jsonl；`record_snapshot_state` 已从整份 `CodexMonitorSession` clone 改成轻量 digest，减少快照去重常驻内存；进程探测改为复用 `MonitorRuntime.system`，不再每轮新建 `sysinfo::System`。
- 已给 `src-tauri/src/terminal_runtime/session_registry.rs` 与 `src-tauri/src/terminal_runtime/quick_command_registry.rs` 增加上限回收：当 exited / finished 记录超过容量时，会优先回收最旧的已结束记录，防止长时间运行后 registry 只增不减。
- 已把启动期的终端布局恢复摘要查询改成 **storage 直出**：`src-tauri/src/lib.rs::list_terminal_layout_snapshot_summaries` 不再调用 `ensure_terminal_layout_runtime_loaded`；新的 `src-tauri/src/storage.rs::list_terminal_layout_snapshot_summaries` 会直接从 store 返回 summary，避免应用启动恢复“已打开项目”时就把全部 snapshot 导入 runtime。
- 已同步更新 `AGENTS.md`，记录 runtime registry 回收、summary 直出路径与 Codex monitor 的进一步收口策略，避免实现和文档漂移。
- 本轮验证通过：`cargo check --manifest-path src-tauri/Cargo.toml`、`cargo test codex_monitor::tests::collect_rollout_files_caps_recent_results --manifest-path src-tauri/Cargo.toml`、`cargo test terminal_runtime::session_registry::tests::session_registry_prunes_old_exited_sessions_when_over_capacity --manifest-path src-tauri/Cargo.toml`、`cargo test terminal_runtime::quick_command_registry::tests::quick_command_registry_prunes_finished_jobs_when_over_capacity --manifest-path src-tauri/Cargo.toml`、`cargo test storage --manifest-path src-tauri/Cargo.toml`、`pnpm build`。

## 项目切换回收策略修正（2026-03-13）

- [x] 为“切项目不降级 replay”补失败用例并完成实现
- [x] 更新 lessons / 审查记录并完成验证

## Review（项目切换回收策略修正）

- 用户反馈确认：上一轮把“切项目短暂后台”错误等同于“长期后台保活”，导致 `TerminalPane` 在 preserve unmount 时立刻把 replay 模式切到 `parked`，切回项目后历史输出明显变短。
- 本轮新增 `src/components/terminal/terminalReplayModePolicy.ts` 与对应测试，把当前策略明确固化为：**项目切换 preserve unmount 默认不降级 replay**；仅在未来显式启用时才切到 `parked`。
- `src/components/terminal/TerminalPane.tsx` 已改为通过策略函数决定是否调用 `setTerminalReplayMode`，当前默认返回 `null`，因此切项目不会再主动把后台 PTY 历史预算降到 parked。
- 本轮验证通过：`node --test src/components/terminal/terminalReplayModePolicy.test.mjs src/utils/codexMonitorActivation.test.mjs src/components/terminal/terminalMemoryPolicy.test.mjs`、`pnpm exec tsc --noEmit`、`pnpm build`。

## 快捷命令状态同步修复（2026-03-13）

- [x] 为“快捷命令结束后 Header / Run 面板状态分叉”补失败用例
- [x] 修复 quick command manager / terminal runtime 的 jobId 与结束态同步
- [x] 运行定向验证并补充审查记录

## Review（快捷命令状态同步修复）

- 根因已定位为 **quick command manager 与 terminal runtime registry 双写但 jobId 不一致**：`quick_command_start` 在 manager 中生成一份 jobId，而 runtime registry 又自行新建另一份 jobId，导致后续 `quick_command_stop/finish` 更新的是 manager job，`quick_command_runtime_snapshot` 读到的却仍是 runtime 里那条旧 running job。
- 这会直接造成你看到的现象：顶部 Header 基于 `quick_command_runtime_snapshot` 的 script 级 active job 继续显示“可停止/不可重新运行”，而底部 Run 面板已经依据 `markRunPanelTabExitedInSnapshot` 写入的 `endedAt/exitCode` 显示“已完成”。
- 本轮修复把 runtime start 改为 **以 manager 生成的 jobId 原样 upsert 到 runtime registry**，确保 start / stop / finish / snapshot 全部围绕同一条 job 记录收敛；同时补了回归测试 `sync_runtime_job_start_keeps_runtime_job_id_in_sync` 防止以后再次漂移。
- 本轮验证通过：`cargo test sync_runtime_job_start_keeps_runtime_job_id_in_sync --manifest-path src-tauri/Cargo.toml`、`cargo test quick_command_ --manifest-path src-tauri/Cargo.toml`、`cargo check --manifest-path src-tauri/Cargo.toml`。

## Review（DevHaven Agent MVP）

- 已按 **pane 级 shell|agent 双态** 路线重写设计与计划：`docs/plans/2026-03-13-devhaven-agent-pane-command-design.md`、`docs/plans/2026-03-13-devhaven-agent-pane-command-mvp.md` 不再把 Agent 作为工作区级入口，而是把控制权收回到 pane 本身。
- 已重写 `src/models/agent.ts` 与 `src/models/agent.test.mjs`：当前模型改为 pane 级 agent runtime map，支持带 marker 的 Codex 启动命令包装、输出 marker 解析，以及 `starting -> running -> stopped/failed` 状态迁移。
- 已将运行态 hook 改为 `src/hooks/usePaneAgentRuntime.ts`，不再维护“项目级唯一 Agent”，而是按 `sessionId -> runtime` 跟踪每个 terminal pane 的 agent 状态、pending command 与 pty 绑定。
- 已在 `src/models/terminal.ts` / `src/utils/terminalLayout.ts` 为 terminal 工作区引入 `pendingTerminal` 模型与对应 helper；新建 tab / split pane 不再直接变成 shell 或 agent，而是先出现 pending pane，再在 pane 内完成类型选择。
- 已回滚“创建前选类型”和已定型 pane 右上角状态 UI：`src/components/terminal/TerminalWorkspaceHeader.tsx` 恢复为纯终端头部；`src/components/terminal/TerminalTabs.tsx` 的 “+” 重新只负责创建 pending tab；`src/components/terminal/TerminalPane.tsx` 只保留“新建 Pane”菜单，不再常驻显示 agent provider / 状态 / 停止按钮；新增 `src/components/terminal/TerminalPendingPane.tsx` 承载 `Shell / Codex / Claude Code / iFlow` 选择。
- 已继续把 pane 级模型升级为 **多 provider adapter**：新增 `src/agents/registry.ts` 与 `src/agents/adapters/{codex,claudeCode,iflow}.ts`，当前支持 `Codex / Claude Code / iFlow` 三个 provider；provider-specific 命令由 adapter 生成，并统一走 `src/agents/shellWrapper.ts` 的 marker 包裹。
- 已把交互重做为 **pending pane**：`src/models/terminal.ts` 新增 `pendingTerminal` pane descriptor、`appendPendingTerminalTabToSnapshot`、`realizePendingTerminalPaneInSnapshot`、`splitPendingPaneInSnapshot`；`src/components/terminal/TerminalTabs.tsx` 的 “+” 与 `src/components/terminal/TerminalPane.tsx` 的 “新建 Pane” 现在都只创建 pending pane，再由 `src/components/terminal/TerminalPendingPane.tsx` 在 pane 内部完成 `Shell / Codex / Claude Code / iFlow` 选择。
- 已继续收口视觉：`src/components/terminal/TerminalPendingPane.tsx` 改成更明显的占位卡片样式，并支持**默认聚焦 Shell、上下键切换、Enter 确认**；已定型 `TerminalPane` 不再在右上角常驻显示 provider/状态/停止等 Agent 控件，同时去掉了 settled pane 的“新建 Pane”按钮，避免与终端内容抢视觉注意力。
- 当前限制：运行态仍是前端投影、不支持重启自动恢复/多 provider task 绑定；但这版已经符合“pane 先出现，再在 pane 里决定它是 shell 还是哪个 provider 的 agent”的交互模型。
- 本轮验证通过：`node --test src/models/agent.test.mjs src/models/terminal.snapshot.test.mjs`、`pnpm exec tsc --noEmit`、`pnpm build`。


## collect_git_daily 日志收口（2026-03-13）

- [x] 定位 collect_git_daily 高频日志与自动统计触发链路
- [x] 为 Git Daily 自动刷新策略补失败测试
- [x] 收口自动刷新调度并移除 collect_git_daily 高频 Info 日志
- [x] 运行定向验证并追加 Review

## Review（collect_git_daily 日志收口）

- 直接原因：`src-tauri/src/lib.rs` 的通用 `log_command` / `log_command_result` 会为 `collect_git_daily` 打印 `command start/done`，同时 `collect_git_daily` 自身又额外打印 `paths=`，而前端 `useAppActions` 会在缺失 `git_daily` 时自动分批触发统计，导致日志里反复出现高频 Info。
- 设计层诱因：存在状态建模过粗的问题。前端一直用 `!project.git_daily` 同时表示“未加载 / 空结果 / 失败未写入”，自动补齐流程难以区分“已尝试但为空”和“真的还没统计”。
- 当前修复方案：新增 `src/utils/gitDailyRefreshPolicy.ts`，把 Git Daily 自动调度策略收口为可测试 helper；自动补齐现在会按“路径 + identity 签名”记录本轮已尝试项目，只在启动后/身份变化后对同一项目自动统计一次，避免空结果项目持续重复拉取；同时在 Rust 侧对白名单命令 `collect_git_daily` 关闭高频 Info 命令日志。
- 长期改进建议：将 `Project.git_daily` 的“值”和“加载状态”拆开，例如新增 `gitDailyStatus/gitDailyUpdatedAt/gitDailyError`，从根上区分 idle / loaded / empty / error，届时自动刷新策略就能更精确地决定何时重试。
- 验证证据：`node --test src/utils/gitDailyRefreshPolicy.test.mjs`；`pnpm exec tsc --noEmit`；`cargo check --manifest-path src-tauri/Cargo.toml`。

## Review（pane 类型选择回退修复）

- 直接原因：虽然新建 tab / split pane 已切到 `pendingTerminal`，但默认布局 `createDefaultLayoutSnapshot` 与“最后一个 session / tab 被移除”的 fallback 仍沿用旧的 shell terminal 兜底，所以打开项目或 `Ctrl+D`/shell 退出到最后一个 session 时，会直接生成 shell，会话真相与 pane 类型选择 UI 脱节。
- 设计层诱因：存在**默认入口与新增交互模型未同源收敛**的问题。pending pane 只覆盖了“显式新建 pane”路径，没有同步覆盖初始化和兜底恢复路径，属于状态入口分裂；除此之外，未发现明显系统设计缺陷。
- 当前修复方案：把默认快照和最后一个 session/tab 的 fallback 全部改为 `pendingTerminal`，标题统一为“新建 Pane”；同时补充回归测试，覆盖首次打开项目、最后一个 session 退出、最后一个 tab 关闭三条路径。
- 长期改进建议：将“默认 pending pane 标题/描述”收口为共享常量或 helper，避免未来在不同入口再次出现 shell/pending 文案或类型漂移。
- 验证证据：`node --test src/models/terminal.snapshot.test.mjs src/components/terminal/terminalWorkspaceShellModel.test.mjs`；`pnpm exec tsc --noEmit`；`pnpm build`。

## Review（终端工作区过快回收修复）

- 直接原因：`src/components/terminal/TerminalWorkspaceWindow.tsx` 在 2026-03-10 的性能优化后只挂载当前 `activeProject` 的 `TerminalWorkspaceView`，一旦切到别的项目，原项目 workspace 会立刻卸载；而项目级运行态（尤其 `src/hooks/useQuickCommandRuntime.ts`）在 workspace 卸载时会执行 unmount 清理，把仍在运行的 quick command 标记为“终端会话已关闭”，导致用户感知为“后台任务被很快回收/结束”。
- 设计层诱因：存在**“PTY 保活”和“workspace 运行态保活”职责分裂**问题。`TerminalPane` 只负责会话级 `preserveSessionOnUnmount`，但工作区级的 quick command / agent runtime 仍依赖 React 挂载生命周期；只保活 PTY、不保活 workspace，本质上还是会让后台任务状态失真。除此之外，未发现明显系统设计缺陷。
- 当前修复方案：恢复为**所有已打开项目的 `TerminalWorkspaceView` 都保持挂载**，仅把非激活项目隐藏并禁交互；新增 `src/components/terminal/terminalWorkspaceMountModel.ts` 收口挂载/可见性/dispatch 分发规则，并在 `TerminalWorkspaceWindow` 里按该模型渲染，避免切项目就卸载后台 workspace。
- 长期改进建议：后续如果还想继续做内存优化，应该把 quick command / pane agent 等运行态迁到独立的 durable store，再考虑更细粒度回收；在那之前，不要再次把“后台项目可恢复”简化成“只保 PTY，不保 workspace”。
- 验证证据：`node --test src/components/terminal/terminalWorkspaceMountModel.test.mjs src/models/terminal.snapshot.test.mjs src/components/terminal/terminalWorkspaceShellModel.test.mjs`；`pnpm exec tsc --noEmit`；`pnpm build`。

## cmux Agent 增强方案迁移设计与实施（2026-03-13）

- [x] 对照 DevHaven 当前 agent 增强实现与 cmux 参考方案，梳理关键差异
- [x] 识别当前设计的直接问题、设计层诱因与可迁移边界
- [x] 输出 2-3 个迁移方案并给出推荐方案
- [x] 与用户确认设计结论，并写入设计稿 / 实施计划
- [x] 先补 Rust 控制面 registry / command 的失败测试
- [x] 实现 Rust 控制面 registry、命令与事件
- [x] 为 terminal session 注入 DEVHAVEN_* 控制面环境变量
- [x] 先补前端 control plane projection 的失败测试
- [x] 接入前端 workspace / pane attention projection
- [x] 回退旧 pane-agent provider 主线为纯 terminal primitive
- [x] 更新 AGENTS.md、lessons、Review 并完成整体验证

## Review（cmux Agent 增强方案迁移设计与实施）

- 直接原因：原有 agent 增强把 provider 选择、运行态、通知和 pane 身份耦合在前端 `pendingTerminal + usePaneAgentRuntime + stdout marker` 主线上，导致 agent/session/pane 的真相源分裂。
- 设计层诱因：存在明显的职责分裂——布局真相在 `TerminalLayoutSnapshot`，运行态真相在 React hook，PTY/client 真相在前端 registry 与 Rust session registry，provider 语义又嵌在 UI 交互里；这类结构很难继续演进成 cmux 式 primitive + control plane。
- 当前修复方案：
  1. 新增 Rust 控制面 `src-tauri/src/agent_control.rs`，收口 terminal binding / agent session / notification registry，并暴露 `devhaven_identify/devhaven_tree/devhaven_notify/devhaven_agent_session_event/devhaven_mark_notification_read/devhaven_mark_notification_unread` 与事件 `devhaven-control-plane-changed`。
  2. `src-tauri/src/terminal.rs::terminal_create_session` 现在支持 `workspaceId/paneId/surfaceId` 上下文，并注入 `DEVHAVEN_WORKSPACE_ID / DEVHAVEN_PANE_ID / DEVHAVEN_SURFACE_ID / DEVHAVEN_TERMINAL_SESSION_ID` 等环境变量。
  3. 前端新增 `src/models/controlPlane.ts`、`src/services/controlPlane.ts`、`src/utils/controlPlaneProjection.ts`，并在 `TerminalWorkspaceWindow` / `TerminalWorkspaceHeader` 投影 unread、latest message、attention。
  4. 终端主路径已回退为 pure terminal primitive：默认布局、最后一个 session/tab 的 fallback、`handleNewTab` 与 split 主路径都直接创建 shell terminal；`TerminalWorkspaceView` 已移除 provider-specific 命令注入主线。
- 长期改进建议：
  1. 给外部 agent 增加正式 wrapper / hook 模板（优先 Claude / Codex），把 `devhaven_*` 命令真正接入 shell 工作流。
  2. 第二阶段把 browser surface / shell telemetry（cwd/git/ports/tty）也接入同一控制面，补齐真正的 cmux 风格 primitive 体系。
  3. 继续清理 `src/agents/*`、`usePaneAgentRuntime`、`pendingTerminal` 等兼容残留，避免旧模型长期滞留仓库。
- 验证证据：
  - `node --test src/utils/controlPlaneProjection.test.mjs src/models/terminal.snapshot.test.mjs src/components/terminal/terminalWorkspaceShellModel.test.mjs`
  - `cargo test agent_control --manifest-path src-tauri/Cargo.toml`
  - `cargo test command_catalog --manifest-path src-tauri/Cargo.toml`
  - `cargo test terminal_ --manifest-path src-tauri/Cargo.toml`
  - `cargo check --manifest-path src-tauri/Cargo.toml`
  - `pnpm exec tsc --noEmit`
  - `pnpm build`

## cmux Agent 第二轮收口（外部接入链路）（2026-03-13）

- [x] 为 terminal session 注入可直接调用控制面的 DEVHAVEN_CONTROL_ENDPOINT
- [x] 新增通用 `scripts/devhaven-control.mjs` 与外部 agent hook 模板
- [x] 补 wrapper / web_server / terminal env 相关测试并完成验证

## Review（cmux Agent 第二轮收口）

- 直接原因：虽然第一轮已经有了 Rust 控制面与 `DEVHAVEN_*` 归属环境变量，但外部 agent 进程还缺少“如何真正调用控制面”的固定入口；只有 ID 没有 endpoint，wrapper/hook 仍无法零配置接线。
- 设计层诱因：第一轮只完成了 registry 与前端 projection，没有把“外部进程 -> 控制面命令”的调用约定收口为统一脚本/endpoint，这会让后续每个 provider 都各自重复造轮子。除此之外，未发现新的系统设计缺陷。
- 当前修复方案：
  1. `src-tauri/src/web_server.rs` 新增 loopback base URL 解析，`src-tauri/src/terminal.rs` 在创建 terminal session 时为 shell 注入 `DEVHAVEN_CONTROL_ENDPOINT=http://127.0.0.1:<port>/api/cmd`。
  2. 新增通用脚本 `scripts/devhaven-control.mjs`、`scripts/devhaven-agent-hook.mjs`，以及 provider 模板 `scripts/devhaven-claude-hook.mjs`、`scripts/devhaven-codex-hook.mjs`，让外部 agent 可直接复用现成命令桥接到 `devhaven_notify` / `devhaven_agent_session_event`。
  3. 补充 `scripts/devhaven-control.test.mjs`、`web_server` loopback helper 测试、`terminal::apply_terminal_control_env_includes_http_command_endpoint` 回归测试，确认 endpoint/env 真的可用。
- 长期改进建议：
  1. 把 Claude / Codex 的实际官方 hook 协议进一步适配到这些模板脚本，减少用户手动拼 JSON。
  2. 后续可以把 `DEVHAVEN_CONTROL_ENDPOINT` 与未来的 browser/control surface endpoint 一起统一成更完整的 SDK/CLI。
  3. 继续清理 `src/hooks/usePaneAgentRuntime.ts`、`src/components/terminal/TerminalPendingPane.tsx`、`src/agents/*` 等兼容残留，直到仓库里不再保留旧的 pane-agent 运行时主线。
- 验证证据：
  - `node --test scripts/devhaven-control.test.mjs src/utils/controlPlaneProjection.test.mjs src/models/terminal.snapshot.test.mjs src/components/terminal/terminalWorkspaceShellModel.test.mjs`
  - `cargo test web_server --manifest-path src-tauri/Cargo.toml`
  - `cargo test terminal_ --manifest-path src-tauri/Cargo.toml`
  - `cargo test agent_control --manifest-path src-tauri/Cargo.toml`
  - `cargo test command_catalog --manifest-path src-tauri/Cargo.toml`
  - `cargo check --manifest-path src-tauri/Cargo.toml`
  - `pnpm exec tsc --noEmit`
  - `pnpm build`

## cmux Agent 第三轮清场（2026-03-13）

- [x] 为旧 pending pane 快照补归一化测试并完成实现
- [x] 删除未再使用的 pane-agent 兼容组件 / hook / adapter
- [x] 运行整体验证并补充 Review

## Review（cmux Agent 第三轮清场）

- 直接原因：第二轮之后，外部 agent 接入链路已经具备，但仓库里仍保留 `TerminalPendingPane`、`usePaneAgentRuntime`、`src/agents/*`、`src/models/agent.ts` 等旧 pane-agent 时代的壳层代码；这些文件已经不再参与主路径，却会继续误导后续实现。
- 设计层诱因：如果不在控制面切换完成后及时做一次“删旧模型”的清场，代码库会长期同时存在两套心智模型：一套是 control plane truth，一套是前端 pane-agent truth，后续维护者很容易再次沿错误路径接回旧逻辑。
- 当前修复方案：
  1. 新增 `normalizeLayoutSnapshotForShellPrimitives`，在加载旧布局快照时把 legacy `pendingTerminal` 归一化为 shell terminal，保证兼容历史数据但不再需要 pending UI 主路径。
  2. 删除 `src/components/terminal/TerminalPendingPane.tsx`、`src/hooks/usePaneAgentRuntime.ts`、`src/agents/*`、`src/models/agent.ts` / `src/models/agent.test.mjs` 等不再使用的旧实现。
  3. `TerminalWorkspaceShell` / `PaneHost` 已不再挂 pending pane 选择器；主路径只保留 terminal/run/filePreview/gitDiff/overlay primitive。
- 长期改进建议：
  1. 若未来还需要兼容更老的布局版本，继续把兼容逻辑收口到加载时归一化 helper，而不是恢复旧 UI 组件。
  2. 后续可继续清查 `src/services/agentSessions.ts` / `src/models/agentSessions.ts` 是否仍有价值，避免留下一批新的半接线文件。
  3. 完成 provider 实际 hook 落地后，再决定是否需要单独的 CLI 包或 SDK 层。
- 验证证据：
  - `pnpm exec tsc --noEmit`
  - `node --test scripts/devhaven-control.test.mjs src/utils/controlPlaneProjection.test.mjs src/models/terminal.snapshot.test.mjs src/components/terminal/terminalWorkspaceShellModel.test.mjs`
  - `cargo test agent_control --manifest-path src-tauri/Cargo.toml`
  - `cargo test command_catalog --manifest-path src-tauri/Cargo.toml`
  - `cargo test web_server --manifest-path src-tauri/Cargo.toml`
  - `cargo test terminal_ --manifest-path src-tauri/Cargo.toml`
  - `cargo check --manifest-path src-tauri/Cargo.toml`
  - `pnpm build`

## Codex 自动通知与通知自动已读修复（2026-03-14）

- [x] 定位 Codex 自动通知未接通的直接原因与设计层诱因
- [x] 定位通知未自动已读/消失的直接原因与设计层诱因
- [x] 先补失败测试，覆盖 Codex 事件桥接到控制面、切回对应 workspace 后通知自动已读
- [x] 实现最小修复并完成验证/Review

## Review（Codex 自动通知与通知自动已读修复）

- 直接原因：`codex_monitor.rs` 已经能产出 `agent-active / task-complete / task-error / needs-attention` 等真实事件，但 `src/hooks/useCodexIntegration.ts` 之前只把这些事件用于 toast / 系统通知，没有桥接到 `notifyControlPlane()` / `emitAgentSessionEvent()`；同时前端虽然已经有 `markControlPlaneNotificationRead()`，但主路径从未调用，所以测试通知会一直保持 unread。
- 设计层诱因：存在 **Codex monitor 状态流** 与 **control plane 状态流** 两套平行链路，且 notification 生命周期只有“写入/展示”没有“消费”阶段；这属于状态生命周期闭环缺失。
- 当前修复方案：
  1. 新增 `src/utils/codexControlPlaneBridge.ts`，把 `CodexAgentEvent` 映射成统一的 control plane `agentSessionEvent + notification` payload，并在 `useCodexIntegration.ts` 中桥接真实 Codex monitor 事件进入 control plane。
  2. 新增 `src/utils/controlPlaneAutoRead.ts`，并在 `TerminalWorkspaceView.tsx` 中对当前 active workspace 的 unread notifications 自动调用 `markControlPlaneNotificationRead()`，让测试通知在用户已经切到对应工作区时自动消失。
  3. 保留现有 toast / 系统通知提示，但 control plane 现在也会同步收到 `Codex 需要处理 / 执行失败 / 已完成` 等状态。
- 长期改进建议：
  1. 后续可把这条桥接进一步下沉到后端，让 `codex_monitor.rs` 直接接入 `agent_control.rs`，彻底消除前端双状态流。
  2. 现在的自动已读策略是 workspace 级，后续可细化为 pane/surface 级消费策略。
  3. 对 Claude 等 provider 也可复用同样的 bridge helper，逐步统一 provider-neutral notification policy。
- 验证证据：
  - `pnpm exec tsc --noEmit`
  - `node --test src/utils/codexControlPlaneBridge.test.mjs src/utils/controlPlaneAutoRead.test.mjs scripts/devhaven-control.test.mjs src/utils/controlPlaneProjection.test.mjs src/models/terminal.snapshot.test.mjs src/components/terminal/terminalWorkspaceShellModel.test.mjs`
  - `pnpm build`

## Codex wrapper 与原会话监听裁剪评估（2026-03-14）

- [x] 盘点现有 Codex 会话监听、wrapper 与控制面的职责边界
- [x] 追踪当前前后端对 Codex monitor 的实际消费点与依赖链
- [x] 判断 wrapper 是否已完整覆盖 monitor 能力，并给出删除/保留建议
- [x] 记录 Review，补充分析证据

## Review（Codex wrapper 与原会话监听裁剪评估）

- 当前**还不建议直接删除** `codex_monitor` 主链。仓库现状是：wrapper/hook 只负责把事件推到 control plane（`scripts/devhaven-codex-hook.mjs` → `devhaven_agent_session_event` / `devhaven_notify`），而原 monitor 仍承担**全局会话发现、启动后恢复、侧栏 CLI 会话列表、项目级 Codex 运行计数**。
- 直接证据：`src/App.tsx` 仍通过 `useCodexMonitor` 驱动 `Sidebar` 的 `CodexSessionSection` 与 `TerminalWorkspaceWindow` 的 `codexProjectStatusById`；`src/hooks/useCodexIntegration.ts` 仍基于 monitor sessions 生成 `codexSessionViews` 并把 monitor 事件桥接进 control plane。
- wrapper 当前**没有完成产品级全接管**：仓库里只提供了 `scripts/devhaven-control.mjs` / `scripts/devhaven-agent-hook.mjs` / `scripts/devhaven-codex-hook.mjs` 这些接入脚本，没有发现应用内部自动强制所有 Codex 启动都走 wrapper 的链路。
- 即使你本机已经手工接好了 wrapper，当前 control plane 仍是**内存态 registry**（`src-tauri/src/agent_control.rs`），wrapper 也是**事件推送型**而不是快照恢复型；应用重启后，既有 Codex 会话不会自动回灌。原 monitor 通过 `src-tauri/src/codex_monitor.rs` 监听 `~/.codex/sessions` + 轮询进程，恰好补了这块恢复能力。
- 因此更稳妥的结论是：
  1. **现在不能直接删 monitor**；
  2. 若你的目标是避免 monitor 与 wrapper 双上报，优先考虑**先移除/开关掉“monitor 事件 -> control plane”桥接**，而不是先删掉会话发现能力；
  3. 等 control plane 补齐“会话列表 / 项目级运行计数 / 启动恢复 / 全量 wrapper 接管”后，再删除 `codex_monitor.rs`、`useCodexMonitor.ts`、`CodexSessionSection.tsx` 这一整套。
- 本次分析证据命令：`rg -n "codex_monitor|useCodexMonitor|get_codex_monitor_snapshot|codex-monitor" src src-tauri scripts`、`rg -n "devhaven-codex-hook|DEVHAVEN_CONTROL_ENDPOINT|devhaven_notify|devhaven_agent_session_event" src src-tauri scripts`、`sed -n '1,260p' src/hooks/useCodexIntegration.ts`、`sed -n '1,260p' src/hooks/useCodexMonitor.ts`、`sed -n '1,260p' scripts/devhaven-codex-hook.mjs`、`sed -n '1,280p' src-tauri/src/agent_control.rs`。

## Codex monitor 删除迁移方案设计（2026-03-14）

- [ ] 盘点删除 Codex monitor 前必须保留的用户能力、数据源与恢复链路
- [ ] 明确 wrapper/control plane 接管 monitor 所需补齐的能力缺口
- [ ] 设计分阶段迁移方案、风险控制与回滚点
- [ ] 产出迁移清单与验收标准，并记录 Review


## Codex wrapper 误报执行失败修复（2026-03-14）

- [x] 复现并定位 Codex 会话为何被持续误判为 `task-error`
- [x] 对照现有实现与参考模式，确认最小修复边界
- [x] 先补失败测试，覆盖“成功 tool output 仅因包含 error/failed 字样而被误判”的回归场景
- [x] 实现修复并完成针对性验证
- [x] 追加 Review，记录直接原因、设计诱因、修复方案与长期建议

## Review（Codex wrapper 误报执行失败修复）

- 直接原因：`src-tauri/src/codex_monitor.rs` 之前在解析 `response_item.type=function_call_output` 时，直接对整段 `output` 文本做关键字扫描；只要成功输出里出现 `error` / `failed` / `task-error` 之类字样，就会把当前会话打成 `CodexMonitorState::Error`。而 Codex 的真实 tool 输出经常会把源代码、grep 命中、编译日志片段原样塞进 `output`，即使前面已经明确写着 `Process exited with code 0`，也会被误判成失败。
- 设计层诱因：monitor 当前把“结构化状态信号”与“自由文本内容”混在同一条判定链路里，缺少“优先信结构化字段、谨慎处理自由文本”的边界；这和 cmux 里 hook/notify 主要依赖显式事件类型驱动状态切换的思路相反。除此之外，未发现新的系统设计缺陷。
- 当前修复方案：
  1. 为 `function_call_output` 单独增加 `function_call_output_indicates_error()`，优先读取结构化 `is_error=true`，其次只识别标准的 `Process exited with code <非 0>` / `Process exited with signal ...`，不再扫描整段成功输出里的任意关键字。
  2. `classify_entry()` 的文本匹配改为**只看值、不看对象 key**，避免 `is_error: false` 这种字段名本身就把会话误判成 error。
  3. 新增 3 个回归测试：
     - 成功 `function_call_output` 即使正文含有 `task-error` 字样也应保持 `Completed`
     - 非 0 exit code 仍应判定为 `Error`
     - `is_error: false` 不应仅因字段名包含 `error` 被误判
- 长期改进建议：
  1. 后续如果继续增强 Codex monitor，优先补“结构化事件 -> 状态”的显式映射，而不是继续扩大自由文本关键字匹配范围。
  2. 若未来 wrapper 真正全量接管状态上报，可以把 monitor 收缩成恢复/发现能力，减少再次从 `.jsonl` 里猜状态的职责。
  3. 可补一个真实样本回放测试集，覆盖 `exec_command`/`cargo`/`pnpm`/`rg` 等常见 tool 输出，避免再被日志内容误伤。
- 验证证据：
  - `cargo test parse_session_file_keeps_successful_function_call_output_with_error_text_completed --manifest-path src-tauri/Cargo.toml`
  - `cargo test classify_entry_does_not_treat_is_error_false_key_name_as_error --manifest-path src-tauri/Cargo.toml`
  - `cargo test parse_session_file_marks_error_when_function_call_output_reports_non_zero_exit_code --manifest-path src-tauri/Cargo.toml`
  - `cargo test codex_monitor --manifest-path src-tauri/Cargo.toml`
  - `cargo check --manifest-path src-tauri/Cargo.toml`

## Codex 完成通知缺失排查（2026-03-14）

- [x] 收集最新现象证据，确认完成事件是否从 monitor 生成
- [x] 对照 wrapper / bridge / control plane 链路定位中断层
- [x] 先补失败测试，再实现最小修复
- [x] 运行针对性验证并补 Review

## Review（Codex 完成通知缺失排查）

- 直接原因：`src-tauri/src/codex_monitor.rs` 的 `process_event_msg()` 之前没有处理 `event_msg.payload.type = "task_complete"`。而我抽样检查最近 67 份带 `task_complete` 的 Codex session，发现至少有 2 份**没有任何 assistant message，只在最后写了 `task_complete`**。这类完成态会被 monitor 直接落成 `Idle`，于是不会产出 `task-complete` 事件，也就没有 toast / 系统通知 / 控制面通知。
- 设计层诱因：当前 monitor 同时兼容“从 assistant message 推断完成”和“从显式 session event 恢复状态”两种来源，但完成态路径只实现了前者，没有把 Codex 已经给出的显式 `task_complete` 事件接入同一真相链路，属于状态源接线不完整。除此之外，未发现新的明显系统设计缺陷。
- 当前修复方案：
  1. 在 `process_event_msg()` 中显式处理 `task_complete`，把它视为完成信号，更新 `last_assistant_ts / last_agent_activity_ts`。
  2. 当 `task_complete` 自身不带正文时，如果此前没有更好的 details，就回退为 `任务已完成`，保证会话状态可解释。
  3. 新增回归测试 `parse_session_file_marks_completed_when_task_complete_has_no_assistant_message`，锁住“只有显式 task_complete 也必须完成”的场景。
- 长期改进建议：
  1. 把 monitor 中所有 provider 显式事件（例如 `task_complete / task_error / needs_attention`）统一纳入结构化事件优先的判定链，减少对消息文本推断的依赖。
  2. 如果后续 wrapper 接管更完整，可以把 monitor 进一步收缩为“恢复/发现兜底”，避免重复猜状态。
  3. 追加真实 session 样本回放测试，覆盖“无 assistant message 直接 task_complete”的 provider 变体。
- 验证证据：
  - `cargo test parse_session_file_marks_completed_when_task_complete_has_no_assistant_message --manifest-path src-tauri/Cargo.toml`
  - `cargo test parse_session_file_keeps_successful_function_call_output_with_error_text_completed --manifest-path src-tauri/Cargo.toml`
  - `cargo test codex_monitor --manifest-path src-tauri/Cargo.toml`
  - `cargo check --manifest-path src-tauri/Cargo.toml`

## Codex 控制面通知已写入但 UI 不显示排查（2026-03-14）

- [x] 收集 control plane tree / projection / auto-read 证据
- [x] 定位 toast / 系统通知 / 最新消息分别为何未出现
- [x] 先补失败测试，再实现最小修复
- [x] 完成验证并补 Review

## Review（Codex 控制面通知已写入但 UI 不显示排查）

- 直接原因：这次日志已经证明 `devhaven_agent_session_event` 与 `devhaven_notify` 都成功执行，问题不在后端命令失败，而在**前端没有以 control plane notification 作为统一的 UI 通知源**。当前 toast / 系统通知只由 `useCodexIntegration` 里的 codex monitor 事件流触发；当外部 wrapper 直接写入 control plane（`devhaven_notify`）时，UI 不会额外弹 toast / 系统通知。另一方面，终端头部的“最新消息”文案优先取 pane projection，而 `projectControlPlaneSurface()` 只在 `unreadCount > 0` 时才返回 notification message；通知一旦被 active workspace 自动已读，inline latest message 就立刻消失。
- 设计层诱因：目前存在 **monitor 事件流** 与 **control plane notification 流** 两套并行的“用户提示”来源，但 UI 只消费前者、头部 latest message 又只消费 unread pane 视角，导致 wrapper 直写 control plane 时出现“后端有记录、前端无反馈”的断层。这属于通知消费真相源分裂。除此之外，未发现新的明显系统设计缺陷。
- 当前修复方案：
  1. `useCodexIntegration.ts` 新增对 `devhaven-control-plane-changed` 的监听：当 reason=`notification` 时，回读对应 workspace tree，提取本次新写入的 Codex 通知，并统一触发 toast / 系统通知；这样 monitor 桥接和 wrapper 直写都会走同一条 UI 提示链。
  2. monitor 事件桥接仍负责把 Codex 状态写入 control plane，但当该事件已经会生成 control plane notification 时，不再直接在同一个 effect 里重复 toast，避免后续双提示。
  3. `TerminalWorkspaceHeader.tsx` 现在会在 active pane latest message 为空时回退显示 workspace 级 latest message，因此通知被 auto-read 后，头部仍能看到最近一条控制面消息，而不是立刻清空。
  4. `ControlPlaneNotification` 前端模型补齐 `updatedAt`，并新增 helper / 测试覆盖“按事件时间提取新通知”“pane 文案为空时回退 workspace latest message”。
- 长期改进建议：
  1. 后续把 toast / 系统通知彻底统一到 control plane notification 真相源，逐步让 monitor 只负责写入状态，不再直接承担 UI 提示。
  2. 若要进一步减少竞态，可让后端 `devhaven-control-plane-changed` payload 直接携带 notification record，而不是前端再回读 tree。
  3. 空 session 文件 warning 仍是噪音，后续可把“新建但尚未写入 session_meta 的空 rollout 文件”降级为静默跳过，避免干扰排障。
- 验证证据：
  - `node --test src/utils/controlPlaneAutoRead.test.mjs src/utils/controlPlaneProjection.test.mjs src/utils/codexControlPlaneBridge.test.mjs`
  - `pnpm exec tsc --noEmit`

## Codex 通知链路最小诊断日志（2026-03-14）

- [x] 检查事件订阅/派发实现，选定最小日志打点位置
- [x] 补充前端诊断日志并给出复现观察点
- [ ] 根据日志结果继续缩小根因范围
- [x] 更新 Review 与证据

## Review（Codex 通知链路最小诊断日志）

- 当前结论：需要前端运行时日志来判断 control-plane changed 事件是否到达 `useCodexIntegration.ts`、tree 回读后是否拿到了新 notification、以及 `showToast()` / `sendSystemNotification()` 是否真正被调用。后端日志已经证明 `devhaven_notify` 成功，因此下一步应该看前端链路，而不是继续猜 Rust 侧是否没写入。
- 本轮新增诊断打点：
  1. `src/hooks/useCodexIntegration.ts`：打印 `control-plane-changed` payload、tree 回读结果、提取到的新通知、monitor event -> control plane 映射结果，以及是否进入 direct toast / delegated 流程。
  2. `src/hooks/useToast.ts`：打印 `showToast()` 是否真的被调用。
  3. `src/services/system.ts`：打印系统通知 API 是否可用、权限状态、以及是否真正 dispatch。
- 建议你下一轮复现时打开前端控制台，重点过滤关键字：`[codex-debug]`。
- 重点观察顺序：
  1. 是否出现 `[codex-debug] control-plane-changed`；若没有，说明前端根本没收到事件。
  2. 若有，再看 `[codex-debug] loaded control-plane tree` / `collected new control-plane notifications`；若为空，说明 tree 回读/筛选条件有问题。
  3. 若已经出现 `[codex-debug] forwarding control-plane notification to toast/system`，再看是否有 `[codex-debug] showToast invoked`；若没有，说明 effect 逻辑被提前 return。
  4. 若 `showToast invoked` 已出现但 UI 仍不显示，再转查 toast 渲染层。
- 验证证据：
  - `pnpm exec tsc --noEmit`

## Codex 控制面事件订阅诊断增强（2026-03-14）

- [x] 给前端 listener 注册/卸载路径补生命周期日志
- [x] 给 Rust emit_control_plane_changed 补发射日志
- [ ] 让用户复现并采集新日志
- [x] 更新 Review 与证据

## Review（Codex 控制面事件订阅诊断增强）

- 当前结论：既然后端 `devhaven_notify` 已成功，而前端连一条 `[codex-debug] control-plane-changed` 都没有，那么还需要区分是“前端 listener 根本没注册成功”还是“Rust emit 发了但 Tauri 前端没收到”。
- 本轮新增诊断：
  1. `src/hooks/useCodexIntegration.ts` 现在会打印 listener effect mount / register / cleanup 生命周期日志，用来确认前端是否真的完成了 `listenControlPlaneChanged()` 注册。
  2. `src-tauri/src/agent_control.rs::emit_control_plane_changed()` 现在会打印每次发射的 `project_path / workspace_id / reason / updated_at`，用来确认 Rust 是否真的进入 emit。
- 下一轮请你重启应用后复现，并同时看两处日志：
  1. **前端控制台**：查 `[codex-debug] useCodexIntegration control-plane listener effect mounted` 与 `[codex-debug] control-plane listener registered`
  2. **Tauri 后端日志**：查 `emit_control_plane_changed project_path=... reason=notification`
- 判定方法：
  - 若后端有 `emit_control_plane_changed ... reason=notification`，但前端没有 `listener registered`，说明前端订阅没起来。
  - 若前端有 `listener registered`，后端也有 `emit_control_plane_changed`，但仍没有 `control-plane-changed`，说明问题更可能在 Tauri event 投递链。
- 验证证据：
  - `pnpm exec tsc --noEmit`
  - `cargo check --manifest-path src-tauri/Cargo.toml`

## Codex 前端 bundle / 事件注册诊断（2026-03-14）

- [x] 检查前端最早期挂载与 Tauri 事件注册点，选定最小全局日志打点
- [x] 补全局挂载/事件注册日志并给出复现观察点
- [ ] 根据结果判断是前端 bundle 未更新还是事件订阅链断裂
- [x] 更新 tasks/todo.md 记录本轮诊断

## Review（Codex 前端 bundle / 事件注册诊断）

- 当前结论：既然你前端连 `useCodexIntegration` 里最早期的 `[codex-debug]` 都看不到，下一步必须先确认“最新前端 bundle 是否真的在跑”。
- 本轮新增最前置打点：
  1. `src/App.tsx`：`AppLayout mounted` 日志，验证 React 根组件是否加载了最新 bundle。
  2. `src/platform/eventClient.ts`：Tauri runtime 下每次 `listenEvent()` 都会打印 `registering tauri listener`，验证事件订阅代码是否执行。
- 下一轮请你重启应用后先不要触发 Codex，直接打开前端控制台看是否至少出现：
  - `[codex-debug] AppLayout mounted`
  - `[codex-debug] registering tauri listener`
- 判定方法：
  - 若这两条都没有，优先说明你当前看到的前端不是最新 bundle（或 DevTools 没连到实际渲染窗口）。
  - 若这两条有，但 `useCodexIntegration` listener 相关日志没有，再继续收缩到 hook 挂载条件。
- 验证证据：
  - `pnpm exec tsc --noEmit`

## Codex 通知显示修复（2026-03-14）

- [x] 先补系统通知/Toast 可见性的失败测试或最小验证用例
- [x] 改为 Tauri 原生系统通知实现，并保留 Web fallback
- [x] 提升 Toast 可见性，确保终端工作区内明显可见
- [x] 完成验证并补 Review

## Review（Codex 通知显示修复）

- 直接原因：日志已证明 control plane notification 会到达前端，并且 `showToast()` 已被调用；真正的问题分成两层：
  1. 系统通知之前一直走浏览器 `Notification` API，在 Tauri 环境里会被权限/用户手势限制拦住；你日志里已经明确出现 `Notification prompting can only be done from a user gesture` 和 `permission: denied`。
  2. Toast 虽然已触发，但原样式是底部居中的轻量胶囊，和终端工作区重叠时不够醒目，导致主观上像“没出现”。
- 设计层诱因：桌面应用场景里仍复用了浏览器通知能力，而没有优先走 Tauri/native 路径；同时全局 Toast 在终端场景下缺少足够强的视觉层级。这属于“运行环境能力选择不匹配 + 反馈可见性不足”。除此之外，未发现新的系统设计缺陷。
- 当前修复方案：
  1. Rust 侧 `src-tauri/src/system.rs` 新增 `send_system_notification`，在 macOS 通过 `osascript display notification` 发送原生系统通知；并补了 AppleScript 字符串转义与脚本文案测试。
  2. Tauri 命令层新增 `send_system_notification`（`src-tauri/src/lib.rs` / `src-tauri/src/command_catalog.rs`），前端 `src/services/system.ts` 在 Tauri runtime 下优先走该命令，仅在失败时回退浏览器 `Notification` API。
  3. `src/App.tsx` 把全局 Toast 调整为右上角高对比卡片（更高 z-index、阴影、白字、明显边框），避免在终端工作区中不易察觉。
- 长期改进建议：
  1. 后续若要支持 Windows/Linux，可继续在 `src-tauri/src/system.rs` 按平台实现原生通知，而不是依赖浏览器 API。
  2. 全局通知可以进一步统一成“控制面通知中心 + Toast + 原生系统通知”三层策略，并允许用户配置等级映射。
  3. 当前排障用 `[codex-debug]` 日志仍保留，等你确认行为恢复后可以再收敛清理一轮。
- 验证证据：
  - `cargo test system::tests --manifest-path src-tauri/Cargo.toml`
  - `pnpm exec tsc --noEmit`
  - `cargo check --manifest-path src-tauri/Cargo.toml`

## Codex task-error 误判根因排查（2026-03-14）

- [x] 检查 monitor 的 error 判定分支并设计最小诊断
- [x] 补失败测试与诊断日志，锁定哪条规则产生 task-error
- [x] 实现最小修复并验证
- [x] 更新 Review 与证据

## Review（Codex task-error 误判根因排查）

- 直接原因：通过回放你日志里的真实 session `rollout-2026-03-14T13-19-49-019ceac9-5873-76d2-843d-6dc28eab201e.jsonl` 可以看出，会话本身其实只有 `task_started -> user_message -> agent_reasoning -> agent_message -> task_complete`，并没有真实失败事件；之所以前端 earlier 收到 `task-error`，是因为 `parse_session_file()` 会把首行 `session_meta` 也送进 `process_entry()`，而旧逻辑把所有未知顶层 type 都交给 `entry_indicates_error()` 做关键字扫描。`session_meta.payload.base_instructions / 用户上下文` 里天然可能包含 `error` / `failed` 等英文单词，于是会把 `last_error_ts` 提前打上；后续 `agent_reasoning` 又把 details 改成 `运行中`，最终就形成了你看到的“event.type = task-error，但 details = 运行中”的矛盾组合。
- 设计层诱因：monitor 之前把**元数据记录**（`session_meta`）和**运行态记录**放在同一条启发式错误判定链里，没有把“仅用于描述上下文的静态记录”与“真正代表运行结果的事件记录”隔离开。这属于状态判定边界不清。除此之外，未发现新的系统设计缺陷。
- 当前修复方案：
  1. `src-tauri/src/codex_monitor.rs::process_entry()` 现在显式忽略顶层 `session_meta`，不再对它做错误关键字扫描。
  2. 新增回归测试 `parse_session_file_ignores_error_keywords_inside_session_meta`，覆盖“session_meta 文本里即使出现 error/failed，也不能把会话判成 Error；运行中仍应保持 Working + 运行中 details”这个场景。
- 长期改进建议：
  1. 后续可继续把 `task_started` 等纯元数据/生命周期记录也显式分类处理，避免再落入 unknown fallback。
  2. monitor 的未知分支最好逐步从“全文关键字扫描”收敛成“只对白名单字段/结构做判定”，减少被提示词、上下文文案误伤。
  3. 等 wrapper 全量接管后，monitor 继续收缩为恢复/发现层，降低启发式推断权重。
- 验证证据：
  - `cargo test parse_session_file_ignores_error_keywords_inside_session_meta --manifest-path src-tauri/Cargo.toml`
  - `cargo test codex_monitor --manifest-path src-tauri/Cargo.toml`
  - `cargo check --manifest-path src-tauri/Cargo.toml`

## Codex 文件扫描收口（2026-03-14）

- [x] 定位 Codex 文件频繁扫描的直接触发链路，并确认 adapter/control plane 已覆盖的状态来源
- [x] 先补回归测试，覆盖“终端工作区不再自动启用 Codex 文件监控”与“终端 Codex 运行态可由 control plane 派生”
- [x] 按最少修改原则收口自动启用链路，并把终端 Codex 状态改走 control plane
- [x] 运行定向验证、更新文档，并追加 Review 结论

## Review（Codex 文件扫描收口）

- 直接原因：`src/App.tsx` 里 `resolveCodexMonitorEnabled` 只要检测到 `terminal.showTerminalWorkspace=true` 就会启用 `useCodexMonitor`；而 `useCodexMonitor` 一旦启用就会立即调用 `get_codex_monitor_snapshot`，该命令在 `src-tauri/src/lib.rs` 中会先执行 `codex_monitor::ensure_monitoring_started`，从而拉起 `src-tauri/src/codex_monitor.rs` 的目录 watcher 与进程轮询线程，并持续扫描 `~/.codex/sessions`。
- 设计层诱因：存在**状态真相源分裂**。终端区“Codex 是否在运行”本来已经可以由 adapter 写入的 control plane 直接投影，但此前 UI 仍同时依赖 monitor 文件扫描产出的 `codexProjectStatusById`，导致“进入终端工作区”这种纯 UI 行为误触发了后台文件扫描链路。
- 当前修复方案：1）把 `src/utils/codexMonitorActivation.ts` 收口为**仅手动启用侧栏会话区时才开启 monitor**；2）给 `src/utils/controlPlaneProjection.ts` 新增 `countRunningProviderSessions`，让 `src/components/terminal/TerminalWorkspaceWindow.tsx` 的项目/worktree/终端头部 Codex 运行态全部直接从 control plane 中按 provider=`codex` 派生，不再依赖 monitor 文件扫描。
- 长期改进建议：如果后续确定 adapter/control plane 已覆盖侧栏“CLI 会话”所需信息，可以继续把 `useCodexIntegration` 里仅服务于 monitor 的聚合逻辑逐步迁出或降级为兼容层，最终让 `src-tauri/src/codex_monitor.rs` 只保留显式调试/兼容入口，而不是常态状态源。
- 验证证据：`node --test src/utils/codexMonitorActivation.test.mjs src/utils/controlPlaneProjection.test.mjs`、`pnpm exec tsc --noEmit`、`pnpm build`。

## Codex monitor 全链路移除（2026-03-14）

- [x] 补删除导向的回归测试，并锁定需要移除的前后端入口
- [x] 清理前端 Codex monitor 入口、Sidebar 会话区块及相关类型/helper
- [x] 删除 Rust 侧 codex_monitor 模块、命令注册与监控模型，并同步 AGENTS 文档
- [x] 运行定向测试、类型检查、构建与 Rust 校验，追加 Review 结论

## Review（Codex monitor 全链路移除）

- 直接原因：即使上一轮已经把“进入终端工作区自动启用 monitor”收口掉，仓库里仍保留完整的 `Codex monitor -> App -> Sidebar -> Rust codex_monitor.rs` 兼容链路；这会继续制造两套状态心智，并让未来任何人都有机会再次把 `~/.codex/sessions` 扫描接回主路径。
- 设计层诱因：存在明显的**兼容路径滞留**问题。系统主路径已经切到 adapter/control plane，但 monitor 的前端 hook、会话视图、Rust 命令、模型和依赖仍完整留存，属于职责边界没有彻底收口；除此之外，未发现新的系统设计缺陷。
- 当前修复方案：
  1. 前端删除 `useCodexMonitor`、`src/services/codex.ts`、`src/components/CodexSessionSection.tsx`、`src/utils/codexMonitorActivation.ts`、`src/models/codex.ts`、`src/utils/codexControlPlaneBridge.ts`，`Sidebar` 不再展示基于文件扫描的 CLI 会话区块。
  2. `src/hooks/useCodexIntegration.ts` 已收口为**仅监听 control plane 中的 Codex 通知**，不再桥接 monitor 事件，也不再维护 monitor session 到 project 的映射。
  3. Rust 侧删除 `src-tauri/src/codex_monitor.rs`、`get_codex_monitor_snapshot` 命令、`command_catalog` 对应 Web 入口以及只服务 monitor 的模型；`Cargo.toml` 同步移除 `notify` / `sysinfo` 依赖。
  4. 终端区的 Codex 运行态继续直接走 `src/utils/controlPlaneProjection.ts::countRunningProviderSessions`，不回退到 monitor。
- 长期改进建议：如果未来需要“应用重启后恢复 agent 会话列表”这类能力，应该在 control plane / agent registry 层补持久化或快照恢复，而不是重新引入 `~/.codex/sessions` 轮询。
- 验证证据：
  - `node --test src/utils/controlPlaneProjection.test.mjs`
  - `cargo test command_catalog_keeps_web_subset_of_tauri --manifest-path src-tauri/Cargo.toml`
  - `pnpm exec tsc --noEmit`
  - `pnpm build`
  - `cargo check --manifest-path src-tauri/Cargo.toml`

## Agent 包装通知 / 运行态可见性修复方案（2026-03-14）

- [x] 继续收口交互式主路径为 cmux 风格单线模型，前端不再暴露显式命令面接口
- [x] 建立隔离 worktree 并完成基线检查（`~/.config/superpowers/worktrees/DevHaven/agent-runtime-control-plane`）
- [x] 用户确认 Codex/Claude 都要做透明 wrapper，且 Codex 必须保持交互式主路径
- [x] 完成第一批实现基础：Task 1、Task 2 已落地，Task 3 已补 Codex/Claude wrapper、scripts/bin shim、terminal PATH/env 注入基础链路
- [x] 修复 zsh login shell 在用户 `.zshenv/.zprofile/.zshrc/.zlogin` 覆盖 PATH 后，wrapper bin 不能保持首位的问题
- [x] 用户已选择 Parallel Session（单独会话按 implementation plan 执行）
- [x] 写设计稿 `docs/plans/2026-03-14-devhaven-agent-runtime-control-plane-design.md`
- [x] 写实施计划 `docs/plans/2026-03-14-devhaven-agent-runtime-control-plane-implementation.md`
- [x] 读取当前 agent 包装、control plane、通知消费链路与最近变更
- [x] 复现并定位“无通知 / 无法判断 Codex 是否在运行”的直接原因
- [x] 评估 monitor 删除后的影响，给出 2-3 个可行修复方案与推荐方案
- [x] 在获批方案内完成最小实现、文档同步与任务记录更新
- [x] 运行验证并补充 Review 证据

## Review（Agent 包装通知 / 运行态可见性修复方案）

- 直接原因：透明 wrapper 本体和 control plane 通知链路都能工作，但 DevHaven login shell 启动后，用户 `.zshenv/.zprofile/.zshrc/.zlogin` 会重建 PATH，把 `scripts/bin` 顶掉，导致 `codex` / `claude` 最终命中系统原始二进制，而不是 shim。
- 设计层诱因：交互式主路径和显式命令面曾同时出现在实现与文档心智中，容易让维护者误以为 `agent_spawn` 也是交互式 Claude/Codex 的主入口；同时 PATH 真相最初放在 `terminal.rs` 启动前注入层，离 shell 最终态太远。
- 当前修复方案：
  1. 保留 control plane 真相层与后端显式命令面，但将交互式 Claude/Codex 主路径明确收口为 `shell integration -> scripts/bin shim -> provider wrapper -> hook/notify -> control plane`。
  2. 新增/完善 `scripts/bin/{codex,claude}`、`scripts/devhaven-{codex,claude}-wrapper.mjs`、`scripts/devhaven-{codex,claude}-hook.mjs`，让终端内直接输入 provider 命令即可进入受管运行时。
  3. 新增 `scripts/shell-integration/*`，并在 zsh/bash 启动后重新夺回 PATH 首位，确保 `DEVHAVEN_WRAPPER_BIN_PATH` 永远排在第一位。
  4. 从前端移除未使用的 `agentSpawn/agentStop/agentRuntimeDiagnose` 接口和类型，避免继续污染交互式主路径心智；显式命令面保留在后端工具层。
- 本轮本地 code review 结论：
  1. 已修正一个重要逻辑问题：`devhaven-codex-hook.mjs` 里 `task_complete` 原先被错误映射为 `waiting`，现已改为 `completed`，避免完成态看起来像“还在等待输入”。
  2. 已继续收口 `terminal.rs` 中 shell integration helper 的职责，删除未使用参数，使“注入上下文”和“shell 最终态收口”边界更清晰。
  3. 当前未再发现必须立刻修复的 Critical 问题；后续若继续对齐商业化 cmux，可再弱化 `agent_launcher` 在交互式路径中的存在感，并补一条“新 terminal 启动后 which codex/claude 命中 shim”的自动化回归测试。
- 长期改进建议：
  1. 继续让交互式 provider 只保留单线主路径，后端 `agent_spawn/stop/diagnose` 明确限定为显式命令面/诊断工具。
  2. 补一条真正的运行时回归测试：新 terminal 启动后 `which codex` / `which claude` 必须命中 shim。
  3. 后续若需要全局 Agent 状态卡，再基于现有 control plane projection 增量实现，不要重新引入第二套状态源。
- 验证证据：
  - `node --test scripts/devhaven-shell-integration.test.mjs scripts/devhaven-control.test.mjs`
  - `pnpm exec tsc --noEmit`
  - `cargo test apply_terminal_shell_integration_env_sets_zdotdir_wrapper --manifest-path src-tauri/Cargo.toml`
  - `cargo test apply_terminal_shell_integration_env_sets_bash_prompt_bootstrap --manifest-path src-tauri/Cargo.toml`
  - `cargo test apply_terminal_control_env_includes_http_command_endpoint --manifest-path src-tauri/Cargo.toml`
  - `cargo check --manifest-path src-tauri/Cargo.toml`



## Codex 增强逻辑与 cmux 差异分析（2026-03-14）

- [x] 读取技能与当前仓库约束，建立分析计划
- [x] 在 DevHaven 侧定位 Codex 增强逻辑主入口与关键数据流
- [x] 在 cmux 侧定位对应实现与关键数据流
- [x] 对照两边差异，提炼直接原因、设计层差异与建议
- [x] 在本文件追加 Review，记录证据与结论

## Review（Codex 增强逻辑与 cmux 差异分析）

- 结论：**你现在的 DevHaven Codex 增强链路，和 cmux 不是“同一套逻辑换皮”，而是只在“终端注入环境变量 + wrapper/hook + 通知/attention UI”这一层方向相近；核心状态模型、hook 粒度、通知闭环和 provider 抽象层次都明显不同。**
- 最关键差异 1：cmux 仓库里实际上**没有 Codex 专用适配器**；`Resources/bin/` 只有 `claude` / `open`，`rg -ni "codex"` 只命中 `README.md` 叙述。也就是说，cmux 当前落地的是“通用通知/状态 primitive + Claude 适配器”，不是“Codex 专用主线”。
- 最关键差异 2：DevHaven Codex 现在是**provider-specific wrapper → control plane command**。入口在 `scripts/devhaven-codex-wrapper.mjs` / `scripts/devhaven-codex-hook.mjs`，由 `src-tauri/src/terminal.rs` 注入 `DEVHAVEN_*` 环境和 wrapper 路径，再通过 `scripts/devhaven-agent-hook.mjs` 调 `devhaven_notify` / `devhaven_agent_session_event` 落到 `src-tauri/src/agent_control.rs` 的 registry。
- 最关键差异 3：cmux 的 Claude 适配是**wrapper → cmux CLI/socket primitive**。`Resources/bin/claude` 注入 `SessionStart/Stop/SessionEnd/Notification/UserPromptSubmit/PreToolUse` 六类 hooks，`CLI/cmux.swift` 再把这些 hook 翻译成 `notify_target`、`set_status`、`clear_status`、`set_agent_pid` 等通用命令，最终落到 `TerminalNotificationStore` / `Workspace.statusEntries` / `agentPIDs`。
- 最关键差异 4：DevHaven Codex hook 粒度明显更粗。当前只有：启动时 `running`、退出时 `stopped/failed`、notify 时 `waiting/completed/failed`；而 cmux Claude 还区分 `prompt-submit`（清通知并回 Running）、`pre-tool-use`（工具恢复时清 Needs input）、`session-end`（兜底清理 PID/状态/通知）。这就是你现在看到“逻辑不像 cmux”的直接原因。
- 最关键差异 5：通知模型也不一样。DevHaven `push_notification()` 是**纯追加记录**，再由前端 `TerminalWorkspaceView.tsx` 主动 mark read、`useCodexIntegration.ts` 再把新通知转成 toast / 系统通知；cmux `TerminalNotificationStore.addNotification()` 会按 tab+surface 去重、在当前聚焦面板时抑制系统通知、维护 unread index，并在 `TabManager` 焦点切换时自动已读。
- 设计层差异：DevHaven 目前仍有一部分“agent 增强行为在前端收尾”的特点（例如 toast 转发、auto-read），cmux 则把 unread / focus / notification delivery 主逻辑放在原生核心层。换句话说，DevHaven 更像“control plane + 前端 projection”，cmux 更像“native primitive + agent adapter”。
- 建议：如果你要追到更像 cmux 的感觉，重点不是再堆 Codex 特判，而是继续把 DevHaven 收口成 **provider-neutral primitive**：至少补齐 `set_status / clear_status / notify_target / set_agent_pid` 这类中间层语义，再让 Codex/Claude wrapper 只负责把各自 hook 翻译成这些 primitive；同时把“已读/聚焦抑制/去重”从前端 effect 下沉到 Rust control plane/runtime。
- 证据：本次仅做源码比对，未改业务实现；核对了 `scripts/devhaven-codex-wrapper.mjs`、`scripts/devhaven-codex-hook.mjs`、`scripts/devhaven-agent-hook.mjs`、`src-tauri/src/agent_control.rs`、`src-tauri/src/terminal.rs`、`src/hooks/useCodexIntegration.ts`，以及 cmux 的 `README.md`、`Resources/bin/claude`、`CLI/cmux.swift`、`Sources/GhosttyTerminalView.swift`、`Sources/TerminalNotificationStore.swift`、`Sources/Workspace.swift`、`Sources/TabManager.swift`。


## DevHaven / cmux 数据流对照图输出（2026-03-14）

- [x] 复用上一轮源码比对结果，提炼对照维度
- [x] 输出 DevHaven 数据流图
- [x] 输出 cmux 数据流图
- [x] 总结关键分叉点与迁移方向


## Review（DevHaven / cmux 数据流对照图输出）

- 已基于上一轮源码核对，补充 DevHaven 与 cmux 的数据流对照图，重点标出 wrapper/hook、状态真相源、通知闭环与 UI attention 的落点差异。
- 结论再次确认：cmux 当前仓库没有 Codex 专用适配主线，实际落地的是 Claude wrapper + CLI primitive；DevHaven 当前则是 Codex wrapper + control plane registry + React projection。
- 本轮为分析输出，无代码改动、无构建验证；证据来自已核对源码文件：`/Users/zhaotianzeng/WebstormProjects/DevHaven/scripts/devhaven-codex-wrapper.mjs`、`/Users/zhaotianzeng/WebstormProjects/DevHaven/scripts/devhaven-codex-hook.mjs`、`/Users/zhaotianzeng/WebstormProjects/DevHaven/src-tauri/src/agent_control.rs`、`/Users/zhaotianzeng/Documents/business/tianzeng/cmux/Resources/bin/claude`、`/Users/zhaotianzeng/Documents/business/tianzeng/cmux/CLI/cmux.swift`、`/Users/zhaotianzeng/Documents/business/tianzeng/cmux/Sources/TerminalNotificationStore.swift` 等。


## 终端内容 / 历史输入缺失排查（2026-03-15）

- [x] 记录用户反馈并建立本轮排查 checklist
- [x] 梳理 DevHaven 终端启动、shell integration 与历史文件链路
- [x] 对照 cmux shell integration / terminal 启动链路找出关键差异
- [x] 定位“终端内容不见、历史输入没来”的直接原因与设计层诱因
- [x] 给出最小修复方向与验证建议

## Review（终端内容 / 历史输入缺失排查）

- 直接原因已定位为 **DevHaven 的 zsh shell integration 把 ZDOTDIR 恢复回集成目录，并试图用 env 覆盖 HISTFILE**，结果 zsh 启动过程仍按集成目录解析历史文件；实际复现输出为 `scripts/shell-integration/zsh/.zsh_history`，不是用户 HOME 下的 `.zsh_history`。这会让命令历史、zsh-autosuggestions、基于共享历史的提示全部失效，看起来像“历史输入没来 / 终端内容不见了”。
- 证据 1：`src-tauri/src/terminal.rs:310-315`（2026-03-14 提交 `768f6ad`）显式注入 `HISTFILE` / `ZSH_COMPDUMP` 到 `~/.devhaven/shell-state/zsh`；`scripts/shell-integration/zsh/.zshenv` 又会在 source 用户 `.zshenv` 后把 `ZDOTDIR` 改回集成目录。
- 证据 2：本地对照执行 `zsh -ic 'print -r -- "$ZDOTDIR|$HISTFILE"'`，DevHaven 集成输出为 `.../scripts/shell-integration/zsh|.../scripts/shell-integration/zsh/.zsh_history`，而 cmux 集成输出为 `<临时 HOME>|<临时 HOME>/.zsh_history`。
- 设计层诱因：为了稳定 wrapper PATH/compdump，把“shell integration 注入”和“shell 状态目录隔离”耦合在一起，导致终端增强侵入了用户 shell 的真实状态源（ZDOTDIR/HISTFILE），这是状态源被错误替换的问题。
- 最小修复方向：参考 cmux，把 zsh wrapper 改成**在 `.zshenv` 里尽早恢复真实 ZDOTDIR，并保留用户 HISTFILE 语义**；不要再为 zsh 强制写 `HISTFILE`/`ZSH_COMPDUMP` 到 `.devhaven`。同时补一条回归测试，断言 DevHaven 注入后 `HISTFILE` 最终落在用户 HOME/ZDOTDIR，而不是集成目录或 `.devhaven/shell-state`。
- 本轮为根因排查，未修改业务代码；验证证据为源码核对 + 本地 `zsh -ic 'print -r -- "$ZDOTDIR|$HISTFILE"'` 对照执行输出。


## 终端增强完整整改方案设计（2026-03-15）

- [x] 汇总历史缺失问题的根因、受影响链路与设计诱因
- [x] 提出 2-3 套整改路线并给出推荐方案
- [x] 输出分阶段完整整改设计（架构、边界、迁移顺序、回滚）
- [x] 待用户确认后落盘设计稿与实施计划

## 终端增强 C 方案（primitive-first）设计与计划（2026-03-15）

- [x] 写入 primitive-first 完整改造设计稿
- [x] 写入分阶段实施计划（测试先行）
- [x] 同步 tasks/todo.md Review 记录设计证据

## Review（终端增强 C 方案（primitive-first）设计与计划）

- 已按用户指定的 C 方案，将“终端增强完整整改”正式落盘为两份文档：`/Users/zhaotianzeng/WebstormProjects/DevHaven/docs/plans/2026-03-15-terminal-enhancement-primitive-first-design.md` 与 `/Users/zhaotianzeng/WebstormProjects/DevHaven/docs/plans/2026-03-15-terminal-enhancement-primitive-first-implementation.md`。
- 设计稿明确把整改拆成五层边界：terminal launcher、shell bootstrap、wrapper/hook adapter、primitive/control plane、前端 projection，并把当前历史缺失问题归因为 shell integration 接管了用户状态源。
- 实施计划按 TDD 拆成 7 个任务：先补 shell 语义回归测试，再恢复 zsh 原生语义、重构 bootstrap、引入 provider-neutral primitive、迁移 wrapper、下沉 lifecycle，最后做 AGENTS/文档与整体验证。
- 本轮仅输出设计与计划，未执行代码改动；证据为已写入的两份设计/实施文档与 `tasks/todo.md` 更新记录。


## 终端增强 C 方案执行（2026-03-15）

- [x] Task 1：补 shell 语义回归测试并确认当前失败
- [x] Task 2：修复 zsh shell bootstrap，恢复用户真实状态源
- [x] Task 3：重构 shell bootstrap 结构
- [x] Task 4：引入 provider-neutral primitive
- [x] Task 5：迁移 Codex / Claude wrapper 到 primitive adapter
- [x] Task 6：下沉 unread / focus / attention 生命周期
- [x] Task 7：文档、AGENTS 与整体验证

## Review（Task 2：修复 zsh shell bootstrap，恢复用户真实状态源）

- 直接原因：DevHaven zsh integration 在 source 用户启动文件后仍把 `ZDOTDIR` 收回到 integration 目录，并在 Rust 侧强制注入 zsh `HISTFILE/ZSH_COMPDUMP`，导致最终历史路径落到 `scripts/shell-integration/zsh/.zsh_history`。
- 设计层诱因：shell bootstrap 与用户 shell 状态源耦合，`wrapper PATH` 与 `ZDOTDIR/HISTFILE` 被一并管理，属于状态源分裂问题。
- 当前修复方案：`src-tauri/src/terminal.rs` 移除 zsh `HISTFILE/ZSH_COMPDUMP` 注入；重写 zsh bootstrap 为“source 用户文件时临时切到用户 ZDOTDIR，兼容 wrapper 注入后再 finalize 到用户语义”；删除仓库误入的 `scripts/shell-integration/zsh/.zsh_history`。
- 长期改进建议：在 Task 3 继续把 zsh/bash bootstrap 抽成更清晰分层，避免再依赖启动时隐藏副作用维持 PATH/HISTFILE 行为。
- 验证证据：
  - `node --test scripts/devhaven-shell-integration.test.mjs scripts/devhaven-zsh-histfile-regression.test.mjs scripts/devhaven-zsh-stacked-zdotdir.test.mjs scripts/devhaven-bash-history-semantics.test.mjs`（4/4 通过）
  - `cargo test apply_terminal_shell_integration_env_sets_zdotdir_wrapper --manifest-path src-tauri/Cargo.toml`（通过）


## Review（终端增强 C 方案 Task 1-2 阶段结果）

- 已完成 Task 1/2：先补 shell 语义回归测试，再修复 zsh shell bootstrap，恢复用户真实 `ZDOTDIR/HISTFILE` 语义。
- 直接原因：`src-tauri/src/terminal.rs` 为 zsh 强制注入 `HISTFILE/ZSH_COMPDUMP`，同时 `scripts/shell-integration/zsh/.zshenv` 在 source 用户配置后把 `ZDOTDIR` 拉回集成目录，导致历史文件落到 integration 目录。
- 设计层诱因：launcher、shell bootstrap、wrapper 注入、用户 shell 状态源职责耦合，存在明显状态源分裂；不是单一实现细节问题。
- 当前修复方案：
  1. zsh 启动链不再强制注入 `HISTFILE` / `ZSH_COMPDUMP`；
  2. `.zshenv/.zprofile/.zshrc/.zlogin` 改为在 source 用户文件时临时切换到用户真实 `ZDOTDIR`；
  3. 非 login shell 在 `.zshrc`、login shell 在 `.zlogin` 完成最终 shell state finalize；
  4. 删除误入仓库的 `scripts/shell-integration/zsh/.zsh_history`。
- 长期改进建议：继续按 primitive-first 方案推进 Task 3+，把 shell bootstrap 与 provider wrapper 完全分层，并把更多 lifecycle 语义下沉到 primitive/control plane。
- 验证证据：
  - `node --test scripts/devhaven-shell-integration.test.mjs scripts/devhaven-zsh-histfile-regression.test.mjs scripts/devhaven-zsh-stacked-zdotdir.test.mjs scripts/devhaven-bash-history-semantics.test.mjs` → 4 passed, 0 failed
  - `cargo test apply_terminal_shell_integration_env_sets_zdotdir_wrapper --manifest-path src-tauri/Cargo.toml` → 1 passed, 0 failed
  - 手工对照：`zsh -ic 'print -r -- "$ZDOTDIR|$HISTFILE"'` 输出用户 HOME 与 `HOME/.zsh_history`


## Review（终端增强 C 方案 Task 1-2）

- Task 1 已补齐 shell 语义回归测试：新增 `scripts/devhaven-zsh-histfile-regression.test.mjs`、`scripts/devhaven-zsh-stacked-zdotdir.test.mjs`、`scripts/devhaven-bash-history-semantics.test.mjs`，并确认当前实现下 zsh 两条回归稳定失败、bash 边界测试通过。
- Task 2 已恢复 zsh 用户状态源语义：`src-tauri/src/terminal.rs` 不再为 zsh 强制注入 `HISTFILE` / `ZSH_COMPDUMP`；zsh integration 改为优先 source 用户真实 `ZDOTDIR` 下的启动文件，并在 bootstrap 后归还用户 `ZDOTDIR/HISTFILE` 语义，同时保留 wrapper PATH 注入。
- 本阶段验证证据：
  - `node --test scripts/devhaven-shell-integration.test.mjs scripts/devhaven-zsh-histfile-regression.test.mjs scripts/devhaven-zsh-stacked-zdotdir.test.mjs scripts/devhaven-bash-history-semantics.test.mjs`
  - `cargo test apply_terminal_shell_integration_env_sets_zdotdir_wrapper --manifest-path src-tauri/Cargo.toml`
- 评审结果：Task 1 与 Task 2 均完成实现者自检 + 规格审查 + 代码质量审查，当前无阻塞问题，可继续推进 Task 3。


## Review（Task 3：重构 shell bootstrap 结构）

- 直接原因：Task 2 已恢复 zsh 历史语义，但 shell bootstrap 仍散落在 `.zshrc/.zlogin` 与长字符串 `PROMPT_COMMAND` 里，后续继续改 provider / integration 时仍容易再次耦合职责。
- 设计层诱因：shell integration 文件职责过散，`PROMPT_COMMAND` 里内联 bootstrap 逻辑、zsh 侧直接 source `devhaven-wrapper-path.sh`，都让“注入能力”和“启动时序”难以单独演进。
- 当前修复方案：
  1. 新增 `scripts/shell-integration/bash/devhaven-bash-bootstrap.sh`，把 bash prompt bootstrap 逻辑抽到独立文件；
  2. 新增 `scripts/shell-integration/zsh/devhaven-zsh-bootstrap.zsh`，把 zsh wrapper-path/finalize 收口到独立 primitive；
  3. `src-tauri/src/terminal.rs` 的 bash `PROMPT_COMMAND` 改为只 source bootstrap 文件，不再内联多职责字符串；
  4. `scripts/shell-integration/devhaven-bash-integration.sh` 改为兼容 shim，优先转调新 bootstrap。
- 长期改进建议：Task 4 开始继续把 provider wrapper 事件翻译与 shell bootstrap 分离，避免 bootstrap 文件再次承载 provider-specific 语义。
- 验证证据：
  - `node --test scripts/devhaven-shell-integration.test.mjs scripts/devhaven-bash-history-semantics.test.mjs scripts/devhaven-zsh-histfile-regression.test.mjs`（4/4 通过）
  - `cargo test apply_terminal_shell_integration_env_sets_bash_prompt_bootstrap --manifest-path src-tauri/Cargo.toml`（通过）
  - `cargo test apply_terminal_shell_integration_env_sets_zdotdir_wrapper --manifest-path src-tauri/Cargo.toml`（通过）


## Review（Task 4：引入 provider-neutral primitive）

- 直接原因：当前 control plane 只有 `notify` / `agent_session_event` 两条 provider-specific 写入主线，缺少 provider-neutral primitive，中间层无法承接后续 wrapper 迁移。
- 设计层诱因：provider wrapper 直接写 control plane 记录，导致后续想对齐 cmux 风格的 `notify_target / set_status / set_agent_pid` 时没有稳定契约层，wrapper 与 durable truth 耦合过紧。
- 当前修复方案：
  1. Rust 侧新增并注册 `devhaven_notify_target`、`devhaven_set_status` / `devhaven_clear_status`、`devhaven_set_agent_pid` / `devhaven_clear_agent_pid`；
  2. `agent_control.rs` 的 durable file / tree 新增 `statuses`、`agent_pids` 记录；
  3. TS 侧新增 `src/models/terminalPrimitives.ts`、`src/utils/terminalPrimitiveProjection.ts`，提供按 key 取最新 primitive 记录的最小 projection；
  4. `src/services/controlPlane.ts` 暴露对应 primitive 调用函数，为 Task 5 wrapper 迁移提供稳定接口。
- 长期改进建议：Task 5/6 继续把 wrapper 事件翻译和 unread/focus lifecycle 下沉到这些 primitive，逐步削弱 provider-specific 写 control plane 的旧路径。
- 验证证据：
  - `cargo test agent_control --manifest-path src-tauri/Cargo.toml`（6 passed）
  - `cargo test command_catalog --manifest-path src-tauri/Cargo.toml`（3 passed）
  - `node --test src/utils/terminalPrimitiveProjection.test.mjs`（3 passed）
  - Task 4 已完成规格审查 + 代码质量审查。


## Review（Task 5：迁移 Codex / Claude wrapper 到 primitive adapter）

- 直接原因：即使 Task 4 已补齐 primitive 命令，Codex / Claude wrapper 仍直接写 legacy `devhaven_notify` / `devhaven_agent_session_event`，没有真正走到新中间层，Task 4 的 primitive 契约还无法承接真实 provider 流量。
- 设计层诱因：wrapper/hook 一直把 provider 生命周期直接编码到 control plane 写入路径里，导致 primitive 层存在但未被主路径使用，中间层继续名存实亡。
- 当前修复方案：
  1. `scripts/devhaven-agent-hook.mjs` 新增 `sendTargetedNotification`、`sendStatusPrimitive`、`clearStatusPrimitive`、`sendAgentPidPrimitive`、`clearAgentPidPrimitive` primitive adapter；
  2. `scripts/devhaven-codex-wrapper.mjs` / `scripts/devhaven-codex-hook.mjs` 迁到 adapter：启动/退出同步状态与 pid primitive，notify 同步 `notify_target + set_status`；
  3. `scripts/devhaven-claude-wrapper.mjs` / `scripts/devhaven-claude-hook.mjs` 迁到 adapter：wrapper 负责 pid primitive，hook 负责 running/waiting/stopped 等状态 primitive；
  4. 保留 legacy `sendAgentNotification` / `sendAgentSessionEvent` 兼容路径，确保 Task 6 前现有 UI 语义不丢失。
- 长期改进建议：Task 6 继续把 unread / focus / attention 主逻辑下沉到 primitive lifecycle，届时可以开始削弱 legacy control plane 双写。
- 验证证据：
  - `node --test scripts/devhaven-control.test.mjs`（15 passed）
  - Task 5 已完成规格审查 + 代码质量审查，review 结论确认 wrapper/hook 对 primitive 调用仍是 best-effort，不会阻塞真实 agent 启动/退出。


## Review（Task 6：下沉 unread / focus / attention 生命周期）

- 直接原因：Task 5 后 wrapper 已经开始写 primitive，但前端 attention / Codex 通知识别仍优先绑死在 legacy `agentSession/provider` 上，primitive 状态无法真正参与 workspace / pane lifecycle。
- 设计层诱因：UI projection 与 provider-specific session 路径长期绑定，导致即使后端已有 primitive 契约，前端仍把它当旁路数据，无法支撑后续削弱 legacy 双写。
- 当前修复方案：
  1. `src/utils/controlPlaneProjection.ts` 新增 primitive fallback：当 surface/workspace 没有 `agentSession` 时，可用 `statuses` 推导 waiting/running/failed/completed attention 与 lastMessage；
  2. `src/hooks/useCodexIntegration.ts` 的 Codex 判定不再只依赖 `agentSession.provider`，也识别 `statuses/agentPids`；
  3. `src/components/terminal/TerminalWorkspaceView.tsx` 的 surface projection 改为把完整 `controlPlaneTree` 传入，确保 pane 级 primitive 状态可见；
  4. 新增 `src/utils/controlPlaneLifecycle.test.mjs`，锁定 primitive lifecycle fallback 行为。
- 长期改进建议：Task 7 后可继续评估何时移除 legacy `agentSession` 双写，把 unread / auto-read / toast 进一步下沉到 primitive 主线。
- 验证证据：
  - `~/.nvm/versions/node/v22.22.0/bin/node --test src/utils/controlPlaneLifecycle.test.mjs src/utils/controlPlaneProjection.test.mjs`（8/8 通过）
  - Task 6 已完成规格审查 + 代码质量审查。


## Review（Task 7：文档、AGENTS 与整体验证）

- 已同步文档与约束：`AGENTS.md` 增补 shell bootstrap 分层边界与 provider-neutral primitive 层说明；`tasks/todo.md` 持续记录了 Task 1-7 的执行与证据。
- 最终阻塞问题已修复：Codex / Claude hook 通知路径不再对 `sendTargetedNotification` 与 legacy `sendAgentNotification` 双写，避免重复通知 / 重复未读。
- 本轮最终验证证据：
  - `export PATH="$HOME/.nvm/versions/node/v22.22.0/bin:$PATH"; node --test scripts/devhaven-control.test.mjs scripts/devhaven-shell-integration.test.mjs scripts/devhaven-zsh-histfile-regression.test.mjs scripts/devhaven-zsh-stacked-zdotdir.test.mjs scripts/devhaven-bash-history-semantics.test.mjs src/utils/terminalPrimitiveProjection.test.mjs src/utils/controlPlaneLifecycle.test.mjs src/utils/controlPlaneProjection.test.mjs`（32 passed）
  - `cargo test agent_control --manifest-path src-tauri/Cargo.toml && cargo test command_catalog --manifest-path src-tauri/Cargo.toml && cargo test terminal_ --manifest-path src-tauri/Cargo.toml && cargo check --manifest-path src-tauri/Cargo.toml`（全部通过）
  - `export PATH="$HOME/.nvm/versions/node/v22.22.0/bin:$PATH"; "$HOME/.nvm/versions/node/v22.22.0/bin/pnpm" exec tsc --noEmit && "$HOME/.nvm/versions/node/v22.22.0/bin/pnpm" build`（通过）
- 最终审查结论：阻塞项已清除，可以进入收尾。


## Codex 版本错配排查（2026-03-15）

- [x] 确认宿主 shell 与 DevHaven 终端中的 codex 解析路径差异
- [x] 定位旧版 codex-cli 0.97.0 的来源与命中条件
- [x] 输出根因、影响范围与修复建议

## Review（Codex 版本错配排查）

- 直接原因：`src-tauri/src/terminal.rs::resolve_terminal_agent_wrapper_paths()` 会在终端会话创建时用当时的 `PATH` 预解析 `real_codex_bin`，并注入 `DEVHAVEN_REAL_CODEX_BIN`。当前 GUI-like PATH 会命中 `/opt/homebrew/bin/codex`，它是指向 `/opt/homebrew/lib/node_modules/@openai/codex/bin/codex.js` 的 symlink；对应 `package.json` 版本是 **0.97.0**。
- 宿主 shell 中的 `codex` 则解析到 `/Applications/Codex.app/Contents/Resources/codex`，当前输出为 **codex-cli 0.115.0-alpha.11**。因此 DevHaven 终端里看到旧版，不是更新没生效，而是 wrapper 一开始就被固定到了另一套旧安装。
- 设计层诱因：wrapper 为了避免递归命中 `scripts/bin/codex`，在 session 创建时提前固化 `DEVHAVEN_REAL_CODEX_BIN`；但当前解析策略只按 PATH 首个 `codex` 命中，不会优先选择新版 Codex.app 资源，也不会比较多个候选版本。
- 当前建议：短期可删除/卸载 `/opt/homebrew/bin/codex` 对应的旧全局包，或在 DevHaven 中显式优先 `/Applications/Codex.app/Contents/Resources/codex`；长期应修改 `resolve_terminal_agent_wrapper_paths()` 的 codex 解析策略，不再盲选 PATH 首个候选。
- 证据：
  - 宿主 shell：`which -a codex` → `/Applications/Codex.app/Contents/Resources/codex`，`codex --version` → `codex-cli 0.115.0-alpha.11`
  - GUI-like PATH 复现：`resolveRealCommand(..., "codex")` → `/opt/homebrew/bin/codex`
  - `/opt/homebrew/bin/codex` -> `../lib/node_modules/@openai/codex/bin/codex.js`
  - `/opt/homebrew/lib/node_modules/@openai/codex/package.json` 版本：`0.97.0`


## Tauri bundle resource 迁移（2026-03-15）

- [x] 确认当前 scripts 模式与 build 行为漂移的根因
- [x] 为 build/resource 路径解析补失败测试
- [x] 将 wrapper / shell-integration 路径改为优先 bundle resource
- [x] 更新 tauri.conf.json 资源打包配置
- [x] 更新 AGENTS.md 并完成验证


## Review（Tauri bundle resource 迁移）

- 直接原因：DevHaven 当前通过 `src-tauri/src/terminal.rs::resolve_devhaven_script_path()` 依赖 `current_dir()` 向上找仓库 `scripts/*`，导致 dev 能命中 wrapper / shell integration，而 build 后因 cwd 不再指向仓库，代理链容易失效。
- 设计层诱因：wrapper / shell integration 资源来源仍是“仓库脚本模式”，而不是像 cmux 那样由 app bundle 统一持有；这会让 dev/build 两套路径解析逻辑天然漂移。
- 当前修复方案：
  1. `src-tauri/src/terminal.rs` 新增 resource-dir 优先解析：先从 `app.path().resource_dir()/scripts/*` 取 wrapper / hook / shell integration，再回退到仓库 `scripts/*`；
  2. `resolve_terminal_agent_wrapper_paths()` 与 `apply_terminal_shell_integration_env()` 都已接入 bundle resource 路径；
  3. `src-tauri/tauri.conf.json` 新增 `bundle.resources`，把 `scripts/bin/`、`scripts/shell-integration/` 以及 `devhaven-*.mjs` 打进 app bundle；
  4. `AGENTS.md` 已补“终端增强资源应优先来自 Tauri bundle resource，而不是依赖 cwd 猜仓库脚本”的边界说明。
- 长期改进建议：后续可继续把 real codex / claude binary 解析也从“PATH 首命中”升级为“显式 env > App bundle 指定 > 官方 app binary > PATH 回退”的优先级策略，彻底解决 build 模式下代理链与版本错配问题。
- 验证证据：
  - `cargo test resolve_devhaven_script_path_prefers_bundle_resource_dir_when_available --manifest-path src-tauri/Cargo.toml`
  - `cargo test resolve_terminal_agent_wrapper_paths_reads_bundle_resources --manifest-path src-tauri/Cargo.toml`
  - `cargo test apply_terminal_shell_integration_env_sets_zdotdir_wrapper --manifest-path src-tauri/Cargo.toml`
  - `cargo test command_catalog --manifest-path src-tauri/Cargo.toml`
  - `cargo check --manifest-path src-tauri/Cargo.toml`


## macOS 原生 Swift 重构可行性评估（2026-03-16）

- [x] 盘点当前前端/后端/平台桥接的实现规模
- [x] 识别只能通过 Tauri/Rust/Node 获得的能力与可替代方案
- [x] 评估是否适合完全重写为原生 Swift
- [x] 输出推荐迁移路线、风险与投入级别


## Review（macOS 原生 Swift 重构可行性评估）

- 结论：**可以做，但应视为“分阶段重写”，不应按“小步重构”预期成本。** 当前仓库前端约 `126` 个 TS/TSX 文件 / `26241` 行，Rust 后端约 `30` 个文件 / `17041` 行，另有 `15` 个脚本文件 / `2125` 行；`src-tauri/src/command_catalog.rs` 暴露约 `79` 个 Tauri/Web 命令对。
- 关键判断依据：
  1. UI 并非简单 CRUD，而是包含大型终端工作区、Run 面板、右侧文件/Git 侧栏、Markdown/备注/Todo、筛选/仪表盘等完整桌面工作台；
  2. 本地能力并非薄壳，Rust 侧已有 PTY、Git/worktree、控制平面、存储、Web bridge、共享脚本、交互锁等厚后端；
  3. 若改为纯 Swift/SwiftUI/AppKit，需要同时替换 React 组件层与 Rust/Tauri 命令层，尤其终端模拟器、代码编辑器、diff/Git 工作流、agent control plane 成本最高。
- 推荐路线：
  1. 若目标只是“只支持 macOS”，优先保留现有 Rust 核心，先砍掉跨平台负担；
  2. 若目标是“mac 原生体验”，优先考虑 **Swift 壳 + 复用 Rust 核心**，而不是一步到位纯 Swift 全重写；
  3. 只有在你明确接受 2~3 个大版本演进周期、且愿意重做终端/编辑器/工作区交互时，才建议推进纯 Swift 重写。
- 证据：
  - `package.json` / `src-tauri/Cargo.toml`
  - `src/platform/commandClient.ts`（Tauri invoke + Web HTTP 双桥接）
  - `src-tauri/src/web_server.rs`（浏览器运行时桥）
  - `src/components/terminal/TerminalWorkspaceView.tsx`、`src/components/terminal/TerminalPane.tsx`
  - `src-tauri/src/terminal.rs`、`src-tauri/src/agent_control.rs`、`src-tauri/src/git_ops.rs`、`src-tauri/src/worktree_init.rs`


## 后续跨平台接入能力评估（2026-03-16）

- [x] 盘点当前项目对浏览器 / 移动端接入的现有基础
- [x] 判断纯 Swift macOS 重构后是否还能对外提供跨平台调用能力
- [x] 输出推荐的目标架构与边界划分


### 评估补充（跨平台接入基础）

- 当前仓库已经具备“多客户端接入雏形”：
  1. `src/platform/commandClient.ts` 已抽象 Tauri `invoke` 与 Web HTTP `/api/cmd/:command` 双入口；
  2. `src/platform/eventClient.ts` 已支持 Tauri event 与 WebSocket `/api/ws` 双事件通道；
  3. `src-tauri/src/web_server.rs` 已提供浏览器运行时桥接，说明核心能力并不完全绑死在桌面壳；
  4. `src/services/controlPlane.ts` + `src-tauri/src/agent_control.rs` 已有 control plane / notification / status tree，可继续演进为“远程客户端消费的状态 API”。


## Review（后续跨平台接入能力评估）

- 结论：**可以，而且建议现在就按“本地核心服务 + 多端客户端”来设计。** 纯 Swift macOS 重构不会天然阻断浏览器/手机接入；真正决定未来扩展性的不是 UI 用不用 Swift，而是你是否把核心能力抽成稳定的本地/远程 API。
- 直接原因：当前仓库已经存在 Web API / WebSocket / control plane 的雏形，说明项目天然适合演进为“Mac 宿主 + Browser/Mobile 客户端”模式。
- 是否存在设计层诱因：存在一定架构分裂风险。当前命令层虽然已经抽象出 Tauri invoke 与 Web HTTP 双入口，但核心能力仍主要按桌面前端直接消费来组织；如果未来要支持手机/浏览器远程接入，应继续把“桌面 UI 语义”和“核心服务语义”彻底分层。
- 当前建议方案：
  1. 把项目分成 `Core Service`、`Desktop Client(macOS)`、`Remote Clients(Web/iOS/Android)` 三层；
  2. Core Service 负责 PTY、Git/worktree、文件系统、控制平面、持久化；
  3. Desktop/Browser/Mobile 都只消费统一 API，不直接持有业务真相源；
  4. 若做 Swift 重构，优先重写 mac 客户端壳与原生交互，不要先重写 Core Service。
- 长期改进建议：
  1. 明确区分“本机专属能力”与“可远程代理能力”；
  2. 为远程接入设计鉴权、会话隔离、权限模型与只读/可执行级别；
  3. 逐步把现有 command/event/control-plane 收敛成稳定的 API contract。
- 证据：
  - `src/platform/commandClient.ts`
  - `src/platform/eventClient.ts`
  - `src/platform/runtime.ts`
  - `src/services/controlPlane.ts`
  - `src-tauri/src/web_server.rs`


## 收口 Codex 重复状态标识（2026-03-18）

- [x] 复核当前终端头部 / 项目列表 / worktree 的重复标识来源，并确认最小修改边界
- [x] 移除独立 Codex 运行中标识，统一改为 control plane 状态展示
- [x] 运行针对性测试与静态检查，确认无回归
- [x] 追加 Review，记录根因、修复方案与验证证据

## Review（收口 Codex 重复状态标识）

- 直接原因：终端头部和项目列表同时渲染了两套 Codex 相关标识：一套来自 `codexRunningCount` 的“Codex 运行中”独立蓝点/徽标，另一套来自 `controlPlaneProjection` 的 control plane attention 状态点，因此 Codex 运行时会并排出现两个标识。
- 是否存在设计层诱因：存在。UI 曾同时暴露“独立运行态”与“控制面状态”两条并行语义，和当前 control plane 单一状态源主线不一致；除此之外，未发现新的明显系统设计缺陷。
- 当前修复方案：删除 `TerminalWorkspaceHeader` / `TerminalWorkspaceShell` / `TerminalWorkspaceView` 链路上的 `codexRunningCount` 展示与透传；左侧项目列表不再单独渲染 Codex 运行中蓝点；worktree 行同步改为复用 `projectControlPlaneWorkspace(...)` 的 attention / unread 投影，统一只保留 control plane 状态点与未读 badge。
- 长期改进建议：后续若继续调整终端列表提示，优先坚持“一个真相源对应一个主标识”的规则；运行中、等待、完成、失败都应继续收敛到 control plane attention，不要再恢复独立 provider 运行态徽标。
- 验证证据：
  - `node --test src/utils/controlPlaneProjection.test.mjs src/utils/controlPlaneLifecycle.test.mjs`（11/11 通过，新增 running attention 用例通过）
  - `pnpm exec tsc --noEmit`（通过，无输出）
  - `git diff --check -- src/components/terminal/TerminalWorkspaceHeader.tsx src/components/terminal/TerminalWorkspaceShell.tsx src/components/terminal/TerminalWorkspaceView.tsx src/components/terminal/TerminalWorkspaceWindow.tsx src/utils/controlPlaneLifecycle.test.mjs tasks/todo.md`（通过，无输出）
  - `rg -n "Codex 运行中" src/components/terminal/TerminalWorkspaceHeader.tsx src/components/terminal/TerminalWorkspaceShell.tsx src/components/terminal/TerminalWorkspaceView.tsx src/components/terminal/TerminalWorkspaceWindow.tsx`（无命中，说明这条 UI 链路已移除独立运行态标识）


## 清理 Codex 重复标识收口后的死代码（2026-03-18）

- [x] 复核 `countRunningProviderSessions` 当前是否已退出生产主路径
- [x] 删除死代码与对应测试，保持 control plane 单一状态入口
- [x] 运行针对性测试与静态检查，确认清理无回归
- [x] 追加 Review，记录清理原因与验证证据

## Review（清理 Codex 重复标识收口后的死代码）

- 直接原因：在上一轮把独立的 `Codex 运行中` 标识从头部 / 项目列表 / worktree 行全部移除后，`src/utils/controlPlaneProjection.ts::countRunningProviderSessions` 已不再被任何生产代码引用，只剩测试引用，属于退出主路径后的死代码。
- 是否存在设计层诱因：存在。状态源从“双入口”收口为 control plane 单入口后，如果不顺手清理旧 helper，后续很容易又有人拿它重新画一层重复的 provider 运行态徽标；除此之外，未发现新的明显系统设计缺陷。
- 当前修复方案：删除 `countRunningProviderSessions` 导出及其在 `src/utils/controlPlaneProjection.test.mjs` 中的对应测试，只保留 `projectControlPlaneWorkspace` / `projectControlPlaneSurface` 这条 control plane 投影主路径。
- 长期改进建议：以后凡是做 UI 状态收口，完成主链替换后应马上清理仅剩“历史兼容心智”的 helper / test，避免代码层面继续暗示旧入口仍是受支持能力。
- 验证证据：
  - `rg -n "countRunningProviderSessions" src tasks`（当前仅剩历史任务记录，不再有生产代码/测试引用）
  - `node --test src/utils/controlPlaneProjection.test.mjs src/utils/controlPlaneLifecycle.test.mjs`（10/10 通过）
  - `pnpm exec tsc --noEmit`（通过，无输出）
  - `git diff --check -- src/utils/controlPlaneProjection.ts src/utils/controlPlaneProjection.test.mjs tasks/todo.md`（通过，无输出）


## 最终工作区审查并提交（2026-03-18）

- [x] 审阅当前工作区改动范围与关键 diff
- [x] 运行新鲜验证（Node tests / tsc / cargo test / cargo check / git diff --check）
- [x] 确认无阻塞问题并整理提交说明
- [x] 提交当前工作区改动

## Review（最终工作区审查并提交）

- 直接原因：用户要求“检查一下工作区的改动，如果没有什么问题则进行 commit”，因此本轮在提交前重新审阅了通知主链、auto-read 收紧、控制面结构化通知、终端重复标识收口与相关文档改动，而不是直接沿用上一轮验证结果。
- 是否存在设计层诱因：存在，但当前已经收口到可接受状态。此前的主要诱因是通知职责分散、事件 payload 过粗、以及 UI 还残留独立 provider 运行态标识；本轮工作区已经把这些问题统一收敛到 control plane 主路径，并清理了退出主路径的死代码。除此之外，未发现新的明显系统设计缺陷。
- 当前审查结论：未发现阻塞本次 commit 的问题。工作区改动在语义上围绕同一主线展开——结构化通知、Rust 主投递、pane/surface 级 auto-read、终端状态入口收口——且最新验证全部通过。
- 提交说明：本次提交采用单个提交，覆盖 control plane 通知修复、终端重复状态标识收口、死代码清理，以及对应的计划/任务/AGENTS 文档同步。
- 验证证据：
  - `node --test src/utils/controlPlaneAutoRead.test.mjs src/utils/controlPlaneProjection.test.mjs src/utils/controlPlaneLifecycle.test.mjs scripts/devhaven-control.test.mjs`（33/33 通过）
  - `pnpm exec tsc --noEmit`（通过，无输出）
  - `cargo test agent_control_registry_preserves_structured_notification_fields --manifest-path src-tauri/Cargo.toml`（通过）
  - `cargo check --manifest-path src-tauri/Cargo.toml`（通过）
  - `git diff --check`（通过，无输出）


## macOS 原生重写 Phase A（2026-03-19）

- [x] 建立 `macos/` Swift Package 原生子工程与基础目录
- [x] 先写失败测试，锁定 `~/.devhaven` 数据兼容与 Todo 语义
- [x] 实现 `DevHavenCore` 数据模型与 `LegacyCompatStore`
- [x] 实现 `NativeAppViewModel` 与基础原生 UI（项目列表 / 详情 / 设置 / 回收站 / 工作区占位）
- [x] 更新 `AGENTS.md` 记录新的 macOS 原生工程结构与边界
- [x] 运行 `swift test --package-path macos` 与必要构建验证
- [x] 回写 Review（包含验证证据、已实现范围与剩余未覆盖项）

## Review（macOS 原生重写 Phase A）

- 直接原因：当前 `swift` worktree 里并不存在先前讨论过的原生骨架，因此这轮不是“续写 Swift 工程”，而是从现有 Tauri 主仓中重新建立 `macos/` 原生子工程，并先交付一个可编译、可读真实 `~/.devhaven` 数据的 Phase A 主壳。
- 是否存在设计层诱因：存在。此前仓库里桌面 UI、终端工作区、控制面和数据持久化都强耦合在 Tauri/React 主链上，导致“只支持 macOS、追求更高性能”的目标没有原生落点；本轮先把原生主壳与数据兼容层拆出来，作为后续继续接 Rust Core / 原生终端子系统的稳定边界。除此之外，未发现新的明显系统设计缺陷。
- 当前修复 / 实现方案：
  1. 新建 `macos/Package.swift`，拆出 `DevHavenCore` 与 `DevHavenApp` 两个 target。
  2. 在 `DevHavenCore` 中实现 `AppStateFile / Project / TodoItem` 等模型、`LegacyCompatStore` 数据兼容层，以及 `NativeAppViewModel` 状态编排。
  3. `LegacyCompatStore` 直接兼容 `~/.devhaven/app_state.json`、`projects.json`、`PROJECT_NOTES.md`、`PROJECT_TODO.md`，并在更新 `recycleBin/settings` 时保留未知字段与嵌套未来字段。
  4. 在 `DevHavenApp` 中落地原生三栏主界面：左侧项目列表与搜索，中间详情（概览 / 备注 / 自动化），右侧 `WorkspacePlaceholderView` 作为后续终端子系统接入位；同时补齐原生设置页与回收站 Sheet，并提供显式关闭入口。
  5. 新增 `.gitignore` 规则忽略 Swift Package `.build/` 运行产物，并同步更新 `AGENTS.md` 说明新的原生工程结构与当前边界。
- 当前已实现范围：项目列表搜索、基础详情、Todo 编辑保存、备注保存、README 回退展示、设置读写、回收站恢复、快捷命令/Worktree 只读展示、原生 Workspace 占位。
- 当前未覆盖范围：终端工作区 / PTY / pane-tab-split / control plane 原生投影、快捷命令真实运行态、Git 分支操作与更深层 Rust Core API 桥接，这些仍属于后续批次。
- 验证证据：
  - 红灯阶段：首次 `swift test --package-path macos` 因目标为空、测试引用类型缺失而失败，随后补齐 Swift Package 与实现；中途又因测试里的 key path 写法错误二次失败，已修正。
  - 绿灯阶段：`swift test --package-path macos`（4/4 通过）；`swift build --package-path macos`（通过）；`git diff --check`（通过）。

## macOS 原生 UI 向 Tauri 主界面收口（2026-03-19）

- [x] 从头重新核对当前 worktree 状态，避免沿用被中断回合的半成品判断
- [x] 对照 Tauri 主界面截图与现有 React 组件，确认差距来自“系统三栏”而非单个控件样式
- [x] 先补失败测试，锁定原生详情抽屉与筛选投影行为
- [x] 将原生主界面改为左侧 Sidebar + 中央 MainContent + 右侧 overlay Detail Drawer
- [x] 让原生版在视觉层次上尽量贴近 Tauri：深色主题、顶部工具栏、卡片/列表切换、热力图/标签/目录分区
- [x] 同步更新 `AGENTS.md` 与验证记录

## Review（macOS 原生 UI 向 Tauri 主界面收口）

- 直接原因：用户实际启动后明确反馈“当前原生 UI 和 Tauri 版差距太大，需要复刻 Tauri 版本”。重新核对截图与现有 Swift 实现后，根因不是某个控件细节，而是主布局模型错了——当前原生版仍是系统 `NavigationSplitView` 三栏结构，而 Tauri 版实际是“左侧导航 + 中央项目画布 + 右侧 overlay 详情抽屉”。
- 是否存在设计层诱因：存在。上一批原生实现虽然已经把数据兼容和基础 UI 跑通，但仍过度沿用了系统默认三栏范式，导致信息架构与用户已习惯的 Tauri 主界面脱节；这类偏差如果不尽快收口，后续继续补功能只会让错误布局越来越难改。除此之外，未发现新的明显系统设计缺陷。
- 当前修复 / 实现方案：
  1. 将 `AppRootView.swift` 改为自定义 `HStack + ZStack` 容器，主路径收口成左侧 Sidebar、中央 MainContent、右侧 overlay 详情抽屉。
  2. 新增 `MainContentView.swift` 和 `NativeTheme.swift`，统一深色视觉基调、顶部工具栏、搜索框、日期 / Git 筛选和卡片/列表模式切换。
  3. 重写 `ProjectSidebarView.swift`，把目录、开发热力图、CLI 会话占位、标签区按 Tauri 版侧栏层次重新摆放。
  4. 重写 `ProjectDetailRootView.swift` 为右侧抽屉式滚动详情，保留基础信息、标签、备注、Todo、快捷命令、Markdown 等板块，不再使用原来的 segmented 三栏详情模式。
  5. 在 `NativeAppViewModel.swift` 中新增主视图所需投影：目录/标签计数、热力图聚合、搜索 + 目录 + 标签 + 日期 + Git 筛选、详情抽屉开关、收藏/回收站写回。
- 当前已实现范围：接近 Tauri 版的主界面骨架、深色视觉层次、卡片/列表视图、右侧详情抽屉、基础侧栏分区与热力图聚合、原生筛选状态投影。
- 当前未覆盖范围：像素级样式追平、完整图标/交互细节、真实 CLI 会话列表、终端工作区与 control plane 原生投影；当前“CLI 会话”区域仍是占位投影，不代表终端已迁完。
- 验证证据：
  - 新增 `NativeAppViewModelTests`，覆盖“选中项目会打开详情抽屉并加载备注”“目录/标签/Git 筛选会缩小项目列表”两条行为。
  - `swift test --package-path macos`（6/6 通过）
  - `swift build --package-path macos`（通过）
  - `git diff --check`（通过）

## 提交当前 macOS 原生迁移改动（2026-03-19）

- [x] 复核当前分支、工作区状态与需要提交的文件范围
- [x] 运行提交前新鲜验证（`swift test` / `swift build` / `git diff --check`）
- [x] 仅暂存原生迁移相关文件并执行 commit
- [x] 回写 Review（包含 commit hash 与验证证据）

## Review（提交当前 macOS 原生迁移改动）

- 直接原因：用户明确要求“先将目前的代码进行 commit，然后再进行迁移”，因此本轮先把已经落地的 macOS 原生主壳、数据兼容层、Tauri 主界面收口、以及对应的 AGENTS / lessons / todo 记录整理成单个提交，作为后续继续迁移的稳定基线。
- 是否存在设计层诱因：未发现新的系统性阻塞；但确认了一个需要持续避免的诱因——如果在原生迁移阶段不及时提交当前稳定基线，后续继续做 UI 追平与终端接入时，工作区会混入过多未分段的结构性改动，导致回滚、对照和继续迁移都变得困难。
- 当前提交方案：只暂存原生迁移相关文件（`.gitignore`、`AGENTS.md`、`tasks/lessons.md`、`tasks/todo.md`、`macos/` 子工程），明确排除 `.agents/`、`.claude/skills/`、`.iflow/`、`skills-lock.json` 这些本地无关未跟踪文件；并额外忽略 `macos/.swiftpm/` 与 `macos/.build/`，避免把 Xcode / SwiftPM 本地状态带进版本库。
- 提交结果：已执行 `git commit -m "feat: 搭建 macOS 原生主壳并收口主界面结构"`，当前提交以本轮最新 commit 为准，可用 `git log --oneline -1` 核对。
- 验证证据：
  - `swift test --package-path macos`（6/6 通过）
  - `swift build --package-path macos`（通过）
  - `git diff --check`（通过）
  - 提交前 `git status --short` 仅暂存原生迁移相关文件；未将 `.agents/`、`.claude/skills/`、`.iflow/`、`skills-lock.json` 纳入 commit。


## 修复输入框无法输入字符（2026-03-19）

- [x] 检查当前输入链路与最近相关改动，确认直接原因
- [x] 先补最小失败用例或可验证复现，再做最小修复
- [x] 运行验证并回写 Review

## Review（修复输入框无法输入字符）

- 直接原因：这次问题不在某一个 `TextField` / `TextEditor` 本身，而在 **Swift 原生预览的窗口激活链**。从当前 CLI 环境直接启动 `DevHaven Native` 后，用 `lsappinfo front` 可以看到前台应用仍停留在其它应用，而不是 DevHaven；这说明预览启动链把窗口拉起来了，但没有稳定把当前进程提升为 active/frontmost app。对用户来说，体感就会是“点了输入框，但焦点根本没过去，所以所有输入框都打不进去”。
- 是否存在设计层诱因：存在。之前我们把“原生主界面搭起来”当成主要目标，默认相信 SwiftUI `WindowGroup` 会自动处理好预览态窗口激活；但对于 `swift run` / Xcode 调试这类预览启动链，这个假设并不稳。结果就是输入能力这种跨页面的基础交互，被错误地暴露成“每个输入框都坏了”。除此之外，未发现新的明显系统设计缺陷。
- 当前修复方案：
  1. 在 `AppRootView.swift` 新增 `InitialWindowActivationBridge`，让主窗口首次挂到真实 `NSWindow` 时，统一走一次激活流程，而不是去给每个输入框单独补焦点逻辑。
  2. 激活逻辑收口到 `InitialWindowActivator`：首次看到新的 `windowNumber` 时，顺序执行 `setActivationPolicy(.regular)`、`orderFrontRegardless()`、`makeKey()`、`NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])`，把当前 Swift 原生预览提升为真正的 active/key app。
  3. 增加 `DevHavenAppTests/InitialWindowActivatorTests.swift`，锁住“同一个窗口只激活一次”“切到新窗口会重新激活”两条回归约束，避免后续再把这层激活桥删坏。
- 长期改进建议：后续如果原生版继续扩展多窗口 / 更多 sheet，建议把“窗口激活、默认 key window、首次 responder 策略”继续沉成统一的 macOS window primitive，而不是等到用户报告“输入框没反应”时，再从具体控件层向上追。
- 验证证据：
  - 根因证据：修复前从当前 CLI 环境启动 Swift 原生预览后，`lsappinfo front` 返回的前台 ASN 仍不是 DevHaven，对应现象与“所有输入框都像拿不到焦点”一致。
  - 定向测试：`swift test --package-path macos --filter InitialWindowActivatorTests`（2/2 通过）。
  - 全量验证：`swift test --package-path macos`（19/19 通过）、`swift build --package-path macos`（通过）、`git diff --check`（通过）。
