# IDEA Git 左右侧区域视觉抛光（二轮） Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在不改底层 Git 读取链路的前提下，继续提升 `.log` 左右侧的信息密度，让 branches header、changes 路径层级与 refs badge 更接近 IDEA。

**Architecture:** 只在 App 层继续抛光 `WorkspaceGitIdeaLogBranchesPanelView`、`WorkspaceGitIdeaLogChangesView` 与 `WorkspaceGitIdeaLogDetailsView`。通过新增显示 helper、路径拆分 helper 与 refs 分类 badge helper，改善面板可读性，不扩展新的 Git 功能。

**Tech Stack:** SwiftUI、Observation、Swift Package、XCTest（源码契约测试）

---

### Task 1: 锁定二轮抛光契约的红灯测试

**Files:**
- Modify: `macos/Tests/DevHavenAppTests/WorkspaceGitIdeaLogViewTests.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceGitIdeaLogViewTests.swift`

**Step 1: 写失败测试**

补充断言，要求：
- branches panel 存在 `selectedRevisionTitle` 一类 helper，且 header 不再直接显示原始 `selectedRevisionFilter`
- branches panel 的 group header 带计数信息
- changes view 存在 `primaryFileName` / `secondaryPathSubtitle` 一类 helper
- details view 存在 `branchReferenceItems` / `tagReferenceItems` / `referenceBadge` 一类 helper

**Step 2: 运行测试确认红灯**

Run:
```bash
swift test --package-path macos --filter WorkspaceGitIdeaLogViewTests
```

Expected:
- FAIL，且失败原因直接指向上述结构尚未实现

**Step 3: Commit**

```bash
git add macos/Tests/DevHavenAppTests/WorkspaceGitIdeaLogViewTests.swift
git commit -m "test: lock second-pass idea git polish contract"
```

### Task 2: 抛光左侧 branches panel 标题与分组信息

**Files:**
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitIdeaLogBranchesPanelView.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceGitIdeaLogViewTests.swift`

**Step 1: 实现标题 helper**

新增 `selectedRevisionTitle`，把 `refs/heads|refs/remotes|refs/tags` 前缀裁掉后再显示在 header 中。

**Step 2: 实现 group count header**

把本地 / 远端 / 标签标题改成带数量的 header helper，而不是继续硬编码纯字符串。

**Step 3: 运行测试确认相关断言转绿**

Run:
```bash
swift test --package-path macos --filter WorkspaceGitIdeaLogViewTests
```

Expected:
- 与 branches panel 标题 / 分组计数相关的断言转绿

**Step 4: Commit**

```bash
git add macos/Sources/DevHavenApp/WorkspaceGitIdeaLogBranchesPanelView.swift \
        macos/Tests/DevHavenAppTests/WorkspaceGitIdeaLogViewTests.swift
git commit -m "feat(git): polish idea log branch panel copy"
```

### Task 3: 抛光 changes 路径层级与 refs badge 语义

**Files:**
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitIdeaLogChangesView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceGitIdeaLogDetailsView.swift`
- Test: `macos/Tests/DevHavenAppTests/WorkspaceGitIdeaLogViewTests.swift`

**Step 1: 重构 changes 路径展示 helper**

新增：
- `primaryFileName(for:)`
- `secondaryPathSubtitle(for:)`

让 changes 列表主文本显示文件名，次文本显示父路径与 rename/copy 来源信息。

**Step 2: 重构 refs badge helper**

新增：
- `branchReferenceItems(for:)`
- `tagReferenceItems(for:)`
- `referenceBadge(_:style:)`

把 refs 继续在 App 层解析成 branch/tag 两类，并使用不同 badge 样式。

**Step 3: 运行测试确认转绿**

Run:
```bash
swift test --package-path macos --filter WorkspaceGitIdeaLogViewTests
```

Expected:
- PASS

**Step 4: Commit**

```bash
git add macos/Sources/DevHavenApp/WorkspaceGitIdeaLogChangesView.swift \
        macos/Sources/DevHavenApp/WorkspaceGitIdeaLogDetailsView.swift \
        macos/Tests/DevHavenAppTests/WorkspaceGitIdeaLogViewTests.swift
git commit -m "feat(git): polish idea log detail semantics"
```

### Task 4: 更新文档、验证与 Review

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`
- Modify: `docs/plans/2026-03-25-idea-git-side-panels-polish-design.md`
- Modify: `docs/plans/2026-03-25-idea-git-side-panels-polish.md`

**Step 1: 更新 AGENTS.md**

补充 `.log` 左侧标题 / 右侧 refs badge / changes 路径层级的职责说明。

**Step 2: 更新 tasks/todo.md**

勾选任务并追加本轮 Review。

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
