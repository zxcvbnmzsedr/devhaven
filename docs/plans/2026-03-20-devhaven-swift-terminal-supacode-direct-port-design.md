# DevHaven Swift Terminal Supacode 直移设计

> 状态：已获用户明确确认，按 supacode 成熟实现直接靠拢，不再继续发明本地变体

## 目标

针对当前 Swift 原生 workspace 分屏拖动闪烁问题，停止继续在现有 split/render 链上补丁式修修补补，改为**直接采用 supacode 已验证稳定的 terminal 内核主线**。

本轮目标不是整仓迁成 supacode，而是把最关键、最成熟、最能直接消除 flicker 的 terminal 子系统对齐过来：

- 终端 split tree 的身份稳定策略；
- split drag 期间的纯布局更新链；
- `GhosttyTerminalView` 的 representable 更新边界；
- 终端 surface 的稳定持有与渲染主线。

## 用户确认的方向

用户已明确要求：

1. 目标是**向成熟的 supacode 靠近**；
2. 不再继续围绕当前 DevHaven 自创 split/render 链做局部脑补；
3. 以“**抄 terminal 内核子系统**”作为主策略，而不是仅做风格参考。

## 问题判断

当前闪烁并非只来自旧的焦点回抢；更高置信根因是：

- `WorkspaceSplitView` 拖动时每帧都回写 ratio；
- `WorkspaceSplitTreeView` 会继续触发递归重算；
- `GhosttyTerminalView.updateNSView(...)` 仍会主动调用 `applyLatestModelState(...)`；
- `GhosttyTerminalSurfaceView` 本身又会在 layout / backing change 时同步 surface 尺寸；
- 结果是一次拖动同时卷进“布局变化 + 宿主同步 + surface resize”，形成终端闪烁。

而 supacode 的稳定路径更接近：

- split 拖动只改布局；
- subtree identity 对 ratio 变化稳定；
- `GhosttyTerminalView.updateNSView(...)` 是 no-op；
- 终端主要只响应真实 AppKit layout。

## 采用方案

### 方案 A：继续在现有链路上局部补丁
- 优点：改动表面较少。
- 缺点：已经证明确实会不断冒出新的副作用，且与 supacode 成熟路径继续背离。

### 方案 B：直接迁移 supacode terminal 内核子系统（采用）
- 优点：目标明确、参考实现成熟、能一次性把 split/render/focus 边界校正到稳定模式。
- 缺点：需要接受一轮结构性调整，而不是只动一两个条件分支。

## 本轮范围

### 包含
- 对齐 supacode 的 split tree structural identity 思路；
- 对齐 supacode 的 `GhosttyTerminalView.updateNSView = no-op` 边界；
- 收紧 DevHaven 当前 terminal split/render 链，避免 drag 期间继续主动做 host model sync；
- 保持现有多项目 workspace 壳（`WorkspaceShellView` / `WorkspaceProjectListView`）不动，只替换 terminal 内核路径；
- 补回归测试，锁定“ratio 变化不应改变 subtree 结构身份”“representable 更新不再主动同步 terminal host”这两个核心约束。

### 不包含
- 整体迁入 supacode 的 TCA / reducer 架构；
- worktree-first 的完整产品语义；
- run script / setup script / notification / command palette 全量迁移；
- 原生 control plane / sidebar / file explorer / git panel 等后续产品层。

## 设计边界

### 保留 DevHaven 自己的部分
- `WorkspaceShellView` 多项目 workspace 壳；
- `NativeAppViewModel` 的项目列表 / 详情 / 设置 / 回收站导航；
- `GhosttyAppRuntime` / `GhosttyRuntime` 的 app 级共享 runtime 主线；
- `WorkspaceTerminalLaunchRequest` 提供的 DevHaven 环境变量注入。

### 直接对齐 supacode 的部分
- split tree 的 structural identity 规则；
- split drag 只更新布局，不主动触发 representable 层 terminal sync；
- `GhosttyTerminalView.updateNSView(...)` 不再承担运行态同步职责；
- terminal leaf 渲染优先围绕稳定 surface/view 身份，而不是让 ratio 改变继续触发宿主同步链。

## 验证策略

1. 先补失败测试：
   - `WorkspaceTopologyTests`：锁定 split ratio 改变不会改变 subtree structural identity；
   - `GhosttySurfaceRepresentableUpdatePolicyTests`：锁定 representable update 默认不再主动触发 host sync。
2. 再做最小实现：
   - 引入 structural identity；
   - 收紧 `GhosttyTerminalView.updateNSView(...)`；
   - 按 supacode 思路稳定 split subtree。
3. 最后运行：
   - `swift test --package-path macos --filter WorkspaceTopologyTests`
   - `swift test --package-path macos --filter GhosttySurfaceRepresentableUpdatePolicyTests`
   - `swift test --package-path macos`
   - `swift build --package-path macos`
   - `git diff --check`

## 风险与对策

### 风险 1：去掉 `updateNSView` 主动同步后，某些状态不再刷新
- 对策：先把“真正必须在 update 时同步的状态”与“本应由 layout/bridge 驱动的状态”分离；本轮优先沿 supacode 主线让 update 退回 no-op，再由测试与回归结果决定是否补最小例外。

### 风险 2：只抄一半导致 DevHaven 再次卡在中间态
- 对策：本轮明确“抄 terminal 内核主线，不抄外围产品层”，避免又出现半保留旧链、半接新链的混合态。

### 风险 3：文档与当前架构漂移
- 对策：如本轮落地后确实改变 terminal 主线边界，同步更新 `AGENTS.md`、`tasks/todo.md`、必要的 `tasks/lessons.md`。
