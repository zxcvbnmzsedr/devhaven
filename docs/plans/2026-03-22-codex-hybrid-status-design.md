# DevHaven Codex 混合状态机设计

## 背景
当前 DevHaven 对 Codex 的主真相源仍是 wrapper 生命周期 signal：

- wrapper 启动前写 `running`
- 进程退出后写 `completed / failed`

这条链路稳定表达了“Codex 进程是否存活”，但它并不等于“当前回合是否仍在执行”。之前为了弥补这一点，App 侧增加了可见文本 heuristic，把 `codex + running` 视图态修正为 `running / waiting`。这一版对“回到输入框仍显示运行中”的问题有帮助，但当 Codex 长时间输出、屏幕内容滚动、或 idle/running 特征混杂时，**纯字符串 heuristic 容易误判**。

用户最新反馈的核心不是文案，而是：**有没有比“看屏幕内容猜状态”更靠谱的主判据。**

## 目标
在不破坏现有 signal store 协议的前提下，把 Codex 的展示态升级为更稳的混合状态机：

1. 继续保留 wrapper 生命周期作为**进程态真相源**；
2. 接入 Codex 官方 `notify` 能力，在“当前回合完成”时写 `waiting` signal；
3. App 仅把可见文本 / 活动度作为**运行时补偿**，不再当主判据；
4. 非交互式 `codex exec`、真实退出、失败等现有链路保持兼容；
5. 不污染用户真实 `~/.codex/config.toml`。

## 非目标
- 不重构 `WorkspaceAgentSignalStore` 协议；
- 不把 heuristic 结果反写回 signal store；
- 不引入 transcript 持久化；
- 不尝试一次性支持 Codex 所有潜在 lifecycle 事件；
- 不修改外部用户 shell 中真实 `codex` 的全局配置。

## 已确认事实
1. Codex CLI 支持通过配置提供 `notify` 程序；官方配置文档说明，Codex 会把事件 JSON 作为参数传给通知程序。
2. 现有 DevHaven wrapper 已经能稳定注入 `DEVHAVEN_AGENT_SIGNAL_DIR`、`DEVHAVEN_AGENT_SESSION_ID` 等上下文，因此最小增量是在 wrapper 里进一步打开 Codex 的 notify。
3. `GhosttySurfaceHostModel.currentVisibleText()` 已能读当前 pane 可见文本，适合做 App 内部只读补偿。
4. `WorkspaceAttentionState` 已具备 pane 级 agent state / summary / updatedAt 记录能力，可继续复用。

## 方案比较

### 方案 A：继续扩展纯文本 heuristic
- 优点：改动最小；
- 缺点：仍然缺少“当前回合完成”的官方信号，长输出/滚动时稳定性天花板低。

### 方案 B：wrapper 注入官方 notify + App 活动度补偿（推荐）
- 优点：
  - turn complete 有官方回调，可把 `waiting` 从“猜测”提升为“事件驱动”；
  - 只需在 wrapper 增加 notify 注入与一支小脚本；
  - App 仍保留 fallback，兼容 notify 漏发或未来版本差异。
- 缺点：
  - 交互会话里“等待输入 -> 新一轮 running”仍缺少官方 start 事件，仍需 App 侧补偿。

### 方案 C：自建 PTY/转录层
- 优点：理论上最强；
- 缺点：侵入性过大，与“最少修改”冲突，也会显著提高维护成本。

## 最终设计
采用 **方案 B：official notify + 进程态 + App 活动度 fallback 的混合状态机**。

### 1. 保留 wrapper 生命周期 signal 主链
仍保留：

- wrapper 启动时写 `running`
- 退出时写 `completed / failed`

这条链路继续表达**进程态**，不变。

### 2. 在 wrapper 内为 DevHaven 会话注入 Codex notify
`AgentResources/bin/codex` 在 DevHaven 环境内启动真实 Codex 前，额外透传：

- `-c notify=["<DevHaven notify 脚本路径>"]`
- `-c tui.notifications=true`

这样无需修改用户真实 `config.toml`，只对 DevHaven 内嵌终端中的这次会话生效。

说明：
- 这里采用 CLI config override，而不是直接改写用户 `CODEX_HOME/config.toml`；
- 原因是 CLI override 更小、更安全，也更符合“不污染用户真实配置”的约束。

### 3. 新增 `devhaven-codex-notify`
新增一个专门消费 Codex notify payload 的脚本：

- 输入：Codex 传来的 JSON payload（argv）
- 行为：
  - 若事件类型为 `agent-turn-complete`，写 `codex + waiting` signal
  - summary 优先取 `last-assistant-message`，其次退回 `msg`
  - 仍复用 `devhaven-agent-emit` 作为唯一 signal 落盘入口
- 未识别的 payload：直接忽略，避免污染现有状态

这样，“当前回合结束、回到输入态”不再依赖屏幕文本猜测，而是有一条官方事件补充链路。

### 4. App 侧展示逻辑升级为“signal 主导 + 活动度补偿”
原本 refresher 只扫描 `codex + running` pane，并试图直接从当前屏幕推导 waiting。

升级后：

- 扫描对象改为 `codex + running` **和** `codex + waiting`
- 对每个 pane 维护只存在于 App 内存中的观测状态：
  - `lastVisibleText`
  - `lastChangedAt`
- 刷新时的规则：

#### 4.1 基础规则
- signal = `waiting`：默认展示 waiting
- signal = `running`：默认展示 running

#### 4.2 从 waiting 提升回 running
当 signal 已被 notify 写成 waiting，但 pane 当前：
- 出现明确 running marker；或
- 最近可见文本发生变化，且不再像 idle/input screen

则临时 override 为 running。

这解决“同一交互会话下一轮开始后，wrapper 不会再重新写 running”的问题。

#### 4.3 从 running 降级为 waiting
只有当以下条件同时满足时，才允许把 `running` 临时修正为 `waiting`：
- 当前文本强烈像 idle/input screen；
- 最近一段时间没有可见文本变化（避免长输出期间误降级）。

这让旧 heuristic 退居为 fallback，而不是主判据。

### 5. heuristic 角色调整
`CodexAgentDisplayHeuristics` 从“主判定器”退为“结构特征识别器”：

- `running` marker：`Working (`、`esc to interrupt`、`Starting MCP servers (`
- `waiting` marker：Codex idle/input screen 结构特征

它不再单独决定最终状态，而是为 refresher 的混合状态机提供输入。

## 数据流
新的链路如下：

1. 用户在 DevHaven 内嵌终端里执行 `codex`
2. DevHaven wrapper 写 `running`
3. wrapper 为真实 Codex 注入 `notify` 配置
4. Codex 当前回合完成时，调用 `devhaven-codex-notify`
5. `devhaven-codex-notify` 通过 `devhaven-agent-emit` 写 `waiting`
6. `WorkspaceAgentSignalStore` 监听 signal 目录，推送给 `NativeAppViewModel`
7. `WorkspaceShellView` 定时读取打开 pane 的可见文本，更新 pane 级 display override
8. Sidebar / worktree 行优先展示 override，未命中时退回 signal

## 影响文件
- `macos/Sources/DevHavenApp/AgentResources/bin/codex`
- `macos/Sources/DevHavenApp/AgentResources/bin/devhaven-codex-notify`（新增）
- `macos/Sources/DevHavenApp/CodexAgentDisplayHeuristics.swift`
- `macos/Sources/DevHavenApp/CodexAgentDisplayStateRefresher.swift`
- `macos/Sources/DevHavenApp/WorkspaceShellView.swift`
- `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`
- `macos/Sources/DevHavenCore/Models/WorkspaceNotificationModels.swift`
- 对应测试文件
- `AGENTS.md`

## 风险与控制

### 风险 1：Codex notify 事件字段在不同版本间有差异
控制：
- `devhaven-codex-notify` 对 payload 做宽松解析；
- 只识别我们当前需要的 `agent-turn-complete`；
- 提取 summary 时做多字段回退。

### 风险 2：waiting -> running 仍没有官方 start 事件
控制：
- App 保留活动度补偿；
- 只有在明确 running marker 或最近文本变化时才临时提升为 running。

### 风险 3：长输出期间被错误降级为 waiting
控制：
- `running -> waiting` 降级必须同时满足：
  - idle/input 特征成立
  - 最近无文本变化

### 风险 4：污染用户 Codex 全局配置
控制：
- 不写用户真实 `config.toml`
- 仅用单次进程级 CLI config override

## 验证策略
1. wrapper / notify 脚本测试
   - wrapper 能注入 notify 配置；
   - notify 脚本收到 `agent-turn-complete` payload 后写 waiting signal；
   - wrapper 退出时 completed/failed 仍生效。
2. 状态机测试
   - waiting signal 默认展示 waiting；
   - waiting + running marker -> override running；
   - running + idle marker + 长时间无变化 -> override waiting；
   - running + idle marker 但近期仍有变化 -> 保持 running。
3. 定向构建 / 测试
   - `swift test --package-path macos --filter ...`
   - `swift build --package-path macos`

## 长期建议
1. 若 Codex 后续补齐“开始一轮 / 等待审批 / 等待用户输入”等官方 lifecycle 事件，应优先切到官方事件，并删除活动度猜测。
2. 如果未来要支持更多 agent，可把当前这套“signal + notify + activity override”抽成统一 display-state adapter。
