# DevHaven 删除 worktree 闪退修复设计

## 背景
用户在删除 workspace 中的 worktree 时，DevHaven 发生 `EXC_BAD_ACCESS (SIGSEGV)`。崩溃栈命中 `GhosttySurfaceState.pwd.setter`，调用链为 `GhosttySurfaceBridge.handleAction(target:action:) -> GhosttyRuntime.handleAction(...)`。结合当前实现可确认：Ghostty 的 surface action 可能先在后台线程收到，再通过 `DispatchQueue.main.async` 跳回主线程处理；而现有代码把 `surface userdata` 直接存成 `Unmanaged.passUnretained(bridge).toOpaque()`。当 worktree 删除触发 workspace/session 关闭并释放对应 terminal surface 后，主线程上晚到的 action 仍会按旧裸指针反解出 bridge，最终命中已经失效的 `GhosttySurfaceBridge / GhosttySurfaceState`，导致野指针崩溃。

## 目标
1. 删除 worktree 时，即使 Ghostty 有晚到的 action / close / clipboard 回调，也不能再因已释放的 bridge 崩溃；
2. 修复应覆盖同一条 surface callback 链上的同类时序问题，而不只针对 `PWD` 单一 action 打补丁；
3. 保持 Ghostty runtime / surface / host 现有职责边界，不把 UI 生命周期细节重新塞回 ViewModel；
4. 通过回归测试约束“跨线程回调 + surface teardown”场景，避免未来再次回归。

## 非目标
- 不修改 `NativeGitWorktreeService.removeWorktree(...)` 的 git 删除语义；
- 不重写 `WorkspaceShellView` 的删除交互流程；
- 不在本次修复中重构整个 Ghostty runtime 回调系统为 actor；
- 不扩大为所有 runtime callback 增加持久化日志或诊断面板。

## 方案比较

### 方案 A：继续使用 bridge 裸指针，但在 bridge / runtime 上补失效标记和 grace period
- 做法：给 `GhosttySurfaceBridge` 增加 `isActive` / `invalidate()`，runtime 在 surface 注销后短暂托管 bridge 生命周期，所有 action 入口先检查失效态再 no-op。
- 优点：改动较小，可以较快止血。
- 缺点：核心问题仍是“跨线程时把非持有裸 bridge 指针带过队列跳转”；正确性依赖多个调用点都记得做失效判断，也会把 callback 生命周期策略继续塞进 bridge/runtim​​e 的补偿逻辑里。

### 方案 B：把 surface userdata 改为稳定的 callback context / handle（推荐）
- 做法：新增一个独立于 view 生命周期的 `GhosttySurfaceCallbackContext`，由 surface userdata 持有并负责安全暴露“当前是否还有可用 bridge”。Ghostty runtime 在收到后台线程回调后，不再捕获 bridge 裸指针，而是捕获 context；主线程执行时再通过 context 解析当前 bridge，若 surface 已 teardown 则直接 no-op。
- 优点：
  1. 直接修正回调生命周期模型，而不是继续补时序护栏；
  2. 同类 callback（action / close / clipboard）可以统一走同一个安全边界；
  3. 后续新增 callback 时，默认沿用 context 模式即可，技术债更低。
- 缺点：需要新增一个轻量 callback context 类型，并调整 runtime / surface 注册链路。

### 方案 C：在删除 worktree 前强制提前关闭 terminal，并依赖时序避免回调晚到
- 优点：表面上改动最少。
- 缺点：只是在删除路径上绕开症状，不能修复其它 pane/tab/workspace 关闭路径中的同类悬挂回调问题，不应采用。

## 最终设计
采用 **方案 B**。

### 1. 为 surface callback 引入稳定 context
新增 `GhosttySurfaceCallbackContext`，职责只包含：
- 持有当前可用的 `GhosttySurfaceBridge`；
- 在 teardown 开始时可被显式 `invalidate()`；
- 线程安全地提供“当前是否还有 active bridge”的查询。

这个 context 作为 C 回调的 userdata 真相源，替代现在直接暴露 bridge 裸指针的做法。

### 2. Ghostty runtime 只跨线程传递 context，不再传递 bridge 裸指针
调整 `GhosttyRuntime.handleAction(...)` / `handleCloseSurface(...)` / clipboard 回调链：
- 先从 userdata 解析出 `GhosttySurfaceCallbackContext`；
- 如果当前线程不是主线程，则把 **context 本身** 捕获进 `DispatchQueue.main.async`；
- 等主线程真正执行时，再向 context 取 active bridge；
- 若 surface 已 teardown、bridge 已失效，则安全返回，不再尝试处理 action。

这样可以消除“后台线程拿到 bridge 裸指针，主线程执行时对象已释放”的根因。

### 3. surface teardown 时先失效 context，再释放 Ghostty surface
调整 `GhosttyTerminalSurfaceView` 的生命周期管理：
- 创建 surface 前先生成 callback context；
- register surface 时把 context 一并交给 runtime/surface reference 持有，保证 Ghostty surface 存活期间 userdata 指针总有稳定宿主；
- `tearDown()` 时先 `invalidate()` callback context，再执行 `unregisterSurface` / `ghostty_surface_free(surface)`，让 teardown 开始后的晚到 callback 全部直接 no-op。

### 4. 测试策略聚焦在“异步 hop + teardown invalidation”
本次回归测试不尝试在单测里真实复现野指针崩溃，而是稳定约束以下语义：
1. callback context 在 active 状态下能提供 bridge；
2. callback context 在 `invalidate()` 后，异步 hop 到主线程时不再暴露 bridge；
3. runtime / surface 相关现有测试继续通过，确保没有破坏正常 terminal 生命周期。

## 影响范围
- `macos/Sources/DevHavenApp/Ghostty/GhosttyRuntime.swift`
- `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceView.swift`
- 新增：`macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceCallbackContext.swift`
- `macos/Tests/DevHavenAppTests/` 下新增或调整 Ghostty 回调生命周期测试
- `AGENTS.md`
- `tasks/todo.md`

## 风险与控制
### 风险 1：context 的 bridge 访问出现并发读写问题
控制：将 context 设计为线程安全访问；只允许通过受控方法读写 active bridge。

### 风险 2：surface teardown 过早 invalidation，影响正常 close 回调语义
控制：本次只让“teardown 开始后的晚到回调” no-op；正常运行中的 callback 路径不变，并通过现有 Ghostty host/bridge 测试回归确认。

### 风险 3：新增 context 后出现生命周期泄漏
控制：让 context 生命周期与 surface reference 对齐；测试覆盖 invalidate 前后的桥接可用性，不额外引入长生命周期全局缓存。

## 验证策略
1. 先为 callback context 写失败测试，验证 active/invalidate 语义与异步 hop 安全边界；
2. 实施最小修复后运行定向 Ghostty 测试；
3. 再跑 `swift test --package-path macos`，确认全量测试仍然通过；
4. 在 `tasks/todo.md` 记录直接原因、设计层诱因、修复方案、长期建议与验证证据。
