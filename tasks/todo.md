# 本次任务清单

- [x] 建立 terminal_runtime 新真相源（session/layout/quick-command）
- [x] 建立 typed event 与按 scope 订阅协议
- [x] 切换持久化到 LayoutSnapshot 并实现旧 workspace 导入
- [x] 切换前端到 runtime client / selectors / TerminalWorkspaceShell
- [x] 统一 pane 系统（terminal/run/tool/overlay）
- [x] 删除旧 workspace 保存/广播/轮询路径并完成集成
- [x] 跑构建与关键测试，确认当前阶段可继续集成

## Review
- 当前阶段已完成：按一次切换策略把终端工作区迁移到 Rust mux-lite runtime + projection UI，当前主路径已切到 runtime snapshot + projection shell。
- 已完成 Rust runtime core 收口：`src-tauri/src/terminal_runtime/*` 现保留 session registry、quick-command registry、JSON layout snapshot registry、scoped 事件与全局 `shared_runtime()`，早期未接线的 typed layout registry 骨架已删除。
- `src-tauri/src/terminal.rs` 已接入 runtime：创建/复用会话时注册 session、绑定 client/pty、输出时递增 seq、退出时标记 exited，并改为仅发 scoped pane 事件。
- 已完成前端协议收口：`src/services/terminal.ts`、`src/services/quickCommands.ts`、`src/terminal-runtime-client/runtimeClient.ts` 不再回退到 legacy terminal/quick-command/workspace 通道。
- 已完成 Rust/Web 协议删旧一轮：`load/save/list_terminal_workspace*` 与 `quick_command_snapshot/quick-command-event` 已从 command/web 路由退役，WS 只向显式订阅事件推送。
- 已完成前端 shell 收口第一步：`TerminalWorkspaceView` 顶层 state 持有 `TerminalLayoutSnapshot`，渲染 shell 已拆到 `TerminalWorkspaceShell`，主视图 header/tabs/active pane/run configuration 选择态统一改为消费 shell model / selectors。
- 已修正该切换里的两处明显回归风险：项目切换时通过 `snapshot.projectPath/projectId` 守卫避免把旧 snapshot 解释成新项目，保存布局时加入本地 dirty revision 防止保存期间的新编辑被误清脏标记。
- 已继续把一部分 UI 状态改为 snapshot 原生更新：右侧文件预览改为落在 `layoutSnapshot.panes[filePreview]`，right sidebar / run panel / activeTab / runConfiguration 的一部分更新已不再走 legacy bridge。
- 已补充 snapshot 原生 helper 与测试：`src/models/terminal.ts` 新增 append/activate/split/remove/update-ratios 等 helper，`src/models/terminal.snapshot.test.mjs` 覆盖 6 个核心用例；主工作区里 New Tab / Split / Activate / Close Tab / Close Session 已开始复用这些 helper。
- 已把 run panel 进一步收口到 snapshot 原生 helper：`src/models/terminal.ts` 新增 run panel 的 upsert/remove/sync/activate/resize/exit helpers，`TerminalWorkspaceView` 与 `useQuickCommandRuntime` 已改为复用这些 helper，减少 UI 层手写对象展开。
- 已补充 run panel 回归测试：`src/models/terminal.snapshot.test.mjs` 现覆盖 10 个核心用例，包含 run pane 创建、run tab 清理、失效会话裁剪与退出码回写。
- 已修正 run tab 关闭语义回归：关闭运行标签页时现在会同步终止底层 terminal session，再做 quick command finalize / runtime cleanup / snapshot 清理，避免出现 UI 关闭但后台 PTY 残留的孤儿会话。
- 已移除默认布局初始化里的 legacy 桥接：`createDefaultLayoutSnapshot` 现在直接在 `src/utils/terminalLayout.ts` 产出 `TerminalLayoutSnapshot`，`TerminalWorkspaceView` 不再通过 `createDefaultWorkspace -> convertLegacyWorkspaceToLayoutSnapshot` 初始化默认布局。
- 已收窄前端 legacy 兼容边界：`src/services/terminalWorkspace.ts` 删除 legacy 布局转换导出，未使用的 `src/terminal-runtime-client/projections.ts` 已移除，窗口/Tab/Pane projection 统一回收到 `src/models/terminal.ts` 与 `src/terminal-runtime-client/selectors.ts`，避免新代码继续误接 `TerminalWorkspace` 兼容口。
- 已补充默认快照入口测试：`src/models/terminal.snapshot.test.mjs` 现覆盖 11 个核心用例，新增默认 snapshot 直接构造验证。
- 已继续收口右侧工具 pane：`src/models/terminal.ts` 新增 right sidebar / file preview 的 snapshot helper（sidebar 联动、showHidden、preview pane upsert/select/remove），`TerminalWorkspaceView` 已改为复用这些 helper，减少 view 层手写 patch。
- 已补充右侧栏回归测试：`src/models/terminal.snapshot.test.mjs` 现覆盖 16 个核心用例，新增 right sidebar 联动、preview pane 生命周期、showHidden 写回与 preview selector 验证。
- 已将 Git 选中文件纳入 snapshot：`src/models/terminal.ts` 新增 `gitDiff` pane 的 upsert/select helper，`TerminalWorkspaceView` / `TerminalRightSidebar` / `TerminalGitPanel` / `TerminalGitFileViewPanel` 不再依赖侧边栏内部 `useState` 保存 Git 选择态。
- 已补充 Git pane 回归测试：`src/models/terminal.snapshot.test.mjs` 现覆盖 18 个核心用例，新增 git diff pane 的 snapshot 存储与 selector 验证。
- 已开始抽离 shell/projection 视图模型：新增 `src/components/terminal/terminalWorkspaceShellModel.ts`，把 `TerminalWorkspaceView` 中的 active tab projection、run panel、sidebar、preview、git diff 选择态派生统一收口到纯函数，减少视图组件内的派生状态散落。
- 已补充 shell model 测试：`src/components/terminal/terminalWorkspaceShellModel.test.mjs` 覆盖 active tab / run panel fallback / sidebar fallback / preview / git diff 选择态推导。
- 已完成前端 shell 收口：新增 `src/components/terminal/TerminalWorkspaceShell.tsx`，`TerminalWorkspaceView` 现在把 headerTabs / activeTabId / active pane projection / run configuration 选择态统一改为消费 shell model，不再在渲染层直接散读 `activeSnapshot`。
- 已推进 pane host 统一：`src/components/terminal/PaneHost.tsx` 现可直接承载 `terminal/run/filePreview/gitDiff/overlay`，`TerminalRunPanel` 与 `TerminalRightSidebar` 已改为复用同一 host 分发逻辑，为后续 tree/overlay 真正统一铺路。
- 已把主 tree 渲染接到统一 pane 分发：`TerminalWorkspaceShell.tsx` 的 `SplitLayout.renderPane` 现按 pane kind 统一走 `PaneHost`，tree / run panel / right sidebar 终于共用同一套 pane 装配入口。
- 已把 quick command runtime snapshot 读路径切到 Rust runtime registry：`quick_command_runtime_snapshot` 现直接读取 `shared_runtime().list_quick_commands(...)`，不再从 `QuickCommandManager` 独立快照回传前端。
- 已把 terminal layout 主路径切到 Rust runtime：`load/save/delete/list_terminal_layout_snapshot*` 现先确保 runtime 从 `terminal_workspaces.json` 导入，再以 runtime snapshot registry 作为命令读写真相源，storage 退回为持久化后端。
- 已补充 runtime layout snapshot 回归测试：`cargo test runtime_layout_snapshot_registry_round_trips_json_snapshots --manifest-path src-tauri/Cargo.toml` 覆盖 runtime 导入 / 读取 / 汇总 / 删除 JSON snapshot 行为。
- 已删除未接线的 typed layout runtime 骨架：`src-tauri/src/terminal_runtime/{layout_registry,pane_registry,tab_registry,window_registry}.rs` 与相关类型/方法已移除，`terminal_runtime` 现只保留主路径真正使用的 session / quick-command / JSON layout snapshot 语义。
- 已清理最后一批小尾巴：删除 `TerminalWorkspaceHeader` 未用 prop、压平 `PaneHost` 的 gitDiff 分支、合并 `AGENTS.md` 重复条目、修正 Review 状态文案。
- 已删除零引用的 legacy hook：`src/hooks/useQuickCommandPanel.ts` 已移除，并同步更新 `AGENTS.md`，避免旧 `TerminalWorkspace` 语义继续在前端扩散。
- 已清理前端 legacy terminal utils：`src/utils/terminalLayout.ts` 中零引用的 legacy workspace/split 工具已删除，当前仅保留 `createId`、`TerminalWorkspaceDefaults` 与 snapshot 默认布局构造，避免继续在前端保留无人调用的旧工作区算法。
- 已清理前端 legacy terminal model 转换：`src/models/terminal.ts` 中未再被主路径使用的 `TerminalWorkspace/SplitNode` 旧模型与双向布局转换已删除，前端工作区模型进一步收敛到 `TerminalLayoutSnapshot` / pane projection 语义。
- 已删除 Rust 侧零引用旧 workspace API：`src-tauri/src/storage.rs` 不再暴露 `load/save/list_terminal_workspace*` 与反向 legacy 转换，`src-tauri/src/models.rs` 同步移除 `TerminalWorkspaceSummary`，后端公开存储接口只剩 layout snapshot 语义。
- 已把 legacy 导入挪出热路径：`TerminalWorkspaceStoreState` 现在在首次加载磁盘缓存时就把旧记录归一化为 snapshot，并标记待刷盘；`load_layout_snapshot` 若在已加载缓存里再遇到 legacy 记录会直接报错，避免运行时按条目懒转换。
- 已补充 Rust 存储迁移测试：`cargo test storage --manifest-path src-tauri/Cargo.toml` 现覆盖 snapshot-only store 更新、legacy 读盘归一化、热路径拒绝未归一化旧记录等行为。
- 本轮最新验证：`node --test src/models/terminal.snapshot.test.mjs`、`pnpm exec tsc --noEmit`、`pnpm build`、`cargo test storage --manifest-path src-tauri/Cargo.toml`、`cargo check --manifest-path src-tauri/Cargo.toml` 通过。
- 本轮补充验证：`node --test src/components/terminal/terminalWorkspaceShellModel.test.mjs`、`pnpm exec tsc --noEmit`、`pnpm build` 通过。
- 本轮最终验证：`node --test src/components/terminal/terminalWorkspaceShellModel.test.mjs`、`pnpm exec tsc --noEmit`、`pnpm build`、`cargo test runtime_layout_snapshot_registry_round_trips_json_snapshots --manifest-path src-tauri/Cargo.toml`、`cargo check --manifest-path src-tauri/Cargo.toml` 通过，且 `cargo check` 已无 warning。
- 当前状态：本轮可直接收尾的小尾巴已清完；当前工作区已没有新的编译 warning / 未用 prop / 旧读路径残留，后续若继续就是新的功能或新的架构任务，而不是“收尾”。

## 性能收尾任务

- [x] 卡片模式补齐增量渲染，避免卡片视图继续全量挂载全部项目卡片
- [x] 收敛 Git Daily / 热力图 / Codex 监控的重复全量更新路径
- [x] 跑验证并补充本轮 Review

## Review（性能收尾）

- 已补齐卡片模式的批次渲染：`MainContent` 现在和列表模式一样按批次加载卡片，并在滚动接近底部或首屏未撑满时继续续载，避免卡片视图一次性挂满全部项目。
- 已把 Git Daily 自动补算改为小批次推进：`useAppActions` 现在按批次刷新缺失项目，并在签名变化时中断旧任务，降低大量项目首屏加载时的后台突刺。
- 已把热力图缓存刷新从“每次项目数组变化都重新读盘”收窄为“按签名/项目数变化同步”，优先复用内存缓存，仅在必要时重建并回写。
- 已给 Codex 监控补上快照去重：Rust 侧忽略仅 `updatedAt` 变化的重复快照推送，前端 hook 也按快照签名跳过重复 `setState`，减少无效重渲染。
- 本轮验证通过：`pnpm exec tsc --noEmit`、`pnpm build`、`cargo test record_snapshot_state_ignores_updated_at_only_changes --manifest-path src-tauri/Cargo.toml`、`cargo test storage --manifest-path src-tauri/Cargo.toml`、`cargo check --manifest-path src-tauri/Cargo.toml`。

## 终端滚动问题任务（2026-03-12）

- [x] 定位终端区域无法滚动到底的根因
- [x] 实现最小修复并补充验证
- [x] 完成验证并追加审查结论

## Review（终端滚动问题）

- 根因确认：`src/styles/global.css` 对 `.terminal-pane .xterm-viewport` 追加了 `height: 100%`，覆盖了 xterm 自己按 viewport/scroll area 计算的滚动容器尺寸，导致终端滚动位置无法稳定落到最底部。
- 修复方式：删除 `.xterm-viewport` 的固定高度覆盖，仅保留 `.terminal-pane .xterm` 的容器高度约束，让 xterm 恢复默认 viewport 布局逻辑。
- 回归保护：新增 `src/styles/global.css.test.mjs`，明确断言样式表不得再次把 `.xterm-viewport` 固定成 `height: 100%`。
- 本轮验证通过：`node --test src/styles/global.css.test.mjs`、`pnpm build`。

## Review（终端滚动问题 - 跟进）

- 根据用户后续截图继续排查后，确认仅移除 `.xterm-viewport` 固定高度还不够；真正的主因是终端 pane 的高度链路在 `PaneHost` / `SplitLayout` / `TerminalRunPanel` 一带没有完全闭合，`fitAddon.fit()` 会在部分容器上拿到偏大的可用高度。
- 本轮修复一：`src/components/terminal/PaneHost.tsx` 给 terminal/run host 显式补上 `h-full w-full`，避免 `TerminalPane` 的 `h-full` 落在 auto-height 父层上失效。
- 本轮修复二：`src/components/terminal/TerminalRunPanel.tsx` 给运行 tab 的绝对定位内容层补齐 `flex min-h-0 min-w-0`，避免 Run 面板里的终端高度链路再次退回 auto。
- 本轮修复三：`src/components/terminal/SplitLayout.tsx` 把 child 分配改成 `flex-basis: 0 + flex-grow 权重`，同时补齐 `h-full/min-h-0/min-w-0`，让 divider 不再把 100% 配额额外顶出容器。
- 本轮修复四：`src/components/terminal/TerminalPane.tsx` 在 `fitAddon.fit()` 后新增 viewport rows clamp，基于真实 `.xterm-viewport` 高度把 rows 收口，避免 Tauri/WebKit 一类运行时里出现“滚动到底但最后几行仍被裁掉”。
- 新增回归保护：`src/components/terminal/terminalViewportFit.ts` + `src/components/terminal/terminalViewportFit.test.mjs`，把 rows clamp 规则固化为可测试纯函数；并同步更新 `AGENTS.md` 记录终端尺寸收口点。
- 本轮验证通过：`node --test src/components/terminal/terminalViewportFit.test.mjs src/styles/global.css.test.mjs`、`pnpm build`。

## 终端内存优化任务（Ghostty 模式映射）

- [x] 为终端 replay 缓冲补测试，并将 Rust 侧输出缓存改成分块 ring buffer
- [x] 为 WebGL 启用策略补测试，并将前端改成“仅单一可见 terminal/run pane 启用 WebGL”
- [x] 删除前端 cachedState / SerializeAddon 重复缓存路径，并让后台 pane 只保留最小恢复锚点
- [x] 收紧终端 scrollback / 连接期缓冲预算，并让 Run 面板仅挂载活动 tab
- [x] 更新 `AGENTS.md` 并完成构建、测试、审查结论

## Review（终端内存优化）

- 已将 Rust 侧 PTY replay 从单个大字符串改为分块缓冲：`src-tauri/src/terminal.rs` 现使用 16KB x 320 chunks 的 `TerminalReplayBuffer`，总预算固定为 5MiB/PTY，并保留 escape-safe trim 语义。
- 已为 replay 缓冲补齐单测：覆盖纯文本 tail 保留、OSC 截断安全和 chunk 上限约束；验证命令为 `cargo test terminal_replay_buffer --manifest-path src-tauri/Cargo.toml`。
- 已删除前端重复历史缓存：`src/components/terminal/TerminalPane.tsx` 不再使用 `SerializeAddon`、`cacheTerminalPtyState`、`consumeTerminalPtyCachedState`，恢复只依赖后端 replay 和最小 `savedState` 锚点。
- 已把 xterm 可视层预算收口：`scrollback` 从 5000 降到 1000，连接期 `bufferedOutput` 从 512KB 降到 128KB，减少多终端场景下前端字符串常驻。
- 已新增 WebGL 资格策略：`src/components/terminal/terminalMemoryPolicy.ts` + `terminalMemoryPolicy.test.mjs` 固化“仅工作区可见且仅 1 个可见 terminal/run pane 时启用 WebGL”，避免多 Pane 同时持有高内存 renderer。
- 已将 Run 面板改为仅挂载活动 tab：`src/components/terminal/TerminalRunPanel.tsx` 不再把所有 run tab 的 `TerminalPane` 全部常驻挂载；切 tab / 收起面板时通过 `preserveSessionOnUnmount` 保活后台 PTY，后台任务继续运行，但不再保留完整前端 UI 实例。
- 已同步更新 `AGENTS.md` 记录新的终端内存预算与 WebGL gating 行为。
- 本轮验证通过：`node --test src/components/terminal/terminalMemoryPolicy.test.mjs src/components/terminal/terminalViewportFit.test.mjs src/components/terminal/terminalEscapeTrim.test.mjs`、`cargo test terminal_replay_buffer --manifest-path src-tauri/Cargo.toml`、`cargo check --manifest-path src-tauri/Cargo.toml`、`pnpm exec tsc --noEmit`、`pnpm build`。
- 用户回归反馈补充修复：`src/components/terminal/TerminalWorkspaceView.tsx` 现在在 load/sync/update 的同一时刻同步刷新 `layoutSnapshotRef`，避免“新建终端后立刻切项目”时 `saveWorkspace()` 持久化旧快照，导致返回项目后看起来像终端被关闭。
- 用户偏好调整：按最新要求把 PTY replay 预算从 512KB 提升到 5MiB，以换取切项目/切视图后更长的终端恢复缓冲。

## 终端切项目控制字符泄漏任务（2026-03-12）

- [x] 复盘控制字符内容并定位到 replay 恢复链路
- [x] 先写失败用例，锁定历史重放与实时输出分离规则
- [x] 修复 hydration 期间的终端回包下行转发
- [x] 完成测试、类型检查和构建验证

## Review（终端切项目控制字符泄漏）

- 根因确认：切项目恢复终端时，`TerminalPane` 在 replay 还原完成前就已经把 xterm `onData` 全量转发回 PTY，导致重放历史输出中的 DA/DSR/OSC 颜色查询再次触发 xterm 回包，shell 在错误时机收到这些响应后把控制字符碎片显示到界面。
- 修复方式：新增 `src/components/terminal/terminalReplayRestore.ts`，把“历史重放”和“实时补发”拆成两段；`TerminalPane` 仅在历史重放完成后才打开 hydration gate，避免 replay 触发的终端响应被写回 PTY，同时保留实时输出阶段的正常终端协商。
- 回归保护：新增 `src/components/terminal/terminalReplayRestore.test.mjs`，覆盖重放历史与实时输出去重分离的 3 个核心场景。
- 本轮验证通过：`node --test src/components/terminal/terminalReplayRestore.test.mjs src/components/terminal/terminalEscapeTrim.test.mjs`、`pnpm exec tsc --noEmit`、`pnpm build`。

## Pane 高度空白排查任务（2026-03-12）

- [x] 对照终端 pane 高度链路与 run panel 拖拽实现，确认现象成因
- [x] 输出根因说明并记录到任务清单

## Review（Pane 高度空白排查）

- 结论确认：当前“调整 pane 高度后内容区出现空白”的根因不是单一控件样式，而是 `SplitLayout -> PaneHost -> TerminalPane/xterm` 这一整条高度传递链一旦有任意一层退回 auto height，内容组件就会比 pane 实际可视区域更矮。
- 关键位置一：`src/components/terminal/SplitLayout.tsx` 依赖 `flex-basis: 0 + flex-grow` 分配空间，并要求子层持续保持 `h-full/min-h-0/min-w-0`；这里如果后续改动丢掉任一约束，拖拽后会直接表现为 pane 容器高度变了，但叶子内容没有同步撑满。
- 关键位置二：`src/components/terminal/PaneHost.tsx` 对 terminal/run 分支必须显式提供 `h-full w-full min-h-0 min-w-0`；否则 `TerminalPane` 的 `h-full` 会落到 auto-height 父容器上，最终在内容区底部留下空白。
- 关键位置三：`src/components/terminal/TerminalRunPanel.tsx` 的活动内容层使用 `absolute inset-0 flex min-h-0 min-w-0` 承接高度；如果这一层退化，run panel 拖拽时最容易出现“外层高度更新了，但终端/内容层没有吃满”的空白。
- 关键位置四：`src/components/terminal/TerminalPane.tsx` 内部依赖 `ResizeObserver + fitAddon.fit()` 把 xterm rows 收敛到新高度；即使容器高度传递正确，只要 fit 链路拿到的 viewport 高度滞后或被误算，终端仍会显示成“底部留白”。
- 辅助结论：`src/styles/global.css` 当前只保留 `.terminal-pane .xterm { height: 100%; }`，说明这次现象已不是早先 `.xterm-viewport` 被强制 `height: 100%` 的那类 CSS 覆盖问题，而是布局高度链路与 xterm 自适配之间的配合问题。

## Pane 高度空白修复任务（2026-03-12）

- [x] 为 viewport 行数不足场景补失败测试
- [x] 修正终端 viewport 行数同步逻辑并完成验证

## Review（Pane 高度空白修复）

- 根因确认：`src/components/terminal/terminalViewportFit.ts` 的行数校正逻辑只会处理“rows 偏大”的场景，不会处理“rows 偏小”的场景；因此 pane 高度被拉大后，即便 `ResizeObserver` 和 `fitAddon.fit()` 已触发，终端仍可能停留在较少的 rows，底部表现为持续空白。
- 修复方式：保持现有布局链路不动，只把 viewport 校正从“单向 clamp”改成“按真实 viewport 高度双向同步”，让 rows 在 pane 变高和变矮时都能重新对齐。
- 实现落点一：`src/components/terminal/terminalViewportFit.ts` 现在直接基于 `viewportHeight / cellHeight` 计算目标 rows，目标行数与当前不一致时就返回修正值。
- 实现落点二：`src/components/terminal/TerminalPane.tsx` 现在在 `fitAddon.fit()` 之后只要发现 `nextRows !== term.rows` 就执行 `term.resize(...)`，不再局限于“只缩不扩”。
- 回归保护：`src/components/terminal/terminalViewportFit.test.mjs` 新增“viewport 变大时应补足 rows”的失败用例，并按 TDD 先见红后转绿。
- 本轮验证通过：`node --test src/components/terminal/terminalViewportFit.test.mjs`、`pnpm exec tsc --noEmit`、`pnpm build`。
