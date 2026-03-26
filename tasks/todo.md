# Todo



## 2026-03-26 提交并推送 Codex 展示态窗口缓存改动

- [x] 审阅当前工作区变更，确认提交范围覆盖代码 / 文档 / 任务记录
- [x] 运行 fresh 验证命令，确认当前改动可安全提交
- [x] 生成提交摘要并执行 git commit
- [x] 推送当前分支到远端
- [x] 在本文件追加 Review，记录提交结果与验证证据


## Review（2026-03-26 提交并推送 Codex 展示态窗口缓存改动）

- 结果：
  1. 已将 Codex 展示态窗口缓存相关代码、测试、设计文档与任务记录提交为 `a15e75e`（`Use cached Codex display snapshots`）。
  2. 已将当前 `main` 推送到 `origin/main`，远端从 `e74db62` 前进到 `a15e75e`。
- 验证证据：
  - `git diff --check` → 无输出。
  - `swift build --package-path macos` → `Build complete!`。
  - `swift test --package-path macos` → 最近一次全量重跑为 `347 tests, 5 skipped, 0 failures`。
  - `swift test --package-path macos --filter WorkspaceRunManagerTests/testStartSupportsMultilineCommandsWithAssignmentsBeforeInnerExec` → 单测重跑通过；用于核对首次全量测试里该用例的一次性断言失败是否可复现。
  - `git push origin main` → `e74db62..a15e75e  main -> main`。

## 2026-03-26 Codex 展示态增量滑动窗口设计

- [x] 探查当前 Codex 展示态刷新链路、Ghostty bridge 回调能力与相关模块边界
- [x] 与用户确认设计目标边界：只服务 Codex 展示态，不抽象成通用 terminal 文本缓存
- [x] 给出 2~3 种可选方案、权衡取舍并推荐“增量滑动窗口”方向
- [x] 分段确认设计细节（模块落点、数据流、容错与验证）
- [x] 设计确认后，写入 `docs/plans/` 设计文档并登记后续实施计划

## 2026-03-26 Codex 展示态增量滑动窗口实现

- [x] 先补 failing tests，锁定 snapshot 输入、HostModel 窗口缓存与 WorkspaceShellView 新接线
- [x] 以最小改动实现 runtime/bridge/host 的内容失效脉冲与 Codex 小窗口缓存
- [x] 用 snapshot provider 替换 WorkspaceShellView 的 currentVisibleText 读取，并收口 tracking 开关
- [x] 更新 AGENTS.md 与本文件 Review，记录新边界、直接原因、设计诱因与验证证据
- [x] 运行定向测试与构建验证，确认修复闭环

## Review（2026-03-26 Codex 展示态增量滑动窗口实现）

- 结果：
  1. Codex 展示态 fallback 已从“WorkspaceShellView 定时读 `currentVisibleText()`”改为“Ghostty host 维护 pane 级 `CodexAgentDisplaySnapshot` 最近文本窗口 + 最近活动时间”。
  2. `WorkspaceShellView` 现在仍可保留轻量刷新入口，但刷新阶段只读取内存中的 cached snapshot；Codex 展示态闭环不再直接触发整屏 `ghostty_surface_read_text(...)`。
  3. `GhosttyRuntime.tick()` 之后会向活跃 surface 广播内容失效脉冲，`GhosttySurfaceHostModel` 仅在 Codex tracking 开启时 debounce 更新最近文本窗口；pane 移除/退出/关闭 tracking 时会取消 pending task 并清空缓存。
- 直接原因：
  1. 旧实现把 `GhosttySurfaceHostModel.currentVisibleText()` 接到了 `WorkspaceShellView.refreshCodexDisplayStates()` 的固定定时刷新链路上。
  2. 这会让 sidebar 展示态修正在后台长期触发 `debugVisibleText()` / `ghostty_surface_read_text(...)` 与多轮字符串处理，长时间运行后持续制造 `MALLOC_SMALL` 压力。
- 设计层诱因：
  1. Codex 展示态 fallback 原本只是 UI 修正语义，但实现上跨层依赖了终端全文 readback，把昂贵调试式读取放进了常驻刷新路径。
  2. 这属于“展示态纠偏依赖重型数据源”的职责错配：UI 只想知道 running / waiting，却每次都反向拉 pane 全文。
- 当前修复方案：
  1. 新增 `CodexAgentDisplaySnapshot`，只保留 pane 级最近文本窗口与最近活动时间。
  2. `GhosttyRuntime` / `GhosttySurfaceBridge` / `GhosttySurfaceHostModel` 新增内容失效脉冲与 host 侧 debounce 缓存更新；`WorkspaceShellView` 改读 `codexDisplaySnapshot()`，并按当前 `codexDisplayCandidates()` 同步 tracking 开关。
  3. `CodexAgentDisplayStateRefresher` 现改为消费 snapshot，而不是直接消费全文字符串。
- 长期改进建议：
  1. 后续若 Ghostty Swift 层能拿到更细的文本增量/活动回调，应继续把 host 侧 debounce readback 收缩成真正的增量窗口更新，进一步减少 readback 次数。
  2. 如果 signal / notify 主链继续增强，可继续减少甚至删除文本 heuristic fallback，让最近文本窗口只保留为最后兜底手段。
- 验证证据：
  - 红灯：`swift test --package-path macos --filter 'CodexAgentDisplayStateRefresherTests|GhosttySurfaceHostModelSnapshotTests|WorkspaceShellViewTests'` → 失败，缺少 `CodexAgentDisplaySnapshot` 与 host tracking 接口。
  - 绿灯：`swift test --package-path macos --filter 'CodexAgentDisplayStateRefresherTests|GhosttySurfaceHostModelSnapshotTests|WorkspaceShellViewTests'` → 15 tests，0 failures。
  - 定向回归：`swift test --package-path macos --filter 'CodexAgentDisplayStateRefresherTests|GhosttySurfaceHostModelSnapshotTests|WorkspaceShellViewTests|WorkspaceAgentStatusAccessoryTests|NativeAppViewModelWorkspaceEntryTests'` → 51 tests，0 failures。
  - 构建验证：`swift build --package-path macos` → Build complete。
  - 差异校验：`git diff --check` → 无输出。


## 2026-03-26 DevHaven.app 异常内存占用排查

- [x] 记录当前运行中的 DevHaven 进程与内存异常现象，建立排查证据基线
- [x] 收集 footprint / heap / sample 等运行时证据，确认主要占用类别与热点线程
- [x] 对照仓库代码定位直接原因，并判断是否存在设计层诱因
- [x] 在本文件追加 Review，记录结论、证据、长期建议与必要后续动作

## Review（2026-03-26 DevHaven.app 异常内存占用排查）

- 结果：
  1. 当前 `/Applications/DevHaven.app` 主进程 `DevHavenApp`（PID `27999`）已运行约 `14:49:21`，`top` / `footprint` 一致显示内存 footprint 约 `32.8 GB`，属于明显异常。
  2. `footprint 27999` 显示主要占用为 `MALLOC_SMALL 31 GB`，其次是 `IOSurface 857 MB`、`IOAccelerator 536 MB`；这更像是**大量小块堆分配长期累积**，而不是单个巨型缓冲区。
  3. 运行时采样 `sample 27999 5 1` 命中一条非常明确的 App 侧周期路径：`WorkspaceShellView.refreshCodexDisplayStates()` → `CodexAgentDisplayStateRefresher.presentationOverrides(...)` → `GhosttySurfaceHostModel.currentVisibleText()` → `GhosttyTerminalSurfaceView.debugVisibleText()` → `terminal.formatter.PageFormatter.formatWithState`。
  4. 结合当前进程下存在 `6` 条 DevHaven 内嵌 Codex wrapper 会话，以及 `WorkspaceShellView` 中固定 `1` 秒一次的 `codexDisplayRefreshTimer`，可以高置信度判断：**内存压力主要来自“为了修正 Codex running/waiting 展示态而对多个 pane 周期性轮询终端可见文本”这条链路。**
- 直接原因：
  1. `WorkspaceShellView` 从 2026-03-22 的 Agent 状态感知特性开始，引入了 `Timer.publish(every: 1, on: .main, in: .common)`，每秒都会触发 `refreshCodexDisplayStates()`。
  2. 这个刷新逻辑会对所有 `codexDisplayCandidates()` 调用 `currentVisibleText()`；后者不是轻量状态查询，而是通过 `GhosttyTerminalSurfaceView.debugVisibleText()` 走 `ghostty_surface_read_text(...)`，把终端当前可见文本重新格式化并桥接成新的 Swift `String`。
  3. 之后同一批文本又会在 `currentVisibleText()`、`normalizedVisibleText()`、`CodexAgentDisplayHeuristics.displayState(for:)` 中多次 `trimmingCharacters(...)`、`String.contains(...)`、整串比较，并被 `Observation.lastVisibleText` 再保存一份；这会持续制造大量短生命周期小对象/字符串分配。
  4. `sample` 已直接证明当前在线进程确实在走这条路径，而 `footprint` 的 `MALLOC_SMALL 31 GB` 也与“高频小对象 / 字符串分配累积”高度一致。
- 设计层诱因：
  1. **展示态修正逻辑跨层依赖了终端 UI 文本读回。** 按 AGENTS 约束，Codex 主链本应以 `wrapper signal + official notify` 为主，终端可见文本只作 fallback；但当前 fallback 的实现方式是全量文本轮询，成本过高。
  2. `debugVisibleText()` 从命名和实现上都更像调试/诊断接口，却被接入了常驻 1 秒轮询的生产路径；这把本应偶发的“整屏文本序列化”变成了长期后台任务。
  3. 刷新范围也偏大：`codexDisplayCandidates()` 面向所有打开项目里的 Codex pane，而不只是当前可见/当前聚焦 pane，所以隐藏 pane 也会持续参与文本读回。
  4. 因此，存在明显系统设计诱因：**为了修正 sidebar 展示语义，把昂贵的 terminal 可见文本读取放进了全局定时器。**
- 当前处置建议：
  1. 临时止血：先关闭不需要的 Codex pane / 项目，或重启 DevHaven 释放已经累积的内存；只要没有活跃的 Codex 展示态候选，这条 1 秒轮询链路的压力就会显著下降。
  2. 真正修复时，优先收口为“只有 signal 不足以判定时才做最小范围 fallback”，并尽量只看当前活动 pane，而不是所有已加载 pane。
  3. 如果仍需要 fallback，建议改成**更便宜的最小信息提取**（例如有限前缀/末行/增量活动标记），不要每秒做整屏文本 readback + 多次全串 trim/contains。
- 长期改进建议：
  1. 优先把 Codex waiting/running 的判断继续收敛到 signal / notify 主链，避免把终端内容分析当作长期真相源。
  2. 若必须保留 heuristic fallback，应增加硬边界：仅活动 pane、仅短时间窗口、仅必要状态、仅一次字符串归一化，避免重复复制同一份大文本。
  3. 给这条展示态刷新链路补性能 / 内存回归测试或至少 profiling 基线，防止类似“UI 语义修正引入后台轮询”再次悄悄进主线。
- 验证证据：
  - `top -l 1 -pid 27999 -stats pid,command,mem,cpu,time,threads` → `DevHavenApp 32G~33G`。
  - `footprint 27999` → `Footprint: 32 GB`，其中 `MALLOC_SMALL 31 GB`。
  - `sample 27999 5 1 -mayDie` → 主线程周期性命中 `WorkspaceShellView.refreshCodexDisplayStates()`、`CodexAgentDisplayStateRefresher.presentationOverrides(...)`、`GhosttySurfaceHostModel.currentVisibleText()`、`GhosttyTerminalSurfaceView.debugVisibleText()`、`terminal.formatter.PageFormatter.formatWithState`。
  - `ps -axo pid,args | grep '/Applications/DevHaven.app/.../AgentResources/bin/codex'` → 当前共有 `6` 条 DevHaven 内嵌 Codex wrapper 会话，与该轮询路径的候选 pane 数量级相符。


## 2026-03-25 Workspace 焦点恢复触发 SwiftUI 崩溃排查

- [x] 基于崩溃栈与相关源码定位直接原因，确认是否存在设计层诱因
- [x] 先补失败测试，覆盖“恢复 terminal responder 不应在当前 SwiftUI 更新栈内同步抢焦点”
- [x] 实施最小修复，并保持 focused pane 仍能在下一轮主线程安全取回 responder
- [x] 运行定向验证并在本文件追加 Review（直接原因、设计层诱因、修复方案、长期建议、证据）

## Review（2026-03-25 Workspace 焦点恢复触发 SwiftUI 崩溃排查）

- 结果：
  1. 已定位并修复这次 3.1.0 的意外退出：`WorkspaceHostView.surfaceModel(for:)` 在 SwiftUI `body` 更新栈里同步调用 `GhosttySurfaceHostModel.restoreWindowResponderIfNeeded()`，进而立刻 `window.makeFirstResponder(ownedSurfaceView)`。
  2. 当此时 AppKit 正在结束一个 `NSTextField` / 输入法会话（你的崩溃栈里是搜狗输入法 deactive 链路）时，这个同步抢 responder 会把 `NSTextInputContext deactivate -> textDidEndEditing -> SwiftUI transaction update` 重新嵌套回当前 AttributeGraph 更新，最终触发 `AG::precondition_failure` 并 `SIGABRT`。
  3. 现在 responder 恢复改为 **延后一拍的主线程任务**：只在确实需要时调度一次，离开当前 SwiftUI/AppKit 更新栈后再执行真正的 `makeFirstResponder`；若 pane 已失焦、surface 释放或恢复已在路上，会自动取消/跳过。
- 直接原因：
  1. 崩溃栈主线程清楚显示：`WorkspaceHostView.surfaceModel(for:) -> GhosttySurfaceHostModel.restoreWindowResponderIfNeeded() -> NSWindow._realMakeFirstResponder -> NSTextView resignFirstResponder -> NSTextField textDidEndEditing -> SwiftUI/AttributeGraph abort`。
  2. 也就是说，触发崩溃的不是 Ghostty renderer 本身，而是 **在 SwiftUI 视图计算期间同步修改 AppKit firstResponder**。
- 设计层诱因：
  1. `surfaceModel(for:)` 名义上是“拿 pane 对应 model”的纯查询入口，但实际上夹带了 responder 修复这种命令式副作用；这让 View builder 期间混入了窗口焦点变更。
  2. `restoreWindowResponderIfNeeded()` 之前默认同步执行 `makeFirstResponder`，没有区分“当前正在 SwiftUI/AppKit 更新栈内”与“安全的下一轮主线程时机”。
  3. 这是典型的 **pure model lookup 与 imperative UI side effect 职责混杂**。未发现更大的系统设计缺陷，但这一处职责边界此前不够清晰。
- 当前修复方案：
  1. 给 `GhosttySurfaceHostModel` 增加 `pendingWindowResponderRestoreTask`，把 responder 恢复改为延后一拍执行，避免在当前 SwiftUI transaction / AppKit 文本输入结束栈内同步抢焦点。
  2. 恢复前先同步判断：pane 仍是逻辑焦点、window 仍存在、surface 仍未拥有 responder、且当前没有同类恢复任务在途；不满足则记录 diagnostics 并跳过。
  3. 当 pane 失焦、surface 释放或进程退出时，主动取消挂起的 responder restore，避免旧 pane 的晚到任务再去操作新窗口状态。
  4. 回归测试 `GhosttySurfaceHostTests.testRestoreWindowResponderDefersFocusedPaneReclaimOutsideCurrentUpdatePass` 先红后绿，约束“不能同步抢焦点，但必须随后安全夺回 terminal responder”。
- 长期改进建议：
  1. 后续应继续把 `WorkspaceHostView.surfaceModel(for:)` 收敛为**纯数据/依赖解析**入口，任何窗口焦点、第一响应者、弹窗展示之类命令式动作都尽量迁到显式 lifecycle hook（如 attach/onChange/task）或专用 coordinator。
  2. 对 AppKit `firstResponder` 这类会牵动输入法、文本编辑与 SwiftUI transaction 的动作，默认都应假设“同步调用是高风险操作”；若来源于 View 计算链路，优先延后到下一轮主线程。
- 验证证据：
  - 红灯：`swift test --package-path macos --filter GhosttySurfaceHostTests/testRestoreWindowResponderDefersFocusedPaneReclaimOutsideCurrentUpdatePass` → 失败，断言“恢复 responder 不应在当前 SwiftUI/AppKit 更新栈内同步抢焦点”未成立。
  - 绿灯：`swift test --package-path macos --filter GhosttySurfaceHostTests/testRestoreWindowResponderDefersFocusedPaneReclaimOutsideCurrentUpdatePass` → 1 test，0 failures。
  - 相关回归：`swift test --package-path macos --filter 'GhosttySurfaceHostTests|GhosttySurfaceLifecycleLoggingIntegrationTests|GhosttySurfaceRepresentableUpdatePolicyTests|WorkspaceSurfaceActivityPolicyTests'` → 22 tests，5 skipped，0 failures。
  - 构建验证：`swift build --package-path macos` → Build complete。
  - 差异校验：`git diff --check` → 无输出。


## 2026-03-24 workspace 打开项目快捷键在终端焦点下无效排查

- [x] 读取 Ghostty 键盘事件/菜单分发代码，确认快捷键在终端焦点下的实际路由
- [x] 复现并锁定 root cause：是菜单未尝试还是 focused action 为 nil
- [x] 先补失败测试，覆盖终端聚焦时应用菜单快捷键仍能命中菜单命令
- [x] 实施最小修复并回归 workspace 打开项目快捷键
- [x] 运行定向验证并在 Review 记录直接原因、设计诱因、修复方案与证据


## 2026-03-24 workspace 打开项目快捷键与弹窗焦点调整

- [x] 阅读 AGENTS / 相关记忆 / 最近提交，确认现有 workspace 打开项目入口、设置页与焦点实现位置
- [x] 确认“设计页面”配置范围与默认快捷键语义（默认 Command+K）
- [x] 给出最小实现方案并等待用户确认
- [x] 先补失败测试，覆盖快捷键配置持久化、命令入口与弹窗默认焦点
- [x] 实现快捷键配置、菜单/命令接线与弹窗焦点修复
- [x] 运行定向验证并在本文件追加 Review（直接原因、设计层诱因、修复方案、长期建议、证据）

- [x] 盘点当前 staged / unstaged / untracked 变更范围
- [x] 阅读关键 diff 与新增文件，记录潜在风险
- [x] 输出按优先级排序的 review findings
- [x] 在 tasks/todo.md 追加本次 review 结论与证据

- [x] 收集 GitHub workflow 失败 run 的日志与错误位置

- [x] 根据日志定位直接原因与是否存在设计层诱因

- [x] 先补充能覆盖该失败场景的测试/验证，再实施最小修复

- [x] 运行本地验证并更新 tasks/todo.md Review

- [x] 核对当前本地/远端 3.0.0 与 v3.0.0 tag 状态
- [x] 删除错误的 3.0.0 tag，创建并推送正确的 v3.0.0 tag
- [x] 验证远端 v3.0.0 指向正确提交，并记录 lessons / review

- [x] 定位工作区左侧侧边栏宽度无法拖拽的问题与根因
- [x] 先补充能稳定复现该问题的测试或验证手段
- [x] 实施最小修复并更新相关注释/文档（如需要）
- [x] 运行验证并在本文件追加 Review 证据
- [x] 设计侧边栏宽度持久化方案并确认写入位置
- [x] 先补充失败测试，约束侧边栏宽度能从设置读取并写回
- [x] 实现侧边栏宽度持久化到设置
- [x] 运行验证并追加新的 Review 证据

- [x] 核对 notify worktree 已提交变更与未提交残留，确定本次合并范围
- [x] 在 main 合并 notify 分支并处理必要冲突
- [x] 运行必要验证并确认工作区状态
- [x] 提交合并结果并记录 Review 证据
- [x] 覆盖 v3.0.0 tag 指向新提交并验证结果

- [x] 核对本地/远端 v3.0.0 当前指向，确认需要强制覆盖远端 tag
- [x] 强制推送本地 v3.0.0 到 origin
- [x] 复核远端 v3.0.0 已指向当前 merge commit，并记录 Review 证据

- [x] 核对本地 main 与 origin/main 指向，确认推送前基线
- [x] 推送本地 main 到 origin/main
- [x] 复核远端 main 已指向当前 HEAD，并记录 Review 证据

- [x] 收集最新失败 GitHub Action run 的编号、触发时间、失败 job 与原始日志
- [x] 对照 workflow 配置与近期提交定位直接原因
- [x] 判断是否存在设计层诱因，并给出修复建议与验证方案

- [x] 为 release workflow 补回归测试，约束 draft release 清理不再依赖不支持的 gh json 字段
- [x] 以最小改动修复 .github/workflows/release.yml 的 draft release 清理逻辑
- [x] 运行定向验证并回填本次 GitHub Action 故障 Review

- [x] 整理 release workflow 修复改动并完成提交前校验
- [x] 提交并推送 release workflow 修复到 origin/main
- [x] 用 workflow_dispatch 触发 release(tag=v3.0.0)
- [ ] 复核新 run 结论、失败点是否消失以及 release 产物状态

- [x] 收集 arm64 Swift test 失败明细并定位是代码回归还是测试脆弱性
- [x] 以最小改动修复两条 AppKit 时序脆弱测试
- [ ] 跑本地定向测试与完整 swift test 验证后重新触发 release workflow

## 2026-03-23 升级方案对标调研（cmux / supacode / ghostty）

- [x] 梳理 DevHaven 当前升级相关现状与已知约束
- [x] 对比 cmux、supacode、ghostty 的升级实现路径与发布形态
- [x] 基于 DevHaven 当前架构给出建议、风险与落地顺序

## 2026-03-23 升级终局方案架构图与模块拆分

- [x] 明确“最完美方案”的范围边界（仅架构，不进入实现）
- [x] 输出升级终局方案的架构图、模块职责与数据流
- [x] 与用户确认该设计方向是否成立

## 2026-03-23 升级终局方案实现

- [x] 落升级终局设计文档与实现计划
- [x] 为更新设置与版本元数据补失败测试
- [x] 实现更新设置模型、菜单与设置页入口
- [x] 接入 Sparkle runtime 与开发态禁用策略
- [x] 补 Sparkle vendor / 打包脚本 / release workflow / nightly workflow
- [x] 更新 README / AGENTS / Review 并完成验证

## 2026-03-23 无苹果账号升级模式收口

- [x] 为 manual-download 更新模式补失败测试
- [x] 实现 appcast 手动检查与“打开下载页” fallback
- [x] 同步打包元数据 / README / AGENTS 并完成验证

## 2026-03-23 Sparkle 启动崩溃修复

- [x] 把 Sparkle dyld 缺库问题登记到 tasks/todo.md，并明确验证闭环
- [x] 收集打包产物内 Sparkle.framework 布局与 DevHavenApp rpath 证据，确认直接原因
- [x] 先为打包脚本补回归测试，约束必须为 Frameworks 注入运行时 rpath
- [x] 修复 build-native-app.sh 的 Sparkle 运行时查找路径
- [x] 重新打包并验证启动不再因缺少 Sparkle.framework 崩溃
- [x] 在 Review 中记录直接原因、设计层诱因、修复方案与验证证据

## 2026-03-23 stable appcast 404 排查

- [x] 把 stable appcast 404 排查任务登记到 tasks/todo.md
- [x] 核对 GitHub 上 stable-appcast / nightly 相关 release 与 appcast 资产实际状态
- [x] 对照本地 AppMetadata 与 workflow，定位 404 的直接原因与设计层诱因
- [x] 先补回归测试，再实施最小修复
- [x] 完成验证并在 Review 记录结论、证据与后续发布方式

## 2026-03-23 首次 stable-appcast 正式发布

- [x] 把首次 stable-appcast 正式发布任务登记到 tasks/todo.md
- [x] 核对当前 git 工作区、版本号、tag、远端 release 与 feed 基线
- [x] 收口发布前必要改动并完成验证
- [x] 提交并推送发布改动，创建/更新正式版本 tag
- [x] 执行首次 stable-appcast 正式发布并验证 feed / 下载链路
- [x] 在 Review 中记录发布结果、证据与后续维护方式

## 2026-03-23 Ghostty 搜索功能排查

- [x] 把 Ghostty 搜索功能排查任务登记到 tasks/todo.md
- [x] 对比 Supacode 与 DevHaven 的 Ghostty / libghostty 搜索相关接入代码
- [x] 定位 DevHaven 当前“没有搜索”的直接原因与是否存在设计层诱因
- [x] 如需改动，给出最小实现方案与验证路径
- [x] 在 Review 中记录结论与证据

## 2026-03-23 Ghostty 搜索功能实现

- [x] 落搜索功能设计文档与实施计划
- [x] 先补 Ghostty 搜索 bridge / 菜单 / overlay 的失败测试
- [x] 运行定向测试确认红灯
- [x] 实现搜索状态、搜索浮层与菜单/快捷键入口
- [x] 更新 AGENTS 与相关源码注释/文档
- [x] 运行定向测试与构建验证
- [x] 在 Review 中记录修复结论与证据

## 2026-03-23 Ghostty 搜索浮层右上角定位

- [x] 落右上角定位设计与实施计划
- [x] 先补搜索浮层右上角定位的失败测试
- [x] 运行定向测试确认红灯
- [x] 以最小改动将搜索浮层固定到右上角
- [x] 运行定向测试与构建验证
- [x] 在 Review 中记录结论与证据

## 2026-03-23 会话恢复方案对标调研（Ghostty / Supacode / cmux）

- [x] 梳理 DevHaven 当前终端/工作区状态模型与会话恢复相关约束
- [x] 检索 Ghostty、Supacode、cmux 是否已有会话恢复实现、边界与实现线索
- [ ] 基于调研结果给出 DevHaven 可借鉴点、缺口与建议

## 2026-03-23 pane 文本回退链修复

- [x] 确认 review 提到的 pane 文本丢失问题在当前 `WorkspaceRestoreStore` 提交顺序中成立
- [x] 先补回归测试，覆盖不同 pane id、相同 pane id 文本覆盖、主 manifest 写失败三种场景
- [x] 修复 `WorkspaceRestoreStore` 的保存协议：pane 文本 ref 改为每次保存唯一、成功写入 manifest 后再 prune、prune 保留 current + prev 两代引用
- [x] 更新 `AGENTS.md` 中 session-restore 存储语义描述
- [x] 运行定向测试并在 Review 追加直接原因、设计诱因、修复方案与验证证据

## 2026-03-24 聚焦 pane 分屏后原 pane 消失回归排查

- [x] 回看 2026-03-20 的历史修复与当前 Ghostty/Workspace 代码差异，确认最可能的回归入口
- [x] 先补能稳定复现“聚焦 pane 分屏后原 pane 消失”的失败测试，判断是 subtree remount 还是 surface attach/focus 复用问题
- [x] 按失败测试实施最小修复，并同步必要文档/注释
- [x] 运行定向验证并在本文件追加 Review（包含直接原因、设计层诱因、修复方案、长期建议、证据）

## Review（2026-03-24 聚焦 pane 分屏后原 pane 消失回归排查）

- 结果：
  1. 已定位并修复这次“聚焦 pane 后再分屏，原 pane 画面消失”的回归；问题不是 2026-03-20 修掉的 `WorkspaceSplitTreeView` structural remount 又被打开，而是 **已有 surface 在 representable 重新挂载时没有先走 container reuse 协议**。
  2. 现在 `makeNSView` 阶段会显式按“新容器附着”路径拿 surface，确保已有 `GhosttyTerminalSurfaceView` 在被复用到新的 split/container 前先执行 `prepareForContainerReuse()`；而普通 `updateNSView` 仍保持轻量复用，不会在每次更新都误做 reuse reset。
- 直接原因：
  1. `GhosttySurfaceRepresentableUpdatePolicy.resolvedSurfaceView(...)` 在 2026-03-21 的加固改动里为了避免 `updateNSView` 反复触发 reuse 副作用，改成了 `model.currentSurfaceView ?? model.acquireSurfaceView(...)`。
  2. 这个改动同时覆盖了 `makeNSView` 路径，导致当 SwiftUI 因 split/tree 重排重新创建 representable 容器时，如果 model 已经持有 surface，就会直接返回 `currentSurfaceView`，从而 **绕过 `GhosttySurfaceHostModel.acquireSurfaceView()` 里唯一负责的 `prepareForContainerReuse()`**。
  3. 一旦旧 surface 此时正持有窗口 `firstResponder`，它就会带着旧焦点身份直接被重挂到新的 split 容器；用户看到的表象就是“原 pane 屏幕空了/像消失了一样”。
- 设计层诱因：
  1. reuse 语义本来集中收口在 `GhosttySurfaceHostModel.acquireSurfaceView()`，但后续 representable update policy 为了规避另一类问题，直接旁路读取 `currentSurfaceView`，把“拿 surface”和“准备复用 surface”拆成了两条不一致的入口。
  2. 这属于**复用协议被 helper 层绕开**的问题：调用方只想“拿一个 view”，却无意中跳过了附着前必须执行的状态迁移。未发现更大的系统设计缺陷，但 reuse protocol 的入口此前不够单一。
- 当前修复方案：
  1. 给 `GhosttySurfaceRepresentableUpdatePolicy.resolvedSurfaceView(...)` 增加 `prepareForAttachment` 参数，明确区分“新容器附着”与“同容器 update”两类调用。
  2. `GhosttyTerminalView.makeNSView` 传 `prepareForAttachment: true`，强制走 `model.acquireSurfaceView(...)`，确保已有 surface 被复用到新 split/container 前一定先执行 `prepareForContainerReuse()`。
  3. `GhosttyTerminalView.updateNSView` 传 `prepareForAttachment: false`，继续沿用轻量路径，避免每次 SwiftUI update 都误触发 reuse reset。
  4. 新增 `GhosttySurfaceRepresentableUpdatePolicyTests.testResolvedSurfaceViewPreparesExistingSurfaceForContainerReuse`，直接复现“已有 surface 已拿到 firstResponder，再次解析代表 view 时应先释放旧 responder”的场景。
- 长期改进建议：
  1. 后续凡是“surface 复用 / 容器重挂载”的逻辑，都应继续收口在 `GhosttySurfaceHostModel` 这一层；helper 可以决定“这次是不是 attachment”，但不应再直接旁路 surface reuse protocol。
  2. 若后续还要继续细分 representable 的 make/update 行为，建议把“attachment lifecycle”抽成更显式的 API（例如 `surfaceViewForAttachment` / `surfaceViewForUpdate`），避免布尔参数语义再次被误用。
- 验证证据：
  - 红灯：`swift test --package-path macos --filter GhosttySurfaceRepresentableUpdatePolicyTests/testResolvedSurfaceViewPreparesExistingSurfaceForContainerReuse` → 失败，断言已有 surface 在 reuse 前没有释放 `firstResponder`，与用户“聚焦 pane 后分屏原 pane 消失”的现象一致。
  - 绿灯：`swift test --package-path macos --filter GhosttySurfaceRepresentableUpdatePolicyTests` → 4 tests，0 failures。
  - 回归验证：`swift test --package-path macos --filter 'GhosttySurfaceRepresentableUpdatePolicyTests|GhosttySurfaceHostTests|WorkspaceSplitTreeViewKeyPolicyTests|WorkspaceTerminalSessionStoreTests|WorkspaceTopologyTests|GhosttySurfaceScrollViewTests'` → 33 tests，0 failures，5 skipped。
  - 构建验证：`swift build --package-path macos` → Build complete。
  - 差异校验：`git diff --check` → 无输出。

## 2026-03-24 为 Ghostty split/attach/focus/reuse 链路补运行期日志

- [x] 梳理现有 diagnostics 模式并确认最小日志边界（make/update/acquire/reuse/attach/focus）
- [x] 先补失败测试，约束 diagnostics 事件与关键调用点都存在
- [x] 实现 unified log 与调用点接线，并同步 AGENTS / lessons
- [x] 运行定向验证并在本文件追加 Review 证据

## 2026-03-24 按 A 方案重构 workspace 分屏渲染为扁平 pane 布局

- [x] 写实现计划文档，明确扁平 pane 布局 + 独立 divider overlay 的落地路径
- [x] 先补失败测试，覆盖 split handle/path 纯布局能力与 `WorkspaceSplitTreeView` 扁平渲染约束
- [x] 以最小改动实现扁平 pane 渲染，避免旧 pane 因递归宿主重建被重复挂载
- [x] 同步更新 AGENTS / lessons，并完成定向验证与 Review 记录

## Review（2026-03-24 按 A 方案重构 workspace 分屏渲染为扁平 pane 布局）

- 结果：
  1. 已按 A 方案把 `WorkspaceSplitTreeView` 从“递归 split 容器里嵌套 pane host”改成“扁平 leaf pane + 独立 split handle overlay”。
  2. 旧 pane 在 split 后现在只改变 frame，不再因为从 root leaf 迁移到 child leaf 而创建第二个宿主去争抢同一个 `GhosttyTerminalSurfaceView`。
  3. 旧的 `WorkspaceSplitTreeViewKeyPolicy` 已删除；当前不再依赖 subtree remount key 策略兜底，而是直接消除“pane host 跟着 split 树迁移”的结构性诱因。
- 直接原因：
  1. 现场 unified log 明确显示：同一个旧 pane 在一次 split 事务里会连续触发多次 `representable-make` + `acquire reused=true`；
  2. 这说明旧 pane 的 SwiftUI 宿主在 split 重排时被重复创建，多个宿主去竞争同一个 surface，最终旧位置只剩空壳，看起来就像“原 pane 消失”。
- 设计层诱因：
  1. 旧实现让 `WorkspaceSplitTreeView` 递归渲染 `SubtreeView -> WorkspaceSplitView -> WorkspaceTerminalPaneView`；当 leaf 变成 split child 时，pane host 的父层级也跟着变。
  2. 对普通 SwiftUI 视图这问题不大，但对“一个 pane 对应一个长生命周期 NSView surface”的 Ghostty 宿主，这会把树结构变化误放大成宿主层级变化。未发现更大的系统设计缺陷，但 pane 宿主边界此前没有从 split 树里剥离。
- 当前方案：
  1. 在 `WorkspacePaneTree.Node` 新增公开的 `splitHandles(in:path:...)`，和已有 `leafFrames(in:)` 一起作为扁平布局输入；
  2. `WorkspaceSplitTreeView` 现在用 `GeometryReader + ZStack` 平铺 `root.leafFrames(in: canvasFrame)`；
  3. split divider 改为独立 `SplitHandleOverlay`，拖拽时按对应 `splitBounds + path` 回写 `onSetSplitRatio(path, ratio)`，双击仍走 `onEqualize(tab.focusedPaneId)`；
  4. 删除 `WorkspaceSplitTreeViewKeyPolicy.swift` 与其测试，避免保留过时的 subtree-remount 兜底路径。
- 长期改进建议：
  1. 后续如果还出现 pane 消失，优先继续看 unified log 中是否仍有“同一 pane 同轮多次 `representable-make`”现象；如果没有，再回到 focus/resize 分支继续排；
  2. 若未来还要增强 split UX，可继续把 divider drag math 抽到 Core 纯布局 helper，但当前先保持最少修改即可。
- 验证证据：
  - 红灯：`swift test --package-path macos --filter 'WorkspaceTopologyTests|WorkspaceSplitTreeViewFlatLayoutTests'`（实现前）→ 编译失败，提示 `splitHandles` 不存在；随后 source-based 测试也明确卡住 `WorkspaceSplitTreeView` 仍是递归 `SubtreeView`。
  - 绿灯：`swift test --package-path macos --filter 'WorkspaceTopologyTests|WorkspaceSplitTreeViewFlatLayoutTests'` → 12 tests，0 failures。
  - 回归验证：`swift test --package-path macos --filter 'WorkspaceTopologyTests|WorkspaceSplitTreeViewFlatLayoutTests|WorkspaceSplitViewTests|GhosttySurfaceRepresentableUpdatePolicyTests|GhosttySurfaceLifecycleLoggingIntegrationTests|GhosttySurfaceHostTests|WorkspaceTerminalSessionStoreTests'` → 34 tests，0 failures，5 skipped。
  - 构建验证：`swift build --package-path macos` → Build complete。
  - 差异校验：`git diff --check` → 无输出。
  - 说明：本轮尚未包含新的用户现场 GUI 复验，因此“代码/测试侧已落地”与“现场已确认彻底不复现”需继续分开表述。

## Review（2026-03-24 为 Ghostty split/attach/focus/reuse 链路补运行期日志）

- 结果：
  1. 已为 Ghostty 分屏相关的关键生命周期边界补齐结构化 unified log，覆盖 `makeNSView`、`updateNSView`、`acquireSurfaceView`、`prepareForContainerReuse`、`surfaceViewDidAttach`、`requestFocusIfNeeded`、`restoreWindowResponderIfNeeded` 与 `updateSurfaceMetrics/resize decision`。
  2. 新日志统一收口到 `GhosttySurfaceLifecycleDiagnostics`，使用 `workspace/tab/pane/surface` 标识 + focus/attachment/resize 状态字段，后续即使问题是“过一段时间才坏”，也能用现场 unified log 还原当次链路。
- 直接原因：
  1. 当前仓库已有 `WorkspaceLaunchDiagnostics`，但它主要覆盖“进入工作区 / 创建 surface”这类首开链路；
  2. 这次 pane 消失问题真正需要排查的是 **steady-state 生命周期**：某次 split/update/reuse/attach/focus/resize 到底走了哪条路径、是否跳过了 reuse protocol、是否请求了焦点、是否被 resize policy 跳过；
  3. 在没有这层运行期日志时，后续即使用户再次复现，也很难区分是 `makeNSView` 重建、`updateNSView` swap、旧 responder 没释放，还是 backing size / resize policy 异常。
- 设计层诱因：
  1. 现有 diagnostics 较偏“入口态”和“导入态”，对 Ghostty surface 这类长生命周期 UI primitive 缺少持续观测点；
  2. 未发现明显系统设计缺陷，但诊断层此前没有把“surface steady-state lifecycle”建模成独立日志面，导致回归问题只能靠代码猜。
- 当前方案：
  1. 新增 `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceLifecycleDiagnostics.swift`，统一输出 `[ghostty-surface] ...` 日志；
  2. `GhosttyTerminalView` 记录 representable make/update；
  3. `GhosttySurfaceHostModel` 记录 acquire/attach/focus-request/restore-responder；
  4. `GhosttyTerminalSurfaceView` 记录 prepare-reuse 与 resize decision；
  5. 日志默认 **不记录终端可见文本**，只记录结构化状态，降低噪音与敏感信息泄漏风险。
- 长期改进建议：
  1. 若后续用户再次给到 unified log，可优先按 `pane` / `surface` 把一条完整事件链串起来，再决定是否需要更细的单次事件日志；
  2. 如果未来确认 resize 是高频但低价值噪音，可再给 `GhosttySurfaceLifecycleDiagnostics` 增加采样或 debug 开关；当前阶段先保证可排障优先。
- 验证证据：
  - 红灯：`swift test --package-path macos --filter 'GhosttySurfaceLifecycleDiagnosticsTests|GhosttySurfaceLifecycleLoggingIntegrationTests'`（实现前）→ 编译失败，明确提示 `GhosttySurfaceLifecycleDiagnostics` / `recordResizeDecision` 等符号不存在。
  - 绿灯：`swift test --package-path macos --filter 'GhosttySurfaceLifecycleDiagnosticsTests|GhosttySurfaceLifecycleLoggingIntegrationTests'` → 6 tests，0 failures。
  - 回归验证：`swift test --package-path macos --filter 'GhosttySurfaceLifecycleDiagnosticsTests|GhosttySurfaceLifecycleLoggingIntegrationTests|GhosttySurfaceRepresentableUpdatePolicyTests|GhosttySurfaceHostTests|GhosttySurfaceScrollViewTests|WorkspaceSplitTreeViewKeyPolicyTests|WorkspaceTerminalSessionStoreTests|WorkspaceTopologyTests'` → 39 tests，0 failures，5 skipped。
  - 构建验证：`swift build --package-path macos` → Build complete。
  - 差异校验：`git diff --check` → 无输出。

## Review（2026-03-23 pane 文本回退链修复）

- 结果：
  1. `manifest.prev.json` 回退链现在会保留完整的 pane 文本引用；不同 pane id 和相同 pane id 文本更新两种场景都能正确回退到旧文本。
  2. 当新一轮保存在写 `manifest.json` 这一步失败时，原有 current 快照和其 pane 文本不会再被提前 prune 或覆盖。
- 直接原因：
  1. 原实现先写新 pane 文本、再 prune、最后才备份旧 manifest 并写新 manifest，导致旧 manifest 仍在引用的 pane 文件可能被提前删除。
  2. 原实现把 `snapshotTextRef` 当成 pane 的长期身份复用；同一 pane id 二次保存时，新文本会覆盖旧文本文件，使 `manifest.prev.json` 退回后仍读到新文本。
- 设计层诱因：
  1. 旧实现把 manifest 做成“两代回退”，但 pane 文本文件没有同步版本化，manifest 与 pane 文件之间缺少统一提交协议。
  2. `snapshotTextRef` 语义此前偏向“pane 身份”，而不是“某次保存的 immutable 文本版本指针”，这会天然破坏 prev 回退语义。
- 当前修复方案：
  1. `WorkspaceRestoreStore.saveSnapshot()` 在每次保存时为带文本的 pane 生成新的 `snapshotTextRef`，不再复用旧 ref；
  2. 先写新 pane 文本，再把“保存前可解析的主 manifest”原子写成 `manifest.prev.json`，再原子写新的 `manifest.json`；
  3. `prune` 延后到主 manifest 成功写入之后，并且同时保留 current + prev 两代 manifest 引用到的 pane 文本文件；
  4. 新增 `manifestWriter` 注入 seam，用稳定单测覆盖“主 manifest 写失败但现有快照不能被污染”的场景。
- 长期改进建议：
  1. 如果后续 session-restore 还会继续扩展，可再把 current/prev 升级成 generation 目录模型，进一步让 manifest 与 pane 文件的切换完全代际化；
  2. 当前阶段保持 store 层集中收口已经足够，避免把版本化逻辑扩散到 coordinator / UI 层。
- 验证证据：
  - 红灯验证：`swift test --package-path macos --filter WorkspaceRestoreStoreTests`（实现前）→ 编译失败，明确提示 `WorkspaceRestoreStore` 缺少 `manifestWriter` 注入点，表明“主 manifest 写失败保护”场景尚不可测试/实现
  - 绿灯验证：`swift test --package-path macos --filter WorkspaceRestoreStoreTests` → 7 tests，0 failures
  - 回归验证：`swift test --package-path macos --filter 'WorkspaceRestoreStoreTests|WorkspaceRestoreCoordinatorTests|GhosttyWorkspaceRestoreSnapshotTests|NativeAppViewModelWorkspaceRestoreTests|GhosttySurfaceHostModelSnapshotTests|WorkspaceRestorePresentationTests'` → 20 tests，0 failures

## Review（2026-03-23 Ghostty 搜索功能排查）

- 结论：
  1. Supacode 的搜索不是“自动开关打开后 libghostty 自己弹出来”的，而是 **宿主 App 自己实现了一层搜索 UI/命令桥接**，再通过 `ghostty_surface_binding_action(...)` 把 `start_search` / `search:<needle>` / `navigate_search:*` / `end_search` 发回 libghostty。
  2. DevHaven 当前没有搜索，不是因为底层 GhosttyKit 不支持，而是 **宿主侧没有接完整搜索链路**。
- 直接原因：
  1. `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceBridge.swift` 目前只处理 title / pwd / scrollbar / config / notification / progress / bell 等 action，没有处理 `GHOSTTY_ACTION_START_SEARCH`、`GHOSTTY_ACTION_END_SEARCH`、`GHOSTTY_ACTION_SEARCH_TOTAL`、`GHOSTTY_ACTION_SEARCH_SELECTED`。
  2. `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceState.swift` 没有搜索相关状态字段（如 `searchNeedle` / `searchTotal` / `searchSelected` / `searchFocusCount`）。
  3. `macos/Sources/DevHavenApp/WorkspaceTerminalPaneView.swift` / `GhosttySurfaceHost.swift` 没有像 Supacode 那样在 terminal 上层叠加搜索条 overlay。
  4. `macos/Sources/DevHavenApp/DevHavenApp.swift` 也没有接入 Find 菜单 / FocusedValue / scene action，因此没有 App 级搜索入口。
- 设计层诱因：
  1. DevHaven 当前对 Ghostty 的接入重点放在 tab / split / agent 状态 / 通知，没有把“需要宿主提供 UI 的 libghostty action”抽象成统一能力层，导致搜索这类功能天然缺口。
  2. 未发现明显系统设计缺陷；但存在一处能力边界未收口：DevHaven 已经有 `performBindingAction(_:)` 这样的底层发送能力，却没有在更高层建立“搜索 UI + menu command + bridge state”的闭环。
- 当前修复方案（建议的最小实现）：
  1. 在 `GhosttySurfaceState` 增加搜索状态字段；
  2. 在 `GhosttySurfaceBridge` 增加 4 个 search action case；
  3. 参考 Supacode 增加 `GhosttySurfaceSearchOverlay`，并在 terminal pane 上层按 `searchNeedle != nil` 显示；
  4. 为当前 focused pane 增加 `startSearch / searchSelection / navigateSearchNext / navigateSearchPrevious / endSearch` 入口；
  5. 在 `DevHavenApp.swift` 增加 Find 菜单项与快捷键桥接；
  6. 保留现有 `ghostty_surface_binding_action(...)` 作为真正发往 libghostty 的唯一出口。
- 长期改进建议：
  1. 把这类“Ghostty action -> 宿主 UI/命令”的能力抽成统一的 command surface，而不是以后再在 `WorkspaceHostView` / `DevHavenApp` 分散补丁式加功能。
  2. 为搜索链路补最少两类测试：bridge action 状态测试、overlay 显隐与按钮行为测试。
- 验证证据：
  - `macos/Vendor/GhosttyKit.xcframework/macos-arm64_x86_64/Headers/ghostty.h` 明确包含 `GHOSTTY_ACTION_START_SEARCH` / `END_SEARCH` / `SEARCH_TOTAL` / `SEARCH_SELECTED` 与 `ghostty_surface_binding_action(...)`。
  - `macos/Sources/DevHavenApp/GhosttyResources/ghostty/doc/ghostty.5.md` 明确包含 `search` / `search_selection` / `navigate_search` / `start_search` / `end_search`。
  - Supacode 侧已有完整接入：`GhosttySurfaceBridge.swift`、`GhosttySurfaceState.swift`、`GhosttySurfaceSearchOverlay.swift`、`TerminalCommands.swift`、`WorktreeDetailView.swift`、`WorktreeTerminalManager.swift`、`TerminalSplitTreeView.swift`。
  - DevHaven 侧当前缺失对应接入：`GhosttySurfaceBridge.swift`、`GhosttySurfaceState.swift`、`WorkspaceTerminalPaneView.swift`、`DevHavenApp.swift`。

## Review（2026-03-23 Ghostty 搜索功能实现）

- 结果：
  1. DevHaven 已补齐 Ghostty 搜索的宿主闭环：菜单入口、focused pane 路由、search action bridge、搜索浮层与 binding action 下发。
  2. 当前已支持：`查找…`、`查找下一个`、`查找上一个`、`隐藏查找栏`、`使用所选内容查找`。
- 直接原因：
  1. 此前 `GhosttySurfaceBridge` 没有处理 `START_SEARCH / END_SEARCH / SEARCH_TOTAL / SEARCH_SELECTED`；
  2. `GhosttySurfaceState` 没有搜索状态字段；
  3. App 菜单与当前 pane 之间缺少 focused action 路由；
  4. 终端宿主层没有搜索浮层。
- 设计层诱因：
  1. DevHaven 之前已经有 `performBindingAction(...)` 这条底层通道，但没有把“菜单命令 -> 当前 pane -> 搜索 UI -> libghostty action”收成完整能力；
  2. 未发现明显系统设计缺陷；本次通过 `WorkspaceTerminalCommands + FocusedValue + GhosttySurfaceSearchOverlay` 把职责边界补齐。
- 当前修复方案：
  1. 在 `GhosttySurfaceState` 增加 `searchNeedle / searchTotal / searchSelected / searchFocusCount`；
  2. 在 `GhosttySurfaceBridge` 中桥接 4 个 search action；
  3. 新增 `GhosttySurfaceSearchOverlay.swift`，通过 `search:<needle>`、`navigate_search:*`、`end_search` 驱动 libghostty；
  4. 在 `GhosttySurfaceHostModel` 中补充当前 pane 搜索动作入口；
  5. 新增 `WorkspaceTerminalCommands.swift`，通过 `FocusedValue` 将 App 菜单命令路由到当前 active pane；
  6. 更新 `AGENTS.md`，记录搜索相关关键文件和边界约束。
- 长期改进建议：
  1. 如后续继续增强 Ghostty 宿主能力，建议把 command-palette / search / readonly / inspector 一类“宿主 UI + Ghostty action”继续沿同一 command surface 扩展，而不要散落在全局菜单或 ViewModel 中；
  2. 若后续要提升体验，可再补搜索输入节流、环绕导航与 UI 级交互测试。
- 验证证据：
  - 红灯验证：`swift test --package-path macos --filter GhosttySurfaceBridgeTabPaneTests`（实现前）→ 编译失败，明确提示 `GhosttySurfaceState` 缺少 `searchNeedle / searchFocusCount / searchTotal / searchSelected`
  - 绿灯验证：`swift test --package-path macos --filter 'GhosttySurfaceBridgeTabPaneTests|DevHavenAppCommandTests|WorkspaceTerminalCommandsTests|GhosttySurfaceSearchOverlayTests'` → 12 tests，0 failures
  - 构建验证：`swift build --package-path macos` → `Build complete! (0.53s)`，exit 0

## Review（2026-03-23 Ghostty 搜索浮层右上角定位）

- 结果：Ghostty 搜索浮层已从左上角改为固定显示在 terminal 区域右上角；搜索行为本身未改动。
- 直接原因：
  1. `GhosttySurfaceHost` 当前使用 `ZStack(alignment: .topLeading)` 承载 startup overlay 与 search overlay；
  2. 搜索浮层此前直接放进该 `ZStack`，未显式声明自己的对齐方式，因此默认落在左上角。
- 设计层诱因：
  1. 未发现明显系统设计缺陷；
  2. 这是一个宿主 overlay 布局细节没有被单独声明的问题：startup overlay 与 search overlay 共用父级左上角对齐，但搜索浮层本应有独立定位语义。
- 当前修复方案：
  1. 保持 `GhosttySurfaceSearchOverlay` 的输入、上下一个、关闭等逻辑不变；
  2. 仅在 `GhosttySurfaceHost.swift` 中给搜索浮层增加 `frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)`，让其固定到右上角；
  3. 不改 startup overlay 的原有左上角位置。
- 长期改进建议：
  1. 如果未来还会新增更多 Ghostty 浮层，建议再考虑统一 overlay 布局策略；
  2. 当前阶段继续保持“单个浮层各自声明定位语义”的轻量做法即可，避免过度设计。
- 验证证据：
  - 红灯验证：`swift test --package-path macos --filter GhosttySurfaceSearchOverlayTests`（实现前）→ 1 failure，明确提示“搜索浮层应固定对齐到 terminal 区域右上角”
  - 绿灯验证：`swift test --package-path macos --filter GhosttySurfaceSearchOverlayTests`（实现后）→ 2 tests，0 failures
  - 构建验证：`swift build --package-path macos` → `Build complete! (1.98s)`，exit 0

## Review

## Review（2026-03-23 stable appcast 404 排查）

- 直接原因：
  1. 用户本地 `3.0.0 (3000002)` 已经带有 stable feed URL：`https://github.com/zxcvbnmzsedr/devhaven/releases/download/stable-appcast/appcast.xml`；
  2. 但截至排查时，远端 GitHub 上并不存在 `stable-appcast` / `nightly` alias release，因此客户端第一次检查更新直接得到 HTTP 404。
- 设计层诱因：
  1. 客户端 update 能力已本地实现，但远端第一次 appcast alias 发布尚未真正落地，导致“客户端先上线、feed 后上线”的时序错位；
  2. 未发现明显系统设计缺陷，但发布验证此前没有覆盖“固定 feed URL 是否真实可访问”这一条线上证据。
- 当前修复方案：
  1. 先完成首次 stable release / stable-appcast alias 正式发布；
  2. 对 live `stable-appcast` alias 做热修，确保固定 URL 命中真实 `appcast.xml`；
  3. 把后续 workflow / promote 脚本中的 feed 命名与 URL 生成问题补回归测试并修复，避免再出现“workflow success 但客户端 feed 仍错误”的假成功。
- 验证证据：
  - `gh release view stable-appcast --json ...`（排查前）→ `release not found`
  - `gh release view nightly --json ...`（排查前）→ `release not found`
  - `curl -I -L https://github.com/zxcvbnmzsedr/devhaven/releases/download/stable-appcast/appcast.xml`（排查前）→ `HTTP/2 404`
  - `gh release download stable-appcast --pattern appcast.xml`（发布后）可下载成功，说明 alias 资产真实存在
  - `curl -L https://github.com/zxcvbnmzsedr/devhaven/releases/download/stable-appcast/appcast.xml | sed -n '1,160p'`（热修后）→ appcast 已返回 `3.0.1 / 20260323013003` 且 enclosure 指向 `v3.0.1/DevHaven-macos-universal.zip`

## Review（2026-03-23 首次 stable-appcast 正式发布）

- 结果：已成功发布 `v3.0.1` 正式 release，并完成首个 `stable-appcast` alias feed 发布；当前稳定通道 feed 已返回 200，内容指向 `v3.0.1` 的 universal 安装包。
- 直接原因：
  1. 需要把本地升级基础设施第一次真正发布到远端，才能让客户端的 stable feed 不再 404；
  2. 发布过程中暴露出两个真实问题：`release.yml` 仍把 stable `v*` release 创建成 prerelease，以及 `promote-appcast.sh` 误把 `gh release upload file#label` 当成“改资产文件名”的手段。
- 设计层诱因：
  1. release workflow 的 appcast 发布链路此前只验证“job 是否成功”，没有验证最终 GitHub 固定 URL、asset 文件名与 appcast 内容是否真正符合客户端约定；
  2. `generate_appcast` 的 `download-url-prefix` 需要尾部斜杠这一细节此前没有被测试覆盖，导致第一次 live 发布生成了错误的 enclosure URL。
- 当前修复方案：
  1. 生成 Sparkle signing key，并把 `SPARKLE_PUBLIC_ED_KEY` / `SPARKLE_PRIVATE_ED_KEY` 写入 repo secrets；
  2. 提交升级基础设施并发布 `v3.0.1`；
  3. 修复 `release.yml`，确保 stable release 不再被标记为 prerelease；
  4. 修复 `promote-appcast.sh`，改为先复制成目标文件名再上传，避免 alias 资产名错误；
  5. 修复 release/nightly workflow 的 appcast 参数：`download-url-prefix` 带尾部 `/`，`--link` 指向具体 release 页面；
  6. 对当前 live `stable-appcast/appcast.xml` 做人工热修，确保现有客户端立即可用。
- 长期改进建议：
  1. 后续每次 release 固定增加两条线上验证：`curl stable-appcast/appcast.xml` 与 `curl vX.Y.Z/DevHaven-macos-universal.zip`；
  2. 若未来要继续增强 manual-download 体验，可再把客户端 appcast 解析逻辑从“优先 item link”收口为“优先 enclosure/download，再回退 release notes”，减少对 feed 文案排序的耦合。
- 验证证据：
  - 2026-03-23 `swift test --package-path macos` → 242 tests，5 skipped，0 failures。
  - 2026-03-23 `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release.yml"); YAML.load_file(".github/workflows/nightly.yml"); puts "workflows ok"'` → `workflows ok`
  - 2026-03-23 `gh secret list -R zxcvbnmzsedr/devhaven` → 已包含 `SPARKLE_PUBLIC_ED_KEY` / `SPARKLE_PRIVATE_ED_KEY`
  - 2026-03-23 `git push origin main` → `8e04767` 发布提交已推送；随后 `git push origin refs/tags/v3.0.1` 成功
  - 2026-03-23 `gh run view 23417576947 --json status,conclusion,jobs,url` → `status: completed`, `conclusion: success`
  - 2026-03-23 `gh release view v3.0.1 --json assets` → 包含 `DevHaven-macos-arm64.zip`、`DevHaven-macos-x86_64.zip`、`DevHaven-macos-universal.zip`、`appcast-staged.xml`
  - 2026-03-23 `gh release view stable-appcast --json assets` → 包含 `appcast.xml`
  - 2026-03-23 `curl -I -L https://github.com/zxcvbnmzsedr/devhaven/releases/download/stable-appcast/appcast.xml` → 最终返回 `HTTP/2 200`
  - 2026-03-23 `curl -L https://github.com/zxcvbnmzsedr/devhaven/releases/download/stable-appcast/appcast.xml | sed -n '1,160p'` → 返回 `3.0.1 / 20260323013003`，且 `enclosure url` 为 `https://github.com/zxcvbnmzsedr/devhaven/releases/download/v3.0.1/DevHaven-macos-universal.zip`

## Review（2026-03-23 Sparkle 启动崩溃修复）

- 直接原因：打包脚本虽然已把 `Sparkle.framework` 复制到 `DevHaven.app/Contents/Frameworks/`，但主可执行文件 `DevHavenApp` 没有注入 `@executable_path/../Frameworks` 这个 `LC_RPATH`，dyld 启动时无法从 app bundle 内解析 `@rpath/Sparkle.framework/Versions/B/Sparkle`，因此在进程刚启动阶段直接 abort。
- 设计层诱因：未发现明显系统设计缺陷；但当前打包验证此前只覆盖“Framework 是否被复制进 bundle”，没有覆盖“主可执行文件的 runtime search path 是否指向 Contents/Frameworks”，因此把一个运行时装载问题漏到了用户启动时才暴露。
- 当前修复方案：
  1. 在 `macos/Tests/DevHavenCoreTests/NativeBuildScriptUpdateSupportTests.swift` 新增回归断言，要求打包脚本显式包含 `install_name_tool` 与 `@executable_path/../Frameworks`。
  2. 在 `macos/scripts/build-native-app.sh` 中新增 `list_rpaths` / `ensure_binary_rpath`，在组装 `.app` 时对 `Contents/MacOS/DevHavenApp` 做幂等 rpath 注入。
  3. 保持注入发生在签名之前，避免后续签名链被二次修改破坏。
- 长期改进建议：后续所有“嵌入第三方动态 Framework”的打包链路，建议固定补一条 launch-time 验证：至少检查 `otool -l` 中存在目标 `rpath`，必要时再跑一次最小启动 smoke test，避免只看 bundle 文件布局就误判为可运行。
- 验证证据：
  - `otool -l /tmp/devhaven-native-app-manual/DevHaven.app/Contents/MacOS/DevHavenApp | rg -n 'LC_RPATH|path '`（修复前）→ 只有 `/usr/lib/swift`、`@loader_path`、Xcode Swift runtime 路径，没有 `@executable_path/../Frameworks`。
  - `swift test --package-path macos --filter NativeBuildScriptUpdateSupportTests`（补测试后、修复前）→ 2 failures，失败点正是缺少 `install_name_tool` / `@executable_path/../Frameworks` 断言。
  - `swift test --package-path macos --filter NativeBuildScriptUpdateSupportTests`（修复后）→ 2 tests，0 failures。
  - `swift test --package-path macos` → 240 tests，5 skipped，0 failures。
  - `bash macos/scripts/build-native-app.sh --release --no-open --skip-sign --output-dir /tmp/devhaven-native-app-manual --build-number 3000003` → exit 0，日志包含 `为主可执行文件注入 rpath：@executable_path/../Frameworks`。
  - `otool -l /tmp/devhaven-native-app-manual/DevHaven.app/Contents/MacOS/DevHavenApp | rg -n 'LC_RPATH|path '`（修复后）→ 新增 `path @executable_path/../Frameworks (offset 12)`。
  - `/tmp/devhaven-native-app-manual/DevHaven.app/Contents/MacOS/DevHavenApp` 后台启动并等待 3 秒 → `LAUNCH_STATUS=running`，说明已不再于 dyld 阶段因缺少 Sparkle.framework 立即崩溃。

## Review（2026-03-23 当前变更代码审查）

- 结论：本次审查基于当前工作树的 unstaged / untracked 变更完成，识别出 3 个需要优先处理的问题：
  1. Nightly 构建虽然在 `Info.plist` 写入了默认更新通道，但运行时完全没有读取该字段，首次启动仍会回到 `AppSettings()` 的 stable，导致 Nightly 安装后默认跟随 stable feed。
  2. stable release workflow 在 `prepare-release` 阶段把正式 `v*` release 一律创建 / 编辑为 prerelease，后续也没有切回正式 release。
  3. universal `.app` 是通过复制 arm64 `.app` 后再 `lipo` 替换主可执行文件生成的；但 workflow 把重新签名标记为“可选”，当 Developer ID secrets 缺失时仍会继续发布，留下签名失效的 universal 安装包。
- 验证证据：
  - `git status --short --branch`
  - `git diff --stat`
  - `swift test --package-path macos --filter '(DevHavenBuildMetadataTests|AppSettingsUpdatePreferencesTests|NativeBuildScriptUpdateSupportTests|ReleaseWorkflowUpdateInfrastructureTests|DevHavenAppCommandTests|SettingsViewTests)'` → 14 tests, 0 failures

## Review

- 直接原因：`WorkspaceShellView` 原先使用 `HStack + .frame(width: 280)` 固定左侧项目栏宽度，界面没有任何可拖拽分栏容器，因此侧边栏宽度无法通过拖拽改变。
- 修复方案：改为在 `WorkspaceShellView` 中使用 `WorkspaceSplitView` 承载左侧项目栏与右侧工作区内容，并新增 `WorkspaceSidebarLayoutPolicy` 负责默认宽度、最小/最大宽度以及最小内容区宽度的约束。
- 新增验证：
  - `macos/Tests/DevHavenAppTests/WorkspaceShellViewTests.swift`
  - `macos/Tests/DevHavenAppTests/WorkspaceSidebarLayoutPolicyTests.swift`
- 验证证据：
  - `swift test --package-path macos --filter 'Workspace(ShellView|SidebarLayoutPolicy)Tests'`
  - `swift test --package-path macos`


## Review（侧边栏宽度持久化）

- 直接原因：侧边栏虽然已经支持拖拽，但宽度只存在 `WorkspaceShellView` 的运行时 `@State` 中，没有写回 `AppSettings`，因此重新进入 workspace 或重启应用后会恢复默认值。
- 设计层诱因：UI 布局状态没有接入现有全局 settings 真相源；另外 `SettingsView.nextSettings` 手工重建 `AppSettings` 时，如果不显式透传新字段，会把后续新增设置悄悄丢掉。
- 当前修复方案：
  - 在 `AppSettings` 中新增 `workspaceSidebarWidth`，默认值 280，兼容旧配置缺省回退。
  - 在 `NativeAppViewModel` 中新增 `workspaceSidebarWidth` 读取入口与 `updateWorkspaceSidebarWidth(_:)` 写回入口。
  - 在 `WorkspaceSplitView` 中新增拖拽结束回调，使 `WorkspaceShellView` 能在拖拽结束后把最终宽度持久化到 settings。
  - 在 `SettingsView` 中透传 `workspaceSidebarWidth`，避免保存其他设置时覆盖该值。
- 新增/更新验证：
  - `macos/Tests/DevHavenCoreTests/AppSettingsWorkspaceSidebarWidthTests.swift`
  - `macos/Tests/DevHavenCoreTests/NativeAppViewModelWorkspaceSidebarWidthTests.swift`
  - `macos/Tests/DevHavenAppTests/WorkspaceShellViewTests.swift`
  - `macos/Tests/DevHavenAppTests/WorkspaceSplitViewTests.swift`
  - `macos/Tests/DevHavenAppTests/SettingsViewTests.swift`
- 验证证据：
  - `swift test --package-path macos --filter '(AppSettingsWorkspaceSidebarWidthTests|NativeAppViewModelWorkspaceSidebarWidthTests|WorkspaceShellViewTests|WorkspaceSplitViewTests|SettingsViewTests)'`
  - `swift test --package-path macos`
- 长期建议：后续如果 `AppSettings` 继续增长，建议把 workspace UI 布局相关设置抽成更聚合的 settings 子结构，避免 `SettingsView.nextSettings` 这类手工构造点持续膨胀。


## Review（GitHub release workflow 故障）

- 直接原因：最新 release workflow run `23379991100` 失败在 `Publish native release asset`，日志报错 `Validation Failed: already_exists, field: tag_name`。进一步核对 GitHub Release 发现同一个 `v3.0.0` 同时存在一个 published pre-release 和一个重复 draft release，`softprops/action-gh-release@v2` 在 arm64 matrix job 里 finalizing release 时与这个重复 draft 冲突。
- 设计层诱因：当前 `.github/workflows/release.yml` 让每个 matrix job 都直接调用 `action-gh-release` 去创建/更新/最终化 release 元数据；当仓库里存在 stale draft release 时，发布逻辑既要上传 asset 又要处理 release 状态，导致同 tag 元数据冲突被放大。
- 当前修复方案：
  - 在 release workflow 中新增 `prepare-release` job，先统一解析 tag、清理同 tag 的重复 draft release，并确保目标 release 已存在。
  - 让 `build-macos-native` matrix job `needs: prepare-release`，并改为只用 `gh release upload --clobber` 上传架构资产，不再由 matrix job 自己 finalizing release。
  - 手动删除远端重复 draft release，随后对失败 run `23379991100` 执行 rerun，成功补齐 `DevHaven-macos-arm64.zip`。
- 新增/更新验证：
  - `macos/Tests/DevHavenCoreTests/ReleaseWorkflowTests.swift`
- 验证证据：
  - `swift test --package-path macos --filter ReleaseWorkflowTests`
  - `swift test --package-path macos`
  - `gh run view 23379991100 --json status,conclusion,jobs,url` => `conclusion: success`
  - `gh release view v3.0.0 --json assets --jq '.assets[].name'` => 同时包含 `DevHaven-macos-arm64.zip` 与 `DevHaven-macos-x86_64.zip`
- 长期建议：对 release workflow 继续保持“单 job 管 release 元数据，matrix job 只传 artifact”的边界，不要再回到每个 matrix job 都直接 finalizing release 的模式。


## Review（2026-03-22 合并 notify worktree）

- 结果：已将 `notify` 分支的 5 个已提交 commit 合并到当前 `main`，并保留 `main` 上的 release workflow / 侧边栏宽度持久化改动；本地 `v3.0.0` tag 也会覆盖到新的合并提交。`notify` worktree 中未提交的 `.claude/settings.local.json` 与 `tasks/todo.md` 未纳入本次合并范围。
- 直接原因：`main` 与 `notify` 同时改动了 `WorkspaceShellView.swift`、相关测试以及 `tasks/{todo,lessons}.md`，因此自动合并时出现内容冲突；第一次手工收口时还遗漏了 `WorkspaceSidebarLayoutPolicy` 定义，导致 `swift test` 首轮编译失败。
- 设计层诱因：`tasks/todo.md` / `tasks/lessons.md` 这类长生命周期共享日志文件，以及把 `WorkspaceSidebarLayoutPolicy` 直接内嵌在 `WorkspaceShellView.swift` 末尾的组织方式，都会放大并行分支合并时的热点冲突与人工漏收口风险。未发现明显系统设计缺陷，但这两个点确实是本次合并冲突的主要放大器。
- 当前修复方案：
  1. 仅合并 `notify` 分支已提交内容，不带入 `notify` worktree 的未提交残留。
  2. 在 `WorkspaceShellView.swift` 中同时保留 `main` 的可拖拽 / 可持久化侧边栏逻辑，以及 `notify` 的 Agent signal 观察、Codex 展示态刷新与通知聚焦入口。
  3. 合并 `SettingsViewTests.swift` 与 `WorkspaceShellViewTests.swift`，同时保留侧边栏持久化和通知 / Agent 展示相关断言。
  4. `tasks/todo.md` 与 `tasks/lessons.md` 采用“保留 main 当前内容 + 追加 notify 历史记录”的方式解冲，避免丢失两边记录。
  5. 补回 `WorkspaceSidebarLayoutPolicy` 定义后重新跑完整验证。
- 长期改进建议：
  1. 若 `tasks/todo.md` / `tasks/lessons.md` 继续作为共享日志，建议按日期或任务拆分成独立文件，减少 worktree 并行开发时的同文件冲突。
  2. `WorkspaceSidebarLayoutPolicy` 这类独立策略对象可考虑单独拆文件，降低手工合并时遗漏尾部定义的概率。
- 验证证据：
  - 2026-03-22 `swift test --package-path macos` → 224 tests，5 skipped，0 failures，exit 0。
  - 2026-03-22 `swift build --package-path macos` → Build complete，exit 0。
  - 2026-03-22 `git log --oneline --decorate -n 1` → `HEAD` 为本次 merge commit。
  - 2026-03-22 `git rev-parse v3.0.0^{}` → tag 最终指向当前合并提交。


## Review（2026-03-22 强制更新远端 v3.0.0 tag）

- 结果：已将远端 `origin` 上的 `v3.0.0` tag 强制更新到当前 merge commit `a15ebe8efea6a92536c2f433162300a764f4fcea`。
- 直接原因：本地 `v3.0.0^{}` 已指向新的 merge commit，但远端 `v3.0.0^{}` 仍停留在旧提交 `8535c55c8c5af501989bde83a243103baccae928`，因此需要执行一次显式 force-push 才能覆盖远端 tag。
- 设计层诱因：tag 覆盖与分支推送是两条独立链路；仅在本地重打 annotated tag，不会自动修改远端已有 tag。未发现明显系统设计缺陷。
- 当前处理方案：执行 `git push --force origin refs/tags/v3.0.0`，随后用 `git ls-remote --tags origin refs/tags/v3.0.0 refs/tags/v3.0.0^{}` 复核远端对象与 peeled commit。
- 长期改进建议：以后凡是“覆盖现有 release tag”，都应固定做两步验证：先核对本地 `tag^{}`，再核对远端 `refs/tags/<tag>^{}`，避免只看到 tag 对象变了，却忽略真正指向的 commit。
- 验证证据：
  - 2026-03-22 `git push --force origin refs/tags/v3.0.0` → `v3.0.0 -> v3.0.0 (forced update)`，exit 0。
  - 2026-03-22 `git rev-parse HEAD` → `a15ebe8efea6a92536c2f433162300a764f4fcea`。
  - 2026-03-22 `git rev-parse v3.0.0^{}` → `a15ebe8efea6a92536c2f433162300a764f4fcea`。
  - 2026-03-22 `git ls-remote --tags origin refs/tags/v3.0.0 refs/tags/v3.0.0^{}` → `refs/tags/v3.0.0^{}` 为 `a15ebe8efea6a92536c2f433162300a764f4fcea`。


## Review（2026-03-22 推送 main 到远端）

- 结果：已将本地 `main` 推送到远端 `origin/main`，远端分支现已指向当前 merge commit `a15ebe8efea6a92536c2f433162300a764f4fcea`。
- 直接原因：本地 `main` 在推送前领先 `origin/main` 6 个提交，且当前合并结果尚未同步到远端分支。
- 设计层诱因：分支推送与 tag 覆盖彼此独立；即使前一步已经把远端 `v3.0.0` 覆盖到新提交，远端 `main` 仍不会自动前进。未发现明显系统设计缺陷。
- 当前处理方案：执行 `git push origin main`，随后通过 `git ls-remote origin refs/heads/main` 与 `git fetch origin main --quiet && git rev-parse origin/main` 双重复核远端分支指向。
- 长期改进建议：以后在“先重写 release tag，再推送主分支”的场景中，建议固定把“tag 已更新”和“branch 已更新”作为两条独立检查项，避免只更新其中一条引用。
- 验证证据：
  - 2026-03-22 `git push origin main` → `75f4d3e..a15ebe8  main -> main`，exit 0。
  - 2026-03-22 `git ls-remote origin refs/heads/main` → `a15ebe8efea6a92536c2f433162300a764f4fcea	refs/heads/main`。
  - 2026-03-22 `git fetch origin main --quiet && git rev-parse origin/main` → `a15ebe8efea6a92536c2f433162300a764f4fcea`。


## Review（2026-03-22 GitHub Action release workflow 故障）

- 结果：已定位最新失败 run `23403125653` 的直接原因，并在本地完成最小修复与回归测试。失败不在构建阶段，而是在 `prepare-release` job 的 `Remove duplicate draft releases for tag` 步骤；该步骤调用了 `gh release list --json databaseId,tagName,isDraft`，但当前 GitHub CLI 官方支持字段里没有 `databaseId`，因此脚本在真正开始清理 draft release 前就直接退出。当前本地修复已改为走 GitHub Releases REST API 列表接口，通过稳定的 `id/tag_name/draft` 字段筛选并删除重复 draft release。
- 直接原因：`.github/workflows/release.yml` 第 43 行把 `gh run list` 风格的 `databaseId` 字段误用到了 `gh release list --json ...` 上；GitHub Actions runner 上的 `gh` 直接报 `Unknown JSON field: "databaseId"`，导致 `prepare-release` 失败，后续 `build-macos-native` 整个被跳过。
- 设计层诱因：release workflow 当前把“列出 release 并拿内部 id 删除草稿”建立在 GitHub CLI 某个子命令的 JSON 字段假设上，但 `gh release list` 的字段面并不覆盖内部 release id，这使脚本对 CLI 子命令实现细节过度耦合。未发现明显系统设计缺陷，但这一步更适合直接使用 Releases REST API 这种字段语义更稳定的主接口。
- 当前修复方案：
  1. 在 `macos/Tests/DevHavenCoreTests/ReleaseWorkflowTests.swift` 新增回归断言，禁止继续依赖 `gh release list --json databaseId,...`。
  2. 将 `.github/workflows/release.yml` 中的 draft release 清理改为：`gh api --paginate "repos/${GITHUB_REPOSITORY}/releases?per_page=100" --jq '.[] | select(.tag_name == env.RELEASE_TAG and .draft == true) | .id'`。
  3. 保持后续删除逻辑仍使用 `DELETE /repos/{owner}/{repo}/releases/{id}`，只修正“如何安全拿到 release id”这一处根因点。
- 长期改进建议：
  1. 对 GitHub CLI 子命令的 `--json` 字段依赖，建议都补一个最小回归测试或改走 REST API，避免 runner 侧 CLI 字段面差异再次把 workflow 炸掉。
  2. 这类 release 元数据清理逻辑，优先依赖 GitHub 官方 REST 响应字段（`id`、`tag_name`、`draft`），不要把不同 `gh` 子命令的 JSON 字段假设互相迁移复用。
- 验证证据：
  - GitHub failed run：`https://github.com/zxcvbnmzsedr/devhaven/actions/runs/23403125653`
  - `gh run view 23403125653 --log-failed`：失败步骤报错 `Unknown JSON field: "databaseId"`，可用字段仅有 `createdAt/isDraft/isImmutable/isLatest/isPrerelease/name/publishedAt/tagName`。
  - 2026-03-22 `gh release list --limit 1 --json databaseId,tagName,isDraft`：本地直接复现同样报错 `Unknown JSON field: "databaseId"`。
  - 2026-03-22 `swift test --package-path macos --filter ReleaseWorkflowTests`（修复前）→ 3 tests 中 1 failure，失败点为新增回归测试。
  - 2026-03-22 `swift test --package-path macos --filter ReleaseWorkflowTests`（修复后）→ 3 tests，0 failures，exit 0。
  - 2026-03-22 `gh api --paginate "repos/zxcvbnmzsedr/devhaven/releases?per_page=100" --jq '.[] | select(.tag_name == "v3.0.0" and .draft == true) | .id'` → exit 0，说明修复后采用的查询路径在当前环境可正常执行。


## 历史记录（notify 分支）

- [x] 梳理 DevHaven 当前工作区/终端状态流，确认通知增强切入点与受影响文件
- [x] 补齐设计文档、实现计划文档与 tasks/todo.md 执行清单
- [x] 按 TDD 为 Bridge/运行时状态/侧边栏通知体验编写失败测试并验证失败
- [x] 实现通知事件采集、运行状态聚合、设置项与 UI 交互
- [x] 更新相关文档与 AGENTS.md，同步任务状态与 Review
- [x] 运行测试/构建验证并整理结果
- [x] 复跑提交前验证并整理本次通知增强提交

## Review

- 结果：已为 DevHaven 引入工作区通知增强链路，覆盖 Ghostty desktop notification / progress / bell 事件、ViewModel 运行时注意力状态、侧边栏 bell / spinner / popover、系统通知与提示音设置、通知回跳对应 tab / pane。
- 直接原因：原实现只桥接标题、路径、渲染状态等基础终端信息，缺少通知事件与任务活动状态的应用层收口。
- 设计层诱因：工作区运行时注意力状态此前未集中建模，导致侧边栏、系统通知与 pane 聚焦之间缺少统一的数据流。
- 当前修复方案：新增 `WorkspaceNotificationModels.swift`、`WorkspaceNotificationPresenter.swift`、`WorkspaceNotificationPopover.swift`，扩展 `GhosttySurfaceBridge` / `GhosttySurfaceHostModel` / `NativeAppViewModel` / `WorkspaceProjectListView` / `SettingsView`，并同步更新 `AGENTS.md` 与计划文档。
- 长期改进建议：后续可补系统通知点击深链回跳、关闭 pane 时更细粒度清理运行态、以及通知历史持久化或 AI 语义归纳，但当前未发现明显系统设计缺陷。
- 验证证据：
  - 2026-03-22 `swift test --package-path macos` → 156 tests，5 skipped，0 failures，exit 0
  - 2026-03-22 `swift build --package-path macos` → Build complete，exit 0

## 2026-03-22 已打开项目列表显示分支

- [x] 探查“已打开项目”列表现状，确认当前分支数据来源与现有 UI 落点
- [x] 与用户逐步确认展示范围与交互预期
- [ ] 提出可选方案，完成设计并获得确认
- [ ] 补设计文档 / 实现计划，按 TDD 落地修改
- [ ] 运行验证并补充 Review 证据

## 2026-03-22 屏蔽 Command+N 默认新建窗口

- [x] 探查当前菜单 / 快捷键实现并确认 `⌘N` 来源
- [x] 按 TDD 补失败测试并验证默认 `newItem` 尚未被覆盖
- [x] 实现命令组覆盖，移除“新建窗口”菜单入口并屏蔽 `⌘N`
- [x] 运行验证并在 Review 记录证据

## Review（2026-03-22 屏蔽 Command+N 默认新建窗口）

- 结果：已在 `DevHavenApp.swift` 中显式使用 `CommandGroup(replacing: .newItem)` 覆盖系统默认 New Window 命令组，移除菜单中的默认“新建窗口”入口，并阻断 `⌘N` 继续触发新顶层窗口。
- 直接原因：当前 `WindowGroup` 默认暴露了 macOS 的 New Window 行为，但 DevHaven 当前产品模型是单主窗口 + 内部标签页 / 分屏，不应继续继承系统默认多窗口语义。
- 设计层诱因：窗口层与工作区 tab 层的职责边界此前没有在菜单命令层显式收口，导致系统默认“新建窗口”语义泄漏到当前单窗口产品模型中。
- 当前修复方案：补充 `DevHavenAppCommandTests` 先验证缺少 `newItem` 覆盖时测试失败，再以最小改动覆盖默认命令组；不改绑 `⌘N`，也不改动现有“新建标签页”入口与 Ghostty `new-tab` 链路。
- 长期改进建议：若未来要正式支持多主窗口，应单独设计窗口恢复、焦点、工作区归属与状态同步策略；当前未发现明显系统设计缺陷，但菜单语义需要继续与单窗口模型保持一致。
- 验证证据：
  - 2026-03-22 `swift test --package-path macos --filter DevHavenAppCommandTests` → 1 test，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos` → 157 tests，5 skipped，0 failures，exit 0
  - 2026-03-22 `swift build --package-path macos` → Build complete，exit 0

## 2026-03-22 调研 cmux 会话状态与内容感知实现

- [x] 阅读 cmux 目录结构与约束，定位会话状态 / 内容感知相关入口
- [x] 梳理 cmux 中状态采集、事件传输、存储与 UI 消费链路
- [x] 对照 DevHaven 当前通知链路，总结可借鉴点、差异与接入建议
- [x] 回填 Review，记录直接原因、设计诱因、结论与证据

## Review（2026-03-22 调研 cmux 会话状态与内容感知实现）

- 结果：已确认 cmux 的“会话状态 + 内容感知”不是单靠 Ghostty 通知完成，而是由三条链路组合而成：① 启动时注入 shell integration 与环境变量；② 通过本地 socket 持续上报 shell / git / PR / 端口等运行时状态；③ 对 Claude Code 再额外包一层 `claude` wrapper + hooks，从结构化 hook JSON 与 transcript 中提炼语义状态和摘要内容。
- 直接原因：cmux 不把“会话状态感知”寄托在终端渲染层，而是主动给 shell / agent 进程植入可回传的控制面。
- 设计层诱因：如果只有终端 bell / desktop notification / progress 这类被动事件，应用层拿到的只是离散提醒，缺少统一状态源、稳定会话标识和语义化内容通道；这正是 DevHaven 当前通知链路的边界。未发现明显系统设计缺陷，但当前设计职责只覆盖“提醒呈现”，尚未扩展到“会话观测”。
- 当前结论：
  - `Sources/GhosttyTerminalView.swift`：为每个 surface 注入 `CMUX_WORKSPACE_ID` / `CMUX_PANEL_ID` / `CMUX_SOCKET_PATH`，并为 zsh/bash 注入自定义 shell integration。
  - `Resources/shell-integration/cmux-zsh-integration.zsh`：在 `preexec` / `precmd` 中异步发送 `report_shell_state`、`report_pwd`、`report_tty`、`ports_kick`、`report_git_branch`、`report_pr`。
  - `Sources/TerminalController.swift`：提供 socket 命令入口，收口到 `Workspace.statusEntries` / `metadataBlocks` / `logEntries` / `progress` / `panelShellActivityStates` 等运行时模型；高频路径通过 `SocketFastPathState` 去重并尽量 off-main。
  - `Resources/bin/claude` + `CLI/cmux.swift`：用 wrapper 给 Claude 注入 `--session-id` 与 hooks；`cmux claude-hook` 处理 `session-start` / `prompt-submit` / `pre-tool-use` / `notification` / `stop` / `session-end`，并把状态映射成 `Running` / `Needs input` / `Idle`，同时读取 transcript JSONL 提炼最后一条 assistant message 作为通知正文。
  - `surface.read_text` / `read-screen`：cmux 另提供按需文本读取能力，通过 `ghostty_surface_read_text` 读取 viewport / scrollback 文本，供自动化、会话快照和补充感知使用，但它不是 Claude 状态感知主链。
- 长期改进建议：
  1. DevHaven 若要做“会话状态”，优先补一条轻量 shell integration / local socket 通道，而不是继续堆通知事件。
  2. 若目标是 Claude / Codex 等 agent 语义状态，优先做 wrapper + hooks + session store，直接消费结构化生命周期事件。
  3. 若目标是“补全文本上下文”，可把 DevHaven 现有 `GhosttySurfaceView.debugVisibleText()` 演进成正式只读 API，用于按需抓取 viewport / scrollback，但不要把它当唯一状态源。
- 验证证据：
  - 2026-03-22 阅读 `cmux/Sources/GhosttyTerminalView.swift`、`cmux/Resources/shell-integration/cmux-zsh-integration.zsh`、`cmux/Sources/TerminalController.swift`、`cmux/CLI/cmux.swift`、`cmux/Sources/Workspace.swift`
  - 2026-03-22 对照 `DevHaven/macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceBridge.swift` 与 `DevHaven/macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceView.swift`

## 2026-03-22 调研 GitHub 上可借鉴的 Claude/Codex 运行状态感知项目

- [x] 搜索 GitHub 上与 Claude / Codex 运行状态感知相关的项目
- [x] 读取候选仓库 README / 关键实现说明，筛掉不相关方案
- [x] 总结最值得借鉴的实现模式、优缺点与对 DevHaven 的启发
- [x] 回填 Review，记录结论与来源证据

## Review（2026-03-22 调研 GitHub 上可借鉴的 Claude/Codex 运行状态感知项目）

- 结果：已确认 GitHub 上与“Claude/Codex 是否正在运行、是否等待输入、是否完成”最相关的开源实现大致分为四类：① Claude hooks → 本地状态文件 / Darwin 通知 / 菜单栏应用；② Claude hooks → 终端 tab / tmux 状态栏；③ Codex 由于 lifecycle hooks 仍不完整，社区普遍采用 `notify` + 进程轮询混合方案；④ 更大一层的 session manager 会抽象出统一事件协议（`session.start/running/waiting/stop`）。
- 直接原因：Claude 生态已经有较成熟的 hooks 入口，因此“运行 / 等待 / 完成”判断多数走结构化事件；Codex 当前社区反馈仍缺少同等级 lifecycle hooks，所以很难只靠官方事件流完成稳定状态机。
- 设计层诱因：如果状态采集完全依赖终端内容分析，会很脆弱；如果只依赖完成通知，又拿不到“正在运行 / 等待权限”两种关键中间态。因此最稳定的项目普遍采用“官方 hooks/notify + 本地状态缓存 + 进程/TTY 补偿”的组合式设计。未发现明显系统设计缺陷，但 GitHub 现状说明 DevHaven 若想同时支持 Claude 与 Codex，必须接受多信号源架构。
- 当前结论：
  - `gmr/claude-status`：最像 DevHaven 目标形态的 macOS 原生菜单栏方案；Claude hooks 写 `.cstatus` 文件，再用 Darwin notification + 文件监听 + 轮询做三重同步。
  - `JasperSui/claude-code-iterm2-tab-status`：最小可用信号链；Claude hooks → JSON signal file → iTerm2 adapter → tab 状态，明确区分 running / idle / attention。
  - `samleeney/tmux-agent-status`：目前对 Claude/Codex 双支持最直接；Claude 用 hooks，Codex 用 `pgrep` 判断 working、用 `notify` 判断 done，是非常值得借鉴的混合补偿方案。
  - `usedhonda/cc-status-bar`：提出了通用会话事件协议 `session.start / running / waiting / stop`，并把 `session_id / cwd / tty / summary / attention` 作为标准字段，适合作为 DevHaven 自己的 runtime event schema 参考。
  - `nielsgroen/claude-tmux`：通过 pane 内容模式匹配来判定 working / idle / waiting，说明“纯内容分析”可行但更脆弱，适合作为最后兜底，不适合作为主链。
  - `Nat1anWasTaken/agent-notifications`、`dazuiba/CCNotify`、`jamez01/claude-notify`：更偏 notification adapter，但能直接参考 Claude hooks / Codex `notify` 的配置方式与事件落盘思路。
  - `openai/codex` issue/discussion：社区仍在推动“等待用户回答/权限时也能发明确信号”，说明 Codex 侧暂不宜假设有完整 hooks 生命周期。
- 长期改进建议：
  1. DevHaven 可优先借鉴 `claude-status` / `cc-status-bar`：定义通用 session event 协议，而不是把状态直接耦合到某个 agent。
  2. Claude 先走 hooks 主链；Codex 先走 `notify` + 进程轮询 / TTY 关联的混合方案，后续再平滑切换到官方 hooks。
  3. 纯终端内容分析只作为 fallback：适合无 hooks / notify 的 agent，但不要拿它做主真相源。
- 验证证据：
  - 2026-03-22 阅读 GitHub 仓库 `gmr/claude-status`、`JasperSui/claude-code-iterm2-tab-status`、`samleeney/tmux-agent-status`、`usedhonda/cc-status-bar`、`nielsgroen/claude-tmux`、`Nat1anWasTaken/agent-notifications`、`dazuiba/CCNotify`、`jamez01/claude-notify`
  - 2026-03-22 阅读 GitHub 讨论 / issue：`openai/codex` Discussion #2150、Issue #10081、Issue #13478

## 2026-03-22 规划 Agent 会话状态感知（Claude / Codex）

- [x] 整理已确认设计，落盘为设计文档
- [x] 生成可执行的分步实现计划文档
- [x] 在 tasks/todo.md 回填 Review，记录规划结论与产物路径

## Review（2026-03-22 规划 Agent 会话状态感知（Claude / Codex））

- 结果：已产出一份经当前上下文收敛后的设计文档与一份可执行实现计划，明确 DevHaven V1 采用“wrapper / hooks -> signal 文件 -> App 监听”的最小链路，Claude 走 hooks 主链，Codex 走 wrapper 生命周期主链。
- 直接原因：当前 DevHaven 只有 Ghostty 通知链路，没有独立的 agent 生命周期观测层，因此无法可靠判断 Claude/Codex 是否正在运行、是否等待输入。
- 设计层诱因：终端提醒与 agent 会话状态来源不同，若继续把两者都堆在 Ghostty bridge 层，会导致职责混杂、状态源不稳定；本次规划通过统一 `WorkspaceAgentState` 与 signal store 把“提醒”与“会话观测”分层。未发现明显系统设计缺陷。
- 当前规划方案：
  - 设计文档：`docs/plans/2026-03-22-agent-session-status-design.md`
  - 实现计划：`docs/plans/2026-03-22-agent-session-status.md`
  - 关键落点：`WorkspaceAgentSessionModels`、`WorkspaceAgentSignalStore`、`AgentResources/bin/{claude,codex,devhaven-agent-emit}`、`NativeAppViewModel` agent 聚合、`WorkspaceProjectListView` 最小状态展示。
- 长期改进建议：
  1. V1 落地后，再根据实际稳定性决定是否演进到 socket 控制面。
  2. Codex 若后续补齐 waiting / permission 生命周期事件，应优先切到官方事件而不是继续扩展内容分析。
  3. transcript / scrollback 读取只作为补充语义来源，不要反客为主变成主状态源。
- 验证证据：
  - 2026-03-22 新增设计文档 `docs/plans/2026-03-22-agent-session-status-design.md`
  - 2026-03-22 新增实现计划 `docs/plans/2026-03-22-agent-session-status.md`

## 2026-03-22 实现 Agent 会话状态感知（Claude / Codex）

- [x] 按 TDD 补充 Agent 会话模型 / signal store / 侧边栏状态展示测试并验证失败
- [x] 实现 Core 模型、signal store 与 ViewModel 聚合
- [x] 实现 AgentResources、环境注入与 Claude/Codex wrapper / hook
- [x] 实现侧边栏最小 Agent 状态展示并同步文档
- [x] 运行完整验证并回填 Review / 验收步骤

## Review（2026-03-22 实现 Agent 会话状态感知（Claude / Codex））

- 结果：已为 DevHaven 落地 Claude / Codex Agent 会话状态感知 V1。内嵌终端现在会自动注入 wrapper / hook 资源，Claude 通过 hooks、Codex 通过 wrapper 生命周期把 signal JSON 写入 `~/.devhaven/agent-status/sessions/`，`WorkspaceAgentSignalStore` 负责监听与清理，`NativeAppViewModel` 完成 project / worktree 级聚合，侧边栏可直接显示 Agent 运行 / 等待 / 完成 / 失败状态与摘要。
- 直接原因：原有实现只有 Ghostty 通知链路，无法稳定判断 Claude / Codex 是否正在运行，也无法把“等待处理 / 已完成”这种会话状态映射到 worktree / pane。
- 设计层诱因：此前“终端提醒”和“Agent 生命周期”没有拆层，若继续把会话状态硬塞进 Ghostty bridge，就会让渲染事件、通知事件、Agent 语义状态混成一个来源不稳定的状态源。本次修复通过 `WorkspaceAgentSessionSignal` / `WorkspaceAgentSignalStore` / `NativeAppViewModel` 聚合层把会话观测从提醒呈现中独立出来。未发现明显系统设计缺陷，但原设计确实缺少独立的 Agent 观测层。
- 当前修复方案：
  - 新增 `WorkspaceAgentSessionModels.swift`、`WorkspaceAgentSignalStore.swift`，统一定义 signal schema、优先级和 signal 目录监听 / 清理策略。
  - 新增 `AgentResources/`、`DevHavenAppResourceLocator.swift`、`WorkspaceAgentStatusAccessory.swift`，把 Claude/Codex wrapper、Claude hook、signal emit 脚本与展示映射收口到 App bundle。
  - 扩展 `GhosttySurfaceHost.swift` / `GhosttySurfaceView.swift`，在终端环境注入 signal 目录 / resource 目录 / PATH，并把焦点补偿重构为可取消的延迟重试，避免后台 Task 跨 pane / 跨测试继续操作旧 window。
  - 扩展 `WorkspaceNotificationModels.swift`、`NativeWorktreeModels.swift`、`NativeAppViewModel.swift`、`WorkspaceProjectListView.swift`、`WorkspaceShellView.swift`，把 pane 级 Agent 状态聚合到 root project / worktree 侧边栏，并在项目打开 / 关闭时同步清理状态。
  - 更新 `AGENTS.md` 与设计 / 实现计划文档，记录新的目录结构、signal 文件链路与模块边界。
- 长期改进建议：
  1. Codex 如果后续补齐 waiting / permission 官方生命周期事件，优先切到官方事件，不要继续扩展 wrapper 语义猜测。
  2. Claude 侧如需更丰富摘要，可在 hooks 基础上再引入 transcript 只读提炼，但不要把 transcript 读取变成主状态源。
  3. 未来若要做历史面板，可在当前 signal store 之外增加独立 timeline store，避免污染瞬时运行态模型。
- 验证证据：
  - 2026-03-22 `swift test --package-path macos --filter WorkspaceAgentSignalStoreTests` → 2 tests，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter DevHavenAppResourceLocatorTests` → 2 tests，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter WorkspaceAgentStatusAccessoryTests` → 3 tests，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests/testWorkspaceAgentStatePrefersWaitingOverRunningInSidebar` → 1 test，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter WorkspaceAgentWrapperScriptTests` → 3 tests，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter GhosttySurfaceHostTests` → 11 tests，5 skipped，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos` → 170 tests，5 skipped，0 failures，exit 0
  - 2026-03-22 `swift build --package-path macos` → Build complete，exit 0

## 2026-03-22 修复 Agent signal store 定时清理队列重入崩溃

- [x] 依据用户提供的 crash report 定位崩溃线程与触发路径
- [x] 按 TDD 补充 signal store 在自身 queue 上重入调用的回归测试，并验证缺少保护时失败
- [x] 修复 signal store 的 queue 重入策略，避免 DispatchSource / timer 回调再触发 `queue.sync`
- [x] 运行定向验证并回填 Review / 教训

## Review（2026-03-22 修复 Agent signal store 定时清理队列重入崩溃）

- 结果：已修复 `WorkspaceAgentSignalStore` 在后台定时清理 / 目录监听回调里触发的 reentrant `queue.sync` 崩溃。现在同一个 store queue 上再次调用 `reload` / `sweepStaleSignals` 时会直接复用当前执行上下文，不再触发 libdispatch 的 `dispatch_sync called on queue already owned by current thread` trap。
- 直接原因：`DispatchSourceTimer` 和目录监听 source 都跑在 `DevHavenCore.WorkspaceAgentSignalStore` 自己的串行 queue 上，但事件回调里又调用了内部使用 `queue.sync` 的 `sweepStaleSignals` / `reload`，形成同队列重入同步。
- 设计层诱因：store 之前没有区分“外部线程安全入口”和“内部 queue 回调入口”，导致同一套 public API 同时被外部线程与 store 自己的 queue 调用时，隐式假设“调用方总在 queue 外部”。这属于并发边界设计不完整。未发现更大的系统设计缺陷，但这类 store 后续都应统一采用 on-queue 检测。
- 当前修复方案：
  - 为 `WorkspaceAgentSignalStore` 增加 queue-specific 标记；
  - 新增 `syncOnStoreQueueIfNeeded`，在当前已位于 store queue 时直接执行，否则再走 `queue.sync`；
  - 将 `currentSnapshots`、`stop()`、`reload(now:)`、`sweepStaleSignals(...)` 全部改为复用这套统一入口；
  - 补充 `performOnStoreQueueForTesting` 与回归测试，覆盖 `reload` / `sweep` 在自身 queue 上被调用的场景；
  - 在 `tasks/lessons.md` 记录本次并发边界教训。
- 长期改进建议：
  1. 后续若继续扩展 signal store，优先把“外部 API”和“queue 内部工作函数”拆得更清楚，避免再依赖隐式调用上下文。
  2. 对所有带 `DispatchSource` / `Timer` 的串行 store，统一加 queue-specific 防重入策略或显式 internal-on-queue helper，形成固定模板。
- 验证证据：
  - 用户 crash report：Thread 5 / `DevHavenCore.WorkspaceAgentSignalStore` / `dispatch_sync called on queue already owned by current thread`
  - 2026-03-22 `swift test --package-path macos --filter WorkspaceAgentSignalStoreTests` → 4 tests，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter WorkspaceAgentWrapperScriptTests` → 3 tests，0 failures，exit 0

## 2026-03-22 修复开发态系统通知初始化崩溃

- [x] 根据用户提供的 crash report 定位 `WorkspaceNotificationPresenter` 崩溃路径与运行环境
- [x] 按 TDD 补充“仅 .app bundle 才允许初始化 UserNotifications”的回归测试，并验证缺少保护时失败
- [x] 实现开发态 / 测试态下的系统通知保护与降级策略
- [x] 运行定向验证并补充 Review / 教训

## Review（2026-03-22 修复开发态系统通知初始化崩溃）

- 结果：已修复 DevHaven 在 `./dev` 开发态下触发系统通知时的主线程 abort。现在 `WorkspaceNotificationPresenter` 会先判断当前进程是否真的是带 bundle identifier 的 `.app` bundle；若不是，则不再调用 `UNUserNotificationCenter.current()`，而是按设置降级为提示音或静默跳过。
- 直接原因：当前 `./dev` 通过 `swift run --package-path macos DevHavenApp` 直接启动可执行文件，不是 `.app` bundle；在这种运行形态下调用 `UNUserNotificationCenter.current()` 会触发 UserNotifications 框架内部断言并 `abort()`。
- 设计层诱因：原实现把“运行在主线程”误当成了“可以安全调用系统通知 API”的充分条件，但系统通知实际上还依赖当前进程具备有效的 app bundle / bundle identifier。也就是说，能力可用性边界没有显式建模。未发现更大的系统设计缺陷，但开发态与打包态差异需要明确收口。
- 当前修复方案：
  - 为 `WorkspaceNotificationPresenter` 增加 `supportsSystemNotifications(...)` 与 `presentationRoute(...)`；
  - 仅当当前进程是合法 `.app` bundle 且存在 bundle identifier 时，才进入 `UNUserNotificationCenter` 链路；
  - 开发态 / 测试态若系统通知不可用，则在“系统通知 + 提示音”同时开启时退回 `NSSound.beep()`，否则 no-op；
  - 补充 `WorkspaceNotificationPresenterTests`，覆盖 `.app` / 直接可执行文件 / `.xctest` 三种形态与降级路由。
- 长期改进建议：
  1. 后续若还有依赖系统服务的 API（如 Dock、通知、权限中心），都应先抽一层“运行环境可用性判断”，不要把 bundle 假设散落在调用点。
  2. 如果后续要让开发态也支持完整系统通知，可考虑通过 `./dev` 先组装临时 `.app` 再启动，而不是继续走裸 `swift run`。
- 验证证据：
  - 用户 crash report：Thread 0 / `UNUserNotificationCenter.current()` / `WorkspaceNotificationPresenter.configuredCenter()` / `abort() called`
  - 2026-03-22 `swift test --package-path macos --filter WorkspaceNotificationPresenterTests` → 2 tests，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter SettingsViewTests` → 2 tests，0 failures，exit 0
  - 2026-03-22 `swift build --package-path macos` → Build complete，exit 0

## 2026-03-22 修复 zsh 启动后 PATH 被用户配置覆盖导致 Agent wrapper 失效

- [x] 依据用户截图与运行时进程环境定位 signal 未落盘的根因
- [x] 按 TDD 补 shell helper / zsh deferred init 回归测试，并验证缺少修复时失败
- [x] 实现 shell 级 PATH 幂等恢复，确保 `codex` / `claude` 优先命中 DevHaven wrapper
- [x] 运行定向验证并回填 Review / 教训

## Review（2026-03-22 修复 zsh 启动后 PATH 被用户配置覆盖导致 Agent wrapper 失效）

- 结果：已修复 DevHaven 内嵌 zsh 中 `codex` / `claude` 没有命中 wrapper、导致 `~/.devhaven/agent-status/sessions/` 一直没有 signal 文件、侧边栏也没有任何 Agent 状态的核心问题。现在 App 会额外注入 `DEVHAVEN_AGENT_BIN_DIR`，并在 zsh / bash shell integration 的 prompt/precmd 阶段幂等恢复 wrapper bin 目录到 PATH 前缀，即使用户 rc 文件在 startup 过程中重写 PATH，后续输入命令前也会自动恢复。
- 直接原因：虽然 `GhosttySurfaceHost` 启动 shell 时已经把 `AgentResources/bin` 放到了 PATH 最前面，但用户的 `.zshrc` / 相关初始化脚本又把 PATH 重写成自己的版本，最终执行 `codex` 时直接命中了全局 npm 安装的 `node .../bin/codex`，完全绕过了 DevHaven wrapper，所以没有 signal 落盘。
- 设计层诱因：之前默认假设“终端启动时注入的 PATH 就等于用户真正执行命令时的 PATH”，但对 zsh 这类会继续加载用户 rc 文件的 shell，这个假设不成立。Agent wrapper 如果只依赖进程启动瞬间的 PATH 注入，是不稳的。未发现更大的系统设计缺陷，但 shell 生命周期边界需要显式建模。
- 当前修复方案：
  - 新增 `AgentResources/shell/devhaven-agent-path.zsh` 与 `devhaven-agent-path.bash`，负责幂等把 wrapper bin 目录补回 PATH；
  - `GhosttyRuntimeEnvironmentBuilder` 额外注入 `DEVHAVEN_AGENT_BIN_DIR`；
  - 在 Ghostty zsh integration 的 `_ghostty_precmd`、bash integration 的 `__ghostty_precmd` 中 source 对应 helper，保证每次回到 prompt 前都恢复 PATH；
  - 补充 `WorkspaceAgentShellPathScriptTests`，覆盖 zsh helper、bash helper、zsh deferred init 三条链路。
- 长期改进建议：
  1. 后续若要支持更多 shell（fish / nushell 等），同样应采用“shell integration 阶段幂等恢复 PATH / command wrapper”而不是只依赖启动环境。
  2. 若后续需要更强鲁棒性，可继续演进为 shell function / alias wrapper 或直接在 shell integration 中暴露 `codex()` / `claude()` 包装函数，彻底摆脱 PATH 竞争。
- 验证证据：
  - 运行时证据：`~/.devhaven/agent-status/sessions/` 为空，同时 Codex 子进程环境里 `DEVHAVEN_AGENT_SIGNAL_DIR` 存在但 `PATH` 已丢失 `AgentResources/bin` 前缀，证明 wrapper 没有被命中
  - 2026-03-22 `swift test --package-path macos --filter WorkspaceAgentShellPathScriptTests` → 4 tests，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter WorkspaceAgentWrapperScriptTests` → 3 tests，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter GhosttySurfaceHostTests/testAcquireSurfaceViewInjectsAgentSignalDirectoryAndAgentResourcePath` → 1 test，0 failures，exit 0
  - 2026-03-22 `swift build --package-path macos` → Build complete，exit 0

## 2026-03-22 修复 Agent PATH helper 未把 wrapper 路径前移导致 codex 仍绕过 wrapper

- [x] 复现“Agent bin 已在 PATH 中但不在首位时，当前 helper 不会前移”的真实根因
- [x] 按 TDD 补充 zsh / bash helper 与 zsh integration 的失败测试，覆盖“路径已存在但被用户配置挤到后面”的场景
- [x] 以最小改动修复 helper：归一化 PATH、去重并强制把 Agent bin 放回首位
- [x] 运行定向验证并回填 Review / 教训

## Review（2026-03-22 修复 Agent PATH helper 未把 wrapper 路径前移导致 codex 仍绕过 wrapper）

- 结果：已修复 `devhaven-agent-path.{zsh,bash}` 在 wrapper 路径“已经存在但不在 PATH 首位”时错误 no-op 的问题。现在 helper 会先去重，再把 `DEVHAVEN_AGENT_BIN_DIR` 归一化到 PATH 第一位，因此 `codex` / `claude` 会重新优先命中 DevHaven bundle 内的 wrapper，而不是继续命中用户全局 Node / npm 安装版本。
- 直接原因：上一轮 helper 只判断“PATH 中是否已经包含 Agent bin”。当用户 `.zshrc` 把 `~/.nvm/.../bin` 顶回首位、同时保留 Agent bin 在后面时，helper 看到路径“已存在”就直接退出，导致 `type -a codex` 仍然把全局 `codex` 放在第一项。
- 设计层诱因：之前把“幂等恢复 PATH”简化成了“避免重复 prepend”，但 PATH 优先级本质上不仅是集合问题，也是顺序问题。对依赖 PATH 命中顺序的 wrapper 来说，只验证“存在”而不验证“位置”是不够的。未发现明显更大的系统设计缺陷，但 shell helper 的职责需要明确包含“顺序归一化”。
- 当前修复方案：
  - 为 zsh helper 改为基于 `path` 数组去重后，把 `DEVHAVEN_AGENT_BIN_DIR` 插回首位；
  - 为 bash helper 增加 PATH 归一化逻辑：过滤已有的 Agent bin，再重新拼接到首位；
  - 补充 `WorkspaceAgentShellPathScriptTests`，覆盖 zsh helper、bash helper、Ghostty zsh deferred init 在“Agent bin 已存在但被用户 PATH 重排到后面”场景下的回归测试；
  - 同步更新 `AGENTS.md` 与 `tasks/lessons.md`，记录“幂等 PATH 修复也必须校验顺序”的约束。
- 长期改进建议：
  1. 如果后续还出现 fish / nushell 等 shell 的 PATH 竞争问题，优先沿用“去重 + 归一化到首位”的策略，而不是只做存在性补丁。
  2. 若未来仍有用户 shell 深度改写 PATH 或命令解析顺序，可再演进为 shell function wrapper，进一步降低 PATH 竞争面。
- 验证证据：
  - 2026-03-22 `swift test --package-path macos --filter WorkspaceAgentShellPathScriptTests`：先红灯，新增 3 个回归测试分别在 zsh helper / bash helper / Ghostty zsh deferred init 场景下失败；修复后同一命令变为 7 tests，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter WorkspaceAgentWrapperScriptTests` → 3 tests，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter GhosttySurfaceHostTests/testAcquireSurfaceViewInjectsAgentSignalDirectoryAndAgentResourcePath` → 1 test，0 failures，exit 0
  - 2026-03-22 `swift build --package-path macos` → Build complete，exit 0
  - 2026-03-22 直接复现实验：`env -i PATH=\"~/.nvm/.../bin:$AGENT_BIN:/usr/bin:/bin\" ... /bin/zsh -f -c 'source devhaven-agent-path.zsh; type -a codex`，修复后第一项已变为 `.../AgentResources/bin/codex`

## 2026-03-22 修复 terminalSessionId 含 `/` 时 Agent signal 文件无法落盘

- [x] 根据用户现场报错定位 signal emit 失败路径，并确认是文件名直接拼接 `terminalSessionId` 导致
- [x] 按 TDD 补充 wrapper / signal store 回归测试，覆盖 `terminalSessionId` 含 `/` 的真实场景
- [x] 修复 signal 文件命名与清理策略，确保带 `/` 的 terminalSessionId 也能稳定写入 / 删除
- [x] 运行定向验证并回填 Review / 教训

## Review（2026-03-22 修复 terminalSessionId 含 `/` 时 Agent signal 文件无法落盘）

- 结果：已修复 `codex` wrapper 已经命中、但 `devhaven-agent-emit` 因 `DEVHAVEN_TERMINAL_SESSION_ID` 含 `/` 而无法落盘 signal JSON 的问题。现在 signal 文件名会先对 `terminalSessionId` 做稳定安全编码，再写入 `~/.devhaven/agent-status/sessions/`；`WorkspaceAgentSignalStore` 清理陈旧 signal 时也复用同一规则，因此“能写也能删”。
- 直接原因：当前 terminal session 标识已升级为类似 `workspace:uuid/session:1` 的层级语义字符串。`devhaven-agent-emit` 之前直接把它拼成 `.../sessions/<terminalSessionId>.json.tmp.$$`，shell 把其中的 `/` 当成目录分隔符，导致临时文件路径指向一个并不存在的子目录，所以报 `No such file or directory`。
- 设计层诱因：之前默认把 `terminalSessionId` 当作“只用于内存 map 的 opaque string”，但现在它同时被复用成文件系统 key。字符串 key 与文件路径 key 的约束并不相同；如果不显式做稳定编码，就会把路径分隔符语义意外泄漏到存储层。未发现明显更大的系统设计缺陷，但 signal 存储层需要明确区分“逻辑 key”和“文件名 key”。
- 当前修复方案：
  - `devhaven-agent-emit` 新增 `signal_file_name()`，对 `DEVHAVEN_TERMINAL_SESSION_ID` 做 base64-url 风格安全编码，再作为 JSON 文件名；
  - `WorkspaceAgentSignalStore.signalFileName(for:)` 复用同一命名规则，保证 stale sweep 删除文件时不会再按原始 `terminalSessionId` 误拼路径；
  - `WorkspaceAgentWrapperScriptTests` 补充 `testCodexWrapperWritesSignalWhenTerminalSessionIdContainsSlash`，直接复现用户现场那类 `workspace:.../session:1` 场景；
  - `WorkspaceAgentSignalStoreTests` 补充 `testStorePrunesStaleRunningSignalsWhenTerminalSessionIdContainsSlash`，验证 store 对同类 session id 也能正常清理；
  - 同步更新 `AGENTS.md` 与 `tasks/lessons.md`，记录“逻辑 session id 不能直接当文件名”的约束。
- 长期改进建议：
  1. 后续凡是拿 workspace / tab / pane / terminal id 做文件系统 key 的地方，都应先统一走稳定编码 helper，不要每处各自拼路径。
  2. 如果未来 signal schema 继续扩展，建议把“逻辑 key -> 存储 key”的转换抽成单独公共约束，避免脚本与 Swift 侧再次各写各的规则。
- 验证证据：
  - 用户现场报错：`devhaven-agent-emit: line 90: .../agent-status/sessions/workspace:.../session:1.json.tmp.<pid>: No such file or directory`
  - 2026-03-22 `swift test --package-path macos --filter WorkspaceAgentWrapperScriptTests`：新增 slash 场景后先红灯，报出与用户现场一致的 `No such file or directory`；修复后 4 tests，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter WorkspaceAgentSignalStoreTests`：新增 slash 场景清理测试后通过，5 tests，0 failures，exit 0
  - 2026-03-22 `swift build --package-path macos` → Build complete，exit 0
  - 2026-03-22 直接复现实验：以 `DEVHAVEN_TERMINAL_SESSION_ID='workspace:.../session:1` 调用 bundle 内 `codex` wrapper，成功在临时 `signals/` 目录生成编码后的 `.json` 文件，且文件内容里的 `terminalSessionId` 仍保留原始值


## 2026-03-22 修复 Codex 交互会话在回合完成后仍显示“正在运行”

- [x] 梳理 Codex 状态数据流，确认“进程态”与“回合态”错位的根因与可用观测点
- [x] 输出修正设计与取舍，确认采用的“等待输入/空闲”判定策略
- [x] 按 TDD 补充回归测试，覆盖 Codex 回合完成后不再显示“正在运行”
- [x] 实现最小修复并同步必要文档/任务记录
- [x] 运行定向验证并补充 Review 证据

## Review（2026-03-22 修复 Codex 交互会话在回合完成后仍显示“正在运行”）

- 结果：已将交互式 Codex 的展示语义从“纯进程态直出”修正为“signal 进程态 + App 只读展示态 override”。现在当底层 signal 仍是 `codex + running` 时，App 会读取当前 pane 可见文本：若仍看到 `Working (` 等工作中标记，则继续显示“Codex 正在运行”；若已回到交互输入态且不再有工作中标记，则侧边栏改显示“Codex 等待输入”。同时，`Codex 正在运行：Codex 正在运行` 这类重复摘要已去重。
- 直接原因：当前 Codex wrapper 只在“进程启动/进程退出”两个时刻写 signal，因此交互式 Codex 一轮任务结束但会话仍存活时，底层状态仍保持 `running`，UI 便把“进程仍活着”误展示成“当前任务仍在跑”。
- 设计层诱因：原实现把 signal 的**进程态**直接当作侧边栏的**任务回合态**，状态源与展示语义不一致；如果继续把这层语义修正塞回 signal store，又会污染底层真相源。当前修复把“进程态”和“展示态”拆开：signal store 继续只管进程态，App/UI 再按可见文本做只读修正。未发现更大的系统设计缺陷，但之前存在明显语义边界缺失。
- 当前修复方案：
  - 新增 `CodexAgentDisplayHeuristics.swift`，收口 Codex 可见文本的 `running / waiting / nil` 纯字符串规则；
  - 新增 `CodexAgentDisplayStateRefresher.swift`，由 `WorkspaceShellView` 定时触发，对打开 pane 的 `codex + running` 计算展示态 override；
  - `NativeAppViewModel` 新增 pane 级 `WorkspaceAgentPresentationOverride` 运行时存储，侧边栏 group/worktree 聚合优先消费 override，再退回 signal 原值；
  - `WorkspaceAgentStatusAccessory` 对 Codex waiting 改成“Codex 等待输入”；
  - `WorkspaceProjectListView` 对 label/summary 完全重复的场景做去重。
- 长期改进建议：
  1. 若 Codex 官方未来补齐 waiting / permission 生命周期事件，优先删除 heuristic，改回官方事件驱动；
  2. 若后续还有更多 agent 需要类似修正，建议把“进程态 -> 展示态”的适配正式抽象成 display-state adapter，而不是继续在单个视图里堆条件分支；
  3. 当前完整 `swift test --package-path macos` 仍会被现有 `GhosttySurfaceHostTests` 弱引用/焦点相关崩溃阻塞，后续应单独治理这组 Ghostty UI 测试的稳定性。
- 验证证据：
  - 2026-03-22 `swift test --package-path macos --filter CodexAgentDisplayHeuristicsTests` → 3 tests，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter WorkspaceAgentStatusAccessoryTests` → 4 tests，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests/testWorkspaceCodexDisplayOverridePrefersWaitingOverRunningSignal` → 1 test，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests/testWorkspaceCodexDisplayOverrideFallsBackToSignalAfterClear` → 1 test，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter WorkspaceProjectListViewTests` → 4 tests，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter WorkspaceShellViewTests` → 1 test，0 failures，exit 0
  - 2026-03-22 `swift build --package-path macos` → Build complete，exit 0
  - 2026-03-22 `swift test --package-path macos` → 两次均在现有 `GhosttySurfaceHostTests` 焦点/弱引用路径被 signal 10/11 打断，尚不能作为本次修复已全量绿灯的证据


## 2026-03-22 修复 worktree Agent 状态外溢到父级项目卡片

- [x] 确认父级卡片状态聚合逻辑为何吸收 worktree 的 Agent 状态
- [x] 按 TDD 补回归测试，覆盖“worktree running 不应让父级卡片显示 Agent 状态”
- [x] 以最小改动修复父级 Agent 状态聚合范围，并同步必要文档
- [x] 运行定向验证并补充 Review 证据

## Review（2026-03-22 修复 worktree Agent 状态外溢到父级项目卡片）

- 结果：已修复 worktree 的 Agent 状态向父级项目卡片冒泡的问题。现在 root project 卡片只显示 root project 自己 pane 的 Agent 状态；worktree 的 Codex/Claude 状态仅保留在对应 worktree 行，不再让父级卡片误显示“Codex 正在运行”。
- 直接原因：`NativeAppViewModel.makeGroupAgentState/makeGroupAgentSummary/makeGroupAgentKind` 之前把 `worktrees` 的 agentState/summary/kind 与 root project 一起做优先级聚合，因此任一子 worktree 进入 `running/waiting`，父级卡片也会继承该状态。
- 设计层诱因：之前把“父级卡片”误当成“整个 group 的 agent 活动总览”，但当前 UI 结构里父级卡片同时承担“root project 自身入口”的语义；子 worktree 活动冒泡到父级会破坏层级边界，让用户误以为 root project 自己在运行。未发现更大的系统设计缺陷，但聚合边界此前定义得不够清楚。
- 当前修复方案：
  - 新增回归测试 `testWorkspaceWorktreeAgentStateDoesNotBubbleToRootProjectCard`；
  - 将父级卡片的 `agentState / agentSummary / agentKind` 聚合范围收窄为 **仅 root project 自身状态**；
  - 保留 worktree 行自身的 Agent 状态展示，不影响之前的 Codex “等待输入”修正链路；
  - 同步在 `AGENTS.md` 记录“父级卡片不接收子 worktree Agent 冒泡”的约束。
- 长期改进建议：
  1. 如果未来确实需要“整个 group 的 agent 总览”，建议单独设计一个 group-level indicator，而不是复用 root project 卡片本身；
  2. 后续若还要调整 task / notification / agent 等不同层级状态的聚合规则，优先先写清“root 自身语义”和“group 汇总语义”的边界，再实现。
- 验证证据：
  - 2026-03-22 `swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests/testWorkspaceWorktreeAgentStateDoesNotBubbleToRootProjectCard` → 1 test，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests/testWorkspaceCodexDisplayOverridePrefersWaitingOverRunningSignal` → 1 test，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter WorkspaceProjectListViewTests` → 4 tests，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter WorkspaceAgentStatusAccessoryTests` → 4 tests，0 failures，exit 0
  - 2026-03-22 `swift build --package-path macos` → Build complete，exit 0


## 2026-03-22 让 worktree 行显示明确 Agent 文案

- [x] 确认 worktree 行当前只在有 summary 时显示文字，缺少 waiting/running label 的根因
- [x] 按 TDD 补回归测试，覆盖 worktree 行在无 summary 时也应显示 Agent label
- [x] 以最小改动修复 worktree 行文案展示，并同步必要文档
- [x] 运行定向验证并补充 Review 证据

## Review（2026-03-22 让 worktree 行显示明确 Agent 文案）

- 结果：已让 worktree 行在没有 summary 时也显示明确的 Agent 文案，不再只剩一个图标。现在 waiting / running / completed / failed 在 worktree 行上都会像父级卡片一样至少显示一份 label；若同时存在 summary，则显示为 `label：summary`。
- 直接原因：`WorkspaceProjectListView` 的 worktree 行此前只有在 `item.agentSummary` 非空时才渲染第二行文字；而 Codex waiting / running 这类展示态经常只有状态 label、没有 summary，于是 worktree 行看起来像“只有图标没有状态”。
- 设计层诱因：父级卡片和 worktree 行对同一份 Agent 状态采用了不一致的展示策略——父级会 fallback 到 label，worktree 行却要求必须有 summary 才显示文字，导致层级间语义表达不一致。未发现更大的系统设计缺陷，但同类状态组件应共享一致的 fallback 规则。
- 当前修复方案：
  - 为 worktree 行新增 `displayedWorktreeAgentText(...)`；
  - 无 summary 时回退显示 `agentAccessory.label`；
  - 有 summary 时显示 `label：summary`，与父级卡片保持一致。
- 长期改进建议：
  1. 若后续 Agent 状态展示继续演进，建议把“label/summary fallback”抽成共享 presenter，避免父级卡片和 worktree 行再次分叉；
  2. 如果未来想进一步压缩视觉噪音，可以再单独设计“紧凑模式”和“完整文案模式”，但语义一致性应保持不变。
- 验证证据：
  - 2026-03-22 `swift test --package-path macos --filter WorkspaceProjectListViewTests/testWorktreeRowsShowAgentLabelEvenWithoutSummary` → 1 test，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter WorkspaceProjectListViewTests` → 5 tests，0 failures，exit 0
  - 2026-03-22 `swift build --package-path macos` → Build complete，exit 0


## 2026-03-22 修复 Codex 等待输入态被错误回退成正在运行

- [x] 确认当前 waiting heuristic 过窄导致正常输入态回退成 running 的根因
- [x] 按 TDD 补回归测试，覆盖“无 fixed placeholder 但无 running marker 的 Codex 屏幕应判为 waiting”
- [x] 以最小改动修复 Codex heuristic 并同步必要文档
- [x] 运行定向验证并补充 Review 证据

## Review（2026-03-22 修复 Codex 等待输入态被错误回退成正在运行）

- 结果：已修复 Codex 正常输入态被错误回退成 `running` 的问题。现在 heuristic 会优先识别 `Working (` / `esc to interrupt` / `Starting MCP servers (` 等运行中标记；若未命中运行标记，但画面仍是 Codex TUI 且出现 `/model to change`、`model:` + `directory:` 等稳定 idle/input 特征，则判为 `waiting`，不再要求必须出现某一条固定 placeholder 文案。
- 直接原因：之前 `CodexAgentDisplayHeuristics` 的 waiting 分支只认 `Improve documentation in @filename` 这一条固定字符串，像“Write tests for @filename”或仅显示 Codex 标题卡片 + 历史对话的正常输入态都会直接漏判，最终退回底层 signal 的 `running`。
- 设计层诱因：把 waiting 判定建立在“某一个示例 placeholder”上，属于过窄的内容匹配策略；Codex 输入态的占位提示是会变的，真正稳定的应该是“是否存在 running marker”和“当前是否仍处于 Codex TUI idle/input screen”这两类更通用特征。未发现更大的系统设计缺陷，但 heuristic 设计需要优先匹配稳定结构，而不是示例文案。
- 当前修复方案：
  - 新增/扩展启发式测试，覆盖 `esc to interrupt -> running` 与“无 fixed placeholder 的 idle Codex screen -> waiting”；
  - `CodexAgentDisplayHeuristics` 改为：
    - 优先识别 `Working (`、`esc to interrupt`、`Starting MCP servers (` 等 running marker；
    - 再识别 `Improve documentation in @filename`、`Write tests for @filename`、`/model to change` 等 waiting marker；
    - 若仍在 Codex TUI 且出现 `model:` + `directory:`，也可判为 waiting。
- 长期改进建议：
  1. 后续可继续把 waiting/input 态识别抽成“结构特征优先、文案特征补充”的规则集，而不是零散字符串 if/else；
  2. 如果 Codex 官方后续提供更稳定的 idle/waiting 生命周期事件，应优先删除这层文本 heuristic，切回官方事件主链。
- 验证证据：
  - 2026-03-22 `swift test --package-path macos --filter CodexAgentDisplayHeuristicsTests` → 5 tests，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter WorkspaceAgentStatusAccessoryTests` → 4 tests，0 failures，exit 0
  - 2026-03-22 `swift build --package-path macos` → Build complete，exit 0


## 2026-03-22 升级 Codex 状态判定为混合状态机（notify + 进程态 + 活动度 fallback）

- [x] 梳理当前误判路径，确认单纯可见文本 heuristic 在长输出期间不够稳的根因
- [x] 补本轮设计文档 / 实现计划，明确 official notify + App 活动度补偿的方案
- [x] 按 TDD 补回归测试，覆盖 Codex notify、wrapper 注入与混合状态机判定
- [x] 实现 Codex notify 接入、状态机与 UI 消费调整
- [x] 运行定向验证并补充 Review / 手工验收步骤

## Review（2026-03-22 升级 Codex 状态判定为混合状态机（notify + 进程态 + 活动度 fallback））

- 结果：已把 Codex 状态判定从“wrapper 进程态 + 纯屏幕 heuristic”升级为“wrapper 进程态 + Codex 官方 notify + App 活动度 fallback”的混合状态机。现在 DevHaven 内嵌终端里的 Codex 会在会话启动时写 `running`，在 `agent-turn-complete` 时通过 `devhaven-codex-notify` 写 `waiting`，退出时再写 `completed / failed`；App 侧只在 `running / waiting` 两态之间用可见文本变化与结构特征做轻量修正，因此长输出时不再那么依赖单帧屏幕猜测。
- 直接原因：此前 Codex waiting 主要靠当前 pane 的文本 heuristic 反推，一旦长输出导致可见区域滚动、idle/running 特征混杂，UI 就容易在“实际上还在跑”和“已经回到输入态”之间误判。
- 设计层诱因：原设计缺少一条“当前回合已完成”的官方事件通道，只能把进程态和屏幕文本硬拼成展示态；这使得 `running -> waiting` 主要依赖猜测，而不是事件驱动。未发现更大的系统设计缺陷，但 Codex 链路此前确实缺少独立的 turn-complete 信号。
- 当前修复方案：
  - 新增 `AgentResources/bin/devhaven-codex-notify`，消费 Codex `notify` payload，并在 `agent-turn-complete` 时写 `codex + waiting` signal；
  - `AgentResources/bin/codex` 现在会在 DevHaven 环境内给真实 Codex 注入 `-c notify=[...]` 与 `-c tui.notifications=true`，不修改用户真实 `~/.codex/config.toml`；
  - `CodexAgentDisplayStateRefresher` 升级为带 pane 级 `lastVisibleText / lastChangedAt` 观测的混合状态机：waiting 时可因最近活动临时提升回 running；running 时只有在 idle screen 稳定一段时间后才降级为 waiting；
  - `NativeAppViewModel` 把 Codex 展示态候选从“只扫描 running pane”扩展为“扫描 running + waiting pane”，确保 notify 与 App fallback 能协同工作；
  - 同步更新 `AGENTS.md`、设计 / 实现计划文档与测试。
- 长期改进建议：
  1. 如果 Codex 后续补齐“新一轮开始”“等待审批”等更完整的官方 lifecycle 事件，应优先切到官方事件并删除活动度猜测；
  2. 当前 notify 只消费 `agent-turn-complete`，后续若官方补更多稳定 payload，可继续按最少字段增量接入；
  3. 完整 `swift test --package-path macos` 这次没有复跑，后续若要作为发布前证据，仍需连同现有 Ghostty UI 测试稳定性一起复核。
- 验证证据：
  - 2026-03-22 `swift test --package-path macos --filter WorkspaceAgentWrapperScriptTests` → 8 tests，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter CodexAgentDisplayStateRefresherTests` → 3 tests，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests/testCodexDisplayCandidatesIncludeWaitingSignals` → 1 test，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests/testWorkspaceCodexDisplayOverridePrefersWaitingOverRunningSignal` → 1 test，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter NativeAppViewModelWorkspaceEntryTests/testWorkspaceCodexDisplayOverrideFallsBackToSignalAfterClear` → 1 test，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter WorkspaceShellViewTests` → 1 test，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter CodexAgentDisplayHeuristicsTests` → 5 tests，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter WorkspaceAgentStatusAccessoryTests` → 4 tests，0 failures，exit 0
  - 2026-03-22 `swift test --package-path macos --filter WorkspaceProjectListViewTests` → 5 tests，0 failures，exit 0
  - 2026-03-22 `swift build --package-path macos` → Build complete，exit 0


## 2026-03-22 扫描 Agent 状态相关修改并提交

- [ ] 梳理当前工作区 diff 与新增文件，完成提交前代码扫描
- [ ] 运行提交前验证，确认本次修改至少通过定向测试与构建
- [ ] 回填本节 Review，记录扫描结论、风险判断与验证证据
- [ ] 整理暂存区并执行 commit

## 2026-03-22 代码审查（当前工作区改动）

- [x] 确认审查范围（当前分支未提交改动、关键模块与文档）
- [x] 建立审查清单并开始逐文件检查
- [x] 复核测试覆盖、潜在回归与架构一致性
- [x] 汇总结论并回填 Review（含风险等级与证据）

## Review（2026-03-22 代码审查：当前工作区改动）

- 结果：完成当前工作区 Agent 状态感知相关改动的代码审查，确认主链设计方向基本合理，但发现 2 个需要优先修复的问题，另有 1 条验证风险需要注意。
- 关键问题：
  1. `WorkspaceAgentSignalStore.sweepStaleSignals(...)` 只有在删除了 stale `running/waiting` signal 时才会调用 `normalizeSnapshots(...)`，导致仅有 `completed/failed` signal 的场景不会按 8 秒保留期自动回落为 `idle`。
  2. `WorkspaceAgentSignalStore.reload(...)` 当前对目录内所有 `*.json` 直接 `map(loadSignal)`；只要存在一个损坏/半旧格式 signal 文件，整次 reload 就会抛错，后续目录监听路径也会被静默吞掉，Agent 状态刷新会整体停摆。
  3. 本地复跑 `swift test --package-path macos` 当前返回 exit 1，日志在 `GhosttySurfaceHostTests` 后异常中断，说明全量验证闭环暂未稳定。
- 直接原因：signal store 的过期归一化与容错策略还不完整；它假设 signal 文件总是健康且目录事件总会持续发生。
- 设计层诱因：运行时 signal 已被设计成短生命周期状态源，但当前 store 同时承担“扫描、清理、降级、容错”职责，却没有把“定时降级”和“坏文件隔离”建成独立且稳定的内部策略。
- 当前建议：
  1. 让 `sweepStaleSignals(...)` 每次都执行 `normalizeSnapshots(...)`，而不是仅在 `removed == true` 时执行；并补充 completed/failed retention 回归测试。
  2. 让 `reload(...)` 对单个坏文件做逐个容错（记录日志并跳过坏文件，必要时移到 quarantine），避免一个坏文件拖垮整批 signal。
  3. 在修完上述问题后重新跑全量 `swift test --package-path macos`，确认不存在隐藏的并发/测试时序问题。
- 长期改进建议：若后续 signal 类型继续增加，建议把“文件发现/解码”“状态归一化”“垃圾回收”“观测通知”拆成更清晰的内部步骤，降低 store 成为多职责脆弱点的风险；当前未发现更大的系统设计缺陷，但 signal store 已经是这一轮改动的主要风险集中点。
- 验证证据：
  - 2026-03-22 `swiftc macos/Sources/DevHavenCore/Models/WorkspaceAgentSessionModels.swift macos/Sources/DevHavenCore/Storage/WorkspaceAgentSignalStore.swift /tmp/devhaven_signal_repro.swift -o /tmp/devhaven_signal_repro && /tmp/devhaven_signal_repro` → 输出 `initial=completed` / `afterSweep=completed`，证明 completed signal 未按保留期自动回落。
  - 2026-03-22 `swiftc macos/Sources/DevHavenCore/Models/WorkspaceAgentSessionModels.swift macos/Sources/DevHavenCore/Storage/WorkspaceAgentSignalStore.swift /tmp/devhaven_signal_corrupt_repro.swift -o /tmp/devhaven_signal_corrupt_repro && /tmp/devhaven_signal_corrupt_repro` → 输出 `reload=threw` / `DecodingError`，证明单个坏文件会拖垮整次 reload。
  - 2026-03-22 `swift test --package-path macos` → 当前返回 `exit 1`，日志记录于 `/tmp/devhaven_swift_test.log`，在 `GhosttySurfaceHostTests` 后异常中断。

## 2026-03-22 修复 Agent signal store 状态降级与坏文件容错

- [x] 明确修复目标、根因与最小改动边界
- [x] 编写并运行失败测试，覆盖 completed/failed 回落与坏文件容错
- [x] 实现最小修复并保持 signal store 职责清晰
- [x] 运行验证并回填 Review（含命令与输出证据）

## Review（2026-03-22 修复 Agent signal store 状态降级与坏文件容错）

- 结果：已修复 `WorkspaceAgentSignalStore` 的两个核心问题：① `completed/failed` signal 在 sweep 周期中不会自动回落为 `idle`；② 单个损坏 signal 文件会让整批 reload 直接抛错。现在 store 会在每次 sweep 后统一执行状态归一化，并在 reload 时跳过损坏的 JSON 文件，保留其余有效 snapshot。
- 直接原因：
  1. `sweepStaleSignals(...)` 之前只在删除 stale `running/waiting` signal 后才执行 `normalizeSnapshots(...)`，导致单独存在的 `completed/failed` signal 无法靠 sweep 定时降级。
  2. `reload(...)` 之前对目录内所有 `*.json` 直接批量解码，只要其中一个文件损坏，就会让整个 `reload` 抛出 `DecodingError`。
- 设计层诱因：signal store 既负责目录扫描，又负责短生命周期状态归一化；但原实现默认“状态降级依赖删除事件”“单文件失败等于整批失败”，使运行时临时状态源缺少独立的归一化与容错边界。未发现更大的系统设计缺陷，但 store 的内部容错粒度此前明显不足。
- 当前修复方案：
  1. 在 `WorkspaceAgentSignalStore.sweepStaleSignals(...)` 中移除对 `removed` 的归一化前置条件，改为每次 sweep 后都统一执行 `normalizeSnapshots(...)`。
  2. 在 `WorkspaceAgentSignalStore.reload(...)` 中改为逐文件解码；单个 JSON 文件解码失败时直接跳过，不再阻断整个 snapshot 刷新。
  3. 补充两条回归测试，分别覆盖 retention 回落与坏文件容错场景。
- 长期改进建议：
  1. 若后续仍频繁遇到坏 signal 文件，可增加 quarantine / 诊断日志，而不是长期静默跳过。
  2. `swift test --package-path macos` 目前仍会在 `GhosttySurfaceHostTests` 附近异常退出，建议后续单独排查该全量测试稳定性；当前未发现它与本次 signal store 修复存在直接耦合。
- 验证证据：
  - 2026-03-22 `swift test --package-path macos --filter WorkspaceAgentSignalStoreTests/testCompletedSignalFallsBackToIdleAfterRetentionDuringSweep`（修复前）→ exit 1，断言仍为 `completed`，summary / pid 未清空。
  - 2026-03-22 `swift test --package-path macos --filter WorkspaceAgentSignalStoreTests/testReloadSkipsMalformedSignalFilesAndKeepsValidSnapshots`（修复前）→ exit 1，抛出 `DecodingError`。
  - 2026-03-22 `swift test --package-path macos --filter WorkspaceAgentSignalStoreTests`（修复后）→ 7 tests，0 failures，exit 0。
  - 2026-03-22 `swift test --package-path macos`（修复后）→ 当前仍返回 `exit 1`；日志位于 `/tmp/devhaven_swift_test_after_fix.log`，仍在 `GhosttySurfaceHostTests` 附近异常中断。

## 2026-03-22 排查并修复全量 swift test 异常退出

- [x] 明确失败症状与当前已知线索（GhosttySurfaceHostTests 附近异常退出）
- [x] 稳定复现并收集日志、崩溃点与最小触发条件
- [x] 补失败测试或最小复现场景，验证根因
- [x] 实施最小修复并重新验证
- [x] 回填 Review（含直接原因、设计诱因、修复方案、长期建议、验证证据）

## Review（2026-03-22 排查并修复全量 swift test 异常退出）

- 结果：已修复 `swift test --package-path macos` 在 `GhosttySurfaceHostTests` 附近异常退出的问题。当前全量测试已恢复为 205 tests、5 skipped、0 failures、exit 0。
- 直接原因：
  1. `GhosttySurfaceHostTests` 里的 host model 之前没有统一调用 `releaseSurface()`，导致 Ghostty runtime surface 与后台线程在测试之间继续存活，旧 surface 事件会污染后续测试运行时。
  2. 测试窗口 teardown 之前显式调用 `window.close()`，会在 AppKit/CA 仍有未完成事务时触发额外的窗口关闭生命周期；结合这些短命测试窗口，最终在全量运行中引发 `_NSWindowTransformAnimation` 相关对象释放时崩溃。
- 设计层诱因：测试夹具生命周期没有统一收口。仓库中其他 Ghostty 测试已经显式 `releaseSurface()`，但 `GhosttySurfaceHostTests` 仍各自手写 model/window 生命周期，导致 surface 清理策略和窗口 teardown 策略分散，容易出现“单测单跑没事、整组跑崩”的隐式时序问题。未发现明显产品运行时架构缺陷，但测试夹具边界此前不够稳定。
- 当前修复方案：
  1. 在 `GhosttySurfaceHostTests.swift` 内新增 `makeManagedHostModel()`，统一为该文件中的 host model 注册 `addTeardownBlock` 并调用 `model.releaseSurface()`。
  2. 将 `makeInteractiveSurfaceView(...)` 与各个测试用例切到这套统一的 managed host model，避免 surface 在测试间泄漏。
  3. 将测试窗口 helper 的 teardown 简化为 `orderOut(nil) + contentView = nil + 移除静态持有`，删除 `window.close()`；同时给测试窗口设置 `animationBehavior = .none`，降低 AppKit 动画对象干扰。
- 长期改进建议：
  1. 后续若还有 Ghostty/AppKit 交互测试，优先抽成统一测试夹具，避免每个测试文件重复维护窗口 / surface 生命周期。
  2. 若未来发现生产代码也存在“model 析构时 surface 未释放”的真实场景，再单独为运行时代码设计安全的析构清理，而不要把测试修复直接等同于产品修复。
- 验证证据：
  - 2026-03-22 `swift test --package-path macos --filter GhosttySurfaceHostTests`（修复前）→ exit 1；日志 `/tmp/devhaven_ghostty_host_tests.log` 显示 `objc[...] Weak reference loaded ... not in the weak references table`。
  - 2026-03-22 诊断报告 `~/Library/Logs/DiagnosticReports/xctest-2026-03-22-184128.ips` → 崩溃栈命中 `GhosttyTerminalSurfaceView.updateScrollbar(total:offset:length:)`。
  - 2026-03-22 诊断报告 `~/Library/Logs/DiagnosticReports/xctest-2026-03-22-184731.ips` → 崩溃栈命中 `_NSWindowTransformAnimation dealloc` / CA transaction runloop，指向测试窗口 teardown 生命周期。
  - 2026-03-22 `swift test --package-path macos --filter GhosttySurfaceHostTests`（修复后）→ 11 tests，5 skipped，0 failures，exit 0。
  - 2026-03-22 `swift test --package-path macos`（修复后）→ 205 tests，5 skipped，0 failures，exit 0。

## 2026-03-22 排查项目打开后的初始焦点异常

- [x] 阅读技能与项目约束，确定按系统化调试流程排查
- [x] 更新任务清单并记录本次排查范围
- [x] 定位“打开项目后焦点落在目录右侧按钮”对应 UI 与焦点链路
- [x] 分析直接原因、是否存在设计诱因，并形成结论 / 改进建议

## Review（2026-03-22 排查项目打开后的初始焦点异常）

- 结果：本轮排查先基于“目录右边那个按钮”的口述描述，误把目标控件推断成 `ProjectDetailRootView.swift` 顶部路径右侧的关闭按钮（`xmark`）。后续用户明确纠偏后，已确认真正的问题控件是左侧边栏“目录”标题右侧的目录操作按钮；因此本节结论只保留为一次中间排查记录，不再作为最终根因。
- 直接原因：
  1. 用户最初的描述不足以唯一定位控件；
  2. 我方在没有截图 / 具体控件标识的情况下，先按“目录显示在详情面板路径右侧”做了错误推断；
  3. 后续用户给出“直接放到搜索框上”的目标语义后，重新确认了真正问题位于主界面左侧边栏的目录操作按钮。
- 设计层诱因：这类“焦点落到哪个可视按钮”问题，如果只靠自然语言描述而不先对照具体视图结构，很容易把“右边那个按钮”误映射到错误的 UI 层级。未发现明显系统设计缺陷，但排查流程需要先确认控件身份再下结论。
- 当前结论：这一轮排查的主要价值是收敛出“根因属于缺少显式初始焦点策略”，但具体按钮定位在用户纠偏前是错的；最终修复与结论以“修复主界面初始焦点落到目录按钮”一节为准。
- 长期改进建议：
  1. 继续保留“先确认控件身份，再分析焦点链路”的排查顺序；
  2. 对“右边那个按钮 / 这个控件”之类模糊描述，优先要求最小补充信息或结合代码结构做多候选核对；
  3. 产品层面仍应给主界面 / 详情面板定义清晰的显式初始焦点策略，减少此类歧义。
- 验证证据：
  - 2026-03-22 用户后续明确要求“实在不知道焦点落在哪里，你就放在搜索框上面吧”，说明真实问题语义落在主界面默认焦点，而非详情面板交互。
  - 2026-03-22 最终修复与验证详见下方“修复主界面初始焦点落到目录按钮” Review。

## 2026-03-22 修复主界面初始焦点落到目录按钮

- [x] 完成设计确认，确定采用“搜索框接管初始焦点 + 目录按钮不参与默认焦点竞争”方案
- [x] 落设计文档与实现计划文档
- [x] 按 TDD 补失败测试并验证当前行为缺少显式焦点策略
- [x] 实现主界面搜索框初始焦点修复与目录按钮防抢焦点
- [x] 运行验证并回填 Review

## Review（2026-03-22 修复主界面初始焦点落到目录按钮）

- 结果：已把 DevHaven 主界面的默认初始焦点显式收口到顶部“搜索项目...”输入框，并让左侧“目录操作”按钮不再参与默认焦点竞争。应用启动进入主界面时，不再依赖系统默认 key-view 顺序猜测焦点落点。
- 直接原因：主界面此前没有定义显式初始焦点策略，导致 AppKit / SwiftUI 退回默认 key-view 顺序；左侧边栏“目录操作”按钮又是较早出现的可聚焦 chrome 控件，因此会先抢到焦点。
- 设计层诱因：主界面虽然已经有明确的主输入入口（搜索框），但“窗口激活后第一输入目标”这一交互语义没有被代码显式建模，只能依赖默认焦点链。未发现明显系统设计缺陷，但焦点策略边界此前没有收口。
- 当前修复方案：
  1. 在 `MainContentView.swift` 中新增 `@FocusState` 与 `FocusableField.search`，让搜索框拥有显式焦点绑定；
  2. 在主界面 `onAppear` 时通过异步主线程请求，把初始焦点交给搜索框；
  3. 在 `ProjectSidebarView.swift` 中给“目录操作”按钮增加 `.focusable(false)`，避免它继续参与默认焦点竞争；
  4. 补充 `MainContentViewTests` 与 `ProjectSidebarViewTests` 回归测试。
- 长期改进建议：
  1. 如果未来主界面还会新增其它主输入控件，应继续把默认焦点策略统一收口在 `MainContentView`，不要再散落到各个 sidebar / toolbar 按钮上；
  2. 若后续产品希望“从工作区返回主界面时也自动回到搜索框”，可以在同一焦点入口上继续扩展状态触发，而不是重新引入窗口级焦点猜测。
- 验证证据：
  - 2026-03-22 `swift test --package-path macos --filter MainContentViewTests/testMainContentRequestsInitialFocusForSearchField` → 失败，确认修复前缺少显式搜索框焦点策略。
  - 2026-03-22 `swift test --package-path macos --filter ProjectSidebarViewTests/testDirectoryMenuButtonDoesNotCompeteForInitialFocus` → 失败，确认修复前目录操作按钮仍参与默认焦点竞争。
  - 2026-03-22 `swift test --package-path macos --filter MainContentViewTests` → 6 tests，0 failures，exit 0。
  - 2026-03-22 `swift test --package-path macos --filter ProjectSidebarViewTests` → 5 tests，0 failures，exit 0。
  - 2026-03-22 `swift build --package-path macos` → Build complete，exit 0。

## 2026-03-22 排查并修复删除 worktree 时闪退

- [x] 在崩溃报告与现有代码中定位删除 worktree 时的崩溃链路
- [x] 判断直接原因与是否存在设计层诱因
- [x] 先补失败测试或最小复现场景，稳定约束该崩溃
- [x] 实施最小修复并保持最少改动边界
- [x] 运行验证并回填 Review（含证据）

## Review（2026-03-22 排查并修复删除 worktree 时闪退）

- 结果：已修复删除 worktree 时的 Ghostty 晚到回调闪退问题。当前 Ghostty surface 的 C callback userdata 不再直接暴露 `GhosttySurfaceBridge` 裸指针，而是改为稳定的 `GhosttySurfaceCallbackContext`；当 workspace/worktree 关闭触发 terminal surface teardown 后，晚到的 action / close / clipboard 回调会通过 context 安全判空并直接 no-op，不再命中已释放 bridge。
- 直接原因：`GhosttyRuntime.handleAction(...)` / `handleCloseSurface(...)` 之前会把 `surface userdata` 中的 `GhosttySurfaceBridge` 非持有裸指针跨 `DispatchQueue.main.async` 带到主线程；删除 worktree 时对应 pane/session 会先释放 surface/view/bridge，等主线程稍后执行晚到回调时，再按旧地址反解 bridge 就会落到悬挂对象，最终在 `GhosttySurfaceBridge.handleAction(...) -> GhosttySurfaceState.pwd.setter` 处触发 `EXC_BAD_ACCESS`。
- 设计层诱因：Ghostty C callback 生命周期此前直接耦合到短命的 Swift bridge/view 对象，userdata 既承担“回调入口”又隐含“对象仍存活”的假设，导致跨线程 hop 与 teardown 并发时没有稳定的中间宿主。未发现更大的系统设计缺陷，但 callback 生命周期边界此前没有收口。
- 当前修复方案：
  1. 新增 `GhosttySurfaceCallbackContext` 作为 surface userdata 的稳定宿主，线程安全持有当前 active bridge；
  2. `GhosttyRuntime` 的 action / close / clipboard 回调统一先解析 callback context，跨线程时只捕获 context，等真正执行时再读取 active bridge；
  3. `GhosttyTerminalSurfaceView.tearDown()` 开始时先 invalidation callback context，再继续 unregister/free surface，让 teardown 开始后的晚到回调统一 no-op；
  4. 补充 `GhosttySurfaceCallbackContextTests`，约束 active/invalidate 语义与异步 hop 场景。
- 长期改进建议：
  1. 后续新增 Ghostty runtime callback 时，继续沿用 callback context 模式，不要再把 `Unmanaged.passUnretained(short-lived object)` 的裸指针直接跨队列传递；
  2. 若未来 callback 类型继续增长，可考虑再把“userdata 解析 + active bridge 判定”收口成更统一的 helper，减少重复 fromOpaque 入口。
- 验证证据：
  - 2026-03-22 `swift test --package-path macos --filter GhosttySurfaceCallbackContextTests`（修复前）→ exit 1，编译报错 `cannot find type 'GhosttySurfaceCallbackContext' in scope`，确认失败测试先建立。
  - 2026-03-22 `swift test --package-path macos --filter GhosttySurfaceCallbackContextTests`（修复后）→ 2 tests，0 failures，exit 0。
  - 2026-03-22 `swift test --package-path macos --filter 'GhosttySurface(CallbackContext|BridgeTabPane|Host)Tests'` → 17 tests，5 skipped，0 failures，exit 0。
  - 2026-03-22 `swift test --package-path macos` → 228 tests，5 skipped，0 failures，exit 0。


## 2026-03-22 修复 release workflow arm64 测试时序脆弱性

- [x] 复核最新 release workflow 失败日志，确认仅 arm64 `swift test` 失败
- [x] 定位失败测试与直接原因，确认属于 AppKit firstResponder 异步时序脆弱而非 release workflow 逻辑回归
- [x] 参考现有可通过路径，将固定等待改为条件轮询，实施最小测试修复
- [x] 运行定向测试验证两条脆弱测试在本地通过
- [x] 运行完整 `swift test --package-path macos` 验证没有引入回归
- [x] 提交并推送测试稳定性修复到 `origin/main`
- [x] 重新触发 `release.yml(tag=v3.0.0)` 并验证 run / release 资产

## Review（2026-03-22 修复 release workflow arm64 测试时序脆弱性）

- 结果：已确认 release workflow 前两个工作流级故障已分别通过 `2a5555a` 与 `64e1b2a` 修复；当前剩余失败点收敛为 arm64 runner 上两条 AppKit 测试的固定等待时长不足。本轮先把测试等待从固定睡眠改为条件轮询，避免 CI 机器较慢时在真正状态达成前过早断言。
- 直接原因：
  1. `GhosttySurfaceHostTests.testRequestFocusRetriesWhenFirstResponderAssignmentMissesFirstAttempt` 依赖 `RunLoop.main.run(until: now + 0.2)`，CI arm64 机器上补焦点第二次尝试未必在 0.2 秒内完成；
  2. `ProjectDetailPanelCloseActionTests.testClosingDetailPanelReleasesActiveEditorResponderBeforeHidingPanel` 同样用固定 `0.3` 秒等待 firstResponder 释放和右侧面板关闭；
  3. 两条测试都把“时间足够久”误当成“状态已经满足”，因此在慢机上出现假失败。
- 设计层诱因：测试代码把 AppKit 异步 firstResponder / 面板关闭链路建模成固定时长等待，而不是等待明确条件成立，导致验证依赖机器速度。未发现明显系统设计缺陷，但测试同步策略此前没有收口为条件驱动。
- 当前修复方案：
  1. 在两条测试里把固定 `RunLoop.main.run(until:)` 改为 `waitUntil(...)` 条件轮询；
  2. `GhosttySurfaceHostTests` 等待“焦点补偿至少执行两次且 firstResponder 已切回 terminal view”；
  3. `ProjectDetailPanelCloseActionTests` 等待“编辑器已释放 firstResponder 且详情面板状态已关闭”；
  4. 保持生产代码不变，只修测试同步方式。
- 长期改进建议：
  1. 后续凡是验证 AppKit / SwiftUI 异步状态流转的测试，优先统一为条件等待 helper，而不是分散写固定 sleep；
  2. 若类似等待逻辑继续增多，可提取测试公共 helper，减少不同测试文件各自维护轮询实现。
- 验证证据：
  - 2026-03-22 `gh run view 23403375014 --log-failed` 日志定位到 arm64 job 失败测试：`GhosttySurfaceHostTests.testRequestFocusRetriesWhenFirstResponderAssignmentMissesFirstAttempt` 与 `ProjectDetailPanelCloseActionTests.testClosingDetailPanelReleasesActiveEditorResponderBeforeHidingPanel`。
  - 2026-03-22 `swift test --package-path macos --filter 'GhosttySurfaceHostTests/testRequestFocusRetriesWhenFirstResponderAssignmentMissesFirstAttempt|ProjectDetailPanelCloseActionTests/testClosingDetailPanelReleasesActiveEditorResponderBeforeHidingPanel'` → 2 tests，0 failures，exit 0。
  - 2026-03-22 `swift test --package-path macos` → 226 tests，5 skipped，0 failures，exit 0。
  - 2026-03-22 `git push origin main`：将提交 `662f9411df5612f73a5943d92de603b142c70f76` 推送到 `origin/main`。
  - 2026-03-22 `git tag -fa v3.0.0 -m "v3.0.0" HEAD && git push origin refs/tags/v3.0.0 --force`：本地 / 远端 `v3.0.0^{}` 均已指向 `662f9411df5612f73a5943d92de603b142c70f76`。
  - 2026-03-22 `gh run view 23403723188 --json status,conclusion,jobs,url` → `status=completed`、`conclusion=success`，`prepare-release` / `build-macos-native (x86_64, macos-26, x86_64-apple-macosx14.0)` / `build-macos-native (arm64, macos-26)` 全部成功。
  - 2026-03-22 `gh release view v3.0.0 --json assets` → 产物包含 `DevHaven-macos-arm64.zip`、`DevHaven-macos-x86_64.zip`。

## 2026-03-22 提交删除 worktree 闪退修复并重新覆盖 v3.0.0

- [x] 核对当前工作区改动、已有验证证据与本地 tag 现状
- [ ] 复跑提交前验证，确认当前改动可提交
- [ ] 提交当前修复到 `main`
- [ ] 将 `v3.0.0` 覆盖到新提交并推送 branch/tag
- [ ] 观察 GitHub Actions / release 状态并回填 Review

## Review（2026-03-23 升级方案对标调研：cmux / supacode / ghostty）

- 结果：已对比 cmux、Supacode、Ghostty 三个 macOS 原生项目的升级主链，并回到 DevHaven 当前发布形态给出建议。结论是：**不要直接在当前 `swift build + 手工拼 .app + zip 上传` 链路上硬接完整升级功能**；更稳的路径是先补齐 release-grade 打包基座（至少单调递增 build number、Sparkle 运行所需 bundle 结构、Developer ID 签名 / notarization、appcast 发布顺序），再上最小可用的 Sparkle 升级能力。三者里最值得借鉴的是 **Ghostty 的“资产先上传、appcast 最后发布”操作顺序** + **cmux 的“单调 build number / 稳定 nightly/stable feed 管理”**；Supacode 的 delta / history / merged appcast 方案更强，但对 DevHaven 当前阶段偏重。
- 直接原因：DevHaven 当前 release workflow 只产出 `DevHaven-macos-*.zip` 并上传到 GitHub Release，`macos/scripts/build-native-app.sh` 仍把 `CFBundleVersion` 固定写成 `1`，且没有 `SUPublicEDKey` / `SUFeedURL` / Sparkle framework / notarization / appcast 主链，因此“升级”问题本质上不是某个 UI 开关没做，而是**底层发布介质与升级协议尚未建立**。
- 设计层诱因：当前 DevHaven 把“开发态可运行”与“发布态可升级”复用为同一条轻量脚本链路；这对快速构建够用，但一旦进入自升级场景，就会把 bundle 组装、框架嵌入、签名、公钥注入、版本号语义、appcast 发布时序等多种职责挤到同一层，容易出现“能打包但不能可靠升级”的结构性问题。未发现明显系统设计缺陷，但**发布链路目前缺少独立的升级基座层**。
- 当前建议：
  1. **先学 Ghostty / cmux 的基座，不先学 Supacode 的高级玩法。** 第一阶段只做 stable channel、完整包更新、不做 delta。
  2. **把 `CFBundleVersion` 改成单调递增的构建号真相源**，不要继续固定为 `1`；`CFBundleShortVersionString` 继续表达用户可见版本（如 `3.0.0`），`CFBundleVersion` 专门用于升级比较。cmux 已明确为 Sparkle 修过“build number 落后于 appcast 导致无法升级”的问题。
  3. **为发布态引入真正的 macOS app 打包壳**（推荐 Xcode app target / project，继续复用现有 Swift Package 里的业务代码），因为 cmux / Supacode / Ghostty 的 Sparkle 集成全部建立在 Xcode app bundle、框架嵌入和单独 codesign Sparkle 组件的前提上。若继续坚持纯脚本手工拼 bundle，也要接受后续在脚本里手工拷贝并签 Sparkle.framework / Updater.app / Autoupdate / XPCServices 的复杂度。
  4. **发布顺序采用 Ghostty 模式：先上传所有安装资产，再发布 appcast。** 不要像现在一样把“发布元数据”和“可触发升级的 feed”混在一起同步暴露。最稳妥是：`DevHaven.dmg` / `DevHaven.app.zip` 先上传到稳定 URL，验活后再把 `appcast.xml` 提升为正式 feed。
  5. **初期 channel 设计用“两个 feed，少做魔法”。** stable 一个 feed；如果以后要 nightly/tip，可学 Ghostty/cmux：要么单独 nightly feed，要么再加 bundle id 区分。不要一开始就上 Supacode 那套 merged appcast + history assets + delta patch。
  6. **UI 只做最小闭环**：菜单里的“检查更新”、设置中的“自动检查 / 自动下载”即可；等发布链路稳定后，再考虑 cmux 那种自定义 popover / update logs。
- 长期改进建议：
  1. 若 DevHaven 后续稳定版 / nightly 都要长期维护，可继续向 Ghostty 靠拢：用独立静态托管（GitHub Pages / R2 / 自有域名）承载 appcast 与安装包，不再依赖 GitHub `latest/download` 语义。
  2. 若下载体积和升级频率真的成为痛点，再评估 Supacode 的 delta updates；但在当前阶段，它会显著放大发布链路复杂度与故障面。
  3. 若仍保留 GitHub Release 作为主分发面，至少把 stable release 从当前 `--prerelease` 语义中分离出来，否则未来即使接 Sparkle，`latest` / stable feed 语义也会持续混乱。
- 验证证据：
  - 2026-03-23 阅读 `DevHaven/.github/workflows/release.yml` 与 `macos/scripts/build-native-app.sh`，确认当前只上传 zip、且脚本生成的 `Info.plist` 把 `CFBundleVersion` 固定为 `1`。
  - 2026-03-23 阅读 `cmux/Resources/Info.plist`、`cmux/Sources/Update/{UpdateController,UpdateDelegate}.swift`、`cmux/scripts/{build-sign-upload,bump-version}.sh`、`cmux/.github/workflows/nightly.yml`，确认其采用 Sparkle、稳定/夜版 feed、单调 build number 与完整签名 / notarization / appcast 生成链路。
  - 2026-03-23 阅读 `supacode/supacode/Clients/Updates/UpdaterClient.swift`、`supacode/.github/workflows/{release,release-tip}.yml`，确认其采用 Sparkle + stable/tip channel + delta/history appcast 方案。
  - 2026-03-23 阅读 `ghostty/macos/Sources/Features/Update/{UpdateController,UpdateDelegate}.swift`、`ghostty/.github/workflows/{release-tag,publish-tag}.yml`、`ghostty/dist/macos/update_appcast_{tag,tip}.py`，确认其采用 Sparkle、stable/tip 分离 feed，以及“资产先上传、appcast staged 后发布”的两阶段发布顺序。



## Review（2026-03-23 升级终局方案实现）

- 结果：已为 DevHaven 落地完整的 macOS 自升级主链，覆盖客户端设置/菜单、Sparkle runtime、Sparkle vendor、本地打包元数据、stable staged appcast、nightly 独立 workflow，以及 universal 更新包合成链路。
- 直接原因：当前仓库虽然已经有原生打包能力，但缺少“客户端可消费的升级协议 + 发布侧可持续维护的固定 feed”，导致 release 只能手动下载，无法形成稳定的自升级闭环。
- 设计层诱因：原先发布主链只关心“按架构上传 zip”，没有把版本单调性、feed 固定 URL、升级签名元数据、客户端更新偏好、以及 universal 安装包这些升级系统必须收口的真相源统一起来。
- 当前修复方案：
  1. 在 `AppSettings` 中新增 `updateChannel`、`updateAutomaticallyChecks`、`updateAutomaticallyDownloads`，并保持旧配置兼容回退。
  2. 在设置页与 App 菜单增加“检查更新”入口，并接入 `DevHavenUpdateController`。
  3. 新增 `DevHavenBuildMetadata` / `DevHavenUpdateDiagnostics` / `DevHavenUpdateController`，让开发态默认禁用 updater，release `.app` 通过 Sparkle feed + 公钥启用升级。
  4. 新增 `setup-sparkle-framework.sh`、`generate-appcast.sh`、`promote-appcast.sh`、`create-universal-app.sh`，并让 `build-native-app.sh` 嵌入 `Sparkle.framework`、写入 `CFBundleVersion` / `SUFeedURL` / `SUPublicEDKey`。
  5. 重写 `.github/workflows/release.yml` 与新增 `.github/workflows/nightly.yml`：矩阵构建 arm64/x86_64，后置 job 合成 universal 包，生成 `appcast-staged.xml`，再 promote 到 `stable-appcast/appcast.xml` 与 `nightly/appcast.xml`。
  6. 同步更新 `README.md` 与 `AGENTS.md`，把 Sparkle vendor、更新设置、发布 alias feed 与 universal 打包约定写回文档。
- 长期改进建议：
  1. 当前 workflow 已预留可选 Developer ID 签名 / notarization 步骤，但仍依赖仓库 secrets；上线前应在真实 GitHub runner 上完成一次完整冒烟，确认 Sparkle key、Apple 签名与 notary 配置可用。
  2. 当前 appcast 先以完整包更新为主，`maximum-deltas=0`；若后续 nightly/stable 体积压力明显，再沿现有脚本把历史 universal 归档下载回本地生成 delta。
  3. 若以后需要更细粒度的 phased rollout 或 beta channel，可继续在 `generate-appcast.sh` 基础上增加 channel / rollout 参数，而不必再改客户端协议。
- 验证证据：
  - `bash macos/scripts/setup-sparkle-framework.sh --verify-only`
  - `bash -n macos/scripts/create-universal-app.sh`
  - `bash -n macos/scripts/generate-appcast.sh`
  - `bash -n macos/scripts/promote-appcast.sh`
  - `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release.yml"); YAML.load_file(".github/workflows/nightly.yml"); puts "workflows ok"'`
  - `swift test --package-path macos --filter 'AppSettingsUpdatePreferencesTests|SettingsViewTests|DevHavenAppCommandTests|DevHavenBuildMetadataTests|NativeBuildScriptUpdateSupportTests|ReleaseWorkflowTests|ReleaseWorkflowUpdateInfrastructureTests'`
  - `swift test --package-path macos`
  - `swift build --package-path macos`
  - `bash macos/scripts/build-native-app.sh --release --no-open --skip-sign --output-dir /tmp/devhaven-native-app-updater --build-number 3000001 --sparkle-public-key test-public-key`
  - `plutil -p /tmp/devhaven-native-app-updater/DevHaven.app/Contents/Info.plist | rg 'CFBundleVersion|SUFeedURL|DevHavenStableFeedURL|DevHavenNightlyFeedURL|SUPublicEDKey|DevHavenDefaultUpdateChannel'`
  - `test -d /tmp/devhaven-native-app-updater/DevHaven.app/Contents/Frameworks/Sparkle.framework`

## 2026-03-23 修复 Nightly 默认升级通道回退 stable

- [x] 核实 Nightly 构建默认升级通道未闭环的直接原因与影响链路
- [ ] 设计 bundle 默认通道与持久化设置的收口方案，并获得确认
- [ ] 先补失败测试，覆盖 fresh install / legacy settings 对默认通道的行为
- [ ] 实施最小修复，确保 Nightly 首次启动默认跟随 nightly feed
- [ ] 运行定向验证并在本文件追加 Review



## Review（2026-03-23 无苹果账号升级模式收口）

- 结果：已把 DevHaven 的升级体验收口为“无苹果开发者账号可正式交付”的形态：正式 `.app` 现在默认采用 `manualDownload` 交付模式，应用内可继续 stable / nightly 检查更新、导出诊断、打开下载页，但不会再把自动安装更新作为默认承诺。
- 直接原因：用户当前没有 Apple Developer Program 账号，无法提供 Developer ID 签名与 notarization，因此继续把 Sparkle 自动安装当成默认交付路径，会让客户端能力与实际分发信任链不一致。
- 设计层诱因：上一版虽然已经补齐 Sparkle runtime / appcast / workflow 主链，但客户端仍把“支持检查更新”和“支持自动安装更新”混成一个布尔语义，缺少无账号场景下的正式 fallback 模式。
- 当前修复方案：
  1. 新增 `DevHavenUpdateDeliveryMode`，并在 `AppMetadata.json` / `Info.plist` 中写入 `manualDownload`、stable/nightly 下载页 URL。
  2. `DevHavenBuildMetadata` 改为区分 `supportsUpdateChecks` 与 `supportsAutomaticUpdates`：正式 `.app` + feed 存在即可检查更新；只有 `automatic` 模式且存在 `SUPublicEDKey` 时才允许自动安装。
  3. 新增 `DevHavenAppcastParser`，在 manual-download 模式下直接读取 appcast，解析最新版本、build、下载链接 / release notes 链接。
  4. `DevHavenUpdateController` 新增 manual-check 分支：保留“立即检查更新”，检查到新版本后给出“请打开下载页完成更新”，并支持 `openDownloadPage()`。
  5. `SettingsView` 新增“打开下载页”按钮，并在自动下载不可用时禁用“自动下载更新”开关。
  6. 同步更新 `README.md` 与 `AGENTS.md`，明确默认交付模式是 manual-download，未来补齐 Apple Developer ID / notarization 后再切到 `automatic`。
- 长期改进建议：
  1. 以后如果补齐 Apple Developer 账号，可直接把 `AppMetadata.json` 的 `updateDeliveryMode` 切到 `automatic`，并在 CI 配置 Developer ID / notarization secrets；当前主链无需重写。
  2. 当前 manual-download 模式主要依赖 appcast 的最新条目与下载页 fallback；若后续要做更精细的“跳过版本 / phased rollout / 增量提醒”，可继续沿 appcast 解析层演进，而不必回退到 GitHub API 特判。
- 验证证据：
  - `swift test --package-path macos --filter 'DevHavenBuildMetadataTests|DevHavenAppcastParserTests|SettingsViewTests|NativeBuildScriptUpdateSupportTests'`
  - `bash macos/scripts/setup-sparkle-framework.sh --verify-only`
  - `bash -n macos/scripts/build-native-app.sh`
  - `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release.yml"); YAML.load_file(".github/workflows/nightly.yml"); puts "workflows ok"'`
  - `bash macos/scripts/build-native-app.sh --release --no-open --skip-sign --output-dir /tmp/devhaven-native-app-manual --build-number 3000002`
  - `plutil -p /tmp/devhaven-native-app-manual/DevHaven.app/Contents/Info.plist | rg 'CFBundleVersion|SUFeedURL|DevHavenStableFeedURL|DevHavenNightlyFeedURL|DevHavenUpdateDeliveryMode|DevHavenStableDownloadsPageURL|DevHavenNightlyDownloadsPageURL|SUPublicEDKey'`
  - `test -d /tmp/devhaven-native-app-manual/DevHaven.app/Contents/Frameworks/Sparkle.framework`
  - `swift test --package-path macos`
  - `swift build --package-path macos`

## 2026-03-23 直接添加为项目无反应排查
- [x] 梳理“直接添加为项目”入口与调用链
- [x] 复现并收集运行时证据
- [x] 对比可用路径与失败路径，定位根因
- [x] 更新任务状态并写入 Review

## Review（2026-03-23 直接添加为项目无反应排查）
- 结果：已定位“直接添加为项目”出现‘选目录后没有任何反应’的核心问题：这条链路对**被静默过滤的目录**没有任何错误提示。当前最典型的静默过滤场景是所选目录其实是 Git worktree；其次是目录元数据读取失败（例如权限 / 安全作用域在真正构建项目前已经失效）。
- 直接原因：`ProjectSidebarView.handleDirectoryImport(...) -> performDirectoryImport(..., .addProjects) -> NativeAppViewModel.addDirectProjects(...) -> buildProjects(...) -> createProject(...)` 这条链路里，`createProject(...)` 会在两种情况下直接返回 `nil`：
  1. `isGitWorktree(projectURL)` 为 true；
  2. `resourceValues.isDirectory` 读取失败或不是目录。
  `addDirectProjects(...)` 随后仍会静默继续，不抛错、不弹窗，因此用户只会看到“点了添加但没变化”。
- 设计层诱因：存在明显的交互 / 责任边界缺陷。导入链路把“记录 directProjectPaths”和“真正构建可展示项目”混在一起，但没有把‘路径被过滤’作为显式结果返回 UI；因此业务层知道要丢弃，界面层却拿不到失败原因，只能表现成无反馈。另一个诱因是 `importedPaths(from:)` 在拿到路径字符串后立即停止 security-scoped access，若后续运行环境需要持续权限，真正的目录检查会在更后面静默失败。
- 当前修复方案建议：
  1. 在 `addDirectProjects` / `buildProjects` 返回结构化结果（成功数、被忽略路径、忽略原因）；
  2. 对 worktree 明确提示“该目录是 Git worktree，请从根项目进入或走 worktree 流程”；
  3. 对目录不可访问明确提示“无法读取目录元数据/权限不足”；
  4. 若需要 security-scoped URL，应把访问范围覆盖到真正完成目录校验与项目构建，而不是只包住 `path()` 提取。
- 长期改进建议：
  1. 给“直接添加为项目”补最小回归测试，覆盖 worktree / 不可访问目录的显式报错；
  2. 统一‘目录导入’结果模型，避免其它导入入口继续出现“业务失败但 UI 没提示”的静默失败；
  3. 若产品上不打算支持 direct add worktree，菜单或文件选择说明里应提前写清限制，而不是让用户试完才发现没有反馈。
- 验证证据：
  - 代码调用链：`macos/Sources/DevHavenApp/ProjectSidebarView.swift:301-347`、`macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift:1117-1133`、`2053-2104`、`2177-2191`
  - 本机状态文件：`~/.devhaven/app_state.json` 当前已有 `directProjectPaths = ['/Users/zhaotianzeng/.codex']`，说明该功能并非完全不可用，而是对某些路径类型会静默失败。
  - 本地 worktree 复现：临时仓库 `/tmp/devhaven-direct-add-2aQ3lC` 中 `wt/.git` 内容为 `gitdir: /private/tmp/devhaven-direct-add-2aQ3lC/repo/.git/worktrees/wt`，与 `isGitWorktree(...)` 的判定条件完全吻合，因此此类目录会在 `createProject(...)` 中被直接过滤掉。

## 2026-03-23 目录移除能力修复

- [x] 定位“添加目录后不可移除”的直接原因与影响范围
- [x] 先补能稳定复现该问题的失败测试
- [x] 以最小改动实现目录移除能力
- [x] 运行定向验证并补充 Review（含直接原因/设计诱因/修复方案/长期建议）

## Review（2026-03-23 目录移除能力修复）

- 直接原因：
  1. `ProjectSidebarView` 的“目录”分区只提供了添加与刷新入口，用户添加的工作目录行没有任何减号 / 移除动作；
  2. `NativeAppViewModel` 只实现了 `addProjectDirectory(_:)`，没有对称的 `removeProjectDirectory(_:)`，导致 UI 就算想提供入口也无业务 API 可调用。
- 设计层诱因：
  1. 目录来源配置（`app_state.json.directories`）和当前项目快照（`snapshot.projects` / `projects.json`）虽然都存在，但“移除来源后如何重建目录快照”此前没有被收口成一条对称链路；
  2. 特别是当最后一个目录被移除时，现有 `refreshProjectCatalog()` 会因“没有任何来源目录 / 直接项目”而直接返回，如果没有额外清空逻辑，就会把旧项目快照残留在内存和磁盘里。
  3. 未发现明显系统设计缺陷，但“添加有链路、移除没链路”确实是这次缺陷的直接诱因。
- 当前修复方案：
  1. 在 `NativeAppViewModel` 新增 `removeProjectDirectory(_:) async throws`，负责：
     - 更新并持久化 `app_state.json.directories`；
     - 若当前正选中被删除目录，则把筛选回退到 `.all`；
     - 若已无任何目录来源与直接项目，则同步清空 `projects.json` / `snapshot.projects`；
     - 否则走现有 `refreshProjectCatalog()` 重建项目目录快照。
  2. 在 `ProjectSidebarView` 中，仅对用户添加的目录行（非系统项“全部 / 直接添加”）显示 `minus.circle` 移除按钮，并直接调用 `viewModel.removeProjectDirectory(...)`。
  3. 新增回归测试覆盖：
     - 目录行存在移除动作；
     - 移除目录后会持久化配置、清空项目快照、回退目录筛选，且不会删除磁盘原目录。
- 长期改进建议：
  1. 继续把“项目来源配置变更后如何重建 / 清空项目快照”抽成统一 helper，减少 direct project / scanned directory 两条链路未来再次分叉；
  2. 后续可补一条 UI 层交互测试，验证点击目录减号后的行为，而不只做源码结构断言。
- 验证证据：
  - `swift test --package-path macos --filter DevHavenCoreTests.NativeAppViewModelTests/testRemoveProjectDirectoryPersistsUpdatedDirectoriesAndClearsSelectedDirectoryFilter`
  - `swift test --package-path macos --filter DevHavenAppTests.ProjectSidebarViewTests/testUserAddedDirectoryRowsExposeRemoveAction`
  - `swift test --package-path macos` → 244 tests，5 skipped，0 failures

## 2026-03-23 添加工作目录/直接添加项目无反应修复

- [x] 复核两条导入链路（添加工作目录 / 直接添加为项目）的共同入口与直接原因
- [x] 先补可稳定复现“导入后无反馈”的失败测试
- [x] 以最小改动修复导入无反应问题
- [x] 运行定向验证与全量验证，并在 Review 记录根因/诱因/修复/证据

## Review（2026-03-23 添加工作目录/直接添加项目无反应修复）

- 直接原因：
  1. 成功导入后，`ProjectSidebarView` 没有自动切换到新导入内容对应的筛选：添加工作目录后不选中新目录，直接添加项目后也不切到“直接添加”，因此新增内容很容易被当前筛选状态遮住，表现成“选完目录没任何反应”。
  2. `NativeAppViewModel` 之前会把 Git worktree 根目录静默写进 `directories` / `directProjectPaths`，但后续构建项目时又把 worktree 过滤掉，结果就是配置被写了、列表却没变化，用户没有任何明确反馈。
- 设计层诱因：
  1. 导入链路缺少“路径校验 + 结构化结果”这一层，导致“能否真正导入成项目”和“是否写入来源配置”没有统一收口；
  2. 另一个实现诱因是 `ProjectSidebarView` 之前只在 `importedPaths(from:)` 中短暂持有 security-scoped URL，再在真正导入前就释放访问权限，这会增加文件选择器导入在部分环境下的脆弱性。这里属于基于代码路径的实现分析，不是单独复现出的唯一根因，但本次一并收口了。
  3. 未发现明显系统设计缺陷，但导入验证、来源持久化与 UI 反馈之间确实存在边界断裂。
- 当前修复方案：
  1. 在 `NativeAppViewModel` 增加导入前目录校验，若选中的是 Git worktree 或不可访问目录，直接抛出中文错误，阻止静默写入无效来源。
  2. `addDirectProjects(_:)` 现在只持久化真正可导入的项目路径；当全部路径都不可导入时，会明确报错而不是“看起来什么都没发生”。
  3. `ProjectSidebarView` 现在会在整个导入执行期间保持 security-scoped access，并在成功后主动切换到：
     - 新增工作目录对应的目录筛选；
     - 或“直接添加”筛选。
  4. 新增回归测试覆盖：
     - 直接添加 worktree 必须报错，且不能静默写入 directProjectPaths；
     - 添加工作目录命中 worktree 根目录必须报错，且不能静默写入 directories；
     - 导入成功后必须切换到对应筛选，避免“无反应”。
- 长期改进建议：
  1. 后续可把“导入结果”升级为明确的数据结构（成功项 / 忽略项 / 警告项），而不是继续让 ViewModel 通过 `errorMessage` 承担全部 UI 反馈；
  2. 若未来继续使用系统文件选择器导入目录，建议把 security-scoped URL 处理抽成统一 helper，避免其它导入入口再次出现“先拿 path、后释放权限、真正读取时才失败”的问题。
- 验证证据：
  - `swift test --package-path macos --filter DevHavenCoreTests.NativeAppViewModelTests/testAddDirectProjectsRejectsGitWorktreePathInsteadOfSilentlyPersistingInvalidSource`
  - `swift test --package-path macos --filter DevHavenCoreTests.NativeAppViewModelTests/testAddProjectDirectoryRejectsGitWorktreeRootInsteadOfPersistingEmptyDirectorySource`
  - `swift test --package-path macos --filter DevHavenAppTests.ProjectSidebarViewTests/testSuccessfulImportSelectsImportedFilterToAvoidNoReaction`
  - `swift test --package-path macos` → 247 tests，5 skipped，0 failures

## 2026-03-23 导入链路日志埋点

- [x] 盘点当前导入链路与现有日志基础设施，确定日志落点
- [x] 先补回归测试，约束导入链路包含关键日志埋点
- [x] 以最小改动为 fileImporter / 目录校验 / 持久化结果补统一日志
- [x] 运行定向验证并在 Review 记录日志点、查看方式与证据

## Review（2026-03-23 导入链路日志埋点）

- 结果：已为“添加工作目录 / 直接添加为项目”链路补齐统一的 `ProjectImport` unified log，日志前缀统一为 `[project-import]`，并覆盖 fileImporter 回调、security-scoped access、真正导入尝试、目录校验、持久化成功、筛选切换和失败原因。
- 直接原因：
  1. 用户反馈“还是没有反应”后，现有代码虽然已有部分行为修复，但缺少足够的运行时观测点，无法快速判断问题是卡在文件选择器回调、URL 权限、路径校验、配置持久化还是筛选切换。
  2. 原先 unified log 只有 workspace launch 相关诊断，没有项目导入专项诊断。
- 设计层诱因：
  1. 导入是一条跨 UI / 文件权限 / ViewModel / 存储层的多边界链路，没有结构化日志时，任何一步静默失败看起来都会像“没反应”；
  2. 未发现明显系统设计缺陷，但可观测性此前明显不足。
- 当前修复方案：
  1. 新增 `macos/Sources/DevHavenCore/Diagnostics/ProjectImportDiagnostics.swift`，统一输出 `subsystem=DevHavenNative`、`category=ProjectImport` 的日志。
  2. `ProjectSidebarView` 在以下节点打日志：
     - importer 成功回调收到多少个 URL；
     - security-scoped access 请求数 / 实际授予数；
     - 真正开始导入的 action / paths；
     - 失败时的错误；
     - 成功后应用了哪个筛选。
  3. `NativeAppViewModel` 在以下节点打日志：
     - 每个导入路径校验 accepted / rejected；
     - 工作目录持久化成功；
     - 直接导入项目 requested / accepted / rejected / total 汇总。
- 查看方式：
  - 开发态推荐直接运行：`./dev --logs app`
  - 然后在输出里搜：`[project-import]`
  - 若要单独看导入日志，也可直接运行：
    `log stream --style compact --level debug --predicate 'subsystem == "DevHavenNative" && category == "ProjectImport"'`
- 验证证据：
  - `swift test --package-path macos --filter DevHavenCoreTests.ProjectImportDiagnosticsTests`
  - `swift test --package-path macos --filter DevHavenAppTests.ProjectSidebarViewTests/testImportFlowRecordsDiagnosticsAtImporterBoundary`
  - `swift test --package-path macos --filter DevHavenCoreTests.NativeAppViewModelTests/testAddDirectProjectsRejectsGitWorktreePathInsteadOfSilentlyPersistingInvalidSource`
  - `swift test --package-path macos` → 249 tests，5 skipped，0 failures

## 2026-03-23 fileImporter 动作丢失修复

- [x] 根据用户日志确认 action=unknown 的直接原因与触发链路
- [x] 先补失败测试，约束 fileImporter dismiss 不得提前清空导入动作
- [x] 以最小改动修复导入动作状态丢失
- [x] 运行定向验证并在 Review 记录日志证据与修复结果

## Review（2026-03-23 fileImporter 动作丢失修复）

- 结果：已确认并修复 `fileImporter` 导致的导入动作丢失问题。根据用户提供的 live 日志：
  - `[project-import] importer-callback action=unknown urlCount=1`
  - `[project-import] security-scope action=unknown requested=1 granted=1`
  可知目录 URL 已成功返回且权限也拿到了，但在回调执行时动作类型已经被提前清空，因此后续无法判断该走“添加工作目录”还是“直接添加为项目”链路。
- 直接原因：
  1. `ProjectSidebarView` 之前把 `pendingDirectoryImportAction` 同时用作：
     - fileImporter 是否展示的状态；
     - 导入完成后要执行哪条链路的动作类型。
  2. `.fileImporter(isPresented: Binding(... set: { if !$0 { pendingDirectoryImportAction = nil } }))` 会在 importer dismiss 时先把 `pendingDirectoryImportAction` 清空，导致 `handleDirectoryImport(...)` 回调执行时 `action == nil`，日志里就表现为 `action=unknown`。
- 设计层诱因：
  1. “展示态”与“业务动作态”被错误地耦合在同一个状态变量上，这是典型的状态源职责不清；
  2. 未发现明显系统设计缺陷，但这属于明确的状态建模错误。
- 当前修复方案：
  1. 新增独立状态 `isDirectoryImporterPresented`，仅表示 fileImporter 是否展示；
  2. `pendingDirectoryImportAction` 只保存业务动作，不再由 `isPresented` setter 隐式清空；
  3. 现在的顺序改为：
     - 点击菜单项时：先写入 `pendingDirectoryImportAction`，再置 `isDirectoryImporterPresented = true`
     - `handleDirectoryImport(...)` 回调时：先读取 action，再清理状态
  4. 因此后续日志中的 `action=unknown` 应该消失，并出现明确的 `action=add-directory` 或 `action=add-projects`。
- 长期改进建议：
  1. 所有“弹窗是否展示”和“弹窗完成后要执行什么动作”都应拆成两个独立状态，不要再复用一个 optional 状态做双重职责；
  2. 若未来继续扩展导入入口，建议直接把导入动作抽成可测试的 request model，避免 UI state 再次吞掉业务语义。
- 验证证据：
  - `swift test --package-path macos --filter DevHavenAppTests.ProjectSidebarViewTests/testFileImporterPresentationStateDoesNotClearPendingActionBeforeCompletion`
  - `swift test --package-path macos --filter DevHavenAppTests.ProjectSidebarViewTests/testImportFlowRecordsDiagnosticsAtImporterBoundary`
  - `swift test --package-path macos --filter DevHavenAppTests.ProjectSidebarViewTests/testSuccessfulImportSelectsImportedFilterToAvoidNoReaction`
  - `swift test --package-path macos` → 250 tests，5 skipped，0 failures

## 2026-03-23 v3.0.2 整理代码与发布

- [x] 盘点当前工作区改动、版本真相源与远端基线
- [x] 记录本次计划到 docs/plans 与 tasks/todo.md
- [x] 整理当前 ProjectSidebarView 最近改动，收口目录行代码
- [x] 升级版本到 3.0.2 并同步 build number / README
- [x] 运行 macOS 相关验证并记录 Review 证据
- [ ] 提交本次变更、创建 v3.0.2 tag、push 分支与 tag

## Review（2026-03-23 v3.0.2 整理代码与发布）

- 结果：已将仓库版本真相源升级到 `3.0.2` / `3002000`，并收口 `ProjectSidebarView` 中用户目录行的渲染职责。当前目录行仍保持整行点击、hover 显示移除动作与既有删除语义不变。
- 直接原因：
  1. `ProjectSidebarView` 目录列表里，用户目录行的“整行选择 + 移除目录”逻辑直接内嵌在 `ForEach` 中，渲染细节与业务动作混在父视图里，可读性和后续维护性都偏差。
  2. 当前仓库版本真相源仍停留在 `3.0.1` / `3001000`，与本次发布目标 `v3.0.2` 不一致。
- 设计层诱因：
  1. 目录行的局部交互职责没有收口到单独组件，父视图承担了过多行内渲染细节；
  2. 未发现明显系统设计缺陷，当前更多是局部职责边界和发布元数据未及时推进的问题。
- 当前修复方案：
  1. 抽出 `DirectoryRowView`，把用户目录行的 hover/移除交互封装在单独视图中；
  2. 将目录移除按钮改为与选择按钮并列的 `ZStack` 结构，并在非 hover 时禁用 hit testing，避免把交互建立在嵌套按钮之上；
  3. 更新 `macos/Resources/AppMetadata.json` 中的 `version=3.0.2`、`buildNumber=3002000`；
  4. 更新 `README.md` 首页版本徽章到 `3.0.2`。
- 长期改进建议：
  1. 如果目录行、标签行、普通 sidebar 行后续继续分化，可以进一步抽象共享的 sidebar row 样式层，避免视觉参数再次散落；
  2. 后续每次 release 准备都可固定检查 `AppMetadata` 与 README 徽章，避免版本展示与构建真相源再次漂移。
- 验证证据：
  - `swift test --package-path macos` → `250 tests, 5 skipped, 0 failures`

## 2026-03-23 macOS quarantine 运行门槛排查

- [x] 查看本地打包脚本中的签名方式与默认行为
- [x] 查看 release/nightly workflow 的 Developer ID / notarization 条件分支
- [x] 结合现有 Review 与文档，确认当前发布包为何需要移除 quarantine 才能运行
- [x] 在 Review 中记录直接原因、设计层诱因、当前建议与验证证据

## Review（2026-03-23 macOS quarantine 运行门槛排查）

- 结论：当前 DevHaven 发布包之所以常需要用户手动执行 `xattr -r -d com.apple.quarantine`，不是因为 macOS 对所有第三方 App 都“必须这样”，而是因为 **下载得到的 `.app` 会带 quarantine 属性，而 DevHaven 当前发布链路默认又没有稳定补齐 Apple Developer ID 签名 + notarization 信任链**；因此 Gatekeeper 会把它当作未建立可信来源的互联网下载应用拦下。
- 直接原因：
  1. `macos/scripts/build-native-app.sh` 默认只做本地 `ad-hoc` 签名：`codesign --force --deep --sign -`，这不等于 Developer ID 签名，也不能替代 notarization。
  2. `.github/workflows/release.yml` / `nightly.yml` 中的 Developer ID 签名与 notarization 都是“可选步骤”；当相关 secrets 缺失时，workflow 会直接输出“跳过 Apple 代码签名 / 跳过 notarization”并继续发布。
  3. `macos/scripts/create-universal-app.sh` 是先复制 arm64 `.app` 再 `lipo` 替换主可执行文件；如果后续没有重新签名，universal `.app` 的签名会失效。
  4. 用户从 GitHub Release / 浏览器下载 zip 后，解压得到的 `.app` 会保留 `com.apple.quarantine`；一旦应用缺少可验证的 Apple 信任链，首次启动就会被 Gatekeeper 阻止。
- 设计层诱因：
  1. 当前发布链路把“是否完成 Apple 信任链”设计成可选项，因此即使签名/公证缺失也能继续产出并发布面向终端用户的安装包；这会让“可下载”与“可直接在 macOS 上无提示运行”之间出现落差。
  2. 未发现明显系统设计缺陷；但发布验收目前更偏向构建成功与资产上传成功，对“终端用户首次安装是否能在保留 quarantine 的前提下直接通过 Gatekeeper”这条证据还不够强约束。
- 当前建议：
  1. 短期：如果继续分发当前这类未完成信任链的包，至少应在下载说明里明确提示用户可能需要右键“打开”或移除 quarantine；通常不建议把 `sudo xattr ...` 当作默认安装步骤公开要求。
  2. 中期：补齐 `APPLE_DEVELOPER_ID_*` 与 `APPLE_NOTARY_*` secrets，让 workflow 对 universal `.app` 重新签名、notarize 并 staple。
  3. 长期：把“面向用户发布”与“Apple 信任链完成”绑定；若 secrets 缺失，应阻止正式 release 对外发布，避免继续产出需要用户手工绕过 Gatekeeper 的安装包。
- 验证证据：
  - `macos/scripts/build-native-app.sh` 第 340-343 行：默认执行 `codesign --force --deep --sign -`（ad-hoc 签名）。
  - `.github/workflows/release.yml` 第 275-276 行：缺少 Developer ID secrets 时输出“未配置 Developer ID 签名 secrets，跳过 Apple 代码签名。”。
  - `.github/workflows/release.yml` 第 303-304 行：缺少 notary secrets 时输出“未配置 notary secrets，跳过 notarization。”。
  - `.github/workflows/nightly.yml` 第 250-251、278-279 行：nightly 同样在 secrets 缺失时跳过签名与 notarization。
  - `macos/scripts/create-universal-app.sh` 第 107-110 行：复制 arm64 `.app` 后执行 `lipo -create` 替换主可执行文件，若不重新签名会破坏已有签名。
  - `README.md` 第 163 行：文档已明确当前正式构建默认采用 `manual-download`，未来补齐 Apple Developer ID / notarization 后才切到 `automatic`。

## 2026-03-23 会话恢复终局方案调研（Ghostty / Supacode / cmux）

- [x] 梳理 DevHaven 当前终端/工作区状态模型与会话恢复相关约束
- [x] 检索 Ghostty、Supacode、cmux 是否已有会话恢复实现、边界与实现线索
- [x] 基于调研结果给出 DevHaven 终局会话恢复方案（非 MVP）

## Review（2026-03-23 会话恢复终局方案调研）

- 结论：
  1. **Ghostty** 在 macOS 上已实现窗口级 state restoration，但只覆盖 window / split tree / focused surface / quick terminal screen state 这一类宿主层状态；没有为 DevHaven 直接提供“关闭 App 后继续保活 shell 进程并重连”的能力。
  2. **cmux** 已实现更完整的 app-level session snapshot：窗口 / workspace / pane 布局、工作目录、terminal scrollback（best effort）、browser history，并有 autosave / startup restore / display geometry remap；但 README 已明确它**不恢复 live terminal process state**。
  3. **Supacode** 当前未见完整会话恢复实现；代码里主要持久化 repository roots / pinned / archived / 排序 / last focused worktree，且退出提示明确写着“会关闭所有 terminal sessions”。
  4. 对 DevHaven 而言，若目标是“关闭 App 后会话真正恢复回来”，**仅做 snapshot 不够**；根因是当前 Ghostty pane 生命周期与子 shell 进程生命周期仍然 1:1 耦合。终局方案必须把“pane 里的真实会话”移到 App 进程之外，由独立 session backend 持有。
- 直接原因：
  1. DevHaven 当前 `openWorkspaceSessions` / `GhosttyWorkspaceController.projection` 仅存在内存，没有独立的 workspace restore store；重启后天然丢失。
  2. `GhosttySurfaceHostModel` 创建的是直接承载 shell 的 `GhosttyTerminalSurfaceView`；`GhosttyTerminalSurfaceView.tearDown()` 会 `ghostty_surface_free(surface)`，因此当前 pane 销毁时并没有“detach but keep process alive”的中间层。
  3. `WorkspaceTerminalLaunchRequest` 当前只携带 `workingDirectory + environment`，没有“attach 到既有后台会话”的启动协议。
- 设计层诱因：
  1. 存在明显的状态源与生命周期耦合问题：UI 拓扑（项目 / tab / pane）与 terminal 进程生命周期混在同一条 Ghostty surface 链路上，导致无法单独保活 pane 状态。
  2. 未发现明显系统设计缺陷；但当前架构确实缺少一层“会话真相源”（session daemon / attach protocol / restore manifest），这是不能实现终局恢复的关键缺口。
- 终局方案方向：
  1. 项目 / tab / pane 布局采用 **cmux 风格的独立 snapshot store**；
  2. pane 内真实 shell / agent / TUI 状态采用 **DevHaven 自己的持久会话后端（推荐 session daemon）** 脱离 App 进程保活；
  3. 若后台会话缺失，再回退到“同 cwd + best-effort scrollback replay”的降级恢复。
- 验证证据：
  - Ghostty：`ghostty/macos/Sources/Features/Terminal/TerminalRestorable.swift`、`QuickTerminalRestorableState.swift`、`TerminalController.swift`、`LastWindowPosition.swift`
  - cmux：`cmux/Sources/SessionPersistence.swift`、`Workspace.swift`、`TabManager.swift`、`AppDelegate.swift`、`cmuxTests/SessionPersistenceTests.swift`、`README.md` 的 `Session restore (current behavior)` 段落
  - Supacode：`supacode/Clients/Repositories/RepositoryPersistenceClient.swift`、`Features/Repositories/Reducer/RepositoriesFeature.swift`、`Features/App/Reducer/AppFeature.swift`
  - DevHaven：`macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`、`GhosttyWorkspaceController.swift`、`WorkspaceTopologyModels.swift`、`GhosttySurfaceHost.swift`、`GhosttySurfaceView.swift`

## 2026-03-23 非 live 工作区快照恢复实现

- [x] 落盘实现计划文档并记录本次实现任务
- [x] 先为恢复快照模型与存储层补失败测试
- [x] 实现恢复快照模型、存储层与主/回退 manifest 读写
- [x] 先为工作区拓扑导出/恢复补失败测试
- [x] 实现 GhosttyWorkspaceController / WorkspaceSessionState 的恢复快照导出与重建
- [x] 先为 pane 上下文快照与展示提示补失败测试
- [x] 实现 pane 快照采集、恢复提示与 fresh shell cwd 恢复
- [x] 先为启动恢复 / 自动保存协调补失败测试
- [x] 实现 WorkspaceRestoreCoordinator、ViewModel 集成与应用生命周期 flush
- [x] 更新 AGENTS / 设计文档并完成全量验证

## Review（2026-03-23 非 live 工作区快照恢复实现）

- 结果：
  1. DevHaven 已具备 **非 live 工作区快照恢复**：重启后可恢复已打开项目、每个项目的 tab/pane 布局，以及 pane 的 cwd / 标题 / 文本快照提示。
  2. 恢复后的 pane 一律启动 fresh shell，不恢复原终端进程；不会额外展示恢复提示弹窗。
  3. 运行期变更已接入自动保存：打开/关闭项目、切换 active project、tab/pane 拓扑变化，以及应用进入 `inactive/background` / `willTerminate` 时都会刷新快照。
- 直接原因：
  1. 之前只有运行时 `NativeAppViewModel -> GhosttyWorkspaceController -> WorkspaceSessionState` 状态，没有独立的工作区恢复快照模型和持久化层；
  2. pane 的 cwd / 标题 / 可见文本只存在 App 运行内存，没有 bridge 回 Core 层参与恢复；
  3. 启动时 `load()` 不会读取任何 workspace restore manifest，退出时也没有统一 flush。
- 设计层诱因：
  1. 旧实现把工作区状态完全视为内存态，没有“关闭 App 后重建上下文”的明确真相源；
  2. 未发现明显系统设计缺陷；本次通过把恢复职责收口到 `WorkspaceRestoreStore + WorkspaceRestoreCoordinator + NativeAppViewModel`，避免继续在 App/UI/Storage 多点散落补丁。
- 当前修复方案：
  1. 新增 `WorkspaceRestoreSnapshot / ProjectWorkspaceRestoreSnapshot / WorkspacePaneRestoreSnapshot` 等恢复模型；
  2. 新增 `WorkspaceRestoreStore`，使用 `~/.devhaven/session-restore/manifest.json`、`manifest.prev.json` 与 `panes/*.txt` 保存主/回退 manifest 和 pane 文本；
  3. 新增 `WorkspaceRestoreCoordinator`，负责 hydrate pane 文本、自动保存节流、pane 上下文 merge，以及空工作区时删除恢复快照；
  4. `WorkspaceSessionState` / `WorkspacePaneTree` 现已支持从恢复快照重建 pane request，并把 restore context 注入 fresh shell 启动；
  5. `NativeAppViewModel` 仅在首轮 `load()` 且当前没有打开会话时应用恢复快照，避免后续 reload 覆盖运行中的 workspace；
  6. `WorkspaceShellView` 会把已加载 pane 的 `snapshotContext()` 回传给 ViewModel；`AppRootView` 在 scene 生命周期与应用终止通知上执行同步 flush。
- 长期改进建议：
  1. 如果后续要继续增强“工作上下文恢复”，可以在当前 snapshot 模型上继续补 scrollback 摘要、最近命令、手动恢复入口，但不要越界演进成 PTY/daemon 保活；
  2. 若后续需要降低写盘频率，可把 autosave debounce 与 pane 文本大小上限继续参数化，但当前先保持正确性优先。
- 验证证据：
  - `swift test --package-path macos --filter 'WorkspaceRestoreCoordinatorTests|NativeAppViewModelWorkspaceRestoreTests'` → 7 tests，0 failures
  - `swift test --package-path macos --filter 'WorkspaceRestoreStoreTests|GhosttyWorkspaceRestoreSnapshotTests|GhosttySurfaceHostModelSnapshotTests|WorkspaceRestorePresentationTests|WorkspaceRestoreCoordinatorTests|NativeAppViewModelWorkspaceRestoreTests'` → 17 tests，0 failures
  - `swift test --package-path macos` → 273 tests，5 skipped，0 failures
  - `swift build --package-path macos` → `Build complete! (2.31s)`，exit 0

## 2026-03-23 恢复上下文提示弹窗移除

- [x] 盘点恢复提示弹窗的实现与引用点，确认最小改动范围
- [x] 先修改测试，约束恢复后不再展示提示弹窗
- [x] 移除 Ghostty 恢复提示 UI，并同步清理文档文案
- [x] 运行定向验证并追加 Review 证据

## Review（2026-03-23 恢复上下文提示弹窗移除）

- 结果：
  1. 恢复上下文快照能力保留不变：pane 仍会使用 restore context 恢复 cwd / 标题 / 文本快照。
  2. `GhosttySurfaceHost` 已不再展示“已恢复工作上下文快照 / 原终端进程未恢复”的提示弹窗。
- 直接原因：
  1. 上一版在 `GhosttySurfaceHost` 中额外叠加了一层 restore overlay，把恢复提示作为常驻 UI 展示；
  2. 这层提示不影响恢复能力本身，只是宿主层展示策略。
- 设计层诱因：
  1. 未发现明显系统设计缺陷；
  2. 这是一次产品层收口：恢复上下文是底层能力，但不一定需要显式前台提示。
- 当前修复方案：
  1. 删除 `GhosttySurfaceHost` 对 restore overlay 的渲染；
  2. 清理 `GhosttySurfaceHostModel` 中仅服务于该弹窗的展示状态；
  3. 保留 `WorkspaceTerminalRestoreContext` 与 fresh shell cwd 恢复逻辑，不动恢复主链；
  4. 同步更新 `WorkspaceRestorePresentationTests`、计划文档与 `AGENTS.md` 文案。
- 验证证据：
  - `swift test --package-path macos --filter 'GhosttySurfaceHostModelSnapshotTests|WorkspaceRestorePresentationTests'` → 4 tests，0 failures
  - `swift build --package-path macos` → `Build complete! (5.54s)`，exit 0

## 2026-03-23 非 live 工作区快照恢复提交

- [x] 复核本次 workspace snapshot restore 的代码 / 测试 / 文档改动范围
- [x] 运行 fresh 验证并确认提交前状态
- [x] 执行 git add / git commit
- [x] 追加本次提交 Review，记录提交信息与验证证据

## Review（2026-03-23 非 live 工作区快照恢复提交）

- 结果：
  1. 已将 workspace snapshot restore 主链相关源码、测试、计划文档与 AGENTS 说明整理为单次提交范围。
  2. 提交信息收口为 `feat: 支持非 live 工作区快照恢复`，避免把本轮恢复链路拆成多段零散提交。
- 验证证据：
  - `swift test --package-path macos` → 276 tests，5 skipped，0 failures
  - `swift build --package-path macos` → `Build complete! (0.39s)`，exit 0
  - `git diff --check` → 无输出

## 2026-03-23 提交 session-restore PR 到 main

- [x] 确认当前分支、main 基线与是否已有现成 PR
- [x] 运行 fresh 验证并做提交前本地 review
- [x] 推送当前分支到 origin
- [x] 创建指向 `main` 的 PR
- [x] 追加本次 PR Review，记录 PR 编号、链接与验证证据

## Review（2026-03-23 提交 session-restore PR 到 main）

- 结果：
  1. 已将 `session-restore` 分支推送到 `origin/session-restore`，并创建指向 `main` 的 PR：#34 `feat: 支持非 live 工作区快照恢复`
  2. PR 链接：`https://github.com/zxcvbnmzsedr/devhaven/pull/34`
  3. 当前 GitHub PR 状态为 `OPEN`，base=`main`，head=`session-restore`，非 draft。
  4. 本地在跑 `swift test --package-path macos` 后出现两份**未提交**测试文件脏改动：`macos/Tests/DevHavenAppTests/WorkspaceShellViewTests.swift`、`macos/Tests/DevHavenCoreTests/NativeAppViewModelWorkspaceEntryTests.swift`；它们**不在已推送的 PR 内容里**，后续需单独判断是否保留。
- 验证证据：
  - `git merge-base HEAD main` → `f93181fc66094baae3ec6cb17b1307423e4c7a21`
  - `gh pr list --head session-restore --state all --json number,title,state,url,headRefName,baseRefName`（创建前）→ `[]`
  - `swift test --package-path macos` → 276 tests，5 skipped，0 failures
  - `swift build --package-path macos` → `Build complete! (1.99s)`，exit 0
  - `git diff --check main...HEAD` → 无输出
  - `git push -u origin HEAD:session-restore` → 已创建远端分支并设置 tracking
  - `gh pr create --base main --head session-restore ...` → `https://github.com/zxcvbnmzsedr/devhaven/pull/34`
  - `gh pr view 34 --json number,title,state,url,headRefName,baseRefName,isDraft` → `state=OPEN`，`isDraft=false`

## 2026-03-23 创建 git worktree 进度弹窗未置前

- [x] 复现并定位创建 worktree 时进度弹窗未显示在最前面的直接原因
- [x] 先补失败测试或最小验证手段，约束进度弹窗在创建开始时立即置前
- [x] 实施最小修复，必要时同步更新相关文档/注释
- [x] 运行定向验证，并在 Review 中记录根因、设计诱因、修复方案与证据

## Review（2026-03-23 创建 git worktree 进度弹窗未置前）

- 结果：
  1. 创建 git worktree 后，管理对话框现在会在任务真正启动后立即退出，进度弹窗能直接显示在最前面，不再需要先手动点“取消”。
  2. 立即校验失败（例如已有任务占用锁、项目不存在）仍然保留在原对话框内返回错误；只有通过前置校验后，才切到全局进度弹窗继续展示后台进度。
- 直接原因：
  1. `WorkspaceWorktreeDialogView.submit()` 之前会一直 `await onCreateWorktree(...)` 到整个 worktree 创建流程结束；
  2. worktree 管理对话框本身是 `.sheet`，而真正的进度 UI 在 `AppRootView` 的全局 overlay 中；sheet 不退出时，全局 overlay 会被它压在下面。
- 设计层诱因：
  1. 当前链路把“前置校验/占坑”和“耗时创建/进度推进”塞进同一个 await 生命周期里，导致局部表单 sheet 持有了整段长任务的前台层级；
  2. 未发现明显系统设计缺陷；问题主要是异步交互边界没有按 UI 层级拆开。
- 当前修复方案：
  1. 在 `NativeAppViewModel` 中把创建链路拆成“同步准备阶段”与“后台执行阶段”；
  2. 新增 `startCreateWorkspaceWorktree(...)`：先完成立即可失败的校验、占坑和 `worktreeInteractionState` 建立，再把真实创建流程放到后台 Task；
  3. `WorkspaceShellView` 的创建入口改为调用该“先启动后后台执行”的 API，让 sheet 可以立刻关闭，而全局 overlay 接手展示进度；
  4. 保留原 `createWorkspaceWorktree(...)` 供需要等待完整结果的调用和既有测试使用。
- 长期改进建议：
  1. 后续凡是“局部 sheet 发起、全局 overlay 展示”的长任务，都应统一采用“先通过前置校验，再切换到全局进度态”的交互协议，避免再次出现层级互相遮挡。
- 验证证据：
  - 红灯验证：`swift test --package-path macos --filter 'WorkspaceShellViewTests|NativeAppViewModelWorkspaceEntryTests'`（实现前）→ 编译失败：`NativeAppViewModel` 缺少 `startCreateWorkspaceWorktree`
  - 绿灯验证：`swift test --package-path macos --filter 'WorkspaceShellViewTests|NativeAppViewModelWorkspaceEntryTests'` → 38 tests，0 failures
  - 构建验证：`swift build --package-path macos` → `Build complete! (0.15s)`，exit 0

## 2026-03-23 提交 worktree 进度弹窗置前修复

- [x] 复核本轮修复改动范围，确认仅包含 worktree 进度弹窗置前相关变更
- [x] 运行 fresh 验证并确认提交前状态
- [x] 执行 git add / git commit / git push
- [x] 处理 PR：若已有当前分支 PR，则更新并记录；否则创建新 PR
- [x] 在 Review 中记录提交信息、PR 信息与验证证据

## Review（2026-03-23 提交 worktree 进度弹窗置前修复）

- 结果：
  1. 已将本轮 worktree 创建进度弹窗置前修复提交为 `967615c`（`fix: 让 worktree 创建进度弹窗及时置前`），并推送到 `origin/session-restore`。
  2. 当前分支历史上已有一个已合并 PR：#34 `feat: 支持非 live 工作区快照恢复`；本轮新增 commit 推送后，已基于同一 `session-restore` 分支创建新的 PR：#35 `fix: 让 worktree 创建进度弹窗及时置前`。
  3. 新 PR 链接：`https://github.com/zxcvbnmzsedr/devhaven/pull/35`，当前状态 `OPEN`，base=`main`，head=`session-restore`，非 draft。
  4. 提交后本地工作区已 clean，没有遗留未提交改动。
- 验证证据：
  - `git diff --stat -- ...` → 仅包含 `WorkspaceShellView.swift`、`NativeAppViewModel.swift`、两份测试文件与 `tasks/{todo,lessons}.md`
  - `swift test --package-path macos` → 278 tests，5 skipped，0 failures
  - `swift build --package-path macos` → `Build complete! (0.15s)`，exit 0
  - `git diff --check` → 无输出
  - `git commit -m "fix: 让 worktree 创建进度弹窗及时置前"` → commit `967615c`
  - `git push origin HEAD:session-restore` → 远端分支从 `77957a2` 推进到 `967615c`
  - `gh pr list --head session-restore --state all --json number,title,state,url,headRefName,baseRefName,isDraft`（创建前）→ 仅发现已合并 PR #34
  - `gh pr create --base main --head session-restore ...` → `https://github.com/zxcvbnmzsedr/devhaven/pull/35`
  - `gh pr view 35 --json number,title,state,url,headRefName,baseRefName,isDraft` → `state=OPEN`，`isDraft=false`

## 2026-03-24 X 最近收藏总结

- [ ] 检查 opencli/twitter 可用能力与登录态
- [ ] 获取最近收藏内容并记录原始证据
- [ ] 输出中文总结并在 Review 记录方法、限制与结果
## 2026-03-24 发布前 commit 梳理

- [x] 确认上个发布 tag、当前 HEAD 与工作区状态
- [x] 提取上个发布 tag 到当前的 commit 列表并按主题归纳
- [x] 生成 release 摘要、建议标题与发布前检查项

## Review（2026-03-24 发布前 commit 梳理）

- 结果：
  1. 已按 **release 语义** 选取最近一个 semver tag `v3.0.2` 作为比较基线，而不是 `nightly` / `stable-appcast` 这类发布别名 tag。
  2. `v3.0.2..HEAD` 共包含 7 个 commit，其中 2 个 merge commit、5 个非 merge commit；真正值得写进 release note 的主变更集中在 3 个提交：Ghostty 搜索、非 live 工作区快照恢复、worktree 创建进度弹窗置前修复。
  3. 当前 `HEAD` 与 `origin/main` 一致，都是 `38ab435a6d38`；如果要从主线发版，远端基线已经对齐。
  4. 当前本地工作区不是 clean：存在 `tasks/todo.md` 修改，以及 `.claude/skills/`、`.iflow/`、`.opencli/`、`skills-lock.json` 未跟踪项；发布前应确认这些本地改动不进入正式 release 操作。
- 建议发布口径：
  1. 如果按 SemVer 严格执行，这一批更像 **minor release**，建议优先考虑 `v3.1.0`，因为包含两个明确的用户可见新能力，而不是纯 bugfix。
  2. 若你只是想快速滚一个保守版本，也可以发 patch，但从变更性质上说不如 minor 语义准确。
- 验证证据：
  - `git tag --list 'v*' --sort=-v:refname | head -n 5` → 最近 semver tag 为 `v3.0.2`
  - `git log --date=short --pretty=format:'%h%x09%ad%x09%s' v3.0.2..HEAD` → 共 7 条 commit，核心为 `f93181f`、`739111a`、`967615c`
  - `git diff --shortstat v3.0.2..HEAD` → `36 files changed, 3626 insertions(+), 27 deletions(-)`
  - `git log --merges --date=short --pretty=format:'%h%x09%ad%x09%s' v3.0.2..HEAD` → merge PR #34 / #35
  - `git rev-parse --short=12 origin/main` / `git rev-parse --short=12 HEAD` → 均为 `38ab435a6d38`
  - `git status --short` → 工作区存在 `tasks/todo.md` 修改及若干未跟踪本地目录/文件

## 2026-03-24 项目刷新链路排查

- [x] 定位“刷新项目”按钮对应的 ViewModel / Core 调用入口
- [x] 梳理 refresh 期间的扫描、Git 信息采集、持久化与 UI 回填链路
- [x] 结合当前 `~/.devhaven` 实际数据估算主要耗时来源
- [x] 在 Review 中记录直接原因、设计层诱因、当前结论与证据

## Review（2026-03-24 项目刷新链路排查）

- 结果：
  1. “刷新项目”最终走的是 `NativeAppViewModel.refreshProjectCatalog()`，不是简单 reload 现有内存，而是一次 **全量重建项目 catalog**。
  2. 当前实现会重新扫描 `app_state.json` 里的所有目录根（当前本机是 5 个目录根 + 4 个 direct project），重新生成完整项目列表，再整体写回 `~/.devhaven/projects.json`。
  3. 真正的慢点不在目录遍历本身，而在 **每个候选项目都顺序跑 Git 子进程**：对 Git 仓库执行 `git rev-list --count HEAD` 和 `git log -n 1` 两条命令；以当前本机 130 个项目估算，仅这一步实测就约 3.5~3.7 秒。
  4. 刷新完成后，UI 侧还会执行 selection realign，并异步重读当前选中项目的 `PROJECT_NOTES.md` / `PROJECT_TODO.md` / `README.md`，但这一段是次要成本，不是主瓶颈。
- 直接原因：
  1. `rebuildProjectCatalogSnapshot()` 每次刷新都会调用 `discoverProjects()` + `buildProjects()`，没有基于 mtime/checksum 或 git metadata 做增量跳过。
  2. `buildProjects()` 内的 `createProject()` 会对每个候选路径调用 `loadGitInfo()`；而 `loadGitInfo()` 当前是同步串行 `Process + waitUntilExit`，每个 Git 仓库固定两次 `/usr/bin/git`。
  3. `scanDirectoryWithGit()` 还会把每个目录根下的**一级子目录**直接作为项目候选加入，即使它不是 Git 仓库，也仍然会参与后续 stat / createProject 流程，扩大了刷新工作量。
- 设计层诱因：
  1. 当前 catalog refresh 的职责偏“全量重建快照”，没有拆成“发现候选项目”和“按需刷新 Git 元数据”两层，因此每次手动刷新都会做完整重算。
  2. 未发现明显系统设计缺陷，但存在一个明确的性能边界未收口：项目发现、Git 元数据采集、持久化现在被绑成一条同步重建链，导致 repo 数量一多就线性变慢。
- 当前结论：
  1. 以当前本机数据，项目刷新体感慢是**真实的**，不是 UI 假象；主要成本来自约 100+ 仓库上的 Git 子进程串行执行。
  2. 如果后续要优化，优先级最高的是：减少 Git 命令次数 / 做增量缓存 / 让 Git 元数据采集并行或延迟，而不是先纠结目录扫描和 JSON 写盘。
- 长期改进建议：
  1. 给 `Project` 引入“目录枚举结果”和“Git 元数据”两级缓存，目录没变时直接复用已有 `gitCommits/gitLastCommit/gitLastCommitMessage`。
  2. 把 Git 信息采集改成限流并发，而不是当前完全串行；并为慢仓库提供阶段性进度文案。
  3. 重新审视“一级子目录默认视为项目”的产品语义；如果不需要这么激进的发现策略，可显著降低候选数量。
- 验证证据：
  - 代码入口：`macos/Sources/DevHavenApp/ProjectSidebarView.swift` / `macos/Sources/DevHavenApp/DevHavenApp.swift` → 刷新入口都调用 `viewModel.refreshProjectCatalog()` 或 `viewModel.refresh()`
  - Core 链路：`macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift` 中 `refreshProjectCatalog()` → `rebuildProjectCatalogSnapshot()` → `discoverProjects()` / `buildProjects()` / `loadGitInfo()`
  - 当前本机配置：`~/.devhaven/app_state.json` → `directories=5`，`directProjectPaths=4`
  - 当前项目规模：`~/.devhaven/projects.json` → `projects=130`
  - 目录扫描估算：本机脚本复现 `discoverProjects` 规则 → `visited_dirs=323`，`unique_discovered_paths=126`，`elapsed_seconds=0.025`
  - Git 成本实测：对当前 130 个项目顺序执行 `git rev-list --count HEAD` + `git log -n 1` → `git_command_runs=260`，`elapsed_seconds=3.48`
  - 全链路估算：按当前 refresh 规则复现 → `discovered_paths=130`，`project_build_seconds=3.656`，`estimated_total_seconds=3.666`

## 2026-03-24 目录刷新与 Git 统计职责拆分设计

- [x] 明确“刷新目录不跑 git、旧值保留、Git 统计单独刷新”的目标边界
- [x] 梳理当前 `gitCommits > 0` 被当作 Git 真相源的影响面
- [x] 形成设计方案并写入仓库文档
- [x] 在 Review 中记录本轮设计结论与证据

## Review（2026-03-24 目录刷新与 Git 统计职责拆分设计）

- 结果：
  1. 已确认采用“**目录刷新只维护项目清单与目录元数据；Git 元数据统一由更新统计链路负责**”的新边界。
  2. 已把设计文档写入 `docs/plans/2026-03-24-directory-refresh-git-metadata-split-design.md`，明确旧项目保留旧 Git 值、新项目只做轻量 Git 判定、不在目录刷新时执行任何 Git 子进程。
  3. 设计中新增关键收口：`Project` 需要引入显式的轻量 Git 真相源（建议命名 `isGitRepository`），避免继续把 `gitCommits > 0` 误当成 repo 类型判断。
- 直接原因：
  1. 当前 `refreshProjectCatalog()` 同时负责“发现项目”和“刷新 Git 元数据”，导致一次目录刷新被昂贵 Git 子进程绑慢。
  2. 当前多处 UI / 过滤逻辑把 `gitCommits > 0` 当成 Git / 非 Git 的真相源，使得“把 Git 调用挪出目录刷新”不能只删调用，必须同时补齐类型语义。
- 设计层诱因：
  1. 现有模型把 repo 类型判断和 Git 统计结果混在同一组字段里，职责边界不清晰。
  2. 未发现明显系统设计缺陷，但存在一个持续放大性能问题的边界混淆：目录发现链路承担了不属于它的 Git 统计职责。
- 当前设计方案：
  1. 目录刷新阶段仅更新路径、名字、mtime、size、checksum、checked 与轻量 `isGitRepository` 判定；
  2. 目录刷新不再执行 `git rev-list` / `git log` 等 Git 子进程；
  3. 更新统计链路升级为统一刷新 `gitCommits`、`gitLastCommit`、`gitLastCommitMessage` 与 `gitDaily`；
  4. 旧项目目录刷新后保留旧 Git 值；新发现 Git 项目在首次统计前显示为“Git 项目但统计未刷新”。
- 长期改进建议：
  1. 在职责拆分完成后，再考虑给 Git 统计链路加限流并发和增量缓存；
  2. 后续如果用户希望更强的体感优化，可继续演进为“两阶段刷新：先出目录、再补 Git 元数据”。
- 验证证据：
  - 当前影响面检索：`rg -n "gitCommits|gitLastCommit|gitLastCommitMessage|gitDaily|refreshGitStatistics|gitStatistics" ...`
  - 关键判定点：`NativeAppViewModel.matchesAllFilters(...)`、`MainContentView.swift`、`ProjectDetailRootView.swift`、`WorkspaceHostView.swift`
  - 设计文档：`docs/plans/2026-03-24-directory-refresh-git-metadata-split-design.md`

## 2026-03-24 目录刷新与 Git 统计职责拆分实现

- [x] 落实施计划到 `docs/plans/2026-03-24-directory-refresh-git-metadata-split.md`
- [x] 先补 Core 失败测试，覆盖目录刷新保留旧 Git 值 / 新增 `isGitRepository` / 统计刷新目标集迁移
- [x] 实现 `Project` 轻量 Git 类型字段与目录刷新职责拆分
- [x] 实现 Git 元数据统一刷新与存储层局部更新入口
- [x] 调整过滤与 UI 文案语义，避免把未统计 Git 项目显示成非 Git
- [x] 运行定向测试与必要回归，并在本文件追加 Review

## Review（2026-03-24 目录刷新与 Git 统计职责拆分实现）

- 结果：
  1. 已把目录刷新与 Git 元数据刷新拆成两条链：`refreshProjectCatalog()` 不再调用 Git 子进程，只做目录发现、目录属性更新与轻量 Git 判定；`refreshGitStatistics{Async}` 统一负责提交数、最后提交摘要与 `gitDaily`。
  2. 已在 `Project` 模型中新增 `isGitRepository`，并把 Git / 非 Git 过滤与 UI 展示从 `gitCommits > 0` 迁移到这个轻量真相源。
  3. 目录刷新现在会对已有 Git 项目保留旧 Git 统计值；新发现的 Git 项目在首次统计前会显示为“Git 项目”，而不是误标成“非 Git”。
  4. Git 统计链路已扩展为同时写回 `git_commits`、`git_last_commit`、`git_last_commit_message`、`git_daily`，并继续保留 `projects.json` 里的未知字段。
- 直接原因：
  1. 旧实现把目录发现与 Git 统计绑在同一条 refresh 链里，导致用户只想刷新目录时也要等待 `git rev-list` / `git log`。
  2. 旧实现把 `gitCommits > 0` 误当成 repo 类型真相源，使得“目录刷新不跑 git”无法直接落地，否则新 Git 项目会被误判成非 Git。
- 设计层诱因：
  1. `Project` 之前缺少显式的 repo 类型字段，导致“Git 类型判断”和“Git 统计缓存”语义耦合。
  2. 未发现明显系统设计缺陷，但存在职责边界混淆：目录刷新链路承担了不属于它的 Git 元数据职责。
- 当前修复方案：
  1. 在 `Project` 中新增 `isGitRepository`，向后兼容老快照 decode；
  2. `NativeAppViewModel.createProject()` 改为只做轻量 Git 判定，不再调用 `loadGitInfo()`；
  3. `refreshGitStatistics{Async}` 目标集改为 `visibleProjects.filter(\\.isGitRepository)`；
  4. `GitDailyRefreshResult` / `GitDailyCollector` / `LegacyCompatStore` 升级为统一刷新并局部写回完整 Git 元数据；
  5. `MainContentView`、`ProjectDetailRootView`、`WorkspaceHostView` 与 Git filter 全部改为接受“Git 项目但尚未统计”的中间态。
- 长期改进建议：
  1. 后续可继续在 Git 统计链路上加限流并发/增量缓存，进一步降低“更新统计”的 wall-clock；
  2. 若需要更强 UX，可再把“刷新目录”和“刷新 Git 统计”做成更明确的两个入口或两阶段提示。
- 验证证据：
  - RED：`swift test --package-path macos --filter 'LegacyCompatStoreTests/testRefreshProjectCatalogPreservesExistingGitMetadataForGitRepos|LegacyCompatStoreTests/testRefreshGitStatisticsAsyncRefreshesGitMetadataForGitRepositoriesWithoutCommitCache|LegacyCompatStoreTests/testGitOnlyFilterUsesIsGitRepositoryInsteadOfCommitCount|MainContentViewTests|ProjectDetailRootViewTests'` → 编译失败，明确提示 `Project` 缺少 `isGitRepository`、`GitDailyRefreshResult` 缺少 Git 元数据字段
  - 定向绿灯：`swift test --package-path macos --filter 'NativeAppViewModelTests/testRefreshProjectCatalogPreservesExistingGitMetadataForGitRepos|NativeAppViewModelTests/testRefreshGitStatisticsAsyncRefreshesGitMetadataForGitRepositoriesWithoutCommitCache|NativeAppViewModelTests/testGitOnlyFilterUsesIsGitRepositoryInsteadOfCommitCount|NativeAppViewModelTests/testRefreshGitStatisticsAsyncMarksRefreshingImmediatelyAndAppliesResults|NativeAppViewModelTests/testRefreshGitStatisticsReadsRealGitLogAndPreservesUnknownProjectFields|MainContentViewTests|ProjectDetailRootViewTests'` → 13 tests，0 failures
  - 目录刷新/并发回归：`swift test --package-path macos --filter 'NativeAppViewModelTests|ProjectCatalogRefreshConcurrencyTests|MainContentViewTests|ProjectDetailRootViewTests'` → 32 tests，0 failures
  - 全量回归：`swift test --package-path macos` → 283 tests，5 skipped，0 failures

## 2026-03-24 版本升级到 v3.1.0

- [x] 确认版本真相源与所有受影响文件
- [x] 更新版本号到 `3.1.0` 及对应 build number
- [x] 运行必要验证并在本文件追加 Review

## Review（2026-03-24 版本升级到 v3.1.0）

- 结果：
  1. 已将原生发布真相源从 `3.0.2 / 3002000` 升级到 `3.1.0 / 3010000`。
  2. 已同步更新 `README.md` 首页版本徽章，避免仓库展示版本落后于 `AppMetadata.json`。
- 直接原因：
  1. 当前仓库版本真相源仍停留在 `macos/Resources/AppMetadata.json` 的 `3.0.2 / 3002000`，与本轮目标版本 `v3.1.0` 不一致。
- 设计层诱因：
  1. 未发现明显系统设计缺陷；当前版本号真相源已足够集中，只需同步更新元数据与 README 展示。
- 当前修复方案：
  1. 更新 `macos/Resources/AppMetadata.json` 中的 `version=3.1.0`、`buildNumber=3010000`；
  2. 更新 `README.md` 首页版本徽章到 `3.1.0`。
- 长期改进建议：
  1. 后续发版时继续保持 `AppMetadata.json` 作为唯一版本真相源，并同步检查 README / tag / release note 是否一致。
- 验证证据：
  - `python3` 解析 `macos/Resources/AppMetadata.json` → `version=3.1.0`，`buildNumber=3010000`
  - `rg -n 'version-3\\.1\\.0' README.md` → 命中 README 第 7 行版本徽章
  - `swift build --package-path macos` → `Build complete! (4.16s)`，exit 0

## 2026-03-24 v3.1.0 提交与打 tag

- [x] 暂存本次版本升级相关文件，不混入本地私有未跟踪内容
- [x] 提交 v3.1.0 版本升级
- [x] 创建并校验本地 tag `v3.1.0`
- [x] 在本文件追加 Review 记录当前本地状态

## Review（2026-03-24 v3.1.0 提交与打 tag）

- 结果：
  1. 已将版本升级改动提交为本地 `main` 最新一条提交（`chore(release): bump version to v3.1.0`）。
  2. 已创建本地 annotated tag `v3.1.0`，并确认其当前指向版本升级提交。
  3. 当前**未 push**；远端状态尚未更新。
- 直接原因：
  1. 用户明确要求执行“创建 `v3.1.0` tag”，而 tag 应指向已提交的版本升级内容，不能指向未提交工作区。
- 设计层诱因：
  1. 未发现明显系统设计缺陷；本轮只是 release 元数据与本地 tag 的标准发布准备动作。
- 当前处理方案：
  1. 仅暂存 `README.md`、`macos/Resources/AppMetadata.json`、`tasks/todo.md` 三个与版本升级直接相关的文件；
  2. 提交版本升级；
  3. 创建本地 `v3.1.0` annotated tag，并校验 tag/HEAD 一致；
  4. 保持本地私有未跟踪目录不入提交。
- 验证证据：
  - `git diff --cached --stat` → 仅包含 `README.md`、`macos/Resources/AppMetadata.json`、`tasks/todo.md`
  - `git commit --amend --no-edit`（基于初始版本升级提交补 Review）→ 成功生成当前本地最新提交
  - `git rev-parse --short=12 HEAD` / `git rev-list -n 1 v3.1.0 | cut -c1-12` → 两者一致，证明 tag 指向当前版本升级提交
  - `git tag --list 'v3.1.0'` → 命中 `v3.1.0`
  - `git status --short` → 仅剩 `.claude/skills/`、`.iflow/`、`.opencli/`、`skills-lock.json` 这些本地未跟踪内容

## 2026-03-24 推送 main 与 v3.1.0

- [x] 推送本地 `main` 到 `origin/main`
- [x] 推送本地 tag `v3.1.0` 到 `origin`
- [x] 校验远端分支与 tag 指向并在本文件追加 Review

## Review（2026-03-24 推送 main 与 v3.1.0）

- 结果：
  1. 已将本地 `main` 推送到 `origin/main`，远端主分支现已推进到 `c3707f2b68ad`。
  2. 已将本地 annotated tag `v3.1.0` 推送到 `origin`。
  3. 已校验远端 `main` 与远端 `v3.1.0` 最终都指向版本升级提交 `c3707f2b68ad`。
- 直接原因：
  1. 用户明确要求执行“push main 和 v3.1.0 到远端”，因此需要分别完成分支推送、tag 推送与远端指向校验。
- 设计层诱因：
  1. 未发现明显系统设计缺陷；本轮是标准 release 推送动作。
- 当前处理方案：
  1. 保持 tag 指向版本升级提交；
  2. 推送 `HEAD -> origin/main`；
  3. 推送本地 `v3.1.0`；
  4. 用 `git ls-remote` 校验远端分支 / tag peeled commit 与本地 HEAD 一致。
- 验证证据：
  - `git push origin HEAD:main` → `38ab435..c3707f2  HEAD -> main`
  - `git push origin v3.1.0` → `* [new tag]         v3.1.0 -> v3.1.0`
  - `git ls-remote --refs --tags --heads origin main v3.1.0` → 远端 `refs/heads/main` 为 `c3707f2...`，远端 `refs/tags/v3.1.0` 已存在
  - `git ls-remote origin refs/tags/v3.1.0^{} | cut -f1 | cut -c1-12` → `c3707f2b68ad`
  - `git rev-parse --short=12 HEAD` → `c3707f2b68ad`


## 2026-03-24 Issue #42 链接点击报错（应用程序无法打开 -50）

- [x] 收集 issue 现场信息、截图/日志与相关历史上下文
- [x] 定位 DevHaven 中链接识别与点击打开链路
- [x] 复现并确认 `-50` 的直接触发条件
- [x] 如需修复，补最小验证并实施修复
- [x] 回填 Review，记录直接原因、设计层诱因、修复方案与验证证据

## Review（2026-03-24 Issue #42 链接点击报错）

- 结果：
  1. 已修复 DevHaven 内嵌 Ghostty 点击本地路径时误报“应用程序无法打开 -50”的问题。
  2. 现在 `https://...` 仍按普通 URL 打开，`/Users/...`、`OUTPUT_DIR=/Users/...`、`./relative/path` 会先被解析成正确的 file URL 再交给 `NSWorkspace`。
- 直接原因：
  1. `GhosttySurfaceBridge.openURL(...)` 原先直接对点击文本执行 `URL(string: string) ?? URL(fileURLWithPath: string)`。
  2. 对 `/Users/...` 或 `APP_PATH=/Users/...` 这类**没有 scheme 的本地路径**，`URL(string:)` 会返回一个无 scheme 的相对 URL；`NSWorkspace.shared.open(...)` 随后稳定报 `NSOSStatusErrorDomain Code=-50`。
- 设计层诱因：
  1. URL 链接与文件路径共用同一条“先 `URL(string:)` 再兜底”的解析逻辑，但这两个输入域的判定规则并不相同。
  2. `build-native-app.sh` 输出的 `APP_PATH=...` / `OUTPUT_DIR=...` 进一步放大了这个问题：终端点击拿到的并不一定是纯路径，而可能是 shell assignment 形式的 token。
  3. 未发现明显系统设计缺陷，但存在边界处理收口不足：点击打开链路缺少对“无 scheme 本地路径”和“shell assignment 包裹路径”的显式归一化。
- 当前修复方案：
  1. 在 `GhosttySurfaceBridge` 中新增 `resolvedOpenURL(from:workingDirectory:)`，先区分显式 scheme URL、本地绝对路径、`~/...`、相对路径以及 `KEY=/path` 形式的 shell assignment；
  2. `openURL(...)` 改为先归一化目标，再调用 `NSWorkspace.shared.open(...)`；
  3. 新增 `GhosttySurfaceBridgeOpenURLTests`，覆盖 HTTP URL、绝对路径、shell assignment 与相对路径四类输入。
- 长期改进建议：
  1. 若后续还要暴露更多“可点击产物路径”，可以考虑把脚本输出从 `KEY=/path` 统一升级为更明确的人类文案或 `file://` 形式，减少终端侧解析歧义；
  2. 若 Ghostty 后续还会上报更多可点击 token 类型，可把这套解析逻辑继续下沉成独立的 link resolver，避免桥接层不断堆判断分支。
- 验证证据：
  - 现场 issue：`gh api repos/zxcvbnmzsedr/devhaven/issues/42` → issue 标题为“链接点击报错。显示应用程序无法打开。”，截图与用户粘贴日志对应 `APP_PATH=` / `OUTPUT_DIR=` 点击场景
  - 独立复现：`swift -e 'import AppKit ... NSWorkspace.shared.open(URL(string: "APP_PATH=/Users/..." )!, configuration: .init()) ...'` → `NSUnderlyingError=NSOSStatusErrorDomain Code=-50`
  - RED：`swift test --package-path macos --filter GhosttySurfaceBridgeOpenURLTests` → 编译失败，提示 `GhosttySurfaceBridge` 尚无 `resolvedOpenURL`
  - GREEN：`swift test --package-path macos --filter GhosttySurfaceBridgeOpenURLTests` → 4 tests，0 failures
  - 相关回归：`swift test --package-path macos --filter 'GhosttySurfaceBridgeOpenURLTests|GhosttySurfaceBridgeTabPaneTests|GhosttySurfaceCallbackContextTests'` → 11 tests，0 failures
  - 构建验证：`swift build --package-path macos` → `Build complete! (0.58s)`


## 2026-03-24 Issue #42 修复提交与 PR

- [x] 基于最新改动做一轮提交前新鲜验证
- [x] 创建独立分支并仅暂存本轮修复相关文件
- [x] 提交修复并推送远端分支
- [x] 创建 Pull Request 并记录链接与验证证据

## Review（2026-03-24 Issue #42 修复提交与 PR）

- 结果：
  1. 已在分支 `fix/issue-42-ghostty-open-url` 提交并推送本轮修复。
  2. 已创建 Pull Request：`https://github.com/zxcvbnmzsedr/devhaven/pull/43`。
- 直接原因：
  1. 用户确认本地手动验证已通过，下一步需求是把已验证修复整理成可审阅的远端 PR。
- 设计层诱因：
  1. 未发现明显系统设计缺陷；本轮只是标准的提交 / 推分支 / 建 PR 收口动作。
- 当前处理方案：
  1. 在 `main` 当前工作区上切出 `fix/issue-42-ghostty-open-url` 独立分支；
  2. 仅暂存 `GhosttySurfaceBridge.swift`、新增测试与 `tasks/todo.md`，不混入 `.iflow/`、`.opencli/` 等本地未跟踪内容；
  3. 提交 `fix(ghostty): normalize clicked local paths before open`；
  4. 推送远端分支并创建 PR，PR 标题为 `fix: normalize clicked local paths in Ghostty`。
- 验证证据：
  - 新鲜验证：`swift test --package-path macos --filter 'GhosttySurfaceBridgeOpenURLTests|GhosttySurfaceBridgeTabPaneTests|GhosttySurfaceCallbackContextTests'` → 11 tests，0 failures
  - 新鲜构建：`swift build --package-path macos` → `Build complete! (2.39s)`
  - 暂存范围：`git diff --cached --stat` → 仅包含 `GhosttySurfaceBridge.swift`、`GhosttySurfaceBridgeOpenURLTests.swift`、`tasks/todo.md`
  - 提交结果：`git commit -m "fix(ghostty): normalize clicked local paths before open"` → 生成提交 `f3f0560`
  - 推送结果：`git push -u origin fix/issue-42-ghostty-open-url` → 远端分支创建成功并建立 tracking
  - PR：`gh pr create --base main --head fix/issue-42-ghostty-open-url ...` → 返回 `https://github.com/zxcvbnmzsedr/devhaven/pull/43`

## Review（2026-03-24 workspace 打开项目快捷键与弹窗焦点调整）

- 结果：
  1. 已为 workspace 新增“打开项目”菜单命令，默认快捷键为 `⌘K`，并且该快捷键现在可在设置页中配置。
  2. 新增 `WorkspaceProjectCommands.swift`，通过 `FocusedValue` 把 App 菜单动作路由到 `WorkspaceShellView` 的 project picker 展示态，没有把这类壳层状态下沉到 `NativeAppViewModel`。
  3. `WorkspaceProjectPickerView` 现在会在弹窗出现时显式把焦点放到搜索输入框，并让“关闭”按钮不再抢默认 focus。
- 直接原因：
  1. 之前 workspace 的“打开项目”只有侧边栏加号按钮入口，没有对应的 App 菜单命令与快捷键路由，因此无法通过键盘直接打开。
  2. `WorkspaceProjectPickerView` 没有显式 `FocusState`，同时“关闭”按钮也没有排除在 key-view 抢占之外，导致弹窗默认焦点容易落到“关闭”而不是搜索框。
- 设计层诱因：
  1. project picker 的展示态此前只和局部按钮点击绑定，没有抽象成可复用的 scene 级命令入口，所以菜单/快捷键层无从接入。
  2. 焦点语义此前依赖 SwiftUI/AppKit 默认 key-view 顺序，属于隐式行为；未发现更大的系统设计缺陷，但这类 UX 关键路径不应继续依赖默认焦点分配。
- 当前修复方案：
  1. 在 `AppSettings` 中新增 `workspaceOpenProjectShortcut`，默认值为 `⌘K`，并保持旧配置缺失字段时自动回退默认值。
  2. 新增 `WorkspaceProjectCommands.swift`，使用 `FocusedValue` + `WorkspaceShellView.openWorkspaceProjectPickerAction` 把“打开项目”菜单命令桥接到当前 workspace 壳层。
  3. 在 `SettingsView` 常规页新增“打开项目快捷键”配置卡片，支持主按键选择和 `Shift / Option / Control` 附加修饰键。
  4. 在 `WorkspaceProjectPickerView` 中新增 `@FocusState`、`requestInitialSearchFocus()` 和 `.focusable(false)`，把默认 focus 收口到搜索框。
- 长期改进建议：
  1. 如果后续还要继续开放更多 workspace / app 菜单快捷键，建议把当前 `AppMenuShortcut` 扩展成统一的命令快捷键模型，而不是在设置页逐个堆叠专用状态。
  2. 若用户后续希望录制任意组合键，可再独立补一个真正的快捷键录入控件；本轮先保持“菜单快捷键 + 轻量配置”的最小闭环。
- 验证证据：
  - 红灯（模型缺失）：`swift test --package-path macos --filter 'AppSettingsUpdatePreferencesTests|SettingsViewTests|DevHavenAppCommandTests|WorkspaceShellViewTests|WorkspaceProjectPickerViewTests'` → 失败，报错 `AppSettings` 缺少 `workspaceOpenProjectShortcut`，随后 source-based 断言也确认设置页/命令/焦点实现尚未存在。
  - 绿灯（定向回归）：`swift test --package-path macos --filter 'AppSettingsUpdatePreferencesTests|SettingsViewTests|DevHavenAppCommandTests|WorkspaceShellViewTests|WorkspaceProjectPickerViewTests'` → 20 tests，0 failures。
  - 构建验证：`swift build --package-path macos` → Build complete。
  - 差异校验：`git diff --check` → 无输出。

## Review（2026-03-24 workspace 打开项目快捷键在终端焦点下无效排查）

- 结果：
  1. 已定位并修复“workspace 打开项目快捷键在终端焦点下按了没反应”的问题。
  2. 修复后，Ghostty 终端聚焦时会先把 `⌘ / ⌃` 组合键交给 App 主菜单尝试处理；若主菜单没有对应命令，再继续回落到终端自身绑定。
  3. 这样 `⌘K` 的“打开项目”菜单命令在终端界面下不再被 Ghostty 键位链路吞掉，同时不会影响普通文本输入。
- 直接原因：
  1. `GhosttyTerminalSurfaceView.performKeyEquivalent(with:)` 之前只有在 `bindingFlags(for:)` 返回某些特定 consumed/non-performable 结果时，才会尝试 `NSApp.mainMenu.performKeyEquivalent(with:)`。
  2. 对像 `⌘K` 这种应用菜单快捷键来说，终端聚焦时事件先进入 Ghostty surface；如果该按键未走到那条“binding 后再尝试菜单”的窄路径，主菜单就根本拿不到机会。
  3. 所以问题不在 `WorkspaceProjectCommands` 的 focused action 为 nil，而在于**Ghostty 键盘事件分发顺序把 App 菜单快捷键拦在了终端层前面**。
- 设计层诱因：
  1. 现有 `performKeyEquivalent` 把“菜单快捷键是否应该优先”这一策略隐含在 Ghostty binding flag 的分支里，导致新的 App 级命令只有在碰巧符合那组 flag 时才能生效。
  2. 这属于**菜单路由策略与终端绑定查询耦合过深**：App 级菜单快捷键不应依赖 Ghostty 是否把某个组合键识别成 binding 才有机会执行。未发现更大的系统设计缺陷，但菜单优先级策略此前不够显式。
- 当前修复方案：
  1. 新增 `GhosttySurfaceMenuShortcutRoutingPolicy.swift`，把“哪些快捷键应先尝试主菜单”收口成独立策略。
  2. `GhosttySurfaceView.performKeyEquivalent(with:)` 现在会先对 `⌘ / ⌃` 组合键执行一次 `NSApp.mainMenu.performKeyEquivalent(with:)`；命中则直接返回，不再把事件继续交给终端。
  3. 旧的 binding-after-menu fallback 仍保留，只是改为复用同一个 routing policy，避免回退逻辑丢失。
- 长期改进建议：
  1. 后续如果继续给 workspace / app 增加菜单快捷键，优先复用同一 routing policy，而不要在 `GhosttySurfaceView` 里继续内联更多特判。
  2. 若未来需要更细的优先级（例如某些终端命令必须压过 App 菜单），可以再把 routing policy 扩成显式的 shortcut ownership 表，而不是继续让 Ghostty binding flag 间接决定 App 菜单是否可达。
- 验证证据：
  - 红灯：`swift test --package-path macos --filter GhosttySurfaceMenuShortcutRoutingPolicyTests` → 失败，报错 `cannot find 'GhosttySurfaceMenuShortcutRoutingPolicy' in scope`，说明测试先约束了缺失的菜单路由策略入口。
  - 绿灯（路由策略）：`swift test --package-path macos --filter GhosttySurfaceMenuShortcutRoutingPolicyTests` → 5 tests，0 failures。
  - 绿灯（相关回归）：`swift test --package-path macos --filter 'GhosttySurfaceMenuShortcutRoutingPolicyTests|AppSettingsUpdatePreferencesTests|SettingsViewTests|DevHavenAppCommandTests|WorkspaceShellViewTests|WorkspaceProjectPickerViewTests|WorkspaceTerminalCommandsTests'` → 27 tests，0 failures。
  - 构建验证：`swift build --package-path macos` → Build complete。
  - 差异校验：`git diff --check` → 无输出。

## 2026-03-24 Workspace Run Console 实现

- [x] 搭建 Core 层运行模型与日志存储
- [x] 实现 WorkspaceRunManager 的启动 / 输出 / 停止链路
- [x] 把运行状态接入 NativeAppViewModel
- [x] 接入 Workspace 顶部控制区与底部 Run Console UI
- [x] 更新 AGENTS.md、补齐验证与 Review

## Review（2026-03-24 Workspace Run Console 实现）

- 结果：已为 workspace 接入基于 `Project.scripts` 的轻量 Run Console，支持同一 workspace 多命令并行运行、底部 session tabs 切换日志、顶部 Run / Stop / Logs 控制、日志落盘到 `~/.devhaven/run-logs/*.log`。
- 直接原因：用户需要的是“像 IDEA 右上角 Run/Stop + 下方看日志”的交互结果，但底层只是运行命令，不需要完整 execution framework。
- 设计层诱因：当前 workspace 架构天然偏向 terminal pane，如果直接把运行管理强塞进 Ghostty pane，会把“停止进程 / 关闭视图 / 查看日志”三种语义混在一起；因此本轮把命令执行抽到 `WorkspaceRunManager`，SwiftUI 只做控制和展示。未发现明显系统设计缺陷，但 run session 与 pane/session attention 原本是两条链路，本轮新增后要持续保持边界清晰。
- 当前修复方案：
  - Core：新增 `WorkspaceRunModels.swift`、`WorkspaceRunLogStore.swift`、`WorkspaceRunManager.swift`
  - ViewModel：`NativeAppViewModel` 新增 workspace run state、script 选择、启动/停止/切换/展开日志 API，并在关闭 workspace 项目时停止该项目全部 run sessions
  - App：新增 `WorkspaceRunToolbarView.swift` 与 `WorkspaceRunConsolePanel.swift`，并在 `WorkspaceHostView` 顶部右侧/底部接入
  - 文档：`AGENTS.md` 新增 run console 模块与 `run-logs/*.log` 本地目录说明
- 长期改进建议：
  - 为 run session 增加历史清理策略与“关闭单个 session tab”动作
  - 如果后续需要参数化执行，可在 `ProjectScript.paramSchema` 之上加参数输入层，而不是把 shell 逻辑继续堆在 UI 上
  - 若未来要支持 Debug/Test，再考虑把当前轻量 run session 抽象成更完整的 executor 层
- 验证证据：
  - `swift test --package-path macos --filter WorkspaceRunLogStoreTests`
  - `swift test --package-path macos --filter WorkspaceRunManagerTests`
  - `swift test --package-path macos --filter NativeAppViewModelWorkspaceRunTests`
  - `swift test --package-path macos --filter WorkspaceRunToolbarViewTests`
  - `swift test --package-path macos --filter WorkspaceHostViewRunConsoleTests`
  - `swift test --package-path macos` -> 315 tests, 5 skipped, 0 failures
  - `swift build --package-path macos` -> Build complete
- 验收步骤：
  1. 打开任一带 `scripts` 的项目并进入 workspace。
  2. 在顶部右侧脚本菜单选择一个脚本，点击 `Run`。
  3. 观察底部 `Run Console` 自动展开，并出现对应 session tab 与实时日志。
  4. 再选择另一个脚本点击 `Run`，确认底部新增第二个 session tab，两个命令可并行存在。
  5. 点击不同 session tab，确认日志内容随之切换。
  6. 点击顶部 `Stop`，确认只停止当前选中 session；未选中的其他 session 继续运行。
  7. 点击顶部 `Logs`，确认仅收起/展开底部日志面板，不会停止进程。
  8. 在底部点击“打开日志”，确认会用系统默认方式打开 `~/.devhaven/run-logs/` 下对应 `.log` 文件。

## 2026-03-24 Workspace Run Console 收敛（配置复用 / 通用配置）

- [x] 先补测试，约束“按配置复用 tab”而不是“每次 Run 新建 session tab”
- [x] 把运行项从单纯 `Project.scripts` 收敛成运行配置（项目脚本 + 通用脚本）
- [x] 接入配置入口，让 workspace 菜单里可直接跳到“配置运行项”
- [x] 更新 AGENTS.md 与 Review，补 fresh 验证证据

## Review（2026-03-24 Workspace Run Console 收敛）

- 结果：Run Console 已从“execution history 视角”收敛为“运行配置视角”。顶部菜单现在统一展示项目脚本 + 通用脚本，底部 tab 按配置复用；同一配置再次 `Run` 时会 stop 旧进程并在原 tab 内 restart-in-place，不再每次追加新 tab。
- 直接原因：上一版把 tab 真相源建在 `sessionID` 上，导致每次运行同一脚本都会生成新的会话标签，这更像终端历史而不是 IDEA 的 run configuration / reused content 心智。
- 设计层诱因：之前缺少“运行配置”这一中间层，UI 直接拿 `Project.scripts` 驱动执行，再把每次执行结果 append 到 `sessions`。这样会让“配置选择”“执行实例”“底部 tab 复用策略”三件事耦在一起。当前已把这三者拆开：配置列表独立推导、执行仍是 session、tab 复用按 `configurationID` 收口。未发现明显新的系统设计缺陷。
- 当前修复方案：
  - Core：`WorkspaceRunModels.swift` 新增 `WorkspaceRunConfiguration` 与 `configurationID` 语义；`NativeAppViewModel` 负责把 `Project.scripts` + `sharedScriptsRoot` 下的通用脚本解析成可运行配置，并为同一配置复用同一个 console 槽位
  - Shared Scripts：复用现有 `Settings -> 脚本` 管理器作为“公用配置”入口；workspace 直接消费其 manifest / 脚本文件，不再额外造第三套配置存储
  - App：`WorkspaceRunToolbarView` 改为配置菜单 + `配置` 按钮；`WorkspaceHostView` 直接桥到 `viewModel.revealSettings(section: .scripts)`；`SettingsView` 支持按入口落到脚本分类
  - Console：底部仍显示 session 运行态，但 tab 只保留每个配置的当前槽位；同配置重跑只替换该槽位的 session
- 长期改进建议：
  - 当前通用脚本参数仍主要依赖默认值；如果后续需要更像 IDEA 的临时参数编辑 / Before Launch / 环境变量面板，可在 `WorkspaceRunConfiguration` 之上再补参数表单层
  - 若未来要支持“允许并行运行同一配置的多个实例”，应显式引入 `allowParallelRuns` 策略，而不是重新退回 append-only tab
  - 若后续需要展示上次运行摘要 / 历史日志，可单独做 history 面板，不要把底部主 tab 再变回历史列表
- 验证证据：
  - `swift test --package-path macos --filter NativeAppViewModelWorkspaceRunTests`
  - `swift test --package-path macos --filter 'WorkspaceRun(LogStoreTests|ManagerTests|ToolbarViewTests|HostViewRunConsoleTests)'`
  - `swift test --package-path macos --filter WorkspaceHostViewRunConsoleTests`
  - `swift test --package-path macos` -> 317 tests, 5 skipped, 0 failures
  - `swift build --package-path macos` -> Build complete
- 验收步骤：
  1. 打开任一 workspace，确认顶部右侧运行菜单里同时能看到“项目脚本”和“通用脚本”两类配置（如果已在设置页配置过通用脚本）。
  2. 先运行一个项目脚本，确认底部出现对应 tab，并持续输出日志。
  3. 在同一个配置上再次点击 `Run`，确认不会新增第二个同名 tab，而是复用原 tab；旧进程被停止，新进程在原 tab 内继续输出。
  4. 再运行另一个不同配置，确认底部新增第二个 tab，说明“不同配置可并行、同一配置复用”。
  5. 点击顶部 `配置`，确认会直接打开设置页并落在“脚本”分类，可继续管理通用脚本。
  6. 若某个通用脚本缺少必填默认参数，确认该配置不会误跑；补好默认值后重新打开 workspace 菜单即可运行。

## 2026-03-24 workspace 通用脚本配置语义修正

- [x] 对比当前 workspace run / script 配置实现与 archive/2.8.3，确认直接原因与设计层诱因
- [x] 先补失败测试，约束“通用脚本只在配置脚本时参与选择，不直接出现在运行入口”
- [x] 以最小改动修复当前实现，并同步必要文档/注释
- [x] 运行定向验证并在 Review 记录证据、直接原因、设计层诱因、修复方案与长期建议

## Review（2026-03-24 workspace 通用脚本配置语义修正）

- 结果：
  1. workspace 顶部 Run 菜单现在只展示当前项目的 `Project.scripts`，不再把 `sharedScriptsRoot` 下的通用脚本误当成可直接运行配置。
  2. 顶部 `配置` 现在会打开新的 `WorkspaceScriptConfigurationSheet`；面板内提供 `archive/2.8.3` 同语义的“插入通用脚本（可选）”，用于把通用脚本模板展开成项目脚本命令与参数默认值，再保存回 `Project.scripts`。
  3. `NativeAppViewModel.saveWorkspaceScripts(...)` 会把配置结果写回真实项目；若当前 workspace 是 worktree，则会落回其 root project 的 `scripts`，保持原有“worktree 继承脚本配置”的数据语义。
- 直接原因：
  1. 上一轮收敛把“通用脚本”错误理解成“运行配置来源”，于是 `availableWorkspaceRunConfigurations(...)` 直接把 `store.listSharedScripts(...)` 的结果拼进运行菜单。
  2. `WorkspaceHostView` 的 `配置` 按钮也因此被错误地直接桥到设置页“脚本”分类，只能管理通用脚本，不能配置当前项目真正会运行的 `Project.scripts`。
- 设计层诱因：
  1. 之前把“运行配置”和“脚本模板来源”混成同一层概念：前者属于 workspace runtime，后者属于项目脚本编辑期；边界一旦混掉，就会自然把模板放进运行菜单。
  2. 同时缺少原生版项目脚本配置面板，导致实现时为了给 `配置` 按钮找落点，错误复用了通用脚本管理页。未发现更深的系统性存储缺陷，问题主要是能力边界判断失真。
- 当前修复方案：
  1. Core：新增 `ScriptTemplateSupport`，把 shared-script template 应用、参数 schema 推导、默认参数构建、required 校验统一收口；`NativeAppViewModel` 运行配置重新只从 `Project.scripts` 推导，并新增 `saveWorkspaceScripts(...)` / `revealSharedScriptsSettings()`。
  2. App：新增 `WorkspaceScriptConfigurationSheet`，提供项目脚本列表、命令编辑、参数值填写与“插入通用脚本（可选）”；`WorkspaceHostView` 的 `配置` 改为打开该面板，面板内如需管理通用脚本再跳设置页。
  3. 文档：更新 `AGENTS.md`，明确 shared scripts 只属于脚本配置阶段，不属于 run menu 运行项。
- 长期改进建议：
  1. 当前脚本配置面板仍是轻量版；如果后续需要更像 IDEA 的 Before Launch、环境变量、临时参数覆盖，可在 `ProjectScript` 之上继续加编辑层，但不要再把通用脚本回退成 runtime config。
  2. 若未来需要在主页/详情页也编辑项目脚本，建议复用同一份 `WorkspaceScriptConfigurationSheet` 内核，而不是再造第二套 shared-script 插入逻辑。
- 验证证据：
  - 红灯验证：`swift test --package-path macos --filter 'NativeAppViewModelWorkspaceRunTests|WorkspaceRunToolbarViewTests|WorkspaceHostViewRunConsoleTests|WorkspaceScriptConfigurationSheetTests|ScriptTemplateSupportTests'`（实现前）→ 编译失败，明确报错 `cannot find 'ScriptTemplateSupport' in scope`，说明新的模板工具 / 配置面板语义尚未落地。
  - 绿灯验证：`swift test --package-path macos --filter 'NativeAppViewModelWorkspaceRunTests|WorkspaceRunToolbarViewTests|WorkspaceHostViewRunConsoleTests|WorkspaceScriptConfigurationSheetTests|ScriptTemplateSupportTests'` → 11 tests，0 failures。
  - 回归验证：`swift test --package-path macos` → 320 tests，5 skipped，0 failures。

## 2026-03-24 预制脚本模板变量赋值导致 zsh command not found 排查

- [x] 复现当前预制脚本渲染结果，确认 `password=...` 被当成命令执行的直接原因
- [x] 分析是否存在脚本模板/参数渲染协议层面的设计诱因
- [x] 先补失败测试，覆盖以 shell 保留字命名的模板参数仍能安全赋值
- [x] 以最小改动修复模板赋值/执行协议，并同步必要文档
- [x] 运行定向验证并在 Review 记录证据、直接原因、设计层诱因、修复方案与长期建议


## Review（2026-03-24 预制脚本模板变量赋值导致 zsh command not found 排查）

- 结果：
  1. 预制脚本里“先做变量赋值、再 `exec bash ...`”的写法现在可以正常运行，不会再出现 `zsh:1: command not found: password=...`。
  2. `WorkspaceRunManager` 仍然支持已有的普通单行命令与 stop 流程；完整回归后未发现 run console 其它链路被这次修复带坏。
- 直接原因：
  1. `WorkspaceRunManager.start(...)` 之前把所有运行命令统一包装成 `zsh -lc "exec <request.command>"`。
  2. 当 `request.command` 本身是一段多行 shell 脚本、并且前面含有 `password='...'`、`server='...'` 这类赋值语句时，shell 实际收到的是 `exec password='...'`，于是把 `password=...` 误当成“要执行的命令名”，直接报 `command not found`。
- 设计层诱因：
  1. 运行层此前默认假设“运行配置总是单个 shell command”，因此试图在进程入口统一外包一层 `exec`。
  2. 但当前项目脚本/预制脚本已经允许用户写完整的多行 shell 程序，并且脚本内容内部自己就可能包含赋值、数组、条件分支乃至 `exec`；这说明执行层与脚本 authoring 层之间存在协议错位。未发现更深的存储模型缺陷，问题主要集中在 RunManager 的入口包装策略。
- 当前修复方案：
  1. 为 `WorkspaceRunManagerTests` 新增回归测试 `testStartSupportsMultilineCommandsWithAssignmentsBeforeInnerExec`，覆盖“前置赋值 + 内层 exec”场景。
  2. `WorkspaceRunManager.start(...)` 不再对 `request.command` 统一追加外层 `exec `，而是直接交给 `zsh -lc` 执行，让多行脚本自己控制是否 `exec` 最终进程。
- 长期改进建议：
  1. 如果后续还要继续增强 run configuration，可以显式区分“单条命令模式”和“脚本模式”，避免执行层继续依赖隐式 shell 包装约定。
  2. 对包含多行脚本、数组、trap、inner exec 的配置，建议继续把回归样例收在 `WorkspaceRunManagerTests`，不要只测单行 `printf` 这类 happy path。
- 验证证据：
  - 根因复现：`/bin/zsh -lc $'exec password=''WwS6P6AzfKHu''
server=''example''
exec bash -lc '''echo ok''''` → `zsh:1: command not found: password=WwS6P6AzfKHu`
  - 红灯验证：`swift test --package-path macos --filter WorkspaceRunManagerTests`（修复前）→ `testStartSupportsMultilineCommandsWithAssignmentsBeforeInnerExec` 失败，并明确输出 `zsh:1: command not found: password=WwS6P6AzfKHu`
  - 绿灯验证：`swift test --package-path macos --filter WorkspaceRunManagerTests` → 3 tests，0 failures
  - 回归验证：`swift test --package-path macos` → 321 tests，5 skipped，0 failures

## 2026-03-24 Run Console 日志补充最终执行命令

- [x] 复现当前脚本执行链路，确认现有日志缺少最终执行命令且不利于继续定位参数注入问题
- [x] 先补失败测试，约束 Run Console / log file 会输出最终执行命令与工作目录
- [x] 以最小改动实现命令头日志，并确认不破坏现有输出/停止语义
- [x] 运行定向验证与完整回归，并在 Review 记录风险、证据与后续排查方式


## Review（2026-03-24 Run Console 日志补充最终执行命令）

- 结果：
  1. Run Console 与落盘 log 现在会在真实进程输出之前，先打印最终执行目录与最终执行命令，方便继续核对变量是否真的被注入到了脚本里。
  2. 现有 run/stop 行为保持不变；针对多行脚本、前置赋值、inner exec 的场景，回归后未发现回退。
- 直接原因：
  1. 当前日志链路此前只记录子进程 stdout/stderr，不记录 DevHaven 实际交给 `zsh -lc` 的最终命令，因此当用户怀疑“变量没有注入”时，日志无法给出第一现场证据。
  2. 这会让脚本问题与参数注入问题难以区分：明明最终命令可能已经被正确解析，但日志层看不到，只能靠猜。
- 设计层诱因：
  1. Run Console 之前把自己定位成“纯子进程输出镜像”，没有给执行器自身的元信息预留首屏诊断位。
  2. 这属于可观测性缺口，而不是新的执行协议缺陷；执行层与日志层之间少了一层“启动上下文”桥接。
- 当前修复方案：
  1. 为 `WorkspaceRunManagerTests` 新增 `testStartLogsResolvedCommandAndWorkingDirectoryBeforeProcessOutput`，约束在真实输出前先记录执行目录/命令。
  2. `WorkspaceRunManager.start(...)` 在创建 log file 后、启动进程前，先向 Run Console / log file 注入命令头：
     - `[DevHaven] 执行目录：...`
     - `[DevHaven] 执行命令：...`
  3. 同步修复 `WorkspaceRunManagerTests` 中因多次 fulfill 导致的测试脆弱性，避免新的命令头输出让旧测试出现 over-fulfill 崩溃。
- 风险说明：
  1. 当前日志会记录“最终执行命令原文”，因此如果脚本参数里包含密码、token、secret 值，这些值也会进入 Run Console 与 `~/.devhaven/run-logs/*.log`。
  2. 这是为了继续排查你当前的参数注入问题而做的诊断增强；如果后续确认要长期保留，建议再补一轮 secret masking 方案，而不是直接把明文日志作为最终形态。
- 长期改进建议：
  1. 下一步可在 `WorkspaceRunConfiguration` / `ProjectScript.paramSchema` 上增加按字段类型的脱敏日志策略，只对 `secret` 字段输出 `***`，同时保留其它字段原值便于排障。
  2. 如果后续还会继续扩展执行器，建议把“命令头 / 环境摘要 / cwd / 退出码”统一抽成 executor metadata block，而不是散在各处追加字符串。
- 验证证据：
  - 红灯验证：`swift test --package-path macos --filter WorkspaceRunManagerTests`（新增测试后、实现前）→ `testStartLogsResolvedCommandAndWorkingDirectoryBeforeProcessOutput` 失败，明确说明日志中还没有 `[DevHaven] 执行命令：...`
  - 绿灯验证：`swift test --package-path macos --filter WorkspaceRunManagerTests` → 4 tests，0 failures
  - 回归验证：`swift test --package-path macos` → 322 tests，5 skipped，0 failures

## 2026-03-24 shared script 架构对照 IntelliJ 模板机制分析

- [x] 阅读 IntelliJ run configuration / template / editor 相关源码，确认“很多模板”背后的真实实现机制
- [x] 对照当前 DevHaven shared script / ProjectScript / WorkspaceRunManager 链路，定位当前架构错位点
- [x] 输出结构化分析：直接原因、设计层诱因、IDEA 的处理方式、推荐终态架构与迁移建议
- [x] 在 Review 中记录本轮结论与证据来源

## Review（2026-03-24 shared script 架构对照 IntelliJ 模板机制分析）

- 结果：
  1. 你判断得对：当前 DevHaven 虽然已经把通用脚本从 Run 菜单移回“配置阶段模板”，但底层仍然是“文本命令模板 + 变量替换 + shell 解释执行”模型；这在架构上仍然偏脆弱。
  2. IntelliJ/IDEA 的“很多模板”并不是靠一个自由拼接的 shell 模板池完成，而是靠 `ConfigurationType -> ConfigurationFactory -> template configuration -> type-specific editor/executor` 这一整套结构化运行配置体系提供。
- 直接原因：
  1. 当前 DevHaven 的 `ProjectScript` 真相源仍然是 `name + start + paramSchema + templateParams`，其中 `start` 本质是整段 shell 文本（`macos/Sources/DevHavenCore/Models/AppModels.swift`）。
  2. `ScriptTemplateSupport.resolveCommand(...)` 会把参数统一折叠成 shell 赋值前缀，再和模板文本拼成最终命令（`macos/Sources/DevHavenCore/Run/ScriptTemplateSupport.swift`）；执行器最终仍只看到“一整段命令字符串”，不知道“这是远程日志查看”“那是 Jenkins 部署”。
  3. 内置通用脚本 preset 也是 `commandTemplate + params + fileContent` 结构，例如 `remote-log-viewer` 直接把一整段多行 shell 当模板（`macos/Sources/DevHavenCore/Storage/LegacyCompatStore.swift`）。
- 设计层诱因：
  1. 当前模型把“运行配置类型”降格成了“命令模板文本”，导致 UI、校验、执行、日志、脱敏都只能围绕字符串做二次猜测。
  2. 一旦某个预设需要更强语义（布尔开关、secret 脱敏、路径选择、可组合 before-launch、执行器差异、平台约束），系统就会被迫继续往 shell 模板里塞约定，复杂度会沿字符串协议外溢。
  3. 未发现这次问题背后还有更深的线程/存储崩坏；当前主要是运行配置抽象层级偏低，导致 shared script 只能被建模成“可插入的 shell 片段”。
- IDEA 的处理方式：
  1. `ConfigurationFactory.createTemplateConfiguration(project)` 明确定义“某一类运行配置”的模板对象，而不是返回一段命令文本（`platform/execution/src/com/intellij/execution/configurations/ConfigurationFactory.java`）。
  2. `RunManagerImpl.getConfigurationTemplate(factory)` 会按 factory 维度缓存模板；首次没有就 `createTemplateSettings(factory)` 创建并注册（`platform/execution-impl/src/com/intellij/execution/impl/RunManagerImpl.kt`）。
  3. “Edit Configurations” 右侧模板编辑面板也是按 factory 打开的：`TemplateConfigurable(runManager.getConfigurationTemplate(factory))`（`platform/execution-impl/src/com/intellij/execution/impl/RunConfigurable.kt`）。
  4. 以 Shell 为例，`ShConfigurationType.createTemplateConfiguration(...)` 先生成结构化 `ShRunConfiguration`，填默认 shell / working dir；`ShRunConfiguration` 自己持有 `scriptPath`、`scriptOptions`、`interpreterPath`、`workingDirectory`、`env` 等字段，并有自己的 editor / 校验 / profile state（`plugins/sh/core/src/com/intellij/sh/run/*.java`）。
- 推荐终态架构：
  1. DevHaven 里“远程日志查看”这类预设，不应再被建模成一段 shared shell template，而应是一个结构化的 `WorkspaceRunPresetKind` / `WorkspaceRunPresetDefinition`。
  2. 项目里保存的也不该只是 `start` 文本；更合理的是保存：`kind`、`displayName`、`fieldValues`、`workingDirectoryPolicy`、必要时的 `executorHints`。
  3. 执行阶段再由 kind-specific executor/rendering 生成命令或参数数组；这样 UI 校验、secret masking、日志显示、默认值、迁移都能基于结构化字段完成，而不是继续靠 shell 文本约定。
  4. shared scripts 最多只保留两类职责：
     - 作为“脚本文件资产”存在；
     - 或作为某种 preset 的底层 helper 文件。
     但它不该继续承担运行配置 DSL 的角色。
- 长期改进建议：
  1. 下一轮可以把现有模型拆成两层：
     - `WorkspaceRunDefinition`：结构化配置类型定义（远程日志、Jenkins、自定义 shell 等）；
     - `WorkspaceRunInstance`：项目内具体实例与字段值。
  2. 为兼容已有数据，可把当前纯文本 `ProjectScript.start` 收口成一种 `customShell` 类型，而不是要求所有类型都继续走这条路。
  3. 这样既能保住“自由脚本”能力，又能给常用预设真正的 IDEA 风格结构化配置体验。
- 验证证据：
  - IntelliJ 源码核对：
    - `platform/execution/src/com/intellij/execution/configurations/ConfigurationFactory.java`
    - `platform/execution-impl/src/com/intellij/execution/impl/RunManagerImpl.kt`
    - `platform/execution-impl/src/com/intellij/execution/impl/RunConfigurable.kt`
    - `plugins/sh/core/src/com/intellij/sh/run/ShConfigurationType.java`
    - `plugins/sh/core/src/com/intellij/sh/run/ShRunConfiguration.java`
  - DevHaven 当前实现核对：
    - `macos/Sources/DevHavenCore/Models/AppModels.swift`
    - `macos/Sources/DevHavenCore/Run/ScriptTemplateSupport.swift`
    - `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`
    - `macos/Sources/DevHavenCore/Storage/LegacyCompatStore.swift`

## 2026-03-24 破坏式升级到 typed run configurations

- [x] Task 1：重构 Core 运行配置模型，支持 `customShell` / `remoteLogViewer`，并兼容旧 `ProjectScript` flatten 迁移
- [x] Task 2：升级 WorkspaceRunManager 为 typed executable，去掉 shared helper script 执行路径
- [x] Task 3：重写 workspace 运行配置编辑器，移除 Settings 中的脚本/模板入口
- [x] Task 4：删除 shared scripts store/model/UI 与相关遗留测试，并同步 AGENTS.md
- [x] Task 5：运行定向测试 + `swift test --package-path macos` 全量回归，补 Review 证据

## Review（2026-03-24 破坏式升级到 typed run configurations）

- 结果：
  1. Workspace 运行配置主链已从 shared scripts / shell 模板拼接切到 typed run configurations；当前项目内只暴露 `customShell` 与 `remoteLogViewer` 两类配置。
  2. `WorkspaceRunManager` 已支持 typed executable：`customShell` 继续走 `/bin/zsh -lc`，`remoteLogViewer` 直接走 `/usr/bin/ssh` 结构化参数，不再依赖 shared helper script。
  3. Settings 已移除脚本模板管理入口，`WorkspaceHostView` 配置按钮已改为只打开 typed 运行配置面板；`SharedScriptsManagerView.swift` 已删除。
  4. 旧 `ProjectScript.start + paramSchema + templateParams` 读取时会一次性 flatten 成 `customShell`，因此旧项目数据不会阻塞新模型落地。
- 直接原因：
  1. 旧实现把运行配置主语义压扁成 shell 文本和变量替换协议，导致 `remote_log_viewer.sh` 这类预设在 UI、校验、执行、日志层都失去结构化语义。
  2. 结果就是运行层只能看到“一整段命令字符串”，像 `follow`、`port`、`allowPasswordPrompt` 这种字段都只能继续依赖字符串约定和 shell 解释。
- 设计层诱因：
  1. 旧 shared scripts 同时承担“预设类型定义”和“可执行模板文本”两种职责，模型层级过低。
  2. Settings 里维护全局模板目录，也让运行配置语义和项目上下文分裂。当前已修掉主链，但底层 `LegacyCompatStore` / `SharedScriptModels` 仍残留未引用的 shared-scripts 代码，属于后续可继续删除的遗留清理项。
- 当前修复方案：
  1. Core：引入 `ProjectRunConfiguration` / `ProjectRunConfigurationKind`、`WorkspaceRunExecutable`、`displayCommand`，并让 ViewModel 直接生成 `remoteLogViewer -> ssh args`。
  2. App：重写 `WorkspaceRunConfigurationSheet`，支持 typed 配置新增/编辑/保存；Settings 删掉 scripts 分类与模板管理入口。
  3. 兼容：保留 `Project.scripts` / `saveWorkspaceScripts(...)` 作为过渡别名，方便当前分支其余代码逐步切到 `runConfigurations`。
- 长期改进建议：
  1. 下一轮可以继续删除 `LegacyCompatStore` 中未再引用的 shared-scripts manifest / preset API，以及 `SharedScriptModels.swift`，把“通用脚本系统”从仓库里彻底移除。
  2. 等其余调用点都切到 `runConfigurations` 后，再删除 `Project.scripts` / `saveWorkspaceScripts(...)` 这些兼容入口，避免长期双语义。
- 验证证据：
  - 定向验证：`swift test --package-path macos --filter 'AppSettingsUpdatePreferencesTests|NativeAppViewModelWorkspaceRunTests|WorkspaceRunManagerTests|WorkspaceHostViewRunConsoleTests|WorkspaceScriptConfigurationSheetTests|SettingsViewTests'` → 21 tests，0 failures。
  - 全量回归：`swift test --package-path macos` → 323 tests，5 skipped，0 failures。

## 2026-03-24 第二阶段：彻底清仓 shared scripts + 贴近 IDEA 交互

- [x] 清理 public API 中的 shared-scripts / legacy scripts 别名，只保留旧数据解码迁移能力
- [x] 删除 `SharedScriptModels.swift` 与 `LegacyCompatStore` 中未再使用的 shared-scripts backend 代码
- [x] 清理测试/fixture/文案中的 `sharedScriptsRoot` / 通用脚本残留引用
- [x] 优化运行配置面板交互：创建即定类型、自动建议名称、分组表单、命令预览，更贴近 IDEA 使用习惯
- [x] 重新跑定向验证与全量回归，并补第二阶段 Review

## Review（2026-03-24 第二阶段：彻底清仓 shared scripts + 贴近 IDEA 交互）

- 结果：
  1. shared scripts / 默认模板体系已经从当前运行配置主链里彻底退出：`SharedScriptModels.swift` 已删除，`LegacyCompatStore` 不再提供 manifest / preset / file-editing API，Settings 也不再保留脚本模板入口。
  2. 当前运行配置交互已经更接近 IDEA：创建时确定类型，编辑页不再用类型 picker 来回切换；支持自动建议名称、复制当前配置、remote log 的分组表单，以及只读“命令预览”。
  3. 旧项目数据仍可兼容读取：仅保留 `Project.scripts` 的解码迁移能力，把旧脚本一次性 flatten 成 `customShell`，但新的 public API / UI / store 主链都只认 `runConfigurations`。
- 直接原因：
  1. 第一阶段虽然已经把执行主链切到 typed run configurations，但仓库里仍残留 shared-script model/store/test fixture/current doc 痕迹，导致架构认知仍然分裂。
  2. `WorkspaceRunConfigurationSheet` 也还不够像 IDEA：如果继续保留“编辑页切类型 + 模板入口 + 缺少命令预览”，用户仍需要理解 DevHaven 自己的一套历史概念，使用成本偏高。
- 设计层诱因：
  1. 旧模型长期把“运行配置类型”“模板资产”“兼容解码”“执行命令字符串”混在一起，导致主链已经升级后，仓库边角仍会持续泄漏旧概念。
  2. 未发现新的系统性设计缺陷；当前主要是破坏式升级没有一次性清到仓库边缘，外加配置编辑器仍带有过渡期交互痕迹。
- 当前修复方案：
  1. 模型层：删除 `SharedScriptModels.swift`，把 `GitDailyRefreshResult` 迁到 `GitStatisticsModels.swift`，避免误删 shared-script 文件时把无关公共模型一起带走；`ProjectRunConfiguration.fromLegacyProjectScript(...)` 改为仅供本文件解码迁移使用。
  2. 存储层：`LegacyCompatStore` 删除 shared-scripts backend API，只保留普通 app/projects/document/git metadata 持久化。
  3. UI 层：重建 `WorkspaceRunConfigurationSheet`，保留 `customShell` / `remoteLogViewer` 两类 typed 配置；新增“复制当前配置”“命令预览”“连接设置 / 日志设置 / 安全设置”“suggestedName”，并确保保存路径统一走 `viewModel.saveWorkspaceRunConfigurations(...)`。
  4. 文档/测试：`AGENTS.md` 删除 `~/.devhaven/scripts/*` 当前目录描述；非兼容场景测试 fixture 统一改为 `runConfigurations`，只在专门的 legacy decode 测试里保留旧 `scripts` JSON。
- 长期改进建议：
  1. 如果后续继续向 IDEA 靠拢，下一层最值得补的是 environment variables、before launch、working directory policy，而不是再恢复任何“全局模板目录”。
  2. `customShell` 建议继续作为唯一自由逃生口；常用能力再逐个长成结构化 configuration type，避免重新退回字符串 DSL。
- 验证证据：
  - 定向验证：`swift test --package-path macos --filter 'ScriptTemplateSupportTests|AppSettingsUpdatePreferencesTests|NativeAppViewModelWorkspaceRunTests|WorkspaceRunManagerTests|WorkspaceHostViewRunConsoleTests|WorkspaceScriptConfigurationSheetTests|SettingsViewTests|LegacyCompatStoreTests'` → 24 tests，0 failures。
  - 全量回归：`swift test --package-path macos` → 324 tests，5 skipped，0 failures。


## 2026-03-24 底部 Run Console 面板拖拽高度

- [x] 把底部 Run Console 拖拽高度任务登记到 tasks/todo.md，并明确本轮边界
- [x] 先补失败测试，约束 run console state/host view 持有可调高度与拖拽入口
- [x] 以最小改动实现底部面板拖拽改高，并将高度保存在 workspace runtime state
- [x] 运行定向测试与构建验证，并在 Review 记录直接原因、设计诱因、修复方案与证据

## Review（2026-03-24 底部 Run Console 面板拖拽高度）

- 结果：
  1. workspace 底部 Run Console 现在支持通过顶部拖拽条实时调整高度。
  2. 调整后的高度保存在 `WorkspaceRunConsoleState` 运行时内存里；同一 workspace 内收起再展开会保留刚才的高度，但不会写入持久化配置。
  3. 双击拖拽条会把底部面板重置回默认高度。
- 直接原因：
  1. `WorkspaceRunConsolePanel.swift` 之前把高度写死为 `220`，没有暴露可调高度输入。
  2. `WorkspaceHostView.swift` 之前只负责“有无显示底部面板”，没有分隔条、拖拽手势，也没有把高度写回任何 runtime state。
- 设计层诱因：
  1. 底部 Run Console 已经有独立的 workspace runtime state，但此前只覆盖 session / selection / visible，没有把“面板尺寸”也纳入同一真相源，导致 UI 只能写死高度。
  2. 未发现明显系统设计缺陷；主要是布局状态漏建模，而不是状态源分裂。
- 当前修复方案：
  1. 在 `WorkspaceRunConsoleState` 中新增 `panelHeight` 与默认高度常量，作为底部面板高度的 runtime 真相源。
  2. 在 `NativeAppViewModel` 中新增 `updateWorkspaceRunConsolePanelHeight(...)`，由宿主视图把拖拽后的高度写回当前 workspace run state。
  3. 在 `WorkspaceHostView` 中新增底部拖拽条与 `WorkspaceRunConsoleLayoutPolicy`，负责拖拽手势、默认值与高度 clamp。
  4. `WorkspaceRunConsolePanel` 不再自己写死高度，改为消费宿主传入的 `height`。
- 长期改进建议：
  1. 如果后续用户希望“重启 App 后也记住高度”，再单独评估是否把该值提升到设置层；本轮先保持 runtime-only，避免把纯 UI 偏好扩散进持久化协议。
  2. 若后续还会新增更多可调 panel，可考虑抽出统一的 panel resize handle/布局策略，避免各处重复实现。
- 验证证据：
  - 红灯验证：`swift test --package-path macos --filter 'NativeAppViewModelWorkspaceRunTests|WorkspaceHostViewRunConsoleTests'`（实现前）→ 编译失败，明确提示 `WorkspaceRunConsoleState` 缺少 `panelHeight/defaultPanelHeight`，且 `NativeAppViewModel` 缺少 `updateWorkspaceRunConsolePanelHeight`
  - 绿灯验证：`swift test --package-path macos --filter 'NativeAppViewModelWorkspaceRunTests|WorkspaceHostViewRunConsoleTests'` → 10 tests，0 failures
  - 构建验证：`swift build --package-path macos` → `Build complete!`，exit 0

## 2026-03-24 合并 focus 与 feature/38 worktree

- [x] 审计 current main、focus、feature/38 的提交关系、ahead/behind 与未提交状态
- [x] 确认本次只合并两个 worktree 的已提交内容，并记录可能冲突文件（`AGENTS.md`、`SettingsView.swift`、`AppModels.swift`、`tasks/todo.md`）
- [x] 先将 focus 合并到当前 main，处理必要冲突
- [x] 再将 feature/38 合并到当前 main，处理必要冲突
- [x] 运行针对性测试 / 构建验证合并结果
- [x] 复核 git 状态并在本文件追加 Review（含直接原因、设计层诱因、修复方案、长期建议、验证证据）

## Review（2026-03-24 合并 focus 与 feature/38 worktree）

- 结果：
  1. 已将 `focus` 与 `feature/38` 两个 worktree 的**已提交内容**合并到当前 `main`。
  2. `focus` 里的 workspace 打开项目快捷键 / 终端菜单快捷键路由，与 `feature/38` 里的 typed run configurations / Run Console / Settings 清理现在已经同时存在于当前树上。
  3. 冲突已收口：`AppModels.swift` 同时保留了 `workspaceOpenProjectShortcut` 与 `SettingsNavigationSection` / `runConfigurations` 相关模型；`SettingsViewTests.swift` 同时保留了“打开项目快捷键”与“移除 shared scripts 入口”两类断言；`tasks/todo.md` 也保留了两边历史记录。
- 直接原因：
  1. `focus` 基于当前 `main` 只前进 1 个提交，而 `feature/38` 相对 `main` 处于 `ahead 3, behind 1`，因此第二次合并时会重新触碰已经被 `focus` 改过的设置 / 模型 / 任务记录文件。
  2. 两个 worktree 都改到了 `SettingsView` / `AppModels` 这一组横切面：一个新增 workspace 打开项目快捷键，另一个删除 shared scripts 并引入 typed run configurations，所以冲突不是偶发文本碰撞，而是同一配置面与模型面的真实语义叠加。
- 设计层诱因：
  1. `AppSettings` / `AppModels` 与 `tasks/todo.md` 都是高扇入文件，不同 worktree 同期推进时天然容易冲突。
  2. 未发现新的系统设计缺陷；本轮冲突主要来自两个分支同时修改同一设置与任务记录收口层，而不是主链模型出现真相源分裂。
- 当前修复方案：
  1. 先在当前 `main` 真合并 `focus`，只把已提交内容带回来；`tasks/todo.md` 的 autostash 冲突通过手工保留 focus Review + 本轮 merge checklist 解决。
  2. 再真合并 `feature/38`，把 typed run configurations / Run Console / settings cleanup 合并进来，并在冲突文件里显式保留两边语义。
  3. 用一次 fresh `swift test --package-path macos` 全量回归确认组合结果没有把任何一侧功能合坏。
- 长期改进建议：
  1. 后续若还会并行推进多个 worktree，尽量提前避开 `AppModels.swift` / `SettingsView.swift` / `tasks/todo.md` 这类公共汇聚文件，或拆出更细的子模块，减少合并时的人肉语义拼接成本。
  2. `tasks/todo.md` 作为单文件流水账非常容易形成冲突热点；若后续并行 worktree 更多，可考虑按日期或主题拆分 Review 记录。
- 验证证据：
  - worktree 审计：`git -C /Users/zhaotianzeng/.devhaven/worktrees/DevHaven/focus status --short --branch` → `focus...origin/main [ahead 1]`；`git -C /Users/zhaotianzeng/.devhaven/worktrees/DevHaven/feature/38 status --short --branch` → `feature/38...origin/main [ahead 3, behind 1]`。
  - 合并动作：`git merge --autostash --no-ff focus` → 成功生成 merge commit，随后手工解决 `tasks/todo.md` 的 autostash 冲突；`git merge --no-ff feature/38` → 进入冲突解析，最终保留两边语义后继续完成合并。
  - 全量回归：`swift test --package-path macos` → 344 tests，5 skipped，0 failures。
  - 差异校验：`git diff --check` → 无输出。
