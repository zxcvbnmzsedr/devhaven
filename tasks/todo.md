# 本次任务清单

## 整理剩余未提交改动并规划下一次 commit（2026-03-21）

- [x] 收集当前剩余未提交/未跟踪文件及 diff 摘要
- [x] 按功能主题判断这些改动是否闭环、是否具备测试/文档配套
- [x] 给出推荐的下一次 commit 拆分方案、顺序与注意事项

## Review（整理剩余未提交改动并规划下一次 commit）

- 当前剩余未提交改动可分成 4 类：
  1. **项目详情面板关闭/打开卡顿修复主线**：
     - `macos/Sources/DevHavenApp/AppRootView.swift`
     - `macos/Sources/DevHavenApp/MainContentView.swift`
     - `macos/Sources/DevHavenApp/ProjectDetailRootView.swift`
     - `macos/Sources/DevHavenApp/DetailPanelCloseAction.swift`
     - `macos/Sources/DevHavenApp/ProjectDetailMarkdownPresentationPolicy.swift`
     - `macos/Tests/DevHavenAppTests/ProjectDetailPanelCloseActionTests.swift`
     - `macos/Tests/DevHavenAppTests/ProjectDetailRootViewTests.swift`
     - `docs/plans/2026-03-21-close-project-detail-panel-freeze.md`
     - `macos/Tests/DevHavenAppTests/MainContentViewTests.swift`（其中只有一条 close helper 相关断言，文件内还混有其它主题测试）
  2. **已完成功能的补录计划文档**：
     - `docs/plans/2026-03-21-direct-projects-virtual-directory-design.md`
     - `docs/plans/2026-03-21-direct-projects-virtual-directory.md`
     - `docs/plans/2026-03-21-recycle-bin-restore-design.md`
     - `docs/plans/2026-03-21-recycle-bin-restore.md`
  3. **尚未实现、只有计划的功能**：
     - `docs/plans/2026-03-21-refresh-project-freeze.md`
  4. **本地环境文件**：
     - `.claude/settings.local.json`
- 推荐拆分：
  - **下一次功能 commit（推荐优先）**：提交“项目详情面板关闭/打开卡顿修复主线”。如果想要历史最干净，可进一步拆成：
    1. `fix(detail-panel): 关闭前释放 responder`
    2. `perf(detail-panel): 详情面板只预览 README`
    但若希望一次性收口用户体感上的“详情面板转圈/卡顿”，也可以合并成一个 detail-panel commit。
  - **之后的 docs-only commit**：单独提交 direct projects / recycle bin 两组补录计划文档，不要和运行时代码混在一起。
  - **暂缓提交**：`docs/plans/2026-03-21-refresh-project-freeze.md`，因为当前没有对应实现与验证证据，单独提交容易让仓库里出现“计划先落地但代码未开始”的悬空状态。
  - **不要提交**：`.claude/settings.local.json`，这是本地环境配置。
- 注意事项：
  - `MainContentViewTests.swift` 目前把“回收站恢复提示”“直连项目移除入口”“detail panel close helper”三类断言混在同一个新文件里；若要让下一次 detail-panel commit 边界更清晰，最好先把 close helper 相关测试拆到独立文件，再提交。
  - `tasks/todo.md` 当前这部分改动只是为了记录整理结论，本身不建议单独成 commit；应跟随你最终选定的功能/文档提交一起落地。

## 提交项目详情面板卡顿修复主线（2026-03-21）

- [x] 明确本次 commit 只包含 detail panel close / README 轻量预览主线，排除 `.claude/settings.local.json` 与未实现计划文档
- [x] 补齐 `ProjectDetailPanelCloseActionTests` 的测试前置条件，避免 `AppRootView.task` 自动 `load()` 把手工注入的测试状态冲掉
- [x] 运行本次提交范围对应的验证命令
- [x] 执行 git commit

## Review（提交项目详情面板卡顿修复主线）

- 提交主题：`fix(detail-panel): avoid project detail panel freeze`
- 提交范围：
  - `macos/Sources/DevHavenApp/AppRootView.swift`
  - `macos/Sources/DevHavenApp/MainContentView.swift`
  - `macos/Sources/DevHavenApp/ProjectDetailRootView.swift`
  - `macos/Sources/DevHavenApp/DetailPanelCloseAction.swift`
  - `macos/Sources/DevHavenApp/ProjectDetailMarkdownPresentationPolicy.swift`
  - `macos/Tests/DevHavenAppTests/ProjectDetailPanelCloseActionTests.swift`
  - `macos/Tests/DevHavenAppTests/ProjectDetailRootViewTests.swift`
  - `docs/plans/2026-03-21-close-project-detail-panel-freeze.md`
  - `tasks/todo.md`
- 本次额外收口：
  - `ProjectDetailPanelCloseActionTests.swift` 里显式设置 `viewModel.hasLoadedInitialData = true`，因为 `AppRootView` 的 `.task` 会在首次挂载时自动调用 `load()`；若不先阻止这条启动链，测试里手工注入的项目/详情状态会被空 store 快照覆盖，导致根本渲染不出详情面板内的 `TextEditor`。
- 提交时明确排除：
  - `.claude/settings.local.json`：本地环境配置
  - `docs/plans/2026-03-21-direct-projects-virtual-directory*`
  - `docs/plans/2026-03-21-recycle-bin-restore*`
  - `docs/plans/2026-03-21-refresh-project-freeze.md`
  - `macos/Tests/DevHavenAppTests/MainContentViewTests.swift`：仍混有其它主题断言，留待对应功能提交时单独收口
- 提交前验证证据：
  - `swift test --package-path macos --filter 'ProjectDetailPanelCloseActionTests|ProjectDetailRootViewTests'` → 通过，`2 tests, 0 failures`
  - `swift build --package-path macos --target DevHavenApp` → 通过
  - `git diff --check -- macos/Sources/DevHavenApp/AppRootView.swift macos/Sources/DevHavenApp/MainContentView.swift macos/Sources/DevHavenApp/ProjectDetailRootView.swift macos/Sources/DevHavenApp/DetailPanelCloseAction.swift macos/Sources/DevHavenApp/ProjectDetailMarkdownPresentationPolicy.swift macos/Tests/DevHavenAppTests/ProjectDetailPanelCloseActionTests.swift macos/Tests/DevHavenAppTests/ProjectDetailRootViewTests.swift docs/plans/2026-03-21-close-project-detail-panel-freeze.md tasks/todo.md` → 通过

## 提交 quick terminal 会话列表改动（2026-03-21）

- [x] 确认本次只提交 quick terminal 会话列表相关文件，不混入其他进行中的工作区改动
- [x] 复用最新验证证据并执行 commit

## Review（提交 quick terminal 会话列表改动）

- 提交主题：`feat(workspace): 收口 quick terminal 会话列表`
- 提交范围：
  - `docs/plans/2026-03-21-quick-terminal-cli-session-list-design.md`
  - `docs/plans/2026-03-21-quick-terminal-cli-session-list.md`
  - `macos/Sources/DevHavenApp/ProjectSidebarView.swift`
  - `macos/Sources/DevHavenApp/WorkspaceProjectListView.swift`
  - `macos/Sources/DevHavenApp/WorkspaceShellView.swift`
  - `macos/Sources/DevHavenCore/Models/AppModels.swift`
  - `macos/Sources/DevHavenCore/Models/OpenWorkspaceSessionState.swift`
  - `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`
  - `macos/Tests/DevHavenAppTests/ProjectSidebarViewTests.swift`
  - `macos/Tests/DevHavenAppTests/WorkspaceProjectListViewTests.swift`
  - `macos/Tests/DevHavenCoreTests/NativeAppViewModelWorkspaceEntryTests.swift`
  - `tasks/todo.md`
  - `tasks/lessons.md`
- 提交前验证证据：
  - `swift test --package-path macos --filter 'NativeAppViewModelWorkspaceEntryTests|ProjectSidebarViewTests|WorkspaceProjectListViewTests'` → 通过，`26 tests, 0 failures`
  - `./dev --no-log` → 成功完成 `swift run --package-path macos DevHavenApp` 构建并进入运行态；确认后手动 `Ctrl+C` 结束
  - `git diff --check -- macos/Sources/DevHavenCore/Models/AppModels.swift macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift macos/Sources/DevHavenApp/ProjectSidebarView.swift macos/Sources/DevHavenApp/WorkspaceProjectListView.swift macos/Tests/DevHavenCoreTests/NativeAppViewModelWorkspaceEntryTests.swift macos/Tests/DevHavenAppTests/ProjectSidebarViewTests.swift macos/Tests/DevHavenAppTests/WorkspaceProjectListViewTests.swift docs/plans/2026-03-21-quick-terminal-cli-session-list-design.md docs/plans/2026-03-21-quick-terminal-cli-session-list.md tasks/todo.md` → 通过

## 实现 quick terminal 会话列表型 UI（2026-03-21）

- [x] 写入 quick terminal 会话列表设计/实施文档
- [x] 先补 quick terminal 会话真相源与 sidebar 交互的失败测试
- [x] 以最小改动实现会话列表型 CLI 区块与 workspace 侧错误按钮隐藏
- [x] 运行验证闭环并追加 Review

## Review（实现 quick terminal 会话列表型 UI）

- 直接原因：之前左侧“CLI 会话”区块的标题虽然已经切到 quick terminal 语义，但列表数据仍来自 `visibleProjects` 的派生逻辑，而不是真实的 `openWorkspaceSessions`。与此同时，workspace 左侧项目列表把 quick terminal 当成普通项目渲染，继续暴露“刷新 worktree / 创建或添加 worktree”按钮，造成标题、状态与可操作能力三者不一致。
- 设计层诱因：存在。问题集中在 **“真实 session 状态”和“sidebar 展示模型”分裂**：`OpenWorkspaceSessionState.isQuickTerminal` 已经是 session 真相源，但 `cliSessionItems` 却还在复用旧的项目派生逻辑，workspace project card 也没有为 quick terminal 建立专门边界。未发现更大的系统设计缺陷。
- 当前修复：
  1. 写入 `docs/plans/2026-03-21-quick-terminal-cli-session-list-design.md` 与 `docs/plans/2026-03-21-quick-terminal-cli-session-list.md`，把“CLI 会话改为真实 quick terminal 会话列表”的设计与实施步骤固化；
  2. `Project` 新增 quick terminal 判定能力，避免 UI 层继续散落 magic id；
  3. `NativeAppViewModel.cliSessionItems` 改为直接读取 `openWorkspaceSessions.filter(\.isQuickTerminal)`，并按当前是否激活输出 `已打开 / 可恢复`；
  4. `ProjectSidebarView` 的“CLI 会话”区块改为真实可交互 session card：点击卡片恢复/激活 quick terminal，点击 `x` 关闭 session；
  5. `WorkspaceProjectListView` 对 quick terminal group 隐藏 worktree 按钮，只保留激活与关闭；
  6. 新增/更新测试，锁定 quick terminal 会话真相源、global sidebar 交互与 workspace 错误按钮隐藏边界。
- 长期建议：如果后续继续扩展 CLI session，优先沿用“session 真相源驱动 UI”的模式，不要再让某个标题叫“会话”，但数据却从项目列表 / scripts / worktrees 临时派生；否则每新增一种 session 类型，都要重复踩一次语义分裂问题。
- 验证证据：
  - TDD 红灯：`swift test --package-path macos --filter 'NativeAppViewModelWorkspaceEntryTests|ProjectSidebarViewTests|WorkspaceProjectListViewTests'` → 修复前失败，关键断言包括：
    - `CLI 会话区块不应继续从普通项目 / worktree 派生`
    - `CLI 会话项点击后应恢复 / 激活真实 quick terminal session`
    - `quick terminal group 应显式跳过 worktree 操作按钮`
  - 定向绿灯：同一命令修复后通过，`26 tests, 0 failures`。
  - 开发入口验证：`./dev --no-log` → 成功完成 `swift run --package-path macos DevHavenApp` 构建并进入运行态；确认后手动 `Ctrl+C` 结束进程。
  - 差异校验：`git diff --check -- macos/Sources/DevHavenCore/Models/AppModels.swift macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift macos/Sources/DevHavenApp/ProjectSidebarView.swift macos/Sources/DevHavenApp/WorkspaceProjectListView.swift macos/Tests/DevHavenCoreTests/NativeAppViewModelWorkspaceEntryTests.swift macos/Tests/DevHavenAppTests/ProjectSidebarViewTests.swift macos/Tests/DevHavenAppTests/WorkspaceProjectListViewTests.swift docs/plans/2026-03-21-quick-terminal-cli-session-list-design.md docs/plans/2026-03-21-quick-terminal-cli-session-list.md tasks/todo.md` → 通过。

## 审查 quick terminal 相关未提交改动（2026-03-21）

- [x] 收集 quick terminal 相关未提交改动与受影响文件
- [x] 检查模型 / ViewModel / UI 状态流是否一致
- [x] 核对测试覆盖与潜在遗漏
- [x] 汇总结论、风险与修复建议

## Review（审查 quick terminal 相关未提交改动）

- 审查范围：
  - `macos/Sources/DevHavenCore/Models/AppModels.swift`
  - `macos/Sources/DevHavenCore/Models/OpenWorkspaceSessionState.swift`
  - `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`
  - `macos/Sources/DevHavenApp/ProjectSidebarView.swift`
  - `macos/Sources/DevHavenApp/WorkspaceShellView.swift`
  - `macos/Tests/DevHavenCoreTests/NativeAppViewModelWorkspaceEntryTests.swift`
- 结论：这批 quick terminal 改动的“创建并进入 terminal workspace”主路径已经打通，但**周边 UI 语义和会话建模还没有完全收口**。我确认到 2 个实质性风险和 1 个低风险一致性问题。
- 主要问题：
  1. **高风险：workspace 侧栏把 quick terminal 当普通项目渲染，暴露了错误的 worktree 操作入口。**
     - `WorkspaceProjectListView.swift:144-149` 对所有 `WorkspaceSidebarProjectGroup` 一律展示“刷新 worktree / 创建或添加 worktree”按钮；
     - quick terminal group 来自 `NativeAppViewModel.workspaceSidebarGroups` 的 `.quickTerminal(at:)` 虚拟项目（`NativeAppViewModel.swift:209-214` + `AppModels.swift:412-428`），并不在 `snapshot.projects` 里；
     - 因此：
       - 点“刷新 worktree”会走 `WorkspaceShellView.swift:35-42` → `viewModel.refreshProjectWorktrees(homePath)`，进一步进入 `NativeAppViewModel.swift:681-692`，在 home 目录上跑 worktree 刷新逻辑，语义错误；
       - 点“创建/添加 worktree”会把 `worktreeDialogProjectPath` 设为 homePath，但 `WorkspaceShellView.swift:18-23` 的 `worktreeDialogProject` 只能从 `snapshot.projects` 里找真实项目，所以弹窗会直接拿不到 source project，表现成按钮无效或路径错误。
  2. **中风险：项目侧栏“CLI 会话”区块没有绑定 quick terminal session 真相源。**
     - `ProjectSidebarView.swift:123-155` 现在右上角 `+` 已经会调用 `viewModel.openQuickTerminal()`；
     - 但实际列表仍来自 `NativeAppViewModel.cliSessionItems`（`NativeAppViewModel.swift:326-335`），它只是从 `visibleProjects` 里筛 `worktrees/scripts`，并不读取 `openWorkspaceSessions`，也不识别 `isQuickTerminal`；
     - 结果是 quick terminal 打开后，这个区块仍可能继续显示“暂无活跃 CLI 会话”，和真实 session 状态脱节；退出 workspace 后，也不会列出这个已保留的 quick terminal session。
  3. **低风险：quick terminal 入口与普通 `enterWorkspace` 的副作用不完全一致。**
     - `enterWorkspace(_:)`（`NativeAppViewModel.swift:471-483`）会同步 `selectedProjectPath`、记录 `workspaceLaunchDiagnostics`、刷新选中文档；
     - `openQuickTerminal()`（`NativeAppViewModel.swift:485-490`）目前只设置 active path 与隐藏 detail panel；
     - 这不一定是当前 bug，但说明 quick terminal 还不是一等“workspace session 类型”，后续只要再有代码默认“所有 workspace entry 都会走 enterWorkspace 同一副作用集”，就容易再次漂移。
- 测试覆盖结论：
  - 已有新增测试 `NativeAppViewModelWorkspaceEntryTests.testOpenQuickTerminalCreatesQuickTerminalWorkspaceSessionAndSidebarGroup` 只能覆盖“session 被创建 + group 出现”；
  - 当前**没有测试**覆盖：
    - quick terminal group 不应展示 worktree 操作按钮；
    - 项目侧栏 CLI 会话区块应反映 quick terminal session；
    - quick terminal 从 workspace 退出/恢复后的可见性与状态一致性。
- 验证证据：
  - 源码证据如上各文件行号；
  - 定向测试：`swift test --package-path macos --filter 'NativeAppViewModelWorkspaceEntryTests|ProjectSidebarViewTests|WorkspaceProjectListViewTests'` → 通过，`23 tests, 0 failures`；
  - 这说明当前测试集没有拦住上面两类 UI / 状态语义问题，也印证了“主路径通过，但边界没锁住”的判断。
- 建议优先级：
  1. 先把 quick terminal 从 `WorkspaceProjectListView` 的普通项目按钮逻辑里分流，隐藏/替换 worktree 按钮；
  2. 再决定“CLI 会话”区块到底是 launcher 还是 session 列表：若是 launcher，就改名并去掉“活跃会话”文案；若是 session 列表，就必须改用 `openWorkspaceSessions` / `isQuickTerminal` 驱动；
  3. 最后补 2~3 条源码级或 ViewModel 级测试，把这些边界锁住。

## 修复 `./dev` 无法启动（2026-03-21）

- [x] 复现 `./dev` 启动失败并记录报错、退出码与触发条件
- [x] 排查 `dev` 及相关原生启动链路，确认直接原因与设计层诱因
- [x] 如需修改，先补最小回归验证，再实现修复
- [x] 运行验证闭环并在 `tasks/todo.md` 追加 Review

## Review（修复 `./dev` 无法启动）

- 直接原因：`./dev` 本身已经顺利通过 Ghostty vendor 准备阶段，真正失败点出在 `swift run --package-path macos DevHavenApp` 的编译阶段。`NativeAppViewModel.swift` 在新加 `openQuickTerminal()` 方法后，多写了一个额外的 `}`，导致 `NativeAppViewModel` 在第 491 行被提前闭合，后半段大量方法/属性都被编译器当成“类型外顶层声明”，于是连锁报出 `static methods may only be declared on a type`、`cannot find ... in scope`、`extraneous '}' at top level` 等错误，`./dev` 因此直接以退出码 1 结束。
- 设计层诱因：存在。`NativeAppViewModel.swift` 当前是一个承载目录筛选、workspace、文档加载、worktree 等多类职责的超长文件；这类大文件里只要在中段插入方法时多出一个花括号，就会把后半个类型整体“踢出作用域”，表面上看像几十个独立编译错误，实际只是一个 scope 断裂。问题集中在文件职责过于集中；未发现更大的系统设计缺陷。
- 当前修复：
  1. 先补 `NativeAppViewModelWorkspaceEntryTests.testOpenQuickTerminalCreatesQuickTerminalWorkspaceSessionAndSidebarGroup`，锁定“快速终端入口必须创建 quick terminal session 与侧栏 group”这条回归边界；
  2. 删除 `NativeAppViewModel.openQuickTerminal()` 末尾误多出的那一个 `}`，让后续 workspace / 筛选 / worktree 相关方法重新回到 `NativeAppViewModel` 类型作用域内；
  3. 保持 quick terminal 其余实现不变，避免把这次“启动链路被语法错误阻断”的修复扩散成额外重构。
- 长期建议：后续如果继续往 `NativeAppViewModel` 塞新入口或状态流，优先把 workspace、筛选、文档加载等职责继续拆分到更小的扩展/辅助类型里；至少在每次插入新方法后立刻跑一次定向 `swift test` 或 `swift build`，不要等到最后再发现整个 `./dev` 被一个花括号拖死。
- 验证证据：
  - TDD 红灯：`swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests/testOpenQuickTerminalCreatesQuickTerminalWorkspaceSessionAndSidebarGroup` → 修复前失败，核心报错为 `NativeAppViewModel.swift:1472:1 extraneous '}' at top level` 与 `NativeAppViewModel.swift:1289:32 static methods may only be declared on a type`。
  - 定向绿灯：同一命令修复后通过，`1 test, 0 failures`。
  - 开发入口实测：`./dev --no-log` → 成功完成 `swift run --package-path macos DevHavenApp` 构建并进入运行态；本次为避免长期占用前台会话，确认启动后手动 `Ctrl+C` 结束进程。
  - 脚本烟测：`bash macos/scripts/test-dev-command.sh` → 通过，输出 `dev command smoke ok`。
  - 差异校验：`git diff --check -- macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift macos/Tests/DevHavenCoreTests/NativeAppViewModelWorkspaceEntryTests.swift tasks/todo.md` → 通过。

## 继续修复项目详情面板打开慢导致转圈（2026-03-21）

- [x] 根据用户补充的“打开项目侧边栏很慢”线索，重新定位真正卡顿点
- [x] 先补失败测试，锁定详情面板不应内联一次性渲染整份超长 README
- [x] 以最小改动收敛详情面板内容渲染开销，并保留完整 README 的使用路径
- [x] 运行定向验证并把新的根因/证据追加到 `tasks/todo.md` 与 `tasks/lessons.md`

## Review（继续修复项目详情面板打开慢导致转圈）

- 直接原因：结合你补充的“打开项目侧边栏很慢所以转圈圈”和代码排查，当前详情面板在 `ProjectDetailRootView.swift` 的 Markdown 区之前会**直接执行 `Text(readme.content)`**，把整份 `README.md` 原文一次性塞进 SwiftUI 文本布局。对大 README 来说，这会让右侧详情抽屉打开/关闭都要做重排版，主线程容易短暂卡住，体感就是 beachball / 转圈。
- 设计层诱因：存在。详情面板同时承担了“轻量元信息查看”和“整份 README 原文展示”两个职责，但没有区分“侧边抽屉预览”和“完整文档内容”的展示边界，导致一个本该快速开的抽屉承载了超长文本布局负担。未发现更大的系统设计缺陷。
- 当前修复：
  1. 新增 `ProjectDetailMarkdownPresentationPolicy`，把 README 展示收口为最多 4000 字符的轻量预览；
  2. `ProjectDetailRootView` 的 Markdown 区不再直接渲染 `readme.content`，而是渲染预览内容；
  3. 若 README 被截断，会额外提示“完整 README 仍保留在『用 README 初始化』路径里”，既保留完整内容入口，又避免详情抽屉一次性布局整份长文档；
  4. 新增源码级回归测试 `ProjectDetailRootViewTests.testMarkdownSectionDoesNotRenderFullReadmeInline`，锁定“详情面板不能再直接 `Text(readme.content)`”这条边界。
- 长期建议：后续凡是侧边抽屉 / inspector / popup 这类“应当秒开”的容器，都不要直接内联完整长文档、长日志或大段 Markdown；应默认拆成**轻量预览 + 明确的完整内容入口**，否则每次布局变化都会把大文本排版成本带进主线程。
- 验证证据：
  - TDD 红灯：新增 `ProjectDetailRootViewTests.testMarkdownSectionDoesNotRenderFullReadmeInline` 后，当前源码中原本存在 `Text(readme.content)`，按测试断言会失败，能直接锁定这条重布局回归边界。
  - 当前代码证据：`ProjectDetailRootView.swift` 已改为 `ProjectDetailMarkdownPresentationPolicy.resolve(readme: readme)` + `Text(markdownPresentation.previewContent)`，不再直接内联整份 README。
  - 差异校验：`git diff --check -- macos/Sources/DevHavenApp/ProjectDetailMarkdownPresentationPolicy.swift macos/Sources/DevHavenApp/ProjectDetailRootView.swift macos/Tests/DevHavenAppTests/ProjectDetailRootViewTests.swift tasks/todo.md tasks/lessons.md` → 通过。
  - 当前工作区边界：本轮无法给出新的 `swift build` / `swift test` 成功结果，因为工作区里存在**与本任务无关**的现有 WIP 改动：`macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift` 当前多出一段 `openQuickTerminal()` 相关未完成改动，并带入额外 `}`，导致整个 package 构建先在该文件报错。这个阻断不在本轮改动范围内。

## 提交终端配置入口优化改动（2026-03-21）

- [x] 确认本次只提交 Ghostty 配置入口优化相关文件，不混入其他进行中的工作区改动
- [x] 复用最新验证证据并执行 commit

## Review（提交终端配置入口优化改动）

- 提交主题：`feat(settings): 直达 Ghostty 配置文件`
- 提交范围：
  - `macos/Sources/DevHavenApp/SettingsView.swift`
  - `macos/Sources/DevHavenApp/Ghostty/GhosttyRuntime.swift`
  - `macos/Tests/DevHavenAppTests/SettingsViewTests.swift`
  - `macos/Tests/DevHavenAppTests/GhosttyRuntimeConfigLoaderTests.swift`
  - `tasks/todo.md`
  - `tasks/lessons.md`
- 提交前验证证据：
  - `swift test --package-path macos --filter 'SettingsViewTests|GhosttyRuntimeConfigLoaderTests'` → 通过，`5 tests, 0 failures`
  - `swift test --package-path macos` → 通过，`139 tests, 5 skipped, 0 failures`
  - `git diff --check -- macos/Sources/DevHavenApp/SettingsView.swift macos/Sources/DevHavenApp/Ghostty/GhosttyRuntime.swift macos/Tests/DevHavenAppTests/SettingsViewTests.swift macos/Tests/DevHavenAppTests/GhosttyRuntimeConfigLoaderTests.swift tasks/todo.md tasks/lessons.md` → 通过

## 优化设置中的终端配置入口（2026-03-21）

- [x] 核对原生设置页与 Ghostty 配置加载逻辑，确认旧 Tauri 终端开关的真实残留范围
- [x] 先补失败测试，锁定设置页应直接提供 Ghostty 配置文件入口、且不再暴露旧开关
- [x] 以最小改动实现 Ghostty 配置文件直达编辑 / 打开目录能力，并保留兼容存储字段不变
- [x] 运行定向验证与必要全量验证，在 `tasks/todo.md` 追加 Review

## Review（优化设置中的终端配置入口）

- 直接原因：原生版的终端实际已经由 Ghostty 托管，并且运行时真相源是 `~/.devhaven/ghostty/config*` / 独立 Ghostty 全局配置；但 `SettingsView.swift` 里仍保留了 Tauri / xterm 时代的 `terminalUseWebglRenderer`、应用内主题切换等开关式 UI，用户在设置里反而无法直接触达到真正生效的 Ghostty 配置文件。
- 设计层诱因：存在。兼容存储层里的旧字段还需要保留给历史 `app_state.json` 读写，但设置页把这些**兼容字段误当成当前产品能力**继续暴露，导致“运行时配置真相源”和“设置页可操作入口”分裂。问题集中在配置入口没有跟随原生终端主线一起迁移；未发现更大的系统设计缺陷。
- 当前修复：
  - `SettingsView.swift`：移除旧 Tauri 终端开关与主题切换 UI，把“终端”分类改为直接展示 Ghostty 配置说明、当前直达路径、`编辑 Ghostty 配置文件` 与 `打开配置目录` 两个入口；
  - `GhosttyRuntime.swift`：新增与运行时同源的 `editableConfigFileURL()` / `ensureEditableConfigFile()`，设置页和终端加载逻辑共用同一套配置路径选择规则；当没有任何现成配置时，首次点击会自动创建 `~/.devhaven/ghostty/config`；
  - 兼容边界：`AppSettings` 里的 `terminalUseWebglRenderer` / `terminalTheme` 继续保留，仅作为兼容存储字段，不再由当前原生设置页编辑。
- 长期建议：后续凡是“为了兼容历史状态仍需保留”的字段，都应明确区分“兼容存储”与“当前产品能力”；如果运行时已经切到新的真相源，设置页应优先暴露真实生效入口，而不是继续维护一套不会驱动当前行为的旧 UI。
- 验证证据：
  - TDD 红灯：`swift test --package-path macos --filter 'SettingsViewTests|GhosttyRuntimeConfigLoaderTests'` 修复前失败，编译错误为 `type 'GhosttyRuntime' has no member 'ensureEditableConfigFile'`，说明新回归边界先锁住了“需要真实的 Ghostty 配置文件入口”；
  - 定向绿灯：同一命令修复后通过，`5 tests, 0 failures`；
  - 全量验证：`swift test --package-path macos` → 通过，`139 tests, 5 skipped, 0 failures`；
  - 差异校验：`git diff --check -- macos/Sources/DevHavenApp/SettingsView.swift macos/Sources/DevHavenApp/Ghostty/GhosttyRuntime.swift macos/Tests/DevHavenAppTests/SettingsViewTests.swift macos/Tests/DevHavenAppTests/GhosttyRuntimeConfigLoaderTests.swift tasks/todo.md tasks/lessons.md` → 通过。

## 修复关闭右侧项目详情面板导致未响应（2026-03-21）

- [x] 复现“关闭右侧项目详情面板”卡死，定位真实交互入口与状态流
- [x] 对照相关 SwiftUI / AppKit 代码，确认直接原因与是否存在设计层诱因
- [x] 先补失败测试，锁定关闭详情面板不应触发未响应这条回归边界
- [x] 以最小改动修复问题，并同步必要文档
- [x] 运行定向验证与必要全量验证，在 `tasks/todo.md` 追加 Review

## Review（修复关闭右侧项目详情面板导致未响应）

- 直接原因：右侧项目详情面板里有 `TextEditor` / `TextField` 一类 AppKit-backed 编辑控件；关闭面板时，代码之前只是把 `isDetailPanelPresented` 设为 `false`，却**没有先让窗口当前 `firstResponder` 释放详情面板内的编辑器**。结果是面板已经从视图树移除，但 `NSWindow.firstResponder` 仍指向那个已经脱离层级的 `NSTextView`，窗口后续事件链会挂在一个悬空 responder 上，体感就像“点完关闭后界面未响应”。
- 设计层诱因：存在，但集中在 AppKit / SwiftUI 生命周期边界。当前详情面板的显示/隐藏状态收口在 `NativeAppViewModel.isDetailPanelPresented`，但“移除一个含原生编辑器的面板前，需要先清理窗口 responder”这一层没有被纳入统一关闭动作，导致状态隐藏了、原生焦点却没回收。未发现更大的系统设计缺陷。
- 当前修复：
  1. 新增 `DetailPanelCloseAction`，把“关闭详情面板前先 `window.makeFirstResponder(nil)`，再落到 `viewModel.closeDetailPanel()`”收口为统一动作；
  2. `MainContentView` 的工具栏关闭入口、`AppRootView` 的遮罩点击关闭、`ProjectDetailRootView` 的右上角关闭按钮，都改为走这条统一关闭链路；
  3. 新增 AppKit 集成回归测试 `ProjectDetailPanelCloseActionTests.testClosingDetailPanelReleasesActiveEditorResponderBeforeHidingPanel`，锁定“关闭前必须先释放活动编辑器 responder”这条边界。
- 长期建议：后续凡是**会整体移除一块含 `TextEditor` / `NSTextView` / `NSTextField` 等 AppKit-backed 控件的面板、抽屉或浮层**，都不要只改 SwiftUI 的布尔显示状态；必须同时检查窗口 `firstResponder` 是否仍挂在即将被移除的子树上，并把 responder 回收动作收口到统一 dismiss helper。
- 验证证据：
  - TDD 红灯：修复前临时探针用例 `swift test --package-path macos --filter TemporaryProjectDetailPanelProbeTests/testClosingDetailPanelReleasesEditorFirstResponder` 失败，断言 `window.firstResponder === textView` 仍成立，证明关闭面板后窗口继续挂着已移除的编辑器 responder。
  - 定向绿灯：`swift test --package-path macos --filter 'ProjectDetailPanelCloseActionTests|NativeAppViewModelWorkspaceEntryTests/(testSelectingAnotherProjectWhileWorkspaceIsOpenKeepsOpenedSessionsAlive|testExitWorkspacePreservesOpenSessionsForLaterReentry)|LegacyCompatStoreTests/testSelectingProjectLoadsProjectDocumentDrafts'` → 通过，`3 tests, 0 failures`。
  - 全量验证快照：在本轮 responder 修复与正式回归测试落地后，`swift test --package-path macos` → 通过，`136 tests, 5 skipped, 0 failures`。
  - 最终代码收口验证：在把 `MainContentView` 的工具栏关闭入口也接到同一 helper 后，`swift build --package-path macos --target DevHavenApp` → 通过。
  - 当前工作区说明：继续重跑 `swift test --package-path macos` 目前会被工作区里**与本任务无关**的现有 WIP 测试 `macos/Tests/DevHavenAppTests/GhosttyRuntimeConfigLoaderTests.swift` 阻断，报 `type 'GhosttyRuntime' has no member 'ensureEditableConfigFile'`；该失败不在本任务 diff 范围内，因此本轮保留上面的全量通过快照，并以最终目标编译验证补齐闭环。
  - 差异校验：`git diff --check -- macos/Sources/DevHavenApp/DetailPanelCloseAction.swift macos/Sources/DevHavenApp/AppRootView.swift macos/Sources/DevHavenApp/ProjectDetailRootView.swift macos/Sources/DevHavenApp/MainContentView.swift macos/Tests/DevHavenAppTests/ProjectDetailPanelCloseActionTests.swift tasks/todo.md tasks/lessons.md` → 通过。

## 修复首页左上角加号点击无反应（2026-03-21）

- [x] 对照 `origin/archive/2.8.3` 中首页左上角加号的真实功能链路，确认菜单项、状态变化与调用顺序
- [x] 回滚上一轮与 2.8.3 行为不一致的假设（例如“单击直接打开目录选择器”“添加目录后自动切到新目录筛选”）
- [x] 先补失败测试，锁定 2.8.3 的三个入口：添加工作目录（扫描项目）/ 直接添加为项目 / 刷新项目列表
- [x] 以最小改动在原生首页恢复与 2.8.3 一致的功能
- [x] 运行验证并在 `tasks/todo.md` 追加基于 2.8.3 对照的 Review

## Review（修复首页左上角加号点击无反应）

- 2.8.3 真相源对照：
  - 归档分支 `origin/archive/2.8.3` 的 `src/components/Sidebar.tsx` 中，首页左上角加号不是单一按钮，而是 `DropdownMenu`；
  - 该菜单有 3 个动作：`添加工作目录（扫描项目）`、`直接添加为项目`、`刷新项目列表`；
  - 其中“添加工作目录”会先写入 `appState.directories`，再执行 refresh 重新扫描；“直接添加为项目”会写入 `directProjectPaths` 并立即 build 项目；“刷新项目列表”会重新扫描 `directories + directProjectPaths`。
- 直接原因：原生版迁移后，`ProjectSidebarView.swift` 只剩下一个静态 `plus.circle` 图标，没有把 2.8.3 里的目录菜单和背后的三条数据链路一起迁过来；因此用户点击时没有任何响应。
- 设计层诱因：存在。问题不只是一个按钮漏绑 action，而是 **Tauri 版的复合入口（菜单 + appState 更新 + 项目扫描/build）在迁到原生版时被降成了纯展示图标**，导致 `directories` / `directProjectPaths` 这些兼容状态虽然还在模型里，却没有对应的首页交互和刷新链路。问题集中在迁移时 UI 行为与数据动作一起丢失；未发现明显更大的系统设计缺陷。
- 当前修复：
  - `ProjectSidebarView.swift`：把“目录”右侧加号恢复为和 2.8.3 一致的 `Menu`，包含 3 个入口：
    1. `添加工作目录（扫描项目）`
    2. `直接添加为项目`
    3. `刷新项目列表`
  - `NativeAppViewModel.swift`：
    - `addProjectDirectory(_:)` 现在只负责持久化工作目录，不再错误地自动切换当前目录筛选；
    - 新增 `addDirectProjects(_:)`，对齐 2.8.3 的“直接添加为项目”；
    - 新增 `refreshProjectCatalog()`，对齐 2.8.3 的 refresh：扫描 `directories`、合并 `directProjectPaths`、重建项目列表并持久化；
    - `refresh()` 同步改为在有目录/直连项目配置时触发上述刷新链路。
  - `LegacyCompatStore.swift`：新增 `updateDirectProjectPaths(_:)`，与既有 `updateDirectories(_:)` 一起负责兼容写回 `app_state.json`。
  - `NativeAppViewModel.swift` 底部新增与 2.8.3 对齐的最小项目发现/构建辅助逻辑：
    - 工作目录扫描：收录根 Git 仓库、直接子目录、以及更深层的嵌套 Git 仓库；
    - 直接项目构建：保留旧项目的 `id/tags/scripts/worktrees/gitDaily/created`，只刷新元信息。
  - 测试更新：
    - `ProjectSidebarViewTests`：锁定目录加号菜单的 3 个动作文案；
    - `NativeAppViewModelTests.testRefreshProjectCatalogMergesConfiguredDirectoriesAndDirectProjectPathsLikeArchiveRefresh`
    - `NativeAppViewModelTests.testAddDirectProjectsPersistsPathsAndBuildsProjectsLikeArchiveSidebarAction`
- 长期建议：后续凡是“从旧栈迁到新栈”的交互，都不要只迁视觉元素；应把 **入口形态、状态写入、刷新/副作用链路** 一起列成迁移清单，否则很容易出现“模型字段还在、UI 图标也还在，但真正行为已断线”的半迁移状态。
- 验证证据：
  - TDD 红灯：`swift test --package-path macos --filter 'ProjectSidebarViewTests|NativeAppViewModelTests/(testRefreshProjectCatalogMergesConfiguredDirectoriesAndDirectProjectPathsLikeArchiveRefresh|testAddDirectProjectsPersistsPathsAndBuildsProjectsLikeArchiveSidebarAction)'`
    - 修复前失败，编译错误：
      - `value of type 'NativeAppViewModel' has no member 'refreshProjectCatalog'`
      - `value of type 'NativeAppViewModel' has no member 'addDirectProjects'`
  - 定向绿灯：同一命令修复后通过，`3 tests, 0 failures`。
  - 全量验证：`swift test --package-path macos` → 通过，`126 tests, 5 skipped, 0 failures`。
  - 差异校验：`git diff --check` → 通过。

## 合并 `worktree` 分支回当前工作区（2026-03-21）

- [x] 核对当前 `main` / `worktree` 分支差异、预先存在的工作区状态与合并基线
- [x] 将 `worktree` 分支合并到当前 `main`，处理冲突并保留需要的文档同步
- [x] 运行合并后的验证命令，并在 `tasks/todo.md` 追加 Review

## Review（合并 `worktree` 分支回当前工作区）

- 合并结果：已将 `worktree` 分支上的 3 个提交（`66914f1`、`9ab13d5`、`5b7cca7`）并入当前 `main`，对应能力包括“worktree 复用已准备好的 Ghostty vendor”“隐藏侧栏项目卡片上的 worktree 数量徽标”“为当前终端窗格增加聚焦描边”。
- 预处理说明：合并前发现当前工作区里有一个**已暂存删除**的 `tasks/todo.md`；由于仓库工作流要求在执行前写 checklist，并且 `worktree` 分支本身也修改了该文件，本轮先恢复该文件，再把两侧任务记录统一收口到最终 merge 结果。
- 冲突处理：本轮真实文本冲突出现在 `AGENTS.md` 与 `tasks/todo.md`。`AGENTS.md` 已合并保留 `./release` 入口、Ghostty 配置优先级说明，以及 worktree 自动复用 vendor 的最新事实；`tasks/todo.md` 已同时保留两边历史任务记录，并补充本次 merge Review。
- 验证证据：
  - `swift test --package-path macos` → 通过，`123 tests, 5 skipped, 0 failures`。
  - `bash macos/scripts/test-dev-command.sh` → 通过，输出 `dev command smoke ok`。
  - `bash macos/scripts/test-release-command.sh` → 通过，输出 `release command smoke ok`。
  - `git diff --check` → 通过。

## 提交当前改动（2026-03-21）

- [x] 确认当前改动范围与提交主题
- [x] 同步更新任务记录
- [x] 运行提交前验证并记录证据
- [x] 执行 git commit

## Review（提交当前改动）

- 提交结果：已创建提交 `feat(workspace): 为当前终端窗格增加聚焦描边`。
- 本次纳入提交的改动：
  - `WorkspaceTerminalPaneView.swift`：在隐藏 pane header 的 workspace minimal 模式下，为当前聚焦终端 pane 增加 accent 描边，避免当前 pane 缺少可见焦点反馈。
  - `.claude/settings.local.json`：补充本地工具权限，允许 `mcp__serena__find_file` 与 `mcp__open-websearch__search`。
  - `tasks/todo.md`：记录本次提交任务与验证证据。
- 验证证据：
  - `swift test --package-path macos` → 通过，`111 tests, 5 skipped, 0 failures`；过程中仅有既有 Ghostty 链接 warning，未阻断构建与测试。
  - `git diff --check` → 通过。
- 当前边界：
  - 工作区里仍有未跟踪文件 `release`，本次未纳入提交；若后续要正式引入新的根目录发布入口，需要同步更新 `AGENTS.md` / 相关文档后再单独提交。

## 删除工作区侧栏项目卡片上的 worktree 数量徽标（2026-03-21）

- [x] 记录最小设计与实施计划
- [x] 先补失败测试，锁定项目卡片不再显示 worktree 数量
- [x] 以最小改动删除数量徽标并保留 worktree 列表
- [x] 运行定向验证并追加 Review

## Review（删除工作区侧栏项目卡片上的 worktree 数量徽标）

- 直接原因：`WorkspaceProjectListView.swift` 里的私有 `ProjectGroupView.projectCard` 之前会在项目卡片右侧用 `group.worktrees.count` 渲染一个数量徽标，因此用户在 `DevHaven` 项目旁会看到 `1`。
- 设计层诱因：这是一个局部 UI 信息密度问题，不是数据流或状态分裂问题。`worktree` 数量和下方列表已经同时表达了相同信息，造成冗余展示；未发现明显系统设计缺陷。
- 当前修复：
  - 删除 `ProjectGroupView.projectCard` 中基于 `group.worktrees.count` 的数量徽标视图；
  - 保留 `ForEach(group.worktrees)` 列表、hover 操作按钮、卡片样式和交互不变；
  - 新增 `WorkspaceProjectListViewTests`，用源码级回归测试锁定“列表仍在，但数量徽标逻辑已删除”。
- 长期建议：后续如果还要继续收敛侧栏信息密度，优先先检查“同一信息是否已经在下一级列表或 hover 操作中表达”，避免再叠加纯统计型徽标。
- 验证证据：
  - TDD 红灯：`swift test --package-path macos --filter WorkspaceProjectListViewTests/testProjectCardDoesNotRenderWorktreeCountBadge` → 修复前失败，报 `项目卡片不应再使用 group.worktrees.count 渲染数量徽标`。
  - 定向绿灯：`swift test --package-path macos --filter WorkspaceProjectListViewTests/testProjectCardDoesNotRenderWorktreeCountBadge` → 通过，`1 test, 0 failures`。
  - 差异校验：`git diff --check` → 通过。

## 修复 worktree 下 ./dev 因 Ghostty vendor 缺失而启动失败（2026-03-21）

- [x] 复现 worktree 下 `./dev` 的 Ghostty vendor 校验失败，并确认触发条件
- [x] 对照 `git worktree` / vendor 布局定位根因与边界
- [x] 先补脚本级失败用例，锁定 worktree vendor 复用预期
- [x] 以最小改动修复 worktree 启动链路并同步必要文档
- [x] 运行定向验证并追加 Review

## Review（修复 worktree 下 ./dev 因 Ghostty vendor 缺失而启动失败）

- 直接原因：根目录 `./dev` 与 `macos/scripts/build-native-app.sh` 之前都只会对“当前 checkout 的 `macos/Vendor/`”执行 `setup-ghostty-framework.sh --verify-only`。而 `macos/Vendor/` 被 `.gitignore` 忽略，linked worktree 不会自动继承主 checkout 已准备好的 vendor，所以在 worktree 里启动时会直接卡死在 vendor 校验阶段。
- 设计层诱因：Ghostty binary target 依赖的是一个本地忽略目录，但脚本边界把“当前 worktree 必然已经有独立 vendor”当成默认前提，导致同一仓库的多个 checkout 在本地依赖真相源上分裂。问题集中在 bootstrap 边界没有对齐；未发现更大的系统设计缺陷。
- 当前修复：
  - `setup-ghostty-framework.sh` 新增 `--ensure-worktree-vendor`，会先检查当前 worktree 的 `macos/Vendor/`；若缺失或损坏，则扫描同仓库其他 `git worktree`，找到首个已验证通过的 vendor 并同步到当前 worktree；
  - `./dev` 改为先执行 `--ensure-worktree-vendor`，所以 linked worktree 里不再因为本地缺少 vendor 而直接失败；
  - `build-native-app.sh` 同步切到相同入口，避免 worktree 下打包链路继续踩同一个坑；
  - `README.md`、`AGENTS.md` 已同步更新为“worktree 可自动复用其他 checkout 的 vendor”的现状说明。
- 长期建议：如果后续 worktree 使用频率继续上升，可进一步把 Ghostty vendor 收口到显式共享缓存（例如 `~/.devhaven/` 下的统一 cache）而不是按 worktree 复制，避免重复占用磁盘并减少同步成本。
- 验证证据：
  - TDD 红灯：`bash macos/scripts/test-dev-command.sh` → 修复前失败；临时 linked worktree 内稳定复现 `Ghostty vendor 验证失败`，缺少 `GhosttyKit.xcframework`、`themes` 与 `terminfo`。
  - 定向绿灯：`bash macos/scripts/test-dev-command.sh` → 通过，输出 `dev command smoke ok`。
  - 当前 worktree 实测：`bash macos/scripts/setup-ghostty-framework.sh --ensure-worktree-vendor` → 成功复用 `/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Vendor`，并完成当前 worktree `macos/Vendor/` 校验。
  - 当前 worktree 启动链路验证：用 mock `swift` 执行 `./dev --no-log` → 通过 vendor 准备阶段并实际调用 `swift run --package-path macos DevHavenApp`。
  - 当前 worktree 打包链路验证：`bash macos/scripts/build-native-app.sh --debug --no-open --output-dir /tmp/devhaven-native-app-worktree-vendor-verify` → 通过，产出 `/tmp/devhaven-native-app-worktree-vendor-verify/DevHaven.app`；过程中出现的 Ghostty umbrella header warning 为上游既有告警，不是本次改动新增错误。
  - 差异校验：`git diff --check` → 通过。
||||||| Stash base

## 修复新开项目 / 新开 pane 后终端焦点未进入命令行（2026-03-21）

- [x] 复盘 workspace / Ghostty 焦点链路，确认新开项目与新开 pane 共用的直接失焦点
- [x] 先补失败测试，锁定“逻辑焦点 pane 后续仍要把 responder 从按钮/列表控件收回 terminal”这条回归边界
- [x] 以最小改动修复焦点请求逻辑，确保新开项目与新开 pane 都会落到对应 terminal surface
- [x] 运行定向验证、必要构建检查，并在 `tasks/todo.md` 追加 Review

## Review（修复新开项目 / 新开 pane 后终端焦点未进入命令行）

- 直接原因：`GhosttySurfaceHostModel.restoreWindowResponderIfNeeded()` 之前只会在 `window.firstResponder` **已经是另一个 `GhosttyTerminalSurfaceView`** 时，才把 responder 转回当前逻辑焦点 pane。可你这次复现的两个入口——**新开项目**与**点击按钮新开 pane**——前一个 responder 往往是项目列表项、按钮或其他非 terminal 控件。于是即使 pane 的业务焦点已经切到了新项目 / 新 pane，首次 attach 阶段若没把焦点稳稳落进 terminal，后续 restore 也会因为这条 guard 过窄而直接跳过，最终表现成“新开后命令行没有输入焦点”。
- 设计层诱因：存在，但集中在 GUI responder 同步边界。当前模型里“哪个 pane 是逻辑焦点”已经由 `focusedPaneId` 统一管理，但“AppKit `firstResponder` 该不该跟进”在恢复阶段仍假设**当前 responder 必须已经属于 terminal 家族**。这个假设对 pane 间切换成立，但对“从项目列表 / pane header 按钮触发的新开动作”不成立。未发现明显更大的系统设计缺陷。
- 当前修复：
  1. 保持现有 logical focus / pane focus 状态流不变；
  2. 仅在 `GhosttySurfaceHostModel.restoreWindowResponderIfNeeded()` 做最小收口：只要当前 pane 已经是逻辑焦点、窗口也已挂载，并且 `firstResponder` 还不是该 pane 自己，就允许把 responder 还给当前 `ownedSurfaceView`，不再强依赖“当前 responder 也必须是 terminal”；
  3. 新增回归测试 `GhosttySurfaceHostTests.testRestoreWindowResponderCanReclaimFocusedPaneFromNonTerminalResponderAfterMissedInitialFocus`，锁定“首次焦点请求被按钮吃掉后，后续仍要把 responder 收回 terminal”这条边界。
- 长期建议：后续只要继续保留“SwiftUI 逻辑焦点 + AppKit 原生 responder”双层机制，就要默认把**来自按钮、列表、tab bar 等非 terminal 控件的临时 responder 占用**视为正常 GUI 行为，而不是只处理 terminal-to-terminal 交接。否则每次新增一个“从控件触发切 pane / 切项目”的入口，都容易再冒出同类焦点回归。
- 验证证据：
  - TDD 红灯：`swift test --package-path macos --filter GhosttySurfaceHostTests/testRestoreWindowResponderCanReclaimFocusedPaneFromNonTerminalResponderAfterMissedInitialFocus` → 修复前失败，断言“当前 pane 已经是逻辑焦点时，即使首次焦点请求被按钮吃掉，后续也应把 responder 还给 terminal surface”未成立。
  - 定向绿灯：同一条命令修复后通过，`1 test, 0 failures`。
  - 相关回归：`swift test --package-path macos --filter 'GhosttySurfaceHostTests/(testPrepareForContainerReuseYieldsWindowFirstResponderWhenSurfaceViewOwnsResponder|testRequestFocusRetriesWhenFirstResponderAssignmentMissesFirstAttempt|testRestoreWindowResponderCanReclaimFocusedPaneFromNonTerminalResponderAfterMissedInitialFocus)|GhosttySurfaceFocusRequestPolicyTests|GhosttySurfaceScrollViewTests|GhosttySurfaceRepresentableUpdatePolicyTests|WorkspaceSurfaceActivityPolicyTests'` → 通过，`20 tests, 0 failures`。
  - 构建验证：`swift build --package-path macos` → 通过。
  - 差异校验：`git diff --check -- macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceHost.swift macos/Tests/DevHavenAppTests/GhosttySurfaceHostTests.swift tasks/todo.md` → 通过。

## 排查 ./release 打包产物字体异常（2026-03-21）

- [x] 核对当前 `./release` 打包链、Ghostty runtime 字体配置与已有字体测试，确认可能落点
- [x] 复现 release 产物的字体异常，并区分是运行态配置问题、bundle 资源问题，还是字体 override 未生效
- [ ] 如果确认是代码问题，先补失败测试再做最小修复
- [ ] 运行定向验证、必要的 release 打包验证，并在 `tasks/todo.md` 追加 Review

## 继续修复 workspace 分屏后旧 pane 仍会丢失（2026-03-21）

- [x] 复盘上轮分屏修复与当前截图，确认真正仍在失效的是 surface 状态重放时序
- [x] 先补失败测试，锁定“只有在新容器完成 attach/layout 后才能重放状态”这条边界
- [x] 以最小改动把 post-attach replay 收口到 `GhosttySurfaceScrollView` + `GhosttySurfaceHostModel`
- [x] 运行定向验证并在 `tasks/todo.md` 追加 Review

## Review（继续修复 workspace 分屏后旧 pane 仍会丢失）

- 直接原因：上一轮虽然已经在 `prepareForContainerReuse()` 里清掉了 `occlusion / focus / backing size` 缓存，但 `GhosttySurfaceHostModel.acquireSurfaceView(...)` 仍然会**在旧 `GhosttySurfaceScrollView` 还没完成移除、新 `GhosttySurfaceScrollView` 还没完成 addSubview/layout 之前**就把这些状态重放回 `GhosttyTerminalSurfaceView`。结果就是：缓存确实被清了，但 replay 仍然打在旧容器时序上；等旧 pane 真正被挂到新的 split 容器后，已经没有新的 attach 后 replay，所以用户仍会看到“左边旧 pane 发白/内容消失”。
- 设计层诱因：存在。问题不再是 split tree 或 surface owner 本身，而是 **surface 复用生命周期被拆成了“model 取 view”与“scroll/container 真正 attach”两段，却把 attach-sensitive replay 放在了前一段**。也就是说，状态缓存和状态重放虽然都已收口，但重放时机仍然分裂。未发现更大的系统设计缺陷。
- 当前修复：
  1. `GhosttySurfaceScrollView` 新增 `onSurfaceAttached` 回调与一次性 `needsSurfaceAttachmentCallback` 标记，只在真实 `layout()` 完成后触发 post-attach hook；
  2. `GhosttySurfaceHostModel.acquireSurfaceView(...)` 在复用既有 surface 时不再提前重放状态，只负责准备复用与记录 diagnostics；
  3. 新增 `GhosttySurfaceHostModel.surfaceViewDidAttach(preferredFocus:)`，把 `occlusion / focus` replay 收口到**真实 attach 完成之后**执行；
  4. `GhosttyTerminalView` 负责把 scroll wrapper 的 attach 回调接回 `surfaceViewDidAttach(...)`，确保首次挂载和 split/tree 迁移后的重新挂载都走同一条时序；
  5. `GhosttySurfaceScrollViewTests` 新增两条回归：锁定“首轮 layout 只回调一次”和“surface swap 后要再回调一次”。
- 长期建议：如果后续 split/tree/zoom 继续暴露新的 AppKit 容器迁移问题，下一步优先考虑把“稳定 owner”继续上提到完整 hosted container，而不是继续在 `GhosttyTerminalSurfaceView` 内增加更多局部 cache reset；但在当前主线上，先把 replay 时序钉死到 post-attach 已经足够对齐当前故障。
- 验证证据：
  - TDD 红灯：`swift test --package-path macos --filter GhosttySurfaceScrollViewTests` → 初次失败，报 `extra argument 'onSurfaceAttached' in call`，证明测试先锁住了“需要显式 post-attach hook”这条边界。
  - 定向绿灯：同一条命令修复后通过，`4 tests, 0 failures`。
  - 相关回归：`swift test --package-path macos --filter 'WorkspaceTerminalSessionStoreTests|WorkspaceSurfaceRegistryTests|WorkspaceTerminalStoreRegistryTests|WorkspaceSplitTreeViewKeyPolicyTests|GhosttySurfaceScrollViewTests'` → 通过，`14 tests, 0 failures`。
  - 构建验证：`swift build --package-path macos` → 通过。
  - 差异校验：`git diff --check -- macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceScrollView.swift macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceHost.swift macos/Sources/DevHavenApp/Ghostty/GhosttyTerminalView.swift macos/Tests/DevHavenAppTests/GhosttySurfaceScrollViewTests.swift` → 通过。

## 继续修复“先点亮 pane 焦点，再分屏时旧 pane 消失”（2026-03-21）

- [x] 根据新复现条件聚焦 firstResponder / surface focus 链路，而不是继续泛化到 split 拓扑
- [x] 先补失败测试，锁定“container reuse 前必须释放旧 pane 的 window firstResponder”边界
- [x] 以最小改动把 firstResponder 释放收口到 `GhosttyTerminalSurfaceView.prepareForContainerReuse()` / `tearDown()`
- [x] 运行定向验证并追加 Review

## Review（继续修复“先点亮 pane 焦点，再分屏时旧 pane 消失”）

- 直接原因：你补充的“**先点击 pane 让它拿到真实焦点，再分屏就稳定消失**”把根因进一步钉死到了 AppKit responder 链。当前 `GhosttyTerminalSurfaceView.prepareForContainerReuse()` 之前只会清 attachment cache，却不会释放 `window.firstResponder`；所以当旧 pane 的 surface 已经因为鼠标点击拿到真实 firstResponder 时，split/tree 重挂载会把**带着旧 responder 身份的 surface**直接搬进新容器，表现成旧 pane 在分屏后变白/内容丢失。
- 设计层诱因：存在。这说明当前 Ghostty surface 的“可见性/尺寸状态”与“AppKit responder 身份”仍然分裂管理：前者已经收口到 attachment replay，后者却没纳入 reuse 生命周期。未发现更大的系统设计缺陷，问题仍集中在 `GhosttyTerminalSurfaceView` 这一层的复用边界。
- 当前修复：
  1. 在 `GhosttyTerminalSurfaceView` 新增 `resignOwnedFirstResponderIfNeeded()`，仅当窗口当前 firstResponder 确实是该 surface（或其后代）时才显式 `makeFirstResponder(nil)`；
  2. `prepareForContainerReuse()` 和 `tearDown()` 都先释放 owned firstResponder，再清本地 `focused` 状态与 attachment cache，确保 surface 不会“带着旧焦点”进入新 split 容器；
  3. 新增回归测试 `GhosttySurfaceHostTests.testPrepareForContainerReuseYieldsWindowFirstResponderWhenSurfaceViewOwnsResponder`，锁定这条 firstResponder 释放边界。
- 长期建议：后续所有 pane 复用/关闭/隐藏问题，都要同时检查两类状态是否成对收口：一类是 Ghostty 的 `occlusion / focus / size`，另一类是 AppKit 的 `window.firstResponder`。只清 Ghostty 内部状态、不处理 AppKit responder，仍然会留下“点击后才触发”的 GUI 级缺陷。
- 验证证据：
  - TDD 红灯：`swift test --package-path macos --filter GhosttySurfaceHostTests/testPrepareForContainerReuseYieldsWindowFirstResponderWhenSurfaceViewOwnsResponder` → 初次失败，断言 `window.firstResponder === view` 仍成立，证明 reuse 前没有释放旧焦点。
  - 定向绿灯：同一条命令修复后通过，`1 test, 0 failures`。
  - 相关回归：`swift test --package-path macos --filter 'GhosttySurfaceHostTests/testPrepareForContainerReuseYieldsWindowFirstResponderWhenSurfaceViewOwnsResponder|GhosttySurfaceScrollViewTests|WorkspaceTerminalSessionStoreTests|WorkspaceSurfaceRegistryTests|WorkspaceTerminalStoreRegistryTests|WorkspaceSplitTreeViewKeyPolicyTests'` → 通过，`15 tests, 0 failures`。
  - 构建验证：`swift build --package-path macos` → 通过。
  - 差异校验：`git diff --check -- macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceView.swift macos/Tests/DevHavenAppTests/GhosttySurfaceHostTests.swift` → 通过。
  - 本轮 fresh 验证：再次运行同一组相关回归 → 通过，`15 tests, 0 failures`。
  - 本轮 full suite：`swift test --package-path macos` → 通过，`118 tests, 5 skipped, 0 failures`。

## 继续修复“点击 pane 后分屏，旧 terminal surface 跑到另一侧、原 pane 留空壳”（2026-03-21）

- [x] 根据最新截图复盘 split 后左右 pane 的真实呈现，确认这次更像 representable 复用换 model 时仍挂着旧 surface，而不是 pane 真被删除
- [x] 先补失败测试，锁定“update 阶段切换到 fresh model 时也必须拿到该 model 自己的 surface”这条边界
- [x] 以最小改动修复 `GhosttyTerminalView` / representable 的 surface 绑定逻辑，避免旧 surface 跟着被复用的 NSView 跑到错误 pane
- [x] 运行定向验证、全量 `swift test --package-path macos` 与差异检查，并把结果追加到 Review

## Review（继续修复“点击 pane 后分屏，旧 terminal surface 跑到另一侧、原 pane 留空壳”）

- 直接原因：最新截图显示的问题不再像“旧 pane 被删掉”，而更像 **旧 terminal surface 跟着被 SwiftUI 复用的 representable 跑到了另一侧 pane，原 pane 留下空壳背景**。顺着这条线往下查，`GhosttySurfaceRepresentable.updateNSView()` 之前只会读取 `model.currentSurfaceView`；如果同一个 `NSViewRepresentable` 在 leaf -> split 的重组里被 SwiftUI 复用到了新的 pane/model，而新 model 此时还没有 `currentSurfaceView`，它就会继续挂着旧 pane 的 surface，不会在 update 阶段为新 model 补一次 `acquireSurfaceView(...)`。
- 设计层诱因：存在。虽然我们之前已经把 subtree structural remount 和 post-attach replay 收口了，但 **representable 这一层仍默认假设“update 时 model 不会换成一个 fresh owner”**。这在普通 SwiftUI 视图里常常没问题，但对“一个活着的 terminal NSView 被外部 store 复用、同时树结构又在变化”的场景就不够稳。未发现更大的系统设计缺陷，问题集中在 representable 的 surface 解析边界。
- 当前修复：
  1. 给 `GhosttySurfaceRepresentableUpdatePolicy` 新增 `resolvedSurfaceView(for:preferredFocus:)`，统一定义“若 model 还没有 current surface，就在此处补 `acquireSurfaceView(...)`”；
  2. `GhosttyTerminalView.makeNSView` 与 `updateNSView` 都改为走这条统一解析逻辑，确保 representable 即使在 update 阶段换到一个 fresh model，也会拿到 **这个 model 自己的 surface**，而不是继续沿用旧 surface；
  3. 新增 `GhosttySurfaceRepresentableUpdatePolicyTests` 两条回归：fresh model 会创建 surface、已有 surface 的 model 会继续复用原实例；
  4. 测试里对新建的 `GhosttySurfaceHostModel` 显式 `releaseSurface()`，避免真实 Ghostty surface 在 full suite 里遗留到后续 AppKit 测试进程。
- 长期建议：后续只要继续沿“外部 store 持有终端 owner，SwiftUI 只负责摆放容器”这条架构，就要默认把 `NSViewRepresentable` 当成**可能被复用换 model** 的边界处理，而不是假设只有 `makeNSView` 会负责建立 owner -> NSView 绑定。对这种终端宿主组件，`updateNSView` 也要能安全地完成 owner 切换。
- 验证证据：
  - TDD 红灯：`swift test --package-path macos --filter GhosttySurfaceRepresentableUpdatePolicyTests` → 初次失败，报 `type 'GhosttySurfaceRepresentableUpdatePolicy' has no member 'resolvedSurfaceView'`。
  - 新增回归：同一条命令修复后通过，`3 tests, 0 failures`。
  - 相关分屏回归：`swift test --package-path macos --filter 'GhosttySurfaceRepresentableUpdatePolicyTests|GhosttySurfaceHostTests/testPrepareForContainerReuseYieldsWindowFirstResponderWhenSurfaceViewOwnsResponder|GhosttySurfaceScrollViewTests|WorkspaceTerminalSessionStoreTests|WorkspaceSurfaceRegistryTests|WorkspaceTerminalStoreRegistryTests|WorkspaceSplitTreeViewKeyPolicyTests'` → 通过，`18 tests, 0 failures`。
  - 全量验证：`swift test --package-path macos` → 最终 fresh 重跑通过，`120 tests, 5 skipped, 0 failures`。
  - 差异校验：`git diff --check -- macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceRepresentableUpdatePolicy.swift macos/Sources/DevHavenApp/Ghostty/GhosttyTerminalView.swift macos/Tests/DevHavenAppTests/GhosttySurfaceRepresentableUpdatePolicyTests.swift tasks/todo.md` → 通过。

## 新增 ./release 原生打包入口（2026-03-21）

- [x] 对照现有 `./dev` 与 `macos/scripts/build-native-app.sh`，确认新入口的最小职责边界
- [x] 确认 `./release` 的行为与参数范围，避免把发布包装脚本做成另一套复杂构建系统
- [x] 实现仓库根 `./release` 入口，并补充必要文档
- [x] 运行定向验证并在 `tasks/todo.md` 追加 Review

## Review（新增 ./release 原生打包入口）

- 直接原因：仓库根目录已经有 `./dev` 作为原生开发态入口，但本地 release 打包仍要求手动记忆并输入 `bash macos/scripts/build-native-app.sh --release`；同时这次给 `./release` 补回归测试时又暴露出 `build-native-app.sh --help` 本身存在 heredoc 帮助文案展开错误，导致入口链上的帮助信息也不可靠。
- 设计层诱因：存在，但属于轻量工具链边界问题。开发入口和打包入口没有在仓库根统一收口，导致“运行用 `./dev`、打包用长命令”的体验分裂；另外包装脚本如果继续复制一套参数解析，也会把打包真相源拆成两份。未发现更大的系统设计缺陷。
- 当前修复：
  1. 新增仓库根 `./release`，固定在仓库根目录执行 `bash macos/scripts/build-native-app.sh --release`，并透传其余参数；
  2. `./release` 显式拒绝 `--debug`，避免 release 入口被悄悄降级成 debug 打包；
  3. 新增 `macos/scripts/test-release-command.sh`，锁定“透传参数 + 固定带 `--release` + 拒绝 `--debug` + `--help` 可用”这几条边界；
  4. 修复 `macos/scripts/build-native-app.sh --help` 的文案展开问题，避免 heredoc 中的反引号和默认值变量把帮助输出本身炸掉；
  5. `README.md` 与 `AGENTS.md` 同步补充 `./release` 入口说明，保持仓库结构与使用文档一致。
- 长期建议：后续如果还要加别的仓库根入口，继续保持“根入口只做 thin wrapper，真正逻辑仍收口到单一脚本/模块”这条边界；不要把 `./release` 再扩成第二套打包系统。
- 验证证据：
  - TDD 红灯：`bash macos/scripts/test-release-command.sh` 在实现前失败，报 `/Users/zhaotianzeng/WebstormProjects/DevHaven/release: No such file or directory`。
  - 定向绿灯：`bash macos/scripts/test-release-command.sh` → 通过，输出 `release command smoke ok`。
  - 帮助验证：`bash macos/scripts/build-native-app.sh --help` → 通过，正确打印帮助文案。
  - 行为验证：`./release --no-open --output-dir /tmp/devhaven-release-verify` → 通过，产物为 `/tmp/devhaven-release-verify/DevHaven.app`。
  - 差异校验：`git diff --check` → 通过。

## 修复终端粘贴图片文件路径缺失（2026-03-21）

- [x] 先确认当前仓库已有未提交改动的隔离边界，避免混入字体 / 分屏等其他任务
- [x] 写失败测试，锁定 Ghostty 风格的 file URL / utf8 plain text 粘贴预期
- [x] 以最小改动补齐 Ghostty 风格 pasteboard helper，并接入 `GhosttyRuntime.handleReadClipboard(...)`
- [x] 运行定向验证，并同步 `tasks/todo.md`、必要文档与 `AGENTS.md`

## Review（修复终端粘贴图片文件路径缺失）

- 直接原因：`GhosttyRuntime.handleReadClipboard(...)` 之前只读取 `NSPasteboard.string(forType: .string)`。当用户从 Finder 或其他宿主复制图片文件时，剪贴板常见真相源是 file URL 或 `public.utf8-plain-text`，不是 `.string`，所以终端最终收到的是空串，连图片文件路径都粘贴不进去。
- 设计层诱因：Ghostty clipboard 语义此前被收窄成了“只认 plain string”，没有把 file URL / utf8 plain text 这些终端真实会遇到的 pasteboard 形态统一收口。问题集中在剪贴板桥接边界；未发现更大的系统设计缺陷。
- 当前修复：
  - 新增 `macos/Sources/DevHavenApp/Ghostty/GhosttyPasteboard.swift`，按 Ghostty 原生结构收口 pasteboard 语义：优先 file URL，回退 `.string` 与 `public.utf8-plain-text`，并对文件路径做 shell escape；
  - `GhosttyRuntime.handleReadClipboard(...)` 改为通过 `NSPasteboard.ghostty(location)?.getOpinionatedStringContents()` 读取剪贴板；
  - `AGENTS.md` 同步补充 `GhosttyPasteboard.swift` 的职责说明；
  - 新增 `GhosttyPasteboardTests` 锁定 file URL 与 utf8 plain text 两条回归预期。
- 长期建议：如果后续用户继续追求“截图本体也能粘进去”，那已经超出 Ghostty 原生路径粘贴边界，应另起一层做 cmux 那种“图片物化为临时文件/远端上传后再注入路径”的宿主增强；不要把图片附件语义继续塞回这个 Ghostty 对齐 helper。
- 验证证据：
  - TDD 红灯：`swift test --package-path macos --filter GhosttyPasteboardTests` → 初次失败，报 `value of type 'NSPasteboard' has no member 'getOpinionatedStringContents'`。
  - 定向绿灯：`swift test --package-path macos --filter GhosttyPasteboardTests` → 通过，`2 tests, 0 failures`。
  - 差异校验：`git diff --check` → 通过。
  - 隔离边界：当前仓库还存在与本任务无关的既有改动（如 `README.md`、`GhosttySurfaceHost.swift`、`GhosttySurfaceView.swift` 等），本轮仅新增/修改 Ghostty pasteboard 对齐相关文件与任务文档。

## 修复 ./dev 启动时字体丢失（2026-03-21)

- [x] 先确认当前仓库已有未提交改动的隔离边界，避免混入其他任务
- [x] 复现 `./dev` 启动时字体丢失的链路，并区分是 UI 字体还是 Ghostty 终端字体
- [x] 对照 `./dev` 启动脚本、Ghostty runtime 与字体资源定位逻辑，锁定直接原因与设计诱因
- [x] 以最小改动修复根因，并补充必要测试/文档
- [x] 运行定向验证并在 `tasks/todo.md` 追加 Review

## Review（修复 ./dev 启动时字体丢失）

- 直接原因：`GhosttyRuntime` 之前直接调用 `ghostty_config_load_default_files(config)`，而当前 `GhosttyKit` binary target 是按 `com.mitchellh.ghostty` 构建的。结果 DevHaven 在 `./dev` 启动时会跟着 Ghostty 默认搜索路径去读取 `~/Library/Application Support/com.mitchellh.ghostty/config`。本机该文件里显式配置了 `font-family = Hack`、`font-family = Noto Sans SC`，但用 CoreText 枚举实际可用字体后，这两个字体在当前系统都不存在，于是嵌入式终端继承了一套无效字体栈，表现成“字体丢失”。
- 设计层诱因：存在。问题不是 `./dev` 脚本本身，而是**DevHaven 内嵌终端的配置真相源错误地依赖了独立 Ghostty App 的全局配置目录**，导致一个外部应用的字体 / 主题 / 键位配置泄漏进 DevHaven。未发现更大的系统设计缺陷，问题集中在 Ghostty runtime 这层边界没有收口到 DevHaven 自己的数据目录。
- 当前修复：
  1. `GhosttyRuntime` 不再调用 `ghostty_config_load_default_files`，改为只读取 `~/.devhaven/ghostty/config` 与 `~/.devhaven/ghostty/config.ghostty`；
  2. 保留 `ghostty_config_load_recursive_files`，让 DevHaven 自己的配置文件仍可通过 `config-file` 继续拆分；
  3. 新增 `GhosttyRuntimeConfigLoaderTests`，锁定“即使存在独立 Ghostty 的全局配置，DevHaven 也不应去读取它”这条回归边界；
  4. `AGENTS.md` / `README.md` 同步补充新的配置入口，避免后续再次把字体问题排到独立 Ghostty 配置上。
- 长期建议：如果后续要把终端字体、主题或键位暴露到设置页，应该继续以 `~/.devhaven/ghostty/config*` 为唯一真相源，并在应用内明确支持哪些选项；不要再让独立 Ghostty App 的全局配置影响 DevHaven。
- 验证证据：
  - 复现前证据：
    - `./dev` 旧日志里出现 `reading configuration file path=/Users/zhaotianzeng/Library/Application Support/com.mitchellh.ghostty/config`；
    - `swift -e 'import Foundation; import CoreText; ...'` 输出 `Hack: false`、`Hack Nerd Font: false`、`Noto Sans SC: false`；
    - `~/Library/Application Support/com.mitchellh.ghostty/config` 里确有 `font-family = Hack`、`font-family = Noto Sans SC`。
  - TDD 红灯：`swift test --package-path macos --filter GhosttyRuntimeConfigLoaderTests/testEmbeddedConfigFileURLsIgnoreStandaloneGhosttyAppSupportConfig` 初次失败，报 `type 'GhosttyRuntime' has no member 'embeddedConfigFileURLs'`。
  - 定向绿灯：同一条测试修复后通过，`1 test, 0 failures`。
  - 行为验证：用 Python 包装 `./dev --logs ghostty` 启动 8 秒后采样，输出 `HAS_STANDALONE_CONFIG_PATH=False`、`HAS_CONFIG_READ_LOG=False`，且日志尾部不再出现 `reading configuration file path=...com.mitchellh.ghostty/config`。
  - 全量验证：`swift test --package-path macos` → 通过，`112 tests, 5 skipped, 0 failures`。
  - 差异校验：`git diff --check` → 通过。

## 调研 Codex 截图粘贴与 Ghostty / Supacode / cmux 图片处理（2026-03-21）

- [x] 快速核对当前 DevHaven 与记忆里的 Ghostty / Supacode / cmux 上下文，避免沿旧栈误判
- [x] 查证 Ghostty 对剪贴板图片、终端图片协议与 paste action 的真实边界
- [x] 查证 Supacode / cmux 在截图输入上的实际实现路径，区分“终端粘贴”与“宿主附件上传”
- [x] 结合运行中的 Codex 形态给出直接原因、设计层诱因、当前建议与长期方案

## Review（调研 Codex 截图粘贴与 Ghostty / Supacode / cmux 图片处理）

- 直接原因：运行中的 Codex 本质上还是跑在 Ghostty/libghostty 承载的终端里，而当前 DevHaven 自己的 `GhosttyRuntime.handleReadClipboard(...)` 只从 `NSPasteboard` 读取 `.string`，没有任何图片 MIME、HTML/RTFD 附件或拖拽图片的宿主级转换逻辑；因此截图在剪贴板里若只有图片数据，终端 paste 回调就只能拿到空字符串。
- 设计层诱因：这不是单纯“Ghostty 少一个开关”，而是“终端文本粘贴”和“AI 客户端图片附件”两种语义被混为一谈。Ghostty / Supacode 的默认边界仍然是“把可表示成文本的东西送进终端”；若产品要支持给 Codex 贴截图，必须由宿主在终端外做图片物化 / 上传 / 路径注入，而不能指望 libghostty 原生帮你把剪贴板图片变成 Codex 可理解的附件。
- 当前结论：
  - Ghostty 原生 macOS：`getOpinionatedStringContents()` 只处理 file URL 和 string；拖拽也只注册 `.string/.fileURL/.URL`，不处理图片剪贴板。
  - Supacode：沿用同样的 Ghostty 语义；终端 paste 和 drop 都是 string/file URL 路径，不做截图图片粘贴增强。
  - cmux：额外实现了终端图片粘贴增强。它会识别剪贴板里的纯图片或仅图片附件的 HTML/RTFD，把图片落到临时 `clipboard-*` 文件，再根据目标终端是本地还是远端，分别“直接把本地路径插入终端”或“先上传再把远端路径插入终端”；拖拽图片也是同一套思路。
  - DevHaven 当前状态比 Ghostty / Supacode 还更窄：目前只读 `.string`，连 file URL / HTML 富文本兜底都还没接入，所以“无法粘贴截图”在现状下是符合代码现状的，不是偶发异常。
- 长期建议：
  - 如果目标是“终端里的 Codex 能像附件一样接收截图”，优先按 cmux 方案做宿主增强：图片剪贴板 -> 临时文件 -> 本地路径注入 / 远端上传后注入远端路径。
  - 如果后续还要支持浏览器 pane / WebView 里的真正二进制图片复制粘贴，可以另走 cmux `CmuxWebView` 那条 browser pasteboard 路线；不要试图把“浏览器图片附件语义”和“终端文本 paste 语义”强行塞进同一层 Ghostty callback。
- 验证证据：
  - DevHaven：`macos/Sources/DevHavenApp/Ghostty/GhosttyRuntime.swift:260-312`
  - Ghostty：`ghostty/macos/Sources/Helpers/Extensions/NSPasteboard+Extension.swift:35-48`、`ghostty/macos/Sources/Ghostty/Ghostty.App.swift:325-338`、`ghostty/macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift:2091-2128`、`ghostty/src/apprt/gtk/class/surface.zig:3764-3771`
  - Supacode：`supacode/Infrastructure/Ghostty/GhosttyRuntime.swift:388-423,616-625`、`supacode/Infrastructure/Ghostty/GhosttySurfaceView.swift:126-129,1355-1378`
  - cmux：`cmux/Sources/GhosttyTerminalView.swift:73-367,1085-1168,3878-3887,6284-6362`、`cmux/Sources/TerminalImageTransfer.swift:112-160`、`cmux/cmuxTests/TerminalAndGhosttyTests.swift:38-58,196-253`、`cmux/CHANGELOG.md:63`

## 修复 workspace 分屏时旧 pane 偶发不显示（2026-03-21）

- [x] 先确认当前仓库已有未提交改动的隔离边界，避免混入 worktree 删除任务
- [x] 复盘 split/tree/surface 可见性链路，定位旧 pane 偶发不显示的直接原因
- [x] 先补失败测试锁定“分屏后旧 pane 仍应保持挂载与可见”预期
- [x] 以最小改动修复根因，并运行定向与全量验证
- [x] 在 `tasks/todo.md` 追加 Review，写明原因、修复、验证证据与长期建议

## Review（修复 workspace 分屏时旧 pane 偶发不显示）

- 直接原因：上一轮 `WorkspaceSplitTreeView` 已经去掉 structural re-key，避免 split/tree 重排时整棵 subtree 被强制 remount；但当前 `GhosttySurfaceHostModel` 复用的只有 `GhosttyTerminalSurfaceView` 本体。旧 pane 在 split/tree 发生挂载迁移时，surface 会继续被复用，但 `GhosttyTerminalSurfaceView` 内部缓存的 `lastOcclusion`、`lastSurfaceFocus`、`lastBackingSize` 仍保留旧容器状态，导致重新挂到新容器后不会重发 occlusion / focus / resize，同一个 pane 就可能出现“树里还在，但画面没重新出来”的偶发空白。
- 设计层诱因：存在。这不是 split 拓扑再次算错，而是 **surface 复用边界只收口到了“不要销毁 terminal view”，却没有把“容器迁移后必须刷新挂载敏感状态”一起收口**。也就是说，生命周期主线已经保护了 `/usr/bin/login` 不重跑，但 AppKit/Ghostty 这层 attachment-sensitive state 仍然分散在 `GhosttySurfaceView` 内部缓存里。未发现更大的系统设计缺陷，问题集中在这条复用边界还差最后一步。
- 当前修复：
  1. 新增 `GhosttySurfaceAttachmentState.swift`，把 `lastOcclusion`、`lastSurfaceFocus`、`lastBackingSize` 收口成显式状态对象，并提供 `prepareForContainerReuse()`。
  2. `GhosttyTerminalSurfaceView` 在 `tearDown()` 和新的 `prepareForContainerReuse()` 中都会清空这三类挂载敏感缓存；`setOcclusion` / `setSurfaceFocus` / `updateSurfaceMetrics` 改为统一读写该状态。
  3. `GhosttySurfaceHostModel.acquireSurfaceView(...)` 在复用既有 `ownedSurfaceView` 前，先调用 `prepareForContainerReuse()`，再重放缓存的可见性 / 焦点 / 尺寸同步，确保 split/tree remount 后旧 pane 能重新收到一次有效 attach 信号。
  4. 新增 `GhosttySurfaceScrollViewTests.testAttachmentStateResetForContainerReuseClearsVisibilityFocusAndResizeCaches`，用 RED -> GREEN 锁住“容器复用前必须清空 attachment-sensitive caches”这条回归边界。
- 长期建议：后续凡是继续优化 split/tree/zoom/tab 切换时的 Ghostty 复用，都要把问题拆成两层分别看：一层是 `WorkspaceTerminalSessionStore` 是否还在错误释放 surface；另一层是 **即便 surface 没被释放，容器迁移后是否有 attachment refresh**。不要只看“有没有重新 `/usr/bin/login`”，因为“surface 存活但缓存未刷新”同样会表现成 pane 黑掉或空白。
- 验证证据：
  - TDD 红灯：`swift test --package-path macos --filter GhosttySurfaceScrollViewTests` 初次失败，报 `cannot find 'GhosttySurfaceAttachmentState' in scope`，证明新测试先锁住了待实现边界。
  - 定向验证：`swift test --package-path macos --filter 'WorkspaceTopologyTests|GhosttyWorkspaceControllerTests|WorkspaceTerminalSessionStoreTests|WorkspaceSplitTreeViewKeyPolicyTests|WorkspaceSurfaceActivityPolicyTests|GhosttySurfaceScrollViewTests'` → 通过，24 tests, 0 failures。
  - 全量验证：`swift test --package-path macos` → 通过，`111 tests, 5 skipped, 0 failures`。
  - 构建验证：`swift build --package-path macos` → 通过。
  - 差异校验：`git diff --check` → 通过。
  - 当前边界：本轮已经补齐了代码级 root-cause 与自动化回归，但还没有新的实机 GUI 录屏/截图证据；是否完全消除你看到的“旧 pane 不显示”，仍建议你本机再分两三次屏确认一下。

## 修复删除 dirty worktree 时被 Git 拒绝（2026-03-21）

- [x] 复现并确认 `git worktree remove` 在 modified / untracked 场景下的失败行为
- [x] 先补失败测试，锁定删除 dirty worktree 的预期
- [x] 以最小改动修复删除逻辑与必要文案
- [x] 运行定向与全量验证，并追加 Review

## Review（修复删除 dirty worktree 时被 Git 拒绝）

- 直接原因：`NativeGitWorktreeService.removeWorktree(...)` 之前直接执行 `git worktree remove <path>`。Git 在 worktree 内存在 modified / untracked 文件时会按默认安全策略拒绝删除，并返回 `fatal: '.../swift' contains modified or untracked files, use --force to delete it`，所以 DevHaven 的“删除 worktree”会直接失败。
- 设计层诱因：产品语义和底层 Git 语义没有收口。UI 已经把这个入口定义成显式 destructive delete，但服务层仍保留 Git 的“仅允许删除干净 worktree”默认策略，同时确认文案也没有提前说明会如何处理未提交改动。这是一个局部边界不一致；未发现更大的系统设计缺陷。
- 当前修复：
  - `NativeGitWorktreeService` 删除 worktree 时改为执行 `git worktree remove --force <path>`，让显式删除动作可以按预期回收 dirty worktree；
  - 保留原有 `worktree prune` fallback 和“删除对应本地分支”的后续处理；
  - `WorkspaceShellView` 的确认文案同步补充“会丢弃未提交修改与未跟踪文件”，把 destructive 语义显式告诉用户。
- 长期建议：如果后续想给用户保留更多控制权，下一步应考虑把删除分成“取消 / 强制删除”两条显式路径，或在确认弹窗里先展示 dirty-state 预检结果；但当前这类单按钮 destructive flow 不应再把裸 Git fatal 暴露给用户。
- 验证证据：
  - 复现脚本：临时仓库里执行 `git worktree remove "$wt"`，在 worktree 含修改和未跟踪文件时稳定复现 `EXIT_CODE=128` 与 `contains modified or untracked files, use --force to delete it`。
  - TDD 红灯：`swift test --package-path macos --filter NativeWorktreeServiceTests/testRemoveWorktreeForceDeletesDirtyManagedWorktree` → 修复前失败，报 `contains modified or untracked files, use --force to delete it`。
  - 定向绿灯：`swift test --package-path macos --filter NativeWorktreeServiceTests/testRemoveWorktreeForceDeletesDirtyManagedWorktree` → 通过，`1 test, 0 failures`。
  - 全量验证：`swift test --package-path macos` → 通过，`110 tests, 5 skipped, 0 failures`。
  - 差异校验：`git diff --check` → 通过。

## DevHaven 3.0.0 仓库收口为纯 macOS 原生主线（2026-03-20）

- [x] 保护当前工作区并核对 merge 前状态
- [x] 将 `swift` 合并到 `main`
- [x] 切换版本真相源到 `macos/Resources/AppMetadata.json`
- [x] 下线 Tauri / Node / pnpm 发布链路
- [x] 删除旧的 React / Vite / Tauri / Rust 兼容源码与构建配置
- [x] 清理历史实施文档与旧版本 release note
- [x] 同步更新 `README.md`、`AGENTS.md`、原生设置文案与 release note
- [x] 运行原生测试与原生打包验证

## Review（DevHaven 3.0.0 纯 macOS 原生主线收口）

- 合并结果：已在 `main` 上完成 `swift` 分支合并，merge commit 为 `5e50a98`（`Merge branch 'swift'`）。
- 仓库结构结果：旧的 `src/`、`src-tauri/`、`scripts/`、`public/` 以及 `package.json` / `pnpm-lock.yaml` / `vite.config.ts` 等旧构建配置已从仓库删除；当前源码仅保留 `macos/` 原生主线。
- 版本结果：版本真相源已切换到 `macos/Resources/AppMetadata.json`，当前版本为 `3.0.0`。
- 发布结果：`.github/workflows/release.yml` 已收口为纯 Swift/macOS 原生链路，只保留 `swift test --package-path macos`、原生 `.app` 构建、压缩与 release asset 上传。
- 文档结果：`README.md`、`AGENTS.md`、`docs/releases/v3.0.0.md` 已更新为原生主线口径；旧的 `docs/plans/`、旧版 release note、`work.md`、`PLAN.md` 已删除。
- 设计层判断：本轮真正的系统性问题是“发布链、仓库结构、版本真相源、历史文档四套边界长期不一致”。现在已经把源码、打包、版本和文档统一收口到 `macos/` 原生主线。
- 验证证据：
  - `swift test --package-path macos` → 通过，`105 tests, 5 skipped, 0 failures`。
  - `bash macos/scripts/setup-ghostty-framework.sh --source /Users/zhaotianzeng/Documents/business/tianzeng/ghostty --skip-build` → 通过，仅用于本机准备 `macos/Vendor/**`。
  - `bash macos/scripts/build-native-app.sh --release --no-open --output-dir /tmp/devhaven-native-app-verify-pure` → 通过，产物为 `/tmp/devhaven-native-app-verify-pure/DevHaven.app`。
  - `git diff --check` → 通过。

## 修复 GitHub Release 缺少 Ghostty vendor 导致的 `swift test` 失败（2026-03-20）

- [x] 复现干净 checkout 下的 `GhosttyKit` binary target 报错
- [x] 收口 CI bootstrap 方案并更新 workflow / 文档
- [x] 重新验证“干净 checkout + 准备 vendor + swift test / 原生打包”链路

## Review（GitHub Release Ghostty vendor bootstrap）

- 直接原因：`macos/Package.swift` 通过本地 `binaryTarget(path: "Vendor/GhosttyKit.xcframework")` 依赖 GhosttyKit，但 `macos/Vendor/` 被 `.gitignore` 忽略，GitHub Actions 的干净 checkout 在 `swift test --package-path macos` 前没有有效的二进制产物，因此直接报错 `does not contain a binary artifact`。
- 设计层诱因：发布 workflow 虽然已经切到纯 Swift/macOS，但仍把“本机已准备好 Ghostty vendor”当成默认前提；也就是说，Swift Package 的 binary target 真相源和 CI 的准备链路是脱节的。
- 当前修复：`.github/workflows/release.yml` 现在会先安装 Zig，再 `git fetch` 固定 commit `da10707f93104c5466cd4e64b80ff48f789238a0` 的 Ghostty 源码，执行 `bash macos/scripts/setup-ghostty-framework.sh --source "$RUNNER_TEMP/ghostty"` 准备临时 `macos/Vendor/`，然后再运行 `swift test` 和原生打包；`README.md`、`AGENTS.md`、`tasks/lessons.md` 已同步更新说明。
- 长期建议：后续如果继续升级 Ghostty 版本，必须把“上游 commit pin + CI bootstrap + 本地开发说明”视为同一组变更一起维护，避免再次出现“本机能过、干净 checkout 直接炸”的问题。
- 验证证据：
  - 干净 worktree 直接执行 `swift test --package-path macos` → 复现失败：`local binary target 'GhosttyKit' ... does not contain a binary artifact`。
  - `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release.yml")'` → 通过，确认 workflow YAML 合法。
  - 在干净 worktree 内按 workflow 新链路执行：
    - `git init "$RUNNER_TEMP/ghostty" && git -C "$RUNNER_TEMP/ghostty" fetch --depth 1 origin da10707f93104c5466cd4e64b80ff48f789238a0 && git -C "$RUNNER_TEMP/ghostty" checkout --detach FETCH_HEAD`
    - `bash macos/scripts/setup-ghostty-framework.sh --source "$RUNNER_TEMP/ghostty"`
    - `swift test --package-path macos`
    - `bash macos/scripts/build-native-app.sh --release --no-open --output-dir "$RUNNER_TEMP/native-app"`
  - 上述整条链路 → 通过，`105 tests, 5 skipped, 0 failures`，并产出 `/tmp/devhaven-workflow-verify-git-36433/.runner-temp/native-app/DevHaven.app`。
  - `git diff --check` → 通过。

## 修复 GitHub Actions 上 Ghostty 在 Xcode 16.4 编译失败（2026-03-20）

- [x] 拉取最新失败 run 并定位实际失败 step
- [x] 确认 root cause 为 runner Xcode 版本落后而非 vendor bootstrap 逻辑错误
- [x] 将 release workflow 切到 `macos-26` 并增加 Xcode 版本诊断输出
- [x] commit / push 并重打 `v3.0.0` 触发新的 release run
- [x] 检查新 run 是否成功起跑

## Review（GitHub Actions Xcode toolchain 对齐）

- 直接原因：最新失败 run `23343818716` 虽然已经成功完成 Ghostty 源码 checkout，但在 `Bootstrap Ghostty vendor` 阶段执行 `cd /Users/runner/work/_temp/ghostty/macos && xcodebuild -target Ghostty -configuration ReleaseLocal` 时退出 `code 65`，日志明确显示使用的是 `/Applications/Xcode_16.4.app/...`。
- 设计层诱因：上一轮只把“CI 缺失 Ghostty vendor bootstrap”补齐了，但没有把 GitHub runner 的 Xcode 主版本与当前 Ghostty 上游的构建要求一起锁定；结果变成“vendor 链路对了，工具链版本又漂移了”。
- 当前修复：`.github/workflows/release.yml` 已把 release runner 从 `macos-latest` 改成 `macos-26`，并新增 `Print Xcode version` 步骤输出 `xcodebuild -version`，用于让日志直接暴露实际工具链版本。
- 长期建议：后续只要升级 Ghostty commit 或切换 GitHub runner 标签，都要把“上游 commit pin / runner OS / Xcode 主版本 / 本地验证环境”作为同一组约束维护，而不是只盯单个脚本。
- 新进展（2026-03-20）：
  - `git push origin main` → 已成功把修复提交 `dd46da5` 推到远端。
  - `git tag -fa v3.0.0 -m "v3.0.0"` + `git push origin refs/tags/v3.0.0 --force` → 已成功把 `v3.0.0` 重指到 `dd46da5` 并推送远端。
  - `gh run list --workflow release.yml --limit 5 ...` → 新 run `23346369319` 已于 `2026-03-20T14:03:39Z` 起跑，当前 URL：`https://github.com/zxcvbnmzsedr/devhaven/actions/runs/23346369319`。

## 修复 GitHub workflow 产物启动即崩（2026-03-20）

- [x] 对照 crash log 与 Supacode 打包方式定位资源加载断裂点
- [x] 调整 `GhosttyAppRuntime` 的资源 bundle 定位逻辑并补回归测试
- [x] 验证原生测试、`.app` 布局、原生打包与启动 smoke test

## Review（GitHub workflow 产物启动即崩）

- 直接原因：GitHub workflow 产出的 `.app` 在启动时崩在 `static NSBundle.module` 初始化，说明运行时没有按 SwiftPM 期望的方式找到 `DevHavenNative_DevHavenApp.bundle`。`build-native-app.sh` 会把该 bundle 复制到 `DevHaven.app/Contents/Resources/`，但旧版 `GhosttyAppRuntime` 仍直接依赖 `Bundle.module`，导致打包后的应用在初始化 `GhosttyResources/ghostty` 时触发断言并直接崩溃。
- 设计层诱因：当前 release 仍是“SwiftPM executable + 手工组装 `.app`”模式，资源拷贝路径由打包脚本掌控，而运行时资源定位却交给 `Bundle.module` 的默认实现；也就是**打包布局真相源**和**运行时资源查找真相源**分裂了。未发现更大的系统设计缺陷，问题集中在这一处边界没有显式收口。
- 当前修复：
  - `GhosttyAppRuntime` 新增显式资源 bundle 定位逻辑，优先解析 `Bundle.main.resourceURL/DevHavenNative_DevHavenApp.bundle`，并兼容测试环境下的 sibling bundle fallback；
  - 新增 `GhosttyAppRuntimeBundleLocatorTests`，锁定“打包产物优先从 `Contents/Resources` 取 bundle”和“测试环境可从同级目录 fallback”两条路径；
  - 新增 `macos/scripts/test-native-app-layout.sh`，持续检查 `.app` 中资源 bundle 的实际落点；
  - 保持资源 bundle 放在 `Contents/Resources/`，不再尝试复制到 `.app` 根目录，避免 `codesign --verify --deep --strict` 报 `unsealed contents present in the bundle root`。
- Supacode 对照：Supacode 走 `xcodebuild archive/exportArchive`，资源通过 Xcode `PBXResourcesBuildPhase` 进入 `Contents/Resources/`，运行时直接按 `Bundle.main.resourceURL/...` 读取 `ghostty` / `terminfo` / `git-wt`。这次修复本质上是把 DevHaven 的运行时资源解析边界也收口到同样稳定的 app resources 语义上，而不是继续赌 `Bundle.module` 在手工组装 `.app` 时能自动对齐。
- 长期建议：如果后续继续沿用 SwiftPM executable + 手工 `.app` 组装路线，凡是要在发布版读取的资源，都应像这次一样显式绑定到最终 app 布局；不要让“构建时生成 bundle”和“运行时查找 bundle”分属两套默认约定。
- 验证证据：
  - `swift test --package-path macos` → 通过，`107 tests, 5 skipped, 0 failures`。
  - `bash macos/scripts/test-native-app-layout.sh` → 通过，确认资源 bundle 位于 `DevHaven.app/Contents/Resources/DevHavenNative_DevHavenApp.bundle`，且 app 根目录不存在非法副本。
  - `bash macos/scripts/build-native-app.sh --release --no-open --output-dir /tmp/devhaven-native-app-verify-launch-fix` → 通过，产物为 `/tmp/devhaven-native-app-verify-launch-fix/DevHaven.app`，脚本内 `codesign --verify --deep --strict` 通过。
  - 启动 smoke test：直接执行 `/tmp/devhaven-native-app-verify-launch-fix/DevHaven.app/Contents/MacOS/DevHavenApp`，5 秒后进程仍存活，输出 `STATUS=running_after_5s`，未再出现启动即崩。
- 额外核对：Supacode 安装产物 `/Applications/supacode.app/Contents/Resources/` 下确实存在 `ghostty`、`terminfo`、`git-wt`，与本次对照结论一致。

## 扩展 GitHub release 为 arm64 + x86_64 双产物（2026-03-21）

- [x] 确认当前单产物 release 只会跟随 runner 架构输出 arm64
- [x] 设计 dual-arch release 方案并记录到 `docs/plans/2026-03-21-devhaven-release-dual-arch.md`
- [x] 修改 `.github/workflows/release.yml` 为 arm64 / x86_64 matrix
- [x] 同步更新 `AGENTS.md` 的发布主链说明
- [x] 校验 workflow YAML 与本地 x86_64 构建验证

## Review（GitHub release dual-arch）

- 直接原因：当前 `.github/workflows/release.yml` 只有单个 `build-macos-native` job，且固定 `runs-on: macos-26`；`build-native-app.sh` 又直接调用不带 `--triple` 的 `swift build`，所以 release 产物天然跟随 runner 架构，只会产出 `arm64` 包。
- 设计层诱因：发布链原先把“目标架构”隐式绑定在 runner 上，但 release asset 名称却没有编码架构信息。这种做法在单 runner 时代问题不明显，一旦扩成多架构发布，构建真相源和发布资产命名就会发生冲突。
- 当前修复：
  - `.github/workflows/release.yml` 现在改为 matrix，同时跑 `arm64/macos-26` 与 `x86_64/macos-15-intel`；
  - 保持 `setup-ghostty-framework.sh`、`swift test --package-path macos`、`build-native-app.sh` 主链不变，不在本轮给脚本再加一套额外架构分支；
  - release asset 名称改成 `DevHaven-macos-arm64.zip` 和 `DevHaven-macos-x86_64.zip`，避免两个 job 互相覆盖。
- 长期建议：后续如果要继续做 universal 包，再单独评估“matrix 双包”与“lipo 合包”谁是正式发行策略；在这之前，不要把 runner 架构、target triple 和 release asset 命名继续混在一起。
- 验证证据：
  - `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release.yml"); puts "yaml ok"'` → 通过，输出 `yaml ok`。
  - `swift build --package-path macos -c release --triple x86_64-apple-macosx14.0` → 通过。
  - `file /Users/zhaotianzeng/WebstormProjects/DevHaven/macos/.build/x86_64-apple-macosx/release/DevHavenApp` → 输出 `Mach-O 64-bit executable x86_64`。
  - `git diff --check` → 通过。

## 修复 dual-arch release 中 Intel hosted runner 编译失败（2026-03-21）

- [x] 拉取失败 run `23365597633` 的 x86_64 job 日志并确认失败步骤
- [x] 对照 arm64 成功链与 Ghostty 上游要求定位根因
- [x] 改为 `macos-26` 上交叉构建 x86_64，并重新验证 workflow / 本地打包

## Review（Intel hosted runner 编译失败）

- 直接原因：失败 run `23365597633` 里的 `build-macos-native (x86_64, macos-15-intel)` 在 `Bootstrap Ghostty vendor` 阶段失败；日志显示该 job 使用的是 `Xcode 16.4 (Build version 16F6)`，并在 `cd /Users/runner/work/_temp/ghostty/macos && xcodebuild -target Ghostty -configuration ReleaseLocal` 时以 `code 65` 退出。arm64 job 同一时间跑在 `macos-26` 上则成功，说明失败点不在 DevHaven 自己的 Swift 包，而在 Ghostty 上游 bootstrap 所依赖的 Intel runner 工具链。
- 设计层诱因：上一轮把“目标 CPU 架构”直接等同于“必须使用同构 GitHub runner”。这对纯 Swift 可执行文件未必是必须的，但对 Ghostty 这种先用较新 Xcode 构建 vendor、再由下游应用复用产物的链路，会把“目标架构”和“可用工具链版本”错误耦合在一起。
- 当前修复：
  - release workflow 仍保留 `arm64` / `x86_64` 双产物，但二者都改在 `macos-26` 上跑；
  - `x86_64` 产物不再依赖 `macos-15-intel`，而是通过 `x86_64-apple-macosx14.0` triple 在 `macos-26` 上交叉构建；
  - `build-native-app.sh` 新增可选 `--triple` / `DEVHAVEN_NATIVE_TRIPLE`，用于让 workflow 在不分叉主脚本的前提下产出 x86_64 `.app`；
  - `x86_64` 这条 CI 验证改为“编译+打包验证”，不再尝试在 arm runner 上执行 x86_64 test bundle。
- 长期建议：只要上游 vendor bootstrap 对 Xcode 主版本敏感，就不要再把“构建 x86_64 目标”简单理解成“必须用 Intel hosted runner”。先看可用工具链，再决定是同构 runner、交叉编译，还是自托管机器。
- 验证证据：
  - `gh run view 23365597633 --job 67978750279 --log` → 确认失败 job 为 `build-macos-native (x86_64, macos-15-intel)`，失败步骤是 `Bootstrap Ghostty vendor`。
  - 同日志中的 `Print Xcode version` → 明确显示 `Xcode 16.4 / Build version 16F6`。
  - `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release.yml"); puts "yaml ok"'` → 通过，输出 `yaml ok`。
  - `swift test --package-path macos` → 通过，`107 tests, 5 skipped, 0 failures`。
  - `bash macos/scripts/build-native-app.sh --release --no-open --triple x86_64-apple-macosx14.0 --output-dir /tmp/devhaven-native-app-x86-cross-verify` → 通过。
  - `file /tmp/devhaven-native-app-x86-cross-verify/DevHaven.app/Contents/MacOS/DevHavenApp` → 输出 `Mach-O 64-bit executable x86_64`。

## 滚动优化：对齐 Ghostty 原生 / Supacode 滚动语义（2026-03-21）

- [x] 检查当前 Ghostty 宿主的滚动事件链与速度来源
- [x] 对照 Ghostty 原生与 Supacode 的滚动包装/节流策略
- [x] 确认最小修复方案并完成验证

## Review（Ghostty scroll 输入桥对齐）

- 直接原因：`GhosttySurfaceView.scrollWheel(with:)` 直接把 `scrollingDeltaX/Y` 原样传给 `ghostty_surface_mouse_scroll(...)`，并把键盘 modifiers 误当成 `ghostty_input_scroll_mods_t` 传入，导致 trackpad 这类高精度滚动事件没有被正确标记为 `precision + momentum`；Ghostty core 因此会把本应走 precision 路径的输入按 discrete scroll 解释，体感表现为“滚得特别快”。
- 设计层诱因：问题不在 `GhosttySurfaceScrollView` wrapper 主线，而在输入桥接边界把“键盘/鼠标修饰键 mods”和“滚动专用 scroll mods”混成了一种 bitfield。未发现更大的系统设计缺陷，当前是局部输入语义接线偏离 Ghostty / Supacode 参考实现。
- 当前修复：
  - 新增 `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceScrollInput.swift`，把 precise scroll 的 delta 调整与 `precision + momentumPhase` 编码收口成可测试 helper；
  - `GhosttySurfaceView.scrollWheel(with:)` 改为使用该 helper，precise scrolling 对齐 Ghostty 原生 / Supacode 的 `x2` delta 规则，并正确传入 `ghostty_input_scroll_mods_t`；
  - 移除原先会误导实现的 `ghosttyScrollMods` 旧接线。
- 长期建议：后续所有 Ghostty 输入问题优先做 source-to-source diff，对照 Ghostty 原生和 Supacode 的桥接细节；不要先在 `GhosttySurfaceScrollView` 或 SwiftUI 外层做人为减速补丁，否则容易掩盖真正的输入语义错误。
- 验证证据：
  - TDD 红灯：`swift test --package-path macos --filter GhosttySurfaceScrollInputTests` → 先失败，报 `cannot find 'GhosttySurfaceScrollInput' in scope`，证明新增测试确实锁住了待实现行为；
  - 定向绿灯：`swift test --package-path macos --filter GhosttySurfaceScrollInputTests` → 通过，2 tests, 0 failures；
  - 全量验证：`swift test --package-path macos` → 通过，`109 tests, 5 skipped, 0 failures`；
  - 代码格式校验：`git diff --check` → 通过。
- 当前边界：本轮已经完成代码级 root-cause 修复并通过自动化验证，但还没有新的 GUI 肉眼滚动手感证据；最终体感是否已与 Ghostty / Supacode 对齐，仍建议你本机再滚一轮确认。

## 新增根目录 `./dev` 原生开发命令（2026-03-21）

- [x] 记录设计与实现计划，明确单命令入口的职责边界
- [x] 先写失败用例，锁定 `./dev` 的帮助、dry-run 与日志包装行为
- [x] 实现根目录 `./dev` 脚本并补 README / AGENTS 说明
- [x] 运行脚本级验证与代码差异校验

## Review（根目录 `./dev` 原生开发命令）

- 直接原因：当前仓库虽然已经有 `swift run --package-path macos DevHavenApp` 这条原生启动链路，但关键诊断日志走的是 macOS unified log；直接运行 `swift run` 时，用户很难像 `pnpm dev` 那样在同一开发入口里同时看到日志和应用启动过程。
- 设计层诱因：开发态入口被拆成了“手动运行应用”和“另开终端执行 `log stream`”两步，应用启动真相源与日志观测真相源分裂。未发现更大的系统设计缺陷，问题集中在本地开发体验缺少统一入口。
- 当前修复：
  - 新增根目录 `./dev`，默认先执行 `bash macos/scripts/setup-ghostty-framework.sh --verify-only`；
  - 默认以 unified log 观察 `DevHavenNative` 与 `com.mitchellh.ghostty`；
  - 前台执行 `swift run --package-path macos DevHavenApp`，并通过 `trap` 回收后台日志进程；
  - 新增 `--dry-run`、`--no-log`、`--logs all|app|ghostty`，保证脚本具备最小可测试/可排障能力；
  - `README.md`、`AGENTS.md`、`tasks/lessons.md` 已同步更新。
- 长期建议：后续如果再增加新的原生诊断 subsystem、环境变量或调试开关，优先继续收口到 `./dev`，不要重新散落成多套“启动命令 + 文档说明 + 临时 shell alias”。
- 验证证据：
  - TDD 红灯：`bash macos/scripts/test-dev-command.sh` → 初次失败，报 `/Users/zhaotianzeng/WebstormProjects/DevHaven/dev: No such file or directory`，证明新测试确实先锁住了缺失的入口。
  - 定向绿灯：`bash macos/scripts/test-dev-command.sh` → 通过，输出 `dev command smoke ok`。
  - 帮助输出：`./dev --help` → 通过，已展示 `--dry-run`、`--no-log`、`--logs all|app|ghostty`。
  - dry-run：`./dev --dry-run` → 通过，已打印 vendor 校验、`log stream` 与 `swift run --package-path macos DevHavenApp` 三条命令。
  - 依赖前置：`bash macos/scripts/setup-ghostty-framework.sh --verify-only` → 通过，确认当前 `macos/Vendor` 完整。
  - 代码差异：`git diff --check` → 通过。
- 当前边界：本轮验证已覆盖脚本外部行为、参数分支与 vendor 前置条件，但没有在自动化会话里实际长时间运行 `./dev` 打开 GUI 应用并观察你桌面上的最终体感；如果你要确认真实开发体验，建议本机手动跑一遍 `./dev`。

## 排查 Ghostty 配置不再加载（2026-03-21）

- [x] 先确认当前 Ghostty 配置加载真相源、最近相关改动与用户现象是否一致
- [x] 定位直接原因与是否存在设计层诱因
- [x] 在最小改动下恢复预期配置加载行为，并补充回归验证
- [x] 更新 `tasks/todo.md` Review，必要时同步文档/测试

## Review（排查 Ghostty 配置不再加载）

- 直接原因：`GhosttyRuntime` 这轮未提交改动把配置加载从 `ghostty_config_load_default_files(config)` 改成了“只读取 `~/.devhaven/ghostty/config*`”。而当前机器上这两个 DevHaven 专属配置文件都不存在，实际只有 `~/Library/Application Support/com.mitchellh.ghostty/config`，因此启动后不再加载你原本就在 Ghostty 里使用的主题 / 键位 / 字体配置。
- 设计层诱因：存在。我们之前为了隔离 DevHaven 和独立 Ghostty App 的字体配置，把“配置真相源”从共享的 Ghostty 默认搜索路径收口到了 DevHaven 私有目录，但**没有提供迁移、显式开关或 fallback**，于是已有用户会在升级后直接感知成“配置突然失效”。问题集中在配置边界切换过猛；未发现更大的系统设计缺陷。
- 当前修复：
  1. `GhosttyRuntime` 新增 `preferredConfigFileURLs(...)`，配置加载改为“优先 `~/.devhaven/ghostty/config*`，若不存在则回退到 `~/Library/Application Support/com.mitchellh.ghostty/config*`”；
  2. 保留 `ghostty_config_load_recursive_files(config)`，因此无论是 DevHaven 专属配置还是原有 Ghostty 配置，`config-file` 拆分能力都还在；
  3. `GhosttyRuntimeConfigLoaderTests` 改成两条回归边界：`没有 DevHaven 专属配置时会回退到独立 Ghostty 配置`、`存在 DevHaven 专属配置时优先使用它`；
  4. `README.md` 与 `AGENTS.md` 同步把配置优先级说明改成“DevHaven 专属优先，缺省回退到现有 Ghostty 配置”。
- 长期建议：如果后续还想把 DevHaven 和独立 Ghostty App 完全隔离，不要再用“静默切断旧配置路径”的方式推进；至少提供一次性迁移、显式开关，或在首次启动时提示“当前正在沿用旧 Ghostty 配置，创建 `~/.devhaven/ghostty/config` 后即可覆盖”。
- 验证证据：
  - 本机现状：`~/.devhaven/ghostty/config` 与 `~/.devhaven/ghostty/config.ghostty` 均不存在；`~/Library/Application Support/com.mitchellh.ghostty/config` 存在，且含 `theme = iTerm2 Solarized Dark`、`font-family = Hack`、`font-family = Noto Sans SC` 等用户配置。
  - TDD 红灯：`swift test --package-path macos --filter GhosttyRuntimeConfigLoaderTests/testPreferredConfigFileURLsFallbackToStandaloneGhosttyConfigWhenDevHavenConfigMissing` 初次失败，报 `type 'GhosttyRuntime' has no member 'preferredConfigFileURLs'`。
  - 定向绿灯：`swift test --package-path macos --filter GhosttyRuntimeConfigLoaderTests` → 通过，`2 tests, 0 failures`。
  - 全量验证：`swift test --package-path macos` → 通过，`115 tests, 5 skipped, 0 failures`。
  - 差异校验：`git diff --check` → 通过。

## 整理当前工作区并执行 git commit（2026-03-21）

- [x] 核对当前分支、已修改文件与未跟踪文件，确认本次提交范围
- [x] 运行 fresh 验证，确保当前工作区具备提交证据
- [x] 整理提交内容并执行本地 `git commit`

## Review（整理当前工作区并执行 git commit）

- 提交范围：当前工作区包含同一批次的原生 Ghostty runtime / pasteboard / split surface 复用修复、根目录 `./release` 入口、相关测试、README / `AGENTS.md` / `tasks/*` 文档同步，以及对应实施计划文档；本轮按当前工作区真实状态统一提交。
- 验证证据：
  - `swift test --package-path macos` → 通过，`120 tests, 5 skipped, 0 failures`。
  - `bash macos/scripts/test-release-command.sh` → 通过，输出 `release command smoke ok`。
  - `bash macos/scripts/build-native-app.sh --help` → 通过，帮助文案正常打印。
  - `git diff --check` → 通过。
- 交付结果：已完成本地 `git commit`；具体 commit hash 以本轮命令输出和最终 `git log -1 --oneline` 为准。


## 修复点击“刷新项目”时界面卡死（2026-03-21）

- [x] 梳理“刷新项目”从 UI 到 ViewModel / Store 的执行链路，确认主线程阻塞点
- [x] 形成单一根因假设，并对照现有刷新/持久化实现找出与可响应路径的关键差异
- [x] 先补失败测试，锁定刷新期间不应继续把重扫描/写盘压在主线程
- [x] 以最小改动把阻塞性刷新流程移到后台，并补必要状态反馈/防重入
- [x] 运行定向验证与全量验证，并在 `tasks/todo.md` 追加 Review

## Review（修复点击“刷新项目”时界面卡死）

- 直接原因：`NativeAppViewModel` 整体挂在 `@MainActor` 上，但“刷新项目”链路里仍然把阻塞性工作放在主线程收尾：
  1. `refresh()` 先同步执行 `load()`，会在主线程读 `app_state.json / projects.json`；
  2. `refreshProjectCatalog()` 虽然把目录扫描和项目构建放进了 `Task.detached`，但最终 `persistProjects()` 仍在主线程里做 `JSONEncoder + JSONSerialization + projects.json 原子写盘 + selection/document refresh`；
  3. 对当前这台机器的 `~/.devhaven` 数据来说，刷新会覆盖约 135 个项目，因此点击后主线程会被这段同步 I/O 和状态收敛短暂卡住。
- 设计层诱因：存在。问题不是单个按钮写错，而是 **UI 状态层（`@MainActor` ViewModel）与重扫描 / 持久化这类重操作耦合过深**。扫描阶段虽然已经开始后台化，但最终写盘与结果应用仍混在主线程方法里，导致“半后台、半阻塞”的刷新链路。未发现更大的系统设计缺陷。
- 当前修复：
  1. `NativeAppViewModel` 新增 `projectCatalogRefresher` 后台刷新注入点与 `ProjectCatalogRefreshRequest`，把“目录扫描 + 项目重建 + `projects.json` 写盘”整体搬到 detached 后台任务执行；
  2. `refreshProjectCatalog()` 改成只在主线程负责刷新状态切换、错误回传和最终 `snapshot.projects` 应用，不再在主线程里执行写盘；
  3. `refresh()` 遇到已配置目录/直连项目时，不再先同步 `load()` 再刷新，避免一次多余的主线程磁盘读取；
  4. 新增 `isRefreshingProjectCatalog`，并在命令菜单 / 侧栏刷新入口上做禁用与“正在刷新…”文案，避免重复触发且给用户最小反馈；
  5. `LegacyCompatStore` 新增后台刷新所需的 home 目录访问口，保证后台持久化仍落到同一份 `~/.devhaven` 数据。
- 长期建议：后续把 `LegacyCompatStore` 的读写职责进一步从 `@MainActor` ViewModel 中抽离成统一的后台 job / actor，避免类似“扫描已后台化，但最终写盘仍卡 UI”反复出现；如果刷新耗时继续增长，再补显式进度提示而不只是禁用入口。
- 验证证据：
  - TDD 红灯：`swift test --package-path macos --filter ProjectCatalogRefreshConcurrencyTests`
    - 修复前失败，编译错误为：
      - `extra argument 'projectCatalogRefresher' in call`
      - `value of type 'NativeAppViewModel' has no member 'isRefreshingProjectCatalog'`
    - 说明新测试确实先锁住了“后台刷新入口 + 刷新中状态”这条边界。
  - 定向绿灯：同一命令修复后通过，`2 tests, 0 failures`。
  - 全量验证：`swift test --package-path macos` → 通过，`128 tests, 5 skipped, 0 failures`。
  - 差异校验：`git diff --check` → 通过。


## 排查删除/恢复功能与归档分支回收站差异（2026-03-21）

- [x] 核对当前工作区状态与上轮中断后的现场，确认排查基线
- [x] 定位当前原生主线中的回收站/删除/恢复入口与数据链路
- [x] 对照归档分支中的回收站实现，找出缺失点与直接原因
- [x] 输出结论；若需恢复功能，再补设计与实施计划

## Review（排查删除/恢复功能与归档分支回收站差异）

- 现场基线：上轮“刷新项目卡死”相关改动仍未提交，当前工作区是脏的；后台仅残留一个 `log stream` 观察进程，没有遗留 `swift test` / `swift run`。本轮只做只读排查，未改业务代码。
- 归档分支 `origin/archive/2.8.3` 的回收站能力包含三层：
  1. 侧栏底部固定 `回收站` 图标入口（`src/components/Sidebar.tsx`）；
  2. 项目删除入口不止一处，包含卡片、列表行以及批量“移入回收站”（`src/components/MainContent.tsx` / `ProjectCard.tsx` / `ProjectListRow.tsx`）；
  3. `RecycleBinModal.tsx` 弹窗支持展示隐藏项目并执行“恢复”。
- 当前原生主线中，“恢复”能力**并没有完全消失**：
  - `DevHavenApp.swift` 仍保留 `回收站` 菜单项并调用 `viewModel.revealRecycleBin()`；
  - `AppRootView.swift` 仍会弹出 `RecycleBinSheetView`；
  - `RecycleBinSheetView.swift` 里仍有 `恢复` 按钮；
  - `NativeAppViewModel.swift` 里仍有 `moveProjectToRecycleBin(...)` / `restoreProjectFromRecycleBin(...)` / `recycleBinItems`。
- 直接原因：这次不是数据层回收站被删了，而是**原生迁移时 UI 入口与操作覆盖范围明显缩水**，导致功能“体感上像没了”：
  1. 归档版侧栏底部的固定回收站入口被移除了，当前只能从菜单栏 `回收站` 进入；
  2. 当前 `MainContentView.swift` 只有**卡片模式**项目卡右上角保留 `trash`，**列表模式** `projectRow(...)` 已经没有任何删除入口；
  3. 归档版的批量移入回收站能力在原生版里也没有迁过来。
- 设计层诱因：存在。与之前“加号菜单只迁了图标没迁行为”的问题同类，属于 **旧栈复合交互在原生迁移时只迁了部分入口，状态方法还在，但用户可见操作面没有完整迁移**。未发现更大的系统设计缺陷。
- 当前结论：
  - “恢复”功能还在，但入口隐藏得更深；
  - “删除到回收站”在卡片模式仍可用，在列表模式基本等于消失；
  - 相比 `origin/archive/2.8.3`，当前主线确实存在回收站交互回归。
- 证据：
  - 当前主线：`macos/Sources/DevHavenApp/DevHavenApp.swift`、`AppRootView.swift`、`RecycleBinSheetView.swift`、`MainContentView.swift`、`NativeAppViewModel.swift`；
  - 归档对照：`origin/archive/2.8.3:src/components/Sidebar.tsx`、`RecycleBinModal.tsx`、`MainContent.tsx`、`ProjectCard.tsx`、`ProjectListRow.tsx`、`src/state/useDevHaven.ts`。


## 设计回收站交互恢复方案（2026-03-21）

- [x] 探查当前项目上下文、当前主线回收站现状与归档分支差异
- [x] 逐步确认用户目标与恢复范围（已确认选方案 A：不恢复多选/批量）
- [x] 提出 2-3 个设计方案并给出推荐
- [x] 分节展示设计并等待用户确认
- [x] 设计确认后写入 `docs/plans/2026-03-21-recycle-bin-restore-design.md`
- [x] 再进入 implementation plan 编写


## 恢复回收站交互（2026-03-21）

- [x] 写入设计文档与实施计划，明确本轮只恢复单项目回收站交互，不恢复多选/批量
- [x] 先补失败测试，锁定固定回收站入口、列表模式删除入口与回收站空状态提示
- [x] 以最小改动恢复侧栏底部回收站入口与列表模式删除
- [x] 运行定向验证与全量验证，并在 `tasks/todo.md` 追加 Review


## Review（恢复回收站交互）

- 直接原因：当前原生主线并没有删除 `recycleBin` 数据链路或恢复能力，真正回归的是 **交互入口覆盖范围**：
  1. 侧栏固定回收站入口在迁移时丢失；
  2. `MainContentView.swift` 仅卡片模式保留 `moveProjectToRecycleBin(project.path)`，列表模式完全没有删除入口；
  3. 空状态提示没有区分“筛选为空”和“项目已全部移入回收站”，导致用户难以意识到还能恢复。
- 设计层诱因：存在。与前面目录加号菜单的回归同类，属于旧栈复合交互迁移时只保留了部分入口，数据方法还在，但用户可见操作面收缩。未发现更大的系统设计缺陷。
- 当前修复：
  1. `ProjectSidebarView.swift` 从单一 `ScrollView` 改为“滚动主体 + 固定底栏”，底栏新增固定 `回收站` 入口，并展示回收站数量；
  2. `MainContentView.swift` 新增 `emptyStateView`，当 `visibleProjects` 为空且 `recycleBin` 非空时，提示“当前没有可见项目 / 可在回收站恢复隐藏项目”；
  3. `MainContentView.swift` 的 `projectRow(_:)` 补回单项目操作区，列表模式重新支持 `moveProjectToRecycleBin(project.path)`；
  4. 继续复用现有 `NativeAppViewModel` 的 `revealRecycleBin()` / `moveProjectToRecycleBin(_:)` / `restoreProjectFromRecycleBin(_:)`，没有引入第二套状态。
- 长期建议：如果后续还要继续对齐 `origin/archive/2.8.3`，下一步应单独评估是否恢复多选/批量移入回收站，而不要在这轮单项目恢复里顺手把 selection 系统重新做一遍。
- 验证证据：
  - TDD 红灯：`swift test --package-path macos --filter 'ProjectSidebarViewTests|MainContentViewTests'`
    - 修复前失败 4 项，包括：
      - `侧栏应恢复固定回收站入口，而不是只能从菜单栏打开`
      - `列表模式应重新提供单项目移入回收站入口，而不只是卡片模式可用`
      - `当没有可见项目且回收站非空时，应提示用户可从回收站恢复`
  - 定向绿灯：同一命令修复后通过，`4 tests, 0 failures`。
  - 全量验证：`swift test --package-path macos` → 通过，`131 tests, 5 skipped, 0 failures`。
  - 差异校验：`git diff --check` → 通过。


## 设计直接添加项目的虚拟目录（2026-03-21）

- [x] 补充当前直连项目筛选/侧栏实现上下文，确认现有数据与入口边界
- [x] 提出 2-3 个方案并给出推荐
- [x] 分节展示设计并取得用户确认
- [x] 设计确认后写入 `docs/plans/2026-03-21-direct-projects-virtual-directory-design.md`
- [x] 再进入 implementation plan 编写与 TDD 实施


## 实现直接添加项目虚拟目录（2026-03-21）

- [x] 写入设计文档与实施计划，明确虚拟目录与移除直连项目边界
- [x] 先补失败测试，锁定虚拟目录筛选与移除直连项目行为
- [x] 以最小改动实现“直接添加”虚拟目录与移除直连项目动作
- [x] 运行定向验证与全量验证，并在 `tasks/todo.md` 追加 Review

## Review（实现直接添加项目虚拟目录）

- 直接原因：当前 `directProjectPaths` 虽然已经存在并参与项目构建/刷新，但侧栏目录筛选仍然只支持“全部 + 真实目录路径”。由于 `selectedDirectory` 原本只是 `String?` 且过滤逻辑依赖 `project.path.hasPrefix(selectedDirectory)`，因此“直接添加的项目”没有正式筛选入口，也无法被当作一个可管理的虚拟目录。
- 设计层诱因：存在。问题集中在 **目录筛选模型过度依赖真实路径字符串**，导致只要出现“非真实路径”的筛选语义（这里是 `directProjectPaths`），就只能继续隐藏在数据层里，无法成为一等 UI 入口。未发现更大的系统设计缺陷。
- 当前修复：
  1. `NativeAppViewModel.swift` 新增 `DirectoryFilter` 显式目录筛选类型，把 `selectedDirectory` 从 `String?` 升级为 `.all / .directory(path) / .directProjects`；
  2. `directoryRows` 现在会正式生成 `直接添加` 虚拟目录项，并按 `directProjectPaths` 计算数量；
  3. `matchesAllFilters(project:)` 改为按筛选类型分支，不再拿虚拟目录去伪装路径前缀匹配；
  4. 新增 `removeDirectProject(_:)`，用于把项目从 `directProjectPaths` 中移除并持久化，但不删除磁盘目录、不移入回收站；
  5. `ProjectSidebarView.swift` 已改为绑定新的显式目录筛选值；
  6. `MainContentView.swift` 在选中 `直接添加` 虚拟目录时，会在卡片 / 列表操作区显示“移除直连项目”动作。
- 长期建议：如果后续还会增加“收藏项目”“最近添加”“手工管理”等虚拟目录，继续沿用这套显式筛选类型，不要退回到往路径字段里塞特殊字符串的做法。
- 验证证据：
  - TDD 红灯：`swift test --package-path macos --filter 'NativeAppViewModelTests|MainContentViewTests'`
    - 修复前失败，关键编译错误包括：
      - `type 'String?' has no member 'directProjects'`
      - `value of type 'NativeAppViewModel.DirectoryRow' has no member 'filter'`
      - `value of type 'NativeAppViewModel' has no member 'removeDirectProject'`
    - 说明新测试确实先锁住了显式目录筛选模型与移除直连项目能力。
  - 定向绿灯：同一命令修复后通过，`18 tests, 0 failures`。
  - 全量验证：`swift test --package-path macos` → 通过，`134 tests, 5 skipped, 0 failures`。
  - 差异校验：`git diff --check` → 通过。


## 修正目录整行点击热区（2026-03-21）

- [x] 确认当前目录行点击热区为何只落在文字/可见内容上
- [x] 提出 2-3 个最小修复方案并给出推荐
- [x] 与用户确认修复方案（方案 1：补 `contentShape`）
- [ ] 先补失败测试，锁定目录行整行热区
- [ ] 以最小改动修复 `sidebarRow(...)` 的整行点击区域
- [ ] 运行定向验证并更新 `tasks/todo.md` Review

## 解释 Ghostty `Noto Sans SC` `bold_italic not found` 日志（2026-03-21）

- [x] 确认 DevHaven 当前实际读取的是哪一份 Ghostty 配置
- [x] 确认本机 `Noto Sans SC` 家族实际提供了哪些字形样式
- [x] 对照 Ghostty 文档判断该日志的含义、影响范围与处理建议

## Review（解释 Ghostty `Noto Sans SC` `bold_italic not found` 日志）

- 直接原因：当前机器不存在 `~/.devhaven/ghostty/config*`，所以 DevHaven 会按现有逻辑回退读取 `~/Library/Application Support/com.mitchellh.ghostty/config`。该文件里配置了 `font-family = Hack` 与 `font-family = Noto Sans SC`。其中 `Noto Sans SC` 在本机确实存在，但枚举结果只有 `Regular/Thin/ExtraLight/Light/Medium/SemiBold/Bold/ExtraBold/Black`，没有 `Italic` 或 `Bold Italic`。因此 Ghostty 在为 `bold_italic` 样式解析这个字体家族时会打印 `font-family bold_italic not found: Noto Sans SC`。
- 设计层诱因：存在，但不是新 bug。本质上是 DevHaven 目前仍会在缺少 `~/.devhaven/ghostty/config*` 时回退到独立 Ghostty App 的全局配置；而该全局配置把一个**没有斜体字形**的 CJK 字体家族加入到了 `font-family` 回退链里。未发现更大的系统设计缺陷。
- 当前结论：这条日志更像**字体样式缺失告警**，而不是 DevHaven 崩溃或终端不可用。按照 Ghostty 文档，若未显式指定对应 style，Ghostty 会先在 `font-family` 中搜索 stylistic variants；缺失时可回退 regular style，部分样式还可能被 synthetic style 合成。
- 处理建议：
  1. 如果只是偶发日志、终端显示正常，可以先视为低风险告警；
  2. 如果想彻底消掉日志，优先在 `~/.devhaven/ghostty/config` 中单独为 DevHaven 设置更合适的终端主字体/回退字体，不要直接继承全局 Ghostty 的整套字体链；
  3. 不建议把 `Noto Sans SC` 作为需要斜体/粗斜体样式的主终端字体；它更适合作为中文 fallback，而不是承担 italic / bold italic 风格；
  4. 如需保留中文 fallback，可继续保留 `Noto Sans SC`，但把真正支持 `Italic` / `Bold Italic` 的等宽字体放在前面，并在需要时显式补 `font-family-italic` / `font-family-bold-italic`。
- 验证证据：
  - 配置文件检查：`~/.devhaven/ghostty/config` 与 `~/.devhaven/ghostty/config.ghostty` 均不存在；`~/Library/Application Support/com.mitchellh.ghostty/config` 存在，且含 `font-family = Hack`、`font-family = Noto Sans SC`。
  - 运行时代码检查：`GhosttyRuntime.preferredConfigFileURLs(...)` 会优先读 `~/.devhaven/ghostty/config*`，缺失时回退到 `~/Library/Application Support/com.mitchellh.ghostty/config*`；对应代码位于 `macos/Sources/DevHavenApp/Ghostty/GhosttyRuntime.swift:77-136`。
  - 字体枚举：`swift - <<'SWIFT' ... NSFontManager.shared.availableMembers(ofFontFamily: "Noto Sans SC") ... SWIFT` 输出 `Noto Sans SC` 存在，但 `has Bold Italic: false`、`has Italic: false`、`has Bold: true`。
  - 文档依据：仓库内 `macos/Sources/DevHavenApp/GhosttyResources/ghostty/doc/ghostty.5.md` 说明 `font-family` 会为各 style 搜索 stylistic variants；若 style 不存在，Ghostty 会回退 regular style，并且某些 style 可以被 synthesized。

## 重推当前分支并替换 `v3.0.0` tag 重新触发构建（2026-03-21）

- [x] 检查当前分支、远端差异、`v3.0.0` 本地/远端指向与 release workflow 触发条件
- [x] 明确是否需要把当前未跟踪文件一并纳入本次 push/tag 重置范围
- [x] 执行分支 push，并强制更新远端 `v3.0.0` tag
- [x] 验证远端分支与 tag 已更新，补充 Review 证据


## Review（重推当前分支并替换 `v3.0.0` tag 重新触发构建）

- 操作结果：已将 `main` 分支提交 `becb1c9` 推送到远端，并把远端注解 tag `v3.0.0` 强制更新到同一提交。
- 执行说明：按用户确认，本轮只推送已提交的 `becb1c9`，未把当前 7 个未跟踪文件纳入本次 push / tag 重置范围。
- 触发结果：`release.yml` 已因 `v3.0.0` tag push 重新触发，最新 run 为 `23376437476`，当前状态 `in_progress`。
- 验证证据：
  - `git push origin main` → 远端更新 `bda3e81..becb1c9  main -> main`
  - `git push --force origin refs/tags/v3.0.0` → 远端更新 `+ 8d15bcc...276ab9a v3.0.0 -> v3.0.0 (forced update)`
  - `git ls-remote origin refs/heads/main` → `becb1c91c2231794dcab81138d213e9c454dfd99	refs/heads/main`
  - `git ls-remote origin 'refs/tags/v3.0.0^{}'` → `becb1c91c2231794dcab81138d213e9c454dfd99	refs/tags/v3.0.0^{}`
  - `gh run list --workflow release.yml --limit 5 --json ...` → 最新记录 `databaseId=23376437476`、`headSha=becb1c91c2231794dcab81138d213e9c454dfd99`、`status=in_progress`、`url=https://github.com/zxcvbnmzsedr/devhaven/actions/runs/23376437476`

## 盯住 `v3.0.0` release workflow 运行状态（2026-03-21）

- [x] 记录待监控的 GitHub Actions run 与当前基线状态
- [ ] 持续轮询 run 状态直到结束
- [ ] 汇总成功/失败结论、关键步骤结果与下一步建议
