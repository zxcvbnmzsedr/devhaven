# Workspace Diff 标签页焦点与关闭回退实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Git Log / Commit 双击打开的独立 Diff 标签页在打开时接管主焦点，并在关闭时恢复到发起打开动作前的 Git/Commit 上下文。

**Architecture:** 在 `NativeAppViewModel` 内把 runtime diff tab 从“只有 source/title 的轻量标签”升级为“带 origin context 的运行时文档标签”；`workspaceFocusedArea` 新增 diff 语义，所有打开 / 选择 / 关闭 diff tab 的动作都通过 ViewModel 统一维护焦点与回退。App 层只负责把 diff 内容区点击桥接回这套焦点真相源，不在视图层自行推断返回目标。

**Tech Stack:** SwiftUI、Observation、DevHavenCore runtime-only state、XCTest

---

### Task 1：锁定 Diff 打开/关闭焦点契约（TDD）

**Files:**
- Modify: `macos/Tests/DevHavenCoreTests/NativeAppViewModelWorkspaceDiffTabTests.swift`
- Modify: `macos/Tests/DevHavenAppTests/WorkspaceHostViewTests.swift`

- [ ] **Step 1: 写红灯测试**
  - `NativeAppViewModelWorkspaceDiffTabTests`：锁定“打开 diff -> focused area 变成 diff；关闭 diff -> 恢复 origin terminal tab + origin tool window focus”。
  - `WorkspaceHostViewTests`：锁定 diff 内容区需要把点击桥接成 `.diffTab(...)` focused area。

- [ ] **Step 2: 跑定向测试确认失败**

Run:

```bash
swift test --package-path macos --filter 'NativeAppViewModelWorkspaceDiffTabTests|WorkspaceHostViewTests'
```

Expected:
- FAIL，提示缺少 diff focused area / origin restore / host click bridge 契约。

### Task 2：实现 runtime diff origin context 与 focused area

**Files:**
- Modify: `macos/Sources/DevHavenCore/Models/WorkspaceGitModels.swift`
- Modify: `macos/Sources/DevHavenCore/Models/WorkspaceDiffModels.swift`
- Modify: `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`

- [ ] **Step 3: 扩展最小模型**
  - 给 `WorkspaceFocusedArea` 增加 diff 语义。
  - 给 runtime diff tab 增加 origin context（origin presented tab + origin focused area）。

- [ ] **Step 4: 以最小改动实现 ViewModel 焦点主链**
  - `openActiveWorkspaceDiffTab(...)` 记录 origin context。
  - `openWorkspaceDiffTab(...)` / `selectWorkspacePresentedTab(...)` 统一把焦点切到 diff。
  - `closeWorkspaceDiffTab(...)` 优先恢复 origin context；无效时再走现有 fallback。

- [ ] **Step 5: 跑定向测试转绿**

Run:

```bash
swift test --package-path macos --filter 'NativeAppViewModelWorkspaceDiffTabTests|WorkspaceHostViewTests'
```

Expected:
- PASS

### Task 3：补 App 层 diff 内容区点击桥接与回归

**Files:**
- Modify: `macos/Sources/DevHavenApp/WorkspaceHostView.swift`

- [ ] **Step 6: 给 diff 内容区补 focused area 回写**
  - diff tab 已选中时，点击 diff viewer 内容区应明确回写 `.diffTab(tabID)`。

- [ ] **Step 7: 跑回归测试**

Run:

```bash
swift test --package-path macos --filter 'NativeAppViewModelWorkspaceDiffTabTests|MainWindowCloseShortcutPlannerTests|WorkspaceHostViewTests|WorkspaceTabBarViewTests|WorkspaceDiffTabViewTests|WorkspaceGitIdeaLogViewTests|WorkspaceCommitRootViewTests'
git diff --check
```

Expected:
- 相关测试全部通过
- `git diff --check` exit 0

### Task 4：文档同步与 Review

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`

- [ ] **Step 8: 同步架构文档**
  - 写清 diff focused area、origin context、关闭回退边界。

- [ ] **Step 9: 回填 Review**
  - 记录根因、设计层诱因、当前修复方案、长期建议、验证证据。
