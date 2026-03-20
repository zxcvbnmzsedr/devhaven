# DevHaven Swift 原生 workspace 常驻挂载修复假死设计

## 目标

修复“从主列表再次进入 workspace 时应用长时间未响应”的问题。

本轮不优化 zsh 启动链，不改 Ghostty runtime，也不做 lazy attach；只修复一个更直接的根因：

> 返回主列表后，`WorkspaceShellView` 被卸载，导致所有 `GhosttySurfaceHost` 触发 `onDisappear -> releaseSurface()`；再次进入时，所有已打开项目的 pane/surface 被一口气重建，最终表现成假死。

## 当前问题

诊断日志已经表明：

- 再次进入 workspace 时，旧项目的 `surface-start / surface-finish` 会重复出现
- `openSessions` 增长后，会把所有 inactive host 一起恢复
- 单次 `surface-finish durationMs` 并不高，但全量重建多个 pane 时，仍会把应用拖进“未响应”

因此根因更像是 **root 级内容层的挂载策略错误**，而不是单个 surface 创建慢。

## 方案

采用 **A：`WorkspaceShellView` 常驻挂载，主列表 / workspace 只切换可见性与交互**。

### 具体做法

当前 `AppRootView` 的 `primaryContent` 是：

- workspace 展示时只挂 `WorkspaceShellView`
- 非 workspace 时只挂 `MainContentView`

这会在两者之间来回切换时触发卸载。

改为：

- `MainContentView` 和 `WorkspaceShellView` 都常驻在 `ZStack`
- 通过 `opacity + allowsHitTesting + accessibilityHidden` 切换前后台
- 继续保留“workspace 展示时隐藏全局 sidebar”这一行为

## 为什么先不做 lazy attach

因为从现有日志看，**最大的错误是“根本不该重建，却被重建了”**。  
先把 root 级卸载去掉，就能直接消掉最粗的一层恢复风暴。

如果修完后仍然慢，再继续做：

- active project only
- selected tab only
- visible pane only

这种更细粒度的 lazy attach。

## 影响文件

### 新增

- `macos/Sources/DevHavenApp/AppRootContentVisibilityPolicy.swift`
- `macos/Tests/DevHavenAppTests/AppRootContentVisibilityPolicyTests.swift`
- `docs/plans/2026-03-20-devhaven-swift-workspace-shell-persistence-fix-plan.md`

### 修改

- `macos/Sources/DevHavenApp/AppRootView.swift`
- `AGENTS.md`
- `tasks/todo.md`

## 验证思路

1. 先补纯策略测试，锁定：
   - 两层内容都应保持挂载
   - workspace 展示时主列表不可交互
   - 主列表展示时 workspace 不可交互
2. 跑定向测试
3. 跑 `swift test --package-path macos`
4. 跑 `swift build --package-path macos`
5. 跑 `git diff --check`

