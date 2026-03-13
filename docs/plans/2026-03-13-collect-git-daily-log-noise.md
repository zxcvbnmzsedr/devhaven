# Collect Git Daily 日志收口实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 收口 collect_git_daily 的高频日志，并避免同一轮自动补齐过程中重复重排 Git Daily 统计任务。

**Architecture:** 前端把 Git Daily 自动刷新调度提炼为可测试的纯策略函数，保证“缺失数据补齐”这类同一轮任务在批次推进时不会被重复改签。后端仅对 collect_git_daily 关闭命令级 info 日志，保留其他命令的可观测性。

**Tech Stack:** React 19、TypeScript、Node built-in test、Rust/Tauri

---

### Task 1: Git Daily 自动刷新策略

**Files:**
- Create: `src/utils/gitDailyRefreshPolicy.ts`
- Test: `src/utils/gitDailyRefreshPolicy.test.mjs`
- Modify: `src/hooks/useAppActions.ts`

**Step 1: 写失败测试**
- 覆盖“缺失数据补齐时，剩余路径是当前运行任务子集则继续沿用当前任务”
- 覆盖“身份切换等主动刷新应抢占旧任务”

**Step 2: 运行测试确认失败**
- Run: `node --test src/utils/gitDailyRefreshPolicy.test.mjs`

**Step 3: 写最小实现并接入 useAppActions**
- 让自动缺失补齐不再因为每批次写回项目状态而重新改签

**Step 4: 重新运行测试确认通过**
- Run: `node --test src/utils/gitDailyRefreshPolicy.test.mjs`

### Task 2: collect_git_daily 日志收口

**Files:**
- Modify: `src-tauri/src/lib.rs`

**Step 1: 调整命令日志策略**
- 对 `collect_git_daily` 关闭 `command start/done` 与额外的 `paths=` info 日志

**Step 2: 运行 Rust 定向验证**
- Run: `cargo check --manifest-path src-tauri/Cargo.toml`

### Task 3: 回归验证与记录

**Files:**
- Modify: `tasks/todo.md`

**Step 1: 运行定向验证**
- `node --test src/utils/gitDailyRefreshPolicy.test.mjs`
- `pnpm exec tsc --noEmit`
- `cargo check --manifest-path src-tauri/Cargo.toml`

**Step 2: 在 `tasks/todo.md` 追加 Review**
- 记录根因、修复点、验证证据
