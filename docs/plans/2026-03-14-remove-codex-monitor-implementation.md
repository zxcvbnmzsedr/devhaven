# Remove Codex Monitor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 彻底删除基于 `~/.codex/sessions` 的 Codex monitor，全量切到 adapter/control plane 状态源。

**Architecture:** 前端删除 `useCodexMonitor`、Sidebar CLI 会话区块与 monitor 相关类型/helper，终端继续直接读取 control plane。Rust 侧删除 `codex_monitor.rs`、对应命令与模型，确保 Tauri/Web 命令目录里不再暴露 monitor 入口。

**Tech Stack:** React + TypeScript、Tauri v2、Rust、Node 内建 test

---

### Task 1: 移除 Rust 命令入口

**Files:**
- Modify: `src-tauri/src/command_catalog.rs`
- Modify: `src-tauri/src/lib.rs`
- Modify: `src-tauri/src/models.rs`
- Delete: `src-tauri/src/codex_monitor.rs`

**Step 1: 写失败测试**
- 在 `src-tauri/src/command_catalog.rs` 现有测试中补断言：命令目录不应包含 `get_codex_monitor_snapshot`。

**Step 2: 运行测试确认失败**
Run: `cargo test command_catalog_keeps_web_subset_of_tauri --manifest-path src-tauri/Cargo.toml`
Expected: FAIL，因为当前命令目录仍包含 `get_codex_monitor_snapshot`。

**Step 3: 最小实现**
- 从命令目录与 `lib.rs` 移除 `get_codex_monitor_snapshot`
- 删除 `mod codex_monitor;`
- 删除只服务于 monitor 的 Rust 模型与整份 `codex_monitor.rs`

**Step 4: 重新运行测试确认通过**
Run: `cargo test command_catalog_keeps_web_subset_of_tauri --manifest-path src-tauri/Cargo.toml`
Expected: PASS

### Task 2: 清理前端 monitor 入口

**Files:**
- Modify: `src/App.tsx`
- Modify: `src/components/Sidebar.tsx`
- Modify: `src/hooks/useCodexIntegration.ts`
- Modify: `src/utils/worktreeHelpers.ts`
- Delete: `src/hooks/useCodexMonitor.ts`
- Delete: `src/services/codex.ts`
- Delete: `src/components/CodexSessionSection.tsx`
- Delete: `src/utils/codexMonitorActivation.ts`
- Delete: `src/utils/codexMonitorActivation.test.mjs`
- Delete: `src/models/codex.ts`
- Delete: `src/utils/codexControlPlaneBridge.ts`

**Step 1: 先补/保留最小验证**
- 依赖已有 `src/utils/controlPlaneProjection.test.mjs`，确保终端 Codex 运行态仍能从 control plane 派生。

**Step 2: 最小实现**
- `App.tsx` 不再 import/use `useCodexMonitor` 与 monitor 启用状态
- `Sidebar.tsx` 删除 Codex CLI 会话区块及相关 props
- `useCodexIntegration.ts` 收口为仅监听 control plane Codex 通知
- 删除所有仅服务 monitor 的 TS 文件与 helper

**Step 3: 运行前端验证**
Run: `node --test src/utils/controlPlaneProjection.test.mjs`
Expected: PASS

### Task 3: 文档与全量验证

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`

**Step 1: 更新文档**
- AGENTS.md 明确 Codex monitor 已删除，状态统一来自 control plane / adapter
- todo.md 追加 Review，写清直接原因、设计层诱因、修复方案、长期建议

**Step 2: 全量验证**
Run:
- `node --test src/utils/controlPlaneProjection.test.mjs`
- `pnpm exec tsc --noEmit`
- `pnpm build`
- `cargo test command_catalog_keeps_web_subset_of_tauri --manifest-path src-tauri/Cargo.toml`
- `cargo check --manifest-path src-tauri/Cargo.toml`

Expected: 全部通过
