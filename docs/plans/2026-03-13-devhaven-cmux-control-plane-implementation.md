# DevHaven cmux Control Plane Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将 DevHaven 的 agent 增强从前端 pane/provider 投影改为 Rust 后端拥有真相的控制平面，并同步建立最小 notification / attention 模型。

**Architecture:** 以 `workspace / pane / surface / terminal_session / agent_session / notification` 为第一阶段控制面主语，在 Rust `terminal_runtime` 邻近模块中新增 registry 与 command/event；前端终端工作区只消费 projection，并回退现有 provider-specific pending pane 主线。agent 退回外部进程运行，terminal 创建时通过 `DEVHAVEN_*` 环境变量暴露归属上下文。

**Tech Stack:** Rust / Tauri v2、现有 `src-tauri/src/terminal_runtime/*`、React 19、TypeScript、Node 内建 `node --test`、Cargo test/check、pnpm build

---

### Task 1: 设计文档与任务清单落盘

**Files:**
- Create: `docs/plans/2026-03-13-devhaven-cmux-control-plane-design.md`
- Create: `docs/plans/2026-03-13-devhaven-cmux-control-plane-implementation.md`
- Modify: `tasks/todo.md`

**Step 1: 写入设计稿与实施计划**

将已确认的控制平面设计和 TDD 实施顺序落盘，保证后续实现不会重新漂回 pane provider MVP。

**Step 2: 更新任务清单**

把本轮实现拆成：
- 控制面 registry / 命令
- terminal 环境注入
- 前端 projection
- 旧 agent 主线回退
- 验证 / 文档同步

**Step 3: 人工校对文件名和路径**

确保后续命令中的路径全部有效。

### Task 2: Rust 控制面模型与 registry

**Files:**
- Create: `src-tauri/src/agent_control.rs`
- Modify: `src-tauri/src/terminal_runtime/mod.rs`
- Modify: `src-tauri/src/lib.rs`
- Modify: `src-tauri/src/command_catalog.rs`
- Test: `src-tauri/src/agent_control.rs`（内联 tests）

**Step 1: Write the failing test**

在 `src-tauri/src/agent_control.rs` 添加失败测试，覆盖：
- 注册 workspace/pane/surface 绑定
- upsert agent session event 后可按 workspace/pane/surface 查询
- notification unread/latest 规则
- orphan 事件降级到 workspace inbox

**Step 2: Run test to verify it fails**

Run:

```bash
cargo test agent_control --manifest-path src-tauri/Cargo.toml
```

Expected:
- FAIL，`agent_control` 模块与 registry 尚不存在

**Step 3: Write minimal implementation**

实现：
- `ControlPlaneRegistry`
- `AgentSessionRecord`
- `NotificationRecord`
- `upsert_agent_session_event`
- `push_notification`
- `identify_for_terminal_session`
- `build_workspace_tree_projection`

**Step 4: Run test to verify it passes**

Run:

```bash
cargo test agent_control --manifest-path src-tauri/Cargo.toml
```

Expected:
- PASS

### Task 3: 暴露 command / event 控制协议

**Files:**
- Modify: `src-tauri/src/lib.rs`
- Modify: `src-tauri/src/command_catalog.rs`
- Modify: `src-tauri/src/web_server.rs`
- Modify: `src-tauri/src/web_event_bus.rs`
- Test: `src-tauri/src/lib.rs` / `src-tauri/src/command_catalog.rs` 现有测试

**Step 1: Write the failing test**

新增失败测试，覆盖：
- `command_catalog` 包含 `devhaven_identify / devhaven_tree / devhaven_notify / devhaven_agent_session_event / devhaven_mark_notification_read / devhaven_mark_notification_unread`
- Web 子集保留这些命令

**Step 2: Run test to verify it fails**

Run:

```bash
cargo test command_catalog --manifest-path src-tauri/Cargo.toml
```

Expected:
- FAIL，命令尚未注册

**Step 3: Write minimal implementation**

添加命令与事件：
- `devhaven-control-plane-changed`
- command payload 使用结构化 JSON，避免 stdout marker 模式回流

**Step 4: Run test to verify it passes**

Run:

```bash
cargo test command_catalog --manifest-path src-tauri/Cargo.toml
```

Expected:
- PASS

### Task 4: terminal session 环境变量注入

**Files:**
- Modify: `src-tauri/src/terminal.rs`
- Modify: `src-tauri/src/agent_control.rs`
- Test: `src-tauri/src/terminal.rs`（或 `agent_control.rs` 内联测试）

**Step 1: Write the failing test**

补失败测试，覆盖 terminal create 请求在已有 `session_id/project_path/pane_id/surface_id` 上下文时，会注入：
- `DEVHAVEN_WORKSPACE_ID`
- `DEVHAVEN_PANE_ID`
- `DEVHAVEN_SURFACE_ID`
- `DEVHAVEN_TERMINAL_SESSION_ID`

**Step 2: Run test to verify it fails**

Run:

```bash
cargo test terminal_create_session --manifest-path src-tauri/Cargo.toml
```

Expected:
- FAIL，环境变量尚未注入或无可测试 helper

**Step 3: Write minimal implementation**

提取可测试 helper，例如：
- `build_devhaven_terminal_env(...)`
- terminal create 时调用该 helper 拼接 env
- 同步把 terminal session 注册到控制面 registry

**Step 4: Run test to verify it passes**

Run:

```bash
cargo test terminal_create_session --manifest-path src-tauri/Cargo.toml
```

Expected:
- PASS

### Task 5: 前端控制面 projection 与服务封装

**Files:**
- Create: `src/models/controlPlane.ts`
- Create: `src/services/controlPlane.ts`
- Create: `src/utils/controlPlaneProjection.ts`
- Create: `src/utils/controlPlaneProjection.test.mjs`
- Modify: `src/platform/commandClient.ts`

**Step 1: Write the failing test**

在 `src/utils/controlPlaneProjection.test.mjs` 补失败用例，覆盖：
- workspace unread 聚合
- pane latest message 选择
- waiting/failed/completed 的 attention 派生

**Step 2: Run test to verify it fails**

Run:

```bash
node --test src/utils/controlPlaneProjection.test.mjs
```

Expected:
- FAIL，projection helper 尚不存在

**Step 3: Write minimal implementation**

新增：
- 控制面 TS 类型
- command 调用封装
- projection helper

**Step 4: Run test to verify it passes**

Run:

```bash
node --test src/utils/controlPlaneProjection.test.mjs
```

Expected:
- PASS

### Task 6: 接入终端工作区 UI projection

**Files:**
- Modify: `src/components/terminal/TerminalWorkspaceWindow.tsx`
- Modify: `src/components/terminal/TerminalWorkspaceView.tsx`
- Modify: `src/components/terminal/TerminalTabs.tsx`
- Modify: `src/components/terminal/terminalWorkspaceShellModel.ts`
- Test: `src/components/terminal/terminalWorkspaceShellModel.test.mjs`

**Step 1: Write the failing test**

补失败测试，覆盖：
- control plane unread/status 能投影到 tab/workspace shell model
- 没有 provider pending pane 时，shell model 不再要求 provider 状态输入

**Step 2: Run test to verify it fails**

Run:

```bash
node --test src/components/terminal/terminalWorkspaceShellModel.test.mjs
```

Expected:
- FAIL，shell model 仍依赖旧 agent 主线输入或不支持新 projection

**Step 3: Write minimal implementation**

让终端工作区消费 control plane 快照：
- 订阅 `devhaven-control-plane-changed`
- 在 tab/workspace 列表展示 unread / latest / status
- 不再依赖 `usePaneAgentRuntime` 作为主信息源

**Step 4: Run test to verify it passes**

Run:

```bash
node --test src/components/terminal/terminalWorkspaceShellModel.test.mjs
```

Expected:
- PASS

### Task 7: 回退旧 pane-agent 主线为纯 terminal primitive

**Files:**
- Modify: `src/components/terminal/TerminalPendingPane.tsx`
- Modify: `src/components/terminal/PaneHost.tsx`
- Modify: `src/components/terminal/TerminalPane.tsx`
- Modify: `src/components/terminal/TerminalWorkspaceView.tsx`
- Modify/Delete: `src/hooks/usePaneAgentRuntime.ts`
- Modify/Delete: `src/models/agent.ts`
- Modify/Delete: `src/agents/registry.ts`
- Modify/Delete: `src/agents/adapters/*`
- Test: `src/models/terminal.snapshot.test.mjs`

**Step 1: Write the failing test**

补失败测试，覆盖：
- 新建 pane/tab 默认只产生 terminal primitive，不再提供 provider 选择
- 默认/fallback pane 仍然可用
- 不再要求 stdout marker 驱动 agent 状态机

**Step 2: Run test to verify it fails**

Run:

```bash
node --test src/models/terminal.snapshot.test.mjs src/components/terminal/terminalWorkspaceShellModel.test.mjs
```

Expected:
- FAIL，旧的 provider pending pane 逻辑仍存在

**Step 3: Write minimal implementation**

- `TerminalPendingPane` 回退为纯“新建终端”占位或直接移除
- `TerminalWorkspaceView` 删除 `createPaneAgentCommand/requestPaneAgentStart/connectPaneAgentPty/handlePaneAgentOutput` 主路径
- 清理未再使用的 provider adapter / marker helper

**Step 4: Run test to verify it passes**

Run:

```bash
node --test src/models/terminal.snapshot.test.mjs src/components/terminal/terminalWorkspaceShellModel.test.mjs
```

Expected:
- PASS

### Task 8: 文档、索引与总体验证

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`
- Modify: `tasks/lessons.md`（如需记录新经验）

**Step 1: Update docs**

同步更新：
- AGENTS 中的 agent/terminal/control-plane 描述
- todo Review
- lessons（记录“provider 不应再作为 pane mode 真相”）

**Step 2: Run targeted verification**

Run:

```bash
node --test src/utils/controlPlaneProjection.test.mjs src/models/terminal.snapshot.test.mjs src/components/terminal/terminalWorkspaceShellModel.test.mjs
cargo test agent_control --manifest-path src-tauri/Cargo.toml
cargo test command_catalog --manifest-path src-tauri/Cargo.toml
cargo test terminal_ --manifest-path src-tauri/Cargo.toml
cargo check --manifest-path src-tauri/Cargo.toml
pnpm exec tsc --noEmit
pnpm build
```

Expected:
- 全部 PASS / exit 0

**Step 3: 追加 Review 记录**

把：
- 直接原因
- 设计层诱因
- 当前修复方案
- 长期改进建议
- 验证证据

写回 `tasks/todo.md`
