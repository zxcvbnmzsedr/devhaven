# 删除工作区侧栏项目卡片上的 worktree 数量徽标设计

**日期：** 2026-03-21

## 背景

当前工作区侧栏中的根项目卡片，会在右上方显示一个 worktree 数量徽标。例如 `DevHaven` 右侧的 `1`。用户已经明确表示不需要展示这个数量。

## 目标

- 删除根项目卡片上的 worktree 数量徽标。
- 保留现有 worktree 列表、hover 操作按钮、选中态和卡片布局主体。
- 不改动任何 worktree 数据结构或统计逻辑。

## 备选方案

### 方案 A：直接删除数量徽标视图（推荐）
- 修改 `macos/Sources/DevHavenApp/WorkspaceProjectListView.swift`
- 仅移除 `ProjectGroupView.projectCard` 中基于 `group.worktrees.count` 渲染的 `Text` 徽标
- 优点：改动最小、语义最直接、没有残留占位
- 风险：卡片右侧留白会略微变化，但属于预期 UI 收敛

### 方案 B：隐藏徽标但保留占位
- 保留视图结构，仅将其透明或不可见
- 优点：布局几乎不变
- 缺点：会残留无意义空间，不符合“删除”要求

## 结论

采用方案 A：直接删除数量徽标视图，并通过最小回归测试确保：
1. 项目卡片仍显示项目名；
2. 下方 worktree 条目仍显示；
3. 数量徽标不再显示。
