# DevHaven Swift 原生终端首开体验对齐 Ghostty / Supacode 设计

> 状态：已获用户确认，方向收口为“Ghostty 和 Supacode 怎么做，DevHaven 就怎么做”，不再单独发明 DevHaven 专属快启模式。

## 目标

把 Swift 原生版在“首次打开项目进入 workspace”这一段的终端体验，收口到和 Ghostty / Supacode 同一条主线：

- 继续保留 **真实 login shell** 语义，不靠剪掉用户 shell 初始化来换速度；
- 让 **workspace / terminal pane 尽快可见**，不要把“shell prompt 何时出现”继续等价成“工作区是否已经打开”；
- 让已打开项目的终端运行态像 Supacode 一样由 **稳定 owner 持有并复用**，而不是只靠 `WorkspaceHostView` 自己的短暂内部状态；
- 让“再次进入同一项目”优先走复用路径，而不是重新从零冷启动整条终端状态链。

本轮目标不是把 prompt 本身从 2 秒直接压到几百毫秒；因为 Ghostty / Supacode 也没有通过自定义 shell profile 去规避用户自己的 `zsh` 初始化。本轮要解决的是：**DevHaven 该如何像它们一样组织终端状态与首屏呈现。**

## 当前事实与问题判断

### 已确认的事实

1. DevHaven 当前原生日志已经证明：
   - `entry -> surface-start` 约 57ms；
   - `surface-start -> surface-finish` 约 30ms；
   - `entry -> host-mounted` 约 121ms。
   说明 workspace host 与 Ghostty surface 创建本身不是秒级瓶颈。
2. 同目录下直接测 `zsh -il`，首个 prompt 约 2s；`zsh -dfi` 只要约 4ms，说明用户 shell 冷启动确实很重。
3. 单纯把 `TERM_PROGRAM` 伪装成 `DevHaven / ghostty / Supacode`，首个 prompt 都在同一量级，宿主名字不是关键差异。
4. 单纯把 shell 拉起命令改成 Ghostty.app 常见的 `/bin/zsh --login -i`，并不会自动比 DevHaven 当前 `login -flp ... exec -l /bin/zsh` 更快。
5. Supacode 的 `WorktreeTerminalManager.state(for:)` 会按 `worktree.id` 复用既有 terminal state；也就是说 Supacode 的“快”，不只是 shell 命令怎么写，更来自 **terminal state owner 与复用语义**。
6. 当前 `macos/Package.swift` 明确把 `DevHavenCore` 与 `DevHavenApp` 分成两个 target，因此任何直接持有 `GhosttySurfaceHostModel` 的 terminal store 都不能落在 `DevHavenCore`，否则会打破模块边界。

### 当前问题

DevHaven 现在的慢感主要来自两层叠加：

1. **首屏可感知边界不对**：用户实际上在等的是“第一个 prompt 终于出来”，而不是“pane / surface 已经 ready”。
2. **终端 owner 边界仍然偏低层**：当前 `WorkspaceSurfaceRegistry` 还只是 `WorkspaceHostView` 内部的 `@StateObject`。虽然在当前 ZStack 常驻结构下已经能保住不少场景，但它依然属于“单个 host view 自己持有的局部 owner”，还不像 Supacode 那样有一层更高的 project/worktree 级 terminal owner。

换句话说，当前 DevHaven 的问题不是 Ghostty runtime 慢，而是：

- 终端状态仍然太靠近具体 host view；
- 首次进入时，没有一个像 Supacode 那样的稳定 terminal owner 来承接“先可见、后就绪、可复用”的语义。

## 方案比较

### 方案 A：对齐 Ghostty / Supacode 的终端 owner 与首屏呈现（采用）

核心思路：

- 保留 login shell；
- 在 **DevHavenApp 层** 新增项目级 `WorkspaceTerminalSessionStore`；
- 再在 `WorkspaceShellView` 持有一个 `projectPath -> WorkspaceTerminalSessionStore` 的 registry；
- 让 `WorkspaceHostView` 改为消费 shell-owned store，而不是自己 new `WorkspaceSurfaceRegistry`；
- active project 切换后，由 `WorkspaceShellView` 对当前 selected pane 做 **eager warm-up**；
- pane 一出现就进入“终端已打开，shell 正在启动”状态，而不是继续让用户等待“整个工作区还没好”。

优点：

- 最接近 Ghostty / Supacode 的真实做法；
- 不牺牲 shell 兼容性；
- 保持模块边界干净；
- 首次进入和再次进入都能收益；
- 后续还可以继续扩展到更细的 session 预热 / 复用，而不推翻架构。

缺点：

- 需要新增 App 层 owner 与状态测试，不是一行配置改完。

### 方案 B：只改 shell 启动命令去对齐 Ghostty

优点：

- 改动小；
- 看起来最像“直接照抄 Ghostty”。

缺点：

- 实测并不会自动更快；
- 解决不了 Supacode 那条 terminal state reuse 的核心差异；
- 体感收益可能很有限。

### 方案 C：做 DevHaven 专属 fast shell 模式

优点：

- 可以明显压缩首个 prompt 时间。

缺点：

- 这已经不是 Ghostty / Supacode 的路子；
- 会偏离系统 shell 行为；
- 不符合当前用户明确收口的方向。

## 采用方案

采用 **方案 A：App 层项目级 terminal owner + eager warm-up + pane 先可见、shell 后就绪**。

## 详细设计

### 1. 在 `DevHavenApp` 新增 `WorkspaceTerminalSessionStore`

新增位置（建议）：

- `macos/Sources/DevHavenApp/WorkspaceTerminalSessionStore.swift`

职责：

- 按 `pane.id` 持有稳定的 `GhosttySurfaceHostModel`；
- 提供 `model(for:)`、`syncRetainedPaneIDs(...)`、`releaseAll()` 这类能力，把现有 `WorkspaceSurfaceRegistry` 逻辑收口成一个明确的 session store；
- 提供 `warmSelectedPane(in controller: GhosttyWorkspaceController, ...)`，允许在 active project 切换时提前触发当前 selected pane 的 surface acquire；
- 跟踪每个 pane 的启动阶段（至少区分 `warming / failed / exited`），供 UI 做“正在启动 shell”展示。

### 2. 在 `WorkspaceShellView` 新增 `WorkspaceTerminalStoreRegistry`

由于 `OpenWorkspaceSessionState` 与 `NativeAppViewModel` 都在 `DevHavenCore`，不能直接持有 `DevHavenApp` 类型，因此 project-level owner 的落点要放在 App 层。

新增一个轻量 registry（可以和 store 写在同文件）：

- `projectPath -> WorkspaceTerminalSessionStore`

由 `WorkspaceShellView` 持有：

- 当 `viewModel.openWorkspaceSessions` 增减时，同步保留/清理对应 store；
- 当 active project 变化时，拿到对应 store 并做 selected pane warm-up；
- 由于 `WorkspaceShellView` 本身已被 `AppRootView` 常驻挂在 ZStack 中，返回主列表时只会隐藏，不会销毁，因此这层 store 能像 Supacode 的 worktree terminal manager 一样稳定存在。

### 3. `WorkspaceHostView` 改为消费 shell-owned store

当前 `WorkspaceHostView` 内部有：

- `@StateObject private var surfaceRegistry = WorkspaceSurfaceRegistry()`

本轮改成：

- 由 `WorkspaceShellView` 把对应 `WorkspaceTerminalSessionStore` 传入 `WorkspaceHostView`；
- `WorkspaceHostView` 不再自己 new registry；
- `surfaceModel(for:)` 改成从传入的 store 取 model；
- `retainedPaneIDs` 同步与释放逻辑也交给该 store。

这样可以把终端 owner 从单个 host view 内部抬高到 project-level shell owner，同时不破坏 Core/App 模块边界。

### 4. active project 切换后由 `WorkspaceShellView` 做 eager warm-up

因为 warm-up owner 在 App 层，不再放在 `NativeAppViewModel.enterWorkspace(...)` 里，而是放在 `WorkspaceShellView`：

- `onAppear`：对当前 active project 的 selected pane 做一次 warm-up；
- `onChange(of: viewModel.activeWorkspaceProjectPath)`：切项目后对目标项目的 selected pane 做 warm-up；
- `onChange(of: selectedPaneID/selectedTabID)`：如有必要，对新的 selected pane 做 warm-up，但仍只 warm 当前可见 pane，不预热整棵树。

这样虽然 warm-up 发生在 shell view 挂上之后，但仍然对齐 Ghostty/Supacode 的“project-level owner + active terminal eager attach”语义；同时由于当前 host-mounted 本身只有约 121ms，这一层不会是主要瓶颈。

### 5. 把“启动中”作为一等 UI 状态，而不是初始化失败前的空白阶段

当前 `GhosttySurfaceHost` 在正常路径下直接显示 `GhosttyTerminalView`；用户视觉上只能靠终端内容是否已经滚出 prompt 判断“有没有打开成功”。

本轮补一条更像 Ghostty / Supacode 的显示语义：

- pane 出现后，如果 surface 已经在 warming / attached 但 shell 尚未表现出稳定运行态，就展示轻量 overlay：
  - 标题：`正在启动 shell...`
  - 副文案：`终端已创建，正在等待登录 shell 初始化完成。`
- 一旦 host model 进入稳定运行态，overlay 自动消失。

注意：

- 本轮**不做脆弱的 prompt 文本解析**；
- 只做“终端是否已经 ready for interaction”的稳定语义；
- 这样才和 Ghostty / Supacode 的行为边界一致，而不是发明 DevHaven 自己的一套 prompt 解析器。

### 6. 非目标与明确不做

本轮明确不做：

- non-login shell；
- DevHaven 专属 shell profile；
- 去修改用户 `~/.zprofile` / `~/.zshrc`；
- 把 Rust `src-tauri/src/terminal.rs` 那条终端链一起重构；
- prompt 文本级解析或“检测到 `main` 才算 ready”这类不稳定规则。

## 影响文件

### 新增

- `macos/Sources/DevHavenApp/WorkspaceTerminalSessionStore.swift`
- `macos/Tests/DevHavenAppTests/WorkspaceTerminalSessionStoreTests.swift`
- `docs/plans/2026-03-20-devhaven-swift-native-terminal-fast-entry-plan.md`

### 修改

- `macos/Sources/DevHavenApp/WorkspaceShellView.swift`
- `macos/Sources/DevHavenApp/WorkspaceHostView.swift`
- `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceHost.swift`
- `tasks/todo.md`
- `tasks/lessons.md`

## 验证策略

1. 先补 `WorkspaceTerminalSessionStoreTests.swift`：
   - 同一 pane 多次取 model 必须复用同一个 host model；
   - `warmSelectedPane(...)` 只预热当前可见 pane，不意外拉起所有 pane；
   - `syncRetainedPaneIDs(...)` 只在 pane 真正移除时释放。
2. 视需要补一个纯策略测试（例如 `WorkspaceTerminalStartupPresentationPolicyTests`），锁定“何时显示启动 overlay”的边界。
3. 再跑：
   - `swift test --package-path macos --filter WorkspaceTerminalSessionStoreTests`
   - `swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests`
   - `swift test --package-path macos`
   - `swift build --package-path macos`
   - `git diff --check`

## 风险与对策

### 风险 1：把 warm-up 做成“所有 pane 一起预热”，反而放大首开成本

对策：

- 第一阶段只 warm **当前 selected pane**；
- 非选中 tab / 非可见 pane 继续延迟到真正可见时再 acquire。

### 风险 2：owner 抬到 shell view 后，pane 真正关闭与 View 短暂消失的边界再次混乱

对策：

- 继续沿用之前的 lesson：`pane` 逻辑生命周期必须由 owner 管，不能由 View 的 `onDisappear` 直接决定；
- `syncRetainedPaneIDs(...)` 是唯一合法清理入口；
- `WorkspaceShellView` 只按 projectPath 管理 store，不直接替代 pane 级释放语义。

### 风险 3：overlay 判断条件过于依赖 shell 输出细节，造成误判

对策：

- 本轮只采用稳定的 host model / surface attach 状态，不做 prompt 文本解析；
- 如果后续确实需要更细粒度“首字节/首个 prompt”诊断，再在 diagnostics 层追加，不把这层耦合进主 UI 语义。
