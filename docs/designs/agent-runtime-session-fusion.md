# DevHaven Agent Runtime 功能与架构文档

关联模块：

- [WorkspaceAgentSessionModels.swift](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenCore/Models/WorkspaceAgentSessionModels.swift)
- [WorkspaceAgentSignalStore.swift](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenCore/Storage/WorkspaceAgentSignalStore.swift)
- [WorkspaceNotificationModels.swift](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenCore/Models/WorkspaceNotificationModels.swift)
- [NativeAppViewModel.swift](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift)
- [CodexAgentDisplayStateRefresher.swift](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenApp/CodexAgentDisplayStateRefresher.swift)
- [CodexAgentPresentationCoordinator.swift](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenApp/CodexAgentPresentationCoordinator.swift)
- [GhosttySurfaceHost.swift](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceHost.swift)
- [bin/codex](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenApp/AgentResources/bin/codex)
- [bin/claude](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenApp/AgentResources/bin/claude)
- [devhaven-claude-hook](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenApp/AgentResources/hooks/devhaven-claude-hook)

## 1. 摘要

本文定义 DevHaven 下一代 Agent Runtime 的完整功能方案。目标不是继续堆叠零散 signal，而是把当前的“wrapper signal + 可见文本猜测”升级为“多源事件采集 -> 会话融合 -> UI 投影”的统一运行时。

这份文档覆盖：

- 功能目标与边界
- 会话状态机
- 数据模型
- 事件来源与适配器
- 运行时融合规则
- UI 投影规则
- 分阶段实施计划
- 验证标准与风险控制

本文档是未来实现的功能真相源。实现过程中若发现与当前代码现实不符，应更新文档，而不是在代码里悄悄偏离。

## 2. 背景

当前 DevHaven 已经具备基本的 Agent 状态感知能力：

- 终端宿主会在启动 CLI 前注入 `DEVHAVEN_AGENT_SIGNAL_DIR` 与 `DEVHAVEN_AGENT_RESOURCES_DIR`
  - 入口位于 [GhosttySurfaceHost.swift:162](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceHost.swift#L162) 和 [GhosttySurfaceHost.swift:174](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceHost.swift#L174)
- `codex` wrapper 会在运行前后写入 `running/completed/failed`，并通过 notify 把会话切换为 `waiting`
  - 见 [bin/codex](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenApp/AgentResources/bin/codex)
- `claude` wrapper 会注入 hooks，并由 [devhaven-claude-hook](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenApp/AgentResources/hooks/devhaven-claude-hook) 转成 signal
- `WorkspaceAgentSignalStore` 负责监听 signal 目录
  - 见 [WorkspaceAgentSignalStore.swift:72](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenCore/Storage/WorkspaceAgentSignalStore.swift#L72)
- `NativeAppViewModel` 直接把 signal 应用到 `WorkspaceAttentionState`
  - 见 [NativeAppViewModel.swift:7709](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift#L7709)
- Codex 额外通过可见文本窗口做运行态修正
  - 见 [CodexAgentDisplayStateRefresher.swift:45](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenApp/CodexAgentDisplayStateRefresher.swift#L45)

这条链路已经能工作，但存在结构性不足。

## 3. 当前问题

### 3.1 状态模型过粗

当前 `WorkspaceAgentState` 只有：

- `unknown`
- `running`
- `waiting`
- `idle`
- `completed`
- `failed`

这不够表达真实 agent 语义。对于用户来说：

- “等待输入”
- “等待审批”
- “正在思考”
- “正在执行工具”
- “仅有普通提醒”

是完全不同的状态，但现在都被折叠成 `waiting` 或 `running`。

### 3.2 Signal 被当成最终真相

当前 `WorkspaceAgentSessionSignal` 直接映射到 `WorkspaceAttentionState`，中间没有统一的会话融合层。这会导致：

- 后到达的弱信号可能覆盖强信号
- UI 修正逻辑只能在 view/app 层临时打补丁
- 不同来源的事件没有统一优先级

### 3.3 Codex 的真实状态依赖 UI 猜测

Codex 当前通过 wrapper 发出基础 signal，但为了区分“仍在运行”还是“已等待用户输入”，又引入了 visible text heuristics。这个方向本身没错，但现在它存在于 UI 层，且只服务 Codex，导致：

- runtime 真相不完整
- 规则分散在 UI 层
- pane 不可见或未聚焦时可靠性下降

### 3.4 Notification 与 Agent State 混在同一投影结构里

当前 [WorkspaceNotificationModels.swift:92](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenCore/Models/WorkspaceNotificationModels.swift#L92) 的 `WorkspaceAttentionState` 同时承载：

- notifications
- task status
- agent state
- agent summary

这使得“通知收件箱”和“agent 运行态”难以独立演进。

### 3.5 没有统一的事件语义

当前 Claude/Codex 的接入方式不对称：

- Claude 以 hook 事件为主
- Codex 以 wrapper + notify 为主

但进入 App 后都被压平成同一个简化 signal，损失了大量上下文信息。

## 4. 产品目标

### 4.1 核心目标

1. DevHaven 必须准确表达内嵌终端中 AI agent 的真实运行态。
2. Agent 状态必须以“会话”为中心，而不是以“单次 signal 文件”为中心。
3. App 必须能区分“运行态”和“用户是否需要介入”。
4. 不同来源的事件必须进入统一融合层，不能由多个 UI 组件各自猜测。
5. Pane、Project、Workspace 三个层级都要能消费同一份 runtime 真相。
6. 方案必须兼容现有 wrapper 与 signal 文件，不允许一次性推翻全部集成。

### 4.2 体验目标

1. 用户一眼能看出 agent 当前在做什么。
2. 用户一眼能看出当前是否需要自己操作。
3. 当 agent 需要审批、提问或完成一轮回复时，UI 应给出结构化提示，而不是只显示“等待”。
4. 当 pane 不可见时，状态仍然尽量准确，不依赖屏幕可见文本作为唯一真相。

### 4.3 工程目标

1. 真相源收敛到 runtime 层，不散落在 SwiftUI 视图里。
2. 新增 agent 或新增事件来源时，只需要新增 adapter，不需要重写整套 UI。
3. 兼容开发态与 release `.app`。
4. 保持当前 PATH/wrapper 模式，不改成修改用户全局 CLI 配置的模式。

## 5. 非目标

1. 不做桌面级全局 AI session 监听器。
   DevHaven 只追踪自己启动并绑定过的 session。
2. 不引入必须常驻的外部 helper service 或 XPC daemon。
3. 不把 transcript watcher 变成“读取用户所有历史会话内容”的通用索引器。
4. 不做跨设备、跨机器、跨用户同步。
5. 不保证兼容所有第三方 CLI。
   第一阶段只覆盖 DevHaven 已正式接入的 `Claude` 与 `Codex`。

## 6. 用户场景

### 6.1 正常对话

用户在某个 pane 中启动 `codex` 或 `claude`。App 应显示：

- 会话已开始
- 当前正在思考或正在执行工具
- 本轮完成后等待用户输入

### 6.2 工具审批

Agent 在执行工具时需要用户审批。App 应显示：

- 当前不是普通 waiting，而是 `awaitingApproval`
- accessory 和 project list 应强调“等待审批”
- 可选地生成通知项或 badge

### 6.3 Agent 提问

Agent 向用户提问而不是等待工具审批。App 应显示：

- `awaitingInput`
- 最新摘要为问题摘要或最近 assistant message
- 聚焦到对应 pane 时状态可以被解决

### 6.4 Pane 不可见但会话仍在继续

用户切换到其它 tab 或隐藏当前 pane。App 仍应根据 transcript/session artifact 感知：

- session 仍在活跃
- 当前阶段是否继续推进
- 是否已完成一轮并等待用户

### 6.5 会话异常结束

CLI 进程异常退出或 signal 停滞。App 应区分：

- 正常 completed
- failed
- stale

而不是统一当作 idle。

## 7. 名词与语义定义

### 7.1 Source Artifact

某个具体来源提供的原始事实。例子：

- wrapper 写出的 signal
- Claude hook payload
- Codex turn-complete notify
- Codex session artifact 的文件增量
- pane 的 visible text snapshot

### 7.2 Session Record

DevHaven 在 runtime 层维护的统一会话对象。一个 session record 表示：

- 某个 agent
- 在某个 DevHaven pane / terminal session 上
- 当前处于何种 phase
- 是否需要用户关注

### 7.3 Phase

Agent 的内部运行阶段。关注“agent 正在做什么”。

### 7.4 Attention

用户的介入需求。关注“用户现在要不要操作”。

### 7.5 Projection

把 session record 投影成 UI 可消费的结构，比如：

- pane accessory
- project list badge
- notification popover item

## 8. 目标架构

完整架构分四层。

### 8.1 Session Artifact Layer

负责采集原始事实，不做最终状态决策。

新增模型建议：

- `WorkspaceAgentEvent`
- `WorkspaceAgentEventSource`
- `WorkspaceAgentSourceSnapshot`
- `WorkspaceAgentSessionBinding`
- `WorkspaceAgentCLIContext`

建议文件：

- `macos/Sources/DevHavenCore/Models/WorkspaceAgentEventModels.swift`
- `macos/Sources/DevHavenCore/Models/WorkspaceAgentRuntimeModels.swift`

### 8.2 Source Adapter Layer

负责把各来源的事实转换成统一 event。

建议 adapter：

- `WrapperSignalAdapter`
- `ClaudeHookEventAdapter`
- `CodexNotifyEventAdapter`
- `CodexSessionArtifactWatcher`
- `CodexTranscriptTailWatcher`
- `VisibleTextFallbackAdapter`
- `WorkspaceAgentNotificationAdapter`

### 8.3 Fusion Engine Layer

负责把 event 和 source snapshot 融合为统一 session record。

建议核心对象：

- `WorkspaceAgentSessionFusionEngine`
- `WorkspaceAgentSessionStore`

### 8.4 Projection Layer

负责从 session record 生成 UI 所需的各种投影。

建议核心对象：

- `WorkspaceAgentProjectionEngine`
- `WorkspacePaneAgentProjection`
- `WorkspaceProjectAgentProjection`

## 9. 功能需求

### 9.1 会话生命周期管理

系统必须支持这些生命周期事件：

- `sessionStarted`
- `userPromptSubmitted`
- `assistantMessageProduced`
- `toolStarted`
- `toolFinished`
- `approvalRequested`
- `approvalResolved`
- `questionAsked`
- `turnCompleted`
- `sessionCompleted`
- `sessionFailed`
- `sessionStale`

这些事件必须能映射到统一 session record。

### 9.2 统一状态机

系统必须把当前粗粒度状态扩展为更完整的 phase。

建议定义：

- `unknown`
- `launching`
- `thinking`
- `runningTool`
- `awaitingApproval`
- `awaitingInput`
- `notifying`
- `idle`
- `completed`
- `failed`
- `stale`

### 9.3 Attention 独立建模

Attention 必须独立于 phase，建议定义：

- `none`
- `soft`
- `question`
- `approval`
- `error`

理由：

- `completed` 并不一定需要 attention
- `awaitingInput` 一定需要 question attention
- `runningTool` 在大部分情况下不需要用户介入

### 9.4 多源融合

系统必须支持多个信号源同时描述一个 session。

最少支持：

- wrapper signal
- hook event
- notify event
- codex session artifact 增量
- transcript 尾部更新
- visible text fallback

融合引擎必须定义来源优先级，而不是按“最后写入者”生效。

### 9.5 Pane 绑定与会话绑定

每条 session record 必须能稳定绑定到：

- `projectPath`
- `workspaceId`
- `tabId`
- `paneId`
- `surfaceId`
- `terminalSessionId`

如果某个来源缺少完整绑定信息，必须通过既有上下文或已知会话关系补齐，不能在 UI 层临时猜。

### 9.6 摘要与标题

系统必须支持每条 session 的：

- 标题
- 简短摘要
- 最近 agent 输出摘要
- 最近工具名
- 最近错误信息

其中标题和摘要优先来自结构化来源，visible text 仅做 fallback。

### 9.7 UI 投影

系统必须至少支持三种投影：

- pane accessory
- project list 聚合状态
- notification/popover

这些投影必须共享同一份 runtime 真相，不允许各自维护独立状态机。

### 9.8 兼容旧 signal

现有 `WorkspaceAgentSessionSignal` 仍需保留，作为 wrapper/hook 与 runtime 的兼容层。

兼容要求：

- 老 signal 文件仍可读
- 老 wrapper 不立即失效
- runtime 可逐步迁移到新 event 模型

## 10. 数据模型

### 10.1 保留模型

保留现有：

- `WorkspaceAgentSessionSignal`
- `WorkspaceAgentKind`
- `WorkspaceAgentState`

但它们的角色降级为：

- 兼容磁盘协议
- 老 UI 兼容桥接

而不是最终真相源。

### 10.2 新增 Runtime 模型

建议新增：

```swift
enum WorkspaceAgentPhase
enum WorkspaceAgentAttentionRequirement
enum WorkspaceAgentEventKind
enum WorkspaceAgentEventSourceKind

struct WorkspaceAgentEvent
struct WorkspaceAgentSourceSnapshot
struct WorkspaceAgentSessionRecord
struct WorkspaceAgentSessionBinding
struct WorkspaceAgentProjection
```

`WorkspaceAgentSessionRecord` 至少包含：

- `sessionID`
- `agentKind`
- `binding`
- `phase`
- `attention`
- `summary`
- `detail`
- `title`
- `lastActivityAt`
- `lastAssistantActivityAt`
- `lastToolActivityAt`
- `lastUserActivityAt`
- `sourceSnapshots`
- `sourceConfidence`

### 10.3 Projection 模型

建议新增：

```swift
struct WorkspacePaneAgentProjection
struct WorkspaceProjectAgentProjection
struct WorkspaceAgentActionSuggestion
```

`WorkspacePaneAgentProjection` 至少包含：

- `paneID`
- `agentKind`
- `phase`
- `attention`
- `label`
- `summary`
- `updatedAt`
- `isUserActionRequired`
- `suggestedAction`

## 11. 状态转移规则

### 11.1 强信号优先

这些事件属于强信号：

- `approvalRequested`
- `questionAsked`
- `sessionCompleted`
- `sessionFailed`

强信号进入后，弱信号不能立即覆盖它。

### 11.2 Transcript 与 Session Artifact 用于补强

对 Codex：

- session artifact 或 transcript 文件持续增长，表示 session 仍活跃
- 如果增长内容属于 assistant reasoning，可判定为 `thinking`
- 如果增长内容对应工具事件，可判定为 `runningTool`
- 如果出现 turn complete 且没有审批/问题事件，则判定为 `awaitingInput`

### 11.3 Visible Text 只做 fallback

visible text 只能在这些条件下参与修正：

- 当前 session 缺少更强 source
- signal 与 transcript 都沉默
- phase 仍不确定

visible text 不能覆盖：

- `completed`
- `failed`
- `awaitingApproval`

### 11.4 TTL 与 Stale 处理

当 session 超过 TTL 且 pid 不存活时：

- 先进入 `stale`
- 再由清理任务移除 source artifact

清理不应直接绕过 runtime store。

## 12. Source Adapter 设计

### 12.1 WrapperSignalAdapter

职责：

- 读取当前 signal 文件
- 转换为 `WorkspaceAgentEvent`
- 补齐 session binding

现有 [WorkspaceAgentSignalStore.swift](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenCore/Storage/WorkspaceAgentSignalStore.swift) 可继续保留，但只负责底层文件监听，不再直接更新 UI attention。

### 12.2 ClaudeHookEventAdapter

职责：

- 解析 Claude hook 事件
- 规范化为：
  - `sessionStarted`
  - `userPromptSubmitted`
  - `toolStarted`
  - `questionAsked`
  - `approvalRequested`
  - `assistantNotification`
  - `sessionCompleted`
  - `sessionEnded`

实现入口仍然来自：

- [bin/claude](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenApp/AgentResources/bin/claude)
- [devhaven-claude-hook](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenApp/AgentResources/hooks/devhaven-claude-hook)

### 12.3 CodexNotifyEventAdapter

职责：

- 解析 `agent-turn-complete`
- 将其转化为 `turnCompleted`
- 触发 phase 从 `thinking/runningTool` 进入 `awaitingInput`

当前 notify 逻辑位于 [devhaven-codex-notify](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenApp/AgentResources/bin/devhaven-codex-notify)。

### 12.4 CodexSessionArtifactWatcher

职责：

- 监听 DevHaven 已知 session 对应的 Codex artifact
- 感知标题、近期活动、turn 变化

关键原则：

- 只 watch DevHaven 启动并绑定过的 session
- 不做全局陌生 session 扫描

### 12.5 CodexTranscriptTailWatcher

职责：

- 从 transcript 尾部提取：
  - 最近 assistant message 摘要
  - 最近 reasoning/tool 迹象
  - 最近 activity 时间

它提供的是 source snapshot，不直接更新 UI。

### 12.6 VisibleTextFallbackAdapter

职责：

- 从 `GhosttySurfaceHostModel` 的可见文本窗口获取有限上下文
- 仅在其它来源沉默时提供 fallback

当前 [CodexAgentDisplayStateRefresher.swift](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenApp/CodexAgentDisplayStateRefresher.swift) 需要在后续被降级为这个 adapter。

## 13. Runtime Store 与 Fusion Engine

### 13.1 Store 职责

`WorkspaceAgentSessionStore` 负责：

- 存储 session record
- 为 session 维护 source snapshot
- 提供按 pane/project/workspace 查询
- 触发 projection rebuild

### 13.2 Fusion Engine 职责

`WorkspaceAgentSessionFusionEngine` 负责：

- ingest event
- 应用状态转移规则
- 决定 phase/attention
- 合并 source snapshot
- 输出最终 session record

### 13.3 明确禁止的事情

Fusion engine 之外的模块不得：

- 直接改 phase
- 直接决定 attention
- 直接把 visible text 作为 UI override 真相

## 14. UI 投影与行为

### 14.1 Pane Accessory

当前 [WorkspaceAgentStatusAccessory.swift](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenApp/WorkspaceAgentStatusAccessory.swift) 只支持粗状态。升级后至少要支持：

- `Claude 正在思考`
- `Claude 正在执行工具`
- `Claude 等待你的回复`
- `Claude 等待审批`
- `Codex 正在思考`
- `Codex 正在执行工具`
- `Codex 等待你的回复`
- `Codex 等待审批`
- `Codex 失败`
- `Codex 已完成`

### 14.2 Project List 聚合

Project list 不应该只显示“当前最相关 state”，而应该遵循：

- 优先显示 `approval`
- 其次显示 `question`
- 其次显示 `failed`
- 其次显示 `runningTool/thinking`
- 最后才是 `awaitingInput` 或 `completed`

### 14.3 Notification Popover

notification 收件箱与 agent runtime 必须分离，但可以互相关联。

例子：

- `approvalRequested` 可生成一条 action-oriented notification
- `questionAsked` 可生成一条可聚焦 notification
- 普通 `assistantMessageProduced` 不一定需要入 notification inbox

### 14.4 Suggested Action

投影层需要产出建议动作：

- `focusPane`
- `reviewApproval`
- `replyToAgent`
- `openNotification`
- `dismiss`

这样 UI 可以从“静态显示状态”升级成“提供下一步动作”。

## 15. 对现有代码的具体演进要求

### 15.1 `WorkspaceAgentSessionSignal` 降级

文件：

- [WorkspaceAgentSessionModels.swift](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenCore/Models/WorkspaceAgentSessionModels.swift)

要求：

- 保留现有结构以兼容磁盘协议
- 不再把它视为最终 runtime 模型
- 新 runtime 模型另起文件

### 15.2 `WorkspaceAgentSignalStore` 只做文件监听

文件：

- [WorkspaceAgentSignalStore.swift](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenCore/Storage/WorkspaceAgentSignalStore.swift)

要求：

- 继续负责目录监听和 stale sweep
- 不再直接驱动 attention 投影
- 改为把 snapshot 发给 fusion engine

### 15.3 `NativeAppViewModel` 不再直接应用 raw signal

文件：

- [NativeAppViewModel.swift](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift)

要求：

- 删除或下沉 `applyAgentSignal(signal, to:)` 这种直接写 `WorkspaceAttentionState` 的路径
- 改为消费 projection engine 结果

### 15.4 Codex special-case 退位

文件：

- [CodexAgentDisplayStateRefresher.swift](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenApp/CodexAgentDisplayStateRefresher.swift)
- [CodexAgentPresentationCoordinator.swift](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenApp/CodexAgentPresentationCoordinator.swift)

要求：

- 不再直接输出 UI override 真相
- 改为可见文本 fallback source

### 15.5 Wrapper 与 Hook 结构化

文件：

- [bin/codex](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenApp/AgentResources/bin/codex)
- [bin/claude](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenApp/AgentResources/bin/claude)
- [devhaven-claude-hook](/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/Sources/DevHavenApp/AgentResources/hooks/devhaven-claude-hook)

要求：

- 保留当前 wrapper 路线
- 丰富结构化事件语义
- 不改成修改用户全局配置文件的模式

## 16. 分阶段实施

### Phase 1：Runtime 模型与 Fusion 主干

交付：

- 新增 runtime models
- 新增 event models
- 新增 fusion engine
- 新增 session store

完成标准：

- 不改变当前 UI 外观
- raw signal 可以进入新 runtime store
- 旧代码仍可工作

### Phase 2：Projection Engine 与 UI 接线

交付：

- 新 projection models
- 新 projection engine
- `NativeAppViewModel` 改为消费 projection
- accessory 与 project list 接线

完成标准：

- 旧 `WorkspaceAttentionState` 不再承担最终 agent 真相
- UI 能显示更细 phase

### Phase 3：Codex 深度接入

交付：

- `CodexSessionArtifactWatcher`
- `CodexTranscriptTailWatcher`
- Codex phase 融合规则

完成标准：

- pane 不可见时仍能稳定区分 `thinking / runningTool / awaitingInput`
- Codex 摘要不再只依赖 visible text

### Phase 4：Claude 事件规范化

交付：

- 结构化 Claude hook 事件
- `approval/question/notification` 单独建模

完成标准：

- Claude 的 “等待” 被拆为 `awaitingApproval` 与 `awaitingInput`

### Phase 5：清理旧路径

交付：

- 删除或压缩 old raw signal -> attention 直连逻辑
- `CodexAgentDisplayStateRefresher` 退化为 fallback adapter

完成标准：

- runtime 真相只存在一处
- UI override 不再是第二状态机

## 17. 验证标准

### 17.1 单元测试

必须新增：

- phase 状态转移测试
- source 优先级测试
- stale cleanup 测试
- projection 排序测试

### 17.2 集成测试

至少覆盖：

- Codex `running -> turn complete -> awaitingInput -> completed`
- Codex `runningTool -> awaitingApproval -> runningTool -> completed`
- Claude `SessionStart -> PreToolUse -> Notification -> Stop`
- Claude `SessionStart -> UserPromptSubmit -> questionAsked -> awaitingInput`

### 17.3 UI 验证

至少覆盖：

- pane accessory 文案和图标
- project list 聚合排序
- notification popover 行为
- 切换 tab / pane / project 时状态一致性

### 17.4 手工验证

至少验证：

- pane 可见
- pane 不可见
- tab 未选中
- split 后 pane 复用
- session 正常退出
- session 崩溃退出

## 18. 成功指标

实现完成后，希望达到：

1. `awaitingApproval` 和 `awaitingInput` 不再混淆。
2. Codex 会话在 pane 不可见时，状态仍稳定。
3. UI 不再依赖可见文本作为主要真相源。
4. 新增 agent 类型时，只需新增 adapter，不需重写 UI。

## 19. 风险与缓解

### 风险 1：状态机过度复杂

缓解：

- phase 与 attention 分离
- 所有状态转移集中在 fusion engine
- 用测试表驱动验证

### 风险 2：Codex artifact 结构不稳定

缓解：

- watcher 只抽取稳定字段
- 文件解析失败时退回 wrapper signal
- visible text 作为最后 fallback

### 风险 3：兼容路径过长

缓解：

- 保留旧 signal 协议
- 通过 phase 分阶段替换，不一次性删除旧逻辑

### 风险 4：UI 与 runtime 再次分叉

缓解：

- UI 只消费 projection
- view 层禁止直接做 phase 决策

## 20. 决策

本方案的最终决策如下：

1. DevHaven 不采用 Vibe Island 那种“修改用户全局 CLI 配置”的接入方式。
2. DevHaven 继续坚持 wrapper + 内嵌终端环境注入路线。
3. 当前 `signal store -> attention state` 的直连模式结束，未来改为 `source adapter -> fusion engine -> projection engine -> UI`。
4. visible text 保留，但只作为 fallback source，不再承担主要真相职责。
5. Codex 必须新增 session artifact / transcript watcher，Claude 必须新增结构化 approval/question 事件。

## 21. 后续输出物

基于本功能文档，下一步应继续产出两份实现级文档：

1. 类型定义与状态转移表
   - 精确列出每个枚举、结构体字段、source 优先级、phase 转移条件
2. 文件级实施计划
   - 精确列出每个 phase 需要改哪些文件、增加哪些测试、删除哪些旧逻辑

在这两份文档完成前，不建议直接开始大范围实现。
