# Workspace Git / Terminal 一体化与通用 Bottom Tool Window 设计

## 背景

当前 Workspace 的 Git 面板采用 **Terminal / Git 一级主模式切换**：

- `NativeAppViewModel.workspacePrimaryMode` 是主真相源；
- `WorkspaceChromeContainerView` 左侧 rail 通过 `WorkspaceModeSwitcherView` 切换模式；
- `WorkspaceShellView` 里按 `workspacePrimaryMode` 在 terminal 与 Git 内容之间二选一。

这条路径已经不符合目标体验。用户本轮明确要求：

1. 终端仍是 Workspace 的主工作区；
2. Git 应像 IntelliJ IDEA 一样，作为 **bottom tool window** 出现在同一界面；
3. 本轮不应停留在“Git 专用底部面板”层面，而要直接提升为 **通用 Tool Window 框架**；
4. 首期只落地 **bottom placement**，Git 作为第一个接入者。

## 直接原因

当前实现的问题不只是“Git 不在底部”，而是抽象层级本身错误：

- `WorkspacePrimaryMode` 表达的是 **主内容互斥切换**；
- 但目标交互需要的是 **主区 + 辅助工具窗**；
- 如果继续复用 `workspacePrimaryMode == .git` 表示“Git 底部面板已打开”，语义会持续错位；
- 焦点路由、菜单命令、布局持久化与后续扩展都会变得别扭。

## 目标

本轮目标不是“把 Git 挪到底部”这么简单，而是建立一条可扩展的 Workspace 主内容 + Bottom Tool Window 主链：

1. Terminal 永远是主区；
2. Workspace 提供一个通用 **Bottom Tool Window Host**；
3. Git 作为首个 tool window 接入；
4. 移除旧的 Terminal / Git 一级模式切换语义；
5. 为未来追加其他 bottom tool window 预留最小但正确的扩展点；
6. 保持现有 `WorkspaceGitViewModel` / `WorkspaceGitRootView` 内部业务主链尽量不重写。

## 方案比较

### 方案 A：保留 `workspacePrimaryMode`，把 `.git` 解释成“底部 Git 已打开”

做法：

- 继续保留 `WorkspacePrimaryMode`；
- 将 `.terminal` / `.git` 重新解释为 terminal-only 与 terminal+git-bottom 两种布局。

优点：

- 改动表面上最小；
- 现有切换逻辑与部分测试似乎还能复用。

缺点：

- 语义错误：`primaryMode == .git`，但主区其实还是 terminal；
- 后续 tool window 扩展会继续背负错误抽象；
- 焦点与菜单命令守门会更混乱。

### 方案 B：只做 Git 专用底部面板

做法：

- 删除主模式切换；
- 在 `WorkspaceShellView` 里单独加一个 Git bottom panel；
- 不抽象通用 tool window。

优点：

- 比方案 A 语义更正确；
- 本轮落地速度快。

缺点：

- 仍然是一次 Git 专用补丁；
- 以后要加第二个 tool window 时大概率还要再拆一轮。

### 方案 C：建立通用 Bottom Tool Window 框架，Git 首个接入

做法：

- 废弃 `WorkspacePrimaryMode`；
- 引入 `WorkspaceToolWindowKind / Placement / State / FocusedArea`；
- `WorkspaceShellView` 改造成 terminal 主区 + bottom tool window host + bottom bar；
- Git 作为第一个 `kind` 接入，复用现有 Git 业务视图与 ViewModel。

优点：

- 和目标体验最一致；
- 抽象层正确，后续可以平滑增加第二个 tool window；
- 能从根源修复“Git 被错误建模为一级模式”的问题。

缺点：

- 改动面大于方案 A / B；
- 需要同步改模型、视图与测试。

## 选型

本轮采用 **方案 C**，但范围收敛为：

- **通用框架命名与宿主正确**
- **只支持 bottom placement**
- **只接入 Git 一个真实 tool window**
- **不在本轮同时实现第二个工具窗**

这既满足用户要求，也避免把“方案 C”扩散成过度工程。

## 设计细节

### 1. 新的运行时模型

在 Core 层新增或重组以下模型：

- `WorkspaceToolWindowKind`
  - 当前先只有 `.git`
- `WorkspaceToolWindowPlacement`
  - 当前先只有 `.bottom`
- `WorkspaceToolWindowState`
  - `activeKind`
  - `isVisible`
  - `placement`
  - `height`
  - `lastExpandedHeight`
- `WorkspaceFocusedArea`
  - `.terminal`
  - `.toolWindow(WorkspaceToolWindowKind)`

其中：

- `activeKind` 与 `isVisible` 必须拆开，避免“选中的 tool 还在，但面板已关闭”时语义混乱；
- `WorkspaceFocusedArea` 只承担运行时命令路由守门，不承担复杂焦点管理。

### 2. ViewModel 边界

`NativeAppViewModel` 负责：

- tool window 宿主运行时状态；
- 打开 / 关闭 / toggle 当前 tool window；
- 高度记忆；
- active project 变化时接线与上下文同步；
- 维护 `activeWorkspaceGitViewModel` 的准备逻辑，但不再依赖 `workspacePrimaryMode`。

`WorkspaceGitViewModel` 继续负责：

- Git 内部 section（log / changes / branches / operations）；
- execution worktree；
- log filters、selection、mutation、read model。

边界原则：

- “面板是否展开”属于 Workspace 宿主；
- “Git 面板内部显示什么”属于 Git ViewModel。

### 3. 布局结构

调整后的层级：

- `WorkspaceRootView`
  - `WorkspaceProjectSidebarHostView`
  - `WorkspaceChromeContainerView`
    - `WorkspaceShellView`
      - terminal 主区
      - bottom tool window host
      - bottom tool window bar

其中：

- `WorkspaceChromeContainerView` 移除左侧 Terminal/Git rail，回归纯 chrome 容器；
- `WorkspaceShellView` 不再做 terminal/git 主模式切换，而改为垂直布局宿主；
- Git 内容继续由 `WorkspaceGitRootView` 承接，只是位置从主区变为 bottom host。

### 4. 底部入口条

新增一个轻量的 bottom tool window bar，首期只放一个入口：

- `Git`

交互语义：

- 当前未激活 Git：点击后激活并展开；
- 当前激活但已收起：点击后展开；
- 当前激活且已展开：点击后收起。

### 5. Active project 切换语义

当 active project 切换时：

- tool window 宿主状态尽量保留；
- Git 内容按新的 active project / root repository 重路由；
- 若当前项目不是 Git 仓库或是 Quick Terminal：
  - Git tool window 仍可保持打开；
  - 内容区显示明确空态，而不是静默关闭整个工具窗。

### 6. 高度与收起语义

- bottom tool window 默认使用一份初始高度；
- 用户拖拽调整后记住当前高度；
- 收起时保留最近一次展开高度；
- 再次打开时恢复。

本轮建议先将高度持久化到 App 设置层或至少保存在会话内；具体持久化实现可在实施阶段按改动面决定，但结构上要支持“恢复上次高度”。

### 7. 焦点与命令路由

删除 `workspacePrimaryMode == .terminal` 这类旧守门后，需要新的最小焦点语义：

- terminal 搜索类 `FocusedValue` / 菜单命令只在 `WorkspaceFocusedArea == .terminal` 时暴露；
- 当用户与 Git tool window 交互时，focused area 更新为 `.toolWindow(.git)`；
- 这样可以避免“Git 面板正在操作，但菜单命令仍误落到 terminal pane”。

### 8. 测试策略

本轮重点补三类测试：

1. **模型 / 状态测试**
   - `NativeAppViewModel` 不再依赖 `workspacePrimaryMode`
   - tool window toggle / visibility / active kind 语义正确

2. **视图结构测试**
   - `WorkspaceChromeContainerView` 不再保留左 rail mode switcher
   - `WorkspaceShellView` 改为 terminal 主区 + bottom host，而不是二选一 switch

3. **Git 接线测试**
   - 打开 Git tool window 时仍能路由到 `WorkspaceGitRootView`
   - 非 Git 项目 / Quick Terminal 下仍有明确空态

### 9. 架构文档同步

由于本轮属于架构级变化，必须同步更新 `AGENTS.md`：

- 删除“WorkspaceModeSwitcherView 负责 Terminal / Git 一级模式切换”的旧描述；
- 新增 Workspace 主区 + bottom tool window host 的结构说明；
- 说明 `WorkspaceToolWindowState`、Git tool window 与 terminal 焦点边界；
- 记录本次变更原因：Git 不再是主模式，而是通用工具窗接入者。

## 涉及文件

预期涉及但不限于：

- `macos/Sources/DevHavenCore/Models/WorkspaceGitModels.swift`
- `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`
- `macos/Sources/DevHavenApp/WorkspaceShellView.swift`
- `macos/Sources/DevHavenApp/WorkspaceChromeContainerView.swift`
- `macos/Sources/DevHavenApp/WorkspaceModeSwitcherView.swift`
- `macos/Sources/DevHavenApp/WorkspaceGitRootView.swift`
- `macos/Tests/DevHavenAppTests/WorkspaceShellViewGitModeTests.swift`
- `macos/Tests/DevHavenAppTests/WorkspaceChromeContainerViewTests.swift`
- `macos/Tests/DevHavenCoreTests/WorkspaceGitViewModelTests.swift`
- `AGENTS.md`
- `tasks/todo.md`

## 风险与边界

- 如果仅改 UI 布局而不废弃 `WorkspacePrimaryMode`，错误抽象会继续残留；
- 如果不补 `WorkspaceFocusedArea`，terminal 菜单命令在新布局下容易误路由；
- 如果把“是否展开”状态塞进 `WorkspaceGitViewModel`，后续扩展第二个工具窗会再次耦合；
- 本轮不做右侧停靠、浮动、多个真实工具窗并存，也不把 tool window 状态纳入 workspace restore snapshot。

## 验证计划

- 定向测试：`swift test --package-path macos --filter 'WorkspaceShellViewGitModeTests|WorkspaceChromeContainerViewTests|WorkspaceGitRootViewTests|WorkspaceGitViewModelTests'`
- 更广范围回归：`swift test --package-path macos --filter 'WorkspaceShellViewTests|WorkspaceTerminalCommandsTests|WorkspaceRootViewTests|WorkspaceGitLogViewModelTests'`
- 质量检查：`git diff --check`
