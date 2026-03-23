# Lessons
- 当一个 optional 状态同时承担“弹窗是否展示”和“弹窗完成后要执行的动作”两种职责时，UI 框架很容易在 dismiss 时先把它清空，导致回调阶段业务语义丢失。弹窗展示态和业务动作态必须拆分成两个独立状态源。
- 对“用户感知为无反应”的跨层交互链路，修行为之前要先补足可观测性：至少记录入口回调、权限获取、核心校验、持久化结果和 UI 收尾动作。否则即使修了一半，下一轮反馈仍很难判断究竟卡在哪一层。
- 文件选择器返回的目录 URL 如果带有 security-scoped access，就不能只在“提取 path 字符串”时短暂访问；真正的目录校验、扫描和导入逻辑必须在访问权限仍然有效的窗口内完成，否则很容易出现“用户刚选完目录，后续读取却静默失败”的假无响应。
- 导入链路不要把“写入来源配置”和“真正生成可展示项目”拆成两个互不约束的步骤；如果某个路径最终不会变成项目（例如 Git worktree 根目录），就不应先静默写进 `directories` / `directProjectPaths`，而应在入口处明确拒绝并反馈原因。
- 任何“可添加的来源配置”（如扫描目录、直接项目、标签源）在落地时都要同步检查**对称的移除链路**：不仅要有 UI 入口和 ViewModel API，还要明确“移除最后一个来源后，派生快照 / 缓存 / 持久化文件如何被清空”，否则很容易出现“配置已删但旧列表还残留”的半失真状态。
- 多个 worktree 并行开发时，`tasks/todo.md`、`tasks/lessons.md` 这类长生命周期共享日志文件很容易成为合并热点；更稳妥的做法是按日期或任务拆分，减少同文件冲突面。
- 发布 tag 前先核对仓库既有版本标签命名（如 `v3.0.0` vs `3.0.0`）与远端现状，避免在错误命名上新增 tag 后再返工。
- 发布矩阵 job 不要同时承担 release 元数据创建/最终化职责；应先单独准备 release，再让各架构 job 仅上传资产，避免 stale draft release 把同 tag 发布流程炸掉。

## 历史记录（notify 分支）

## 2026-03-22 Agent signal store 队列重入崩溃

- `DispatchSource` / `DispatchSourceTimer` 如果本身就跑在某个串行 queue 上，事件回调里不能再直接调用内部使用 `queue.sync` 的公共方法，否则会触发 `dispatch_sync called on queue already owned by current thread`。
- 这类 store 应显式区分：
  1. 面向外部线程的同步入口；
  2. 面向内部 queue 回调的“已持锁 / 已在 queue 上”执行路径。
- 若一个模块既会被 UI / 外部线程调用，也会被自身 queue 的 event handler / timer 回调调用，优先给 queue 设置 `DispatchSpecificKey`，并通过 “on queue 则直执行，否则 sync” 的统一 helper 收口，避免同类崩溃再次出现。

## 2026-03-22 开发态直接运行可执行文件时禁止触发 UserNotifications

- `swift run` 启动的原生可执行文件不是 `.app` bundle；在这种开发态下直接调用 `UNUserNotificationCenter.current()` 可能触发 framework 内部断言并 abort。
- 凡是依赖系统通知 / bundle proxy 的 macOS API，都不能只看“当前在主线程”就调用，还要先校验当前进程是否真的是带 bundle identifier 的 `.app`。
- 对这类能力要提供明确降级路径：开发态 / 测试态不可用时，退回提示音、应用内提醒或 no-op，而不是硬调系统 API。

## 2026-03-22 终端启动时注入 PATH 不等于用户实际执行命令时的 PATH

- 对 zsh 这类 shell，哪怕父进程在启动时已经把 wrapper bin 目录放到了 PATH 前缀，用户 `.zshrc` / `.zprofile` 仍可能在后续 startup 中重写 PATH，导致实际执行 `codex` / `claude` 时绕过 wrapper。
- 调试 PATH 问题时，要同时看三层：
  1. 父进程 / login 进程的环境；
  2. 交互 shell 进程的最终环境；
  3. 实际被执行子进程（如 `node .../bin/codex`）的环境。
- 若命令包装依赖 PATH 前缀，最佳做法不是只在进程启动时注入 PATH，而是在 shell integration 的 precmd / prompt 阶段再做一次幂等修复，这样即使用户 rc 覆盖 PATH，下一次输入命令前也能自动恢复。
- shell helper 的“幂等修复”不能只写成“PATH 中没有 wrapper 才 prepend”；如果 wrapper 路径已经存在但被用户配置挤到了后面，helper 仍要先去重再强制前移到首位，否则 `type -a codex` 还是会优先命中全局 Node / npm 安装版本。

## 2026-03-22 terminalSessionId 可能包含 `/`，不能直接拿来当 signal 文件名

- DevHaven 的 workspace / terminal session 标识现在可能是类似 `workspace:uuid/session:1` 的层级语义字符串，其中 `/` 对文件系统来说是路径分隔符，不是普通文件名字符。
- 任何 signal / 缓存 / 临时文件如果以 `terminalSessionId` 为 key，都不能直接拼成 `"\(terminalSessionId).json"`；否则脚本侧会在写临时文件时直接报 `No such file or directory`，store 侧也无法按同一 key 删除陈旧文件。
- 正确做法是：对 `terminalSessionId` 做稳定、安全、无 `/` 的编码，再作为文件名；并且“写入脚本”和“读取/清理 store”必须共享同一命名规则，否则会出现“能写不能删”或“能读不能覆盖”的双边不一致问题。

## 2026-03-22 不要把 agent 的进程态直接当成任务回合态展示

- 对交互式 agent（尤其是 Codex 这类 TUI 会话），`wrapper 启动 -> running`、`进程退出 -> completed/failed` 只能稳定表达**进程生命周期**，不能自动代表“这一轮任务是否还在执行”。
- 如果 UI 想展示“正在运行 / 等待输入”这类用户语义状态，必须显式区分：
  1. 底层真相源（signal / process lifecycle）；
  2. 展示层修正（visible text / heuristic / official lifecycle event）。
- 正确做法不是把 heuristic 结果反写回 signal store，而是在 App 运行时内存中增加 display override；这样既保住底层状态源的稳定性，又能在 UI 层修正语义错位。

## 2026-03-22 父级项目卡片不要默认聚合子 worktree 的 Agent 状态

- 侧边栏 root project 卡片和其下方 worktree 行在视觉层级上同时存在时，root card 默认应表达 **root 自身状态**，而不是整组 worktree 的 agent 汇总；否则用户会把子 worktree 的运行误读成父项目自身在运行。
- 如果确实需要 group 级总览，应单独设计专用 indicator，而不是直接把 `worktrees.map(\\.agentState)` 聚到 root card 的 `agentState/summary/kind` 上。
- 这类层级聚合问题要分别问清三件事：谁是 root 自身状态、谁是 child 局部状态、谁才是 group 汇总状态；三者不应默认共用同一展示位。

## 2026-03-22 同一份 Agent 状态在父级卡片和 worktree 行上要有一致的文案 fallback

- 如果父级卡片在没有 summary 时会回退显示 `agent label`，而 worktree 行要求必须有 summary 才显示文字，用户会误以为“父级识别出来了、worktree 没识别出来”。
- 对 waiting / running 这类经常没有摘要的状态，worktree 行至少也应显示一份 label；图标只能辅助识别，不能替代完整语义。
- 设计这类层级 UI 时，要分别检查：
  1. 状态有没有被判出来；
  2. 判出来后图标有没有显示；
  3. 在没有 summary 时，文本 fallback 是否仍能把状态说清楚。

## 2026-03-22 文本 heuristic 要优先匹配稳定结构，不要把单个示例文案当主判据

- 对 Codex 这类 TUI，`Improve documentation in @filename`、`Write tests for @filename` 只是示例提示，不是稳定协议；如果 waiting 判定只认某一条固定 placeholder，后续 prompt 提示一变就会整段漏判。
- 更稳的顺序应该是：
  1. 先识别 running marker（如 `Working (`、`esc to interrupt`）；
  2. 再识别 idle/input screen 的结构特征（如 `OpenAI Codex` + `model:` + `directory:`）；
  3. 最后才把具体 placeholder 文案作为补充匹配。

## 2026-03-22 对 Codex 这类交互式 TUI，要优先接官方 turn-complete 事件，再用活动度补齐缺失生命周期

- 只靠“当前屏幕长什么样”去猜 `running / waiting`，在长输出、滚动、光标位置变化时天然不稳；如果官方已经提供 `notify` 这类 turn-complete 事件，就应先把它接成 waiting 主判据。
- 但 Codex 当前仍缺少稳定的“新一轮开始”事件，因此不能把 notify 当成全部真相；更稳的做法是：
  1. wrapper 生命周期继续表达进程态；
  2. official notify 表达回合完成；
  3. App 侧只在 `running <-> waiting` 两态之间用最近活动度 / 可见文本做最小补偿。
- 这种“三层分工”比“继续加更多字符串 if/else”更稳，也更容易在官方协议变完整后平滑删除 fallback。

## 2026-03-22 排查焦点落点时，先确认具体控件身份，不要把模糊方位描述直接映射到某个视图

- 对“右边那个按钮”“这个图标”这类只包含相对方位的描述，如果当前界面存在多个候选控件，不能直接把它当成唯一定位依据。
- 更稳的顺序应是：
  1. 先结合当前界面结构列出 2~3 个候选控件；
  2. 再通过用户补充描述、截图或代码结构确认真正目标；
  3. 最后才对具体控件的焦点链路下结论。
- 这类问题真正要找的往往不是“某个按钮为什么被主动聚焦”，而是“当前界面有没有显式初始焦点策略”；先抓语义，再落到具体控件，能减少误判。

## 2026-03-22 C callback userdata 不要直接指向短命 bridge 再跨队列传递

- 如果某个 C 库 callback 会先在后台线程触发，再异步 hop 到主线程处理，就不能把 `Unmanaged.passUnretained(short-lived object).toOpaque()` 当成长期安全的 userdata 真相源。
- 裸指针在 callback 触发当下也许还是有效的，但只要中间经过 `DispatchQueue.main.async`、Task 或其它延迟执行，原对象就可能在真正处理前被释放；这类 bug 往往只在关闭 pane、删除 worktree、退出会话等 teardown 场景下以 `EXC_BAD_ACCESS` 暴露出来。
- 更稳的做法是：
  1. 让 userdata 指向稳定的 callback context / handle；
  2. 跨线程时只捕获 context；
  3. 真正执行时再向 context 解析当前 active 对象；
  4. teardown 开始时先 invalidation，让晚到回调统一 no-op。
