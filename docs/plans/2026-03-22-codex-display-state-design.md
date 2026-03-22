# DevHaven Codex 展示态修正设计

## 背景
当前 DevHaven 对 Codex 的状态真相源是 `AgentResources/bin/codex` wrapper 写入的 signal：启动前写 `running`，进程退出后写 `completed / failed`。这条链路能稳定表示“Codex 进程是否还活着”，但不能表达交互式 TUI 中“一轮任务已结束，正在等待下一次输入”的中间态。

用户现场截图说明：Codex 在同一个交互会话内完成当前回合后，侧边栏仍显示“Codex 正在运行”。这不是单纯 UI 文案错误，而是 **进程态被误当成任务回合态**。当前 signal 链路没有坏，坏的是“如何把 signal 映射为用户可理解的展示态”。

## 目标
在**不改底层 signal 文件协议**的前提下，让 DevHaven 能把交互式 Codex pane 的展示态修正为更贴近用户语义的状态：

1. Codex 真正在工作时，显示“Codex 正在运行”；
2. Codex 已结束当前回合、回到输入框等待下一条消息时，显示“Codex 等待输入”；
3. 非交互式 `codex run ...`、真实退出、失败等现有链路保持兼容；
4. 避免出现“Codex 正在运行：Codex 正在运行”这类重复文案。

## 非目标
- 不重写 Codex wrapper 主链；
- 不把 UI 猜测结果写回 signal 文件；
- 不引入 transcript 持久化或完整 scrollback 语义分析；
- 不试图在本次修复中精确识别全部 Codex permission / approval 子状态。

## 约束与事实
1. `WorkspaceAgentSignalStore` 当前是运行时瞬时状态真相源，负责 signal 文件监听、超时清理、completed/failed 回落；
2. `GhosttySurfaceView.debugVisibleText()` 已具备读取当前 pane 可见文本的能力，说明我们可以在 App 内部做只读启发式判断；
3. `GhosttySurfaceHostModel` 已由 `WorkspaceTerminalSessionStore` 以 pane 维度缓存，适合作为读取可见文本的入口；
4. AGENTS 约束要求最少修改，并避免把 UI 规则塞回 signal 存储层。

## 方案比较

### 方案 A：只改文案
把 running 文案改成“会话活跃”。

- 优点：改动极小；
- 缺点：不解决“当前任务已完成却仍像在跑”的核心误导。

### 方案 B：展示层引入 Codex 可见文本启发式修正（推荐）
保留底层 signal 作为进程态真相源，仅在 App 内存里对 `codex + running` 做展示态覆盖：

- 若可见文本表明 Codex 当前正在执行，则继续显示 `running`；
- 若可见文本表明 Codex 已回到交互输入态，则展示为 `waiting`；
- 这层修正不回写 signal 文件，也不改变 Claude 链路。

优点：
- 最小改动即可解决用户可见问题；
- 保持 signal store 职责单一；
- 后续若 Codex 官方提供更好的 lifecycle 事件，可直接移除该 heuristic。

缺点：
- 依赖 Codex TUI 当前文本模式，是启发式而非官方协议；
- 需要谨慎控制轮询频率与判定范围。

### 方案 C：重做 wrapper / PTY 解析
在 wrapper 或伪终端层直接解析 Codex 输出并发新 signal。

- 优点：长期最干净；
- 缺点：侵入性大、风险高，与“最少修改”冲突。

## 最终设计
采用 **方案 B**。

### 1. 保持底层 signal 协议不变
以下链路保持不动：
- `AgentResources/bin/codex`
- `devhaven-agent-emit`
- `WorkspaceAgentSignalStore`

它们继续表达“Codex 进程态”：running / completed / failed。

### 2. 新增展示态修正层
新增一层仅在 App 内存中生效的展示态 override，作用范围严格限定为：

- `agentKind == .codex`
- 底层 signal `state == .running`
- 当前 pane 对应的 `GhosttySurfaceHostModel` 可用且能读取可见文本

展示态 override 的职责：
- 根据可见文本把 `codex + running` 修正为 `running` 或 `waiting`；
- 不影响 `.completed` / `.failed` / `.idle`；
- 不影响 Claude。

### 3. 启发式规则
新增纯字符串规则模块，例如 `CodexAgentDisplayHeuristics.swift`，输出：

- `.running`：可见文本包含 Codex 正在工作中的显著标记；
- `.waiting`：可见文本已回到交互输入态，且没有工作中标记；
- `nil`：无法可靠判断，保持底层 signal 原值。

V1 规则按“保守降级”设计：

优先判定 `running`：
- 包含 `Working (`；
- 或其他非常明确的工作中标记（如 `esc to interrupt` 且处于工作行）。

判定 `waiting`：
- 已出现 Codex 交互输入框/占位文本，例如 `Improve documentation in @filename` 一类输入提示；
- 当前可见文本中不再有 `Working (`。

如果同时无法满足，返回 `nil`，继续显示 signal 的 `running`，避免误降级。

### 4. 轮询与数据流
为避免改动 signal store，本次轮询只存在于 App 层：

1. `WorkspaceShellView` 在界面出现后启动轻量定时刷新；
2. 遍历当前打开 workspace 的 pane，对应 `WorkspaceTerminalSessionStore` 中已存在的 `GhosttySurfaceHostModel`；
3. 仅对 `codex + running` 的 pane 读取可见文本；
4. 计算展示态 override，存入 `NativeAppViewModel` 的运行时内存态；
5. `workspaceSidebarGroups` 等现有 UI 聚合优先消费 override，未命中时退回 signal 原值。

### 5. 文案调整
`WorkspaceAgentStatusAccessory` 对 Codex 的 `.waiting` 改成专用文案：
- `Codex 等待输入`

保留 Claude 的 `.waiting = Claude 等待处理` 语义。

### 6. 重复摘要去重
`WorkspaceProjectListView` / worktree row 在拼接 `label + summary` 前增加去重：
- 若 `summary` 与 `label` 完全相同，则只显示一份 `label`；
- 避免 `Codex 正在运行：Codex 正在运行`。

## 影响范围
预计涉及：
- `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceView.swift`
- `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceHost.swift`
- `macos/Sources/DevHavenApp/WorkspaceShellView.swift`
- `macos/Sources/DevHavenApp/WorkspaceProjectListView.swift`
- `macos/Sources/DevHavenApp/WorkspaceAgentStatusAccessory.swift`
- `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`
- `macos/Sources/DevHavenCore/Models/WorkspaceNotificationModels.swift`（若需要展示态聚合辅助）
- 新增展示态 heuristic 文件
- 对应测试文件
- `AGENTS.md`

## 风险与控制
### 风险 1：文本规则误判
控制：
- 只对 `codex + running` 生效；
- 规则判不准时返回 `nil`，不强行覆盖；
- 先覆盖用户现场明确截图对应模式。

### 风险 2：频繁读取可见文本影响性能
控制：
- 仅轮询打开中的 workspace；
- 仅轮询处于 `codex + running` 的 pane；
- 使用较低频率（如 1s）；
- 只读 viewport，不读完整 scrollback。

### 风险 3：UI override 与 signal store 语义混淆
控制：
- 明确命名为 display / override；
- 不回写 signal 文件；
- 在 AGENTS.md 中补充职责边界。

## 验证策略
1. 纯字符串 heuristic 单元测试：
   - 工作中样本 -> `.running`
   - 回到输入态样本 -> `.waiting`
   - 无法判断样本 -> `nil`
2. ViewModel / sidebar 聚合测试：
   - 底层 signal 为 `codex + running`，override 为 `.waiting` 时，侧边栏显示 waiting；
   - Claude signal 不受影响。
3. UI 文案测试：
   - Codex waiting 标签为“Codex 等待输入”；
   - 重复摘要被去重。
4. 定向 `swift test --package-path macos --filter ...`。

## 长期演进建议
1. 若 Codex 官方未来补齐 waiting / permission 事件，优先改为官方事件驱动，并删除 heuristic；
2. 若未来要支持更多 agent，可把“进程态 -> 展示态”的 override 正式抽象为 display-state adapter；
3. 如果后续需要更高精度，可考虑在不污染主链的前提下增加 transcript / structured event 补充读取。
