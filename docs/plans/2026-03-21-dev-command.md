# DevHaven 单命令开发入口 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为仓库新增一个接近 `pnpm dev` 体验的 `./dev` 命令，统一完成 vendor 校验、日志观测与原生应用启动。

**Architecture:** 采用根目录 Bash 包装脚本作为唯一开发入口，内部继续复用现有 `setup-ghostty-framework.sh` 与 SwiftPM `DevHavenApp` 可执行 target，不引入新的构建系统。脚本以 macOS unified log 为正式日志真相源，并通过 `trap` 管理后台 `log stream` 生命周期。

**Tech Stack:** Bash、Swift Package Manager、macOS `log` CLI、Ghostty vendor bootstrap

---

### Task 1: 先锁定脚本对外行为

**Files:**
- Create: `macos/scripts/test-dev-command.sh`
- Test: `macos/scripts/test-dev-command.sh`

**Step 1: Write the failing test**

编写 shell 验证脚本，要求 `./dev` 至少支持：

- `--help`
- `--dry-run`
- `--dry-run --logs app`
- `--dry-run --no-log`

关键断言：

- help 输出包含“用法”和 `--dry-run`
- dry-run 默认打印 vendor 校验命令、`log stream` 命令、`swift run --package-path macos DevHavenApp`
- `--logs app` 只包含 `DevHavenNative`
- `--no-log` 不再打印 `log stream`

**Step 2: Run test to verify it fails**

Run: `bash macos/scripts/test-dev-command.sh`  
Expected: FAIL，原因应为根目录 `./dev` 尚不存在，或缺少对应参数行为。

### Task 2: 实现最小可用 `./dev`

**Files:**
- Create: `dev`
- Modify: `README.md`
- Modify: `AGENTS.md`

**Step 1: Write minimal implementation**

在 `dev` 中实现：

- 参数解析：`--help`、`--dry-run`、`--no-log`、`--logs all|app|ghostty`
- 默认 vendor 校验：`bash macos/scripts/setup-ghostty-framework.sh --verify-only`
- 默认启动日志：`log stream --style compact --level debug --predicate ...`
- 默认启动应用：`swift run --package-path macos DevHavenApp`
- `trap` 回收后台日志进程
- `--dry-run` 打印稳定命令文本并退出

同时在 `README.md` 与 `AGENTS.md` 增加新入口说明。

**Step 2: Run test to verify it passes**

Run: `bash macos/scripts/test-dev-command.sh`  
Expected: PASS，输出 `dev command smoke ok`

### Task 3: 做整体验证并回填任务记录

**Files:**
- Modify: `tasks/todo.md`
- Modify: `tasks/lessons.md`

**Step 1: Run verification commands**

Run:

```bash
bash macos/scripts/test-dev-command.sh
./dev --help
git diff --check
```

Expected:

- shell 验证脚本通过
- `./dev --help` 输出帮助
- `git diff --check` 无格式问题

**Step 2: Update task records**

在 `tasks/todo.md` 写入：

- 直接原因
- 是否存在设计层诱因
- 当前修复方案
- 长期建议
- 验证证据

并在 `tasks/lessons.md` 增加一条关于“macOS 原生 GUI 开发入口应同时收口 unified log 与应用启动”的复用教训。
