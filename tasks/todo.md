# 当前任务：第二刀性能优化——活跃挂载 + PTY 生命周期解耦

- [x] 读取仓库约束、相关技能与现有性能敏感链路
- [x] 确认根因集中在终端工作区常驻挂载与事件 fan-out
- [x] 延续第一刀的项目切换前保存链路
- [x] 补齐切换 Tab 前的 workspace 快照回写安全性
- [x] 实现仅挂载当前激活 Tab 的 `SplitLayout` / `TerminalPane`
- [x] 修复隐藏卸载误杀运行中 PTY 的生命周期耦合问题
- [x] 补齐关闭项目时的显式 PTY 回收链路
- [x] 跑构建验证并记录结果

## Working Notes
- 先按“用户说的是 DevHaven 打开多个项目后 UI/交互变卡”这个假设排查。
- 已知仓库最近做过一次“终端工作区持久化写放大”整改，需要确认这是否只是其中一个点，还是仍有更大的渲染/事件广播瓶颈。
- 已补充落地计划：`docs/plans/2026-03-10-project-scale-performance-plan.md`，按收益优先处理终端常驻挂载、事件 fan-out，再处理主界面全量渲染与后台增量化。
- `tauri://localhost` 高内存基本可视为 WebView 渲染进程在吃内存；当前最大头不是 Rust 后端本身，而是前端常驻的 xterm/Monaco/隐藏 workspace/tab 树与其缓存状态。
- 用户补充的担心是对的：如果“隐藏即卸载”仍然沿用原先的 PTY ref 计数回收，切项目/切 tab 后 1 秒就可能把仍在运行的会话杀掉，优化收益会变成行为回归。

## Archive：整改终端工作区持久化写放大

- [x] 读取仓库约束、相关技能与现有保存链路
- [x] 明确问题根因与最小可行整改方案
- [x] 先写失败测试，锁定缓存/批量落盘行为
- [x] 实现 Rust 侧终端工作区内存缓存与延迟刷盘
- [x] 保持现有命令接口与跨窗口同步兼容
- [x] 跑针对性测试与构建验证
- [x] 追加复盘总结

## Review（归档）
- 已将终端工作区保存改为“内存更新 + debounce 异步刷盘”，避免每次 UI 微调都全量读改写 `terminal_workspaces.json`。
- 保持前端调用协议、同步事件与现有文件格式兼容；退出应用时会补一次同步 flush，降低 debounce 窗口内状态丢失风险。
- 新增两条 Rust 单测覆盖缓存状态机与摘要行为；`cargo test --manifest-path src-tauri/Cargo.toml` 与 `npm run build` 已通过。

## Review
- 卡顿根因分成两类：主界面“项目总数变多”与终端工作区“已打开项目/Tab/Pane 变多”；其中终端层的结构性成本更重。
- 终端窗口当前会把每个已打开项目的 `TerminalWorkspaceView` 常驻挂载、每个项目内部的所有 Tab 也常驻挂载，仅通过 `opacity-0` 隐藏，导致 PTY 监听、快捷命令轮询、工作区保存/同步等成本按已打开总量线性放大。
- 主界面则存在顶层 `AppLayout` 串联多个派生 hook、卡片模式全量渲染、Git Daily 自动补算与热力图签名重建等叠加成本；项目一多时任何 `projects` 级状态变更都会放大为整页重算。
- 第一刀已落地：终端主窗口只挂载当前激活项目的 `TerminalWorkspaceView`，不再把所有已打开项目的终端树长期留在 `tauri://localhost` 渲染进程里。
- 为避免切换项目时丢失 workspace 状态，新增了“切换前注册并主动保存当前激活 workspace”的链路，再执行激活项目切换。
- 第二刀已落地：主终端区只渲染活动 Tab 的 `SplitLayout` / `TerminalPane`，不再把一个项目下所有 tab 的 xterm 树、监听器和 scrollback 一起常驻。
- 为避免切 Tab 时丢失隐藏前的终端内容，新增了“切换前抓取当前活动 Tab session 快照并写回 `workspace.sessions`”的链路。
- 已补齐 PTY 生命周期：隐藏卸载改为“park + 缓存序列化状态 + 下次附着走 replay”，只有用户显式关闭 tab / pane / project 时才会真正触发 PTY terminate。
- 已补齐“关闭项目”这条回收链路：窗口层会汇总被关闭 root project / worktree 对应的全部 sessionId，并在移除 UI 前显式结束这些 PTY，避免 parked 会话残留在后端。
- `npm run build` 已通过；本仓库当前没有现成前端单测基建，这一轮先用类型检查 + 生产构建兜底。
