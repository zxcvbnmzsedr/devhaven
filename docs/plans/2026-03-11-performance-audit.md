# DevHaven Performance Audit Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 审计 DevHaven 的前端、终端工作区、Rust/Tauri/Web bridge 与构建链路，找出高收益性能优化点并给出落地顺序。

**Architecture:** 先按运行路径拆分为 React 渲染层、终端/事件层、Rust/Tauri/Web server 层、构建/依赖层四个面向进行证据驱动审查；每一层都记录热点代码、触发条件、可能症状、优化策略与验证方式。最终按收益/改动成本/风险排序输出建议。

**Tech Stack:** React + Vite + TypeScript + UnoCSS + Tauri v2 + Rust + Axum + xterm.js

---

### Task 1: 收集结构信息

**Files:**
- Modify: `tasks/todo.md`
- Reference: `package.json`
- Reference: `src/App.tsx`
- Reference: `src-tauri/src/lib.rs`

**Step 1: 建立审计清单**
记录待审计的运行链路与输出模板。

**Step 2: 收集关键入口**
查看应用入口、状态入口、命令注册入口。

**Step 3: 标记潜在高风险模块**
优先关注全局 state、终端工作区、事件广播、项目扫描与持久化。

### Task 2: React/UI 审计

**Files:**
- Reference: `src/App.tsx`
- Reference: `src/components/MainContent.tsx`
- Reference: `src/components/Sidebar.tsx`
- Reference: `src/hooks/useProjectFilter.ts`
- Reference: `src/hooks/useTerminalWorkspace.ts`
- Reference: `src/hooks/useCodexIntegration.ts`
- Reference: `src/state/useDevHaven.ts`

**Step 1: 检查 Context 与 hook 返回值稳定性**
找出会导致大面积 re-render 的状态/回调。

**Step 2: 检查列表/详情/终端 UI 的昂贵计算**
找出 render 中重复计算、全量 map/filter、长列表未虚拟化等问题。

**Step 3: 检查 effect、事件订阅与持久化频率**
找出重复监听、频繁写盘、跨组件级联更新等问题。

### Task 3: Rust/Tauri/Web 审计

**Files:**
- Reference: `src-tauri/src/lib.rs`
- Reference: `src-tauri/src/project_loader.rs`
- Reference: `src-tauri/src/storage.rs`
- Reference: `src-tauri/src/web_server.rs`
- Reference: `src-tauri/src/terminal.rs`
- Reference: `src-tauri/src/quick_command_manager.rs`

**Step 1: 检查命令注册与桥接设计**
找出重复序列化/广播/不必要 I/O。

**Step 2: 检查扫描、缓存、持久化路径**
找出全量重建、同步阻塞、过度序列化等热点。

**Step 3: 检查终端与事件总线**
找出广播风暴、缓存回放、锁竞争与潜在内存增长点。

### Task 4: 构建与依赖审计

**Files:**
- Reference: `package.json`
- Reference: `vite.config.ts`
- Reference: `src/main.tsx`

**Step 1: 检查依赖体积与入口加载方式**
识别可懒加载的重量级依赖。

**Step 2: 检查 dev/prod 配置**
识别热更新、代理、静态资源与优化配置问题。

**Step 3: 形成优先级建议**
按“高收益/低风险优先”输出落地顺序。
