# DevHaven CLI 控制设计

关联：`issues/56`

## 背景

当前 DevHaven 的工作区生命周期完全由 GUI 驱动。内嵌终端虽然已经注入了项目上下文和 Agent wrapper，但没有任何“反向控制 App”的命令通道。

这直接带来两个问题：

1. Agent 无法在任务完成后自举收尾。
   典型例子就是“当前工作区任务完成后关闭工作区/关闭当前会话”，现在只能依赖用户手点 UI。
2. 终端脚本无法把 DevHaven 当成一个可编排宿主。
   例如无法从 shell 里打开项目、切换激活工作区、关闭底部 Git 面板、触发 Run Configuration，导致 App 的自动化边界被卡在终端内部。

仓库里其实已经具备了两类可复用基础：

- 状态真相源已经集中在 `NativeAppViewModel`。
  例如：
  - `enterWorkspace(_:)`
  - `activateWorkspaceProject(_:)`
  - `exitWorkspace()`
  - `closeWorkspaceProject(_:)`
  - `closeWorkspaceSession(_:)`
  - `toggleWorkspaceToolWindow(_:)`
- 终端环境里已经注入了当前上下文。
  例如：
  - `DEVHAVEN_PROJECT_PATH`
  - `DEVHAVEN_WORKSPACE_ID`
  - `DEVHAVEN_TAB_ID`
  - `DEVHAVEN_PANE_ID`
  - `DEVHAVEN_TERMINAL_SESSION_ID`
- App 已经有文件系统监听先例。
  `WorkspaceAgentSignalStore` 使用 `~/.devhaven/...` 目录监听 signal 文件，这说明用“本地目录 + JSON 请求/响应”的方式做 CLI 控制，在当前架构里是自然延伸，而不是异类。

## 目标

1. 在 DevHaven 内嵌终端里默认提供 `devhaven` 命令。
2. CLI 可以控制当前运行中的 DevHaven 实例，不依赖辅助功能权限，不做 UI 脚本点击。
3. CLI 命令必须复用现有 ViewModel / runtime state，不再新造第二套工作区状态机。
4. CLI 的长期目标不是“补几个命令”，而是尽可能覆盖 DevHaven 的全部核心可控能力。
   这里的“可控能力”指的是：
   - 可以稳定结构化表达的业务动作
   - 可以稳定查询的运行时状态
   - 不依赖屏幕坐标和视觉布局的界面语义
5. 首批命令优先覆盖“自举闭环”场景：
   - 查询当前工作区/会话
   - 打开/激活工作区
   - 离开工作区视图
   - 关闭当前会话 / 关闭工作区
   - 展示或隐藏 Project / Commit / Git tool window
6. 命令调用必须支持机器可读输出，便于 agent 或脚本判断是否成功。

## 非目标

1. 不做跨机器远程控制。
2. 不做任意代码执行型 RPC。
   CLI 只能调用白名单动作，不能成为“向 App 注入任意 shell”的后门。
3. 第一阶段不覆盖所有 UI 能力。
   例如复杂 diff 导航、编辑器光标控制、Git Log 精细筛选，不进入 MVP。
4. 不改变 restore snapshot 边界。
   CLI 只操作现有 runtime-only 状态，不把 side/bottom tool window、focused area 等额外写入恢复快照。
5. 不把 CLI 做成“屏幕自动化替代品”。
   对于纯视觉布局、窗口拖拽、像素级滚动位置这类不稳定语义，不承诺 CLI 全覆盖。

## 关键语义澄清

现有代码里已经有三种容易混淆的动作，CLI 必须保持一致：

- `exitWorkspace()`
  语义是“退出当前工作区界面，回到主内容区”，并不销毁会话。
- `closeWorkspaceSession(_:)`
  语义是“只关闭某一个 workspace session”。
- `closeWorkspaceProject(_:)`
  语义是“关闭某个项目对应的工作区入口”；如果该 path 是 root project 或 workspace root，可能会级联关闭它名下的 owned sessions。

因此 CLI 不能只暴露一个含糊的 `close`。
至少要把下面三个动作分开：

- `workspace exit`
- `workspace close --scope session`
- `workspace close --scope project`

对用户例子“任务完成后关闭工作区”，如果当前终端所在 session 是 workspace root，那么 `workspace close --current --scope project` 就会对应现有的“关闭整个工作区”。如果只是普通项目 session，则 `--scope session` 更安全。

## 方案选型

### 候选方案

#### 方案 A：AppleScript / UI Scripting

优点：

- 外部 shell 很容易发起
- 理论上不需要 App 内新增太多状态桥接

问题：

- 依赖辅助功能权限，部署和首启体验差
- 行为建立在 UI 结构和焦点上，极脆弱
- 很难返回结构化结果
- 无法自然映射到当前的 runtime state 边界

结论：不采用。

#### 方案 B：URL Scheme / Apple Event

优点：

- 触发轻量
- 可以从外部拉起 App

问题：

- 更适合 fire-and-forget，不适合请求/响应
- 参数表达能力有限，复杂命令需要再编码
- 很难做可靠的成功/失败返回
- 对“列出当前 sessions / 返回 JSON”这类命令支持很差

结论：不作为主通道。

#### 方案 C：XPC / Mach Service

优点：

- 技术上最标准，实时性最好

问题：

- 需要引入 helper/service 打包、生命周期和签名链路
- 开发态 `swift run` 与 release `.app` 的行为对齐成本高
- 对当前仓库体量来说实现复杂度过高

结论：后续可演进，但不适合作为第一阶段入口。

#### 方案 D：文件队列 IPC

优点：

- 与现有 `WorkspaceAgentSignalStore` 风格一致
- 无需额外权限和系统服务
- Dev / Release 都可工作
- 请求/响应天然可落盘，易调试、易回放
- 很容易做 `--json` 输出和失败诊断

问题：

- 实时性略逊于 XPC，但对 CLI 控制足够
- 需要处理请求排序、超时和陈旧响应清理

结论：第一阶段采用。

## 总体设计

整体分三层：

1. 分发层：把 `devhaven` 命令带进终端 PATH
2. 协议层：CLI 和 App 通过本地 JSON 队列通信
3. 执行层：App 端把命令映射到 `NativeAppViewModel`

## 全覆盖策略

CLI 要“尽可能覆盖全”，不能只在命令数量上堆砌，而要先把扩展方式设计对。建议遵守下面几条原则：

1. 先查询，后变更。
   任何可变对象先提供 `list/get`，再提供 `open/close/update/toggle`，否则脚本无法稳定定位目标。
2. 所有可寻址对象都要有稳定 ID。
   包括 workspace、project session、presented tab、pane、run session、diff tab、Git commit selection、notification item。
3. 所有高频命令同时支持两种寻址方式。
   - 显式 ID / path
   - `--current` 基于当前终端上下文推断
4. 协议层从第一天就按 namespaced command kind 设计。
   例如：
   - `workspace.close`
   - `workspace.tab.close`
   - `run.start`
   - `git.log.list`
   而不是把命令编码成一批不可扩展的 if-else 字符串。
5. GUI 新增核心功能时，应默认评估是否需要 CLI 对等能力。
   如果不提供，也要明确记录“为什么该能力不适合 CLI”。
6. 命令面优先覆盖“业务语义”，而不是“按钮点击”。
   例如应该提供 `workspace.close(scope=project)`，而不是“点左上角关闭按钮”。

换句话说，第一阶段可以只实现一部分命令，但协议、模型和命名空间必须按“最终全覆盖”来设计，避免后面推翻。

## 配套 Skill

考虑到现在 agent 生态里 `skill` 的传播效率很高，CLI 方案建议从一开始就配套一份官方 skill。

但两者的关系必须明确：

1. `CLI` 是能力真相源。
   所有稳定动作、查询、错误模型、兼容性边界都由 CLI 协议定义。
2. `skill` 是工作流包装层。
   它负责告诉 agent 什么时候调用哪些 `devhaven` 命令、如何解析 `--json` 返回、遇到什么错误该如何降级。
3. `skill` 不能绕过 CLI 直接耦合 App 私有实现。
   不能要求 agent 直接读写 `~/.devhaven/cli-control`、不能依赖未公开内部文件、不能走 UI 点击替代正式命令。

### 为什么需要官方 Skill

单有 CLI 还不够，原因是：

- 很多 agent 用户不会主动去翻 CLI 手册
- skill 更容易在任务触发时被自动命中
- skill 可以把“推荐调用顺序”和“错误恢复模式”固化下来
- skill 能把 DevHaven 从“有命令行入口”提升为“被 agent 优先理解的工作台”

### Skill 定位

建议 skill 名称采用类似：

- `devhaven-cli`
- `devhaven-workspace-control`

skill 的触发范围建议覆盖：

- 打开 / 激活 / 离开 / 关闭工作区
- 关闭当前 session / 当前项目 / 当前工作区
- 显示 / 隐藏 / 切换 Project / Commit / Git tool window
- 查询当前 DevHaven 状态、workspace 列表、capabilities
- 后续逐步扩展到 run / git / commit / diff / editor

### Skill 必须遵守的约束

1. 每次进入前优先执行 `devhaven capabilities --json` 或 `devhaven status --json`。
2. 所有自动化调用优先使用 `--current`，失败时再回退到显式 path / ID。
3. 读取结果一律优先使用 `--json`，不要依赖纯文本输出做脆弱解析。
4. 当 CLI 返回 `unsupported_command` / `target_not_found` / `app_not_running` 等错误时，skill 必须有明确降级提示。
5. skill 不得把 MCP、AppleScript、辅助功能点击作为默认路径。

### Skill 内容建议

这份官方 skill 不需要很长，重点应该是：

- 何时使用 DevHaven CLI
- 先查 capability，再执行 mutation 的工作流
- 当前上下文解析优先级
- 常见命令模板
- 常见错误与恢复策略

skill 更适合作为“agent onboarding guide”，而不是再复制一遍完整 CLI 文档。

### 与分阶段实现的关系

- Phase 1：
  - 同步交付官方 skill 初版
  - skill 只覆盖 workspace / tool-window / status / capabilities
- Phase 2：
  - 扩展 skill 到 run / git / commit
- Phase 3：
  - 扩展 skill 到 editor / diff / notification / update

因此，建议把“官方 CLI 配套 skill”视为本方案的正式 deliverable，而不是可有可无的附属品。

### 1. 分发层

新增一个正式 CLI 命令：`devhaven`

推荐实现：

- 新增 SwiftPM 可执行 target：`DevHavenCLI`
- 在 App bundle 内放置编译后的 helper binary
- 在 `AgentResources/bin/devhaven` 放一个极薄 wrapper，优先执行 bundle/helper 中的 `DevHavenCLI`

这样做的原因：

- CLI 参数解析、JSON 编解码、超时处理更适合用 Swift 写
- 可以直接复用 `DevHavenCore` 里的共享模型
- 避免 bash 脚本手搓 JSON 转义

建议分发形态：

- Dev 模式：
  - `./dev` 在启动前确保 `DevHavenCLI` 已构建
  - `GhosttyRuntimeEnvironmentBuilder` 注入 helper 路径
- Release 模式：
  - `build-native-app.sh` 把 `DevHavenCLI` 一并复制进 `.app`
  - `AgentResources/bin/devhaven` 通过环境变量或 bundle 相对路径定位 helper

建议新增环境变量：

- `DEVHAVEN_CLI_HELPER`
  指向真实 CLI binary 路径
- `DEVHAVEN_CLI_CONTROL_DIR`
  指向 `~/.devhaven/cli-control`

### 2. 协议层

采用本地目录请求/响应模型：

```text
~/.devhaven/cli-control/
  v1/
    server.json
    requests/
    responses/
    archive/        # 可选，调试期开启
```

#### `server.json`

由 App 启动后写入，包含：

- 协议版本
- app pid
- 启动时间
- app 版本
- 是否已完成 initial load
- 支持的命令集合

CLI 调用时先读 `server.json`：

- 若文件不存在，视为 App 不在线
- 若文件存在但 pid 已失活，视为陈旧 server state
- 若 `--launch-if-needed` 打开，则自动 `open -a DevHaven` 后等待 server 就绪

#### request 文件

CLI 通过“先写临时文件，再原子 rename”为 `.json` 的方式提交请求，防止 App 读到半写入内容。

建议 schema：

```json
{
  "schemaVersion": 1,
  "requestId": "4E6B7E2B-8A8D-4E8A-8C19-9E4D8D4C4F5B",
  "createdAt": "2026-04-10T03:15:45Z",
  "source": {
    "pid": 12345,
    "cwd": "/Users/zhaotianzeng/project",
    "argv": ["devhaven", "workspace", "close", "--current", "--scope", "project"]
  },
  "target": {
    "projectPath": "/Users/zhaotianzeng/project",
    "workspaceId": "workspace-abc",
    "paneId": "pane-1",
    "terminalSessionId": "terminal-1"
  },
  "command": {
    "kind": "workspace.close",
    "arguments": {
      "scope": "project",
      "preferCurrent": true
    }
  }
}
```

#### response 文件

App 处理完成后写入 `responses/<requestId>.json`：

```json
{
  "schemaVersion": 1,
  "requestId": "4E6B7E2B-8A8D-4E8A-8C19-9E4D8D4C4F5B",
  "finishedAt": "2026-04-10T03:15:45Z",
  "status": "succeeded",
  "message": "已关闭工作区「支付链路」",
  "result": {
    "activeWorkspaceProjectPath": null
  }
}
```

状态枚举建议：

- `accepted`
- `succeeded`
- `rejected`
- `failed`
- `timedOut`

CLI 默认等待最终状态，支持：

- `--timeout <seconds>`
- `--json`
- `--no-wait`

#### 排序与幂等

App 端必须串行消费请求，按文件名中的时间前缀排序，例如：

```text
20260410T111545.123Z-<uuid>.json
```

同一个 `requestId` 如果已经处理过，App 直接返回已有 response，不重复执行。

#### capability 发现

如果 CLI 要长期覆盖全量能力，必须有自描述能力，否则不同版本之间很难协商。

建议补两个基础接口：

- `devhaven capabilities`
- `devhaven schema`

示例返回：

```json
{
  "protocolVersion": 1,
  "appVersion": "3.1.9",
  "commands": [
    "status",
    "workspace.list",
    "workspace.enter",
    "workspace.activate",
    "workspace.exit",
    "workspace.close",
    "toolWindow.show",
    "toolWindow.hide",
    "toolWindow.toggle"
  ],
  "namespaces": [
    "app",
    "workspace",
    "toolWindow",
    "run",
    "git",
    "commit",
    "diff",
    "notification",
    "settings",
    "update"
  ]
}
```

这一步很重要，因为“尽可能覆盖全”不是一次性完成，而是持续扩展。没有 capability discovery，agent 很难写出可兼容脚本。

### 3. 执行层

App 侧新增一个命令协调器，在完成 `viewModel.load()` 后启动：

- 监听 `requests/`
- 解析 request
- 在主线程调用 `NativeAppViewModel` 对应方法
- 写入 response

建议新增以下对象：

- `WorkspaceCLICommandStore`
  负责 request/response 文件读写、目录创建、陈旧文件清理
- `WorkspaceCLICommandCoordinator`
  负责目录监听、请求排队、生命周期
- `WorkspaceCLICommandExecutor`
  负责把 command 映射到 `NativeAppViewModel`

其中 `WorkspaceCLICommandExecutor` 是最关键的一层，它必须明确只走现有状态真相源：

- `workspace.enter` -> `enterWorkspace(_:)`
- `workspace.activate` -> `activateWorkspaceProject(_:)`
- `workspace.exit` -> `exitWorkspace()`
- `workspace.close(scope: .session)` -> `closeWorkspaceSession(_:)`
- `workspace.close(scope: .project)` -> `closeWorkspaceProject(_:)`
- `toolWindow.toggle(kind)` -> `toggleWorkspaceToolWindow(_:)`
- `toolWindow.show(kind)` -> `showWorkspaceSideToolWindow(_:)` / `showWorkspaceBottomToolWindow(_:)`
- `toolWindow.hide(kind)` -> `hideWorkspaceSideToolWindow()` / `hideWorkspaceBottomToolWindow()`

不要把这些逻辑写进 CLI 本身。CLI 只负责发命令，真正的业务决策必须留在 App 内。

## 命令面设计

### 覆盖定义

这里建议把 CLI 目标范围定义为：

- 覆盖所有“核心用户任务”
- 覆盖所有“核心运行态对象”的查询
- 覆盖所有“稳定可表达”的业务动作

建议不以 CLI 覆盖的对象包括：

- 任意窗口拖拽到某个像素位置
- 依赖当前滚动偏移的纯视觉行为
- 尚无稳定模型的瞬时 hover / highlight 动画态

也就是说，CLI 应覆盖“语义层”，而不是“像素层”。

### 命令原则

1. 默认优先支持“当前上下文”。
2. 所有命令都支持 `--json`。
3. 高风险动作必须要求显式 scope。
4. 命令名尽量与现有模型语义一致，不制造新的模糊词。
5. 所有 mutation 命令最好都有对应的 query/list 命令。
6. 所有 list 结果都返回可再次传回 mutation 命令的稳定 ID。

### 命令版图

如果按“尽可能覆盖全”来设计，建议最终命令面至少包含这些 namespace：

- `app`
  - `status`
  - `focus`
  - `show`
  - `hide`
  - `quit`
- `project`
  - `list`
  - `open`
  - `remove`
  - `reveal`
  - `rescan`
- `workspace`
  - `list`
  - `enter`
  - `activate`
  - `exit`
  - `close`
  - `summary`
- `workspace tab`
  - `list`
  - `new`
  - `close`
  - `close-others`
  - `close-right`
  - `select`
  - `move`
- `workspace pane`
  - `list`
  - `split`
  - `close`
  - `focus`
  - `zoom`
- `tool-window`
  - `list`
  - `show`
  - `hide`
  - `toggle`
- `editor`
  - `list`
  - `open`
  - `close`
  - `save`
  - `reveal`
- `browser`
  - `list`
  - `open`
  - `close`
  - `reload`
- `diff`
  - `list`
  - `open`
  - `close`
  - `refresh`
  - `navigate`
  - `mode`
- `run`
  - `list`
  - `start`
  - `stop`
  - `logs`
  - `tail`
- `git`
  - `status`
  - `log`
  - `branches`
  - `checkout`
  - `fetch`
  - `pull`
  - `push`
- `commit`
  - `status`
  - `include`
  - `exclude`
  - `message get`
  - `message set`
  - `create`
- `notification`
  - `list`
  - `read`
  - `clear`
- `settings`
  - `get`
  - `set`
- `update`
  - `status`
  - `check`
  - `open-download-page`

不是这些都要在 Phase 1 完成，但协议、ID 体系、JSON schema、错误模型都要按这个级别考虑。

### 第一阶段命令集

#### `devhaven status`

返回 App 是否在线、当前 active workspace、open session 数、支持协议版本。

用途：

- agent 启动前探测
- shell 脚本快速判断是否可控

#### `devhaven workspace list`

返回当前已打开工作区列表，建议字段：

- `projectPath`
- `rootProjectPath`
- `kind`
  - `workspaceRoot`
  - `quickTerminal`
  - `project`
  - `worktree`
- `isActive`
- `workspaceId`
- `workspaceName`

#### `devhaven workspace enter --path <path>`

打开或恢复指定项目工作区。

第一阶段限定：

- path 必须是已知项目 path，或是可按现有规则进入的 directory workspace

#### `devhaven workspace activate --path <path>`

只激活已打开 session，不创建新 session。

#### `devhaven workspace exit`

对应 `exitWorkspace()`。
适合“临时退回主界面，但保留终端会话”。

#### `devhaven workspace close --current --scope session`

关闭当前 terminal 所在 session。

当前 session 解析顺序：

1. `DEVHAVEN_TERMINAL_SESSION_ID`
2. `DEVHAVEN_PROJECT_PATH`
3. App 当前 active workspace

#### `devhaven workspace close --current --scope project`

关闭当前项目根入口。

如果当前 session 是：

- workspace root：关闭整个工作区
- quick terminal：关闭快速终端
- 普通 root project：按现有 `closeWorkspaceProject(_:)` 级联规则关闭
- worktree：关闭该 worktree 对应 project session

#### `devhaven tool-window show --kind project|commit|git`

#### `devhaven tool-window hide --kind project|commit|git`

#### `devhaven tool-window toggle --kind project|commit|git`

因为现有 `WorkspaceToolWindowKind` 已经区分了 `.side` 与 `.bottom`，CLI 不需要重复暴露 placement，只要传 `kind` 即可。

### 第二阶段命令集

第二阶段建议补到“工作区结构 + Run + Git/Commit 主链”：

- `devhaven workspace tab list|new|close|select`
- `devhaven workspace pane list|split|close|focus|zoom`
- `devhaven run list`
- `devhaven run start --configuration <id|name>`
- `devhaven run stop --session <id>`
- `devhaven run logs --session <id>`
- `devhaven git status`
- `devhaven git branches list`
- `devhaven git fetch|pull|push`
- `devhaven commit status`
- `devhaven commit message get|set`
- `devhaven commit include|exclude`
- `devhaven commit create`

### 第三阶段命令集

第三阶段建议把 editor/diff/notification/update 补齐：

- `devhaven editor list|open|close|save`
- `devhaven diff list|open|close|refresh|navigate|mode`
- `devhaven notification list|read|clear`
- `devhaven update status|check|open-download-page`

### 第四阶段：覆盖缺口清理

当主链能力都暴露后，补“CLI 缺口清单”，目标是：

- 对每个核心 UI 区块建立一张“GUI 功能 -> CLI 是否覆盖”的矩阵
- 对尚未覆盖项，明确归类为：
  - `planned`
  - `intentionally_not_exposed`
  - `blocked_by_missing_model`

只有这样，“尽可能覆盖全”才是可验证目标，而不是口号。

## 当前上下文解析

为了让 agent 在当前 pane 内“一句话闭环”，CLI 应优先解析现有环境变量：

- `DEVHAVEN_PROJECT_PATH`
- `DEVHAVEN_WORKSPACE_ID`
- `DEVHAVEN_TAB_ID`
- `DEVHAVEN_PANE_ID`
- `DEVHAVEN_TERMINAL_SESSION_ID`

推荐规则：

1. 如果命令带 `--current`，CLI 先从环境变量组装 `target`
2. 如果环境变量不完整，再向 App 请求 `status`
3. 如果还是无法唯一定位，则报错并要求显式 `--path`

这能直接覆盖用户最在意的场景：

```bash
devhaven workspace close --current --scope project
```

agent 不需要再手抄项目路径。

## 错误模型

CLI 建议统一退出码：

- `0` 成功
- `2` App 不在线且未允许自动拉起
- `3` 参数错误
- `4` 命令被拒绝
- `5` 执行超时
- `6` App 执行失败

标准错误输出要给出明确原因，例如：

- `未检测到运行中的 DevHaven 实例`
- `当前上下文无法唯一解析 projectPath，请显式传 --path`
- `workspace.close(scope=project) 需要 projectPath`
- `目标项目未打开，无法 activate`

`--json` 模式下，错误也要走统一结构：

```json
{
  "status": "failed",
  "code": "target_not_found",
  "message": "目标项目未打开，无法 activate"
}
```

## 安全与边界

1. request/response 目录权限固定为当前用户私有，文件模式建议 `0600`。
2. CLI 只允许执行白名单动作，不提供“任意方法名 + 任意参数”。
3. Run 相关命令只能触发现有 `Project.runConfigurations`，不能把 CLI 变成通用 shell 执行入口。
4. App 不应信任 request 里的“显示文本”，只信任结构化字段。
5. 所有 path 在 App 端再次走现有 normalize 逻辑，避免字符串比较歧义。

## 对现有代码的建议改动

### 新增

- `macos/Sources/DevHavenCore/CLI/WorkspaceCLICommandModels.swift`
- `macos/Sources/DevHavenCore/CLI/WorkspaceCLICommandStore.swift`
- `macos/Sources/DevHavenCore/CLI/WorkspaceCLICommandCoordinator.swift`
- `macos/Sources/DevHavenCore/CLI/WorkspaceCLICommandExecutor.swift`
- `macos/Sources/DevHavenCLI/main.swift`
- `macos/Sources/DevHavenApp/AgentResources/bin/devhaven`
- 官方 skill 目录（后续确定放在仓库内还是独立分发仓库）

### 修改

- `macos/Package.swift`
  - 新增 `DevHavenCLI` executable target
- `macos/Sources/DevHavenApp/DevHavenApp.swift`
  - 注入 CLI command coordinator 生命周期
- `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceHost.swift`
  - 注入 `DEVHAVEN_CLI_HELPER` / `DEVHAVEN_CLI_CONTROL_DIR`
- `dev`
  - 开发态确保 CLI target 已构建
- `macos/scripts/build-native-app.sh`
  - release 打包时复制 CLI helper

### 测试

建议至少新增：

- `WorkspaceCLICommandStoreTests`
  - request/response 原子写入
  - 陈旧 response 清理
- `WorkspaceCLICommandExecutorTests`
  - `workspace.exit`
  - `workspace.close(scope: session)`
  - `workspace.close(scope: project)`
  - `tool-window.toggle`
- `DevHavenCLITests`
  - 参数解析
  - `--current` 上下文解析
  - `--json` 输出
- skill 验证
  - 至少验证 skill 在 Phase 1 能正确驱动 `status / capabilities / workspace close / tool-window toggle`

## 分阶段落地

### Phase 1：MVP

完成：

- `devhaven status`
- `devhaven workspace list`
- `devhaven workspace enter`
- `devhaven workspace activate`
- `devhaven workspace exit`
- `devhaven workspace close --scope session|project`
- `devhaven tool-window show|hide|toggle`
- `devhaven capabilities`
- 官方 skill 初版

验收标准：

- 在 DevHaven 内嵌终端执行 `devhaven workspace close --current --scope project`，可以关闭当前工作区或当前项目入口
- CLI 在 `--json` 模式下可被 agent 稳定解析
- App 未运行时能给出清晰错误，或按开关自动拉起
- protocol / schema 已经允许后续 namespace 扩展，不需要重做 IPC
- skill 能基于正式 CLI 完成 Phase 1 主链任务，而不是依赖内部实现或 UI 自动化

### Phase 2：工作区结构 + Run/Git/Commit

完成：

- `workspace tab`
- `workspace pane`
- `run`
- `git`
- `commit`
- skill 扩展到 run / git / commit

### Phase 3：Editor/Diff/Notification/Update

完成：

- `editor`
- `diff`
- `notification`
- `update`
- skill 扩展到 editor / diff / notification / update

### Phase 4：CLI 覆盖率治理

完成：

- 输出 GUI -> CLI 覆盖矩阵
- 对每个核心模块标注未覆盖原因
- 建立“新增核心功能时同步评估 CLI parity”的规范

## 推荐交互示例

### 任务完成后关闭当前工作区

```bash
devhaven workspace close --current --scope project
```

### 只离开工作区视图，不销毁会话

```bash
devhaven workspace exit
```

### 从脚本里激活某个项目

```bash
devhaven workspace activate --path ~/WebstormProjects/DevHaven
```

### 展开底部 Git tool window

```bash
devhaven tool-window show --kind git
```

### 机器可读查询

```bash
devhaven workspace list --json
```

## 为什么这份设计适合当前仓库

这套方案有三个关键优点：

1. 它尊重现有边界。
   CLI 不直接碰 SwiftUI 视图，只驱动 `NativeAppViewModel`。
2. 它与现有工程习惯一致。
   目录监听、`~/.devhaven/*` 持久目录、AgentResources PATH 注入，这些都已经存在。
3. 它能先解决最痛的场景。
   用户不需要再等一个“全量自动化平台”，先把“任务完成后自举关闭工作区”打通，就已经让 agent 工作流闭环。

## 建议结论

`issues/56` 建议按“文件队列 IPC + Swift CLI helper + AgentResources wrapper + 官方配套 skill”推进。

但它的设计目标不应只是“做几个命令”，而应从协议层就面向全覆盖扩展。第一阶段仍然先做 workspace / tool-window 闭环，是为了最快落地；不过从 namespaced command、capability discovery、稳定 ID、query/mutation 成对设计这些基础上，必须一次设计到位。与此同时，官方 skill 作为 agent 入口层应同步交付，但必须建立在正式 CLI 之上，而不是再发明第二套隐式协议。这样后续把 Run / Git / Commit / Diff / Editor 补进来时，才不会推翻重做。
