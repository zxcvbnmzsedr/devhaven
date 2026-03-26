# Codex 展示态增量滑动窗口设计

## 背景

当前 DevHaven 为了修正 Codex `running / waiting` 的 sidebar 展示态，在 `WorkspaceShellView` 中通过固定 `1` 秒定时器调用 `CodexAgentDisplayStateRefresher.refresh(...)`。刷新逻辑会对所有 Codex 候选 pane 调 `GhosttySurfaceHostModel.currentVisibleText()`，进而触发 `GhosttyTerminalSurfaceView.debugVisibleText()` / `ghostty_surface_read_text(...)` 做整屏文本读回。

线上排查结果表明，这条链路会持续制造大量字符串与小块堆分配，长时间运行后导致 `DevHavenApp` 主进程 footprint 升到数十 GB，且主要占用类别是 `MALLOC_SMALL`。

## 目标

只为 **Codex 展示态 fallback** 提供一个轻量运行时文本窗口，替代“每秒整屏读回可见文本”的做法：

- 仅作用于 Codex 展示态判断；
- 不抽象为通用 terminal 文本缓存；
- 不写入 signal / restore / 任何持久化存储；
- 优先按内容变化驱动更新，而不是常驻整屏轮询。

## 非目标

- 不修改 Codex wrapper / notify / signal store 主链协议；
- 不把 Ghostty bridge 升级成通用终端增量日志系统；
- 不改变 workspace restore 的 pane 文本快照语义；
- 不尝试恢复 live terminal 或完整 scrollback。

## 方案对比

### 方案 A：保留轮询，只把整屏结果裁成小窗口

优点：
- 改动最小；
- 快速止血。

缺点：
- 仍需每秒整屏 `read_text`；
- 主要成本仍然存在；
- 只减少结果保留量，难以根治内存增长。

### 方案 B：内容变化驱动的小窗口缓存（推荐）

做法：
- 终端内容变化时，只更新 pane 级最近文本窗口；
- sidebar 刷新阶段只读取内存中的轻量窗口与最近活动时间；
- 不再在展示刷新链路中调用整屏 `debugVisibleText()`。

优点：
- 真正切掉定时整屏 readback 主链；
- 仍可保留 Codex marker heuristic；
- 边界清晰，只服务 Codex 展示态。

缺点：
- 需要新增运行时状态与 bridge / host 接线；
- 首版实现需要选定可控的内容变化脉冲源。

### 方案 C：只跟踪活动时间，不保留文本

优点：
- 最轻量。

缺点：
- 仅凭 activity 很难区分 waiting / running；
- 无法保留当前 marker heuristic 能力。

## 选定方案

采用 **方案 B：内容变化驱动的小窗口缓存**，首版实现保持最小闭环：

1. `GhosttyRuntime.tick()` 后向活跃 surface 发出“内容可能已变化”的轻量失效脉冲。
2. `GhosttySurfaceHostModel` 在 Codex 展示态 tracking 开启时，对该脉冲做 debounce，然后用一次受控的读回更新本 pane 的最近文本窗口。
3. `CodexAgentDisplayStateRefresher` 不再消费 `currentVisibleText()`，而是消费 `GhosttySurfaceHostModel` 暴露的轻量 snapshot。
4. `WorkspaceShellView` 仍可保留低频刷新入口，但刷新阶段只读取内存态小窗口，不能再触发整屏读回。

> 注：由于当前 Swift 层没有现成的逐字/逐块文本增量回调，首版“增量窗口”的事件源采用 `GhosttyRuntime.tick()` 后的内容失效脉冲；核心收益是把“整屏读回”从全局固定轮询改成“仅 tracking pane 的 debounce 更新”。

## 模块落点

### 1. `GhosttyRuntime`

- 新增 tick 后的 surface 内容失效广播；
- 只负责通知“这块 surface 可能变了”，不携带文本，不引入 Codex 语义。

### 2. `GhosttySurfaceBridge`

- 新增轻量内容失效回调，例如 `onContentInvalidated`；
- 只转发事件，不解释 running / waiting。

### 3. `GhosttySurfaceHostModel`

- 新增 Codex 展示态专用运行时状态：
  - 最近文本窗口；
  - 最近活动时间；
  - pending refresh task / debounce；
  - tracking 开关。
- 对 bridge 的内容失效脉冲做 debounce；
- 仅在 tracking 开启、surface 存在时做受控 readback；
- 产出 `CodexAgentDisplaySnapshot` 供上层消费。

### 4. `CodexAgentDisplayStateRefresher`

- 输入由“可见全文字符串”调整为“pane 级 snapshot”；
- 继续保留 marker + recent activity 的判断逻辑；
- 内部 observation 也收缩为围绕 snapshot 的轻量比较。

### 5. `WorkspaceShellView`

- 不再在 refresh 闭环中调用 `currentVisibleText()`；
- 在调用 refresher 前，先基于 `codexDisplayCandidates()` 给相关 model 打开 tracking；
- 刷新时只读取 `codexDisplaySnapshot()`。

## 数据流

```text
GhosttyRuntime.tick()
→ bridge.onContentInvalidated
→ GhosttySurfaceHostModel.scheduleCodexSnapshotRefreshIfNeeded()
→ debounce 后更新最近文本窗口 + lastActivityAt
→ WorkspaceShellView 调 refresher 时读取 codexDisplaySnapshot
→ heuristic 判断 running / waiting
→ ViewModel 更新 sidebar 展示 override
```

## 关键边界

1. **Codex 专用**
   - tracking 开关仅在当前 pane 属于 Codex 展示候选时开启；
   - 其它 pane 不维护这份窗口状态。

2. **只作用于运行时内存**
   - 不能进入 `projects.json` / `app_state.json` / signal store；
   - 不能影响 restore snapshot 语义。

3. **受控读回**
   - 首版允许在 debounce 后做一次 `debugVisibleText()` 读回；
   - 但绝不能在 sidebar 刷新链路或全局 1 秒轮询中直接触发整屏读回。

4. **资源回收**
   - pane tracking 关闭、surface 释放、pane 移除时，必须清空相关窗口状态并取消 pending task；
   - 避免旧 pane 的晚到任务继续抓取文本。

## 验证策略

1. 纯逻辑测试：
   - 仅保留最近窗口，不保留整串；
   - 内容变化后 recent activity 更新；
   - waiting / running 的 heuristic 在 snapshot 输入下仍成立。

2. source / wiring 测试：
   - `WorkspaceShellView` 不再通过 `currentVisibleText()` 驱动 Codex 展示刷新；
   - `GhosttyRuntime` / `GhosttySurfaceBridge` / `GhosttySurfaceHostModel` 存在内容失效接线。

3. 回归验证：
   - Codex 展示态原有测试继续通过；
   - `swift test --package-path macos --filter ...` 跑定向回归；
   - `swift build --package-path macos` 成功。
