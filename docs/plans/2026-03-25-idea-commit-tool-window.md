# IDEA Commit Tool Window Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在 DevHaven Workspace 中新增独立 Commit Tool Window，完成 Changes Browser + Inclusion + Diff Preview + Commit Panel + Commit/Git 工具窗职责拆分的首轮完整实现。

**Architecture:** 以独立 `Commit` tool window 取代当前 `Git > Changes` 结构；Commit 工作流在 Core 层新增独立 Models / ViewModel / Service，App 层新增独立 Commit 根视图与分区布局。Git 工具窗移除 `.changes` section，Workspace stripe 改为 `Commit / Git` 双入口，提交主链围绕 inclusion model 组织。

**Tech Stack:** SwiftUI、Observation、DevHavenCore、Native Git CLI service、XCTest

---

### Task 1: 锁定 Workspace 工具窗拓扑与 Git/Commit 边界

**Files:**
- Modify: `tasks/todo.md`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceChromeContainerViewTests.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceGitRootViewTests.swift`
- Test: `macos/Tests/DevHavenCoreTests/WorkspaceGitViewModelTests.swift`
- Modify: `macos/Sources/DevHavenCore/Models/WorkspaceGitModels.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitRootView.swift`

**Step 1: 写红灯测试**

- 新增/修改测试，锁定：
  - `WorkspaceToolWindowKind` 包含 `.commit`
  - `WorkspaceGitSection` 不再包含 `.changes`
  - `WorkspaceGitRootView` 不再引用 `WorkspaceGitChangesView`
  - stripe/host 结构允许 Commit 与 Git 并列

**Step 2: 运行红灯**

Run:

```bash
swift test --package-path macos --filter 'WorkspaceChromeContainerViewTests|WorkspaceGitRootViewTests|WorkspaceGitViewModelTests'
```

Expected:
- 断言失败，指出当前仍只有 `.git` 或 Git root 仍承载 changes

**Step 3: 最小实现**

- 在 `WorkspaceGitModels.swift` 中引入 `.commit`
- 从 `WorkspaceGitSection` 删除 `.changes`
- 调整 `WorkspaceGitRootView` 顶层 tab / section 路由，确保 Git 仅保留 `log / console / branches / operations`

**Step 4: 运行绿灯**

Run:

```bash
swift test --package-path macos --filter 'WorkspaceChromeContainerViewTests|WorkspaceGitRootViewTests|WorkspaceGitViewModelTests'
```

Expected:
- 相关测试通过

**Step 5: Commit**

```bash
git add tasks/todo.md macos/Sources/DevHavenCore/Models/WorkspaceGitModels.swift macos/Sources/DevHavenApp/WorkspaceGitRootView.swift macos/Tests/DevHavenAppTests/WorkspaceChromeContainerViewTests.swift macos/Tests/DevHavenAppTests/WorkspaceGitRootViewTests.swift macos/Tests/DevHavenCoreTests/WorkspaceGitViewModelTests.swift
git commit -m "refactor(workspace): split commit tool window from git"
```

---

### Task 2: 建立 Commit 域的 Core 模型与 ViewModel 外壳

**Files:**
- Create: `macos/Sources/DevHavenCore/Models/WorkspaceCommitModels.swift`
- Create: `macos/Sources/DevHavenCore/ViewModels/WorkspaceCommitViewModel.swift`
- Test: `macos/Tests/DevHavenCoreTests/WorkspaceCommitViewModelTests.swift`
- Modify: `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`

**Step 1: 写红灯测试**

- 为 `WorkspaceCommitViewModel` 新建测试，锁定：
  - 能加载 local changes snapshot
  - 能维护 inclusion state
  - 能同步 selected change / diff preview
  - 能维护 commit draft / options / execution state

**Step 2: 运行红灯**

Run:

```bash
swift test --package-path macos --filter 'WorkspaceCommitViewModelTests'
```

Expected:
- 编译失败或测试失败，因为 Commit 模型/ViewModel 尚不存在

**Step 3: 最小实现**

- 新建 `WorkspaceCommitModels.swift`：
  - repository context
  - changes snapshot
  - change node / status
  - inclusion state
  - draft / options / execution / diff preview state
- 新建 `WorkspaceCommitViewModel.swift`
- 在 `NativeAppViewModel` 中增加 Commit tool window 对应的 runtime 挂载点

**Step 4: 运行绿灯**

Run:

```bash
swift test --package-path macos --filter 'WorkspaceCommitViewModelTests'
```

Expected:
- 新测试通过

**Step 5: Commit**

```bash
git add macos/Sources/DevHavenCore/Models/WorkspaceCommitModels.swift macos/Sources/DevHavenCore/ViewModels/WorkspaceCommitViewModel.swift macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift macos/Tests/DevHavenCoreTests/WorkspaceCommitViewModelTests.swift
git commit -m "feat(commit): add commit workflow core models"
```

---

### Task 3: 把提交执行链路从 Git Changes 页抽到独立 Commit Service

**Files:**
- Create: `macos/Sources/DevHavenCore/Storage/NativeGitCommitWorkflowService.swift`
- Modify: `macos/Sources/DevHavenCore/Storage/NativeGitRepositoryService.swift`
- Modify: `macos/Sources/DevHavenCore/Storage/NativeGitParsers.swift`
- Test: `macos/Tests/DevHavenCoreTests/NativeGitCommitWorkflowServiceTests.swift`

**Step 1: 写红灯测试**

- 锁定以下契约：
  - 加载 local changes snapshot 时可产生 inclusion-friendly 结构
  - commit / amend / commit-and-push 走统一 workflow service
  - 无 included changes、空消息、hook/push 失败时能返回结构化错误

**Step 2: 运行红灯**

Run:

```bash
swift test --package-path macos --filter 'NativeGitCommitWorkflowServiceTests'
```

Expected:
- 因 service 不存在而失败

**Step 3: 最小实现**

- 新增独立 commit workflow service
- 复用底层 repository service/git runner，但不把 UI 直接绑到 stage/unstage API
- 建立 inclusion 到执行链路的桥接

**Step 4: 运行绿灯**

Run:

```bash
swift test --package-path macos --filter 'NativeGitCommitWorkflowServiceTests'
```

Expected:
- workflow service 测试通过

**Step 5: Commit**

```bash
git add macos/Sources/DevHavenCore/Storage/NativeGitCommitWorkflowService.swift macos/Sources/DevHavenCore/Storage/NativeGitRepositoryService.swift macos/Sources/DevHavenCore/Storage/NativeGitParsers.swift macos/Tests/DevHavenCoreTests/NativeGitCommitWorkflowServiceTests.swift
git commit -m "feat(commit): add native commit workflow service"
```

---

### Task 4: 新增 Commit Tool Window App 根视图并接入 Workspace host

**Files:**
- Create: `macos/Sources/DevHavenApp/WorkspaceCommitRootView.swift`
- Create: `macos/Sources/DevHavenApp/WorkspaceCommitChangesBrowserView.swift`
- Create: `macos/Sources/DevHavenApp/WorkspaceCommitDiffPreviewView.swift`
- Create: `macos/Sources/DevHavenApp/WorkspaceCommitPanelView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceShellView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceChromeContainerView.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceCommitRootViewTests.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceShellViewTests.swift`

**Step 1: 写红灯测试**

- 锁定：
  - stripe 有 Commit / Git 两个入口
  - bottom tool window host 能路由到 `WorkspaceCommitRootView`
  - Commit root 包含 changes browser + diff preview + commit panel 三分区

**Step 2: 运行红灯**

Run:

```bash
swift test --package-path macos --filter 'WorkspaceCommitRootViewTests|WorkspaceShellViewTests|WorkspaceChromeContainerViewTests'
```

Expected:
- 因新视图不存在或 host 未接入而失败

**Step 3: 最小实现**

- 新增 Commit App 侧根视图与三个子视图
- `WorkspaceShellView` 根据 `WorkspaceToolWindowKind.commit` 路由
- `WorkspaceChromeContainerView` stripe 补齐 Commit 图标入口

**Step 4: 运行绿灯**

Run:

```bash
swift test --package-path macos --filter 'WorkspaceCommitRootViewTests|WorkspaceShellViewTests|WorkspaceChromeContainerViewTests'
```

Expected:
- App 侧结构测试通过

**Step 5: Commit**

```bash
git add macos/Sources/DevHavenApp/WorkspaceCommitRootView.swift macos/Sources/DevHavenApp/WorkspaceCommitChangesBrowserView.swift macos/Sources/DevHavenApp/WorkspaceCommitDiffPreviewView.swift macos/Sources/DevHavenApp/WorkspaceCommitPanelView.swift macos/Sources/DevHavenApp/WorkspaceShellView.swift macos/Sources/DevHavenApp/WorkspaceChromeContainerView.swift macos/Tests/DevHavenAppTests/WorkspaceCommitRootViewTests.swift macos/Tests/DevHavenAppTests/WorkspaceShellViewTests.swift
git commit -m "feat(app): add commit tool window root views"
```

---

### Task 5: 落地 Changes Browser + Inclusion + Diff Preview 主链

**Files:**
- Modify: `macos/Sources/DevHavenApp/WorkspaceCommitChangesBrowserView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceCommitDiffPreviewView.swift`
- Modify: `macos/Sources/DevHavenCore/ViewModels/WorkspaceCommitViewModel.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceCommitRootViewTests.swift`
- Test: `macos/Tests/DevHavenCoreTests/WorkspaceCommitViewModelTests.swift`

**Step 1: 写红灯测试**

- 锁定：
  - inclusion checkbox 对文件/目录生效
  - selected change 会驱动 diff preview
  - 大 diff / binary / empty selection 有稳定占位态

**Step 2: 运行红灯**

Run:

```bash
swift test --package-path macos --filter 'WorkspaceCommitRootViewTests|WorkspaceCommitViewModelTests'
```

Expected:
- 因浏览器与 preview 逻辑不完整而失败

**Step 3: 最小实现**

- 补齐 tree 结构渲染
- 补齐 inclusion toggle / select / diff load
- 为 preview 增加 loading / empty / truncated 状态

**Step 4: 运行绿灯**

Run:

```bash
swift test --package-path macos --filter 'WorkspaceCommitRootViewTests|WorkspaceCommitViewModelTests'
```

Expected:
- 相关交互测试通过

**Step 5: Commit**

```bash
git add macos/Sources/DevHavenApp/WorkspaceCommitChangesBrowserView.swift macos/Sources/DevHavenApp/WorkspaceCommitDiffPreviewView.swift macos/Sources/DevHavenCore/ViewModels/WorkspaceCommitViewModel.swift macos/Tests/DevHavenAppTests/WorkspaceCommitRootViewTests.swift macos/Tests/DevHavenCoreTests/WorkspaceCommitViewModelTests.swift
git commit -m "feat(commit): add inclusion browser and diff preview"
```

---

### Task 6: 落地 Commit Panel、Commit Options 与执行反馈

**Files:**
- Modify: `macos/Sources/DevHavenApp/WorkspaceCommitPanelView.swift`
- Modify: `macos/Sources/DevHavenCore/ViewModels/WorkspaceCommitViewModel.swift`
- Modify: `macos/Sources/DevHavenCore/Models/WorkspaceCommitModels.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceCommitRootViewTests.swift`
- Test: `macos/Tests/DevHavenCoreTests/WorkspaceCommitViewModelTests.swift`
- Test: `macos/Tests/DevHavenCoreTests/NativeGitCommitWorkflowServiceTests.swift`

**Step 1: 写红灯测试**

- 锁定：
  - commit legend/status
  - message editor
  - amend / author / sign-off / commit-and-push
  - progress / error / success surface

**Step 2: 运行红灯**

Run:

```bash
swift test --package-path macos --filter 'WorkspaceCommitRootViewTests|WorkspaceCommitViewModelTests|NativeGitCommitWorkflowServiceTests'
```

Expected:
- 因 panel/option/execution state 不完整而失败

**Step 3: 最小实现**

- 增强 panel 状态区
- 增加 executor 选择和 options UI
- 打通 commit / amend / commit-and-push -> progress -> result

**Step 4: 运行绿灯**

Run:

```bash
swift test --package-path macos --filter 'WorkspaceCommitRootViewTests|WorkspaceCommitViewModelTests|NativeGitCommitWorkflowServiceTests'
```

Expected:
- 相关能力全部通过

**Step 5: Commit**

```bash
git add macos/Sources/DevHavenApp/WorkspaceCommitPanelView.swift macos/Sources/DevHavenCore/ViewModels/WorkspaceCommitViewModel.swift macos/Sources/DevHavenCore/Models/WorkspaceCommitModels.swift macos/Tests/DevHavenAppTests/WorkspaceCommitRootViewTests.swift macos/Tests/DevHavenCoreTests/WorkspaceCommitViewModelTests.swift macos/Tests/DevHavenCoreTests/NativeGitCommitWorkflowServiceTests.swift
git commit -m "feat(commit): add commit panel and execution flow"
```

---

### Task 7: 更新 Git 工具窗、文档与架构说明，并做全链路验证

**Files:**
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitRootView.swift`
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceGitRootViewTests.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceCommitRootViewTests.swift`
- Test: `macos/Tests/DevHavenCoreTests/WorkspaceCommitViewModelTests.swift`
- Test: `macos/Tests/DevHavenCoreTests/NativeGitCommitWorkflowServiceTests.swift`

**Step 1: 写/补红灯测试**

- 锁定：
  - Git 工具窗不再承载 changes
  - AGENTS 描述已同步为 Commit/Git 双工具窗架构
  - todo/review 有完整验证记录

**Step 2: 运行红灯**

Run:

```bash
swift test --package-path macos --filter 'WorkspaceGitRootViewTests|WorkspaceCommitRootViewTests|WorkspaceCommitViewModelTests|NativeGitCommitWorkflowServiceTests'
```

Expected:
- 任何遗漏的结构性问题暴露出来

**Step 3: 最小实现**

- 补齐 Git root 精简
- 更新 `AGENTS.md`
- 更新 `tasks/todo.md` 完成状态与 Review

**Step 4: 全量验证**

Run:

```bash
swift test --package-path macos --filter 'WorkspaceGitRootViewTests|WorkspaceCommitRootViewTests|WorkspaceShellViewTests|WorkspaceChromeContainerViewTests|WorkspaceCommitViewModelTests|WorkspaceGitViewModelTests|NativeGitCommitWorkflowServiceTests|NativeGitRepositoryServiceTests'
git diff --check
```

Expected:
- 定向测试通过
- `git diff --check` 为 0

**Step 5: Commit**

```bash
git add AGENTS.md tasks/todo.md macos/Sources/DevHavenApp/WorkspaceGitRootView.swift macos/Tests/DevHavenAppTests/WorkspaceGitRootViewTests.swift macos/Tests/DevHavenAppTests/WorkspaceCommitRootViewTests.swift macos/Tests/DevHavenCoreTests/WorkspaceCommitViewModelTests.swift macos/Tests/DevHavenCoreTests/NativeGitCommitWorkflowServiceTests.swift
git commit -m "docs(workspace): document commit tool window architecture"
```

---

Plan complete and saved to `docs/plans/2026-03-25-idea-commit-tool-window.md`。  
按用户当前指令，执行方式固定为：**Subagent-Driven（当前会话）**。
