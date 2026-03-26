# IDEA Git/Commit 独立 Diff 标签页 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在 DevHaven 中为 `Git Log Changes Browser + Commit Changes Browser` 统一接入“独立标签页打开 diff”的主链，并提供原生 side-by-side / unified diff viewer。

**Architecture:** 保持 `GhosttyWorkspaceController` 继续只负责 terminal tab / pane / restore；在 `NativeAppViewModel + WorkspaceHostView` 层新增 runtime-only diff tab 与 presented-tab 选择能力。Git Log 与 Commit 只产出统一的 `WorkspaceDiffOpenRequest`，真正的 diff 文档加载与渲染由新的 `WorkspaceDiffTabViewModel + WorkspaceDiffTabView` 承接。

**Tech Stack:** SwiftUI、Observation、DevHavenCore、Native Git CLI、XCTest

---

### Task 1: 锁定 runtime diff tab 与 close planner 契约

**Files:**
- Modify: `tasks/todo.md`
- Create: `macos/Tests/DevHavenCoreTests/NativeAppViewModelWorkspaceDiffTabTests.swift`
- Modify: `macos/Tests/DevHavenAppTests/InitialWindowActivatorTests.swift`
- Modify: `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`
- Modify: `macos/Sources/DevHavenApp/AppRootView.swift`

**Step 1: 写红灯测试**

- 新增 `NativeAppViewModelWorkspaceDiffTabTests`，锁定：
  - `openWorkspaceDiffTab(...)` 会创建 runtime diff tab
  - 同 identity 二次打开只会切换选中，不会重复创建
  - 关闭 diff tab 不影响 terminal tab 数量
- 修改 `InitialWindowActivatorTests.swift`，锁定：
  - 当前选中 diff tab 时，close planner 优先返回“关闭 diff tab”而不是“关闭 pane”

**Step 2: 运行红灯**

Run:

```bash
swift test --package-path macos --filter 'NativeAppViewModelWorkspaceDiffTabTests|InitialWindowActivatorTests'
```

Expected:
- 编译失败或断言失败，提示 `NativeAppViewModel` 还没有 diff tab runtime 状态与 close planner 分支

**Step 3: 最小实现**

- 在 `NativeAppViewModel.swift` 中新增：
  - `workspaceDiffTabsByProjectPath`
  - `workspaceSelectedPresentedTabByProjectPath`
  - `openWorkspaceDiffTab(...)`
  - `closeWorkspaceDiffTab(...)`
  - `selectWorkspacePresentedTab(...)`
  - `activeWorkspacePresentedTabs`（或同义 computed property）
- 在 `AppRootView.swift` 的 close shortcut context / planner 中加入 diff tab 分支

**Step 4: 运行绿灯**

Run:

```bash
swift test --package-path macos --filter 'NativeAppViewModelWorkspaceDiffTabTests|InitialWindowActivatorTests'
```

Expected:
- 新增与修改测试通过

**Step 5: Commit**

```bash
git add tasks/todo.md macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift macos/Sources/DevHavenApp/AppRootView.swift macos/Tests/DevHavenCoreTests/NativeAppViewModelWorkspaceDiffTabTests.swift macos/Tests/DevHavenAppTests/InitialWindowActivatorTests.swift
git commit -m "feat(workspace): add runtime diff tab state"
```

---

### Task 2: 把 Workspace 顶部 tab bar 升级为 terminal + diff 共用展示层

**Files:**
- Create: `macos/Tests/DevHavenAppTests/WorkspaceHostViewTests.swift`
- Create: `macos/Tests/DevHavenAppTests/WorkspaceTabBarViewTests.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceHostView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceTabBarView.swift`

**Step 1: 写红灯测试**

- `WorkspaceHostViewTests` 锁定：
  - 当前选中 diff tab 时，host 不应继续渲染 terminal split tree，而应路由到 diff host
- `WorkspaceTabBarViewTests` 锁定：
  - tab bar 可同时显示 terminal tab 与 diff tab
  - 选中 diff tab 时，split 按钮必须禁用

**Step 2: 运行红灯**

Run:

```bash
swift test --package-path macos --filter 'WorkspaceHostViewTests|WorkspaceTabBarViewTests'
```

Expected:
- 因 app 层仍只接受 terminal tabs 而失败

**Step 3: 最小实现**

- 让 `WorkspaceHostView` 从 `NativeAppViewModel` 读取 active workspace 的 presented tabs
- `WorkspaceTabBarView` 从 `[WorkspaceTabState]` 升级为消费统一展示模型（如 `WorkspacePresentedTabItem`）
- 选中 terminal tab 时继续驱动 `GhosttyWorkspaceController.selectTab(...)`
- 选中 diff tab 时只切换 runtime selection

**Step 4: 运行绿灯**

Run:

```bash
swift test --package-path macos --filter 'WorkspaceHostViewTests|WorkspaceTabBarViewTests'
```

Expected:
- tab bar / host 结构测试通过

**Step 5: Commit**

```bash
git add macos/Sources/DevHavenApp/WorkspaceHostView.swift macos/Sources/DevHavenApp/WorkspaceTabBarView.swift macos/Tests/DevHavenAppTests/WorkspaceHostViewTests.swift macos/Tests/DevHavenAppTests/WorkspaceTabBarViewTests.swift
git commit -m "feat(app): render diff tabs in workspace tab bar"
```

---

### Task 3: 建立 diff 文档模型、完整 diff 加载链路与 patch parser

**Files:**
- Create: `macos/Sources/DevHavenCore/Models/WorkspaceDiffModels.swift`
- Create: `macos/Sources/DevHavenCore/Storage/WorkspaceDiffPatchParser.swift`
- Create: `macos/Sources/DevHavenCore/ViewModels/WorkspaceDiffTabViewModel.swift`
- Create: `macos/Tests/DevHavenCoreTests/WorkspaceDiffPatchParserTests.swift`
- Create: `macos/Tests/DevHavenCoreTests/WorkspaceDiffTabViewModelTests.swift`
- Modify: `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`

**Step 1: 写红灯测试**

- `WorkspaceDiffPatchParserTests` 锁定：
  - 能解析普通 unified diff 的 hunk / line type
  - 能生成 side-by-side 所需的 paired rows
  - empty diff / binary diff / malformed diff 有稳定 fallback
- `WorkspaceDiffTabViewModelTests` 锁定：
  - Git Log source 会走 commit-file diff loader
  - Commit source 会走 working-tree diff loader
  - 切换 viewer mode 不丢现有文档内容
  - 加载失败时会产生稳定中文错误态

**Step 2: 运行红灯**

Run:

```bash
swift test --package-path macos --filter 'WorkspaceDiffPatchParserTests|WorkspaceDiffTabViewModelTests'
```

Expected:
- 因 parser / diff tab view model 尚不存在而失败

**Step 3: 最小实现**

- 新增 `WorkspaceDiffModels.swift`：
  - `WorkspaceDiffOpenRequest`
  - `WorkspaceDiffSource`
  - `WorkspaceDiffViewerMode`
  - `WorkspaceDiffTabState`
  - `WorkspaceDiffDocumentState`
  - 结构化 parsed diff 模型
- 新增 `WorkspaceDiffPatchParser.swift`
- 新增 `WorkspaceDiffTabViewModel.swift`
- 让 `NativeAppViewModel` 为每个 diff tab 提供对应的 view model/runtime cache

**Step 4: 运行绿灯**

Run:

```bash
swift test --package-path macos --filter 'WorkspaceDiffPatchParserTests|WorkspaceDiffTabViewModelTests'
```

Expected:
- diff 模型、parser、view model 测试通过

**Step 5: Commit**

```bash
git add macos/Sources/DevHavenCore/Models/WorkspaceDiffModels.swift macos/Sources/DevHavenCore/Storage/WorkspaceDiffPatchParser.swift macos/Sources/DevHavenCore/ViewModels/WorkspaceDiffTabViewModel.swift macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift macos/Tests/DevHavenCoreTests/WorkspaceDiffPatchParserTests.swift macos/Tests/DevHavenCoreTests/WorkspaceDiffTabViewModelTests.swift
git commit -m "feat(diff): add diff document models and parser"
```

---

### Task 4: 落地独立 Diff 标签页 viewer（side-by-side / unified）

**Files:**
- Create: `macos/Sources/DevHavenApp/WorkspaceDiffTabView.swift`
- Create: `macos/Tests/DevHavenAppTests/WorkspaceDiffTabViewTests.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceHostView.swift`

**Step 1: 写红灯测试**

- `WorkspaceDiffTabViewTests` 锁定：
  - 顶部工具栏包含标题与 viewer mode 切换
  - 默认呈现 side-by-side viewer
  - 支持切到 unified viewer
  - loading / empty / error / binary 四态有稳定中文文案
- `WorkspaceHostViewTests` 扩展锁定：
  - 选中 diff tab 时实际挂载 `WorkspaceDiffTabView`

**Step 2: 运行红灯**

Run:

```bash
swift test --package-path macos --filter 'WorkspaceDiffTabViewTests|WorkspaceHostViewTests'
```

Expected:
- 因 diff viewer 视图尚不存在或 host 未路由而失败

**Step 3: 最小实现**

- 新增 `WorkspaceDiffTabView.swift`
- 用结构化 parsed diff 渲染：
  - side-by-side
  - unified
- 在 `WorkspaceHostView` 中为当前选中 diff tab 挂载对应 viewer

**Step 4: 运行绿灯**

Run:

```bash
swift test --package-path macos --filter 'WorkspaceDiffTabViewTests|WorkspaceHostViewTests'
```

Expected:
- viewer UI 与 host 路由测试通过

**Step 5: Commit**

```bash
git add macos/Sources/DevHavenApp/WorkspaceDiffTabView.swift macos/Sources/DevHavenApp/WorkspaceHostView.swift macos/Tests/DevHavenAppTests/WorkspaceDiffTabViewTests.swift macos/Tests/DevHavenAppTests/WorkspaceHostViewTests.swift
git commit -m "feat(app): add workspace diff tab viewer"
```

---

### Task 5: 统一接入 Git Log / Commit 的双击打开逻辑

**Files:**
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitRootView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitIdeaLogView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitIdeaLogRightSidebarView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitIdeaLogChangesView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceCommitSideToolWindowHostView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceCommitRootView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceCommitChangesBrowserView.swift`
- Modify: `macos/Tests/DevHavenAppTests/WorkspaceGitIdeaLogViewTests.swift`
- Modify: `macos/Tests/DevHavenAppTests/WorkspaceCommitRootViewTests.swift`

**Step 1: 写红灯测试**

- `WorkspaceGitIdeaLogViewTests` 锁定：
  - changes browser 文件行必须显式接入双击打开 diff 闭包/动作
  - Git Log 根视图必须把统一 `openWorkspaceDiffTab(...)` 闭包下传到 changes browser
- `WorkspaceCommitRootViewTests` 锁定：
  - Commit changes browser 文件行必须显式接入双击打开 diff 闭包/动作
  - Commit host/root 必须把统一 open diff 闭包下传到 browser

**Step 2: 运行红灯**

Run:

```bash
swift test --package-path macos --filter 'WorkspaceGitIdeaLogViewTests|WorkspaceCommitRootViewTests'
```

Expected:
- 因当前只有单击选中，没有双击 open diff 链路而失败

**Step 3: 最小实现**

- Git Log 路径：
  - 从 `WorkspaceShellView.gitToolWindowContent` / `WorkspaceGitRootView` 开始，把 `open diff` 闭包传到 `WorkspaceGitIdeaLogChangesView`
  - 文件行保留单击 selection，新增双击 open diff
- Commit 路径：
  - 从 `WorkspaceCommitSideToolWindowHostView` 开始，把 `open diff` 闭包传到 `WorkspaceCommitChangesBrowserView`
  - 文件行保留单击 selection，新增双击 open diff
- 两端都统一构造 `WorkspaceDiffOpenRequest`

**Step 4: 运行绿灯**

Run:

```bash
swift test --package-path macos --filter 'WorkspaceGitIdeaLogViewTests|WorkspaceCommitRootViewTests'
```

Expected:
- Git Log / Commit 双击打开 diff 的 source contract 测试通过

**Step 5: Commit**

```bash
git add macos/Sources/DevHavenApp/WorkspaceGitRootView.swift macos/Sources/DevHavenApp/WorkspaceGitIdeaLogView.swift macos/Sources/DevHavenApp/WorkspaceGitIdeaLogRightSidebarView.swift macos/Sources/DevHavenApp/WorkspaceGitIdeaLogChangesView.swift macos/Sources/DevHavenApp/WorkspaceCommitSideToolWindowHostView.swift macos/Sources/DevHavenApp/WorkspaceCommitRootView.swift macos/Sources/DevHavenApp/WorkspaceCommitChangesBrowserView.swift macos/Tests/DevHavenAppTests/WorkspaceGitIdeaLogViewTests.swift macos/Tests/DevHavenAppTests/WorkspaceCommitRootViewTests.swift
git commit -m "feat(diff): open workspace diff tab from git and commit browsers"
```

---

### Task 6: 更新架构文档、完整验证并回填 Review

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`

**Step 1: 同步文档**

- 在 `AGENTS.md` 中补充：
  - Workspace 顶部标签页现已区分 terminal tab 与 runtime-only diff tab
  - diff tab 不进入 restore snapshot
  - `WorkspaceHostView / WorkspaceTabBarView / NativeAppViewModel` 的职责调整

**Step 2: 运行定向验证**

Run:

```bash
swift test --package-path macos --filter 'NativeAppViewModelWorkspaceDiffTabTests|WorkspaceDiffPatchParserTests|WorkspaceDiffTabViewModelTests|WorkspaceDiffTabViewTests|WorkspaceGitIdeaLogViewTests|WorkspaceCommitRootViewTests|WorkspaceHostViewTests|WorkspaceTabBarViewTests|InitialWindowActivatorTests'
```

Expected:
- 本轮新增与修改的主链测试全部通过

**Step 3: 运行回归验证**

Run:

```bash
swift test --package-path macos --filter 'WorkspaceShellViewTests|WorkspaceShellViewGitModeTests|WorkspaceGitRootViewTests|WorkspaceCommitSideToolWindowHostViewTests|NativeAppViewModelWorkspaceEntryTests'
```

Expected:
- 不破坏现有 Workspace / Git / Commit 主链

**Step 4: 质量检查**

Run:

```bash
git diff --check
```

Expected:
- exit 0

**Step 5: 回填 Review 并 Commit**

- 在 `tasks/todo.md` 追加本轮 Review，至少包含：
  - 直接原因
  - 是否存在设计层诱因
  - 当前修复方案
  - 长期建议
  - 验证证据

```bash
git add AGENTS.md tasks/todo.md
git commit -m "docs(diff): document workspace diff tab architecture"
```

