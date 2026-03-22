# DevHaven Agent 会话状态感知设计

## 背景
DevHaven 当前已经具备工作区通知能力：Ghostty bridge 能把 `desktop notification`、`progress report`、`bell` 收口到 `NativeAppViewModel` 的运行时注意力状态中，并在侧边栏展示 bell / spinner / 未读通知。但这条链路仍然只覆盖“终端发生了提醒”，无法可靠回答下面这类更关键的问题：

- Claude 现在是不是正在运行？
- Claude 是已经停下来，还是正在等待用户输入 / 权限确认？
- Codex 当前 pane 里是否仍有活跃会话？
- 某个 pane 的“运行中”到底是普通终端任务，还是 AI agent 会话？

这类问题的本质不是终端提醒，而是 **agent 生命周期观测**。cmux 和近期 GitHub 上较成熟的 Claude/Codex 状态栏项目都说明：如果只依赖终端通知或屏幕内容分析，状态会非常脆弱；稳定方案通常都要引入独立的 agent 适配层。

## 目标
为 DevHaven 增加一套最小但可靠的 **Agent 会话状态感知** 能力，优先覆盖 Claude 与 Codex：

1. 在 DevHaven 打开的 terminal pane 中，识别 Claude / Codex 会话是否处于 `running` / `waiting` / `idle` / `completed` / `failed`。
2. 将 agent 状态以 pane 为粒度并入现有 workspace 注意力状态，供侧边栏与工作区 UI 统一消费。
3. 让 DevHaven 能通过会话摘要文案提示“当前在做什么”，而不是只显示普通 spinner。
4. 保持最少改动：不先做 socket 控制面，不先做通知历史持久化，不先做 transcript 全量索引。

## 非目标
本次设计明确不做：

- 不做 agent 对话历史持久化或全文检索。
- 不做 Codex “等待用户输入” 的复杂内容分析主链。
- 不做 agent 状态设置项（先默认开启，仅在 DevHaven 内部终端生效）。
- 不做多 agent 并发编排 UI；V1 只保证“一个 pane 的前台 agent 状态可观测”。

## 设计原则
1. **Agent 状态独立于 Ghostty 终端事件。** Ghostty 继续负责终端 title / cwd / bell / progress；Claude/Codex 生命周期由专门适配器负责。
2. **文件信号优先于 socket。** V1 先采用本地 signal file，保证实现简单、可调试、App 未运行时也不丢状态。
3. **统一事件模型，按 agent 适配。** UI 不直接感知 Claude/Codex 差异，而是消费统一的 `WorkspaceAgentState`。
4. **最少侵入现有运行时状态。** 尽量复用 `WorkspaceAttentionState`、`NativeAppViewModel`、`WorkspaceSidebarProjectGroup` / `WorkspaceSidebarWorktreeItem`，只补充 agent 维度字段。
5. **Codex 现实优先。** Claude 以 hooks 为主真相源；Codex 在官方 lifecycle hooks 仍不完整的前提下，先走 wrapper + 进程退出 + notify 补偿。

## 方案比较

### 方案 A：wrapper / hooks -> signal 文件 -> App 监听（推荐）
**做法：**
- 在 DevHaven terminal 环境中把 `Resources/bin` 放到 PATH 前面，拦截 `claude` / `codex`。
- Claude wrapper 注入 hooks，并由 hook 写本地 JSON signal 文件。
- Codex wrapper 在启动时写 `running`，退出时写 `completed` / `failed`，后续可选接 `notify`。
- App 侧监听 `~/.devhaven/agent-status/sessions/` 目录，把 JSON 同步到 `NativeAppViewModel`。

**优点：**
- 与 `claude-status`、`cc-status-bar`、`iTerm2 tab status` 等现成方案一致，成熟度高。
- 简单、可调试、崩溃后仍有最后状态可读。
- 适合当前 DevHaven 的原生单进程架构。

**缺点：**
- 写入文件不是纯实时总线，需要目录监听 + 定时 sweep。
- Claude 与 Codex 仍需分别适配。

### 方案 B：wrapper / shell integration -> Unix socket -> App 收口
**做法：**
- 类似 cmux，给 DevHaven 增加本地 socket server，由 wrapper / hooks / shell integration 往 socket 发事件。

**优点：**
- 扩展性最强，未来可继续纳入 shell state、cwd、端口、git、PR 等更丰富遥测。
- 延迟低，适合高频事件。

**缺点：**
- 实现成本明显更高。
- App 未运行时会丢事件，需要重放 / 缓冲补偿。
- 当前目标只是识别 Claude/Codex 是否正在运行，属于过度工程。

### 方案 C：直接分析 pane 内容 / scrollback
**做法：**
- 像 `claude-tmux` 一样读取 terminal 文本，匹配 prompt、`[y/n]`、`ctrl+c to interrupt` 等模式。

**优点：**
- 不依赖 hooks / wrapper。
- 对未知 agent 有兜底价值。

**缺点：**
- 最脆弱，强依赖输出格式。
- 难以稳定区分 running / waiting / completed。
- 不适合作为主链，只能做 fallback。

## 结论
采用 **方案 A：wrapper / hooks -> signal 文件 -> App 监听**。

理由：
- 最贴近当前 DevHaven 技术栈与代码结构；
- 可以在不引入 socket 的前提下快速获得 Claude/Codex 可观测性；
- 后续若要升级到 cmux 风格控制面，signal store 和统一事件模型都可以保留，只需更换传输层。

## 架构设计

### 1. 统一 Agent 会话模型
新增 `WorkspaceAgentSessionModels.swift`，定义：

- `WorkspaceAgentKind`
  - `claude`
  - `codex`
- `WorkspaceAgentState`
  - `unknown`
  - `running`
  - `waiting`
  - `idle`
  - `completed`
  - `failed`
- `WorkspaceAgentSessionSignal`
  - `projectPath`
  - `workspaceId`
  - `tabId`
  - `paneId`
  - `surfaceId`
  - `terminalSessionId`
  - `agentKind`
  - `sessionId`
  - `pid`
  - `state`
  - `summary`
  - `detail`
  - `updatedAt`

V1 使用“每个 terminal session 一份当前态文件”，而不是追加事件日志。这样 App 启动后能直接读取当前最后状态。

### 2. Signal 文件目录与命名
新增目录：

```text
~/.devhaven/agent-status/sessions/
```

文件名使用：

```text
<terminalSessionId>.json
```

原因：
- DevHaven 当前 `WorkspaceTerminalLaunchRequest` 已经有稳定的 `terminalSessionId`；
- 侧边栏和 pane 聚合本来就是按 `projectPath + paneId + terminalSessionId` 工作；
- 顺序执行多个 agent 时采用最后写入覆盖即可，足够满足 V1 的“当前状态”目标。

### 3. 资源布局
由于 SwiftPM 可执行 target 的资源位于 `macos/Sources/DevHavenApp/` 下，本次新增：

```text
macos/Sources/DevHavenApp/AgentResources/
  bin/
    claude
    codex
    devhaven-agent-emit
  hooks/
    devhaven-claude-hook
```

并在 `macos/Package.swift` 中把 `AgentResources` 复制进 App 资源 bundle。

### 4. Terminal 环境注入
`WorkspaceTerminalLaunchRequest.environment` 已经提供：

- `DEVHAVEN_PROJECT_PATH`
- `DEVHAVEN_WORKSPACE_ID`
- `DEVHAVEN_TAB_ID`
- `DEVHAVEN_PANE_ID`
- `DEVHAVEN_SURFACE_ID`
- `DEVHAVEN_TERMINAL_SESSION_ID`

本次仅在 App 层补充运行时可解析的资源路径与 signal 目录，例如：

- `DEVHAVEN_AGENT_SIGNAL_DIR`
- `DEVHAVEN_AGENT_RESOURCES_DIR`
- `PATH=<bundle>/AgentResources/bin:$PATH`

这一步应放在 `GhosttySurfaceHostModel` 创建 `GhosttyTerminalSurfaceView` 前完成，避免把 bundle 资源定位逻辑塞进 Core。

### 5. Claude 适配器
Claude wrapper 工作流：

```text
用户在 DevHaven terminal 输入 claude
-> PATH 命中 AgentResources/bin/claude
-> wrapper 判断当前是否处于 DevHaven shell
-> 注入 session-id 与 hooks 设置
-> hooks 调用 devhaven-claude-hook
-> hook 统一调用 devhaven-agent-emit 写 signal 文件
```

V1 状态映射：

- `SessionStart` -> `idle`
- `UserPromptSubmit` -> `running`
- `PreToolUse` -> `running`，附带 `summary`
- `Notification` -> `waiting`
- `Stop` -> `completed`
- `SessionEnd` -> `idle` 或清理文件

若 hook payload 中有问题文本、工具名、transcript 路径，则尽量提炼成短摘要；没有则回退到通用文案。

### 6. Codex 适配器
Codex 当前不假设有完整 lifecycle hooks。V1 策略：

```text
用户在 DevHaven terminal 输入 codex
-> PATH 命中 AgentResources/bin/codex
-> wrapper 在启动前写 running
-> 启动真实 codex 子进程并 wait
-> 进程正常退出写 completed
-> 进程异常退出写 failed
```

后续可扩展：
- 如果检测到 Codex `notify` 能提供 turn-complete，再补更准确的 `completed`；
- 如果未来有 waiting / permission 事件，再补 `waiting`；
- 纯 pane 内容分析只作为后备方案，不进入 V1。

### 7. App 侧 signal ingest
新增 `WorkspaceAgentSignalStore`：

职责：
1. 监听 `agent-status/sessions` 目录。
2. 对新增 / 修改的 JSON 做 decode。
3. 暴露当前所有 session 的快照字典。
4. 定时清理 stale session：
   - 超过阈值未更新；
   - 且 pid 已不存在；
   - 则改为 `idle` 或移除文件。

### 8. ViewModel 聚合
在 `NativeAppViewModel` 中新增一层 pane 级 agent 运行态聚合，但不另起一整套 UI 状态容器，而是扩展 `WorkspaceAttentionState`：

- `agentStateByPaneID`
- `agentSummaryByPaneID`
- `agentKindByPaneID`
- 可选：`agentSessionIDByPaneID`

同时增加：

- `recordAgentSignal(_:)`
- `clearAgentSignal(projectPath:paneID:)`
- `workspaceAgentState(for:)`

聚合规则：
- `waiting` 优先级高于 `running`
- `running` 高于 `idle`
- `completed` / `failed` 只保留短时提示，不长期顶替 pane 的普通任务状态

### 9. UI 展示
V1 只做最小展示：

- root project 行：
  - 有任一 pane `waiting` -> 红色 attention 徽标
  - 否则有任一 pane `running` -> agent 徽标 / spinner
- worktree 行：
  - 优先显示 agent 状态，再回退到普通 task status
  - tooltip 或副文案显示 `summary`

不做：
- 独立 agent timeline popover
- agent 历史面板
- transcript 面板

## 数据流

### Claude
```text
claude wrapper
-> devhaven-claude-hook
-> devhaven-agent-emit 写 <terminalSessionId>.json
-> WorkspaceAgentSignalStore 监听变更
-> NativeAppViewModel.recordAgentSignal
-> workspaceSidebarGroups / 工作区 UI 更新
```

### Codex
```text
codex wrapper 启动
-> emit running
-> 真实 codex 子进程执行
-> 退出时 emit completed/failed
-> WorkspaceAgentSignalStore ingest
-> NativeAppViewModel 聚合
```

## 风险与边界
1. **Codex waiting 态不保证精确。** 在官方 hooks 不完整前，V1 只承诺 running / completed / failed。
2. **同一 pane 多 agent 嵌套不在 V1 解决。** 采用最后写入覆盖；异常情况通过 stale sweep 回收。
3. **PATH 注入必须仅影响 DevHaven 自己的 terminal。** wrapper 外部运行时应完全透传，不影响系统 shell。
4. **资源定位不能污染 Ghostty runtime 逻辑。** 新增通用资源定位 helper，避免把 AgentResources 硬塞进 `GhosttyAppRuntime` 的职责里。

## 测试策略
1. **Core 单测**
   - `WorkspaceAgentSignalStore`：decode、目录扫描、stale sweep
   - `NativeAppViewModel`：agent signal 聚合、waiting/running 优先级、侧边栏映射
2. **App 单测**
   - 资源定位与 PATH 注入
   - wrapper 脚本在模拟环境下写出预期 JSON
   - 侧边栏视图源码/行为测试：agent 徽标与摘要入口
3. **全量验证**
   - `swift test --package-path macos`
   - `swift build --package-path macos`

## 实施顺序
1. 先定义统一模型与 signal store。
2. 再打通资源定位与 terminal 环境注入。
3. 然后接入 Claude wrapper / hook。
4. 再接 Codex wrapper。
5. 最后把状态映射到 `NativeAppViewModel` 与侧边栏 UI。
