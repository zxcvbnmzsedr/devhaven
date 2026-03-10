# Project Scale Performance Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让 DevHaven 在“项目很多 / 终端打开很多项目与标签页”时，先明显降低卡顿，再逐步收敛后台总量成本。

**Architecture:** 先砍终端层的常驻挂载和全局 fan-out，因为这是最重、最直接影响交互流畅度的链路；再处理主界面的全量渲染与后台全量补算，把系统从“按全部已打开对象工作”收敛成“按当前活跃对象工作”。

**Tech Stack:** React 19、TypeScript、Tauri v2、Rust、xterm、Axum

---

### Task 1: 建立性能基线与验证脚本

**Files:**
- Modify: `tasks/todo.md`
- Create: `docs/perf/2026-03-10-project-scale-baseline.md`
- Verify: `npm run build`
- Verify: `cargo test --manifest-path src-tauri/Cargo.toml`

**Step 1: 记录基线场景**
- 终端场景：打开 1 / 5 / 10 个项目，每个项目 2 个 tab，记录切换项目、输入、滚动体感。
- 主界面场景：项目总数 100+ 时，分别在卡片 / 列表模式记录搜索输入、切换标签、打开详情面板的体感。

**Step 2: 补充可复现清单**
- 在 `docs/perf/2026-03-10-project-scale-baseline.md` 记录复现步骤、环境、项目数量、终端数量、Codex 会话数量。

**Step 3: 运行基本健康检查**
Run: `npm run build`
Expected: TypeScript + Vite 构建通过。

**Step 4: 运行 Rust 测试**
Run: `cargo test --manifest-path src-tauri/Cargo.toml`
Expected: 现有 Rust 测试通过，保证后续调优前基线稳定。

**Step 5: Commit**
```bash
git add tasks/todo.md docs/perf/2026-03-10-project-scale-baseline.md
git commit -m "docs: add project scale performance baseline"
```

### Task 2: 只挂载当前激活项目的终端工作区

**Files:**
- Modify: `src/components/terminal/TerminalWorkspaceWindow.tsx`
- Modify: `src/hooks/useTerminalWorkspace.ts`
- Verify: `npm run build`
- Manual: 终端打开 10 个项目后切换项目

**Step 1: 写失败验证用例（手工）**
- 打开 10 个项目。
- 观察当前实现里 `openProjects.map(...)` 会为每个项目挂一个 `TerminalWorkspaceView`。
- 目标行为：只有当前 `activeProject` 挂载，切走的项目保留可恢复状态，但不继续常驻渲染树。

**Step 2: 写最小实现**
- 在 `src/components/terminal/TerminalWorkspaceWindow.tsx` 中，从“全量 map + 隐藏”改成“只渲染 activeProject 的 `TerminalWorkspaceView`”。
- 保持左侧“已打开项目”列表不变，状态仍由 `terminalOpenProjects` 管理。

**Step 3: 验证**
- 切换项目后，原项目终端状态可恢复。
- React 挂载数量显著下降，卡顿应立刻改善。

**Step 4: 运行构建**
Run: `npm run build`
Expected: 前端构建通过。

**Step 5: Commit**
```bash
git add src/components/terminal/TerminalWorkspaceWindow.tsx src/hooks/useTerminalWorkspace.ts
git commit -m "perf: mount only active terminal workspace"
```

### Task 3: 只保留当前激活 Tab 的终端 pane 树

**Files:**
- Modify: `src/components/terminal/TerminalWorkspaceView.tsx`
- Modify: `src/components/terminal/SplitLayout.tsx`
- Modify: `src/components/terminal/TerminalPane.tsx`
- Verify: `npm run build`
- Manual: 一个项目内打开 5 个 tab / 多个 split

**Step 1: 写失败验证用例（手工）**
- 当前实现会为 `workspace.tabs` 全量渲染，每个 tab 下的 `TerminalPane` 都还活着。
- 目标行为：只渲染当前 `activeTabId` 对应的 pane 树，非激活 tab 只保留序列化状态。

**Step 2: 写最小实现**
- 在 `src/components/terminal/TerminalWorkspaceView.tsx` 中从 `workspace.tabs.map(...)` 改为仅渲染活动 tab。
- 确保切换 tab 时仍能恢复滚动区与 session 绑定。

**Step 3: 补强状态恢复**
- 确认 `savedState`、`onRegisterSnapshotProvider`、`handleSessionExit` 在卸载/切换 tab 场景下不丢状态。

**Step 4: 验证**
- 多 tab 切换正常。
- 非激活 tab 不再持有活跃的 xterm / 监听器 / ResizeObserver。

**Step 5: Commit**
```bash
git add src/components/terminal/TerminalWorkspaceView.tsx src/components/terminal/SplitLayout.tsx src/components/terminal/TerminalPane.tsx
git commit -m "perf: mount only active terminal tab tree"
```

### Task 4: 把终端输出分发从“广播给全部 pane”收敛成“按 sessionId 路由”

**Files:**
- Modify: `src/services/terminal.ts`
- Modify: `src/components/terminal/TerminalPane.tsx`
- Verify: `npm run build`
- Manual: 多项目同时有输出

**Step 1: 写失败验证用例（设计级）**
- 当前 `createSharedTerminalEventListener` 会遍历全部 handler，再让每个 pane 自己过滤。
- 目标行为：按 `sessionId` 建 handler bucket，只把输出投递给对应 pane。

**Step 2: 写最小实现**
- 在 `src/services/terminal.ts` 为 `terminal-output` / `terminal-exit` 增加按 `sessionId` 注册的索引。
- `TerminalPane` 注册/卸载时绑定自己的 `sessionId`。

**Step 3: 验证**
- 单个 session 输出不再触发所有 pane handler。
- 退出事件同样按 session 精确投递。

**Step 4: 运行构建**
Run: `npm run build`
Expected: 构建通过。

**Step 5: Commit**
```bash
git add src/services/terminal.ts src/components/terminal/TerminalPane.tsx
git commit -m "perf: route terminal events by session id"
```

### Task 5: 停掉非激活 workspace 的 quick-command 轮询与全量 reconcile

**Files:**
- Modify: `src/hooks/useQuickCommandRuntime.ts`
- Modify: `src/components/terminal/TerminalWorkspaceView.tsx`
- Verify: `npm run build`
- Manual: 打开多个项目但只操作一个项目的运行配置

**Step 1: 写失败验证用例（手工）**
- 当前每个 workspace 都会 `getQuickCommandSnapshot()` 一次并每 10 秒轮询一次。
- 目标行为：只有当前激活 workspace 保持轮询；非激活 workspace 仅靠必要的恢复动作或被动同步。

**Step 2: 写最小实现**
- 给 `useQuickCommandRuntime` 增加 `enabled` / `isActiveWorkspace` 开关。
- 在 `src/components/terminal/TerminalWorkspaceView.tsx` 里把 `isActive` 透传进去。

**Step 3: 验证**
- 非激活项目不再持续轮询。
- 当前激活项目的运行配置状态仍正确。

**Step 4: 运行构建**
Run: `npm run build`
Expected: 构建通过。

**Step 5: Commit**
```bash
git add src/hooks/useQuickCommandRuntime.ts src/components/terminal/TerminalWorkspaceView.tsx
git commit -m "perf: pause quick command reconcile for inactive workspaces"
```

### Task 6: 把 workspace 自动保存从“全 session 快照”改成“按脏 session / 关键时机保存”

**Files:**
- Modify: `src/components/terminal/TerminalWorkspaceView.tsx`
- Modify: `src/components/terminal/TerminalPane.tsx`
- Modify: `src/models/terminal.ts`
- Verify: `npm run build`
- Verify: `cargo test --manifest-path src-tauri/Cargo.toml`

**Step 1: 写失败验证用例（设计级）**
- 当前 800ms debounce 后会抓整个 workspace 的 session 快照。
- 目标行为：普通 UI 变更仅保存布局；终端内容仅在 tab 切换、项目切换、窗口隐藏、beforeunload 等关键时机保存，或只保存脏 session。

**Step 2: 写最小实现**
- 把 workspace 持久化拆成“布局状态”和“终端快照状态”。
- 为 `TerminalPane` 增加 dirty 标记；只有 dirty session 参与 serialize。

**Step 3: 验证**
- 频繁拖动面板、切右侧 sidebar、改 run panel 高度时，不再导致全部 session serialize。
- 关闭 / 切换后终端状态仍可恢复。

**Step 4: 运行验证**
Run: `npm run build && cargo test --manifest-path src-tauri/Cargo.toml`
Expected: 前后端验证通过。

**Step 5: Commit**
```bash
git add src/components/terminal/TerminalWorkspaceView.tsx src/components/terminal/TerminalPane.tsx src/models/terminal.ts
git commit -m "perf: reduce terminal workspace snapshot serialization"
```

### Task 7: 主界面卡片模式增量渲染 / 虚拟化

**Files:**
- Modify: `src/components/MainContent.tsx`
- Modify: `src/components/ProjectCard.tsx`
- Modify: `src/hooks/useProjectFilter.ts`
- Verify: `npm run build`
- Manual: 100+ 项目下搜索、滚动、切标签

**Step 1: 写失败验证用例（手工）**
- 当前卡片模式会直接渲染全部 `filteredProjects`。
- 目标行为：卡片模式也像列表模式一样分批，或直接改为虚拟化。

**Step 2: 写最小实现**
- 优先方案：复用列表模式的批次加载逻辑，让卡片模式先按 40~60 条渐进加载。
- 保守保持 UI 不变，只改渲染策略。

**Step 3: 验证**
- 100+ 项目下首屏更快。
- 搜索和标签切换时主线程阻塞明显下降。

**Step 4: 运行构建**
Run: `npm run build`
Expected: 构建通过。

**Step 5: Commit**
```bash
git add src/components/MainContent.tsx src/components/ProjectCard.tsx src/hooks/useProjectFilter.ts
git commit -m "perf: batch render project cards"
```

### Task 8: 把 Git Daily / 热力图 / Codex 监控从顶层全量派生改成增量更新

**Files:**
- Modify: `src/hooks/useAppActions.ts`
- Modify: `src/state/useHeatmapData.ts`
- Modify: `src/hooks/useCodexMonitor.ts`
- Modify: `src/hooks/useCodexIntegration.ts`
- Modify: `src/App.tsx`
- Modify: `src-tauri/src/codex_monitor.rs`
- Verify: `npm run build`
- Verify: `cargo test --manifest-path src-tauri/Cargo.toml`

**Step 1: 写失败验证用例（设计级）**
- 当前缺失 `git_daily` 会自动批量补算，顶层 `AppLayout` 还会把热力图、Codex 状态一起重算。
- 目标行为：只对新增 / 变更项目增量补算；Codex snapshot 只在内容变化时推送；热力图签名避免整包重扫。

**Step 2: 写最小实现**
- `useAppActions`：把 Git Daily 自动补算改成分批、空闲时、可中断。
- `useHeatmapData`：引入增量签名或按项目缓存，而不是每次重扫全量 `projects`。
- `useCodexMonitor` / `src-tauri/src/codex_monitor.rs`：降低重复 snapshot 推送频率，只在变化时发事件。

**Step 3: 验证**
- 首屏加载和项目刷新后，后台 CPU 抖动更小。
- 没有活跃 Codex 变化时，前端不再频繁 setState。

**Step 4: 运行验证**
Run: `npm run build && cargo test --manifest-path src-tauri/Cargo.toml`
Expected: 前后端验证通过。

**Step 5: Commit**
```bash
git add src/hooks/useAppActions.ts src/state/useHeatmapData.ts src/hooks/useCodexMonitor.ts src/hooks/useCodexIntegration.ts src/App.tsx src-tauri/src/codex_monitor.rs
git commit -m "perf: make project-wide background updates incremental"
```
