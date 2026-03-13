# DevHaven Pane 级 Agent MVP Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让 tab / split pane 先以 pending 形态出现，再在 pane 本体里选择它是 Shell 还是 Claude Code / Codex / iFlow agent，并保持 pane 本体内的停止/切回 shell 能力。

**Architecture:** 复用现有 PTY / terminal pane / split layout，但新增 `pendingTerminal` pane kind 表示“pane 已创建、身份待定”；用户在 `TerminalPendingPane` 内选择 Shell / provider agent 后，再把 pending pane 实化为 terminal shell 或 agent pane。provider 仍通过 adapter registry 适配 Claude Code / Codex / iFlow 三个 provider。

**Tech Stack:** React 19、TypeScript、现有 terminal workspace shell、Tauri terminal commands、Node 内建 `node --test`

---

### Task 1: 重写 agent helper 为 pane 级模型

**Files:**
- Modify: `src/models/agent.ts`
- Modify: `src/models/agent.test.mjs`

**Step 1: Write the failing test**

覆盖：
- shell|agent 的 pane 级状态语义
- Claude Code / Codex / iFlow 三个 provider 的启动命令构建
- 输出 marker 解析 `starting -> running -> stopped/failed`

**Step 2: Run test to verify it fails**

Run:

```bash
node --test src/models/agent.test.mjs
```

Expected:

- FAIL，旧的项目级单 Agent helper 无法通过 pane 级场景

**Step 3: Write minimal implementation**

在 `src/models/agent.ts` 中改为：

- `PaneAgentMode`
- `PaneAgentStatus`
- `PaneAgentRuntimeMap`
- `buildPaneAgentLaunchCommand`
- `consumePaneAgentOutput`
- `start/finish/clearPaneAgentRuntime`

**Step 4: Run test to verify it passes**

Run:

```bash
node --test src/models/agent.test.mjs
```

Expected:

- PASS

### Task 2: 把运行态从“项目单例”改为“pane map”

**Files:**
- Create: `src/hooks/usePaneAgentRuntime.ts`
- Delete: `src/hooks/useProjectAgentRuntime.ts`

**Step 1: Write minimal hook**

实现：

- `sessionId -> runtime`
- `sessionId -> pending command`
- `sessionId -> ptyId`
- `requestStart / connectPty / handleOutput / handleExit / clearRuntime / disposeSession`

**Step 2: Run verification**

Run:

```bash
pnpm exec tsc --noEmit
```

Expected:

- 类型通过

### Task 3: 给 terminal pane descriptor 增加 pending / mode / agent 元数据

**Files:**
- Modify: `src/models/terminal.ts`
- Modify: `src/utils/terminalLayout.ts`
- Modify: `src/terminal-runtime-client/selectors.ts`（仅当类型投影需要）
- Modify: `src/models/terminal.snapshot.test.mjs`

**Step 1: Implement model changes**

在 `TerminalShellPaneDescriptor` 中增加：

- `mode?: "shell" | "agent"`
- `agent?: { provider: "codex" | "claude-code" | "iflow"; model?: string | null } | null`

增加 helper：

- `appendPendingTerminalTabToSnapshot`
- `realizePendingTerminalPaneInSnapshot`
- `splitPendingPaneInSnapshot`
- `setTerminalPaneAgentMode`

并确保新建 tab / split pane 默认先变成 `pendingTerminal`

**Step 2: Run verification**

Run:

```bash
pnpm exec tsc --noEmit
node --test src/models/agent.test.mjs
```

Expected:

- PASS

### Task 4: 新增 adapter registry 与 pane-local provider 选择

**Files:**
- Create: `src/agents/registry.ts`
- Create: `src/agents/shellWrapper.ts`
- Create: `src/agents/adapters/{codex,claudeCode,iflow}.ts`
- Modify: `src/models/agent.ts`
- Modify: `src/models/agent.test.mjs`

**Step 1: Implement adapters**

- 提供三种 provider 的 base command / launch command
- 通用 shell wrapper 负责 started/exit marker
- `iflow` 当前真实命令固定为 `iflow`

**Step 2: Run verification**

Run:

```bash
node --test src/models/agent.test.mjs
pnpm exec tsc --noEmit
```

Expected:

- PASS

### Task 5: 引入 TerminalPendingPane，并把创建入口改为 pending pane

**Files:**
- Modify: `src/components/terminal/TerminalWorkspaceHeader.tsx`
- Modify: `src/components/terminal/TerminalWorkspaceShell.tsx`
- Modify: `src/components/terminal/PaneHost.tsx`
- Create: `src/components/terminal/TerminalPendingPane.tsx`
- Modify: `src/components/terminal/TerminalPane.tsx`
- Modify: `src/components/terminal/TerminalTabs.tsx`

**Step 1: Implement minimal UI**

- 撤掉 header 上的 Agent 按钮与 badge owner 语义
- `TerminalTabs` 的 “+” 只创建 pending tab
- `TerminalPane` 的局部菜单只创建右侧/下方 pending pane
- 由 `PaneHost` 给 terminal pane 透传：
  - pane mode
  - agent provider
  - agent status
  - split create / stop / reset callbacks
  - output callback
- `TerminalPendingPane` 负责在 pane 本体里选择 `Shell / Codex / Claude Code / iFlow`
- `TerminalPane` 只保留局部状态 / 新建 Pane / 停止 / 切回 shell

**Step 2: Run verification**

Run:

```bash
pnpm exec tsc --noEmit
```

Expected:

- 类型通过

### Task 6: 在 TerminalWorkspaceView 接入 pane 级 agent 编排

**Files:**
- Modify: `src/components/terminal/TerminalWorkspaceView.tsx`

**Step 1: Implement minimal runtime orchestration**

实现：

- `resolvePaneMode`
- `resolvePaneAgentProvider`
- `handleResolvePendingPane`
- `handleStartPaneAgent`
- `handleStopPaneAgent`
- `handleResetPaneToShell`
- `handleSelectPaneAgentProvider`
- `handleSessionOutput`
- `handleWorkspacePtyReady` 中对 pending agent command 的处理
- `handleSessionExit` 中的 pane runtime 清理

**Step 2: Run targeted verification**

Run:

```bash
node --test src/models/agent.test.mjs
pnpm exec tsc --noEmit
```

Expected:

- PASS

### Task 7: Build + 文档收尾

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`

**Step 1: Run build**

Run:

```bash
pnpm build
```

Expected:

- 构建通过

**Step 2: Update docs**

- `AGENTS.md` 同步记录 pane 级 agent 模型
- `tasks/todo.md` 记录回滚错误方向与新方案的验证结论
