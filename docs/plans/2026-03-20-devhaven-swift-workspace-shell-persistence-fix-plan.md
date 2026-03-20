# DevHaven Swift workspace 常驻挂载修复假死实施计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让 `WorkspaceShellView` 在 root 级保持挂载，避免返回主列表后再次进入 workspace 时全量重建 Ghostty surfaces。

**Architecture:** 把 `AppRootView` 从“条件挂载 MainContent / WorkspaceShell”改成“双层常驻 + 可见性切换”。用一个很小的纯策略对象收口显示与交互规则，并通过测试锁住这条约束。

**Tech Stack:** SwiftUI、XCTest、Observation、Ghostty shared runtime

---

### Task 1: 先补失败测试锁定 root 内容层切换策略

**Files:**
- Create: `macos/Tests/DevHavenAppTests/AppRootContentVisibilityPolicyTests.swift`

**Step 1: 写失败测试**

- 断言非 workspace 状态：
  - main content 可见且可交互
  - workspace content 隐藏且不可交互
  - 两层都应保持 mounted
- 断言 workspace 状态：
  - workspace content 可见且可交互
  - main content 隐藏且不可交互
  - 两层都应保持 mounted

**Step 2: 跑测试确认先红**

```bash
swift test --package-path macos --filter AppRootContentVisibilityPolicyTests
```

### Task 2: 落 root 内容层可见性策略

**Files:**
- Create: `macos/Sources/DevHavenApp/AppRootContentVisibilityPolicy.swift`
- Modify: `macos/Sources/DevHavenApp/AppRootView.swift`

**Step 1: 新增纯策略对象**

**Step 2: 让 `AppRootView` 用 `ZStack` 常驻挂 `MainContentView` 与 `WorkspaceShellView`**

**Step 3: 用 `opacity / allowsHitTesting / accessibilityHidden` 切换前后台**

**Step 4: 跑定向测试转绿**

### Task 3: 文档与验证

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`

**Step 1: 同步文档，记录 root 级常驻挂载的新真相**

**Step 2: 跑完整验证**

```bash
swift test --package-path macos --filter AppRootContentVisibilityPolicyTests
swift test --package-path macos
swift build --package-path macos
git diff --check
```

**Step 3: 在 `tasks/todo.md` 追加 Review**

