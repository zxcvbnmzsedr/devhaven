# DevHaven Codex 通知完整修复 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让 DevHaven 的 Codex 通知达到“正文稳定、Rust 主投递、pane/surface 级已读、前端只做 UI 投影”的完整闭环，不再依赖前端回拉整棵 control-plane tree 才能完成主通知链路。

**Architecture:** 保留现有 `wrapper -> hook -> control plane` 主线，但把 notification record 升级为结构化通知模型（`title/subtitle/body/level/message`），由 Rust `devhaven_notify` / `devhaven_notify_target` 在落盘后直接完成系统通知主投递；前端 `useCodexIntegration.ts` 改为只消费结构化事件 payload 来弹 toast，并在 Web / fallback 场景下补浏览器通知。workspace 自动已读从“active workspace 全量清理”收紧为“仅 active pane/surface 匹配的 unread 自动已读”。

**Tech Stack:** Tauri v2、Rust、React 19、TypeScript、Node 内建 test、Cargo test/check。

---

### Task 1: 修正 Codex notify payload 兼容并锁定脚本级回归

**Files:**
- Modify: `scripts/devhaven-codex-hook.mjs`
- Test: `scripts/devhaven-control.test.mjs`

**Step 1: 扩展 notify payload 正文字段兼容**

- `summarizeNotifyPayload` 同时支持 `last-assistant-message`、`last_assistant_message`、`lastAssistantMessage`。
- 仍保持 `message/summary/body/text` 优先级更高。
- 不恢复 legacy duplicate notify 路径。

**Step 2: 在 primitive-only 通知路径上传递结构化 body**

- `dispatchCodexNotificationLifecycle` 调用 `sendTargetedNotification` 时显式携带 `body=summary.message`。
- 保持 `title/message/level` 兼容输出不变。

**Step 3: 运行脚本级验证**

Run: `node --test scripts/devhaven-control.test.mjs`
Expected: 通过，含 hyphen-case Codex notify 新用例。

### Task 2: 升级 control plane 为结构化通知模型

**Files:**
- Modify: `src-tauri/src/agent_control.rs`
- Modify: `src-tauri/src/lib.rs`
- Modify: `src-tauri/src/command_catalog.rs`
- Modify: `src/models/controlPlane.ts`

**Step 1: 扩展 Rust notification record / request**

- `NotificationRecord` 新增：`title?`、`subtitle?`、`body?`、`level?`。
- `NotificationInput` 与 `DevHavenNotifyRequest` / `DevHavenNotifyTargetRequest` 同步支持结构化字段。
- `message` 继续保留为兼容展示文本。

**Step 2: 在 Rust 内统一规范化通知内容**

- 新增 helper 统一生成：
  - display message（有 `title` 时输出 `title：body`）
  - notification body（优先 `body`，回退 `message`）
- `push_notification` 持久化结构化字段并生成兼容 `message`。

**Step 3: 扩展 control-plane changed payload**

- `ControlPlaneChangedPayload` 在 notification 相关 reason 下带上 `notification` 结构体与 `notificationId`。
- 其他 reason 显式传 `notification: None`。

**Step 4: 运行 Rust 定向验证**

Run: `cargo test agent_control_registry_preserves_structured_notification_fields --manifest-path src-tauri/Cargo.toml`
Expected: 通过，notification record/tree 均保留 `title/body/subtitle`。

### Task 3: 把系统通知主投递前移到 Rust，并让前端退居 UI-only

**Files:**
- Modify: `src-tauri/src/agent_control.rs`
- Modify: `src/hooks/useCodexIntegration.ts`
- Reuse: `src/services/system.ts`

**Step 1: Rust 侧在 notify 落盘后直接投递系统通知**

- `notify_control_plane` 在 `push_notification` 成功后，立即根据结构化 record 调用后端 `send_system_notification`。
- 系统通知失败仅记录 warning，不影响 control plane 记录与事件发射。

**Step 2: 前端消费改为事件直读，不再依赖 tree pull 作为主链**

- `useCodexIntegration.ts` 优先消费 `payload.notification`。
- 只在 payload 缺失结构化通知时，兼容回退到旧的 `loadControlPlaneTree + collectNewControlPlaneNotifications`。
- Tauri 运行时不再由前端重复发送系统通知；仅 Web / 非 Tauri fallback 场景保留 `sendSystemNotification`。

**Step 3: 保持 Codex 识别收敛**

- 事件直读路径优先通过 `notification.title/message/body` 判断是否为 Codex 通知。
- 保留旧 `isCodexTree` 兼容路径，避免老 payload 或混合版本场景直接静默。

### Task 4: 把自动已读从 workspace 级收紧为 pane/surface 级

**Files:**
- Modify: `src/utils/controlPlaneAutoRead.ts`
- Modify: `src/components/terminal/TerminalWorkspaceView.tsx`
- Modify: `src/utils/controlPlaneProjection.ts`
- Test: `src/utils/controlPlaneAutoRead.test.mjs`
- Test: `src/utils/controlPlaneLifecycle.test.mjs`

**Step 1: 改造 auto-read 输入接口**

- `collectNotificationIdsToMarkRead` 不再只接收 `isActive`，改为同时接收：
  - `activePaneId`
  - `activeSurfaceId`
  - `activeTerminalSessionId`
- workspace 级通知仍允许在当前 workspace 前台活跃时已读。

**Step 2: `TerminalWorkspaceView` 传入当前焦点 surface 上下文**

- 复用 control-plane active surface 匹配逻辑，先求得当前匹配 surface，再传给 auto-read helper。
- 不再在 workspace 激活时批量清理全部 unread。

**Step 3: pane-level latest message 改为读取真实匹配通知**

- `projectControlPlaneSurface` 不再用 dummy notification 拼消息。
- 改为读取 `tree.notifications` 中与当前 pane/surface/session 匹配的真实 notification，确保消息在 read 后仍能保留正确 latest text。

**Step 4: 运行前端定向验证**

Run: `node --test src/utils/controlPlaneAutoRead.test.mjs src/utils/controlPlaneLifecycle.test.mjs scripts/devhaven-control.test.mjs`
Expected: 全通过，active surface 只清自身 unread，pane latest message 正确保留。

### Task 5: 同步文档与架构说明

**Files:**
- Create: `docs/plans/2026-03-18-codex-notification-fix-plan.md`
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`

**Step 1: 写入本计划文档**

- 记录本次完整修复的目标、阶段、验证与迁移策略。

**Step 2: 更新 `AGENTS.md` 中控制面职责描述**

- 说明 notification record 已升级为结构化字段。
- 说明系统通知主投递已前移到 Rust。
- 说明 auto-read 现在是 pane/surface 级，而不是 active workspace 全量清理。

**Step 3: 在 `tasks/todo.md` 写入实现 Review**

- 记录直接原因、设计层诱因、当前修复方案与长期建议。

### Task 6: 运行最终验证

**Files:**
- Verify only

**Step 1: 前端/脚本测试**

Run: `node --test src/utils/controlPlaneAutoRead.test.mjs src/utils/controlPlaneProjection.test.mjs src/utils/controlPlaneLifecycle.test.mjs scripts/devhaven-control.test.mjs`
Expected: 全通过。

**Step 2: TypeScript 编译**

Run: `node node_modules/typescript/bin/tsc --noEmit`
Expected: 通过，无 TS 报错。

**Step 3: Rust 编译检查**

Run: `cargo check --manifest-path src-tauri/Cargo.toml`
Expected: 通过，无结构体字段/命令签名不一致问题。

**Step 4: diff 健康检查**

Run: `git diff --check`
Expected: 通过，无冲突标记或 whitespace 错误。
