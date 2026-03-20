- 原生 Swift 首页如果把筛选点击直接绑到 `@MainActor` 上的同步文档读取与整份 snapshot reload，会立刻放大点击卡顿；后续同类性能问题优先先查“筛选是否重复读项目文档”“收藏/设置保存是否又触发 `load()` 全量重载”。
- 当 `@MainActor` ViewModel 需要在选中项目后读取磁盘文档时，不能继续同步 `read -> decode -> apply` 一把梭；应优先做成“命中缓存立即展示，未命中则先切选中态/打开抽屉，再后台异步加载，并用 revision/token 挡住旧请求回写”，否则快速切项目时很容易出现点击闷顿或旧项目内容串屏。
- 在 macOS SwiftUI 里，顶部纯图标 `Button` 即使没有业务 active 态，也可能因为进入了窗口初始焦点链而显示出蓝色 focus ring；如果产品要复刻 Web/Tauri 风格的“静态图标按钮”，需要显式决定它是否参与焦点（例如 `focusable(false)`），不能把系统焦点高亮误当成选中态。
- 做原生 Dashboard / heatmap 这类信息密度高的面板时，不能先按“大屏设计稿”写死 `minWidth`、固定列数和固定并排布局；sheet/弹窗实际宽度一旦比预期小，就会直接出现左侧裁切、卡片看似空白、筛选按钮缺一截。应优先做成按实际宽度切换列数/堆叠方向的响应式布局，并让热力图月份标签与网格共享同一条横向滚动坐标系。
- 在 macOS 原生壳里，只要按钮会触发 `git log` / 扫描目录 / 读写大 JSON 这类重任务，就不能继续直接从 SwiftUI 按钮同步调用 `@MainActor` ViewModel 方法；哪怕 UI 上有“更新中...”文案，也会把整个窗口卡死。稳定做法是把重聚合放到 `Task.detached` 等后台任务里，再回主线程做状态提交。
- attached sheet 在 macOS 上也是一扇真实窗口；如果用户希望它“默认更宽一点，还能手动拖大拖小”，就要显式配置该 window 的 `minSize`、`initialSize` 和 `.resizable`，不能只指望 SwiftUI 根据内容自动推导出合适的窗口尺寸。
- 对“更新统计”这类会遍历大量 Git 仓库的长任务，仅仅改成后台执行还不够；如果没有阶段/进度提示，用户仍会觉得“按钮一直在转，不知道在干嘛”。稳定做法是同时补：进度文案、合理并发度，以及单仓超时保护，避免少数异常仓库把整轮刷新无限拖住。
- 对 Swift 原生预览（`swift run` / Xcode 调试）这类启动链，不能默认相信 `WindowGroup` 会自动把应用提升为 active/frontmost；如果窗口能看到但输入框普遍拿不到焦点，优先先查“当前进程是否真的成为 key/active app”，并把激活逻辑统一收口在窗口挂载层，而不是去给每个 `TextField` 分散补焦点补丁。
- 在 AppKit 内嵌 Ghostty 时，宿主外观不要再硬编码另一套终端主题；如果用户要求“和 Ghostty 配置保持一致”，应直接把 `background/background-opacity` 等基础样式从 Ghostty config 读取出来，并在 config/color change action 到来时同步更新宿主 chrome。
- 对 Ghostty 这类原生终端，`keyDown` 不能简化成“拿 `event.characters` 直接发给底层”；否则 `interpretKeyEvents` / `insertText` 会和手工 text 发送双写，出现 `ls -> lsls` 一类重复回显。稳定做法是 translation event + `interpretKeyEvents` + `insertText` accumulator，再决定发 key 还是 text。
- `Ctrl+D` / shell exit 这类 close-surface 场景不能只把 pane 留在失败态；收到进程关闭回调后，上层宿主必须显式 `tearDown()` + `shutdown()` 并切到 exited UI，保证 workspace 仍可继续操作。
- 对 Ghostty / AppKit 终端输入链，不能只用“直接调 `keyDown` 的 ASCII smoke”来判断输入已经稳定；真实用户桌面输入常常还会经过 `NSTextInputClient` / `setMarkedText` / preedit。若这层没接，中文输入法或输入法英文态都可能把 `p -> pw -> pwd` 这类预编辑中间态错误提交成重复文本。
- 当 Ghostty / AppKit 终端的复杂度已经同时碰到 `keyDown`、`NSTextInputClient`、preedit、keybinding 和 runtime observer 时，不要继续在宿主 host 文件里补丁式修复；应尽快收敛成 dedicated `GhosttySurfaceView.swift`，让 SwiftUI host、Ghostty runtime 和 AppKit 输入协议各守边界。
- 涉及原生终端 smoke 时，不要把断言直接绑定到 `pwd` 输出 cwd、prompt 主题或其他 shell 展示细节；更稳的做法是锁住“输入只回显一次、没有 `ppwd/pwdd/pwdpwd/command not found` 这类伪影”这类稳定不变量。
# Lessons Learned

- 当终端侧新增“运行配置”能力时，必须先对齐详情面板已有的配置模型与交互（通用脚本插入、模板参数快照、校验逻辑），避免出现两套不一致的配置语义。
- 对于用户明确指出“与现有入口不一致”的反馈，应优先做同源行为收敛，而不是继续叠加新的交互变体。
- 对 Node 子进程跨平台封装（尤其是 Windows）时，避免直接 `spawn` `.cmd` 文件；优先用 `node <cli.js>` 启动 JS 入口并保留失败日志，防止 CI 上出现无上下文的 `ELIFECYCLE exit 1`。
- 修复“唤醒黑屏”这类问题时，避免在多个层级同时叠加补偿式重绘/定时恢复；全局层只做一次窄触发，局部组件再做最小自愈，否则普通前后台切换会被误判成恢复并产生闪烁。
- 涉及“创建终端/标签后立刻切换项目或视图”的交互时，不能只依赖 `useEffect` 把最新 layout state 同步进 ref；任何会在切换前触发持久化的路径，都必须在 `setState` 回调内同步刷新 ref，避免保存到旧快照导致会话看起来被关掉。
- 在 React 组件里新增任何 Hook（尤其是 `useMemo` / `useCallback`）时，必须先检查它是否落在条件返回之前；即使逻辑上只依赖已加载状态，也不能把 Hook 放到 `if (!ready) return ...` 之后，否则首屏与恢复阶段会触发 Hook 顺序错乱。
- 做内存优化时，不能把“切项目短暂后台”与“长期后台保活/关闭项目”混为一谈；凡是会影响终端历史恢复体验的回收策略，都要单独验证项目切换场景，避免刚切走就把 replay 历史降级掉。
- 当用户要“每个 pane 都可以是一个 agent”时，不能把需求偷换成“在终端头部加一个独立 Agent 按钮”；前者要求 **pane 自身具备 agent 身份/模式切换/元数据**，后者只是额外启动入口，产品模型完全不同。
- 涉及终端工作区的新能力时，必须先确认“用户想要的是全局入口、项目入口，还是 pane 级一等能力”；如果粒度判断错了，哪怕代码可运行，也属于方向性错误。
- 当用户明确要求“pane 先创建出来，再在 pane 内选择它是 shell 还是 agent”时，不能擅自改成“创建前弹菜单选类型”；两者虽然都叫“创建时决定身份”，但交互时序完全不同：前者需要 **pending pane / 未定型 pane**，后者只是创建菜单。
- 对已定型的 pane，任何常驻在右上角的状态/控制都要极度克制；如果用户已经明确“视觉很怪”，优先删除常驻控制，让 pending pane 承担类型选择职责，已定型 pane 保持接近纯终端。
- 对 pending pane 里的装饰性元素也要保持克制；如果用户点名不要标题、说明文案或加号图标，就直接删除，不要保留“我觉得有帮助”的占位装饰。
- 一旦交互模型切到“pending pane 先出现，再选择 shell/agent”，就必须同步收敛所有默认/兜底入口：首次打开项目、最后一个 session 退出、最后一个 tab 关闭都要回到 pending pane，不能只改“新建 pane”路径，否则 pane 类型与真实会话会再次错位。
- 对“只挂载当前 active workspace”的性能优化要特别谨慎：终端 PTY 虽然能靠 `preserveSessionOnUnmount` 保活，但项目级 `useQuickCommandRuntime` / pane agent 等 React 运行态仍会随着 workspace 卸载而被误判结束；只要用户需要后台继续跑任务，就应优先保持 workspace 挂载，仅把非激活项隐藏/降交互。
- 当产品方向切到 cmux 式 primitive + control plane 时，不能继续把 provider 选择、运行态和 notification 绑在前端 pane mode 里；应优先把 terminal binding / agent session / notification 真相收口到后端 registry，再让前端只做 projection。
- 当旧架构已经不再是主路径时，不要长期保留“兼容但无人使用”的 UI/Hook/adapter 壳层；最好在控制面和默认路径稳定后立刻做一次第三轮清场，把死代码删除，并用加载时归一化兼容历史快照。
- 当系统里同时存在 monitor 事件流和 control plane 事件流时，不能只做 toast/系统通知；必须明确把真实事件桥接进 control plane，否则用户会看到“状态在跑、控制面却没通知”的割裂体验。通知模型也必须尽早补上消费策略（至少 workspace 级自动已读）。
- 当用户明确反馈“通知没了/看不到是否在运行”时，不能只检查 control plane 消费链路；还要回头核对**事件生产者是否真的被产品化接线**（例如 wrapper 是否自动接管、状态是否有启动恢复、UI 是否还有可见入口），否则容易在删掉兜底监控后留下整条空链路。
- 当工程里已经有 env 注入、control endpoint、hook 脚本等必要条件时，排查时不能把问题描述成“从零开始”；应明确区分“必要条件已具备”和“闭环尚未产品化”两类状态，避免误导后续实现方向。
- 当用户明确要求“Codex 必须保持交互式透明 wrapper”时，不能擅自把主路径改写成 non-interactive `exec` 任务；launcher 命令可以保留作诊断/显式托管入口，但终端内默认体验必须仍是透明接管交互命令。
- 当目标是“像 cmux 一样简洁优雅”时，重点不是删掉控制面，而是把**交互式主路径**收口成单线：shell integration、shim、wrapper、hook、control plane 各守其位；显式 launcher/diagnose 命令应退到工具层，而不是继续占据用户心智。


## 2026-03-15 终端增强实现回归反馈

- 用户反馈“当前实现导致终端内容都不见了，历史输入也没来”时，不能只从 agent control plane / wrapper 角度解释设计差异，必须回到**终端启动链路、shell integration、历史文件与 replay 恢复**做根因排查。
- 以后只要涉及终端增强、wrapper、shell integration 改动，结论里必须显式检查：登录 shell 是否仍加载用户 rc、历史文件路径是否被切换、ZDOTDIR/HISTFILE/PROMPT_COMMAND 是否被覆盖、replay/restore 是否影响可见内容。


## 2026-03-15 primitive / legacy 双写通知教训

- 在 primitive-first 过渡期，允许 legacy `agent_session_event` 双写兼容，但**通知绝不能 primitive 与 legacy 同时各写一份**；否则会直接造成 unread 计数翻倍、toast/系统通知重复。
- 以后只要做“旧路径兼容 + 新中间层接管”，必须单独补一条回归测试，锁定“单次 hook 事件只产生一条通知记录/一次外显通知”。


## 2026-03-15 codex 路径固化教训

- 终端 wrapper 若在 session 创建时提前固化 `DEVHAVEN_REAL_CODEX_BIN`，就不能只按当时 PATH 的首个 `codex` 命中来选；否则用户同时装有旧 npm/Homebrew 版与新版 App/官方版时，DevHaven 会长期锁死到旧版本，更新 App 也不会生效。
- 以后涉及 wrapper real-binary 解析，必须同时检查：宿主 shell PATH、GUI-like PATH、显式 env 覆盖、以及“多个候选中是否应按版本/来源优先级选择”的策略。


## 2026-03-15 控制面指示灯语义教训

- 分析终端项目列表里的 Codex 提示时，不能把所有圆点都笼统称为“通知角标”；当前 UI 至少同时存在 **控制面状态点、未读 badge、Codex 运行中点** 三种语义，只有未读 badge 会随自动已读消失，状态点不会。
- 以后只要用户反馈“读过了怎么还在”，必须先把截图里的可见元素和具体 JSX 条件一一对上，再下结论，避免把“已读没清掉”误判成“状态没清掉”。


## 2026-03-16 控制面通知事件主键教训

- 只要事件消费侧需要精确处理“本次新增的是哪一条通知”，事件 payload 就必须直接携带 `notificationId` 这类主键；不能偷懒只给 `updatedAt/projectPath` 再让前端回拉整棵树按时间窗口猜测，否则异步加载一旦落后，就会把后续通知提前吞掉。
- 以后处理控制面/事件总线类 bug，遇到“前几次正常，后面逐渐不触发”的现象时，必须优先排查 **事件粒度是否过粗、消费者是否在用全量快照回推单条事件**，而不是先怀疑 UI toast 或系统通知组件本身。


## 2026-03-18 Codex 重复状态标识教训

- 当 control plane 已经能表达 running / waiting / completed / failed 全套状态时，不要再在同一块 UI 上额外叠加独立的 provider 运行态徽标；否则用户只会看到“两个点/两个 chip”，却分不清语义边界。
- 以后只要用户用截图指出“有两个标识、多余了”，必须先把可见元素映射回具体 JSX 条件和状态源；如果只是同一事实被两套 projection 重复暴露，优先删掉重复入口，而不是继续补文案解释。

## 2026-03-18 macOS 通知点击路由教训

- 只要产品要求“点击系统通知后返回应用并跳到具体工作区”，就不能继续用 `osascript display notification` 这类无回调的代发方案；它会把通知来源显示成“脚本编辑器”，点击后也只会打开 Script Editor，无法保留 DevHaven 的导航上下文。
- 以后处理桌面端通知时，必须同时检查两件事：**通知归属是不是应用本体**、**点击事件能不能拿回 `projectPath/workspaceId/paneId` 这类上下文**。只解决“能弹出来”而不解决“点了去哪”，等同于通知链路没闭环。

## 2026-03-19 macOS 原生 UI 复刻 Tauri 主界面教训

- 当用户明确反馈“原生版 UI 差距太大，需要复刻 Tauri 版本”时，不能继续沿用系统默认 `NavigationSplitView` 三栏范式做小修小补；应立即回到现有 React 入口与真实截图，按 **左侧 Sidebar + 中央 MainContent + 右侧 overlay Detail Drawer** 的信息架构重建原生主布局。
- 以后做原生迁移时，如果用户已经明确选择“尽量保留现有信息架构”，就不要擅自把界面改造成更像系统样板 app 的布局；先追平现有产品结构，再谈更原生的局部优化。
- 在 SwiftUI + Ghostty 的原生 workspace 里，标签页切换不能靠“只渲染当前选中 tab”实现；如果非选中 tab 被卸载，`GhosttySurfaceHost.onDisappear -> releaseSurface()` 会把后台终端直接销毁。稳定做法是保活所有 tab，只把非选中项做透明隐藏并禁交互。
- 在 SwiftUI + Ghostty 的原生 workspace 里，项目切换和标签页切换属于同一类生命周期问题；如果通过“只渲染当前 active project/workspace”来切换项目，`WorkspaceHostView` 的 `onDisappear` 一样会把后台 Ghostty surface 提前释放。稳定做法是保活所有已打开项目对应的 workspace host，只把非激活项隐藏并禁交互。
- 对“支持同时打开多个项目”这类需求，不能只把底层状态模型做成 `openWorkspaceSessions` 就算完成；还必须在 workspace 壳里提供**继续打开其他项目的真实入口**，否则用户仍要先退出当前 workspace 才能打开第二个项目，产品语义并没有真正闭环。
- 对 workspace 的“返回上一页”操作，不能等价实现成“关闭所有已打开会话”；返回只是暂时离开 workspace 视图，不应清空 `openWorkspaceSessions`。否则用户回到主列表再双击进入时，会误以为原本已打开的项目被系统吞掉了。
- 当前 `xctest` 宿主下，`ghostty_surface_new(...)` 可能直接失败并返回 nil；后续写 Ghostty smoke 时，必须先区分“surface 根本没创建成功”和“已创建但交互回归”，否则很容易把 GUI 宿主限制误判成输入/分屏逻辑 bug。
