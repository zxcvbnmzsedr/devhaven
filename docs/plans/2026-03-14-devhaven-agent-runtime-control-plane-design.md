# DevHaven Agent Runtime / Durable Control Plane 设计稿

## 目标

将 DevHaven 的 Agent 能力收口到一条**唯一正确主线**：

1. **DevHaven 拥有 Agent 启动权**，不再依赖 `~/.codex/sessions` 文件扫描推断状态。
2. **Control Plane 成为唯一真相源**，并具备持久化与启动恢复能力。
3. **所有 UI 只消费 Control Plane Projection**，不再保留 monitor / hook / 前端局部状态三套并行来源。
4. **Codex / Claude / 其他 provider 统一走结构化 Agent Runtime 协议**，而不是各自直写散乱通知。
5. **Codex 与 Claude 在 DevHaven 内都要支持交互式透明 wrapper**，用户在终端里直接输入 `codex` / `claude` 即进入受管运行时。

## 背景与问题

2026-03-14 删除 `codex_monitor` 后，系统暴露出两个核心问题：

- 用户看不到通知，不知道 Agent 是否在运行。
- 应用重启后没有恢复能力，Control Plane 仅是内存态 registry。

直接原因不是某个 toast 组件失效，而是**旧 monitor 被删除后，新 runtime 主链还没有真正产品化接管**：

- `scripts/devhaven-codex-hook.mjs` 等脚本存在，但 DevHaven 没有拥有 Codex 启动权。
- `src-tauri/src/agent_control.rs` 只持有内存 `HashMap`，没有 durable store。
- Sidebar 的会话入口被一起删除，用户失去全局可见性。

如果此时回退到 monitor 或保留双轨状态源，只会继续制造新的屎山。最终正确道路只能是：

> **DevHaven 自己拥有 Agent 运行时，Control Plane 持久化保存状态，UI 只读 Control Plane。**

## 产品边界（必须明确）

### DevHaven 承诺支持的会话

DevHaven 只承认两类 Agent 会话：

1. **由 DevHaven 启动的会话**
   - 用户通过 DevHaven 提供的 Agent 入口启动。
   - 或在 DevHaven 内置 terminal 中，通过 DevHaven 注入的 wrapper 启动。
2. **通过显式 attach/register 协议接入的会话**
   - 外部进程主动调用 DevHaven 的 attach / session-event / notify 协议完成注册。

### DevHaven 不再承诺支持的会话

- 系统中任意裸跑的 `codex` 进程。
- 仅存在于 `~/.codex/sessions`、但没有被 DevHaven 启动或 attach 的会话。

这条边界是最终方案成立的必要条件。否则系统会再次退回“文件扫描 + 轮询 + 猜状态”的错误架构。

## 非目标

本轮不做以下事情：

- 不恢复 `codex_monitor.rs` 或任何 `~/.codex/sessions` watcher。
- 不再引入“轻量 monitor 兜底”。
- 不试图无侵入发现系统里所有外部 Agent。
- 不实现 provider-specific 的复杂 UI 面板；先把 runtime / durable control plane 建好。

## 架构总览

### 交互式主路径（收口后的单线模型）

交互式 `codex` / `claude` 的正式主路径收口为：

```text
terminal
  -> shell integration
  -> scripts/bin shim
  -> provider wrapper
  -> hook / notify
  -> control plane
  -> UI
```

这条路径是 DevHaven 需要对齐 cmux 的核心心智：用户只是在终端里输入 `codex` / `claude`，其余接管逻辑都在 shell integration / shim / wrapper 层自动完成。

### 1. Launch Ownership（启动权）

新增 Rust 后端 Agent Runtime Launcher，负责：

- 分配 `agentSessionId`
- 绑定 `projectPath / workspaceId / paneId / surfaceId / terminalSessionId`
- 拉起真实 provider 进程（Codex / Claude 均需支持交互式透明 wrapper）
- 监听子进程退出与心跳
- 将结构化状态写入 durable control plane

启动权必须收回到 DevHaven 后端，而不是“前端只是给 shell 注入几个环境变量，期待外部脚本自己上报”。

### 2. Durable Control Plane（持久化控制面）

补充边界：`agent_spawn / agent_stop / agent_runtime_diagnose` 保留为**显式命令面 / 调试工具面**，不再作为交互式 Claude/Codex 的主心智模型。

Control Plane 分成两层：

- **内存层**：运行时快速读写、事件分发。
- **持久化层**：存储会话摘要、通知、binding、恢复元数据。

建议新增独立持久化文件：

- `~/.devhaven/agent_control_plane.json`

持久化内容只保存**状态摘要**，不保存终端完整输出。

### 3. Structured Agent Runtime Protocol（结构化协议）

统一 Agent Runtime 事件：

- `started`
- `running`
- `waiting`
- `completed`
- `failed`
- `stopped`
- `heartbeat`

统一通知意图：

- `info`
- `attention`
- `error`

Wrapper / hook 的职责仅是上报结构化事实，不直接控制 UI。UI 只订阅 Control Plane。

### 4. Single Projection UI（单一投影 UI）

以下 UI 统一只读 Control Plane：

- Sidebar Agent 状态卡
- 项目列表 / 终端工作区中的 provider 运行数
- TerminalWorkspaceHeader 最新消息 / unread / attention
- toast / 系统通知

## 模块设计

### Rust 后端

#### A. `src-tauri/src/agent_launcher.rs`（新增）

职责：

- 启动 / 停止 / attach Agent 进程
- 持有运行时句柄（子进程、pid、最近心跳时间）
- 将状态同步到 `AgentControlState`
- 启动恢复后执行 reconcile

为什么单独拆模块：

- 避免 `agent_control.rs` 同时承担“真相层 + 进程管理 + 持久化 +命令入口”而继续膨胀。

#### B. `src-tauri/src/agent_control.rs`

职责调整为：

- 持有 Control Plane 内存 registry
- 提供 projection/tree 查询
- 处理通知生命周期
- 发 `devhaven-control-plane-changed`
- 对接持久化层加载/保存

不再承担：

- 直接启动 provider 进程
- 作为唯一 attach / spawn 逻辑入口

#### C. `src-tauri/src/storage.rs`

新增 Agent Control Plane Store：

- `load_agent_control_plane_store`
- `save_agent_control_plane_store`
- `flush_agent_control_plane_store`
- `load_agent_control_plane_summary`

写盘策略与 terminal layout 保持一致：

- 内存态 dirty revision
- debounce flush
- 原子写入

#### D. `src-tauri/src/terminal.rs`

保留 terminal binding 注入，但职责收口为：

- 创建 terminal session 时写入 `DEVHAVEN_*` 环境变量
- 支持“从 terminal 派生 agent 启动上下文”
- 不直接作为 Agent 真相层

### 前端

#### A. `src/services/controlPlane.ts`

扩展为 Agent 主服务层：

- `agentSpawn`
- `agentStop`
- `agentAttach`
- `listAgentSessions`
- `loadAgentWorkspaceSummary`

现有 `devhaven_notify` / `devhaven_agent_session_event` 继续保留，但退居为外部 adapter 接入协议。

#### B. `src/models/controlPlane.ts`

补齐 durable session / summary 模型：

- `ControlPlaneAgentSession`
- `ControlPlaneWorkspaceSummary`
- `ControlPlaneGlobalSummary`
- `ControlPlaneRuntimeSource`
- `ControlPlaneSessionHealth`

#### C. `src/utils/controlPlaneProjection.ts`

统一产生三种 projection：

- 全局 summary（Sidebar）
- workspace summary（项目级）
- surface / pane summary（终端 header）

#### D. `src/hooks/useCodexIntegration.ts`

收口为唯一通知消费层：

- 只监听 control plane changed
- 根据 notification record 统一弹 toast / 系统通知
- 不再承担会话发现、project 匹配、monitor bridge 等逻辑

#### E. `src/components/Sidebar.tsx`

恢复一个**轻量 Agent 状态卡**，但不再回到旧 monitor 列表：

展示：

- 运行中会话数
- attention / error 数
- 最新一条消息
- 打开 Agent 面板 / 打开终端工作区入口
- 一键运行诊断入口

#### F. `src/components/terminal/TerminalWorkspaceHeader.tsx`

继续展示 workspace 级 running count / attention / latest message，但数据来源严格统一到 projection helper。

## 数据模型

建议持久化文件结构：

```json
{
  "version": 1,
  "sessions": {
    "agent-1": {
      "agentSessionId": "agent-1",
      "provider": "codex",
      "status": "running",
      "projectPath": "/repo",
      "workspaceId": "project-1",
      "paneId": "pane-a",
      "surfaceId": "surface-a",
      "terminalSessionId": "term-1",
      "cwd": "/repo",
      "launchSource": "devhaven-spawn",
      "runtimeStatus": "alive",
      "createdAt": 0,
      "updatedAt": 0,
      "lastHeartbeatAt": 0,
      "message": "正在执行"
    }
  },
  "notifications": {
    "notif-1": {
      "id": "notif-1",
      "agentSessionId": "agent-1",
      "projectPath": "/repo",
      "workspaceId": "project-1",
      "level": "attention",
      "message": "Codex 需要你的处理",
      "read": false,
      "createdAt": 0,
      "updatedAt": 0
    }
  },
  "bindings": {
    "term-1": {
      "terminalSessionId": "term-1",
      "projectPath": "/repo",
      "workspaceId": "project-1",
      "paneId": "pane-a",
      "surfaceId": "surface-a",
      "cwd": "/repo",
      "updatedAt": 0,
      "exited": false
    }
  }
}
```

## 启动 / 停止 / 恢复流程

### 启动流程

1. 前端调用 `agentSpawn`，传入 provider + 归属上下文。
2. Rust `agent_launcher` 创建 `agentSessionId` 与 runtime handle。
3. 将 session/binding 写入内存 control plane，并持久化。
4. 子进程启动后上报 `started -> running`。
5. Control Plane 发事件；UI 刷新 running 状态。

### 停止流程

1. 前端调用 `agentStop(agentSessionId)`。
2. `agent_launcher` 终止子进程。
3. Control Plane 将状态更新为 `stopped`。
4. 持久化并向前端广播。

### 启动恢复流程

1. App 启动时加载 `agent_control_plane.json`。
2. 恢复最近 session / notification / bindings 到内存 registry。
3. 对 `launchSource = devhaven-spawn` 且状态仍为 running/waiting 的 session 执行 reconcile：
   - 进程仍在：保留 running/waiting
   - 进程消失：转为 stopped
   - 心跳超时：转为 stopped 或 stale
4. 广播恢复结果。

## 诊断能力

最终正确道路不能没有诊断入口。建议新增一个轻量诊断命令：

- `agent_runtime_diagnose`

返回：

- wrapper 是否可用
- control plane store 是否加载成功
- 最近一次 session event / notification 时间
- 当前 running session 数
- 持久化文件 revision / flushedAt

前端 Sidebar 状态卡可直接展示“诊断正常 / 诊断异常”。

## 风险与防线

### 风险 1：仍有用户习惯在 DevHaven 外部裸跑 Codex

处理：

- 文档中明确边界
- 提供 attach/register 协议
- 不再提供 monitor 式无侵入发现

### 风险 2：持久化与运行时状态不一致

处理：

- 启动恢复时统一走 reconcile
- 所有 running 状态都要带 `lastHeartbeatAt`
- session / notification / binding 写盘统一做 revision 管理

### 风险 3：Rust 模块继续膨胀

处理：

- launcher / control / storage 分模块
- 禁止把 provider-specific 启动细节重新塞回 `agent_control.rs`

## 验收标准

1. 在 DevHaven 内启动 Codex 后，主界面与终端工作区都能看到运行态。
2. Codex 完成 / 失败 / attention 时，toast 和系统通知都由 Control Plane 统一触发。
3. 应用重启后，最近会话摘要和通知摘要可以恢复。
4. 仓库内不再依赖 `~/.codex/sessions`、`codex_monitor.rs` 或任何文件扫描兜底。
5. UI 中不存在第二套 Agent 状态源。

## 影响文件（预估）

- Rust
  - `src-tauri/src/lib.rs`
  - `src-tauri/src/command_catalog.rs`
  - `src-tauri/src/agent_control.rs`
  - `src-tauri/src/terminal.rs`
  - `src-tauri/src/storage.rs`
  - `src-tauri/src/agent_launcher.rs`（新增）
- 前端
  - `src/models/controlPlane.ts`
  - `src/services/controlPlane.ts`
  - `src/utils/controlPlaneProjection.ts`
  - `src/hooks/useCodexIntegration.ts`
  - `src/components/Sidebar.tsx`
  - `src/components/terminal/TerminalWorkspaceHeader.tsx`
  - `src/components/terminal/TerminalWorkspaceWindow.tsx`
- 文档
  - `AGENTS.md`
  - `tasks/todo.md`
  - `tasks/lessons.md`

## 结论

最终正确道路不是“修回通知”，而是：

> **把 Agent 从“被动猜测的外部工具”升级为 DevHaven 自己拥有启动权、持久化真相和统一 UI 投影的一等运行时。**

这条路完成后，Agent 增强、通知、恢复、可见性都会自然闭环，不再需要任何 monitor 式兜底。
