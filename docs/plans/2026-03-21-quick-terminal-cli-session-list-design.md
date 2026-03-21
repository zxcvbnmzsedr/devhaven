# Quick Terminal CLI 会话列表设计

**日期：** 2026-03-21

## 背景

当前左侧全局 sidebar 的“CLI 会话”区块已经新增 `+` 按钮，可直接调用 `openQuickTerminal()` 打开快速终端；但列表内容仍来自 `visibleProjects` 的派生数据，而不是真实的 `openWorkspaceSessions`。这导致 UI 标题、会话状态与真实 session 真相源分裂。

同时，workspace 左侧项目列表会把 quick terminal 当成普通项目渲染，继续暴露“刷新 worktree / 创建或添加 worktree”等错误操作入口。

## 目标

把“CLI 会话”区块改成 **真实 quick terminal 会话列表**，并让 workspace 左侧列表对 quick terminal 隐藏 worktree 相关操作，避免把它误当成 Git 项目。

## 非目标

- 本轮不引入多个 quick terminal session；
- 不扩展新的 CLI session 类型；
- 不重构整个 workspace / sidebar 架构。

## 设计

### 1. 会话真相源

“CLI 会话”区块只读取 `openWorkspaceSessions.filter(\.isQuickTerminal)`，不再从 `visibleProjects`、`scripts` 或 `worktrees` 派生。

这意味着：

- 没有 quick terminal session 时显示空状态；
- 有 quick terminal session 时显示会话卡片；
- `exitWorkspace()` 之后，session 仍保留在 `openWorkspaceSessions` 中，因此该区块可以继续展示并恢复它。

### 2. 单会话模型

继续沿用当前“单 quick terminal”模型：以 home path 为 session key。

- 点击 `+`：
  - 若不存在 quick terminal session，则创建并激活；
  - 若已存在，则直接激活该 session，不重复创建。

### 3. 全局 sidebar 交互

“CLI 会话”区块中的 quick terminal 卡片提供两类操作：

- 点击卡片：激活 / 恢复该 quick terminal session；
- 点击关闭：关闭该 quick terminal session。

状态文案采用：

- 当前活跃：`已打开`
- 非当前活跃但 session 仍存在：`可恢复`

### 4. workspace 左侧项目列表

quick terminal 仍在 workspace 左侧列表中占一个 group，但它不是 Git 项目，因此：

- 保留“激活”和“关闭”能力；
- 隐藏“刷新 worktree”和“创建/添加 worktree”按钮。

### 5. 建模边界

为了避免继续在 UI 层散落 magic string / magic id，`Project` 增加 quick terminal 判定能力，供：

- `WorkspaceProjectListView`
- `NativeAppViewModel`

统一判断该 group / project 是否为 quick terminal。

## 测试策略

1. `NativeAppViewModelWorkspaceEntryTests`
   - quick terminal session 列表来自 `openWorkspaceSessions`
   - 再次调用 `openQuickTerminal()` 不重复创建，而是激活已有 session
   - `exitWorkspace()` 后 CLI 会话列表仍能展示 quick terminal

2. `ProjectSidebarViewTests`
   - “CLI 会话”区块应读取真实 session，而不是旧的 `visibleProjects` 派生逻辑

3. `WorkspaceProjectListViewTests`
   - quick terminal group 不应暴露 worktree 按钮

## 风险控制

- 尽量复用现有 `openWorkspaceSessions`、`activateWorkspaceProject(_:)`、`closeWorkspaceProject(_:)`，避免新增第二套 session 管理逻辑；
- 只做单 quick terminal session，避免引入 tab / session 管理复杂度；
- 保持改动范围集中在 sidebar / workspace list / ViewModel。
