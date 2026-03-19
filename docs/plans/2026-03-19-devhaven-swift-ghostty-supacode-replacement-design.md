# DevHaven Swift Ghostty Supacode 化替换设计

> 状态：已获用户确认，进入实施

## 目标

将当前 DevHaven Swift worktree 中基于 `GhosttyBootstrap + GhosttyPathLocator + pane 级 GhosttyTerminalRuntime` 的集成方式，替换为 supacode 风格的 Ghostty 接入模型：

- App 启动时一次性初始化 Ghostty；
- 终端运行时为 app 级共享单例；
- 每个 workspace pane 只创建 `ghostty_surface_t`；
- SwiftUI 只保留薄壳包装，不再承担 runtime 生命周期与资源发现职责；
- Ghostty 资源改为稳定 bundle 资源，不再走运行时路径探测主链。

## 当前问题

当前实现的复杂度主要来自三层耦合：

1. 资源与 framework 依赖运行时探测，导致启动链必须先跑 `GhosttyPathLocator` / `GhosttyBootstrap`。
2. `GhosttySurfaceHostModel` 为每个 pane 单独创建 `GhosttyTerminalRuntime`，把 app 级逻辑降成了 pane 级逻辑。
3. Ghostty callback、surface 状态、SwiftUI 呈现主要耦合在 `GhosttySurfaceHost.swift` 与 `GhosttySurfaceView.swift`，边界不清。

## 目标结构

替换后采用以下分层：

```text
DevHavenApp
  -> GhosttyAppRuntime.bootstrapIfNeeded()
  -> 共享 GhosttyRuntime

GhosttyRuntime
  -> 持有 ghostty_app_t / ghostty_config_t
  -> 监听 focus / keyboard layout / runtime tick
  -> 注册与注销 surface
  -> 统一处理 runtime 级 callback

GhosttySurfaceView
  -> 纯 AppKit surface 宿主
  -> 键盘 / IME / 鼠标 / 选区 / quicklook
  -> 持有 GhosttySurfaceBridge

GhosttySurfaceBridge
  -> 处理 Ghostty action callback
  -> 维护 GhosttySurfaceState
  -> 通过闭包把 surface 事件回推到宿主 ViewModel

GhosttyTerminalView
  -> 薄 NSViewRepresentable 壳
```

## 关键决策

### 1. 资源采用 bundle 模式

`Vendor/GhosttyResources` 通过 SwiftPM resources 打进 `DevHavenApp` bundle，运行时直接用 `Bundle.module` 下的 `GhosttyResources/ghostty` 作为 `GHOSTTY_RESOURCES_DIR`。

这意味着：

- `GhosttyPathLocator.swift` 退出运行主链；
- `GhosttyBootstrap.swift` 退出运行主链；
- `setup-ghostty-framework.sh` 仅作为开发辅助脚本保留。

### 2. Ghostty runtime 改为 app 级共享

运行时改为共享单例，负责：

- 全局 `ghostty_init(...)` 一次；
- 共享 `ghostty_app_t`；
- 统一 config / focus / keyboard observer；
- surface 注册与统一 color scheme/config 更新。

### 3. workspace 不再对 bootstrap 做条件分支

workspace 页面不再因 bootstrap 状态切到 placeholder。主路径统一进入 `GhosttySurfaceHost`：

- runtime 正常时展示终端；
- runtime 初始化失败时由 host 内展示错误 UI。

### 4. 保留当前 DevHaven 业务约束，但收口到 bridge/state

当前 DevHaven 已有的业务约束仍要保留：

- 工作目录与控制面环境变量注入；
- title / pwd / renderer health / color change 更新；
- clipboard / open url / close surface；
- `Ctrl+D` 或 shell exit 后 pane 正确切到 exited 状态。

但这些行为不再散落在 host 与 runtime 中，而改为 `GhosttySurfaceBridge + GhosttySurfaceState` 主线。

## 风险与对策

### 风险 1：SwiftPM bundle 资源路径与当前 Vendor 路径不一致

对策：

- 新增测试锁定 `Bundle.module` 资源路径解析；
- App 启动时只接受 bundle 资源，避免双真相源。

### 风险 2：共享 runtime 改造可能破坏现有 surface smoke

对策：

- 先补 host/runtime 单例行为测试；
- 保留并重跑现有 `GhosttySurfaceHostTests`，确保输入、preedit、process exit 都继续通过。

### 风险 3：文档与 AGENTS 会与新结构漂移

对策：

- 替换完成后同步更新 `AGENTS.md`、`tasks/todo.md`、`MEMORY.md`。

## 验收标准

1. 运行时不再依赖 `GhosttyPathLocator` / `GhosttyBootstrap` 主链。
2. `DevHavenApp` 启动时一次性完成 Ghostty 全局初始化。
3. workspace 主路径直接展示内嵌 Ghostty pane，不再展示 bootstrap placeholder。
4. `GhosttySurfaceHostTests` 与新增 bundle/runtime 测试通过。
5. `swift test --package-path macos`、`swift build --package-path macos`、`git diff --check` 通过。
