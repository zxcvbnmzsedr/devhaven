# Workspace Flat Pane Split Rendering Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 把 workspace 分屏渲染从递归宿主改成扁平 pane 布局，避免旧 pane 在 split 事务里被重复创建宿主并抢同一个 Ghostty surface。

**Architecture:** 保留现有 `WorkspacePaneTree` / `GhosttySurfaceHostModel` / `WorkspaceTerminalSessionStore` 真相源，不再让 `WorkspaceSplitTreeView` 递归嵌套 `WorkspaceTerminalPaneView`。改为由 tree 先计算 leaf frame 与 split handle frame，再在单个 `GeometryReader + ZStack` 中平铺 pane，并用独立 divider overlay 回写 ratio。这样旧 pane 在 split 后只改变 frame，不再迁移宿主层级。

**Tech Stack:** SwiftUI, AppKit-hosted Ghostty surface, DevHavenCore `WorkspacePaneTree`, XCTest

---

### Task 1: 补齐 split handle 纯布局能力

**Files:**
- Modify: `macos/Sources/DevHavenCore/Models/WorkspaceTopologyModels.swift`
- Test: `macos/Tests/DevHavenCoreTests/WorkspaceTopologyTests.swift`

**Step 1: Write the failing test**

补两条测试：
- root split 只生成一个 handle，path 为空路径，direction 正确；
- 嵌套 split 会同时生成 root 与子 split 的 handle，且子 split path 为 `.left` / `.right` 等真实路径。

**Step 2: Run test to verify it fails**

Run: `swift test --package-path macos --filter WorkspaceTopologyTests`
Expected: FAIL，提示 `splitHandles` / `SplitHandleLayout` 不存在或断言不满足。

**Step 3: Write minimal implementation**

在 `WorkspacePaneTree` 内新增扁平 split handle 布局结构（包含 path、direction、splitBounds、visibleFrame、hitFrame），并复用现有 split ratio 递归计算 handle frame。

**Step 4: Run test to verify it passes**

Run: `swift test --package-path macos --filter WorkspaceTopologyTests`
Expected: PASS

### Task 2: 先锁住 `WorkspaceSplitTreeView` 扁平渲染策略

**Files:**
- Create: `macos/Tests/DevHavenAppTests/WorkspaceSplitTreeViewFlatLayoutTests.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceSplitTreeView.swift`

**Step 1: Write the failing test**

增加 source-based 断言，要求：
- `WorkspaceSplitTreeView` 使用 `leafFrames(in:)` 扁平渲染 pane；
- 使用 `splitHandles(in:)` 独立渲染 divider；
- 不再在该文件中递归构建 `SubtreeView` + `WorkspaceSplitView(...)` 来承载 pane host。

**Step 2: Run test to verify it fails**

Run: `swift test --package-path macos --filter WorkspaceSplitTreeViewFlatLayoutTests`
Expected: FAIL，当前源码仍是递归 `SubtreeView`。

**Step 3: Write minimal implementation**

把 `WorkspaceSplitTreeView` 改为：
- zoom 模式下仍直接渲染单 pane；
- 普通模式下用 `GeometryReader + ZStack(alignment: .topLeading)` 平铺所有 leaf pane；
- divider overlay 单独渲染，并通过 `onSetSplitRatio(path, ratio)` 回写；
- pane view 只由 `pane.id` 标识，不再随 split 树父层级变化而更换宿主。

**Step 4: Run test to verify it passes**

Run: `swift test --package-path macos --filter WorkspaceSplitTreeViewFlatLayoutTests`
Expected: PASS

### Task 3: 让 divider overlay 继续支持拖拽与双击 equalize

**Files:**
- Modify: `macos/Sources/DevHavenApp/WorkspaceSplitTreeView.swift`
- Optional Modify: `macos/Sources/DevHavenApp/WorkspaceSplitView.swift`（若需要抽公共 drag math）
- Test: `macos/Tests/DevHavenAppTests/WorkspaceSplitViewTests.swift`

**Step 1: Write/extend failing test**

若需要，补 source-based 测试确认扁平 divider 仍保留：
- drag -> `onSetSplitRatio(path, ratio)`；
- double click -> `onEqualize(tab.focusedPaneId)`。

**Step 2: Run test to verify it fails**

Run: `swift test --package-path macos --filter WorkspaceSplitViewTests`
Expected: FAIL（若新增断言）。

**Step 3: Write minimal implementation**

在 `WorkspaceSplitTreeView` 内实现 divider overlay：
- 使用 named coordinate space 计算全局拖拽点；
- ratio 以对应 split 的 `splitBounds` 为基准计算；
- 双击 divider 时调用 `onEqualize(tab.focusedPaneId)`。

**Step 4: Run test to verify it passes**

Run: `swift test --package-path macos --filter WorkspaceSplitViewTests`
Expected: PASS

### Task 4: 回归验证分屏宿主复用主线

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/lessons.md`
- Modify: `tasks/todo.md`
- Verify: `macos/Tests/DevHavenAppTests/GhosttySurfaceRepresentableUpdatePolicyTests.swift`
- Verify: `macos/Tests/DevHavenAppTests/GhosttySurfaceLifecycleLoggingIntegrationTests.swift`

**Step 1: Run focused regression tests**

Run:
```bash
swift test --package-path macos --filter 'WorkspaceTopologyTests|WorkspaceSplitTreeViewFlatLayoutTests|WorkspaceSplitViewTests|GhosttySurfaceRepresentableUpdatePolicyTests|GhosttySurfaceLifecycleLoggingIntegrationTests|GhosttySurfaceHostTests|WorkspaceTerminalSessionStoreTests'
```
Expected: PASS

**Step 2: Run build + diff check**

Run:
```bash
swift build --package-path macos
git diff --check
```
Expected: Build complete；无 diff whitespace 错误。

**Step 3: Update docs**

- 在 `AGENTS.md` 记录 `WorkspaceSplitTreeView` 已改为扁平 pane 布局；
- 在 `tasks/lessons.md` 记录“terminal host 不要随 split 树父层级迁移”；
- 在 `tasks/todo.md` 回填直接原因、设计诱因、方案与验证证据。
