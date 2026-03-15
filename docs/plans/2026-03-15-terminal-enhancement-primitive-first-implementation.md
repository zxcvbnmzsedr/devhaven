# Terminal Enhancement Primitive-First Remediation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将 DevHaven 终端增强从“shell integration 接管用户状态源”的脆弱实现，整改为 primitive-first 分层架构，先恢复用户 shell 原生语义，再逐步收口 provider-neutral primitive 与通知生命周期。

**Architecture:** 本次实施分五个阶段推进：先修复 zsh/bashi shell bootstrap 与用户状态源边界，再重构 integration 目录结构与测试矩阵，随后引入 provider-neutral terminal primitives，最后下沉 unread/focus/attention 生命周期并补齐文档/回滚机制。Rust launcher 只注入最小环境，shell bootstrap 只做轻量注入，provider wrapper 只翻译事件，Rust primitive/control plane 持有 durable truth。

**Tech Stack:** Rust / Tauri v2、TypeScript、Node 内建 `node --test`、Cargo test/check、pnpm build、zsh/bash shell integration scripts

---

### Task 1: 固化问题复现与 shell 语义回归测试

**Files:**
- Create: `scripts/devhaven-zsh-histfile-regression.test.mjs`
- Create: `scripts/devhaven-zsh-stacked-zdotdir.test.mjs`
- Create: `scripts/devhaven-bash-history-semantics.test.mjs`
- Modify: `tasks/todo.md`
- Test: `scripts/devhaven-shell-integration.test.mjs`

**Step 1: Write the failing test**

新增失败测试，覆盖：
- DevHaven 注入后 `zsh -ic 'print -r -- "$ZDOTDIR|$HISTFILE"'` 应指向用户真实 HOME / ZDOTDIR
- stacked injection 场景下，不允许历史落到 DevHaven integration 目录
- bash integration 不应错误覆盖用户 `HISTFILE` / `PROMPT_COMMAND`

**Step 2: Run test to verify it fails**

Run:

```bash
node --test scripts/devhaven-shell-integration.test.mjs scripts/devhaven-zsh-histfile-regression.test.mjs scripts/devhaven-zsh-stacked-zdotdir.test.mjs scripts/devhaven-bash-history-semantics.test.mjs
```

Expected:
- FAIL，当前实现仍把 zsh history 指到 DevHaven integration 或 `.devhaven/shell-state`

**Step 3: Write minimal implementation**

只添加测试与必要 helper，不动主实现，确保先把问题锁死。

**Step 4: Run test to verify it fails consistently**

Run 同上。

Expected:
- FAIL，且失败信息明确指向 `ZDOTDIR` / `HISTFILE`

**Step 5: Commit**

```bash
git add scripts/devhaven-shell-integration.test.mjs scripts/devhaven-zsh-histfile-regression.test.mjs scripts/devhaven-zsh-stacked-zdotdir.test.mjs scripts/devhaven-bash-history-semantics.test.mjs tasks/todo.md
git commit -m "test: lock shell history semantics regressions"
```

### Task 2: 修复 zsh shell bootstrap，恢复用户真实状态源

**Files:**
- Modify: `src-tauri/src/terminal.rs:289-318`
- Modify: `scripts/shell-integration/zsh/.zshenv`
- Modify: `scripts/shell-integration/zsh/.zprofile`
- Modify: `scripts/shell-integration/zsh/.zshrc`
- Modify: `scripts/shell-integration/zsh/.zlogin`
- Delete: `scripts/shell-integration/zsh/.zsh_history`
- Test: `scripts/devhaven-zsh-histfile-regression.test.mjs`
- Test: `scripts/devhaven-zsh-stacked-zdotdir.test.mjs`

**Step 1: Write the failing test**

使用 Task 1 中的失败测试作为回归栅栏。

**Step 2: Run test to verify it fails**

Run:

```bash
node --test scripts/devhaven-zsh-histfile-regression.test.mjs scripts/devhaven-zsh-stacked-zdotdir.test.mjs
```

Expected:
- FAIL，当前 `ZDOTDIR` / `HISTFILE` 语义不正确

**Step 3: Write minimal implementation**

实施内容：
- `src-tauri/src/terminal.rs` 不再为 zsh 注入 `HISTFILE` 与 `ZSH_COMPDUMP`
- 重写 `.zshenv`：尽早恢复真实 `ZDOTDIR`，source 用户 `.zshenv` 后仅追加 DevHaven bootstrap
- `.zprofile/.zshrc/.zlogin` 只作为兼容 shim，不重新夺回 `ZDOTDIR`
- 删除仓库里的误入 `.zsh_history`

**Step 4: Run test to verify it passes**

Run:

```bash
node --test scripts/devhaven-zsh-histfile-regression.test.mjs scripts/devhaven-zsh-stacked-zdotdir.test.mjs scripts/devhaven-shell-integration.test.mjs
```

Expected:
- PASS

**Step 5: Commit**

```bash
git add src-tauri/src/terminal.rs scripts/shell-integration/zsh/.zshenv scripts/shell-integration/zsh/.zprofile scripts/shell-integration/zsh/.zshrc scripts/shell-integration/zsh/.zlogin scripts/devhaven-zsh-histfile-regression.test.mjs scripts/devhaven-zsh-stacked-zdotdir.test.mjs scripts/devhaven-shell-integration.test.mjs
git rm -f scripts/shell-integration/zsh/.zsh_history
git commit -m "fix: restore zsh shell state semantics"
```

### Task 3: 重构 shell integration 目录与 bootstrap 分层

**Files:**
- Create: `scripts/shell-integration/zsh/devhaven-zsh-bootstrap.zsh`
- Create: `scripts/shell-integration/bash/devhaven-bash-bootstrap.sh`
- Modify: `scripts/shell-integration/devhaven-bash-integration.sh`
- Modify: `scripts/shell-integration/devhaven-wrapper-path.sh`
- Modify: `src-tauri/src/terminal.rs:319-347`
- Test: `scripts/devhaven-shell-integration.test.mjs`
- Test: `scripts/devhaven-bash-history-semantics.test.mjs`

**Step 1: Write the failing test**

补测试覆盖：
- bootstrap 结构分层后，wrapper PATH 仍在最前
- bash `PROMPT_COMMAND` 语义保持
- shell integration 不再依赖历史目录副作用

**Step 2: Run test to verify it fails**

Run:

```bash
node --test scripts/devhaven-shell-integration.test.mjs scripts/devhaven-bash-history-semantics.test.mjs
```

Expected:
- FAIL，当前目录结构与 bootstrap 约定不匹配

**Step 3: Write minimal implementation**

实施内容：
- 将 zsh / bash bootstrap 抽到独立文件
- `devhaven-wrapper-path.sh` 只负责 PATH 注入
- `PROMPT_COMMAND` 只 source bash bootstrap，不再携带其他职责
- `terminal.rs` 改为面向 bootstrap 契约注入最小 env

**Step 4: Run test to verify it passes**

Run:

```bash
node --test scripts/devhaven-shell-integration.test.mjs scripts/devhaven-bash-history-semantics.test.mjs scripts/devhaven-zsh-histfile-regression.test.mjs
```

Expected:
- PASS

**Step 5: Commit**

```bash
git add scripts/shell-integration/zsh/devhaven-zsh-bootstrap.zsh scripts/shell-integration/bash/devhaven-bash-bootstrap.sh scripts/shell-integration/devhaven-bash-integration.sh scripts/shell-integration/devhaven-wrapper-path.sh src-tauri/src/terminal.rs scripts/devhaven-shell-integration.test.mjs scripts/devhaven-bash-history-semantics.test.mjs
 git commit -m "refactor: split terminal shell bootstrap responsibilities"
```

### Task 4: 为终端增强引入 provider-neutral primitives

**Files:**
- Modify: `src-tauri/src/agent_control.rs`
- Modify: `src-tauri/src/lib.rs`
- Modify: `src-tauri/src/command_catalog.rs`
- Modify: `src/services/controlPlane.ts`
- Create: `src/models/terminalPrimitives.ts`
- Create: `src/utils/terminalPrimitiveProjection.test.mjs`
- Test: `src-tauri/src/agent_control.rs`

**Step 1: Write the failing test**

新增失败测试，覆盖：
- `notify_target`
- `set_status / clear_status`
- `set_agent_pid / clear_agent_pid`
- primitive 与现有 control plane tree 的映射

**Step 2: Run test to verify it fails**

Run:

```bash
cargo test agent_control --manifest-path src-tauri/Cargo.toml
node --test src/utils/terminalPrimitiveProjection.test.mjs
```

Expected:
- FAIL，primitive 尚未显式建模

**Step 3: Write minimal implementation**

实施内容：
- 在 Rust 侧新增/收口 provider-neutral primitive API
- 保持 control plane 为 durable truth，但让 wrapper 层只依赖 primitive 契约
- 前端新增 primitive 投影 helper，避免 provider-specific 语义继续散落

**Step 4: Run test to verify it passes**

Run:

```bash
cargo test agent_control --manifest-path src-tauri/Cargo.toml
node --test src/utils/terminalPrimitiveProjection.test.mjs
```

Expected:
- PASS

**Step 5: Commit**

```bash
git add src-tauri/src/agent_control.rs src-tauri/src/lib.rs src-tauri/src/command_catalog.rs src/services/controlPlane.ts src/models/terminalPrimitives.ts src/utils/terminalPrimitiveProjection.test.mjs
git commit -m "feat: add terminal enhancement primitives"
```

### Task 5: 迁移 Codex / Claude wrapper 到 primitive adapter

**Files:**
- Modify: `scripts/devhaven-agent-hook.mjs`
- Modify: `scripts/devhaven-codex-wrapper.mjs`
- Modify: `scripts/devhaven-codex-hook.mjs`
- Modify: `scripts/devhaven-claude-wrapper.mjs`
- Modify: `scripts/bin/codex`
- Modify: `scripts/bin/claude`
- Test: `scripts/devhaven-control.test.mjs`

**Step 1: Write the failing test**

新增失败测试，覆盖：
- provider wrapper 仍可命中真实命令
- provider hook 只翻译事件到 primitive，而非直接依赖 shell 状态副作用
- notify / session-event 到 primitive 的映射稳定

**Step 2: Run test to verify it fails**

Run:

```bash
node --test scripts/devhaven-control.test.mjs
```

Expected:
- FAIL，当前 wrapper 仍直接耦合旧 control plane 事件形态

**Step 3: Write minimal implementation**

实施内容：
- 将 `devhaven-agent-hook.mjs` 收口为 primitive adapter
- codex / claude wrapper 统一走 adapter
- 保持当前功能兼容，但禁止继续碰 shell 状态语义

**Step 4: Run test to verify it passes**

Run:

```bash
node --test scripts/devhaven-control.test.mjs scripts/devhaven-shell-integration.test.mjs
```

Expected:
- PASS

**Step 5: Commit**

```bash
git add scripts/devhaven-agent-hook.mjs scripts/devhaven-codex-wrapper.mjs scripts/devhaven-codex-hook.mjs scripts/devhaven-claude-wrapper.mjs scripts/bin/codex scripts/bin/claude scripts/devhaven-control.test.mjs
git commit -m "refactor: move provider wrappers onto terminal primitives"
```

### Task 6: 下沉 unread / focus / attention 生命周期

**Files:**
- Modify: `src-tauri/src/agent_control.rs`
- Modify: `src/services/controlPlane.ts`
- Modify: `src/hooks/useCodexIntegration.ts`
- Modify: `src/components/terminal/TerminalWorkspaceView.tsx`
- Create: `src/utils/controlPlaneLifecycle.test.mjs`
- Test: `src/utils/controlPlaneProjection.test.mjs`

**Step 1: Write the failing test**

新增失败测试，覆盖：
- focus 后自动已读
- 新通知在 active workspace 上抑制重复外显
- unread / attention lifecycle 由 Rust primitive 输出，前端只做投影

**Step 2: Run test to verify it fails**

Run:

```bash
cargo test agent_control --manifest-path src-tauri/Cargo.toml
node --test src/utils/controlPlaneProjection.test.mjs src/utils/controlPlaneLifecycle.test.mjs
```

Expected:
- FAIL，当前 lifecycle 仍有部分前端 effect 主导

**Step 3: Write minimal implementation**

实施内容：
- Rust 增强 notification lifecycle primitive
- 前端减少 effect 收尾，仅消费已下沉结果
- 保持 toast / 系统通知展示，但不再承担真相源职责

**Step 4: Run test to verify it passes**

Run:

```bash
cargo test agent_control --manifest-path src-tauri/Cargo.toml
node --test src/utils/controlPlaneProjection.test.mjs src/utils/controlPlaneLifecycle.test.mjs
```

Expected:
- PASS

**Step 5: Commit**

```bash
git add src-tauri/src/agent_control.rs src/services/controlPlane.ts src/hooks/useCodexIntegration.ts src/components/terminal/TerminalWorkspaceView.tsx src/utils/controlPlaneLifecycle.test.mjs src/utils/controlPlaneProjection.test.mjs
git commit -m "refactor: move terminal notification lifecycle into primitives"
```

### Task 7: 文档、AGENTS 与整体验证

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`
- Modify: `tasks/lessons.md`
- Create: `docs/plans/2026-03-15-terminal-enhancement-primitive-first-design.md`
- Create: `docs/plans/2026-03-15-terminal-enhancement-primitive-first-implementation.md`

**Step 1: Update docs**

同步更新：
- 终端增强分层边界
- shell integration 与 wrapper 的职责
- control plane / primitive 的长期方向

**Step 2: Run full verification**

Run:

```bash
node --test scripts/devhaven-shell-integration.test.mjs scripts/devhaven-zsh-histfile-regression.test.mjs scripts/devhaven-zsh-stacked-zdotdir.test.mjs scripts/devhaven-bash-history-semantics.test.mjs scripts/devhaven-control.test.mjs src/utils/controlPlaneProjection.test.mjs src/utils/terminalPrimitiveProjection.test.mjs src/utils/controlPlaneLifecycle.test.mjs
cargo test agent_control --manifest-path src-tauri/Cargo.toml
cargo test command_catalog --manifest-path src-tauri/Cargo.toml
cargo test terminal_ --manifest-path src-tauri/Cargo.toml
cargo check --manifest-path src-tauri/Cargo.toml
pnpm exec tsc --noEmit
pnpm build
```

Expected:
- PASS

**Step 3: 手工验证**

Run:

```bash
zsh -ic 'print -r -- "$ZDOTDIR|$HISTFILE"'
zsh -ilc 'fc -l -5'
zsh -ilc 'which codex && which claude'
bash -ilc 'printf "%s\n" "$PROMPT_COMMAND" "$HISTFILE"'
```

Expected:
- 历史与路径语义正确，wrapper 命中正常

**Step 4: Commit**

```bash
git add AGENTS.md tasks/todo.md tasks/lessons.md docs/plans/2026-03-15-terminal-enhancement-primitive-first-design.md docs/plans/2026-03-15-terminal-enhancement-primitive-first-implementation.md
git commit -m "docs: record terminal enhancement primitive-first remediation"
```
