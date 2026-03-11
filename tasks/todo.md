# 当前任务：补齐项目切换时终端控制字符残片的前端根因修复

- [x] 复核现有后端 replay cache 修复与切换项目恢复链路
- [x] 先补失败测试，锁定连接期缓冲裁剪切进 CSI/OSC 序列的场景
- [x] 实现前端连接期缓冲的 escape-aware 裁剪，并补齐 Rust 侧 CSI 覆盖
- [x] 跑针对性验证并在文末追加复盘

## Working Notes
- 现有未提交改动已经在 `src-tauri/src/terminal.rs` 修掉了 Rust replay cache 的 ANSI 边界问题，这一轮不要覆盖它，而是补齐前端 `bufferedOutput` 同类漏点。
- `TerminalPane` 连接阶段在 `hydrated=false` 时会把 live output 先堆进 `bufferedOutput`，超过 512 KiB 后直接 `slice()`，这里仍可能把 `CSI ?1;2c` 或 `OSC 10/11` 从中间切开。
- 本次只修根因、只防新增，不增加“文本正则清洗”兜底，不强制丢弃历史 snapshot。

## Review
- 新增 `src/components/terminal/terminalEscapeTrim.ts`，把前端连接期缓冲的“裁头保尾”改成 escape-aware trim，和 Rust replay cache 保持同类边界策略。
- `src/components/terminal/TerminalPane.tsx` 在 `bufferedOutput` 超限时不再裸 `slice()`，避免把 `CSI ?1;2c` / `OSC 10;11;rgb...` 的前缀截掉后写进 xterm。
- 新增 `src/components/terminal/terminalEscapeTrim.test.mjs`，先用 Node 内建 test 跑出缺失 helper 的失败，再覆盖 plain text / partial OSC / partial CSI 三个场景。
- Rust 侧补了一条 `trim_terminal_output_cache_skips_partial_csi_sequence`，确认 replay cache 对 `CSI` 残片也不会回放成裸文本。
- 验证通过：`node --test src/components/terminal/terminalEscapeTrim.test.mjs`、`cargo test --manifest-path src-tauri/Cargo.toml`、`pnpm build`。

# 当前任务：修复 xterm.js 偶发显示裸露 `10;rgb...11;rgb...` 控制串

- [x] 读取仓库约束、相关技能与现有终端链路
- [x] 排查前后端 terminal-output / replay / snapshot 恢复路径
- [x] 先补失败测试，锁定“缓存截断切进 OSC 序列”场景
- [x] 实现最小修复，避免重放缓存从控制序列中间开始
- [x] 跑针对性验证并记录复盘

## Working Notes
- 用户给出的 `10;rgb:...11;rgb:...` 很像 OSC 10 / OSC 11 颜色查询响应体被当成普通文本渲染，重点怀疑“重放缓存从转义序列中间开始”。
- `TerminalPane` 恢复顺序是 `cachedState/savedState + replayData + bufferedOutput`，真正写入 xterm 前没有做 ANSI 边界修复。
- Rust 侧 `output_cache_by_pty` 会按 4 MiB 上限从头裁剪，但当前只保证 UTF-8 边界，不保证 ANSI/OSC 边界；如果裁进 `ESC ] 10/11 ... BEL/ST` 中间，后续恢复就会把尾巴当普通字符显示。
- 连接期 `bufferedOutput` 也有 512 KiB 的头部裁剪，但时间窗口很短，优先先修更大概率触发的 Rust replay cache。

## Review
- 根因确认：不是 xterm live stream 自己把 OSC 10/11 打印出来，而是 Rust replay cache 头部裁剪只看 UTF-8，不看 ANSI/OSC 边界，导致恢复时从控制序列中间开始回放。
- 修复方式：在 `trim_terminal_output_cache` 增加 escape-aware 起点调整；若裁剪点落在 CSI/OSC/DCS/APC/PM/SOS 等控制序列内部，就把起点推进到该序列结束之后。
- 新增 4 条 Rust 单测，覆盖普通文本、BEL 终止的 OSC、ST 终止的 OSC、以及裁剪点落到第二段 OSC 内部的场景。
- 验证通过：`cargo test --manifest-path src-tauri/Cargo.toml`、`pnpm build`。

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
