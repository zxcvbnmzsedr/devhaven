# Todo

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
