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

---

# 性能优化冲刺（第一批）任务清单

- [x] 优化 `project_loader` Git 元数据读取：单项目 3 次 git 调用降到 2 次
- [x] 优化 `terminal` 会话锁粒度：避免在全局会话锁内执行阻塞写入/resize
- [x] 优化 `MainContent` 列表渲染：减少行内闭包与大对象透传导致的全量重渲染
- [x] 优化 `codex_monitor`：降低轮询/子进程检测开销，收敛锁内重 I/O
- [x] 增加 release 流水线基础质量门禁（至少前端构建 + Rust 测试）
- [x] 集成验证：执行构建与关键检查，记录结果

## Review
- 本轮通过多 agent 并行执行完成 5 条高收益优化，保持了现有对外接口与核心行为不变。
- Rust 侧关键收益：终端全局锁竞争降低、Codex 监控轮询与 `lsof` 子进程开销下降、项目扫描 Git 元数据读取次数减少。
- 前端关键收益：主列表去除行内闭包与 `Set` 透传，降低 `memo` 失效导致的无效重渲染；标签颜色重复计算被消除。
- 工程门禁补齐：release workflow 在发版前新增前端构建与 Rust check 失败快返。
- 验证结果：`npm run build`、`cargo check --manifest-path src-tauri/Cargo.toml`、`cargo test --manifest-path src-tauri/Cargo.toml codex_monitor -- --nocapture`、`cargo test --manifest-path src-tauri/Cargo.toml project_loader -- --nocapture` 全部通过。

---

# 性能优化冲刺（第二批）任务清单

- [x] 备注预览增量缓存：仅请求缺失路径，减少列表筛选时的重复 I/O 与闪烁
- [x] 备注预览后端并行化：批量读取 `PROJECT_NOTES.md` 时提升吞吐
- [x] `parseGitDaily` 增加有界缓存：降低热力图/筛选重复解析开销
- [x] 标签颜色查找降复杂度：从每次线性查找改为映射查找
- [x] 集成验证：执行前端构建与 Rust 检查/测试

## Review
- 备注预览链路改为“前端缺失增量请求 + 后端并行读取”，在频繁筛选/排序时显著减少重复磁盘读取与 UI 闪烁。
- `parseGitDaily` 新增有界 LRU 风格缓存（超限淘汰最旧项），减少同一字符串在热力图与筛选路径上的重复解析成本。
- 标签颜色查询从线性查找切换为 `Map` 查询，降低高标签密度场景下的渲染额外开销。
- 本轮保持对外接口与交互语义不变，属于低风险性能优化。
- 验证通过：`npm run build`、`cargo check --manifest-path src-tauri/Cargo.toml`、`cargo test --manifest-path src-tauri/Cargo.toml codex_monitor -- --nocapture`、`cargo test --manifest-path src-tauri/Cargo.toml project_loader -- --nocapture`。

---

# 性能优化冲刺（第三批）任务清单

- [x] 主列表渐进渲染：列表模式按批次加载，降低初次渲染峰值
- [x] 备注预览按可见批次请求：减少非可见项目的预读开销
- [x] `collect_git_daily` 并行化：提升多项目统计吞吐
- [x] `useCodexMonitor` 轮询自适应：降低事件通道稳定时的无效轮询
- [x] 集成验证：执行前端构建与 Rust 检查/测试

## Review
- 主列表改为“首批渲染 + 滚动追加”的渐进加载策略，降低大项目集合场景下首屏渲染峰值与卡顿风险。
- 备注预览请求范围收敛为“已渲染批次”，避免对长尾不可见项目提前发起无效 I/O。
- `collect_git_daily` 改为并行遍历路径，在多仓库统计场景下提升整体吞吐，同时保持输出结构与顺序兼容。
- `useCodexMonitor` 从固定间隔轮询切换为事件活跃度驱动的自适应轮询，降低实时事件稳定时的无效 snapshot 拉取。
- 验证通过：`npm run build`、`cargo check --manifest-path src-tauri/Cargo.toml`、`cargo test --manifest-path src-tauri/Cargo.toml codex_monitor -- --nocapture`、`cargo test --manifest-path src-tauri/Cargo.toml project_loader -- --nocapture`。

---

# 性能优化冲刺（第四批）任务清单

- [x] 终端事件订阅收敛：输出/退出事件改为全局单订阅分发，避免每个 Pane 各自监听
- [x] 备注预览读取优化：仅读取首个非空行，避免为预览全量读取大文件
- [x] 热力图/筛选链路降耗：减少重复签名计算与重复 `parseGitDaily` 开销
- [x] 集成验证：执行前端构建与 Rust 检查/测试

## Review
- 终端事件监听改为“全局一次订阅 + 本地 handler 分发”，减少 Pane 数量增长时的重复订阅与内存压力。
- 备注预览后端改为流式首行读取，避免读取超大 `PROJECT_NOTES.md` 全量内容，仅保留列表展示所需信息。
- 热力图与筛选链路移除了重复签名/解析热点，减少 `parseGitDaily` 在多 hook 间重复触发。
- 验证通过：`npm run build`、`cargo check --manifest-path src-tauri/Cargo.toml`、`cargo test --manifest-path src-tauri/Cargo.toml codex_monitor -- --nocapture`、`cargo test --manifest-path src-tauri/Cargo.toml project_loader -- --nocapture`。

---

# 性能优化冲刺（第五批）任务清单

- [x] `MainContent` 移除大字符串 key 依赖：改为 ID 顺序对比 + ref，减少 `join("\n")` 构造与重复 effect
- [x] `useProjectFilter` 筛选链路单次遍历：减少中间数组分配与重复字符串处理
- [x] `TerminalPane` 尺寸同步去重：resize 合帧 + 签名去重，降低重复 IPC
- [x] `git_daily` fast path：identity 为空时只输出日期，减少 `git log` 输出与解析开销
- [x] `codex_monitor` entry 分类合并：一次文本归一化同时判断 error/needs_attention
- [x] 集成验证：执行前端构建 + Rust check + 关键测试

## Review
- 前端层面：列表与筛选链路进一步减少了重复分配和无效计算；终端 Pane 高频 resize 的 IPC 风暴得到抑制。
- 后端层面：`git_daily` 在“不过滤身份”场景显著减少解析负担，`codex_monitor` 降低了 JSON 事件文本重复小写/匹配成本。
- 风险控制：全部改动保持对外命令与交互语义不变，属于低风险性能改造。
- 验证通过：`npm run build`、`cargo check --manifest-path src-tauri/Cargo.toml`、`cargo test --manifest-path src-tauri/Cargo.toml codex_monitor -- --nocapture`、`cargo test --manifest-path src-tauri/Cargo.toml project_loader -- --nocapture`、`cargo test --manifest-path src-tauri/Cargo.toml git_daily::tests -- --nocapture`。

---

# 性能优化冲刺（第六批）任务清单

- [x] `project_loader` 增加 HEAD 缓存：HEAD 未变化时复用 `GitInfo`，减少重复 `rev-list/log`
- [x] `terminal_create_session` 输出微批量：8ms 窗口聚合 `terminal-output`，降低事件风暴
- [x] 输出链路可靠性：reader 结束后先 flush 缓存，再发送 `terminal-exit`
- [x] 回归测试补齐：`project_loader` 新增 HEAD 变化/仓库失效场景
- [x] 集成验证：执行前端构建 + Rust check + 关键测试

## Review
- `project_loader` 现在采用“路径 + HEAD key”缓存策略；HEAD 未变化时跳过重命令，仅保留一次 `rev-parse` 判定，扫描吞吐更稳。
- `terminal` 输出链路改为微批量聚合发送，在高频输出时可显著减少事件数量，同时保持输出顺序不变。
- 退出语义保持一致：批量缓存会在退出前强制 flush，避免尾部输出丢失。
- 验证通过：`npm run build`、`cargo check --manifest-path src-tauri/Cargo.toml`、`cargo test --manifest-path src-tauri/Cargo.toml codex_monitor -- --nocapture`、`cargo test --manifest-path src-tauri/Cargo.toml project_loader -- --nocapture`、`cargo test --manifest-path src-tauri/Cargo.toml git_daily::tests -- --nocapture`。

---

# 性能优化冲刺（第七批）任务清单

- [x] `project_loader` 缓存裁剪策略：仅在超阈值时触发，优先保留本轮 `paths` 命中项
- [x] `project_loader` 缓存治理测试：覆盖“优先路径保留”和“全优先场景硬上限”两种情况
- [x] `terminal` 批量阈值优化：8ms 窗口基础上增加 32KB 强制 flush，控制高吞吐单批大小
- [x] 关键语义保持：`terminal` 输出顺序与“flush 后 exit”语义不变
- [x] 集成验证：执行前端构建 + Rust check + 关键测试

## Review
- `project_loader` 现在具备内存缓存治理能力：缓存超上限才裁剪，且优先保留本轮扫描路径，降低长期运行的缓存膨胀风险。
- `terminal` 在高吞吐场景下新增“按字节阈值强制发送”，降低单批输出过大的延迟抖动。
- 本轮未改动任何 command 对外签名与事件 payload 结构，属于低风险性能调优。
- 验证通过：`npm run build`、`cargo check --manifest-path src-tauri/Cargo.toml`、`cargo test --manifest-path src-tauri/Cargo.toml codex_monitor -- --nocapture`、`cargo test --manifest-path src-tauri/Cargo.toml project_loader -- --nocapture`、`cargo test --manifest-path src-tauri/Cargo.toml git_daily::tests -- --nocapture`。

---

# 终端右上角运行配置支持编辑/删除任务清单

- [x] 梳理终端运行配置入口与回调链路，确认最小改动面
- [x] 在终端头部新增配置操作入口，支持编辑与删除当前配置
- [x] 在终端视图补充编辑弹窗与删除确认，并对接项目脚本持久化更新
- [x] 联调验证（前端构建）并补充任务复盘

## Review
- 终端头部运行配置区域新增“配置操作”菜单，支持直接编辑/删除当前选中配置，避免必须切回详情面板处理。
- 编辑流程复用现有参数模板校验（占位符参数、必填校验、渲染校验），保证更新后可直接用于运行链路。
- 删除流程增加确认提示，并在删除后自动收口编辑弹窗与已选配置状态，避免脏 UI 状态残留。
- 本次改动仅扩展前端交互链路，不涉及 Rust command 与存储结构变更；验证通过：`npm run build`。

# 终端运行配置全量弹窗（IDEA 风格）任务清单

- [x] 扩展终端脚本回调链路，支持在终端视图内新增/编辑/删除配置
- [x] 将右上角“编辑配置...”升级为全量管理弹窗（左侧配置列表 + 右侧编辑区）
- [x] 补齐弹窗内新建/切换/删除/应用/确定/运行交互与表单校验
- [x] 前端构建验证并同步文档

## Review
- 原先仅支持“当前配置单点编辑”，现已改为接近 IDEA 的“Edit Configurations”全量弹窗，可在一个界面管理全部运行配置。
- 弹窗左侧维护配置列表（支持切换与新建态），右侧统一编辑名称、命令与模板参数；底部提供“应用/确定/运行”操作。
- 新增配置、更新配置、删除配置全部复用现有 `add/update/removeProjectScript` 持久化链路，避免引入新的存储模型。
- 验证通过：`npm run build`。

---

# 终端运行配置弹窗对齐详情面板配置方式任务清单

- [x] 对照详情面板快捷命令配置流程，确认关键差异（通用脚本插入、参数快照）
- [x] 在终端全量配置弹窗补齐“插入通用脚本（可选）”与同款参数合并逻辑
- [x] 保持新增/编辑/删除走统一项目脚本持久化链路并完成构建验证

## Review
- 终端弹窗右侧编辑区已与详情面板保持同源交互：支持选择通用脚本、自动填充命令模板与参数 schema、保留模板参数快照。
- 参数编辑、必填校验与命令渲染校验继续复用同一套 `scriptTemplate` 工具，避免两套配置语义漂移。
- 验证通过：`npm run build`。

---

# 终端 Run 面板化（对齐 IDEA）任务清单

- [x] 扩展终端工作区 UI 模型：新增 `workspace.ui.runPanel` 与 run tabs 持久化结构
- [x] 改造快捷命令运行承载：运行时会话迁移到底部 Run 面板，不再新建主终端 tab
- [x] 新增底部 `TerminalRunPanel` 组件：支持多运行 tab 切换、状态展示、收起/展开、关闭
- [x] 完善会话生命周期：运行结束保留输出并记录退出码；关闭 run tab 时回收 session
- [x] 修复主终端最后一个 tab 关闭场景：保留 run panel 会话，不重置整份 workspace
- [x] 同步更新架构索引：回写 `AGENTS.md` 的终端功能地图
- [x] 验证构建：`npm run build`

## Review
- “运行”现在进入底部 Run 面板，主终端 tab 仅承载交互终端，符合 IDEA 的运行窗口心智模型。
- Run 面板支持多任务 tab 并保留完成输出（含退出码），便于在同一项目内并行观察脚本执行结果。
- 终端持久化新增 `workspace.ui.runPanel`，并在 `normalizeWorkspaceUi` 内提供兼容与兜底，老数据可无损加载。
- 关键回归已处理：关闭最后一个主终端 tab 时不再清空 Run 面板历史会话。

---

# 2.7.2 发版任务清单

- [x] 检查工作区状态、定位 `ide` 分支与 release workflow
- [x] 将 `ide` 分支并入 `main`
- [x] 升级应用版本到 `2.7.2`（`package.json` / `package-lock.json` / `src-tauri/Cargo.toml` / `src-tauri/tauri.conf.json`）
- [x] 执行发版前验证并记录结果
- [x] 提交版本发布变更、创建 `v2.7.2` tag、push 到远端
- [x] 确认 GitHub release workflow 已触发并记录结果
- [x] 补充 `v2.7.2` release 说明（仓库文档 + GitHub Release body）

## Review
- `ide` 当前是 `main` 的线性后继，本次按 fast-forward 并入，避免额外 merge commit 噪声。
- 版本号已在前端、Tauri 配置与 Rust manifest/lock 四处同步到 `2.7.2`，保证本地构建与 CI/release 版本一致。
- 发版前验证通过：`pnpm build`、`cargo check --manifest-path src-tauri/Cargo.toml --locked`。
- release 流水线执行成功（ubuntu/macos/windows 三平台均成功），并已同步补齐 `v2.7.2` 发布说明。

---

# Web 化改造（浏览器可用）任务清单

- [x] 新增前端运行时桥接层：`src/platform/runtime.ts`、`src/platform/commandClient.ts`、`src/platform/eventClient.ts`
- [x] 前端 services 改造为统一命令/事件通道（Tauri invoke/listen 与 Web HTTP/WS 自动切换）
- [x] 新增 Rust Web 服务：`src-tauri/src/web_server.rs`（`/api/health`、`/api/cmd/:command`、`/api/ws`）
- [x] 新增 Web 事件总线：`src-tauri/src/web_event_bus.rs`，并镜像 quick-command/terminal/worktree/interaction/codex 事件
- [x] 浏览器兼容兜底：目录选择、confirm、openUrl/openPath、版本/home 读取、terminal window 行为降级
- [x] 新增 `resolve_home_dir` command，修复 Web 模式 `~` 路径展开
- [x] 增加 Web API 路径范围校验（受管目录 + 已加载项目/worktree + `~/.devhaven`）
- [x] 文档回写：更新 `AGENTS.md` 的双端架构与 Web 功能地图
- [x] 构建与回归验证：`npm run build`、`cargo check --manifest-path src-tauri/Cargo.toml`、`cargo test --manifest-path src-tauri/Cargo.toml codex_monitor -- --nocapture`、`cargo test --manifest-path src-tauri/Cargo.toml project_loader -- --nocapture`

## Review
- 本次完成“同仓双端并行”：桌面端能力不回退，浏览器端通过统一桥接层直接复用现有 command 语义。
- Web API 采用“命令分发 + 事件总线”模式，优先保证兼容性与最小迁移面，避免前端重写业务逻辑。
- 事件链路已打通（terminal/quick command/worktree/codex/interaction），浏览器可实时消费后端状态变化。
- 在“局域网访问 + 无鉴权”前提下，新增了路径范围校验作为最低限度防护，但多客户端事件隔离仍有后续优化空间。
