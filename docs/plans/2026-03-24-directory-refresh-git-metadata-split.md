# 目录刷新与 Git 统计职责拆分 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让“刷新目录”只同步项目清单与目录元数据，不再执行 Git 子进程；把 Git 提交数、最后提交摘要与 gitDaily 统一迁移到“更新统计”链路。

**Architecture:** 在 `Project` 中新增轻量 `isGitRepository` 真相源，把 repo 类型判断从 `gitCommits` 中解耦。目录刷新阶段仅做路径发现、目录属性更新与轻量 Git 判定；Git 元数据刷新链路统一负责昂贵 Git 信息，并通过存储层局部更新入口写回现有 `projects.json`。

**Tech Stack:** Swift 6、SwiftUI、Foundation、XCTest、LegacyCompatStore JSON 兼容层。

---

### Task 1: Core 模型与目录刷新职责拆分

**Files:**
- Modify: `macos/Sources/DevHavenCore/Models/AppModels.swift`
- Modify: `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`
- Test: `macos/Tests/DevHavenCoreTests/LegacyCompatStoreTests.swift`

- [ ] **Step 1: 写失败测试，证明目录刷新不再重算 Git 元数据**

新增测试场景：已有 Git 项目在磁盘上产生新 commit 后，执行 `refreshProjectCatalog()` 仍保留旧 `gitCommits` / `gitLastCommitMessage`，但会把项目标记为 `isGitRepository == true`。

- [ ] **Step 2: 运行定向测试确认 RED**

Run: `swift test --package-path macos --filter 'LegacyCompatStoreTests/testRefreshProjectCatalogPreservesExistingGitMetadataForGitRepos'`
Expected: FAIL，提示 `Project` 缺少 `isGitRepository` 或 refresh 仍改写 Git 元数据。

- [ ] **Step 3: 最小实现 `Project.isGitRepository` 与目录刷新新语义**

实现点：
1. `Project` 新增 `isGitRepository`，保持向后兼容 decode default；
2. `createProject()` 只做轻量 `isGitRepository` 判定，不再调用 `loadGitInfo()`；
3. 已有项目 refresh 时保留旧 Git 元数据，新项目默认空 Git 统计值。

- [ ] **Step 4: 运行定向测试确认 GREEN**

Run: `swift test --package-path macos --filter 'LegacyCompatStoreTests/testRefreshProjectCatalogPreservesExistingGitMetadataForGitRepos'`
Expected: PASS

### Task 2: Git 统计链路升级为统一刷新 Git 元数据

**Files:**
- Modify: `macos/Sources/DevHavenCore/Models/SharedScriptModels.swift`
- Modify: `macos/Sources/DevHavenCore/Storage/GitDailyCollector.swift`
- Modify: `macos/Sources/DevHavenCore/Storage/LegacyCompatStore.swift`
- Modify: `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`
- Test: `macos/Tests/DevHavenCoreTests/LegacyCompatStoreTests.swift`

- [ ] **Step 1: 写失败测试，证明统计刷新会覆盖新 Git 元数据且目标集改为 `isGitRepository`**

新增测试场景：项目 `gitCommits == 0` 但 `isGitRepository == true` 时，执行 `refreshGitStatisticsAsync()` 后应更新 `gitCommits` / `gitLastCommitMessage` / `gitDaily`。

- [ ] **Step 2: 运行定向测试确认 RED**

Run: `swift test --package-path macos --filter 'LegacyCompatStoreTests/testRefreshGitStatisticsAsyncRefreshesGitMetadataForGitRepositoriesWithoutCommitCache'`
Expected: FAIL，提示目标集仍依赖 `gitCommits > 0` 或 store 未写回新字段。

- [ ] **Step 3: 最小实现统一 Git 元数据刷新与存储**

实现点：
1. 扩展 `GitDailyRefreshResult`（或等价模型）携带 commitCount / lastCommit / lastCommitMessage；
2. `collectGitDaily{Async}` 同步产出完整 Git 元数据；
3. `LegacyCompatStore` 新增/扩展局部更新入口，保留未知字段；
4. `refreshGitStatistics{Async}` 目标集改为 `isGitRepository`。

- [ ] **Step 4: 运行定向测试确认 GREEN**

Run: `swift test --package-path macos --filter 'LegacyCompatStoreTests/testRefreshGitStatisticsAsyncRefreshesGitMetadataForGitRepositoriesWithoutCommitCache|LegacyCompatStoreTests/testRefreshGitStatisticsPreservesUnknownProjectFields'`
Expected: PASS

### Task 3: 过滤与 UI 文案语义调整

**Files:**
- Modify: `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`
- Modify: `macos/Sources/DevHavenCore/Models/GitStatisticsModels.swift`
- Modify: `macos/Sources/DevHavenApp/MainContentView.swift`
- Modify: `macos/Sources/DevHavenApp/ProjectDetailRootView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceHostView.swift`
- Test: `macos/Tests/DevHavenCoreTests/LegacyCompatStoreTests.swift`
- Test: `macos/Tests/DevHavenAppTests/MainContentViewTests.swift`

- [ ] **Step 1: 写失败测试，证明 Git filter / UI 不再把未统计 Git 项目显示成非 Git**

新增测试场景：
1. `gitOnly` 过滤应命中 `isGitRepository == true && gitCommits == 0` 的项目；
2. `MainContentView` / 详情页源码检查应包含 “Git 项目” 的展示分支。

- [ ] **Step 2: 运行定向测试确认 RED**

Run: `swift test --package-path macos --filter 'LegacyCompatStoreTests/testGitOnlyFilterUsesIsGitRepositoryInsteadOfCommitCount|MainContentViewTests|ProjectDetailRootViewTests'`
Expected: FAIL

- [ ] **Step 3: 实现最小 UI / filter 语义调整**

实现点：
1. `matchesAllFilters()` 改用 `isGitRepository`；
2. 搜索中对 commit message 的命中加上 `isGitRepository` 保护；
3. 列表/卡片/详情/workspace header 为“Git 项目但未统计”提供文案分支。

- [ ] **Step 4: 运行定向测试确认 GREEN**

Run: `swift test --package-path macos --filter 'LegacyCompatStoreTests/testGitOnlyFilterUsesIsGitRepositoryInsteadOfCommitCount|MainContentViewTests|ProjectDetailRootViewTests'`
Expected: PASS

### Task 4: 回归验证与文档同步

**Files:**
- Modify: `AGENTS.md`（仅在实现后发现边界描述需要更新时）
- Modify: `tasks/todo.md`

- [ ] **Step 1: 运行集中回归**

Run: `swift test --package-path macos --filter 'LegacyCompatStoreTests|MainContentViewTests|ProjectDetailRootViewTests'`
Expected: PASS

- [ ] **Step 2: 运行完整回归**

Run: `swift test --package-path macos`
Expected: PASS

- [ ] **Step 3: 更新 Review 证据**

把直接原因、设计诱因、当前修复方案与验证证据追加到 `tasks/todo.md`。
