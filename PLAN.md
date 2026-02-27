# Quick Command Lifecycle Refactor Plan

## 背景
当前快捷命令运行/停止主要依赖前端解析终端输出中的 `qc-exit` 标记，这在复杂命令、嵌套 shell、异常中断场景下容易产生状态漂移。

本计划目标是把“运行态真相源”迁移到后端进程生命周期事件，逐步对齐 VSCode/IDEA 的运行管理模式。

## 总目标
- 用后端作业状态机替代前端文本解析主逻辑。
- 停止流程升级为“软停优先，超时硬停”。
- 保留灰度与回滚能力，避免一次性大切换。

## 分期计划

### Phase 1（兼容期）: 后端作业层落地（不改变现有用户行为）
- [x] 新增 `QuickCommandSupervisor` 模块（状态机 + 作业表 + 事件分发）。
- [x] 新增 Tauri Commands：
  - `quick_command_start`
  - `quick_command_stop`
  - `quick_command_list`
  - `quick_command_snapshot`
- [x] 新增统一事件：`quick-command-event`（started/state_changed/exited）。
- [ ] 增加 feature flag：`quick_command_engine`（`v1`/`v2`），默认 `v1`。
- [x] `src-tauri/src/lib.rs` 注册新状态与命令（先并存，不替换旧链路）。

**验收标准**
- [x] `cargo check` 通过。
- [x] 新命令可调用并返回结构化数据。
- [x] 事件可被前端订阅到（至少 started/exited）。

### Phase 2（切流期）: 前端切到 v2 事件（双轨到单轨）
- [x] 新增前端 service：`src/services/quickCommands.ts`（已接入主路径）。
- [ ] 终端快捷命令面板改为消费 `quick-command-event` 作为主信号。
- [ ] 运行态改成状态机：`starting/running/stopping/stopped/failed`。
- [x] 停止策略：先软停，超时自动升级硬停。
- [x] `qc-exit` 降级为兜底，不再主导状态判定。

**验收标准**
- [ ] 多命令并发时状态不串。
- [ ] 停止按钮在软停/硬停阶段反馈准确。
- [ ] `pnpm tsc --noEmit` 通过。

### Phase 3（收口期）: 清理旧链路并固化恢复能力
- [x] 移除 `wrapQuickCommandForShell` 的主链路依赖。
- [x] 下线 `terminal-quick-command-run/stop` 事件与 pending 队列逻辑。
- [ ] 增加作业快照持久化与重启恢复。
- [x] 更新 `AGENTS.md` 功能地图与命令索引。

**验收标准**
- [ ] 新架构路径覆盖主流程（run/stop/exit/recover）。
- [ ] 回滚开关验证可用。

## 风险与回滚
- 关键风险：终端 session 与作业状态解耦后的一致性问题。
- 缓解：全程保留 `v1` 路径 + feature flag。
- 回滚：将 `quick_command_engine` 切回 `v1`，恢复旧行为。

## 当前迭代执行清单（本次先做）
- [x] 输出迁移计划文档 `PLAN.md`。
- [x] 开启 subagent 实施 Phase 1 后端骨架。
- [x] 主进程审阅并合并改动。
- [x] 进行最小编译验证并汇报。
