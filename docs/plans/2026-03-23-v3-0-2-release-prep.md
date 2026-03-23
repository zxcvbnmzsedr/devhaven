# v3.0.2 Release Prep Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在保持现有行为不变的前提下，整理当前侧边栏目录行代码，并把仓库版本升级到 v3.0.2，随后完成提交、打 tag 与 push。

**Architecture:** 仅做最小范围调整：一是收口 `ProjectSidebarView` 最近的目录行渲染整理，保持 UI 行为与已有测试语义不变；二是更新 `AppMetadata` 与 README 中的版本真相源，让构建脚本、发布脚本与仓库展示统一指向 3.0.2。最后通过 `swift test --package-path macos` 验证，并将 tag `v3.0.2` 落到版本升级提交上。

**Tech Stack:** SwiftUI、AppKit、Swift Package、shell 发布脚本、Git

---

### Task 1: 记录与收口改动范围

**Files:**
- Modify: `tasks/todo.md`
- Create: `docs/plans/2026-03-23-v3-0-2-release-prep.md`

**Step 1:** 记录本次任务 checklist，明确“代码整理 / 版本升级 / 验证 / 提交 / tag / push”顺序。

**Step 2:** 标记只提交与本次任务相关的文件，不混入 `.claude/` 与 `.playwright-mcp/` 等本地环境改动。

### Task 2: 整理最近变更的侧边栏目录行代码

**Files:**
- Modify: `macos/Sources/DevHavenApp/ProjectSidebarView.swift`
- Test: `macos/Tests/DevHavenAppTests/ProjectSidebarViewTests.swift`

**Step 1:** 检查当前目录行抽取是否保持整行点击、hover 删除按钮与移除目录动作不变。

**Step 2:** 只做最小整理，避免扩大到无关 UI 区域。

**Step 3:** 如测试断言依赖源码结构且需同步，按最小范围更新测试。

### Task 3: 升级到 v3.0.2

**Files:**
- Modify: `macos/Resources/AppMetadata.json`
- Modify: `README.md`

**Step 1:** 将版本从 `3.0.1` 升级到 `3.0.2`。

**Step 2:** 将 build number 从 `3001000` 升级到 `3002000`，保持单调递增。

**Step 3:** 更新 README 首页版本徽章，保持仓库展示与打包真相源一致。

### Task 4: 验证并记录 Review

**Files:**
- Modify: `tasks/todo.md`

**Step 1:** 运行 `swift test --package-path macos` 获取完整验证证据。

**Step 2:** 在 `tasks/todo.md` 追加 Review，记录直接原因、设计层诱因、当前修复/整理方案与验证输出。

### Task 5: 提交、打 tag、push

**Files:**
- Git only

**Step 1:** 仅暂存本次相关文件并提交。

**Step 2:** 创建 `v3.0.2` tag 并校验其指向当前 release 提交。

**Step 3:** 推送 `main` 与 `v3.0.2` 到 `origin`。
