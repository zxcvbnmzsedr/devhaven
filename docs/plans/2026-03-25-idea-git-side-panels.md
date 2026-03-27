# IDEA Git 左右侧区域 1:1 复刻 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让 `.log` section 补齐可展开 / 可收起的左侧 branches panel，并把右侧 changes / details / diff 联动区收紧为更接近 IDEA 的结构。

**Architecture:** 保留现有 `WorkspaceGitIdeaLogTableView` 与 `WorkspaceGitLogViewModel` 的中间主链，只在 App 层重构 `.log` 外壳。新增专用 `WorkspaceGitIdeaLogBranchesPanelView` 承接左侧 branches dashboard panel，`WorkspaceGitIdeaLogView` 改成 `control strip + optional branches panel + main content` 结构；右侧 changes/details/diff 沿用现有读取链路，只收紧面板层级与展示样式。

**Tech Stack:** SwiftUI、Observation、Swift Package、XCTest（源码契约测试）

---

### Task 1: 锁定 `.log` 左右侧新结构的红灯测试

**Files:**
- Modify: `macos/Tests/DevHavenAppTests/WorkspaceGitIdeaLogViewTests.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceGitIdeaLogViewTests.swift`

**Step 1: 写失败测试，约束左侧可收起 branches panel 与 toolbar 职责收口**

新增 / 修改断言，要求：

- `WorkspaceGitIdeaLogView.swift` 必须包含 `.log` 左侧 branches control strip 与 `WorkspaceGitIdeaLogBranchesPanelView`
- `WorkspaceGitIdeaLogBranchesPanelView.swift` 必须包含搜索框、本地 / 远端 / 标签分组、`selectRevisionFilter(...)`
- `WorkspaceGitIdeaLogToolbarView.swift` 不再包含 `branchFilterMenu`
- 右侧 details / changes / diff 视图继续独立存在，但收口到更紧凑的 pane header / metadata 结构

**Step 2: 运行测试，确认红灯**

Run:
```bash
swift test --package-path macos --filter WorkspaceGitIdeaLogViewTests
```

Expected:
- FAIL
- 失败信息指向缺少 branches panel / toolbar 仍保留旧 branch filter menu / 右侧 pane 契约未满足

**Step 3: 不写生产代码，先确认失败原因正确**

确认失败是因为目标结构尚未实现，而不是测试拼写或路径错误。

**Step 4: Commit**

```bash
git add macos/Tests/DevHavenAppTests/WorkspaceGitIdeaLogViewTests.swift
git commit -m "test: lock idea git side panels contract"
```

### Task 2: 实现左侧可展开 / 可收起 branches panel

**Files:**
- Create: `macos/Sources/DevHavenApp/WorkspaceGitIdeaLogBranchesPanelView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitIdeaLogView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitIdeaLogToolbarView.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceGitIdeaLogViewTests.swift`

**Step 1: 在 `.log` 容器中新增 branches control strip 运行时状态**

在 `WorkspaceGitIdeaLogView.swift` 中新增：

- `@State private var isBranchesPanelVisible = true`
- `@State private var branchesPanelRatio = ...`
- 一个常驻左侧的 control strip button
- 一个在展开态下包裹 `WorkspaceGitIdeaLogBranchesPanelView` 与 main content 的横向 split

**Step 2: 新建 `WorkspaceGitIdeaLogBranchesPanelView.swift`**

实现：

- header（标题、清除 revision filter、收起 panel）
- 搜索框
- local / remote / tags 的 `DisclosureGroup`
- 当前 branch / HEAD 的高亮语义
- 点击项后调用 `viewModel.selectRevisionFilter(...)`

**Step 3: 收口顶部 toolbar 职责**

在 `WorkspaceGitIdeaLogToolbarView.swift` 中删除 `branchFilterMenu` 与 `revisionTitle`，仅保留：

- search
- author filter
- date filter
- path filter
- details / diff preview toggle
- refresh

**Step 4: 运行测试，确认左侧结构转绿**

Run:
```bash
swift test --package-path macos --filter WorkspaceGitIdeaLogViewTests
```

Expected:
- 与 branches panel / toolbar 职责相关的断言转绿

**Step 5: Commit**

```bash
git add macos/Sources/DevHavenApp/WorkspaceGitIdeaLogView.swift \
        macos/Sources/DevHavenApp/WorkspaceGitIdeaLogBranchesPanelView.swift \
        macos/Sources/DevHavenApp/WorkspaceGitIdeaLogToolbarView.swift \
        macos/Tests/DevHavenAppTests/WorkspaceGitIdeaLogViewTests.swift
git commit -m "feat(git): add collapsible idea log branches panel"
```

### Task 3: 收紧右侧 changes / details / diff pane 结构

**Files:**
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitIdeaLogBottomPaneView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitIdeaLogChangesView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitIdeaLogDetailsView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitIdeaLogDiffPreviewView.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceGitIdeaLogViewTests.swift`

**Step 1: 先让测试继续约束右侧 pane header / metadata 结构**

补充断言，要求：

- changes view 使用统一 pane header 语义
- details view 包含紧凑 header、message / refs / parents / metadata 分区
- diff preview 使用面板式 header + 内容容器

**Step 2: 运行测试确认仍是红灯**

Run:
```bash
swift test --package-path macos --filter WorkspaceGitIdeaLogViewTests
```

Expected:
- FAIL，指向右侧 pane 仍是旧布局

**Step 3: 以最小改动实现新的 pane 组织**

实现目标：

- `WorkspaceGitIdeaLogChangesView`：更紧凑的 header、列表行、rename/copy 补充文案与高亮
- `WorkspaceGitIdeaLogDetailsView`：更像 commit details panel 的 message / metadata / refs / parents 分区
- `WorkspaceGitIdeaLogDiffPreviewView`：统一 header 与内容容器，保留 diff 截断提示
- 不改 `WorkspaceGitLogViewModel` 的读取 API

**Step 4: 运行测试确认转绿**

Run:
```bash
swift test --package-path macos --filter WorkspaceGitIdeaLogViewTests
```

Expected:
- PASS

**Step 5: Commit**

```bash
git add macos/Sources/DevHavenApp/WorkspaceGitIdeaLogBottomPaneView.swift \
        macos/Sources/DevHavenApp/WorkspaceGitIdeaLogChangesView.swift \
        macos/Sources/DevHavenApp/WorkspaceGitIdeaLogDetailsView.swift \
        macos/Sources/DevHavenApp/WorkspaceGitIdeaLogDiffPreviewView.swift \
        macos/Tests/DevHavenAppTests/WorkspaceGitIdeaLogViewTests.swift
git commit -m "feat(git): align idea log detail panes with idea"
```

### Task 4: 更新文档、验证并回填任务记录

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceGitIdeaLogViewTests.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceGitRootViewTests.swift`
- Test: `macos/Tests/DevHavenCoreTests/WorkspaceGitLogViewModelTests.swift`

**Step 1: 更新 AGENTS.md**

补充：

- `WorkspaceGitIdeaLogBranchesPanelView.swift` 的职责
- `.log` 左侧 branches panel 与右侧 details/diff pane 的边界
- toolbar 不再承担 branch filter 主入口

**Step 2: 更新 `tasks/todo.md`**

- 勾选本轮 checklist
- 追加 Review（结果 / 直接原因 / 设计诱因 / 当前方案 / 长期建议 / 验证证据）

**Step 3: 运行定向验证**

Run:
```bash
swift test --package-path macos --filter 'WorkspaceGitIdeaLogViewTests|WorkspaceGitRootViewTests|WorkspaceGitLogViewModelTests'
```

Expected:
- PASS

**Step 4: 运行质量检查**

Run:
```bash
git diff --check
```

Expected:
- exit 0

**Step 5: Commit**

```bash
git add AGENTS.md tasks/todo.md docs/plans/2026-03-25-idea-git-side-panels-design.md docs/plans/2026-03-25-idea-git-side-panels.md
git commit -m "docs: record idea git side panels alignment"
```
