# DevHaven 工作区通知增强设计

## 背景
DevHaven 当前工作区侧边栏与 Ghostty 集成已经具备 tab / pane / focus 基础能力，但缺少 Supacode 式的运行时通知体验：终端通知不会进入应用内状态层，用户也无法在工作区列表中看到未读提醒、运行中状态或点击通知跳回对应 pane。

## 目标
在不引入通知历史持久化与 AI 语义理解的前提下，为 DevHaven 增加一套完整的运行时工作区通知体验：
- 捕获 Ghostty desktop notification / progress / bell 事件
- 维护 worktree 级运行时未读与任务状态
- 在侧边栏渲染 bell / spinner / 聚合提示
- 点击通知后切换到对应项目、tab、pane
- 支持系统通知、声音提示与“收到通知后置顶”设置

## 设计原则
1. 运行时态与持久化业务态分离：通知列表、未读状态、运行中状态只存在于内存。
2. Ghostty 桥接层只翻译事件，不承担排序与 UI 决策。
3. 应用层统一维护工作区注意力状态，侧边栏与 workspace UI 共同消费。
4. 设置仍以 `app_state.json` 为真相源，但仅持久化通知开关，不持久化通知内容。

## 架构方案
### 1. Ghostty 事件桥接
在 `GhosttySurfaceBridge` 中新增：
- desktop notification 回调
- progress report 回调
- ring bell 回调

### 2. Surface Host Model
在 `GhosttySurfaceHostModel` 中新增 pane 级 closure 与状态：
- `onNotificationEvent`
- `onTaskStatusChange`
- `onBell`
- `taskStatus`
- `bellCount`

### 3. Core 运行时注意力状态
在 `DevHavenCore` 增加运行时模型：
- `WorkspaceTerminalNotification`
- `WorkspaceTaskStatus`
- `WorkspaceAttentionState`

由 `NativeAppViewModel` 维护 `attentionStateByProjectPath`，并提供：
- 记录通知
- 标记已读
- 根据 pane 聚合运行状态
- 根据最近未读通知时间调整侧边栏顺序
- 跳转到指定 tab / pane

### 4. 侧边栏与交互
扩展 `WorkspaceSidebarWorktreeItem` / `WorkspaceSidebarProjectGroup`：
- worktree 行显示 bell / spinner / 未读数
- root project 行显示聚合提醒
- popover 列出通知并支持点击回跳

### 5. 系统通知与声音
在 `DevHavenApp` 新增 presenter：
- 请求/查询系统通知权限
- 发送本地系统通知
- 播放本地提示音

## 风险与边界
- 不做通知历史持久化
- 不做系统通知点击深链回跳
- 不做 AI 总结通知内容
- 不改动项目/worktree持久化顺序，只做运行时排序覆盖

## 测试策略
- Bridge 单测覆盖 desktop notification / progress / bell
- Core 单测覆盖通知记录、已读、排序、聚焦跳转
- App 侧单测覆盖设置文案、通知 popover 入口与 host model 状态传播
