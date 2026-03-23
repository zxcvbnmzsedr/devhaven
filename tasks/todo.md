# Todo

- [x] 盘点当前 staged / unstaged / untracked 变更范围
- [x] 阅读关键 diff 与新增文件，记录潜在风险
- [x] 输出按优先级排序的 review findings
- [x] 在 tasks/todo.md 追加本次 review 结论与证据

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

- [x] 核对本地/远端 v3.0.0 当前指向，确认需要强制覆盖远端 tag
- [x] 强制推送本地 v3.0.0 到 origin
- [x] 复核远端 v3.0.0 已指向当前 merge commit，并记录 Review 证据

- [x] 核对本地 main 与 origin/main 指向，确认推送前基线
- [x] 推送本地 main 到 origin/main
- [x] 复核远端 main 已指向当前 HEAD，并记录 Review 证据

- [x] 收集最新失败 GitHub Action run 的编号、触发时间、失败 job 与原始日志
- [x] 对照 workflow 配置与近期提交定位直接原因
- [x] 判断是否存在设计层诱因，并给出修复建议与验证方案

- [x] 为 release workflow 补回归测试，约束 draft release 清理不再依赖不支持的 gh json 字段
- [x] 以最小改动修复 .github/workflows/release.yml 的 draft release 清理逻辑
- [x] 运行定向验证并回填本次 GitHub Action 故障 Review

- [x] 整理 release workflow 修复改动并完成提交前校验
- [x] 提交并推送 release workflow 修复到 origin/main
- [x] 用 workflow_dispatch 触发 release(tag=v3.0.0)
- [ ] 复核新 run 结论、失败点是否消失以及 release 产物状态

- [x] 收集 arm64 Swift test 失败明细并定位是代码回归还是测试脆弱性
- [x] 以最小改动修复两条 AppKit 时序脆弱测试
- [ ] 跑本地定向测试与完整 swift test 验证后重新触发 release workflow

## 2026-03-23 升级方案对标调研（cmux / supacode / ghostty）

- [x] 梳理 DevHaven 当前升级相关现状与已知约束
- [x] 对比 cmux、supacode、ghostty 的升级实现路径与发布形态
- [x] 基于 DevHaven 当前架构给出建议、风险与落地顺序

## 2026-03-23 升级终局方案架构图与模块拆分

- [x] 明确“最完美方案”的范围边界（仅架构，不进入实现）
- [x] 输出升级终局方案的架构图、模块职责与数据流
- [x] 与用户确认该设计方向是否成立

## 2026-03-23 升级终局方案实现

- [x] 落升级终局设计文档与实现计划
- [x] 为更新设置与版本元数据补失败测试
- [x] 实现更新设置模型、菜单与设置页入口
- [x] 接入 Sparkle runtime 与开发态禁用策略
- [x] 补 Sparkle vendor / 打包脚本 / release workflow / nightly workflow
- [x] 更新 README / AGENTS / Review 并完成验证

## 2026-03-23 无苹果账号升级模式收口

- [x] 为 manual-download 更新模式补失败测试
- [x] 实现 appcast 手动检查与“打开下载页” fallback
- [x] 同步打包元数据 / README / AGENTS 并完成验证

## 2026-03-23 Sparkle 启动崩溃修复

- [x] 把 Sparkle dyld 缺库问题登记到 tasks/todo.md，并明确验证闭环
- [x] 收集打包产物内 Sparkle.framework 布局与 DevHavenApp rpath 证据，确认直接原因
- [x] 先为打包脚本补回归测试，约束必须为 Frameworks 注入运行时 rpath
- [x] 修复 build-native-app.sh 的 Sparkle 运行时查找路径
- [x] 重新打包并验证启动不再因缺少 Sparkle.framework 崩溃
- [x] 在 Review 中记录直接原因、设计层诱因、修复方案与验证证据

## 2026-03-23 stable appcast 404 排查

- [x] 把 stable appcast 404 排查任务登记到 tasks/todo.md
- [x] 核对 GitHub 上 stable-appcast / nightly 相关 release 与 appcast 资产实际状态
- [x] 对照本地 AppMetadata 与 workflow，定位 404 的直接原因与设计层诱因
- [x] 先补回归测试，再实施最小修复
- [x] 完成验证并在 Review 记录结论、证据与后续发布方式

## 2026-03-23 首次 stable-appcast 正式发布

- [x] 把首次 stable-appcast 正式发布任务登记到 tasks/todo.md
- [x] 核对当前 git 工作区、版本号、tag、远端 release 与 feed 基线
- [x] 收口发布前必要改动并完成验证
- [x] 提交并推送发布改动，创建/更新正式版本 tag
- [x] 执行首次 stable-appcast 正式发布并验证 feed / 下载链路
- [x] 在 Review 中记录发布结果、证据与后续维护方式

## Review

## Review（2026-03-23 stable appcast 404 排查）

- 直接原因：
  1. 用户本地 `3.0.0 (3000002)` 已经带有 stable feed URL：`https://github.com/zxcvbnmzsedr/devhaven/releases/download/stable-appcast/appcast.xml`；
  2. 但截至排查时，远端 GitHub 上并不存在 `stable-appcast` / `nightly` alias release，因此客户端第一次检查更新直接得到 HTTP 404。
- 设计层诱因：
  1. 客户端 update 能力已本地实现，但远端第一次 appcast alias 发布尚未真正落地，导致“客户端先上线、feed 后上线”的时序错位；
  2. 未发现明显系统设计缺陷，但发布验证此前没有覆盖“固定 feed URL 是否真实可访问”这一条线上证据。
- 当前修复方案：
  1. 先完成首次 stable release / stable-appcast alias 正式发布；
  2. 对 live `stable-appcast` alias 做热修，确保固定 URL 命中真实 `appcast.xml`；
  3. 把后续 workflow / promote 脚本中的 feed 命名与 URL 生成问题补回归测试并修复，避免再出现“workflow success 但客户端 feed 仍错误”的假成功。
- 验证证据：
  - `gh release view stable-appcast --json ...`（排查前）→ `release not found`
  - `gh release view nightly --json ...`（排查前）→ `release not found`
  - `curl -I -L https://github.com/zxcvbnmzsedr/devhaven/releases/download/stable-appcast/appcast.xml`（排查前）→ `HTTP/2 404`
  - `gh release download stable-appcast --pattern appcast.xml`（发布后）可下载成功，说明 alias 资产真实存在
  - `curl -L https://github.com/zxcvbnmzsedr/devhaven/releases/download/stable-appcast/appcast.xml | sed -n '1,160p'`（热修后）→ appcast 已返回 `3.0.1 / 20260323013003` 且 enclosure 指向 `v3.0.1/DevHaven-macos-universal.zip`

## Review（2026-03-23 首次 stable-appcast 正式发布）

- 结果：已成功发布 `v3.0.1` 正式 release，并完成首个 `stable-appcast` alias feed 发布；当前稳定通道 feed 已返回 200，内容指向 `v3.0.1` 的 universal 安装包。
- 直接原因：
  1. 需要把本地升级基础设施第一次真正发布到远端，才能让客户端的 stable feed 不再 404；
  2. 发布过程中暴露出两个真实问题：`release.yml` 仍把 stable `v*` release 创建成 prerelease，以及 `promote-appcast.sh` 误把 `gh release upload file#label` 当成“改资产文件名”的手段。
- 设计层诱因：
  1. release workflow 的 appcast 发布链路此前只验证“job 是否成功”，没有验证最终 GitHub 固定 URL、asset 文件名与 appcast 内容是否真正符合客户端约定；
  2. `generate_appcast` 的 `download-url-prefix` 需要尾部斜杠这一细节此前没有被测试覆盖，导致第一次 live 发布生成了错误的 enclosure URL。
- 当前修复方案：
  1. 生成 Sparkle signing key，并把 `SPARKLE_PUBLIC_ED_KEY` / `SPARKLE_PRIVATE_ED_KEY` 写入 repo secrets；
  2. 提交升级基础设施并发布 `v3.0.1`；
  3. 修复 `release.yml`，确保 stable release 不再被标记为 prerelease；
  4. 修复 `promote-appcast.sh`，改为先复制成目标文件名再上传，避免 alias 资产名错误；
  5. 修复 release/nightly workflow 的 appcast 参数：`download-url-prefix` 带尾部 `/`，`--link` 指向具体 release 页面；
  6. 对当前 live `stable-appcast/appcast.xml` 做人工热修，确保现有客户端立即可用。
- 长期改进建议：
  1. 后续每次 release 固定增加两条线上验证：`curl stable-appcast/appcast.xml` 与 `curl vX.Y.Z/DevHaven-macos-universal.zip`；
  2. 若未来要继续增强 manual-download 体验，可再把客户端 appcast 解析逻辑从“优先 item link”收口为“优先 enclosure/download，再回退 release notes”，减少对 feed 文案排序的耦合。
- 验证证据：
  - 2026-03-23 `swift test --package-path macos` → 242 tests，5 skipped，0 failures。
  - 2026-03-23 `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release.yml"); YAML.load_file(".github/workflows/nightly.yml"); puts "workflows ok"'` → `workflows ok`
  - 2026-03-23 `gh secret list -R zxcvbnmzsedr/devhaven` → 已包含 `SPARKLE_PUBLIC_ED_KEY` / `SPARKLE_PRIVATE_ED_KEY`
  - 2026-03-23 `git push origin main` → `8e04767` 发布提交已推送；随后 `git push origin refs/tags/v3.0.1` 成功
  - 2026-03-23 `gh run view 23417576947 --json status,conclusion,jobs,url` → `status: completed`, `conclusion: success`
  - 2026-03-23 `gh release view v3.0.1 --json assets` → 包含 `DevHaven-macos-arm64.zip`、`DevHaven-macos-x86_64.zip`、`DevHaven-macos-universal.zip`、`appcast-staged.xml`
  - 2026-03-23 `gh release view stable-appcast --json assets` → 包含 `appcast.xml`
  - 2026-03-23 `curl -I -L https://github.com/zxcvbnmzsedr/devhaven/releases/download/stable-appcast/appcast.xml` → 最终返回 `HTTP/2 200`
  - 2026-03-23 `curl -L https://github.com/zxcvbnmzsedr/devhaven/releases/download/stable-appcast/appcast.xml | sed -n '1,160p'` → 返回 `3.0.1 / 20260323013003`，且 `enclosure url` 为 `https://github.com/zxcvbnmzsedr/devhaven/releases/download/v3.0.1/DevHaven-macos-universal.zip`

## Review（2026-03-23 Sparkle 启动崩溃修复）

- 直接原因：打包脚本虽然已把 `Sparkle.framework` 复制到 `DevHaven.app/Contents/Frameworks/`，但主可执行文件 `DevHavenApp` 没有注入 `@executable_path/../Frameworks` 这个 `LC_RPATH`，dyld 启动时无法从 app bundle 内解析 `@rpath/Sparkle.framework/Versions/B/Sparkle`，因此在进程刚启动阶段直接 abort。
- 设计层诱因：未发现明显系统设计缺陷；但当前打包验证此前只覆盖“Framework 是否被复制进 bundle”，没有覆盖“主可执行文件的 runtime search path 是否指向 Contents/Frameworks”，因此把一个运行时装载问题漏到了用户启动时才暴露。
- 当前修复方案：
  1. 在 `macos/Tests/DevHavenCoreTests/NativeBuildScriptUpdateSupportTests.swift` 新增回归断言，要求打包脚本显式包含 `install_name_tool` 与 `@executable_path/../Frameworks`。
  2. 在 `macos/scripts/build-native-app.sh` 中新增 `list_rpaths` / `ensure_binary_rpath`，在组装 `.app` 时对 `Contents/MacOS/DevHavenApp` 做幂等 rpath 注入。
  3. 保持注入发生在签名之前，避免后续签名链被二次修改破坏。
- 长期改进建议：后续所有“嵌入第三方动态 Framework”的打包链路，建议固定补一条 launch-time 验证：至少检查 `otool -l` 中存在目标 `rpath`，必要时再跑一次最小启动 smoke test，避免只看 bundle 文件布局就误判为可运行。
- 验证证据：
  - `otool -l /tmp/devhaven-native-app-manual/DevHaven.app/Contents/MacOS/DevHavenApp | rg -n 'LC_RPATH|path '`（修复前）→ 只有 `/usr/lib/swift`、`@loader_path`、Xcode Swift runtime 路径，没有 `@executable_path/../Frameworks`。
  - `swift test --package-path macos --filter NativeBuildScriptUpdateSupportTests`（补测试后、修复前）→ 2 failures，失败点正是缺少 `install_name_tool` / `@executable_path/../Frameworks` 断言。
  - `swift test --package-path macos --filter NativeBuildScriptUpdateSupportTests`（修复后）→ 2 tests，0 failures。
  - `swift test --package-path macos` → 240 tests，5 skipped，0 failures。
  - `bash macos/scripts/build-native-app.sh --release --no-open --skip-sign --output-dir /tmp/devhaven-native-app-manual --build-number 3000003` → exit 0，日志包含 `为主可执行文件注入 rpath：@executable_path/../Frameworks`。
  - `otool -l /tmp/devhaven-native-app-manual/DevHaven.app/Contents/MacOS/DevHavenApp | rg -n 'LC_RPATH|path '`（修复后）→ 新增 `path @executable_path/../Frameworks (offset 12)`。
  - `/tmp/devhaven-native-app-manual/DevHaven.app/Contents/MacOS/DevHavenApp` 后台启动并等待 3 秒 → `LAUNCH_STATUS=running`，说明已不再于 dyld 阶段因缺少 Sparkle.framework 立即崩溃。

## Review（2026-03-23 当前变更代码审查）

- 结论：本次审查基于当前工作树的 unstaged / untracked 变更完成，识别出 3 个需要优先处理的问题：
  1. Nightly 构建虽然在 `Info.plist` 写入了默认更新通道，但运行时完全没有读取该字段，首次启动仍会回到 `AppSettings()` 的 stable，导致 Nightly 安装后默认跟随 stable feed。
  2. stable release workflow 在 `prepare-release` 阶段把正式 `v*` release 一律创建 / 编辑为 prerelease，后续也没有切回正式 release。
  3. universal `.app` 是通过复制 arm64 `.app` 后再 `lipo` 替换主可执行文件生成的；但 workflow 把重新签名标记为“可选”，当 Developer ID secrets 缺失时仍会继续发布，留下签名失效的 universal 安装包。
- 验证证据：
  - `git status --short --branch`
  - `git diff --stat`
  - `swift test --package-path macos --filter '(DevHavenBuildMetadataTests|AppSettingsUpdatePreferencesTests|NativeBuildScriptUpdateSupportTests|ReleaseWorkflowUpdateInfrastructureTests|DevHavenAppCommandTests|SettingsViewTests)'` → 14 tests, 0 failures

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


## Review（2026-03-22 强制更新远端 v3.0.0 tag）

- 结果：已将远端 `origin` 上的 `v3.0.0` tag 强制更新到当前 merge commit `a15ebe8efea6a92536c2f433162300a764f4fcea`。
- 直接原因：本地 `v3.0.0^{}` 已指向新的 merge commit，但远端 `v3.0.0^{}` 仍停留在旧提交 `8535c55c8c5af501989bde83a243103baccae928`，因此需要执行一次显式 force-push 才能覆盖远端 tag。
- 设计层诱因：tag 覆盖与分支推送是两条独立链路；仅在本地重打 annotated tag，不会自动修改远端已有 tag。未发现明显系统设计缺陷。
- 当前处理方案：执行 `git push --force origin refs/tags/v3.0.0`，随后用 `git ls-remote --tags origin refs/tags/v3.0.0 refs/tags/v3.0.0^{}` 复核远端对象与 peeled commit。
- 长期改进建议：以后凡是“覆盖现有 release tag”，都应固定做两步验证：先核对本地 `tag^{}`，再核对远端 `refs/tags/<tag>^{}`，避免只看到 tag 对象变了，却忽略真正指向的 commit。
- 验证证据：
  - 2026-03-22 `git push --force origin refs/tags/v3.0.0` → `v3.0.0 -> v3.0.0 (forced update)`，exit 0。
  - 2026-03-22 `git rev-parse HEAD` → `a15ebe8efea6a92536c2f433162300a764f4fcea`。
  - 2026-03-22 `git rev-parse v3.0.0^{}` → `a15ebe8efea6a92536c2f433162300a764f4fcea`。
  - 2026-03-22 `git ls-remote --tags origin refs/tags/v3.0.0 refs/tags/v3.0.0^{}` → `refs/tags/v3.0.0^{}` 为 `a15ebe8efea6a92536c2f433162300a764f4fcea`。


## Review（2026-03-22 推送 main 到远端）

- 结果：已将本地 `main` 推送到远端 `origin/main`，远端分支现已指向当前 merge commit `a15ebe8efea6a92536c2f433162300a764f4fcea`。
- 直接原因：本地 `main` 在推送前领先 `origin/main` 6 个提交，且当前合并结果尚未同步到远端分支。
- 设计层诱因：分支推送与 tag 覆盖彼此独立；即使前一步已经把远端 `v3.0.0` 覆盖到新提交，远端 `main` 仍不会自动前进。未发现明显系统设计缺陷。
- 当前处理方案：执行 `git push origin main`，随后通过 `git ls-remote origin refs/heads/main` 与 `git fetch origin main --quiet && git rev-parse origin/main` 双重复核远端分支指向。
- 长期改进建议：以后在“先重写 release tag，再推送主分支”的场景中，建议固定把“tag 已更新”和“branch 已更新”作为两条独立检查项，避免只更新其中一条引用。
- 验证证据：
  - 2026-03-22 `git push origin main` → `75f4d3e..a15ebe8  main -> main`，exit 0。
  - 2026-03-22 `git ls-remote origin refs/heads/main` → `a15ebe8efea6a92536c2f433162300a764f4fcea	refs/heads/main`。
  - 2026-03-22 `git fetch origin main --quiet && git rev-parse origin/main` → `a15ebe8efea6a92536c2f433162300a764f4fcea`。


## Review（2026-03-22 GitHub Action release workflow 故障）

- 结果：已定位最新失败 run `23403125653` 的直接原因，并在本地完成最小修复与回归测试。失败不在构建阶段，而是在 `prepare-release` job 的 `Remove duplicate draft releases for tag` 步骤；该步骤调用了 `gh release list --json databaseId,tagName,isDraft`，但当前 GitHub CLI 官方支持字段里没有 `databaseId`，因此脚本在真正开始清理 draft release 前就直接退出。当前本地修复已改为走 GitHub Releases REST API 列表接口，通过稳定的 `id/tag_name/draft` 字段筛选并删除重复 draft release。
- 直接原因：`.github/workflows/release.yml` 第 43 行把 `gh run list` 风格的 `databaseId` 字段误用到了 `gh release list --json ...` 上；GitHub Actions runner 上的 `gh` 直接报 `Unknown JSON field: "databaseId"`，导致 `prepare-release` 失败，后续 `build-macos-native` 整个被跳过。
- 设计层诱因：release workflow 当前把“列出 release 并拿内部 id 删除草稿”建立在 GitHub CLI 某个子命令的 JSON 字段假设上，但 `gh release list` 的字段面并不覆盖内部 release id，这使脚本对 CLI 子命令实现细节过度耦合。未发现明显系统设计缺陷，但这一步更适合直接使用 Releases REST API 这种字段语义更稳定的主接口。
- 当前修复方案：
  1. 在 `macos/Tests/DevHavenCoreTests/ReleaseWorkflowTests.swift` 新增回归断言，禁止继续依赖 `gh release list --json databaseId,...`。
  2. 将 `.github/workflows/release.yml` 中的 draft release 清理改为：`gh api --paginate "repos/${GITHUB_REPOSITORY}/releases?per_page=100" --jq '.[] | select(.tag_name == env.RELEASE_TAG and .draft == true) | .id'`。
  3. 保持后续删除逻辑仍使用 `DELETE /repos/{owner}/{repo}/releases/{id}`，只修正“如何安全拿到 release id”这一处根因点。
- 长期改进建议：
  1. 对 GitHub CLI 子命令的 `--json` 字段依赖，建议都补一个最小回归测试或改走 REST API，避免 runner 侧 CLI 字段面差异再次把 workflow 炸掉。
  2. 这类 release 元数据清理逻辑，优先依赖 GitHub 官方 REST 响应字段（`id`、`tag_name`、`draft`），不要把不同 `gh` 子命令的 JSON 字段假设互相迁移复用。
- 验证证据：
  - GitHub failed run：`https://github.com/zxcvbnmzsedr/devhaven/actions/runs/23403125653`
  - `gh run view 23403125653 --log-failed`：失败步骤报错 `Unknown JSON field: "databaseId"`，可用字段仅有 `createdAt/isDraft/isImmutable/isLatest/isPrerelease/name/publishedAt/tagName`。
  - 2026-03-22 `gh release list --limit 1 --json databaseId,tagName,isDraft`：本地直接复现同样报错 `Unknown JSON field: "databaseId"`。
  - 2026-03-22 `swift test --package-path macos --filter ReleaseWorkflowTests`（修复前）→ 3 tests 中 1 failure，失败点为新增回归测试。
  - 2026-03-22 `swift test --package-path macos --filter ReleaseWorkflowTests`（修复后）→ 3 tests，0 failures，exit 0。
  - 2026-03-22 `gh api --paginate "repos/zxcvbnmzsedr/devhaven/releases?per_page=100" --jq '.[] | select(.tag_name == "v3.0.0" and .draft == true) | .id'` → exit 0，说明修复后采用的查询路径在当前环境可正常执行。


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

## 2026-03-22 排查并修复删除 worktree 时闪退

- [x] 在崩溃报告与现有代码中定位删除 worktree 时的崩溃链路
- [x] 判断直接原因与是否存在设计层诱因
- [x] 先补失败测试或最小复现场景，稳定约束该崩溃
- [x] 实施最小修复并保持最少改动边界
- [x] 运行验证并回填 Review（含证据）

## Review（2026-03-22 排查并修复删除 worktree 时闪退）

- 结果：已修复删除 worktree 时的 Ghostty 晚到回调闪退问题。当前 Ghostty surface 的 C callback userdata 不再直接暴露 `GhosttySurfaceBridge` 裸指针，而是改为稳定的 `GhosttySurfaceCallbackContext`；当 workspace/worktree 关闭触发 terminal surface teardown 后，晚到的 action / close / clipboard 回调会通过 context 安全判空并直接 no-op，不再命中已释放 bridge。
- 直接原因：`GhosttyRuntime.handleAction(...)` / `handleCloseSurface(...)` 之前会把 `surface userdata` 中的 `GhosttySurfaceBridge` 非持有裸指针跨 `DispatchQueue.main.async` 带到主线程；删除 worktree 时对应 pane/session 会先释放 surface/view/bridge，等主线程稍后执行晚到回调时，再按旧地址反解 bridge 就会落到悬挂对象，最终在 `GhosttySurfaceBridge.handleAction(...) -> GhosttySurfaceState.pwd.setter` 处触发 `EXC_BAD_ACCESS`。
- 设计层诱因：Ghostty C callback 生命周期此前直接耦合到短命的 Swift bridge/view 对象，userdata 既承担“回调入口”又隐含“对象仍存活”的假设，导致跨线程 hop 与 teardown 并发时没有稳定的中间宿主。未发现更大的系统设计缺陷，但 callback 生命周期边界此前没有收口。
- 当前修复方案：
  1. 新增 `GhosttySurfaceCallbackContext` 作为 surface userdata 的稳定宿主，线程安全持有当前 active bridge；
  2. `GhosttyRuntime` 的 action / close / clipboard 回调统一先解析 callback context，跨线程时只捕获 context，等真正执行时再读取 active bridge；
  3. `GhosttyTerminalSurfaceView.tearDown()` 开始时先 invalidation callback context，再继续 unregister/free surface，让 teardown 开始后的晚到回调统一 no-op；
  4. 补充 `GhosttySurfaceCallbackContextTests`，约束 active/invalidate 语义与异步 hop 场景。
- 长期改进建议：
  1. 后续新增 Ghostty runtime callback 时，继续沿用 callback context 模式，不要再把 `Unmanaged.passUnretained(short-lived object)` 的裸指针直接跨队列传递；
  2. 若未来 callback 类型继续增长，可考虑再把“userdata 解析 + active bridge 判定”收口成更统一的 helper，减少重复 fromOpaque 入口。
- 验证证据：
  - 2026-03-22 `swift test --package-path macos --filter GhosttySurfaceCallbackContextTests`（修复前）→ exit 1，编译报错 `cannot find type 'GhosttySurfaceCallbackContext' in scope`，确认失败测试先建立。
  - 2026-03-22 `swift test --package-path macos --filter GhosttySurfaceCallbackContextTests`（修复后）→ 2 tests，0 failures，exit 0。
  - 2026-03-22 `swift test --package-path macos --filter 'GhosttySurface(CallbackContext|BridgeTabPane|Host)Tests'` → 17 tests，5 skipped，0 failures，exit 0。
  - 2026-03-22 `swift test --package-path macos` → 228 tests，5 skipped，0 failures，exit 0。


## 2026-03-22 修复 release workflow arm64 测试时序脆弱性

- [x] 复核最新 release workflow 失败日志，确认仅 arm64 `swift test` 失败
- [x] 定位失败测试与直接原因，确认属于 AppKit firstResponder 异步时序脆弱而非 release workflow 逻辑回归
- [x] 参考现有可通过路径，将固定等待改为条件轮询，实施最小测试修复
- [x] 运行定向测试验证两条脆弱测试在本地通过
- [x] 运行完整 `swift test --package-path macos` 验证没有引入回归
- [x] 提交并推送测试稳定性修复到 `origin/main`
- [x] 重新触发 `release.yml(tag=v3.0.0)` 并验证 run / release 资产

## Review（2026-03-22 修复 release workflow arm64 测试时序脆弱性）

- 结果：已确认 release workflow 前两个工作流级故障已分别通过 `2a5555a` 与 `64e1b2a` 修复；当前剩余失败点收敛为 arm64 runner 上两条 AppKit 测试的固定等待时长不足。本轮先把测试等待从固定睡眠改为条件轮询，避免 CI 机器较慢时在真正状态达成前过早断言。
- 直接原因：
  1. `GhosttySurfaceHostTests.testRequestFocusRetriesWhenFirstResponderAssignmentMissesFirstAttempt` 依赖 `RunLoop.main.run(until: now + 0.2)`，CI arm64 机器上补焦点第二次尝试未必在 0.2 秒内完成；
  2. `ProjectDetailPanelCloseActionTests.testClosingDetailPanelReleasesActiveEditorResponderBeforeHidingPanel` 同样用固定 `0.3` 秒等待 firstResponder 释放和右侧面板关闭；
  3. 两条测试都把“时间足够久”误当成“状态已经满足”，因此在慢机上出现假失败。
- 设计层诱因：测试代码把 AppKit 异步 firstResponder / 面板关闭链路建模成固定时长等待，而不是等待明确条件成立，导致验证依赖机器速度。未发现明显系统设计缺陷，但测试同步策略此前没有收口为条件驱动。
- 当前修复方案：
  1. 在两条测试里把固定 `RunLoop.main.run(until:)` 改为 `waitUntil(...)` 条件轮询；
  2. `GhosttySurfaceHostTests` 等待“焦点补偿至少执行两次且 firstResponder 已切回 terminal view”；
  3. `ProjectDetailPanelCloseActionTests` 等待“编辑器已释放 firstResponder 且详情面板状态已关闭”；
  4. 保持生产代码不变，只修测试同步方式。
- 长期改进建议：
  1. 后续凡是验证 AppKit / SwiftUI 异步状态流转的测试，优先统一为条件等待 helper，而不是分散写固定 sleep；
  2. 若类似等待逻辑继续增多，可提取测试公共 helper，减少不同测试文件各自维护轮询实现。
- 验证证据：
  - 2026-03-22 `gh run view 23403375014 --log-failed` 日志定位到 arm64 job 失败测试：`GhosttySurfaceHostTests.testRequestFocusRetriesWhenFirstResponderAssignmentMissesFirstAttempt` 与 `ProjectDetailPanelCloseActionTests.testClosingDetailPanelReleasesActiveEditorResponderBeforeHidingPanel`。
  - 2026-03-22 `swift test --package-path macos --filter 'GhosttySurfaceHostTests/testRequestFocusRetriesWhenFirstResponderAssignmentMissesFirstAttempt|ProjectDetailPanelCloseActionTests/testClosingDetailPanelReleasesActiveEditorResponderBeforeHidingPanel'` → 2 tests，0 failures，exit 0。
  - 2026-03-22 `swift test --package-path macos` → 226 tests，5 skipped，0 failures，exit 0。
  - 2026-03-22 `git push origin main`：将提交 `662f9411df5612f73a5943d92de603b142c70f76` 推送到 `origin/main`。
  - 2026-03-22 `git tag -fa v3.0.0 -m "v3.0.0" HEAD && git push origin refs/tags/v3.0.0 --force`：本地 / 远端 `v3.0.0^{}` 均已指向 `662f9411df5612f73a5943d92de603b142c70f76`。
  - 2026-03-22 `gh run view 23403723188 --json status,conclusion,jobs,url` → `status=completed`、`conclusion=success`，`prepare-release` / `build-macos-native (x86_64, macos-26, x86_64-apple-macosx14.0)` / `build-macos-native (arm64, macos-26)` 全部成功。
  - 2026-03-22 `gh release view v3.0.0 --json assets` → 产物包含 `DevHaven-macos-arm64.zip`、`DevHaven-macos-x86_64.zip`。

## 2026-03-22 提交删除 worktree 闪退修复并重新覆盖 v3.0.0

- [x] 核对当前工作区改动、已有验证证据与本地 tag 现状
- [ ] 复跑提交前验证，确认当前改动可提交
- [ ] 提交当前修复到 `main`
- [ ] 将 `v3.0.0` 覆盖到新提交并推送 branch/tag
- [ ] 观察 GitHub Actions / release 状态并回填 Review

## Review（2026-03-23 升级方案对标调研：cmux / supacode / ghostty）

- 结果：已对比 cmux、Supacode、Ghostty 三个 macOS 原生项目的升级主链，并回到 DevHaven 当前发布形态给出建议。结论是：**不要直接在当前 `swift build + 手工拼 .app + zip 上传` 链路上硬接完整升级功能**；更稳的路径是先补齐 release-grade 打包基座（至少单调递增 build number、Sparkle 运行所需 bundle 结构、Developer ID 签名 / notarization、appcast 发布顺序），再上最小可用的 Sparkle 升级能力。三者里最值得借鉴的是 **Ghostty 的“资产先上传、appcast 最后发布”操作顺序** + **cmux 的“单调 build number / 稳定 nightly/stable feed 管理”**；Supacode 的 delta / history / merged appcast 方案更强，但对 DevHaven 当前阶段偏重。
- 直接原因：DevHaven 当前 release workflow 只产出 `DevHaven-macos-*.zip` 并上传到 GitHub Release，`macos/scripts/build-native-app.sh` 仍把 `CFBundleVersion` 固定写成 `1`，且没有 `SUPublicEDKey` / `SUFeedURL` / Sparkle framework / notarization / appcast 主链，因此“升级”问题本质上不是某个 UI 开关没做，而是**底层发布介质与升级协议尚未建立**。
- 设计层诱因：当前 DevHaven 把“开发态可运行”与“发布态可升级”复用为同一条轻量脚本链路；这对快速构建够用，但一旦进入自升级场景，就会把 bundle 组装、框架嵌入、签名、公钥注入、版本号语义、appcast 发布时序等多种职责挤到同一层，容易出现“能打包但不能可靠升级”的结构性问题。未发现明显系统设计缺陷，但**发布链路目前缺少独立的升级基座层**。
- 当前建议：
  1. **先学 Ghostty / cmux 的基座，不先学 Supacode 的高级玩法。** 第一阶段只做 stable channel、完整包更新、不做 delta。
  2. **把 `CFBundleVersion` 改成单调递增的构建号真相源**，不要继续固定为 `1`；`CFBundleShortVersionString` 继续表达用户可见版本（如 `3.0.0`），`CFBundleVersion` 专门用于升级比较。cmux 已明确为 Sparkle 修过“build number 落后于 appcast 导致无法升级”的问题。
  3. **为发布态引入真正的 macOS app 打包壳**（推荐 Xcode app target / project，继续复用现有 Swift Package 里的业务代码），因为 cmux / Supacode / Ghostty 的 Sparkle 集成全部建立在 Xcode app bundle、框架嵌入和单独 codesign Sparkle 组件的前提上。若继续坚持纯脚本手工拼 bundle，也要接受后续在脚本里手工拷贝并签 Sparkle.framework / Updater.app / Autoupdate / XPCServices 的复杂度。
  4. **发布顺序采用 Ghostty 模式：先上传所有安装资产，再发布 appcast。** 不要像现在一样把“发布元数据”和“可触发升级的 feed”混在一起同步暴露。最稳妥是：`DevHaven.dmg` / `DevHaven.app.zip` 先上传到稳定 URL，验活后再把 `appcast.xml` 提升为正式 feed。
  5. **初期 channel 设计用“两个 feed，少做魔法”。** stable 一个 feed；如果以后要 nightly/tip，可学 Ghostty/cmux：要么单独 nightly feed，要么再加 bundle id 区分。不要一开始就上 Supacode 那套 merged appcast + history assets + delta patch。
  6. **UI 只做最小闭环**：菜单里的“检查更新”、设置中的“自动检查 / 自动下载”即可；等发布链路稳定后，再考虑 cmux 那种自定义 popover / update logs。
- 长期改进建议：
  1. 若 DevHaven 后续稳定版 / nightly 都要长期维护，可继续向 Ghostty 靠拢：用独立静态托管（GitHub Pages / R2 / 自有域名）承载 appcast 与安装包，不再依赖 GitHub `latest/download` 语义。
  2. 若下载体积和升级频率真的成为痛点，再评估 Supacode 的 delta updates；但在当前阶段，它会显著放大发布链路复杂度与故障面。
  3. 若仍保留 GitHub Release 作为主分发面，至少把 stable release 从当前 `--prerelease` 语义中分离出来，否则未来即使接 Sparkle，`latest` / stable feed 语义也会持续混乱。
- 验证证据：
  - 2026-03-23 阅读 `DevHaven/.github/workflows/release.yml` 与 `macos/scripts/build-native-app.sh`，确认当前只上传 zip、且脚本生成的 `Info.plist` 把 `CFBundleVersion` 固定为 `1`。
  - 2026-03-23 阅读 `cmux/Resources/Info.plist`、`cmux/Sources/Update/{UpdateController,UpdateDelegate}.swift`、`cmux/scripts/{build-sign-upload,bump-version}.sh`、`cmux/.github/workflows/nightly.yml`，确认其采用 Sparkle、稳定/夜版 feed、单调 build number 与完整签名 / notarization / appcast 生成链路。
  - 2026-03-23 阅读 `supacode/supacode/Clients/Updates/UpdaterClient.swift`、`supacode/.github/workflows/{release,release-tip}.yml`，确认其采用 Sparkle + stable/tip channel + delta/history appcast 方案。
  - 2026-03-23 阅读 `ghostty/macos/Sources/Features/Update/{UpdateController,UpdateDelegate}.swift`、`ghostty/.github/workflows/{release-tag,publish-tag}.yml`、`ghostty/dist/macos/update_appcast_{tag,tip}.py`，确认其采用 Sparkle、stable/tip 分离 feed，以及“资产先上传、appcast staged 后发布”的两阶段发布顺序。



## Review（2026-03-23 升级终局方案实现）

- 结果：已为 DevHaven 落地完整的 macOS 自升级主链，覆盖客户端设置/菜单、Sparkle runtime、Sparkle vendor、本地打包元数据、stable staged appcast、nightly 独立 workflow，以及 universal 更新包合成链路。
- 直接原因：当前仓库虽然已经有原生打包能力，但缺少“客户端可消费的升级协议 + 发布侧可持续维护的固定 feed”，导致 release 只能手动下载，无法形成稳定的自升级闭环。
- 设计层诱因：原先发布主链只关心“按架构上传 zip”，没有把版本单调性、feed 固定 URL、升级签名元数据、客户端更新偏好、以及 universal 安装包这些升级系统必须收口的真相源统一起来。
- 当前修复方案：
  1. 在 `AppSettings` 中新增 `updateChannel`、`updateAutomaticallyChecks`、`updateAutomaticallyDownloads`，并保持旧配置兼容回退。
  2. 在设置页与 App 菜单增加“检查更新”入口，并接入 `DevHavenUpdateController`。
  3. 新增 `DevHavenBuildMetadata` / `DevHavenUpdateDiagnostics` / `DevHavenUpdateController`，让开发态默认禁用 updater，release `.app` 通过 Sparkle feed + 公钥启用升级。
  4. 新增 `setup-sparkle-framework.sh`、`generate-appcast.sh`、`promote-appcast.sh`、`create-universal-app.sh`，并让 `build-native-app.sh` 嵌入 `Sparkle.framework`、写入 `CFBundleVersion` / `SUFeedURL` / `SUPublicEDKey`。
  5. 重写 `.github/workflows/release.yml` 与新增 `.github/workflows/nightly.yml`：矩阵构建 arm64/x86_64，后置 job 合成 universal 包，生成 `appcast-staged.xml`，再 promote 到 `stable-appcast/appcast.xml` 与 `nightly/appcast.xml`。
  6. 同步更新 `README.md` 与 `AGENTS.md`，把 Sparkle vendor、更新设置、发布 alias feed 与 universal 打包约定写回文档。
- 长期改进建议：
  1. 当前 workflow 已预留可选 Developer ID 签名 / notarization 步骤，但仍依赖仓库 secrets；上线前应在真实 GitHub runner 上完成一次完整冒烟，确认 Sparkle key、Apple 签名与 notary 配置可用。
  2. 当前 appcast 先以完整包更新为主，`maximum-deltas=0`；若后续 nightly/stable 体积压力明显，再沿现有脚本把历史 universal 归档下载回本地生成 delta。
  3. 若以后需要更细粒度的 phased rollout 或 beta channel，可继续在 `generate-appcast.sh` 基础上增加 channel / rollout 参数，而不必再改客户端协议。
- 验证证据：
  - `bash macos/scripts/setup-sparkle-framework.sh --verify-only`
  - `bash -n macos/scripts/create-universal-app.sh`
  - `bash -n macos/scripts/generate-appcast.sh`
  - `bash -n macos/scripts/promote-appcast.sh`
  - `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release.yml"); YAML.load_file(".github/workflows/nightly.yml"); puts "workflows ok"'`
  - `swift test --package-path macos --filter 'AppSettingsUpdatePreferencesTests|SettingsViewTests|DevHavenAppCommandTests|DevHavenBuildMetadataTests|NativeBuildScriptUpdateSupportTests|ReleaseWorkflowTests|ReleaseWorkflowUpdateInfrastructureTests'`
  - `swift test --package-path macos`
  - `swift build --package-path macos`
  - `bash macos/scripts/build-native-app.sh --release --no-open --skip-sign --output-dir /tmp/devhaven-native-app-updater --build-number 3000001 --sparkle-public-key test-public-key`
  - `plutil -p /tmp/devhaven-native-app-updater/DevHaven.app/Contents/Info.plist | rg 'CFBundleVersion|SUFeedURL|DevHavenStableFeedURL|DevHavenNightlyFeedURL|SUPublicEDKey|DevHavenDefaultUpdateChannel'`
  - `test -d /tmp/devhaven-native-app-updater/DevHaven.app/Contents/Frameworks/Sparkle.framework`

## 2026-03-23 修复 Nightly 默认升级通道回退 stable

- [x] 核实 Nightly 构建默认升级通道未闭环的直接原因与影响链路
- [ ] 设计 bundle 默认通道与持久化设置的收口方案，并获得确认
- [ ] 先补失败测试，覆盖 fresh install / legacy settings 对默认通道的行为
- [ ] 实施最小修复，确保 Nightly 首次启动默认跟随 nightly feed
- [ ] 运行定向验证并在本文件追加 Review



## Review（2026-03-23 无苹果账号升级模式收口）

- 结果：已把 DevHaven 的升级体验收口为“无苹果开发者账号可正式交付”的形态：正式 `.app` 现在默认采用 `manualDownload` 交付模式，应用内可继续 stable / nightly 检查更新、导出诊断、打开下载页，但不会再把自动安装更新作为默认承诺。
- 直接原因：用户当前没有 Apple Developer Program 账号，无法提供 Developer ID 签名与 notarization，因此继续把 Sparkle 自动安装当成默认交付路径，会让客户端能力与实际分发信任链不一致。
- 设计层诱因：上一版虽然已经补齐 Sparkle runtime / appcast / workflow 主链，但客户端仍把“支持检查更新”和“支持自动安装更新”混成一个布尔语义，缺少无账号场景下的正式 fallback 模式。
- 当前修复方案：
  1. 新增 `DevHavenUpdateDeliveryMode`，并在 `AppMetadata.json` / `Info.plist` 中写入 `manualDownload`、stable/nightly 下载页 URL。
  2. `DevHavenBuildMetadata` 改为区分 `supportsUpdateChecks` 与 `supportsAutomaticUpdates`：正式 `.app` + feed 存在即可检查更新；只有 `automatic` 模式且存在 `SUPublicEDKey` 时才允许自动安装。
  3. 新增 `DevHavenAppcastParser`，在 manual-download 模式下直接读取 appcast，解析最新版本、build、下载链接 / release notes 链接。
  4. `DevHavenUpdateController` 新增 manual-check 分支：保留“立即检查更新”，检查到新版本后给出“请打开下载页完成更新”，并支持 `openDownloadPage()`。
  5. `SettingsView` 新增“打开下载页”按钮，并在自动下载不可用时禁用“自动下载更新”开关。
  6. 同步更新 `README.md` 与 `AGENTS.md`，明确默认交付模式是 manual-download，未来补齐 Apple Developer ID / notarization 后再切到 `automatic`。
- 长期改进建议：
  1. 以后如果补齐 Apple Developer 账号，可直接把 `AppMetadata.json` 的 `updateDeliveryMode` 切到 `automatic`，并在 CI 配置 Developer ID / notarization secrets；当前主链无需重写。
  2. 当前 manual-download 模式主要依赖 appcast 的最新条目与下载页 fallback；若后续要做更精细的“跳过版本 / phased rollout / 增量提醒”，可继续沿 appcast 解析层演进，而不必回退到 GitHub API 特判。
- 验证证据：
  - `swift test --package-path macos --filter 'DevHavenBuildMetadataTests|DevHavenAppcastParserTests|SettingsViewTests|NativeBuildScriptUpdateSupportTests'`
  - `bash macos/scripts/setup-sparkle-framework.sh --verify-only`
  - `bash -n macos/scripts/build-native-app.sh`
  - `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release.yml"); YAML.load_file(".github/workflows/nightly.yml"); puts "workflows ok"'`
  - `bash macos/scripts/build-native-app.sh --release --no-open --skip-sign --output-dir /tmp/devhaven-native-app-manual --build-number 3000002`
  - `plutil -p /tmp/devhaven-native-app-manual/DevHaven.app/Contents/Info.plist | rg 'CFBundleVersion|SUFeedURL|DevHavenStableFeedURL|DevHavenNightlyFeedURL|DevHavenUpdateDeliveryMode|DevHavenStableDownloadsPageURL|DevHavenNightlyDownloadsPageURL|SUPublicEDKey'`
  - `test -d /tmp/devhaven-native-app-manual/DevHaven.app/Contents/Frameworks/Sparkle.framework`
  - `swift test --package-path macos`
  - `swift build --package-path macos`
