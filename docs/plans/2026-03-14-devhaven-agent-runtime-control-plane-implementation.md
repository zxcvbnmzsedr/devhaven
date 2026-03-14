# DevHaven Agent Runtime / Durable Control Plane Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将 DevHaven 的 Agent 能力重构为“后端拥有启动权 + 持久化控制面 + 单一 UI 投影”的正式运行时，不再依赖任何 `~/.codex/sessions` monitor 或文件扫描兜底。

**Architecture:** 新增 Rust `agent_launcher` 负责启动/停止/恢复 Agent 进程，`agent_control` 负责内存 registry 与 projection，`storage` 负责 durable control plane store；前端统一通过 `controlPlane` service 和 projection helper 读取状态，Sidebar 恢复轻量 Agent 状态卡，`useCodexIntegration` 收口为唯一通知消费层。

**Tech Stack:** Tauri v2、Rust、React、TypeScript、Node 内建 test、cargo test、TypeScript typecheck

---

### Task 1: 搭建 Durable Control Plane Store

**Files:**
- Modify: `src-tauri/src/storage.rs`
- Modify: `src-tauri/src/agent_control.rs`
- Modify: `src-tauri/src/lib.rs`
- Test: `src-tauri/src/agent_control.rs`
- Test: `src-tauri/src/storage.rs`

**Step 1: 写失败测试**

在 Rust 测试中补两类断言：

1. `agent_control` 新增测试：registry 导出快照后再次载入，session / notification / binding 能保持一致。
2. `storage` 新增测试：`agent_control_plane.json` 能被原子写入与再次读取。

**Step 2: 运行测试确认失败**

Run:
- `cargo test agent_control --manifest-path src-tauri/Cargo.toml`
- `cargo test storage --manifest-path src-tauri/Cargo.toml`

Expected: FAIL，因为当前没有 agent control plane store 的读写逻辑。

**Step 3: 写最小实现**

- 在 `storage.rs` 新增 `AgentControlPlaneFile` 的读写、debounce flush、原子写入。
- 在 `agent_control.rs` 新增导出 / 导入内存 registry 的 helper。
- 在 `lib.rs` setup 阶段加载 durable control plane，启动时导入内存 registry。

**Step 4: 重新运行测试确认通过**

Run:
- `cargo test agent_control --manifest-path src-tauri/Cargo.toml`
- `cargo test storage --manifest-path src-tauri/Cargo.toml`

Expected: PASS

**Step 5: Commit**

```bash
git add src-tauri/src/storage.rs src-tauri/src/agent_control.rs src-tauri/src/lib.rs
git commit -m "feat: persist agent control plane store"
```

---

### Task 2: 新增 Agent Launcher 与正式命令入口

**Files:**
- Create: `src-tauri/src/agent_launcher.rs`
- Modify: `src-tauri/src/lib.rs`
- Modify: `src-tauri/src/command_catalog.rs`
- Modify: `src-tauri/src/agent_control.rs`
- Test: `src-tauri/src/command_catalog.rs`
- Test: `src-tauri/src/agent_launcher.rs`

**Step 1: 写失败测试**

补充测试覆盖：

1. `command_catalog` 包含新命令：`agent_spawn`、`agent_stop`、`agent_runtime_diagnose`。
2. `agent_launcher` 能在不真正拉起 provider 的假实现里创建 session 并更新 control plane。

**Step 2: 运行测试确认失败**

Run:
- `cargo test command_catalog --manifest-path src-tauri/Cargo.toml`
- `cargo test agent_launcher --manifest-path src-tauri/Cargo.toml`

Expected: FAIL，因为当前没有 `agent_launcher` 模块与命令入口。

**Step 3: 写最小实现**

- 新建 `agent_launcher.rs`，封装 spawn / stop / reconcile / diagnose。
- 在 `lib.rs` 注册新命令。
- 在 `command_catalog.rs` 暴露 Tauri/Web 入口。
- `agent_control.rs` 增加与 launcher 对接的最小写接口。

**Step 4: 重新运行测试确认通过**

Run:
- `cargo test command_catalog --manifest-path src-tauri/Cargo.toml`
- `cargo test agent_launcher --manifest-path src-tauri/Cargo.toml`

Expected: PASS

**Step 5: Commit**

```bash
git add src-tauri/src/agent_launcher.rs src-tauri/src/lib.rs src-tauri/src/command_catalog.rs src-tauri/src/agent_control.rs
git commit -m "feat: add agent launcher runtime commands"
```

---

### Task 3: 将交互式 Claude / Codex 收口为单线主路径（shell integration -> shim -> wrapper -> hook -> control plane）

**Files:**
- Create: `scripts/devhaven-codex-wrapper.mjs`
- Create: `scripts/devhaven-claude-wrapper.mjs`
- Modify: `src-tauri/src/terminal.rs`
- Modify: `src/services/terminal.ts`
- Modify: `src/services/controlPlane.ts`
- Modify: `src/models/controlPlane.ts`
- Test: `scripts/devhaven-control.test.mjs`
- Test: `src-tauri/src/terminal.rs`

**Step 1: 写失败测试**

补充测试覆盖：

1. `terminal.rs` 创建 session 时会为 DevHaven 内部 Agent 启动链路注入必要环境变量。
2. wrapper 脚本能把 session-event / notify 发到 control plane endpoint。

**Step 2: 运行测试确认失败**

Run:
- `node --test scripts/devhaven-control.test.mjs`
- `cargo test terminal_ --manifest-path src-tauri/Cargo.toml`

Expected: FAIL，因为当前没有正式的 Codex wrapper 主路径。

**Step 3: 写最小实现**

- 新增 `scripts/devhaven-codex-wrapper.mjs` 与 `scripts/devhaven-claude-wrapper.mjs`，负责调用真实 `codex` / `claude` 并上报结构化事件。
- 在 `terminal.rs` 中补充 DevHaven 内部启动上下文注入，并为 shell integration / wrapper shim 提供默认命令接管入口。
- 前端不再把 `agentSpawn` / `agentStop` / `agentRuntimeDiagnose` 暴露成交互式主路径接口；这些能力保留在后端显式命令面，用于诊断与后续非交互托管能力。
- 扩展 `controlPlane.ts` 与模型以表达 launch-source / runtime-status。

**Step 4: 重新运行测试确认通过**

Run:
- `node --test scripts/devhaven-control.test.mjs`
- `cargo test terminal_ --manifest-path src-tauri/Cargo.toml`

Expected: PASS

**Step 5: Commit**

```bash
git add scripts/devhaven-codex-wrapper.mjs src-tauri/src/terminal.rs src/services/terminal.ts src/services/controlPlane.ts src/models/controlPlane.ts
git commit -m "feat: own codex launch path inside devhaven"
```

---

### Task 4: 实现启动恢复与 Runtime Reconcile

**Files:**
- Modify: `src-tauri/src/agent_launcher.rs`
- Modify: `src-tauri/src/agent_control.rs`
- Modify: `src-tauri/src/lib.rs`
- Test: `src-tauri/src/agent_launcher.rs`
- Test: `src-tauri/src/agent_control.rs`

**Step 1: 写失败测试**

补充测试覆盖：

1. 启动时能从 durable store 恢复 session summary。
2. 标记为 running 的 session 在 reconcile 时，若 runtime 已不存在，会转成 stopped。
3. 最近 notification / unread 状态在恢复后仍可投影。

**Step 2: 运行测试确认失败**

Run:
- `cargo test agent_launcher --manifest-path src-tauri/Cargo.toml`
- `cargo test agent_control --manifest-path src-tauri/Cargo.toml`

Expected: FAIL，因为当前无 reconcile / startup recovery。

**Step 3: 写最小实现**

- `agent_launcher` 增加 reconcile helper。
- `lib.rs` 在应用启动时调用恢复与 reconcile。
- `agent_control.rs` 增加 session health / heartbeat 字段的最小支持。

**Step 4: 重新运行测试确认通过**

Run:
- `cargo test agent_launcher --manifest-path src-tauri/Cargo.toml`
- `cargo test agent_control --manifest-path src-tauri/Cargo.toml`

Expected: PASS

**Step 5: Commit**

```bash
git add src-tauri/src/agent_launcher.rs src-tauri/src/agent_control.rs src-tauri/src/lib.rs
git commit -m "feat: restore and reconcile agent runtime on startup"
```

---

### Task 5: 前端统一 Projection 与 Sidebar Agent 状态卡

**Files:**
- Modify: `src/models/controlPlane.ts`
- Modify: `src/utils/controlPlaneProjection.ts`
- Modify: `src/hooks/useCodexIntegration.ts`
- Modify: `src/components/Sidebar.tsx`
- Modify: `src/App.tsx`
- Modify: `src/components/terminal/TerminalWorkspaceWindow.tsx`
- Modify: `src/components/terminal/TerminalWorkspaceHeader.tsx`
- Test: `src/utils/controlPlaneProjection.test.mjs`
- Test: `src/utils/controlPlaneAutoRead.test.mjs`

**Step 1: 写失败测试**

补充测试覆盖：

1. 生成 Sidebar 全局 summary：running / attention / error / latest message。
2. `useCodexIntegration` 只从 control plane notification 触发 toast / 系统通知。
3. Header / Window / Sidebar 三处对同一份 summary projection 一致。

**Step 2: 运行测试确认失败**

Run:
- `node --test src/utils/controlPlaneProjection.test.mjs src/utils/controlPlaneAutoRead.test.mjs`

Expected: FAIL，因为当前没有全局 Agent 状态卡和统一 summary projection。

**Step 3: 写最小实现**

- `controlPlaneProjection.ts` 新增 global/workspace/surface summary helper。
- `Sidebar.tsx` 恢复轻量 Agent 状态卡。
- `useCodexIntegration.ts` 收口为唯一通知消费层。
- `TerminalWorkspaceWindow` / `Header` 统一只读 projection helper。

**Step 4: 重新运行测试确认通过**

Run:
- `node --test src/utils/controlPlaneProjection.test.mjs src/utils/controlPlaneAutoRead.test.mjs`
- `pnpm exec tsc --noEmit`

Expected: PASS

**Step 5: Commit**

```bash
git add src/models/controlPlane.ts src/utils/controlPlaneProjection.ts src/hooks/useCodexIntegration.ts src/components/Sidebar.tsx src/App.tsx src/components/terminal/TerminalWorkspaceWindow.tsx src/components/terminal/TerminalWorkspaceHeader.tsx
git commit -m "feat: unify agent status projection across ui"
```

---

### Task 6: 清理残留假设与文档同步

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`
- Modify: `tasks/lessons.md`
- Optional cleanup: `src/models/agentSessions.ts`
- Optional cleanup: `src/services/agentSessions.ts`

**Step 1: 清查残留接口**

- 确认 `src/models/agentSessions.ts` / `src/services/agentSessions.ts` 是否仍有价值；若未接线则删除。
- 搜索仓库中所有“monitor / sessions 文件扫描 / 外部裸 codex 自动发现”描述并清理。

**Step 2: 更新文档**

- `AGENTS.md` 改写 Agent 部分：明确 DevHaven 只承认 DevHaven-spawn / attach 会话。
- `tasks/todo.md` 追加 Review，写清直接原因、设计层诱因、当前修复方案、长期建议。
- `tasks/lessons.md` 记录迁移顺序与产品边界教训。

**Step 3: 全量验证**

Run:
- `node --test src/utils/controlPlaneProjection.test.mjs src/utils/controlPlaneAutoRead.test.mjs scripts/devhaven-control.test.mjs`
- `pnpm exec tsc --noEmit`
- `pnpm build`
- `cargo test agent_control --manifest-path src-tauri/Cargo.toml`
- `cargo test agent_launcher --manifest-path src-tauri/Cargo.toml`
- `cargo test command_catalog --manifest-path src-tauri/Cargo.toml`
- `cargo test terminal_ --manifest-path src-tauri/Cargo.toml`
- `cargo check --manifest-path src-tauri/Cargo.toml`

Expected: 全部通过

**Step 4: Commit**

```bash
git add AGENTS.md tasks/todo.md tasks/lessons.md src/models/agentSessions.ts src/services/agentSessions.ts
git commit -m "docs: finalize durable agent runtime control plane migration"
```
