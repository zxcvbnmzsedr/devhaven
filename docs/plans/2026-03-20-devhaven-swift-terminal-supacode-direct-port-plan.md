# DevHaven Swift Terminal Supacode 直移 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 直接把当前 Swift 原生 terminal 的 split/render/focus 主线对齐到 supacode 成熟实现，优先消除分屏拖动闪烁。

**Architecture:** 保留 DevHaven 现有多项目 workspace 外层壳与 app 级共享 Ghostty runtime，不再继续发明本地 split/render 变体。terminal 内核层改为对齐 supacode：split tree structural identity 忽略 ratio、representable update 不再主动 sync host、drag 主线只做布局变化。

**Tech Stack:** Swift 6、SwiftUI、AppKit、GhosttyKit、SwiftPM。

---

### Task 1: 先用测试锁定 supacode 风格的结构身份约束

**Files:**
- Modify: `macos/Tests/DevHavenCoreTests/WorkspaceTopologyTests.swift`
- Modify: `macos/Sources/DevHavenCore/Models/WorkspaceTopologyModels.swift`

**Step 1: 写失败测试**

在 `WorkspaceTopologyTests.swift` 新增：
- 创建一个双 pane split；
- 记录 split tree 的 structural identity；
- 只改变 ratio；
- 断言 structural identity 不变。

**Step 2: 运行测试确认失败**

Run: `swift test --package-path macos --filter WorkspaceTopologyTests`

Expected: 新测试失败，报错当前 `WorkspacePaneTree` / `Node` 没有 structural identity 或 ratio 变化导致身份变化。

**Step 3: 最小实现**

在 `WorkspaceTopologyModels.swift`：
- 为 `WorkspacePaneTree` 新增 `structuralIdentity`；
- 为 `WorkspacePaneTree.Node` 新增 `structuralIdentity`；
- 结构比较与哈希忽略 split ratio，只保留 direction + 子节点结构 + leaf pane id。

**Step 4: 重跑测试确认转绿**

Run: `swift test --package-path macos --filter WorkspaceTopologyTests`

Expected: `WorkspaceTopologyTests` 全绿。

### Task 2: 先用测试锁定 representable update 不再主动 sync host

**Files:**
- Create: `macos/Tests/DevHavenAppTests/GhosttySurfaceRepresentableUpdatePolicyTests.swift`
- Create: `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceRepresentableUpdatePolicy.swift`
- Modify: `macos/Sources/DevHavenApp/Ghostty/GhosttyTerminalView.swift`

**Step 1: 写失败测试**

新增 `GhosttySurfaceRepresentableUpdatePolicyTests.swift`，断言默认策略下 representable update 不应主动触发 host sync。

**Step 2: 运行测试确认失败**

Run: `swift test --package-path macos --filter GhosttySurfaceRepresentableUpdatePolicyTests`

Expected: 编译失败，提示 `GhosttySurfaceRepresentableUpdatePolicy` 不存在。

**Step 3: 最小实现**

- 新建 `GhosttySurfaceRepresentableUpdatePolicy.swift`，收口一个 supacode 风格约束：`updateNSView` 默认不做 host sync；
- `GhosttyTerminalView.updateNSView(...)` 改为按该策略直接 no-op，不再主动 `applyLatestModelState(...)`。

**Step 4: 重跑测试确认转绿**

Run: `swift test --package-path macos --filter GhosttySurfaceRepresentableUpdatePolicyTests`

Expected: 通过。

### Task 3: 对齐 split subtree 的稳定渲染路径

**Files:**
- Modify: `macos/Sources/DevHavenApp/WorkspaceSplitTreeView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceSplitView.swift`
- Test: `macos/Tests/DevHavenCoreTests/WorkspaceTopologyTests.swift`

**Step 1: 写失败测试 / 先补结构约束**

如果 Task 1 绿灯后仍缺 “leaf/subtree 身份稳定” 语义，则在 `WorkspaceTopologyTests` 再补：
- split ratio 变化后，leaf pane id 顺序与结构 identity 保持稳定。

**Step 2: 运行测试确认失败**

Run: `swift test --package-path macos --filter WorkspaceTopologyTests`

Expected: 若当前渲染前置结构约束未锁住则失败。

**Step 3: 最小实现**

- 让 `WorkspaceSplitTreeView` 对齐 supacode 的 subtree 身份思路：给 root/subtree 绑定 structural identity；
- 减少 `AnyView` 带来的额外身份抖动；
- 保持 `WorkspaceSplitView` 只负责布局与 divider drag，不再掺进任何 host/surface 副作用。

**Step 4: 重跑测试确认转绿**

Run: `swift test --package-path macos --filter WorkspaceTopologyTests`

Expected: 通过。

### Task 4: 做回归验证并同步文档

**Files:**
- Modify: `AGENTS.md`（如果 terminal 主线职责边界发生实质变化）
- Modify: `tasks/todo.md`
- Modify: `tasks/lessons.md`

**Step 1: 运行完整验证**

Run:
- `swift test --package-path macos --filter GhosttySurfaceRepresentableUpdatePolicyTests`
- `swift test --package-path macos --filter WorkspaceTopologyTests`
- `swift test --package-path macos`
- `swift build --package-path macos`
- `git diff --check`

**Step 2: 同步文档**

- 在 `tasks/todo.md` 追加本轮 Review，记录根因、差异、修法与验证证据；
- 用户已明确纠偏“向成熟 supacode 靠近就直接抄”，把这条可复用边界写入 `tasks/lessons.md`；
- 如果 terminal 主线职责确实收口为更接近 supacode 的 split/render/focus 边界，同步更新 `AGENTS.md`。

**Step 3: 最终自检**

- 确认本轮只替换 terminal 内核主线，没有误伤多项目 workspace 外壳；
- 确认没有继续把拖动事件穿透到 representable update / host sync 主线；
- 确认所有验证命令有真实通过证据。
