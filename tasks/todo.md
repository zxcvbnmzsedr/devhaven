# Quick Command 重构任务清单

- [x] 现状审查：梳理 quick command 运行/停止/结束链路与竞态点
- [x] 后端状态机收敛：实现严格迁移、幂等 finish/stop、终态保护
- [x] 前端监听改造：接入 quick command snapshot + event，改为事件驱动
- [x] 停止闭环改造：软停 -> 超时硬停 -> 终态收口，避免状态漂移
- [x] 运行/停止竞态修复：处理 run 后立即 stop、重复 finish 等问题
- [x] 验证：类型检查与关键流程自测

---

## Review
- 采用“后端状态机 + 前端快照/事件对账”的执行模型，避免前端本地状态漂移。
- 运行与停止链路加入幂等保护（finish once）和 run->stop 启动竞态兜底。
- 补充会话关闭时的任务终态回写，减少 running/stopping 残留任务。
- 本地验证通过：`npm run build`、`cargo check --manifest-path src-tauri/Cargo.toml`。

---

# Codex 终端浮层移除任务清单

- [x] 删除前端终端 Pane 右上角 Codex 模型/推理强度浮层渲染
- [x] 删除前端 overlay 轮询与启动输出解析逻辑
- [x] 删除前端 `get_terminal_codex_pane_overlay` service 封装
- [x] 删除 Tauri `get_terminal_codex_pane_overlay` command、模型结构与后端实现
- [x] 更新 `AGENTS.md` 功能地图，移除浮层说明
- [x] 验证构建：`npm run build` 与 `cargo check --manifest-path src-tauri/Cargo.toml`

## Review
- 本次改动只移除了“终端 pane 右上角浮层”链路，未影响侧栏 Codex 会话监控与运行状态聚合能力。
- Rust 侧同时清理了仅服务该浮层的 rollout/lsof/process-tree 代码，避免保留死代码和无效 command。

---

# App.tsx 拆分重构任务清单

- [x] 提取纯函数到 `src/utils/worktreeHelpers.ts`
- [x] 提取基础 hooks：`useToast`、`useProjectSelection`、`useProjectFilter`
- [x] 提取终端/worktree hooks：`useTerminalWorkspace`、`useWorktreeManager`
- [x] 提取 Codex 与命令面板 hooks：`useCodexIntegration`、`useCommandPalette`
- [x] 追加视图/业务聚合 hooks：`useAppViewState`、`useAppActions`
- [x] 重组 `src/App.tsx`，保持渲染行为不变并将文件收敛到 < 350 行
- [x] 更新 `AGENTS.md` 功能定位
- [x] 构建验证：`npm run build`

## Review
- `src/App.tsx` 从 2336 行收敛到 349 行，职责聚焦为“组装 hooks + 渲染树”。
- 终端、worktree、命令面板、Codex 监控与筛选逻辑全部迁入独立 hooks，降低跨域耦合。
- 补充 `useAppActions` / `useAppViewState` 统一承接批量操作与顶层视图状态，减少 App 内业务噪声。
- 构建已通过（`tsc && vite build`），未改动 Tauri 命令与存储结构，功能链路保持不变。

---

# TerminalWorkspaceView 拆分任务清单

- [x] 提取 `useQuickCommandRuntime`：收敛快捷命令运行/停止/快照/事件/终态回写逻辑
- [x] 提取 `useQuickCommandDispatch`：处理外部 run/stop 派发与 pending 队列
- [x] 提取 `useQuickCommandPanel`：管理快捷命令浮层初始化与拖拽定位
- [x] 提取 `QuickCommandsPanel` 组件：承接浮层 UI 渲染
- [x] 提取 `TerminalWorkspaceHeader` 组件：承接头部栏 UI
- [x] 重构 `TerminalWorkspaceView`：改为 Hook + 子组件组合编排
- [x] 更新 `AGENTS.md` 终端工作区定位说明
- [x] 验证构建：`npm run build`

## Review
- 快捷命令逻辑已从视图组件解耦到独立 Hook，主组件不再直接维护运行态同步细节。
- 浮层拖拽和外部派发链路单独封装，避免在主组件中混杂异步事件与 UI 代码。
- 构建验证通过（`tsc && vite build`），现有终端分屏/标签页/侧栏链路保持可用。
