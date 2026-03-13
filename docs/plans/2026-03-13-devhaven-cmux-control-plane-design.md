# DevHaven cmux 化控制平面设计稿

## 目标

将 DevHaven 从“前端 pane 级 provider agent MVP”收敛为 **terminal/browser primitive + topology/control/notification** 的控制平面架构：

- 应用不再内建 `Codex / Claude Code / iFlow` pane 模式
- agent 完全退回外部进程 / wrapper / hook 自行运行
- Rust 后端成为 `workspace / pane / surface / terminal session / agent session / notification` 的统一真相源
- React 前端只负责 projection 与交互，不再通过 stdout marker 推导 agent 运行态
- 第一阶段先完成 **控制平面 + 通知/attention 同步建模**，browser 深增强与 shell telemetry 后续追加

## 非目标

本轮不做：

- 完整复刻 cmux 的短句柄（`pane:1 / surface:2`）
- 全量 browser automation parity
- tmux compat / claude teams 兼容层
- 终端活进程 durable 恢复
- quick command / codex monitor 全面重写

## 现状问题

### 直接原因

当前 DevHaven 的 agent 增强以 `pending pane -> provider 选择 -> 前端 adapter 组装命令 -> 注入 PTY -> stdout marker 推导状态` 为主线，能跑 MVP，但控制平面仍依赖前端运行时投影。

### 设计层诱因

存在明显的真相源分裂：

- layout snapshot 维护 pane / tab / split 真相
- `usePaneAgentRuntime` 维护 `sessionId -> runtime` 前端状态机
- `src/services/terminal.ts` 维护前端 PTY registry
- Rust `terminal_runtime` 维护 session registry
- provider 语义又嵌在 pending pane / adapter / marker 中

结果是 `pane / session / PTY / agent runtime / notification` 没有统一后端主语，导致恢复、通知、归属、attention 都容易继续分叉。

## 架构决策

### 1. 控制平面的主语

第一阶段统一采用以下对象模型：

```text
Window
  -> Workspace
      -> Pane
          -> Surface
              -> TerminalSession?
              -> AgentSession[]?
      -> Notification[]
```

关键约束：

- `Pane` 是位置，不承载 provider 语义
- `Surface` 是内容，第一阶段先支持 `terminal / browser`
- `TerminalSession` 是 transport/runtime 细节，不是产品主语
- `AgentSession` 是外部 agent 会话的归属记录，不是 pane mode
- `Notification` 是 registry 中的结构化事件，而不是前端局部状态

### 2. Rust 后端是真相源

Rust 后端新增控制平面 registry，统一持有：

- workspace / pane / surface 的控制平面投影
- terminal session 绑定
- agent session 记录
- notification / unread / latest attention 记录

React 前端不再拥有 agent runtime 真相，只负责：

- 调用 command
- 订阅事件
- 渲染 projection

### 3. provider 退回外部进程

取消 DevHaven 内建 provider pane 模式：

- 不再从应用内部选择 `Codex / Claude Code / iFlow`
- 不再由前端 adapter 生成启动命令并写入 PTY
- 不再通过 stdout marker 判断 `starting/running/stopped/failed`

取而代之的是：

- terminal session 启动时自动注入 `DEVHAVEN_*` 上下文环境变量
- 外部 wrapper / hook 读取这些环境变量
- 外部进程通过 command / HTTP / WS 上报：
  - notify
  - session event
  - status / progress / log

### 4. surface 概念先保留，即使 v1 内部仍近似 1:1

对外协议保留：

- `workspace_id`
- `pane_id`
- `surface_id`
- `terminal_session_id`
- `agent_session_id`
- `notification_id`

第一阶段全部使用 UUID；短 ref 作为第二阶段增强。

## 第一阶段控制协议

### 查询类

- `devhaven.identify`
  - 返回当前上下文的 window/workspace/pane/surface/terminal session/agent session 归属
- `devhaven.tree`
  - 返回当前终端工作区拓扑与 attention 摘要

### 写入类

- `devhaven.notify`
  - 上报一条结构化通知
- `devhaven.agent_session_event`
  - 上报外部 agent 会话事件：`started / running / waiting / completed / failed / stopped`
- `devhaven.mark_notification_read`
- `devhaven.mark_notification_unread`
- `devhaven.trigger_attention`（第一阶段可先做最小事件模型）

## 数据流

```text
Terminal session 创建
  -> Rust 注入 DEVHAVEN_* 环境变量
  -> 用户在终端里运行外部 agent / wrapper
  -> agent wrapper / hook 上报 notify / agent_session_event
  -> Rust registry 更新 agent session / notification / attention
  -> WebSocket / Tauri event 推送前端
  -> 前端更新 workspace / pane / project 的 unread / last message / status 投影
```

## 兼容策略

### 保留但降级为数据源

以下能力本轮不重写，只先避免继续作为 agent 主线：

- quick command runtime
- codex monitor
- run panel
- file preview / git diff / overlay pane

它们后续可以作为 notification/status 的数据源接入控制平面，但不再主导 agent 架构。

### 找不到目标归属时的降级

若外部 agent 上报事件时，原 pane/surface 已关闭：

1. 优先挂到原 workspace
2. 若 workspace 也不存在，则挂到 project/worktree 级 inbox
3. 记录 orphan 标记，避免事件直接丢失

## 前端收敛策略

前端第一阶段只保留 primitive：

- terminal pane
- browser pane（协议层预留）
- 现有 preview/git diff 等内部 pane 不暴露为 agent primitive

前端需要移除 / 回退：

- `pendingTerminal` 中的 provider 选择
- `usePaneAgentRuntime` 作为主线运行态
- `src/agents/*` 在主路径中的调度职责
- stdout marker 驱动的 pane agent 状态机

## 验证策略

### Rust

优先补：

- registry 单测
- identify/tree 输出测试
- notification unread/latest/attention 规则测试
- terminal env 注入测试
- orphan event 降级测试

### 前端

优先补：

- 控制平面 projection helper 测试
- unread badge / last message 渲染策略测试
- 去除 provider pending pane 后的默认布局/入口测试

## 长期演进

第二阶段再考虑：

- Claude 深适配 wrapper / hooks
- Codex / 其他 provider 的 provider-neutral 事件入口
- shell telemetry（cwd/git/ports/tty）
- browser control protocol 扩展
- 短 ref（`pane:1` / `surface:2`）
