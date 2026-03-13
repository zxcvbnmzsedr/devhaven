# 本次任务清单

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
