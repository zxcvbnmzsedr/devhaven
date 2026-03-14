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

## Codex 自动通知与通知自动已读修复（2026-03-14）

- [x] 定位 Codex 自动通知未接通的直接原因与设计层诱因
- [x] 定位通知未自动已读/消失的直接原因与设计层诱因
- [x] 先补失败测试，覆盖 Codex 事件桥接到控制面、切回对应 workspace 后通知自动已读
- [x] 实现最小修复并完成验证/Review

## Review（Codex 自动通知与通知自动已读修复）

- 直接原因：`codex_monitor.rs` 已经能产出 `agent-active / task-complete / task-error / needs-attention` 等真实事件，但 `src/hooks/useCodexIntegration.ts` 之前只把这些事件用于 toast / 系统通知，没有桥接到 `notifyControlPlane()` / `emitAgentSessionEvent()`；同时前端虽然已经有 `markControlPlaneNotificationRead()`，但主路径从未调用，所以测试通知会一直保持 unread。
- 设计层诱因：存在 **Codex monitor 状态流** 与 **control plane 状态流** 两套平行链路，且 notification 生命周期只有“写入/展示”没有“消费”阶段；这属于状态生命周期闭环缺失。
- 当前修复方案：
  1. 新增 `src/utils/codexControlPlaneBridge.ts`，把 `CodexAgentEvent` 映射成统一的 control plane `agentSessionEvent + notification` payload，并在 `useCodexIntegration.ts` 中桥接真实 Codex monitor 事件进入 control plane。
  2. 新增 `src/utils/controlPlaneAutoRead.ts`，并在 `TerminalWorkspaceView.tsx` 中对当前 active workspace 的 unread notifications 自动调用 `markControlPlaneNotificationRead()`，让测试通知在用户已经切到对应工作区时自动消失。
  3. 保留现有 toast / 系统通知提示，但 control plane 现在也会同步收到 `Codex 需要处理 / 执行失败 / 已完成` 等状态。
- 长期改进建议：
  1. 后续可把这条桥接进一步下沉到后端，让 `codex_monitor.rs` 直接接入 `agent_control.rs`，彻底消除前端双状态流。
  2. 现在的自动已读策略是 workspace 级，后续可细化为 pane/surface 级消费策略。
  3. 对 Claude 等 provider 也可复用同样的 bridge helper，逐步统一 provider-neutral notification policy。
- 验证证据：
  - `pnpm exec tsc --noEmit`
  - `node --test src/utils/codexControlPlaneBridge.test.mjs src/utils/controlPlaneAutoRead.test.mjs scripts/devhaven-control.test.mjs src/utils/controlPlaneProjection.test.mjs src/models/terminal.snapshot.test.mjs src/components/terminal/terminalWorkspaceShellModel.test.mjs`
  - `pnpm build`

## Codex wrapper 与原会话监听裁剪评估（2026-03-14）

- [x] 盘点现有 Codex 会话监听、wrapper 与控制面的职责边界
- [x] 追踪当前前后端对 Codex monitor 的实际消费点与依赖链
- [x] 判断 wrapper 是否已完整覆盖 monitor 能力，并给出删除/保留建议
- [x] 记录 Review，补充分析证据

## Review（Codex wrapper 与原会话监听裁剪评估）

- 当前**还不建议直接删除** `codex_monitor` 主链。仓库现状是：wrapper/hook 只负责把事件推到 control plane（`scripts/devhaven-codex-hook.mjs` → `devhaven_agent_session_event` / `devhaven_notify`），而原 monitor 仍承担**全局会话发现、启动后恢复、侧栏 CLI 会话列表、项目级 Codex 运行计数**。
- 直接证据：`src/App.tsx` 仍通过 `useCodexMonitor` 驱动 `Sidebar` 的 `CodexSessionSection` 与 `TerminalWorkspaceWindow` 的 `codexProjectStatusById`；`src/hooks/useCodexIntegration.ts` 仍基于 monitor sessions 生成 `codexSessionViews` 并把 monitor 事件桥接进 control plane。
- wrapper 当前**没有完成产品级全接管**：仓库里只提供了 `scripts/devhaven-control.mjs` / `scripts/devhaven-agent-hook.mjs` / `scripts/devhaven-codex-hook.mjs` 这些接入脚本，没有发现应用内部自动强制所有 Codex 启动都走 wrapper 的链路。
- 即使你本机已经手工接好了 wrapper，当前 control plane 仍是**内存态 registry**（`src-tauri/src/agent_control.rs`），wrapper 也是**事件推送型**而不是快照恢复型；应用重启后，既有 Codex 会话不会自动回灌。原 monitor 通过 `src-tauri/src/codex_monitor.rs` 监听 `~/.codex/sessions` + 轮询进程，恰好补了这块恢复能力。
- 因此更稳妥的结论是：
  1. **现在不能直接删 monitor**；
  2. 若你的目标是避免 monitor 与 wrapper 双上报，优先考虑**先移除/开关掉“monitor 事件 -> control plane”桥接**，而不是先删掉会话发现能力；
  3. 等 control plane 补齐“会话列表 / 项目级运行计数 / 启动恢复 / 全量 wrapper 接管”后，再删除 `codex_monitor.rs`、`useCodexMonitor.ts`、`CodexSessionSection.tsx` 这一整套。
- 本次分析证据命令：`rg -n "codex_monitor|useCodexMonitor|get_codex_monitor_snapshot|codex-monitor" src src-tauri scripts`、`rg -n "devhaven-codex-hook|DEVHAVEN_CONTROL_ENDPOINT|devhaven_notify|devhaven_agent_session_event" src src-tauri scripts`、`sed -n '1,260p' src/hooks/useCodexIntegration.ts`、`sed -n '1,260p' src/hooks/useCodexMonitor.ts`、`sed -n '1,260p' scripts/devhaven-codex-hook.mjs`、`sed -n '1,280p' src-tauri/src/agent_control.rs`。

## Codex monitor 删除迁移方案设计（2026-03-14）

- [ ] 盘点删除 Codex monitor 前必须保留的用户能力、数据源与恢复链路
- [ ] 明确 wrapper/control plane 接管 monitor 所需补齐的能力缺口
- [ ] 设计分阶段迁移方案、风险控制与回滚点
- [ ] 产出迁移清单与验收标准，并记录 Review


## Codex wrapper 误报执行失败修复（2026-03-14）

- [x] 复现并定位 Codex 会话为何被持续误判为 `task-error`
- [x] 对照现有实现与参考模式，确认最小修复边界
- [x] 先补失败测试，覆盖“成功 tool output 仅因包含 error/failed 字样而被误判”的回归场景
- [x] 实现修复并完成针对性验证
- [x] 追加 Review，记录直接原因、设计诱因、修复方案与长期建议

## Review（Codex wrapper 误报执行失败修复）

- 直接原因：`src-tauri/src/codex_monitor.rs` 之前在解析 `response_item.type=function_call_output` 时，直接对整段 `output` 文本做关键字扫描；只要成功输出里出现 `error` / `failed` / `task-error` 之类字样，就会把当前会话打成 `CodexMonitorState::Error`。而 Codex 的真实 tool 输出经常会把源代码、grep 命中、编译日志片段原样塞进 `output`，即使前面已经明确写着 `Process exited with code 0`，也会被误判成失败。
- 设计层诱因：monitor 当前把“结构化状态信号”与“自由文本内容”混在同一条判定链路里，缺少“优先信结构化字段、谨慎处理自由文本”的边界；这和 cmux 里 hook/notify 主要依赖显式事件类型驱动状态切换的思路相反。除此之外，未发现新的系统设计缺陷。
- 当前修复方案：
  1. 为 `function_call_output` 单独增加 `function_call_output_indicates_error()`，优先读取结构化 `is_error=true`，其次只识别标准的 `Process exited with code <非 0>` / `Process exited with signal ...`，不再扫描整段成功输出里的任意关键字。
  2. `classify_entry()` 的文本匹配改为**只看值、不看对象 key**，避免 `is_error: false` 这种字段名本身就把会话误判成 error。
  3. 新增 3 个回归测试：
     - 成功 `function_call_output` 即使正文含有 `task-error` 字样也应保持 `Completed`
     - 非 0 exit code 仍应判定为 `Error`
     - `is_error: false` 不应仅因字段名包含 `error` 被误判
- 长期改进建议：
  1. 后续如果继续增强 Codex monitor，优先补“结构化事件 -> 状态”的显式映射，而不是继续扩大自由文本关键字匹配范围。
  2. 若未来 wrapper 真正全量接管状态上报，可以把 monitor 收缩成恢复/发现能力，减少再次从 `.jsonl` 里猜状态的职责。
  3. 可补一个真实样本回放测试集，覆盖 `exec_command`/`cargo`/`pnpm`/`rg` 等常见 tool 输出，避免再被日志内容误伤。
- 验证证据：
  - `cargo test parse_session_file_keeps_successful_function_call_output_with_error_text_completed --manifest-path src-tauri/Cargo.toml`
  - `cargo test classify_entry_does_not_treat_is_error_false_key_name_as_error --manifest-path src-tauri/Cargo.toml`
  - `cargo test parse_session_file_marks_error_when_function_call_output_reports_non_zero_exit_code --manifest-path src-tauri/Cargo.toml`
  - `cargo test codex_monitor --manifest-path src-tauri/Cargo.toml`
  - `cargo check --manifest-path src-tauri/Cargo.toml`

## Codex 完成通知缺失排查（2026-03-14）

- [x] 收集最新现象证据，确认完成事件是否从 monitor 生成
- [x] 对照 wrapper / bridge / control plane 链路定位中断层
- [x] 先补失败测试，再实现最小修复
- [x] 运行针对性验证并补 Review

## Review（Codex 完成通知缺失排查）

- 直接原因：`src-tauri/src/codex_monitor.rs` 的 `process_event_msg()` 之前没有处理 `event_msg.payload.type = "task_complete"`。而我抽样检查最近 67 份带 `task_complete` 的 Codex session，发现至少有 2 份**没有任何 assistant message，只在最后写了 `task_complete`**。这类完成态会被 monitor 直接落成 `Idle`，于是不会产出 `task-complete` 事件，也就没有 toast / 系统通知 / 控制面通知。
- 设计层诱因：当前 monitor 同时兼容“从 assistant message 推断完成”和“从显式 session event 恢复状态”两种来源，但完成态路径只实现了前者，没有把 Codex 已经给出的显式 `task_complete` 事件接入同一真相链路，属于状态源接线不完整。除此之外，未发现新的明显系统设计缺陷。
- 当前修复方案：
  1. 在 `process_event_msg()` 中显式处理 `task_complete`，把它视为完成信号，更新 `last_assistant_ts / last_agent_activity_ts`。
  2. 当 `task_complete` 自身不带正文时，如果此前没有更好的 details，就回退为 `任务已完成`，保证会话状态可解释。
  3. 新增回归测试 `parse_session_file_marks_completed_when_task_complete_has_no_assistant_message`，锁住“只有显式 task_complete 也必须完成”的场景。
- 长期改进建议：
  1. 把 monitor 中所有 provider 显式事件（例如 `task_complete / task_error / needs_attention`）统一纳入结构化事件优先的判定链，减少对消息文本推断的依赖。
  2. 如果后续 wrapper 接管更完整，可以把 monitor 进一步收缩为“恢复/发现兜底”，避免重复猜状态。
  3. 追加真实 session 样本回放测试，覆盖“无 assistant message 直接 task_complete”的 provider 变体。
- 验证证据：
  - `cargo test parse_session_file_marks_completed_when_task_complete_has_no_assistant_message --manifest-path src-tauri/Cargo.toml`
  - `cargo test parse_session_file_keeps_successful_function_call_output_with_error_text_completed --manifest-path src-tauri/Cargo.toml`
  - `cargo test codex_monitor --manifest-path src-tauri/Cargo.toml`
  - `cargo check --manifest-path src-tauri/Cargo.toml`

## Codex 控制面通知已写入但 UI 不显示排查（2026-03-14）

- [x] 收集 control plane tree / projection / auto-read 证据
- [x] 定位 toast / 系统通知 / 最新消息分别为何未出现
- [x] 先补失败测试，再实现最小修复
- [x] 完成验证并补 Review

## Review（Codex 控制面通知已写入但 UI 不显示排查）

- 直接原因：这次日志已经证明 `devhaven_agent_session_event` 与 `devhaven_notify` 都成功执行，问题不在后端命令失败，而在**前端没有以 control plane notification 作为统一的 UI 通知源**。当前 toast / 系统通知只由 `useCodexIntegration` 里的 codex monitor 事件流触发；当外部 wrapper 直接写入 control plane（`devhaven_notify`）时，UI 不会额外弹 toast / 系统通知。另一方面，终端头部的“最新消息”文案优先取 pane projection，而 `projectControlPlaneSurface()` 只在 `unreadCount > 0` 时才返回 notification message；通知一旦被 active workspace 自动已读，inline latest message 就立刻消失。
- 设计层诱因：目前存在 **monitor 事件流** 与 **control plane notification 流** 两套并行的“用户提示”来源，但 UI 只消费前者、头部 latest message 又只消费 unread pane 视角，导致 wrapper 直写 control plane 时出现“后端有记录、前端无反馈”的断层。这属于通知消费真相源分裂。除此之外，未发现新的明显系统设计缺陷。
- 当前修复方案：
  1. `useCodexIntegration.ts` 新增对 `devhaven-control-plane-changed` 的监听：当 reason=`notification` 时，回读对应 workspace tree，提取本次新写入的 Codex 通知，并统一触发 toast / 系统通知；这样 monitor 桥接和 wrapper 直写都会走同一条 UI 提示链。
  2. monitor 事件桥接仍负责把 Codex 状态写入 control plane，但当该事件已经会生成 control plane notification 时，不再直接在同一个 effect 里重复 toast，避免后续双提示。
  3. `TerminalWorkspaceHeader.tsx` 现在会在 active pane latest message 为空时回退显示 workspace 级 latest message，因此通知被 auto-read 后，头部仍能看到最近一条控制面消息，而不是立刻清空。
  4. `ControlPlaneNotification` 前端模型补齐 `updatedAt`，并新增 helper / 测试覆盖“按事件时间提取新通知”“pane 文案为空时回退 workspace latest message”。
- 长期改进建议：
  1. 后续把 toast / 系统通知彻底统一到 control plane notification 真相源，逐步让 monitor 只负责写入状态，不再直接承担 UI 提示。
  2. 若要进一步减少竞态，可让后端 `devhaven-control-plane-changed` payload 直接携带 notification record，而不是前端再回读 tree。
  3. 空 session 文件 warning 仍是噪音，后续可把“新建但尚未写入 session_meta 的空 rollout 文件”降级为静默跳过，避免干扰排障。
- 验证证据：
  - `node --test src/utils/controlPlaneAutoRead.test.mjs src/utils/controlPlaneProjection.test.mjs src/utils/codexControlPlaneBridge.test.mjs`
  - `pnpm exec tsc --noEmit`

## Codex 通知链路最小诊断日志（2026-03-14）

- [x] 检查事件订阅/派发实现，选定最小日志打点位置
- [x] 补充前端诊断日志并给出复现观察点
- [ ] 根据日志结果继续缩小根因范围
- [x] 更新 Review 与证据

## Review（Codex 通知链路最小诊断日志）

- 当前结论：需要前端运行时日志来判断 control-plane changed 事件是否到达 `useCodexIntegration.ts`、tree 回读后是否拿到了新 notification、以及 `showToast()` / `sendSystemNotification()` 是否真正被调用。后端日志已经证明 `devhaven_notify` 成功，因此下一步应该看前端链路，而不是继续猜 Rust 侧是否没写入。
- 本轮新增诊断打点：
  1. `src/hooks/useCodexIntegration.ts`：打印 `control-plane-changed` payload、tree 回读结果、提取到的新通知、monitor event -> control plane 映射结果，以及是否进入 direct toast / delegated 流程。
  2. `src/hooks/useToast.ts`：打印 `showToast()` 是否真的被调用。
  3. `src/services/system.ts`：打印系统通知 API 是否可用、权限状态、以及是否真正 dispatch。
- 建议你下一轮复现时打开前端控制台，重点过滤关键字：`[codex-debug]`。
- 重点观察顺序：
  1. 是否出现 `[codex-debug] control-plane-changed`；若没有，说明前端根本没收到事件。
  2. 若有，再看 `[codex-debug] loaded control-plane tree` / `collected new control-plane notifications`；若为空，说明 tree 回读/筛选条件有问题。
  3. 若已经出现 `[codex-debug] forwarding control-plane notification to toast/system`，再看是否有 `[codex-debug] showToast invoked`；若没有，说明 effect 逻辑被提前 return。
  4. 若 `showToast invoked` 已出现但 UI 仍不显示，再转查 toast 渲染层。
- 验证证据：
  - `pnpm exec tsc --noEmit`

## Codex 控制面事件订阅诊断增强（2026-03-14）

- [x] 给前端 listener 注册/卸载路径补生命周期日志
- [x] 给 Rust emit_control_plane_changed 补发射日志
- [ ] 让用户复现并采集新日志
- [x] 更新 Review 与证据

## Review（Codex 控制面事件订阅诊断增强）

- 当前结论：既然后端 `devhaven_notify` 已成功，而前端连一条 `[codex-debug] control-plane-changed` 都没有，那么还需要区分是“前端 listener 根本没注册成功”还是“Rust emit 发了但 Tauri 前端没收到”。
- 本轮新增诊断：
  1. `src/hooks/useCodexIntegration.ts` 现在会打印 listener effect mount / register / cleanup 生命周期日志，用来确认前端是否真的完成了 `listenControlPlaneChanged()` 注册。
  2. `src-tauri/src/agent_control.rs::emit_control_plane_changed()` 现在会打印每次发射的 `project_path / workspace_id / reason / updated_at`，用来确认 Rust 是否真的进入 emit。
- 下一轮请你重启应用后复现，并同时看两处日志：
  1. **前端控制台**：查 `[codex-debug] useCodexIntegration control-plane listener effect mounted` 与 `[codex-debug] control-plane listener registered`
  2. **Tauri 后端日志**：查 `emit_control_plane_changed project_path=... reason=notification`
- 判定方法：
  - 若后端有 `emit_control_plane_changed ... reason=notification`，但前端没有 `listener registered`，说明前端订阅没起来。
  - 若前端有 `listener registered`，后端也有 `emit_control_plane_changed`，但仍没有 `control-plane-changed`，说明问题更可能在 Tauri event 投递链。
- 验证证据：
  - `pnpm exec tsc --noEmit`
  - `cargo check --manifest-path src-tauri/Cargo.toml`

## Codex 前端 bundle / 事件注册诊断（2026-03-14）

- [x] 检查前端最早期挂载与 Tauri 事件注册点，选定最小全局日志打点
- [x] 补全局挂载/事件注册日志并给出复现观察点
- [ ] 根据结果判断是前端 bundle 未更新还是事件订阅链断裂
- [x] 更新 tasks/todo.md 记录本轮诊断

## Review（Codex 前端 bundle / 事件注册诊断）

- 当前结论：既然你前端连 `useCodexIntegration` 里最早期的 `[codex-debug]` 都看不到，下一步必须先确认“最新前端 bundle 是否真的在跑”。
- 本轮新增最前置打点：
  1. `src/App.tsx`：`AppLayout mounted` 日志，验证 React 根组件是否加载了最新 bundle。
  2. `src/platform/eventClient.ts`：Tauri runtime 下每次 `listenEvent()` 都会打印 `registering tauri listener`，验证事件订阅代码是否执行。
- 下一轮请你重启应用后先不要触发 Codex，直接打开前端控制台看是否至少出现：
  - `[codex-debug] AppLayout mounted`
  - `[codex-debug] registering tauri listener`
- 判定方法：
  - 若这两条都没有，优先说明你当前看到的前端不是最新 bundle（或 DevTools 没连到实际渲染窗口）。
  - 若这两条有，但 `useCodexIntegration` listener 相关日志没有，再继续收缩到 hook 挂载条件。
- 验证证据：
  - `pnpm exec tsc --noEmit`

## Codex 通知显示修复（2026-03-14）

- [x] 先补系统通知/Toast 可见性的失败测试或最小验证用例
- [x] 改为 Tauri 原生系统通知实现，并保留 Web fallback
- [x] 提升 Toast 可见性，确保终端工作区内明显可见
- [x] 完成验证并补 Review

## Review（Codex 通知显示修复）

- 直接原因：日志已证明 control plane notification 会到达前端，并且 `showToast()` 已被调用；真正的问题分成两层：
  1. 系统通知之前一直走浏览器 `Notification` API，在 Tauri 环境里会被权限/用户手势限制拦住；你日志里已经明确出现 `Notification prompting can only be done from a user gesture` 和 `permission: denied`。
  2. Toast 虽然已触发，但原样式是底部居中的轻量胶囊，和终端工作区重叠时不够醒目，导致主观上像“没出现”。
- 设计层诱因：桌面应用场景里仍复用了浏览器通知能力，而没有优先走 Tauri/native 路径；同时全局 Toast 在终端场景下缺少足够强的视觉层级。这属于“运行环境能力选择不匹配 + 反馈可见性不足”。除此之外，未发现新的系统设计缺陷。
- 当前修复方案：
  1. Rust 侧 `src-tauri/src/system.rs` 新增 `send_system_notification`，在 macOS 通过 `osascript display notification` 发送原生系统通知；并补了 AppleScript 字符串转义与脚本文案测试。
  2. Tauri 命令层新增 `send_system_notification`（`src-tauri/src/lib.rs` / `src-tauri/src/command_catalog.rs`），前端 `src/services/system.ts` 在 Tauri runtime 下优先走该命令，仅在失败时回退浏览器 `Notification` API。
  3. `src/App.tsx` 把全局 Toast 调整为右上角高对比卡片（更高 z-index、阴影、白字、明显边框），避免在终端工作区中不易察觉。
- 长期改进建议：
  1. 后续若要支持 Windows/Linux，可继续在 `src-tauri/src/system.rs` 按平台实现原生通知，而不是依赖浏览器 API。
  2. 全局通知可以进一步统一成“控制面通知中心 + Toast + 原生系统通知”三层策略，并允许用户配置等级映射。
  3. 当前排障用 `[codex-debug]` 日志仍保留，等你确认行为恢复后可以再收敛清理一轮。
- 验证证据：
  - `cargo test system::tests --manifest-path src-tauri/Cargo.toml`
  - `pnpm exec tsc --noEmit`
  - `cargo check --manifest-path src-tauri/Cargo.toml`

## Codex task-error 误判根因排查（2026-03-14）

- [x] 检查 monitor 的 error 判定分支并设计最小诊断
- [x] 补失败测试与诊断日志，锁定哪条规则产生 task-error
- [x] 实现最小修复并验证
- [x] 更新 Review 与证据

## Review（Codex task-error 误判根因排查）

- 直接原因：通过回放你日志里的真实 session `rollout-2026-03-14T13-19-49-019ceac9-5873-76d2-843d-6dc28eab201e.jsonl` 可以看出，会话本身其实只有 `task_started -> user_message -> agent_reasoning -> agent_message -> task_complete`，并没有真实失败事件；之所以前端 earlier 收到 `task-error`，是因为 `parse_session_file()` 会把首行 `session_meta` 也送进 `process_entry()`，而旧逻辑把所有未知顶层 type 都交给 `entry_indicates_error()` 做关键字扫描。`session_meta.payload.base_instructions / 用户上下文` 里天然可能包含 `error` / `failed` 等英文单词，于是会把 `last_error_ts` 提前打上；后续 `agent_reasoning` 又把 details 改成 `运行中`，最终就形成了你看到的“event.type = task-error，但 details = 运行中”的矛盾组合。
- 设计层诱因：monitor 之前把**元数据记录**（`session_meta`）和**运行态记录**放在同一条启发式错误判定链里，没有把“仅用于描述上下文的静态记录”与“真正代表运行结果的事件记录”隔离开。这属于状态判定边界不清。除此之外，未发现新的系统设计缺陷。
- 当前修复方案：
  1. `src-tauri/src/codex_monitor.rs::process_entry()` 现在显式忽略顶层 `session_meta`，不再对它做错误关键字扫描。
  2. 新增回归测试 `parse_session_file_ignores_error_keywords_inside_session_meta`，覆盖“session_meta 文本里即使出现 error/failed，也不能把会话判成 Error；运行中仍应保持 Working + 运行中 details”这个场景。
- 长期改进建议：
  1. 后续可继续把 `task_started` 等纯元数据/生命周期记录也显式分类处理，避免再落入 unknown fallback。
  2. monitor 的未知分支最好逐步从“全文关键字扫描”收敛成“只对白名单字段/结构做判定”，减少被提示词、上下文文案误伤。
  3. 等 wrapper 全量接管后，monitor 继续收缩为恢复/发现层，降低启发式推断权重。
- 验证证据：
  - `cargo test parse_session_file_ignores_error_keywords_inside_session_meta --manifest-path src-tauri/Cargo.toml`
  - `cargo test codex_monitor --manifest-path src-tauri/Cargo.toml`
  - `cargo check --manifest-path src-tauri/Cargo.toml`

## Codex 文件扫描收口（2026-03-14）

- [x] 定位 Codex 文件频繁扫描的直接触发链路，并确认 adapter/control plane 已覆盖的状态来源
- [x] 先补回归测试，覆盖“终端工作区不再自动启用 Codex 文件监控”与“终端 Codex 运行态可由 control plane 派生”
- [x] 按最少修改原则收口自动启用链路，并把终端 Codex 状态改走 control plane
- [x] 运行定向验证、更新文档，并追加 Review 结论

## Review（Codex 文件扫描收口）

- 直接原因：`src/App.tsx` 里 `resolveCodexMonitorEnabled` 只要检测到 `terminal.showTerminalWorkspace=true` 就会启用 `useCodexMonitor`；而 `useCodexMonitor` 一旦启用就会立即调用 `get_codex_monitor_snapshot`，该命令在 `src-tauri/src/lib.rs` 中会先执行 `codex_monitor::ensure_monitoring_started`，从而拉起 `src-tauri/src/codex_monitor.rs` 的目录 watcher 与进程轮询线程，并持续扫描 `~/.codex/sessions`。
- 设计层诱因：存在**状态真相源分裂**。终端区“Codex 是否在运行”本来已经可以由 adapter 写入的 control plane 直接投影，但此前 UI 仍同时依赖 monitor 文件扫描产出的 `codexProjectStatusById`，导致“进入终端工作区”这种纯 UI 行为误触发了后台文件扫描链路。
- 当前修复方案：1）把 `src/utils/codexMonitorActivation.ts` 收口为**仅手动启用侧栏会话区时才开启 monitor**；2）给 `src/utils/controlPlaneProjection.ts` 新增 `countRunningProviderSessions`，让 `src/components/terminal/TerminalWorkspaceWindow.tsx` 的项目/worktree/终端头部 Codex 运行态全部直接从 control plane 中按 provider=`codex` 派生，不再依赖 monitor 文件扫描。
- 长期改进建议：如果后续确定 adapter/control plane 已覆盖侧栏“CLI 会话”所需信息，可以继续把 `useCodexIntegration` 里仅服务于 monitor 的聚合逻辑逐步迁出或降级为兼容层，最终让 `src-tauri/src/codex_monitor.rs` 只保留显式调试/兼容入口，而不是常态状态源。
- 验证证据：`node --test src/utils/codexMonitorActivation.test.mjs src/utils/controlPlaneProjection.test.mjs`、`pnpm exec tsc --noEmit`、`pnpm build`。

## Codex monitor 全链路移除（2026-03-14）

- [x] 补删除导向的回归测试，并锁定需要移除的前后端入口
- [x] 清理前端 Codex monitor 入口、Sidebar 会话区块及相关类型/helper
- [x] 删除 Rust 侧 codex_monitor 模块、命令注册与监控模型，并同步 AGENTS 文档
- [x] 运行定向测试、类型检查、构建与 Rust 校验，追加 Review 结论

## Review（Codex monitor 全链路移除）

- 直接原因：即使上一轮已经把“进入终端工作区自动启用 monitor”收口掉，仓库里仍保留完整的 `Codex monitor -> App -> Sidebar -> Rust codex_monitor.rs` 兼容链路；这会继续制造两套状态心智，并让未来任何人都有机会再次把 `~/.codex/sessions` 扫描接回主路径。
- 设计层诱因：存在明显的**兼容路径滞留**问题。系统主路径已经切到 adapter/control plane，但 monitor 的前端 hook、会话视图、Rust 命令、模型和依赖仍完整留存，属于职责边界没有彻底收口；除此之外，未发现新的系统设计缺陷。
- 当前修复方案：
  1. 前端删除 `useCodexMonitor`、`src/services/codex.ts`、`src/components/CodexSessionSection.tsx`、`src/utils/codexMonitorActivation.ts`、`src/models/codex.ts`、`src/utils/codexControlPlaneBridge.ts`，`Sidebar` 不再展示基于文件扫描的 CLI 会话区块。
  2. `src/hooks/useCodexIntegration.ts` 已收口为**仅监听 control plane 中的 Codex 通知**，不再桥接 monitor 事件，也不再维护 monitor session 到 project 的映射。
  3. Rust 侧删除 `src-tauri/src/codex_monitor.rs`、`get_codex_monitor_snapshot` 命令、`command_catalog` 对应 Web 入口以及只服务 monitor 的模型；`Cargo.toml` 同步移除 `notify` / `sysinfo` 依赖。
  4. 终端区的 Codex 运行态继续直接走 `src/utils/controlPlaneProjection.ts::countRunningProviderSessions`，不回退到 monitor。
- 长期改进建议：如果未来需要“应用重启后恢复 agent 会话列表”这类能力，应该在 control plane / agent registry 层补持久化或快照恢复，而不是重新引入 `~/.codex/sessions` 轮询。
- 验证证据：
  - `node --test src/utils/controlPlaneProjection.test.mjs`
  - `cargo test command_catalog_keeps_web_subset_of_tauri --manifest-path src-tauri/Cargo.toml`
  - `pnpm exec tsc --noEmit`
  - `pnpm build`
  - `cargo check --manifest-path src-tauri/Cargo.toml`
