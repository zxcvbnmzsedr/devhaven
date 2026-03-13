# DevHaven Pane 级 Agent MVP 设计稿

## 目标

把 Agent 语义收回到 **terminal pane 本身**，而不是工作区级独立入口：

- 每个 terminal pane 都可以在 `shell | agent` 两态之间切换
- pane 先创建出来，但初始是 **pending pane**；随后在 pane 自己内部选择 `Shell / Codex / Claude Code / iFlow`
- pane 进入 agent 模式后，继续复用当前 PTY / TerminalPane
- 通过向当前 pane 注入 provider-specific 启动命令，让该 pane 直接承载 Claude Code / Codex / iFlow TUI

## 非目标

本轮不做：

- 独立 Rust `agent_launch / agent_resume`
- durable recovery truth
- task-agent 绑定
- 项目级 agent 历史

## 方案对比

### 方案 A：terminal pane 增加 `mode = shell | agent`（本轮采用）

做法：

1. `TerminalShellPaneDescriptor` 增加 `mode` 与 `agent` 元数据
2. `PaneHost` 把 pane mode / pane-local 回调继续传给 `TerminalPane`
3. `TerminalTabs` 与 `TerminalPane` 只负责创建 **pending pane**
4. `TerminalPendingPane` 自己渲染待定态选择器：
   - Shell
   - Codex
   - Claude Code
   - iFlow
5. `TerminalPane` 自己渲染局部 overlay：
   - agent 状态
   - 停止 Agent
   - 切回 Shell
6. `TerminalWorkspaceView` 在 `onPtyReady` / 输出流 / exit 上做 pane 级 agent 编排

优点：

- 真正符合“每个 pane 都可以是 agent”
- 不把 agent 语义绑死在 workspace header 或 tab 容器
- 最大化复用现有 terminal / PTY / split tree

缺点：

- 需要修改 terminal snapshot 模型
- pane 级 agent 状态比项目级单例更复杂

### 方案 B：新增独立 `kind = agent` 的 pane

优点：

- 类型边界更清楚
- 后续多 provider / resume 更自然

缺点：

- 首版成本更高
- 需要改更多 pane 分发与 projection 逻辑

## 架构决策

### 1. pane 是一等公民，agent 是 pane 的模式

本轮不再引入“官方单一 agent pane”的项目级真相。  
真正的主语改成：

```text
sessionId -> paneId -> mode(shell|agent) -> runtime status
```

### 2. UI 入口收敛到 `TerminalPane`

不再让 `TerminalWorkspaceHeader` 成为 agent 控制中心。  
header 最多保留全局观察语义，不拥有 pane agent 控制语义。

### 3. agent 启动采用“adapter + 命令包裹 + 输出 marker”路线

为了让 agent 在当前 shell pane 内运行，同时又能感知完成/失败：

- 启动时不直接写裸命令
- 而是写入一个带前后 marker 的 shell command
- provider-specific 的 base command 由 adapter 生成
- pane 输出流里只要看到：
  - `[DevHaven Agent Started]`
  - `[DevHaven Agent Exit:<code>]`
- 就能更新 pane 级 agent 状态

### 4. mode 可持久，runtime 状态不作为 durable truth

- pane 的 `mode=agent` 与 provider 元数据可以跟随 snapshot 持久化
- 但 `starting/running/stopped/failed` 仍只作为前端运行时投影
- 重启后不保证自动恢复 agent 执行

## 关键模块

### 模型层

- `src/models/agent.ts`
  - pane agent 状态、provider 列表、输出 marker 解析 helper
- `src/agents/registry.ts`
  - provider adapter 注册表
- `src/agents/adapters/{codex,claudeCode,iflow}.ts`
  - Claude Code / Codex / iFlow 的命令适配
- `src/agents/shellWrapper.ts`
  - 通用 shell marker 包裹器
- `src/models/terminal.ts`
  - terminal pane descriptor 增加 `mode / agent`
  - 增加 `setTerminalPaneAgentMode`

### 编排层

- `src/hooks/usePaneAgentRuntime.ts`
  - 管理 `sessionId -> runtime state`
- `src/components/terminal/TerminalWorkspaceView.tsx`
  - 负责：
    - pane 切到 agent mode
    - `onPtyReady` 注入命令
    - `onOutput` 消费 marker
    - `onExit` 清理运行态

### 视图层

- `src/components/terminal/PaneHost.tsx`
  - 透传 pane mode / pane-local 回调
- `src/components/terminal/TerminalPane.tsx`
  - 显示 pane-local agent overlay

## 数据流

```text
点击 “+” 或 pane 内部“新建 Pane”菜单
  -> 先创建 pending pane
  -> 在该 pane 内点击 Shell / provider agent
  -> snapshot: pane.mode = agent
  -> runtime: sessionId 进入 starting
  -> 若 pty 已存在：立即 writeTerminal(command)
  -> 若 pty 未就绪：等待 onPtyReady
  -> TerminalPane 输出流收到 [DevHaven Agent Started]
  -> runtime: running
  -> provider CLI 退出后输出 [DevHaven Agent Exit:<code>]
  -> runtime: stopped / failed
```

## 错误处理

- 命令注入失败：当前 pane 状态设为 `failed`
- Ctrl+C 停止失败：回退到 kill session
- 切回 Shell：仅在 agent 不处于 running/starting 时允许

## 验证策略

### 单元 / Node 测试

- 命令包装 helper
- output marker 解析
- pane agent runtime 状态迁移

### 手工验证

1. 点击 “+” 新建一个 pending tab
2. 或在当前 pane 右上角菜单里新建右侧/下方 pending pane
3. 在 pending pane 内点击 `Shell / Codex / Claude Code / iFlow`
4. agent pane 启动后自动进入对应 provider
5. 停止后 pane 仍保留，可切回 shell mode
