# 本次任务清单

## 终端工作区过快回收修复（2026-03-13）

- [x] 定位“工作区一会没看就被回收，运行中的任务被结束”的直接原因
- [x] 先补回归测试，覆盖切项目/非激活工作区时运行中 session 不应被自动结束
- [x] 按最少修改原则修复错误回收链路，并同步必要经验记录
- [x] 运行定向验证并补充 Review 记录

## pane 类型选择回退修复（2026-03-13）

- [x] 定位“打开项目/最后一个 session 退出后直接变 shell”与 pending pane 设计不一致的根因
- [x] 先补回归测试，覆盖默认打开项目与最后一个 session/tab 关闭后的 pending pane 行为
- [x] 按最少修改原则修复默认快照与 fallback tab 的 pane 类型
- [x] 运行定向验证并补充 Review 记录

## DevHaven Agent MVP（2026-03-13）

- [x] 读取实现前必须遵循的技能与当前仓库约束
- [x] 确定「pane 级 shell|agent 双态」MVP 的范围与接入点
- [x] 写入设计文档与实施计划
- [x] 先补前端 helper / 状态流测试，再实现 pane 级 Agent 状态流
- [x] 将 Agent 入口收回到 pane-local overlay，并完成本地验证
- [x] 按用户新反馈回滚错误方向，并重做“pane 本身就是 agent”的方案
- [x] 将 pane 级 agent 实现升级为多 provider adapter（Claude Code / Codex / iFlow）
- [x] 将“创建后切换”改为“创建 pane 时先选 shell/agent 身份”
- [x] 将“创建前选类型”重做为“pane 先出现，再在 pane 内选择 shell/agent”

## OpenCove Agent 代理探索（2026-03-13）

- [x] 读取会话技能、经验与 opencove 项目约束
- [x] 扫描 opencove 中 agent 代理相关入口、核心模块与调用链
- [ ] 提炼 agent 代理的架构模式、状态模型与运行机制
- [ ] 结合当前项目给出可迁移实现方案与风险建议

## 内存优化第一轮实施（2026-03-13）

- [x] 为 Codex monitor 按需启动补失败用例并完成实现
- [x] 为终端输出队列背压补失败用例并完成实现
- [x] 为 replay 缓冲分层预算补失败用例并完成实现
- [x] 更新文档/索引并完成构建、测试、审查结论

## Review（内存优化第一轮实施）

- 已把 Codex monitor 从“冷启动默认拉起”改为**按需启用**：`src/App.tsx` 新增启用门控，`src/hooks/useCodexMonitor.ts` 支持 `enabled` 模式，`src/components/Sidebar.tsx` / `src/components/CodexSessionSection.tsx` 在未启用时展示轻量占位与“启用”按钮；同时进入终端工作区会自动启用监控，保留终端侧 Codex 状态联动。
- 已把 PTY 输出链路从无界 `mpsc::channel` 改成**有界 `sync_channel`**，并补充 `terminal_output_channel_is_bounded` 回归测试，防止高吞吐终端继续通过无界字符串队列顶高 RSS。
- 已把 Rust replay 缓冲改为**分层预算**：活跃 PTY 约 2MiB、后台保活 PTY 约 256KiB；新增 `TerminalReplayMode` 与 `terminal_set_replay_mode` 命令，前端 `TerminalPane` 在 preserve unmount 时主动把后台会话切到 parked 预算。
- 本轮验证通过：`node --test src/utils/codexMonitorActivation.test.mjs src/components/terminal/terminalMemoryPolicy.test.mjs`、`cargo test command_catalog_keeps_web_subset_of_tauri --manifest-path src-tauri/Cargo.toml`、`cargo test terminal_ --manifest-path src-tauri/Cargo.toml`、`cargo check --manifest-path src-tauri/Cargo.toml`、`pnpm build`。

## 内存优化第二轮实施（2026-03-13）

- [x] 为 Codex monitor 扫描链路瘦身补失败用例并完成实现
- [x] 为 terminal / quick-command registry 回收补失败用例并完成实现
- [x] 为终端布局快照启动加载成本收口补失败用例并完成实现
- [x] 更新文档/索引并完成构建、测试、审查结论

## Review（内存优化第二轮实施）

- 已继续瘦身 `src-tauri/src/codex_monitor.rs`：新增 rollout 文件数量上限，避免历史会话很多时一次监控全量处理过多 jsonl；`record_snapshot_state` 已从整份 `CodexMonitorSession` clone 改成轻量 digest，减少快照去重常驻内存；进程探测改为复用 `MonitorRuntime.system`，不再每轮新建 `sysinfo::System`。
- 已给 `src-tauri/src/terminal_runtime/session_registry.rs` 与 `src-tauri/src/terminal_runtime/quick_command_registry.rs` 增加上限回收：当 exited / finished 记录超过容量时，会优先回收最旧的已结束记录，防止长时间运行后 registry 只增不减。
- 已把启动期的终端布局恢复摘要查询改成 **storage 直出**：`src-tauri/src/lib.rs::list_terminal_layout_snapshot_summaries` 不再调用 `ensure_terminal_layout_runtime_loaded`；新的 `src-tauri/src/storage.rs::list_terminal_layout_snapshot_summaries` 会直接从 store 返回 summary，避免应用启动恢复“已打开项目”时就把全部 snapshot 导入 runtime。
- 已同步更新 `AGENTS.md`，记录 runtime registry 回收、summary 直出路径与 Codex monitor 的进一步收口策略，避免实现和文档漂移。
- 本轮验证通过：`cargo check --manifest-path src-tauri/Cargo.toml`、`cargo test codex_monitor::tests::collect_rollout_files_caps_recent_results --manifest-path src-tauri/Cargo.toml`、`cargo test terminal_runtime::session_registry::tests::session_registry_prunes_old_exited_sessions_when_over_capacity --manifest-path src-tauri/Cargo.toml`、`cargo test terminal_runtime::quick_command_registry::tests::quick_command_registry_prunes_finished_jobs_when_over_capacity --manifest-path src-tauri/Cargo.toml`、`cargo test storage --manifest-path src-tauri/Cargo.toml`、`pnpm build`。

## 项目切换回收策略修正（2026-03-13）

- [x] 为“切项目不降级 replay”补失败用例并完成实现
- [x] 更新 lessons / 审查记录并完成验证

## Review（项目切换回收策略修正）

- 用户反馈确认：上一轮把“切项目短暂后台”错误等同于“长期后台保活”，导致 `TerminalPane` 在 preserve unmount 时立刻把 replay 模式切到 `parked`，切回项目后历史输出明显变短。
- 本轮新增 `src/components/terminal/terminalReplayModePolicy.ts` 与对应测试，把当前策略明确固化为：**项目切换 preserve unmount 默认不降级 replay**；仅在未来显式启用时才切到 `parked`。
- `src/components/terminal/TerminalPane.tsx` 已改为通过策略函数决定是否调用 `setTerminalReplayMode`，当前默认返回 `null`，因此切项目不会再主动把后台 PTY 历史预算降到 parked。
- 本轮验证通过：`node --test src/components/terminal/terminalReplayModePolicy.test.mjs src/utils/codexMonitorActivation.test.mjs src/components/terminal/terminalMemoryPolicy.test.mjs`、`pnpm exec tsc --noEmit`、`pnpm build`。

## 快捷命令状态同步修复（2026-03-13）

- [x] 为“快捷命令结束后 Header / Run 面板状态分叉”补失败用例
- [x] 修复 quick command manager / terminal runtime 的 jobId 与结束态同步
- [x] 运行定向验证并补充审查记录

## Review（快捷命令状态同步修复）

- 根因已定位为 **quick command manager 与 terminal runtime registry 双写但 jobId 不一致**：`quick_command_start` 在 manager 中生成一份 jobId，而 runtime registry 又自行新建另一份 jobId，导致后续 `quick_command_stop/finish` 更新的是 manager job，`quick_command_runtime_snapshot` 读到的却仍是 runtime 里那条旧 running job。
- 这会直接造成你看到的现象：顶部 Header 基于 `quick_command_runtime_snapshot` 的 script 级 active job 继续显示“可停止/不可重新运行”，而底部 Run 面板已经依据 `markRunPanelTabExitedInSnapshot` 写入的 `endedAt/exitCode` 显示“已完成”。
- 本轮修复把 runtime start 改为 **以 manager 生成的 jobId 原样 upsert 到 runtime registry**，确保 start / stop / finish / snapshot 全部围绕同一条 job 记录收敛；同时补了回归测试 `sync_runtime_job_start_keeps_runtime_job_id_in_sync` 防止以后再次漂移。
- 本轮验证通过：`cargo test sync_runtime_job_start_keeps_runtime_job_id_in_sync --manifest-path src-tauri/Cargo.toml`、`cargo test quick_command_ --manifest-path src-tauri/Cargo.toml`、`cargo check --manifest-path src-tauri/Cargo.toml`。

## Review（DevHaven Agent MVP）

- 已按 **pane 级 shell|agent 双态** 路线重写设计与计划：`docs/plans/2026-03-13-devhaven-agent-pane-command-design.md`、`docs/plans/2026-03-13-devhaven-agent-pane-command-mvp.md` 不再把 Agent 作为工作区级入口，而是把控制权收回到 pane 本身。
- 已重写 `src/models/agent.ts` 与 `src/models/agent.test.mjs`：当前模型改为 pane 级 agent runtime map，支持带 marker 的 Codex 启动命令包装、输出 marker 解析，以及 `starting -> running -> stopped/failed` 状态迁移。
- 已将运行态 hook 改为 `src/hooks/usePaneAgentRuntime.ts`，不再维护“项目级唯一 Agent”，而是按 `sessionId -> runtime` 跟踪每个 terminal pane 的 agent 状态、pending command 与 pty 绑定。
- 已在 `src/models/terminal.ts` / `src/utils/terminalLayout.ts` 为 terminal 工作区引入 `pendingTerminal` 模型与对应 helper；新建 tab / split pane 不再直接变成 shell 或 agent，而是先出现 pending pane，再在 pane 内完成类型选择。
- 已回滚“创建前选类型”和已定型 pane 右上角状态 UI：`src/components/terminal/TerminalWorkspaceHeader.tsx` 恢复为纯终端头部；`src/components/terminal/TerminalTabs.tsx` 的 “+” 重新只负责创建 pending tab；`src/components/terminal/TerminalPane.tsx` 只保留“新建 Pane”菜单，不再常驻显示 agent provider / 状态 / 停止按钮；新增 `src/components/terminal/TerminalPendingPane.tsx` 承载 `Shell / Codex / Claude Code / iFlow` 选择。
- 已继续把 pane 级模型升级为 **多 provider adapter**：新增 `src/agents/registry.ts` 与 `src/agents/adapters/{codex,claudeCode,iflow}.ts`，当前支持 `Codex / Claude Code / iFlow` 三个 provider；provider-specific 命令由 adapter 生成，并统一走 `src/agents/shellWrapper.ts` 的 marker 包裹。
- 已把交互重做为 **pending pane**：`src/models/terminal.ts` 新增 `pendingTerminal` pane descriptor、`appendPendingTerminalTabToSnapshot`、`realizePendingTerminalPaneInSnapshot`、`splitPendingPaneInSnapshot`；`src/components/terminal/TerminalTabs.tsx` 的 “+” 与 `src/components/terminal/TerminalPane.tsx` 的 “新建 Pane” 现在都只创建 pending pane，再由 `src/components/terminal/TerminalPendingPane.tsx` 在 pane 内部完成 `Shell / Codex / Claude Code / iFlow` 选择。
- 已继续收口视觉：`src/components/terminal/TerminalPendingPane.tsx` 改成更明显的占位卡片样式，并支持**默认聚焦 Shell、上下键切换、Enter 确认**；已定型 `TerminalPane` 不再在右上角常驻显示 provider/状态/停止等 Agent 控件，同时去掉了 settled pane 的“新建 Pane”按钮，避免与终端内容抢视觉注意力。
- 当前限制：运行态仍是前端投影、不支持重启自动恢复/多 provider task 绑定；但这版已经符合“pane 先出现，再在 pane 里决定它是 shell 还是哪个 provider 的 agent”的交互模型。
- 本轮验证通过：`node --test src/models/agent.test.mjs src/models/terminal.snapshot.test.mjs`、`pnpm exec tsc --noEmit`、`pnpm build`。


## collect_git_daily 日志收口（2026-03-13）

- [x] 定位 collect_git_daily 高频日志与自动统计触发链路
- [x] 为 Git Daily 自动刷新策略补失败测试
- [x] 收口自动刷新调度并移除 collect_git_daily 高频 Info 日志
- [x] 运行定向验证并追加 Review

## Review（collect_git_daily 日志收口）

- 直接原因：`src-tauri/src/lib.rs` 的通用 `log_command` / `log_command_result` 会为 `collect_git_daily` 打印 `command start/done`，同时 `collect_git_daily` 自身又额外打印 `paths=`，而前端 `useAppActions` 会在缺失 `git_daily` 时自动分批触发统计，导致日志里反复出现高频 Info。
- 设计层诱因：存在状态建模过粗的问题。前端一直用 `!project.git_daily` 同时表示“未加载 / 空结果 / 失败未写入”，自动补齐流程难以区分“已尝试但为空”和“真的还没统计”。
- 当前修复方案：新增 `src/utils/gitDailyRefreshPolicy.ts`，把 Git Daily 自动调度策略收口为可测试 helper；自动补齐现在会按“路径 + identity 签名”记录本轮已尝试项目，只在启动后/身份变化后对同一项目自动统计一次，避免空结果项目持续重复拉取；同时在 Rust 侧对白名单命令 `collect_git_daily` 关闭高频 Info 命令日志。
- 长期改进建议：将 `Project.git_daily` 的“值”和“加载状态”拆开，例如新增 `gitDailyStatus/gitDailyUpdatedAt/gitDailyError`，从根上区分 idle / loaded / empty / error，届时自动刷新策略就能更精确地决定何时重试。
- 验证证据：`node --test src/utils/gitDailyRefreshPolicy.test.mjs`；`pnpm exec tsc --noEmit`；`cargo check --manifest-path src-tauri/Cargo.toml`。

## Review（pane 类型选择回退修复）

- 直接原因：虽然新建 tab / split pane 已切到 `pendingTerminal`，但默认布局 `createDefaultLayoutSnapshot` 与“最后一个 session / tab 被移除”的 fallback 仍沿用旧的 shell terminal 兜底，所以打开项目或 `Ctrl+D`/shell 退出到最后一个 session 时，会直接生成 shell，会话真相与 pane 类型选择 UI 脱节。
- 设计层诱因：存在**默认入口与新增交互模型未同源收敛**的问题。pending pane 只覆盖了“显式新建 pane”路径，没有同步覆盖初始化和兜底恢复路径，属于状态入口分裂；除此之外，未发现明显系统设计缺陷。
- 当前修复方案：把默认快照和最后一个 session/tab 的 fallback 全部改为 `pendingTerminal`，标题统一为“新建 Pane”；同时补充回归测试，覆盖首次打开项目、最后一个 session 退出、最后一个 tab 关闭三条路径。
- 长期改进建议：将“默认 pending pane 标题/描述”收口为共享常量或 helper，避免未来在不同入口再次出现 shell/pending 文案或类型漂移。
- 验证证据：`node --test src/models/terminal.snapshot.test.mjs src/components/terminal/terminalWorkspaceShellModel.test.mjs`；`pnpm exec tsc --noEmit`；`pnpm build`。

## Review（终端工作区过快回收修复）

- 直接原因：`src/components/terminal/TerminalWorkspaceWindow.tsx` 在 2026-03-10 的性能优化后只挂载当前 `activeProject` 的 `TerminalWorkspaceView`，一旦切到别的项目，原项目 workspace 会立刻卸载；而项目级运行态（尤其 `src/hooks/useQuickCommandRuntime.ts`）在 workspace 卸载时会执行 unmount 清理，把仍在运行的 quick command 标记为“终端会话已关闭”，导致用户感知为“后台任务被很快回收/结束”。
- 设计层诱因：存在**“PTY 保活”和“workspace 运行态保活”职责分裂**问题。`TerminalPane` 只负责会话级 `preserveSessionOnUnmount`，但工作区级的 quick command / agent runtime 仍依赖 React 挂载生命周期；只保活 PTY、不保活 workspace，本质上还是会让后台任务状态失真。除此之外，未发现明显系统设计缺陷。
- 当前修复方案：恢复为**所有已打开项目的 `TerminalWorkspaceView` 都保持挂载**，仅把非激活项目隐藏并禁交互；新增 `src/components/terminal/terminalWorkspaceMountModel.ts` 收口挂载/可见性/dispatch 分发规则，并在 `TerminalWorkspaceWindow` 里按该模型渲染，避免切项目就卸载后台 workspace。
- 长期改进建议：后续如果还想继续做内存优化，应该把 quick command / pane agent 等运行态迁到独立的 durable store，再考虑更细粒度回收；在那之前，不要再次把“后台项目可恢复”简化成“只保 PTY，不保 workspace”。
- 验证证据：`node --test src/components/terminal/terminalWorkspaceMountModel.test.mjs src/models/terminal.snapshot.test.mjs src/components/terminal/terminalWorkspaceShellModel.test.mjs`；`pnpm exec tsc --noEmit`；`pnpm build`。

## cmux Agent 增强方案迁移设计与实施（2026-03-13）

- [x] 对照 DevHaven 当前 agent 增强实现与 cmux 参考方案，梳理关键差异
- [x] 识别当前设计的直接问题、设计层诱因与可迁移边界
- [x] 输出 2-3 个迁移方案并给出推荐方案
- [x] 与用户确认设计结论，并写入设计稿 / 实施计划
- [x] 先补 Rust 控制面 registry / command 的失败测试
- [x] 实现 Rust 控制面 registry、命令与事件
- [x] 为 terminal session 注入 DEVHAVEN_* 控制面环境变量
- [x] 先补前端 control plane projection 的失败测试
- [x] 接入前端 workspace / pane attention projection
- [x] 回退旧 pane-agent provider 主线为纯 terminal primitive
- [x] 更新 AGENTS.md、lessons、Review 并完成整体验证

## Review（cmux Agent 增强方案迁移设计与实施）

- 直接原因：原有 agent 增强把 provider 选择、运行态、通知和 pane 身份耦合在前端 `pendingTerminal + usePaneAgentRuntime + stdout marker` 主线上，导致 agent/session/pane 的真相源分裂。
- 设计层诱因：存在明显的职责分裂——布局真相在 `TerminalLayoutSnapshot`，运行态真相在 React hook，PTY/client 真相在前端 registry 与 Rust session registry，provider 语义又嵌在 UI 交互里；这类结构很难继续演进成 cmux 式 primitive + control plane。
- 当前修复方案：
  1. 新增 Rust 控制面 `src-tauri/src/agent_control.rs`，收口 terminal binding / agent session / notification registry，并暴露 `devhaven_identify/devhaven_tree/devhaven_notify/devhaven_agent_session_event/devhaven_mark_notification_read/devhaven_mark_notification_unread` 与事件 `devhaven-control-plane-changed`。
  2. `src-tauri/src/terminal.rs::terminal_create_session` 现在支持 `workspaceId/paneId/surfaceId` 上下文，并注入 `DEVHAVEN_WORKSPACE_ID / DEVHAVEN_PANE_ID / DEVHAVEN_SURFACE_ID / DEVHAVEN_TERMINAL_SESSION_ID` 等环境变量。
  3. 前端新增 `src/models/controlPlane.ts`、`src/services/controlPlane.ts`、`src/utils/controlPlaneProjection.ts`，并在 `TerminalWorkspaceWindow` / `TerminalWorkspaceHeader` 投影 unread、latest message、attention。
  4. 终端主路径已回退为 pure terminal primitive：默认布局、最后一个 session/tab 的 fallback、`handleNewTab` 与 split 主路径都直接创建 shell terminal；`TerminalWorkspaceView` 已移除 provider-specific 命令注入主线。
- 长期改进建议：
  1. 给外部 agent 增加正式 wrapper / hook 模板（优先 Claude / Codex），把 `devhaven_*` 命令真正接入 shell 工作流。
  2. 第二阶段把 browser surface / shell telemetry（cwd/git/ports/tty）也接入同一控制面，补齐真正的 cmux 风格 primitive 体系。
  3. 继续清理 `src/agents/*`、`usePaneAgentRuntime`、`pendingTerminal` 等兼容残留，避免旧模型长期滞留仓库。
- 验证证据：
  - `node --test src/utils/controlPlaneProjection.test.mjs src/models/terminal.snapshot.test.mjs src/components/terminal/terminalWorkspaceShellModel.test.mjs`
  - `cargo test agent_control --manifest-path src-tauri/Cargo.toml`
  - `cargo test command_catalog --manifest-path src-tauri/Cargo.toml`
  - `cargo test terminal_ --manifest-path src-tauri/Cargo.toml`
  - `cargo check --manifest-path src-tauri/Cargo.toml`
  - `pnpm exec tsc --noEmit`
  - `pnpm build`

## cmux Agent 第二轮收口（外部接入链路）（2026-03-13）

- [x] 为 terminal session 注入可直接调用控制面的 DEVHAVEN_CONTROL_ENDPOINT
- [x] 新增通用 `scripts/devhaven-control.mjs` 与外部 agent hook 模板
- [x] 补 wrapper / web_server / terminal env 相关测试并完成验证

## Review（cmux Agent 第二轮收口）

- 直接原因：虽然第一轮已经有了 Rust 控制面与 `DEVHAVEN_*` 归属环境变量，但外部 agent 进程还缺少“如何真正调用控制面”的固定入口；只有 ID 没有 endpoint，wrapper/hook 仍无法零配置接线。
- 设计层诱因：第一轮只完成了 registry 与前端 projection，没有把“外部进程 -> 控制面命令”的调用约定收口为统一脚本/endpoint，这会让后续每个 provider 都各自重复造轮子。除此之外，未发现新的系统设计缺陷。
- 当前修复方案：
  1. `src-tauri/src/web_server.rs` 新增 loopback base URL 解析，`src-tauri/src/terminal.rs` 在创建 terminal session 时为 shell 注入 `DEVHAVEN_CONTROL_ENDPOINT=http://127.0.0.1:<port>/api/cmd`。
  2. 新增通用脚本 `scripts/devhaven-control.mjs`、`scripts/devhaven-agent-hook.mjs`，以及 provider 模板 `scripts/devhaven-claude-hook.mjs`、`scripts/devhaven-codex-hook.mjs`，让外部 agent 可直接复用现成命令桥接到 `devhaven_notify` / `devhaven_agent_session_event`。
  3. 补充 `scripts/devhaven-control.test.mjs`、`web_server` loopback helper 测试、`terminal::apply_terminal_control_env_includes_http_command_endpoint` 回归测试，确认 endpoint/env 真的可用。
- 长期改进建议：
  1. 把 Claude / Codex 的实际官方 hook 协议进一步适配到这些模板脚本，减少用户手动拼 JSON。
  2. 后续可以把 `DEVHAVEN_CONTROL_ENDPOINT` 与未来的 browser/control surface endpoint 一起统一成更完整的 SDK/CLI。
  3. 继续清理 `src/hooks/usePaneAgentRuntime.ts`、`src/components/terminal/TerminalPendingPane.tsx`、`src/agents/*` 等兼容残留，直到仓库里不再保留旧的 pane-agent 运行时主线。
- 验证证据：
  - `node --test scripts/devhaven-control.test.mjs src/utils/controlPlaneProjection.test.mjs src/models/terminal.snapshot.test.mjs src/components/terminal/terminalWorkspaceShellModel.test.mjs`
  - `cargo test web_server --manifest-path src-tauri/Cargo.toml`
  - `cargo test terminal_ --manifest-path src-tauri/Cargo.toml`
  - `cargo test agent_control --manifest-path src-tauri/Cargo.toml`
  - `cargo test command_catalog --manifest-path src-tauri/Cargo.toml`
  - `cargo check --manifest-path src-tauri/Cargo.toml`
  - `pnpm exec tsc --noEmit`
  - `pnpm build`

## cmux Agent 第三轮清场（2026-03-13）

- [x] 为旧 pending pane 快照补归一化测试并完成实现
- [x] 删除未再使用的 pane-agent 兼容组件 / hook / adapter
- [x] 运行整体验证并补充 Review

## Review（cmux Agent 第三轮清场）

- 直接原因：第二轮之后，外部 agent 接入链路已经具备，但仓库里仍保留 `TerminalPendingPane`、`usePaneAgentRuntime`、`src/agents/*`、`src/models/agent.ts` 等旧 pane-agent 时代的壳层代码；这些文件已经不再参与主路径，却会继续误导后续实现。
- 设计层诱因：如果不在控制面切换完成后及时做一次“删旧模型”的清场，代码库会长期同时存在两套心智模型：一套是 control plane truth，一套是前端 pane-agent truth，后续维护者很容易再次沿错误路径接回旧逻辑。
- 当前修复方案：
  1. 新增 `normalizeLayoutSnapshotForShellPrimitives`，在加载旧布局快照时把 legacy `pendingTerminal` 归一化为 shell terminal，保证兼容历史数据但不再需要 pending UI 主路径。
  2. 删除 `src/components/terminal/TerminalPendingPane.tsx`、`src/hooks/usePaneAgentRuntime.ts`、`src/agents/*`、`src/models/agent.ts` / `src/models/agent.test.mjs` 等不再使用的旧实现。
  3. `TerminalWorkspaceShell` / `PaneHost` 已不再挂 pending pane 选择器；主路径只保留 terminal/run/filePreview/gitDiff/overlay primitive。
- 长期改进建议：
  1. 若未来还需要兼容更老的布局版本，继续把兼容逻辑收口到加载时归一化 helper，而不是恢复旧 UI 组件。
  2. 后续可继续清查 `src/services/agentSessions.ts` / `src/models/agentSessions.ts` 是否仍有价值，避免留下一批新的半接线文件。
  3. 完成 provider 实际 hook 落地后，再决定是否需要单独的 CLI 包或 SDK 层。
- 验证证据：
  - `pnpm exec tsc --noEmit`
  - `node --test scripts/devhaven-control.test.mjs src/utils/controlPlaneProjection.test.mjs src/models/terminal.snapshot.test.mjs src/components/terminal/terminalWorkspaceShellModel.test.mjs`
  - `cargo test agent_control --manifest-path src-tauri/Cargo.toml`
  - `cargo test command_catalog --manifest-path src-tauri/Cargo.toml`
  - `cargo test web_server --manifest-path src-tauri/Cargo.toml`
  - `cargo test terminal_ --manifest-path src-tauri/Cargo.toml`
  - `cargo check --manifest-path src-tauri/Cargo.toml`
  - `pnpm build`

