# 本次任务清单

## 继续修复 workspace 分屏后旧 pane 仍会丢失（2026-03-21）

- [x] 复盘上轮分屏修复与当前截图，确认真正仍在失效的是 surface 状态重放时序
- [x] 先补失败测试，锁定“只有在新容器完成 attach/layout 后才能重放状态”这条边界
- [x] 以最小改动把 post-attach replay 收口到 `GhosttySurfaceScrollView` + `GhosttySurfaceHostModel`
- [x] 运行定向验证并在 `tasks/todo.md` 追加 Review

## Review（继续修复 workspace 分屏后旧 pane 仍会丢失）

- 直接原因：上一轮虽然已经在 `prepareForContainerReuse()` 里清掉了 `occlusion / focus / backing size` 缓存，但 `GhosttySurfaceHostModel.acquireSurfaceView(...)` 仍然会**在旧 `GhosttySurfaceScrollView` 还没完成移除、新 `GhosttySurfaceScrollView` 还没完成 addSubview/layout 之前**就把这些状态重放回 `GhosttyTerminalSurfaceView`。结果就是：缓存确实被清了，但 replay 仍然打在旧容器时序上；等旧 pane 真正被挂到新的 split 容器后，已经没有新的 attach 后 replay，所以用户仍会看到“左边旧 pane 发白/内容消失”。
- 设计层诱因：存在。问题不再是 split tree 或 surface owner 本身，而是 **surface 复用生命周期被拆成了“model 取 view”与“scroll/container 真正 attach”两段，却把 attach-sensitive replay 放在了前一段**。也就是说，状态缓存和状态重放虽然都已收口，但重放时机仍然分裂。未发现更大的系统设计缺陷。
- 当前修复：
  1. `GhosttySurfaceScrollView` 新增 `onSurfaceAttached` 回调与一次性 `needsSurfaceAttachmentCallback` 标记，只在真实 `layout()` 完成后触发 post-attach hook；
  2. `GhosttySurfaceHostModel.acquireSurfaceView(...)` 在复用既有 surface 时不再提前重放状态，只负责准备复用与记录 diagnostics；
  3. 新增 `GhosttySurfaceHostModel.surfaceViewDidAttach(preferredFocus:)`，把 `occlusion / focus` replay 收口到**真实 attach 完成之后**执行；
  4. `GhosttyTerminalView` 负责把 scroll wrapper 的 attach 回调接回 `surfaceViewDidAttach(...)`，确保首次挂载和 split/tree 迁移后的重新挂载都走同一条时序；
  5. `GhosttySurfaceScrollViewTests` 新增两条回归：锁定“首轮 layout 只回调一次”和“surface swap 后要再回调一次”。
- 长期建议：如果后续 split/tree/zoom 继续暴露新的 AppKit 容器迁移问题，下一步优先考虑把“稳定 owner”继续上提到完整 hosted container，而不是继续在 `GhosttyTerminalSurfaceView` 内增加更多局部 cache reset；但在当前主线上，先把 replay 时序钉死到 post-attach 已经足够对齐当前故障。
- 验证证据：
  - TDD 红灯：`swift test --package-path macos --filter GhosttySurfaceScrollViewTests` → 初次失败，报 `extra argument 'onSurfaceAttached' in call`，证明测试先锁住了“需要显式 post-attach hook”这条边界。
  - 定向绿灯：同一条命令修复后通过，`4 tests, 0 failures`。
  - 相关回归：`swift test --package-path macos --filter 'WorkspaceTerminalSessionStoreTests|WorkspaceSurfaceRegistryTests|WorkspaceTerminalStoreRegistryTests|WorkspaceSplitTreeViewKeyPolicyTests|GhosttySurfaceScrollViewTests'` → 通过，`14 tests, 0 failures`。
  - 构建验证：`swift build --package-path macos` → 通过。
  - 差异校验：`git diff --check -- macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceScrollView.swift macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceHost.swift macos/Sources/DevHavenApp/Ghostty/GhosttyTerminalView.swift macos/Tests/DevHavenAppTests/GhosttySurfaceScrollViewTests.swift` → 通过。

## 继续修复“先点亮 pane 焦点，再分屏时旧 pane 消失”（2026-03-21）

- [x] 根据新复现条件聚焦 firstResponder / surface focus 链路，而不是继续泛化到 split 拓扑
- [x] 先补失败测试，锁定“container reuse 前必须释放旧 pane 的 window firstResponder”边界
- [x] 以最小改动把 firstResponder 释放收口到 `GhosttyTerminalSurfaceView.prepareForContainerReuse()` / `tearDown()`
- [x] 运行定向验证并追加 Review

## Review（继续修复“先点亮 pane 焦点，再分屏时旧 pane 消失”）

- 直接原因：你补充的“**先点击 pane 让它拿到真实焦点，再分屏就稳定消失**”把根因进一步钉死到了 AppKit responder 链。当前 `GhosttyTerminalSurfaceView.prepareForContainerReuse()` 之前只会清 attachment cache，却不会释放 `window.firstResponder`；所以当旧 pane 的 surface 已经因为鼠标点击拿到真实 firstResponder 时，split/tree 重挂载会把**带着旧 responder 身份的 surface**直接搬进新容器，表现成旧 pane 在分屏后变白/内容丢失。
- 设计层诱因：存在。这说明当前 Ghostty surface 的“可见性/尺寸状态”与“AppKit responder 身份”仍然分裂管理：前者已经收口到 attachment replay，后者却没纳入 reuse 生命周期。未发现更大的系统设计缺陷，问题仍集中在 `GhosttyTerminalSurfaceView` 这一层的复用边界。
- 当前修复：
  1. 在 `GhosttyTerminalSurfaceView` 新增 `resignOwnedFirstResponderIfNeeded()`，仅当窗口当前 firstResponder 确实是该 surface（或其后代）时才显式 `makeFirstResponder(nil)`；
  2. `prepareForContainerReuse()` 和 `tearDown()` 都先释放 owned firstResponder，再清本地 `focused` 状态与 attachment cache，确保 surface 不会“带着旧焦点”进入新 split 容器；
  3. 新增回归测试 `GhosttySurfaceHostTests.testPrepareForContainerReuseYieldsWindowFirstResponderWhenSurfaceViewOwnsResponder`，锁定这条 firstResponder 释放边界。
- 长期建议：后续所有 pane 复用/关闭/隐藏问题，都要同时检查两类状态是否成对收口：一类是 Ghostty 的 `occlusion / focus / size`，另一类是 AppKit 的 `window.firstResponder`。只清 Ghostty 内部状态、不处理 AppKit responder，仍然会留下“点击后才触发”的 GUI 级缺陷。
- 验证证据：
  - TDD 红灯：`swift test --package-path macos --filter GhosttySurfaceHostTests/testPrepareForContainerReuseYieldsWindowFirstResponderWhenSurfaceViewOwnsResponder` → 初次失败，断言 `window.firstResponder === view` 仍成立，证明 reuse 前没有释放旧焦点。
  - 定向绿灯：同一条命令修复后通过，`1 test, 0 failures`。
  - 相关回归：`swift test --package-path macos --filter 'GhosttySurfaceHostTests/testPrepareForContainerReuseYieldsWindowFirstResponderWhenSurfaceViewOwnsResponder|GhosttySurfaceScrollViewTests|WorkspaceTerminalSessionStoreTests|WorkspaceSurfaceRegistryTests|WorkspaceTerminalStoreRegistryTests|WorkspaceSplitTreeViewKeyPolicyTests'` → 通过，`15 tests, 0 failures`。
  - 构建验证：`swift build --package-path macos` → 通过。
  - 差异校验：`git diff --check -- macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceView.swift macos/Tests/DevHavenAppTests/GhosttySurfaceHostTests.swift` → 通过。
  - 本轮 fresh 验证：再次运行同一组相关回归 → 通过，`15 tests, 0 failures`。
  - 本轮 full suite：`swift test --package-path macos` → 通过，`118 tests, 5 skipped, 0 failures`。

## 继续修复“点击 pane 后分屏，旧 terminal surface 跑到另一侧、原 pane 留空壳”（2026-03-21）

- [x] 根据最新截图复盘 split 后左右 pane 的真实呈现，确认这次更像 representable 复用换 model 时仍挂着旧 surface，而不是 pane 真被删除
- [x] 先补失败测试，锁定“update 阶段切换到 fresh model 时也必须拿到该 model 自己的 surface”这条边界
- [x] 以最小改动修复 `GhosttyTerminalView` / representable 的 surface 绑定逻辑，避免旧 surface 跟着被复用的 NSView 跑到错误 pane
- [x] 运行定向验证、全量 `swift test --package-path macos` 与差异检查，并把结果追加到 Review

## Review（继续修复“点击 pane 后分屏，旧 terminal surface 跑到另一侧、原 pane 留空壳”）

- 直接原因：最新截图显示的问题不再像“旧 pane 被删掉”，而更像 **旧 terminal surface 跟着被 SwiftUI 复用的 representable 跑到了另一侧 pane，原 pane 留下空壳背景**。顺着这条线往下查，`GhosttySurfaceRepresentable.updateNSView()` 之前只会读取 `model.currentSurfaceView`；如果同一个 `NSViewRepresentable` 在 leaf -> split 的重组里被 SwiftUI 复用到了新的 pane/model，而新 model 此时还没有 `currentSurfaceView`，它就会继续挂着旧 pane 的 surface，不会在 update 阶段为新 model 补一次 `acquireSurfaceView(...)`。
- 设计层诱因：存在。虽然我们之前已经把 subtree structural remount 和 post-attach replay 收口了，但 **representable 这一层仍默认假设“update 时 model 不会换成一个 fresh owner”**。这在普通 SwiftUI 视图里常常没问题，但对“一个活着的 terminal NSView 被外部 store 复用、同时树结构又在变化”的场景就不够稳。未发现更大的系统设计缺陷，问题集中在 representable 的 surface 解析边界。
- 当前修复：
  1. 给 `GhosttySurfaceRepresentableUpdatePolicy` 新增 `resolvedSurfaceView(for:preferredFocus:)`，统一定义“若 model 还没有 current surface，就在此处补 `acquireSurfaceView(...)`”；
  2. `GhosttyTerminalView.makeNSView` 与 `updateNSView` 都改为走这条统一解析逻辑，确保 representable 即使在 update 阶段换到一个 fresh model，也会拿到 **这个 model 自己的 surface**，而不是继续沿用旧 surface；
  3. 新增 `GhosttySurfaceRepresentableUpdatePolicyTests` 两条回归：fresh model 会创建 surface、已有 surface 的 model 会继续复用原实例；
  4. 测试里对新建的 `GhosttySurfaceHostModel` 显式 `releaseSurface()`，避免真实 Ghostty surface 在 full suite 里遗留到后续 AppKit 测试进程。
- 长期建议：后续只要继续沿“外部 store 持有终端 owner，SwiftUI 只负责摆放容器”这条架构，就要默认把 `NSViewRepresentable` 当成**可能被复用换 model** 的边界处理，而不是假设只有 `makeNSView` 会负责建立 owner -> NSView 绑定。对这种终端宿主组件，`updateNSView` 也要能安全地完成 owner 切换。
- 验证证据：
  - TDD 红灯：`swift test --package-path macos --filter GhosttySurfaceRepresentableUpdatePolicyTests` → 初次失败，报 `type 'GhosttySurfaceRepresentableUpdatePolicy' has no member 'resolvedSurfaceView'`。
  - 新增回归：同一条命令修复后通过，`3 tests, 0 failures`。
  - 相关分屏回归：`swift test --package-path macos --filter 'GhosttySurfaceRepresentableUpdatePolicyTests|GhosttySurfaceHostTests/testPrepareForContainerReuseYieldsWindowFirstResponderWhenSurfaceViewOwnsResponder|GhosttySurfaceScrollViewTests|WorkspaceTerminalSessionStoreTests|WorkspaceSurfaceRegistryTests|WorkspaceTerminalStoreRegistryTests|WorkspaceSplitTreeViewKeyPolicyTests'` → 通过，`18 tests, 0 failures`。
  - 全量验证：`swift test --package-path macos` → 最终 fresh 重跑通过，`120 tests, 5 skipped, 0 failures`。
  - 差异校验：`git diff --check -- macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceRepresentableUpdatePolicy.swift macos/Sources/DevHavenApp/Ghostty/GhosttyTerminalView.swift macos/Tests/DevHavenAppTests/GhosttySurfaceRepresentableUpdatePolicyTests.swift tasks/todo.md` → 通过。

## 新增 ./release 原生打包入口（2026-03-21）

- [x] 对照现有 `./dev` 与 `macos/scripts/build-native-app.sh`，确认新入口的最小职责边界
- [x] 确认 `./release` 的行为与参数范围，避免把发布包装脚本做成另一套复杂构建系统
- [x] 实现仓库根 `./release` 入口，并补充必要文档
- [x] 运行定向验证并在 `tasks/todo.md` 追加 Review

## Review（新增 ./release 原生打包入口）

- 直接原因：仓库根目录已经有 `./dev` 作为原生开发态入口，但本地 release 打包仍要求手动记忆并输入 `bash macos/scripts/build-native-app.sh --release`；同时这次给 `./release` 补回归测试时又暴露出 `build-native-app.sh --help` 本身存在 heredoc 帮助文案展开错误，导致入口链上的帮助信息也不可靠。
- 设计层诱因：存在，但属于轻量工具链边界问题。开发入口和打包入口没有在仓库根统一收口，导致“运行用 `./dev`、打包用长命令”的体验分裂；另外包装脚本如果继续复制一套参数解析，也会把打包真相源拆成两份。未发现更大的系统设计缺陷。
- 当前修复：
  1. 新增仓库根 `./release`，固定在仓库根目录执行 `bash macos/scripts/build-native-app.sh --release`，并透传其余参数；
  2. `./release` 显式拒绝 `--debug`，避免 release 入口被悄悄降级成 debug 打包；
  3. 新增 `macos/scripts/test-release-command.sh`，锁定“透传参数 + 固定带 `--release` + 拒绝 `--debug` + `--help` 可用”这几条边界；
  4. 修复 `macos/scripts/build-native-app.sh --help` 的文案展开问题，避免 heredoc 中的反引号和默认值变量把帮助输出本身炸掉；
  5. `README.md` 与 `AGENTS.md` 同步补充 `./release` 入口说明，保持仓库结构与使用文档一致。
- 长期建议：后续如果还要加别的仓库根入口，继续保持“根入口只做 thin wrapper，真正逻辑仍收口到单一脚本/模块”这条边界；不要把 `./release` 再扩成第二套打包系统。
- 验证证据：
  - TDD 红灯：`bash macos/scripts/test-release-command.sh` 在实现前失败，报 `/Users/zhaotianzeng/WebstormProjects/DevHaven/release: No such file or directory`。
  - 定向绿灯：`bash macos/scripts/test-release-command.sh` → 通过，输出 `release command smoke ok`。
  - 帮助验证：`bash macos/scripts/build-native-app.sh --help` → 通过，正确打印帮助文案。
  - 行为验证：`./release --no-open --output-dir /tmp/devhaven-release-verify` → 通过，产物为 `/tmp/devhaven-release-verify/DevHaven.app`。
  - 差异校验：`git diff --check` → 通过。

## 修复终端粘贴图片文件路径缺失（2026-03-21）

- [x] 先确认当前仓库已有未提交改动的隔离边界，避免混入字体 / 分屏等其他任务
- [x] 写失败测试，锁定 Ghostty 风格的 file URL / utf8 plain text 粘贴预期
- [x] 以最小改动补齐 Ghostty 风格 pasteboard helper，并接入 `GhosttyRuntime.handleReadClipboard(...)`
- [x] 运行定向验证，并同步 `tasks/todo.md`、必要文档与 `AGENTS.md`

## Review（修复终端粘贴图片文件路径缺失）

- 直接原因：`GhosttyRuntime.handleReadClipboard(...)` 之前只读取 `NSPasteboard.string(forType: .string)`。当用户从 Finder 或其他宿主复制图片文件时，剪贴板常见真相源是 file URL 或 `public.utf8-plain-text`，不是 `.string`，所以终端最终收到的是空串，连图片文件路径都粘贴不进去。
- 设计层诱因：Ghostty clipboard 语义此前被收窄成了“只认 plain string”，没有把 file URL / utf8 plain text 这些终端真实会遇到的 pasteboard 形态统一收口。问题集中在剪贴板桥接边界；未发现更大的系统设计缺陷。
- 当前修复：
  - 新增 `macos/Sources/DevHavenApp/Ghostty/GhosttyPasteboard.swift`，按 Ghostty 原生结构收口 pasteboard 语义：优先 file URL，回退 `.string` 与 `public.utf8-plain-text`，并对文件路径做 shell escape；
  - `GhosttyRuntime.handleReadClipboard(...)` 改为通过 `NSPasteboard.ghostty(location)?.getOpinionatedStringContents()` 读取剪贴板；
  - `AGENTS.md` 同步补充 `GhosttyPasteboard.swift` 的职责说明；
  - 新增 `GhosttyPasteboardTests` 锁定 file URL 与 utf8 plain text 两条回归预期。
- 长期建议：如果后续用户继续追求“截图本体也能粘进去”，那已经超出 Ghostty 原生路径粘贴边界，应另起一层做 cmux 那种“图片物化为临时文件/远端上传后再注入路径”的宿主增强；不要把图片附件语义继续塞回这个 Ghostty 对齐 helper。
- 验证证据：
  - TDD 红灯：`swift test --package-path macos --filter GhosttyPasteboardTests` → 初次失败，报 `value of type 'NSPasteboard' has no member 'getOpinionatedStringContents'`。
  - 定向绿灯：`swift test --package-path macos --filter GhosttyPasteboardTests` → 通过，`2 tests, 0 failures`。
  - 差异校验：`git diff --check` → 通过。
  - 隔离边界：当前仓库还存在与本任务无关的既有改动（如 `README.md`、`GhosttySurfaceHost.swift`、`GhosttySurfaceView.swift` 等），本轮仅新增/修改 Ghostty pasteboard 对齐相关文件与任务文档。

## 修复 ./dev 启动时字体丢失（2026-03-21)

- [x] 先确认当前仓库已有未提交改动的隔离边界，避免混入其他任务
- [x] 复现 `./dev` 启动时字体丢失的链路，并区分是 UI 字体还是 Ghostty 终端字体
- [x] 对照 `./dev` 启动脚本、Ghostty runtime 与字体资源定位逻辑，锁定直接原因与设计诱因
- [x] 以最小改动修复根因，并补充必要测试/文档
- [x] 运行定向验证并在 `tasks/todo.md` 追加 Review

## Review（修复 ./dev 启动时字体丢失）

- 直接原因：`GhosttyRuntime` 之前直接调用 `ghostty_config_load_default_files(config)`，而当前 `GhosttyKit` binary target 是按 `com.mitchellh.ghostty` 构建的。结果 DevHaven 在 `./dev` 启动时会跟着 Ghostty 默认搜索路径去读取 `~/Library/Application Support/com.mitchellh.ghostty/config`。本机该文件里显式配置了 `font-family = Hack`、`font-family = Noto Sans SC`，但用 CoreText 枚举实际可用字体后，这两个字体在当前系统都不存在，于是嵌入式终端继承了一套无效字体栈，表现成“字体丢失”。
- 设计层诱因：存在。问题不是 `./dev` 脚本本身，而是**DevHaven 内嵌终端的配置真相源错误地依赖了独立 Ghostty App 的全局配置目录**，导致一个外部应用的字体 / 主题 / 键位配置泄漏进 DevHaven。未发现更大的系统设计缺陷，问题集中在 Ghostty runtime 这层边界没有收口到 DevHaven 自己的数据目录。
- 当前修复：
  1. `GhosttyRuntime` 不再调用 `ghostty_config_load_default_files`，改为只读取 `~/.devhaven/ghostty/config` 与 `~/.devhaven/ghostty/config.ghostty`；
  2. 保留 `ghostty_config_load_recursive_files`，让 DevHaven 自己的配置文件仍可通过 `config-file` 继续拆分；
  3. 新增 `GhosttyRuntimeConfigLoaderTests`，锁定“即使存在独立 Ghostty 的全局配置，DevHaven 也不应去读取它”这条回归边界；
  4. `AGENTS.md` / `README.md` 同步补充新的配置入口，避免后续再次把字体问题排到独立 Ghostty 配置上。
- 长期建议：如果后续要把终端字体、主题或键位暴露到设置页，应该继续以 `~/.devhaven/ghostty/config*` 为唯一真相源，并在应用内明确支持哪些选项；不要再让独立 Ghostty App 的全局配置影响 DevHaven。
- 验证证据：
  - 复现前证据：
    - `./dev` 旧日志里出现 `reading configuration file path=/Users/zhaotianzeng/Library/Application Support/com.mitchellh.ghostty/config`；
    - `swift -e 'import Foundation; import CoreText; ...'` 输出 `Hack: false`、`Hack Nerd Font: false`、`Noto Sans SC: false`；
    - `~/Library/Application Support/com.mitchellh.ghostty/config` 里确有 `font-family = Hack`、`font-family = Noto Sans SC`。
  - TDD 红灯：`swift test --package-path macos --filter GhosttyRuntimeConfigLoaderTests/testEmbeddedConfigFileURLsIgnoreStandaloneGhosttyAppSupportConfig` 初次失败，报 `type 'GhosttyRuntime' has no member 'embeddedConfigFileURLs'`。
  - 定向绿灯：同一条测试修复后通过，`1 test, 0 failures`。
  - 行为验证：用 Python 包装 `./dev --logs ghostty` 启动 8 秒后采样，输出 `HAS_STANDALONE_CONFIG_PATH=False`、`HAS_CONFIG_READ_LOG=False`，且日志尾部不再出现 `reading configuration file path=...com.mitchellh.ghostty/config`。
  - 全量验证：`swift test --package-path macos` → 通过，`112 tests, 5 skipped, 0 failures`。
  - 差异校验：`git diff --check` → 通过。

## 调研 Codex 截图粘贴与 Ghostty / Supacode / cmux 图片处理（2026-03-21）

- [x] 快速核对当前 DevHaven 与记忆里的 Ghostty / Supacode / cmux 上下文，避免沿旧栈误判
- [x] 查证 Ghostty 对剪贴板图片、终端图片协议与 paste action 的真实边界
- [x] 查证 Supacode / cmux 在截图输入上的实际实现路径，区分“终端粘贴”与“宿主附件上传”
- [x] 结合运行中的 Codex 形态给出直接原因、设计层诱因、当前建议与长期方案

## Review（调研 Codex 截图粘贴与 Ghostty / Supacode / cmux 图片处理）

- 直接原因：运行中的 Codex 本质上还是跑在 Ghostty/libghostty 承载的终端里，而当前 DevHaven 自己的 `GhosttyRuntime.handleReadClipboard(...)` 只从 `NSPasteboard` 读取 `.string`，没有任何图片 MIME、HTML/RTFD 附件或拖拽图片的宿主级转换逻辑；因此截图在剪贴板里若只有图片数据，终端 paste 回调就只能拿到空字符串。
- 设计层诱因：这不是单纯“Ghostty 少一个开关”，而是“终端文本粘贴”和“AI 客户端图片附件”两种语义被混为一谈。Ghostty / Supacode 的默认边界仍然是“把可表示成文本的东西送进终端”；若产品要支持给 Codex 贴截图，必须由宿主在终端外做图片物化 / 上传 / 路径注入，而不能指望 libghostty 原生帮你把剪贴板图片变成 Codex 可理解的附件。
- 当前结论：
  - Ghostty 原生 macOS：`getOpinionatedStringContents()` 只处理 file URL 和 string；拖拽也只注册 `.string/.fileURL/.URL`，不处理图片剪贴板。
  - Supacode：沿用同样的 Ghostty 语义；终端 paste 和 drop 都是 string/file URL 路径，不做截图图片粘贴增强。
  - cmux：额外实现了终端图片粘贴增强。它会识别剪贴板里的纯图片或仅图片附件的 HTML/RTFD，把图片落到临时 `clipboard-*` 文件，再根据目标终端是本地还是远端，分别“直接把本地路径插入终端”或“先上传再把远端路径插入终端”；拖拽图片也是同一套思路。
  - DevHaven 当前状态比 Ghostty / Supacode 还更窄：目前只读 `.string`，连 file URL / HTML 富文本兜底都还没接入，所以“无法粘贴截图”在现状下是符合代码现状的，不是偶发异常。
- 长期建议：
  - 如果目标是“终端里的 Codex 能像附件一样接收截图”，优先按 cmux 方案做宿主增强：图片剪贴板 -> 临时文件 -> 本地路径注入 / 远端上传后注入远端路径。
  - 如果后续还要支持浏览器 pane / WebView 里的真正二进制图片复制粘贴，可以另走 cmux `CmuxWebView` 那条 browser pasteboard 路线；不要试图把“浏览器图片附件语义”和“终端文本 paste 语义”强行塞进同一层 Ghostty callback。
- 验证证据：
  - DevHaven：`macos/Sources/DevHavenApp/Ghostty/GhosttyRuntime.swift:260-312`
  - Ghostty：`ghostty/macos/Sources/Helpers/Extensions/NSPasteboard+Extension.swift:35-48`、`ghostty/macos/Sources/Ghostty/Ghostty.App.swift:325-338`、`ghostty/macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift:2091-2128`、`ghostty/src/apprt/gtk/class/surface.zig:3764-3771`
  - Supacode：`supacode/Infrastructure/Ghostty/GhosttyRuntime.swift:388-423,616-625`、`supacode/Infrastructure/Ghostty/GhosttySurfaceView.swift:126-129,1355-1378`
  - cmux：`cmux/Sources/GhosttyTerminalView.swift:73-367,1085-1168,3878-3887,6284-6362`、`cmux/Sources/TerminalImageTransfer.swift:112-160`、`cmux/cmuxTests/TerminalAndGhosttyTests.swift:38-58,196-253`、`cmux/CHANGELOG.md:63`

## 修复 workspace 分屏时旧 pane 偶发不显示（2026-03-21）

- [x] 先确认当前仓库已有未提交改动的隔离边界，避免混入 worktree 删除任务
- [x] 复盘 split/tree/surface 可见性链路，定位旧 pane 偶发不显示的直接原因
- [x] 先补失败测试锁定“分屏后旧 pane 仍应保持挂载与可见”预期
- [x] 以最小改动修复根因，并运行定向与全量验证
- [x] 在 `tasks/todo.md` 追加 Review，写明原因、修复、验证证据与长期建议

## Review（修复 workspace 分屏时旧 pane 偶发不显示）

- 直接原因：上一轮 `WorkspaceSplitTreeView` 已经去掉 structural re-key，避免 split/tree 重排时整棵 subtree 被强制 remount；但当前 `GhosttySurfaceHostModel` 复用的只有 `GhosttyTerminalSurfaceView` 本体。旧 pane 在 split/tree 发生挂载迁移时，surface 会继续被复用，但 `GhosttyTerminalSurfaceView` 内部缓存的 `lastOcclusion`、`lastSurfaceFocus`、`lastBackingSize` 仍保留旧容器状态，导致重新挂到新容器后不会重发 occlusion / focus / resize，同一个 pane 就可能出现“树里还在，但画面没重新出来”的偶发空白。
- 设计层诱因：存在。这不是 split 拓扑再次算错，而是 **surface 复用边界只收口到了“不要销毁 terminal view”，却没有把“容器迁移后必须刷新挂载敏感状态”一起收口**。也就是说，生命周期主线已经保护了 `/usr/bin/login` 不重跑，但 AppKit/Ghostty 这层 attachment-sensitive state 仍然分散在 `GhosttySurfaceView` 内部缓存里。未发现更大的系统设计缺陷，问题集中在这条复用边界还差最后一步。
- 当前修复：
  1. 新增 `GhosttySurfaceAttachmentState.swift`，把 `lastOcclusion`、`lastSurfaceFocus`、`lastBackingSize` 收口成显式状态对象，并提供 `prepareForContainerReuse()`。
  2. `GhosttyTerminalSurfaceView` 在 `tearDown()` 和新的 `prepareForContainerReuse()` 中都会清空这三类挂载敏感缓存；`setOcclusion` / `setSurfaceFocus` / `updateSurfaceMetrics` 改为统一读写该状态。
  3. `GhosttySurfaceHostModel.acquireSurfaceView(...)` 在复用既有 `ownedSurfaceView` 前，先调用 `prepareForContainerReuse()`，再重放缓存的可见性 / 焦点 / 尺寸同步，确保 split/tree remount 后旧 pane 能重新收到一次有效 attach 信号。
  4. 新增 `GhosttySurfaceScrollViewTests.testAttachmentStateResetForContainerReuseClearsVisibilityFocusAndResizeCaches`，用 RED -> GREEN 锁住“容器复用前必须清空 attachment-sensitive caches”这条回归边界。
- 长期建议：后续凡是继续优化 split/tree/zoom/tab 切换时的 Ghostty 复用，都要把问题拆成两层分别看：一层是 `WorkspaceTerminalSessionStore` 是否还在错误释放 surface；另一层是 **即便 surface 没被释放，容器迁移后是否有 attachment refresh**。不要只看“有没有重新 `/usr/bin/login`”，因为“surface 存活但缓存未刷新”同样会表现成 pane 黑掉或空白。
- 验证证据：
  - TDD 红灯：`swift test --package-path macos --filter GhosttySurfaceScrollViewTests` 初次失败，报 `cannot find 'GhosttySurfaceAttachmentState' in scope`，证明新测试先锁住了待实现边界。
  - 定向验证：`swift test --package-path macos --filter 'WorkspaceTopologyTests|GhosttyWorkspaceControllerTests|WorkspaceTerminalSessionStoreTests|WorkspaceSplitTreeViewKeyPolicyTests|WorkspaceSurfaceActivityPolicyTests|GhosttySurfaceScrollViewTests'` → 通过，24 tests, 0 failures。
  - 全量验证：`swift test --package-path macos` → 通过，`111 tests, 5 skipped, 0 failures`。
  - 构建验证：`swift build --package-path macos` → 通过。
  - 差异校验：`git diff --check` → 通过。
  - 当前边界：本轮已经补齐了代码级 root-cause 与自动化回归，但还没有新的实机 GUI 录屏/截图证据；是否完全消除你看到的“旧 pane 不显示”，仍建议你本机再分两三次屏确认一下。

## 修复删除 dirty worktree 时被 Git 拒绝（2026-03-21）

- [x] 复现并确认 `git worktree remove` 在 modified / untracked 场景下的失败行为
- [x] 先补失败测试，锁定删除 dirty worktree 的预期
- [x] 以最小改动修复删除逻辑与必要文案
- [x] 运行定向与全量验证，并追加 Review

## Review（修复删除 dirty worktree 时被 Git 拒绝）

- 直接原因：`NativeGitWorktreeService.removeWorktree(...)` 之前直接执行 `git worktree remove <path>`。Git 在 worktree 内存在 modified / untracked 文件时会按默认安全策略拒绝删除，并返回 `fatal: '.../swift' contains modified or untracked files, use --force to delete it`，所以 DevHaven 的“删除 worktree”会直接失败。
- 设计层诱因：产品语义和底层 Git 语义没有收口。UI 已经把这个入口定义成显式 destructive delete，但服务层仍保留 Git 的“仅允许删除干净 worktree”默认策略，同时确认文案也没有提前说明会如何处理未提交改动。这是一个局部边界不一致；未发现更大的系统设计缺陷。
- 当前修复：
  - `NativeGitWorktreeService` 删除 worktree 时改为执行 `git worktree remove --force <path>`，让显式删除动作可以按预期回收 dirty worktree；
  - 保留原有 `worktree prune` fallback 和“删除对应本地分支”的后续处理；
  - `WorkspaceShellView` 的确认文案同步补充“会丢弃未提交修改与未跟踪文件”，把 destructive 语义显式告诉用户。
- 长期建议：如果后续想给用户保留更多控制权，下一步应考虑把删除分成“取消 / 强制删除”两条显式路径，或在确认弹窗里先展示 dirty-state 预检结果；但当前这类单按钮 destructive flow 不应再把裸 Git fatal 暴露给用户。
- 验证证据：
  - 复现脚本：临时仓库里执行 `git worktree remove "$wt"`，在 worktree 含修改和未跟踪文件时稳定复现 `EXIT_CODE=128` 与 `contains modified or untracked files, use --force to delete it`。
  - TDD 红灯：`swift test --package-path macos --filter NativeWorktreeServiceTests/testRemoveWorktreeForceDeletesDirtyManagedWorktree` → 修复前失败，报 `contains modified or untracked files, use --force to delete it`。
  - 定向绿灯：`swift test --package-path macos --filter NativeWorktreeServiceTests/testRemoveWorktreeForceDeletesDirtyManagedWorktree` → 通过，`1 test, 0 failures`。
  - 全量验证：`swift test --package-path macos` → 通过，`110 tests, 5 skipped, 0 failures`。
  - 差异校验：`git diff --check` → 通过。

## DevHaven 3.0.0 仓库收口为纯 macOS 原生主线（2026-03-20）

- [x] 保护当前工作区并核对 merge 前状态
- [x] 将 `swift` 合并到 `main`
- [x] 切换版本真相源到 `macos/Resources/AppMetadata.json`
- [x] 下线 Tauri / Node / pnpm 发布链路
- [x] 删除旧的 React / Vite / Tauri / Rust 兼容源码与构建配置
- [x] 清理历史实施文档与旧版本 release note
- [x] 同步更新 `README.md`、`AGENTS.md`、原生设置文案与 release note
- [x] 运行原生测试与原生打包验证

## Review（DevHaven 3.0.0 纯 macOS 原生主线收口）

- 合并结果：已在 `main` 上完成 `swift` 分支合并，merge commit 为 `5e50a98`（`Merge branch 'swift'`）。
- 仓库结构结果：旧的 `src/`、`src-tauri/`、`scripts/`、`public/` 以及 `package.json` / `pnpm-lock.yaml` / `vite.config.ts` 等旧构建配置已从仓库删除；当前源码仅保留 `macos/` 原生主线。
- 版本结果：版本真相源已切换到 `macos/Resources/AppMetadata.json`，当前版本为 `3.0.0`。
- 发布结果：`.github/workflows/release.yml` 已收口为纯 Swift/macOS 原生链路，只保留 `swift test --package-path macos`、原生 `.app` 构建、压缩与 release asset 上传。
- 文档结果：`README.md`、`AGENTS.md`、`docs/releases/v3.0.0.md` 已更新为原生主线口径；旧的 `docs/plans/`、旧版 release note、`work.md`、`PLAN.md` 已删除。
- 设计层判断：本轮真正的系统性问题是“发布链、仓库结构、版本真相源、历史文档四套边界长期不一致”。现在已经把源码、打包、版本和文档统一收口到 `macos/` 原生主线。
- 验证证据：
  - `swift test --package-path macos` → 通过，`105 tests, 5 skipped, 0 failures`。
  - `bash macos/scripts/setup-ghostty-framework.sh --source /Users/zhaotianzeng/Documents/business/tianzeng/ghostty --skip-build` → 通过，仅用于本机准备 `macos/Vendor/**`。
  - `bash macos/scripts/build-native-app.sh --release --no-open --output-dir /tmp/devhaven-native-app-verify-pure` → 通过，产物为 `/tmp/devhaven-native-app-verify-pure/DevHaven.app`。
  - `git diff --check` → 通过。

## 修复 GitHub Release 缺少 Ghostty vendor 导致的 `swift test` 失败（2026-03-20）

- [x] 复现干净 checkout 下的 `GhosttyKit` binary target 报错
- [x] 收口 CI bootstrap 方案并更新 workflow / 文档
- [x] 重新验证“干净 checkout + 准备 vendor + swift test / 原生打包”链路

## Review（GitHub Release Ghostty vendor bootstrap）

- 直接原因：`macos/Package.swift` 通过本地 `binaryTarget(path: "Vendor/GhosttyKit.xcframework")` 依赖 GhosttyKit，但 `macos/Vendor/` 被 `.gitignore` 忽略，GitHub Actions 的干净 checkout 在 `swift test --package-path macos` 前没有有效的二进制产物，因此直接报错 `does not contain a binary artifact`。
- 设计层诱因：发布 workflow 虽然已经切到纯 Swift/macOS，但仍把“本机已准备好 Ghostty vendor”当成默认前提；也就是说，Swift Package 的 binary target 真相源和 CI 的准备链路是脱节的。
- 当前修复：`.github/workflows/release.yml` 现在会先安装 Zig，再 `git fetch` 固定 commit `da10707f93104c5466cd4e64b80ff48f789238a0` 的 Ghostty 源码，执行 `bash macos/scripts/setup-ghostty-framework.sh --source "$RUNNER_TEMP/ghostty"` 准备临时 `macos/Vendor/`，然后再运行 `swift test` 和原生打包；`README.md`、`AGENTS.md`、`tasks/lessons.md` 已同步更新说明。
- 长期建议：后续如果继续升级 Ghostty 版本，必须把“上游 commit pin + CI bootstrap + 本地开发说明”视为同一组变更一起维护，避免再次出现“本机能过、干净 checkout 直接炸”的问题。
- 验证证据：
  - 干净 worktree 直接执行 `swift test --package-path macos` → 复现失败：`local binary target 'GhosttyKit' ... does not contain a binary artifact`。
  - `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release.yml")'` → 通过，确认 workflow YAML 合法。
  - 在干净 worktree 内按 workflow 新链路执行：
    - `git init "$RUNNER_TEMP/ghostty" && git -C "$RUNNER_TEMP/ghostty" fetch --depth 1 origin da10707f93104c5466cd4e64b80ff48f789238a0 && git -C "$RUNNER_TEMP/ghostty" checkout --detach FETCH_HEAD`
    - `bash macos/scripts/setup-ghostty-framework.sh --source "$RUNNER_TEMP/ghostty"`
    - `swift test --package-path macos`
    - `bash macos/scripts/build-native-app.sh --release --no-open --output-dir "$RUNNER_TEMP/native-app"`
  - 上述整条链路 → 通过，`105 tests, 5 skipped, 0 failures`，并产出 `/tmp/devhaven-workflow-verify-git-36433/.runner-temp/native-app/DevHaven.app`。
  - `git diff --check` → 通过。

## 修复 GitHub Actions 上 Ghostty 在 Xcode 16.4 编译失败（2026-03-20）

- [x] 拉取最新失败 run 并定位实际失败 step
- [x] 确认 root cause 为 runner Xcode 版本落后而非 vendor bootstrap 逻辑错误
- [x] 将 release workflow 切到 `macos-26` 并增加 Xcode 版本诊断输出
- [x] commit / push 并重打 `v3.0.0` 触发新的 release run
- [x] 检查新 run 是否成功起跑

## Review（GitHub Actions Xcode toolchain 对齐）

- 直接原因：最新失败 run `23343818716` 虽然已经成功完成 Ghostty 源码 checkout，但在 `Bootstrap Ghostty vendor` 阶段执行 `cd /Users/runner/work/_temp/ghostty/macos && xcodebuild -target Ghostty -configuration ReleaseLocal` 时退出 `code 65`，日志明确显示使用的是 `/Applications/Xcode_16.4.app/...`。
- 设计层诱因：上一轮只把“CI 缺失 Ghostty vendor bootstrap”补齐了，但没有把 GitHub runner 的 Xcode 主版本与当前 Ghostty 上游的构建要求一起锁定；结果变成“vendor 链路对了，工具链版本又漂移了”。
- 当前修复：`.github/workflows/release.yml` 已把 release runner 从 `macos-latest` 改成 `macos-26`，并新增 `Print Xcode version` 步骤输出 `xcodebuild -version`，用于让日志直接暴露实际工具链版本。
- 长期建议：后续只要升级 Ghostty commit 或切换 GitHub runner 标签，都要把“上游 commit pin / runner OS / Xcode 主版本 / 本地验证环境”作为同一组约束维护，而不是只盯单个脚本。
- 新进展（2026-03-20）：
  - `git push origin main` → 已成功把修复提交 `dd46da5` 推到远端。
  - `git tag -fa v3.0.0 -m "v3.0.0"` + `git push origin refs/tags/v3.0.0 --force` → 已成功把 `v3.0.0` 重指到 `dd46da5` 并推送远端。
  - `gh run list --workflow release.yml --limit 5 ...` → 新 run `23346369319` 已于 `2026-03-20T14:03:39Z` 起跑，当前 URL：`https://github.com/zxcvbnmzsedr/devhaven/actions/runs/23346369319`。

## 修复 GitHub workflow 产物启动即崩（2026-03-20）

- [x] 对照 crash log 与 Supacode 打包方式定位资源加载断裂点
- [x] 调整 `GhosttyAppRuntime` 的资源 bundle 定位逻辑并补回归测试
- [x] 验证原生测试、`.app` 布局、原生打包与启动 smoke test

## Review（GitHub workflow 产物启动即崩）

- 直接原因：GitHub workflow 产出的 `.app` 在启动时崩在 `static NSBundle.module` 初始化，说明运行时没有按 SwiftPM 期望的方式找到 `DevHavenNative_DevHavenApp.bundle`。`build-native-app.sh` 会把该 bundle 复制到 `DevHaven.app/Contents/Resources/`，但旧版 `GhosttyAppRuntime` 仍直接依赖 `Bundle.module`，导致打包后的应用在初始化 `GhosttyResources/ghostty` 时触发断言并直接崩溃。
- 设计层诱因：当前 release 仍是“SwiftPM executable + 手工组装 `.app`”模式，资源拷贝路径由打包脚本掌控，而运行时资源定位却交给 `Bundle.module` 的默认实现；也就是**打包布局真相源**和**运行时资源查找真相源**分裂了。未发现更大的系统设计缺陷，问题集中在这一处边界没有显式收口。
- 当前修复：
  - `GhosttyAppRuntime` 新增显式资源 bundle 定位逻辑，优先解析 `Bundle.main.resourceURL/DevHavenNative_DevHavenApp.bundle`，并兼容测试环境下的 sibling bundle fallback；
  - 新增 `GhosttyAppRuntimeBundleLocatorTests`，锁定“打包产物优先从 `Contents/Resources` 取 bundle”和“测试环境可从同级目录 fallback”两条路径；
  - 新增 `macos/scripts/test-native-app-layout.sh`，持续检查 `.app` 中资源 bundle 的实际落点；
  - 保持资源 bundle 放在 `Contents/Resources/`，不再尝试复制到 `.app` 根目录，避免 `codesign --verify --deep --strict` 报 `unsealed contents present in the bundle root`。
- Supacode 对照：Supacode 走 `xcodebuild archive/exportArchive`，资源通过 Xcode `PBXResourcesBuildPhase` 进入 `Contents/Resources/`，运行时直接按 `Bundle.main.resourceURL/...` 读取 `ghostty` / `terminfo` / `git-wt`。这次修复本质上是把 DevHaven 的运行时资源解析边界也收口到同样稳定的 app resources 语义上，而不是继续赌 `Bundle.module` 在手工组装 `.app` 时能自动对齐。
- 长期建议：如果后续继续沿用 SwiftPM executable + 手工 `.app` 组装路线，凡是要在发布版读取的资源，都应像这次一样显式绑定到最终 app 布局；不要让“构建时生成 bundle”和“运行时查找 bundle”分属两套默认约定。
- 验证证据：
  - `swift test --package-path macos` → 通过，`107 tests, 5 skipped, 0 failures`。
  - `bash macos/scripts/test-native-app-layout.sh` → 通过，确认资源 bundle 位于 `DevHaven.app/Contents/Resources/DevHavenNative_DevHavenApp.bundle`，且 app 根目录不存在非法副本。
  - `bash macos/scripts/build-native-app.sh --release --no-open --output-dir /tmp/devhaven-native-app-verify-launch-fix` → 通过，产物为 `/tmp/devhaven-native-app-verify-launch-fix/DevHaven.app`，脚本内 `codesign --verify --deep --strict` 通过。
  - 启动 smoke test：直接执行 `/tmp/devhaven-native-app-verify-launch-fix/DevHaven.app/Contents/MacOS/DevHavenApp`，5 秒后进程仍存活，输出 `STATUS=running_after_5s`，未再出现启动即崩。
- 额外核对：Supacode 安装产物 `/Applications/supacode.app/Contents/Resources/` 下确实存在 `ghostty`、`terminfo`、`git-wt`，与本次对照结论一致。

## 扩展 GitHub release 为 arm64 + x86_64 双产物（2026-03-21）

- [x] 确认当前单产物 release 只会跟随 runner 架构输出 arm64
- [x] 设计 dual-arch release 方案并记录到 `docs/plans/2026-03-21-devhaven-release-dual-arch.md`
- [x] 修改 `.github/workflows/release.yml` 为 arm64 / x86_64 matrix
- [x] 同步更新 `AGENTS.md` 的发布主链说明
- [x] 校验 workflow YAML 与本地 x86_64 构建验证

## Review（GitHub release dual-arch）

- 直接原因：当前 `.github/workflows/release.yml` 只有单个 `build-macos-native` job，且固定 `runs-on: macos-26`；`build-native-app.sh` 又直接调用不带 `--triple` 的 `swift build`，所以 release 产物天然跟随 runner 架构，只会产出 `arm64` 包。
- 设计层诱因：发布链原先把“目标架构”隐式绑定在 runner 上，但 release asset 名称却没有编码架构信息。这种做法在单 runner 时代问题不明显，一旦扩成多架构发布，构建真相源和发布资产命名就会发生冲突。
- 当前修复：
  - `.github/workflows/release.yml` 现在改为 matrix，同时跑 `arm64/macos-26` 与 `x86_64/macos-15-intel`；
  - 保持 `setup-ghostty-framework.sh`、`swift test --package-path macos`、`build-native-app.sh` 主链不变，不在本轮给脚本再加一套额外架构分支；
  - release asset 名称改成 `DevHaven-macos-arm64.zip` 和 `DevHaven-macos-x86_64.zip`，避免两个 job 互相覆盖。
- 长期建议：后续如果要继续做 universal 包，再单独评估“matrix 双包”与“lipo 合包”谁是正式发行策略；在这之前，不要把 runner 架构、target triple 和 release asset 命名继续混在一起。
- 验证证据：
  - `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release.yml"); puts "yaml ok"'` → 通过，输出 `yaml ok`。
  - `swift build --package-path macos -c release --triple x86_64-apple-macosx14.0` → 通过。
  - `file /Users/zhaotianzeng/WebstormProjects/DevHaven/macos/.build/x86_64-apple-macosx/release/DevHavenApp` → 输出 `Mach-O 64-bit executable x86_64`。
  - `git diff --check` → 通过。

## 修复 dual-arch release 中 Intel hosted runner 编译失败（2026-03-21）

- [x] 拉取失败 run `23365597633` 的 x86_64 job 日志并确认失败步骤
- [x] 对照 arm64 成功链与 Ghostty 上游要求定位根因
- [x] 改为 `macos-26` 上交叉构建 x86_64，并重新验证 workflow / 本地打包

## Review（Intel hosted runner 编译失败）

- 直接原因：失败 run `23365597633` 里的 `build-macos-native (x86_64, macos-15-intel)` 在 `Bootstrap Ghostty vendor` 阶段失败；日志显示该 job 使用的是 `Xcode 16.4 (Build version 16F6)`，并在 `cd /Users/runner/work/_temp/ghostty/macos && xcodebuild -target Ghostty -configuration ReleaseLocal` 时以 `code 65` 退出。arm64 job 同一时间跑在 `macos-26` 上则成功，说明失败点不在 DevHaven 自己的 Swift 包，而在 Ghostty 上游 bootstrap 所依赖的 Intel runner 工具链。
- 设计层诱因：上一轮把“目标 CPU 架构”直接等同于“必须使用同构 GitHub runner”。这对纯 Swift 可执行文件未必是必须的，但对 Ghostty 这种先用较新 Xcode 构建 vendor、再由下游应用复用产物的链路，会把“目标架构”和“可用工具链版本”错误耦合在一起。
- 当前修复：
  - release workflow 仍保留 `arm64` / `x86_64` 双产物，但二者都改在 `macos-26` 上跑；
  - `x86_64` 产物不再依赖 `macos-15-intel`，而是通过 `x86_64-apple-macosx14.0` triple 在 `macos-26` 上交叉构建；
  - `build-native-app.sh` 新增可选 `--triple` / `DEVHAVEN_NATIVE_TRIPLE`，用于让 workflow 在不分叉主脚本的前提下产出 x86_64 `.app`；
  - `x86_64` 这条 CI 验证改为“编译+打包验证”，不再尝试在 arm runner 上执行 x86_64 test bundle。
- 长期建议：只要上游 vendor bootstrap 对 Xcode 主版本敏感，就不要再把“构建 x86_64 目标”简单理解成“必须用 Intel hosted runner”。先看可用工具链，再决定是同构 runner、交叉编译，还是自托管机器。
- 验证证据：
  - `gh run view 23365597633 --job 67978750279 --log` → 确认失败 job 为 `build-macos-native (x86_64, macos-15-intel)`，失败步骤是 `Bootstrap Ghostty vendor`。
  - 同日志中的 `Print Xcode version` → 明确显示 `Xcode 16.4 / Build version 16F6`。
  - `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release.yml"); puts "yaml ok"'` → 通过，输出 `yaml ok`。
  - `swift test --package-path macos` → 通过，`107 tests, 5 skipped, 0 failures`。
  - `bash macos/scripts/build-native-app.sh --release --no-open --triple x86_64-apple-macosx14.0 --output-dir /tmp/devhaven-native-app-x86-cross-verify` → 通过。
  - `file /tmp/devhaven-native-app-x86-cross-verify/DevHaven.app/Contents/MacOS/DevHavenApp` → 输出 `Mach-O 64-bit executable x86_64`。

## 滚动优化：对齐 Ghostty 原生 / Supacode 滚动语义（2026-03-21）

- [x] 检查当前 Ghostty 宿主的滚动事件链与速度来源
- [x] 对照 Ghostty 原生与 Supacode 的滚动包装/节流策略
- [x] 确认最小修复方案并完成验证

## Review（Ghostty scroll 输入桥对齐）

- 直接原因：`GhosttySurfaceView.scrollWheel(with:)` 直接把 `scrollingDeltaX/Y` 原样传给 `ghostty_surface_mouse_scroll(...)`，并把键盘 modifiers 误当成 `ghostty_input_scroll_mods_t` 传入，导致 trackpad 这类高精度滚动事件没有被正确标记为 `precision + momentum`；Ghostty core 因此会把本应走 precision 路径的输入按 discrete scroll 解释，体感表现为“滚得特别快”。
- 设计层诱因：问题不在 `GhosttySurfaceScrollView` wrapper 主线，而在输入桥接边界把“键盘/鼠标修饰键 mods”和“滚动专用 scroll mods”混成了一种 bitfield。未发现更大的系统设计缺陷，当前是局部输入语义接线偏离 Ghostty / Supacode 参考实现。
- 当前修复：
  - 新增 `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceScrollInput.swift`，把 precise scroll 的 delta 调整与 `precision + momentumPhase` 编码收口成可测试 helper；
  - `GhosttySurfaceView.scrollWheel(with:)` 改为使用该 helper，precise scrolling 对齐 Ghostty 原生 / Supacode 的 `x2` delta 规则，并正确传入 `ghostty_input_scroll_mods_t`；
  - 移除原先会误导实现的 `ghosttyScrollMods` 旧接线。
- 长期建议：后续所有 Ghostty 输入问题优先做 source-to-source diff，对照 Ghostty 原生和 Supacode 的桥接细节；不要先在 `GhosttySurfaceScrollView` 或 SwiftUI 外层做人为减速补丁，否则容易掩盖真正的输入语义错误。
- 验证证据：
  - TDD 红灯：`swift test --package-path macos --filter GhosttySurfaceScrollInputTests` → 先失败，报 `cannot find 'GhosttySurfaceScrollInput' in scope`，证明新增测试确实锁住了待实现行为；
  - 定向绿灯：`swift test --package-path macos --filter GhosttySurfaceScrollInputTests` → 通过，2 tests, 0 failures；
  - 全量验证：`swift test --package-path macos` → 通过，`109 tests, 5 skipped, 0 failures`；
  - 代码格式校验：`git diff --check` → 通过。
- 当前边界：本轮已经完成代码级 root-cause 修复并通过自动化验证，但还没有新的 GUI 肉眼滚动手感证据；最终体感是否已与 Ghostty / Supacode 对齐，仍建议你本机再滚一轮确认。

## 新增根目录 `./dev` 原生开发命令（2026-03-21）

- [x] 记录设计与实现计划，明确单命令入口的职责边界
- [x] 先写失败用例，锁定 `./dev` 的帮助、dry-run 与日志包装行为
- [x] 实现根目录 `./dev` 脚本并补 README / AGENTS 说明
- [x] 运行脚本级验证与代码差异校验

## Review（根目录 `./dev` 原生开发命令）

- 直接原因：当前仓库虽然已经有 `swift run --package-path macos DevHavenApp` 这条原生启动链路，但关键诊断日志走的是 macOS unified log；直接运行 `swift run` 时，用户很难像 `pnpm dev` 那样在同一开发入口里同时看到日志和应用启动过程。
- 设计层诱因：开发态入口被拆成了“手动运行应用”和“另开终端执行 `log stream`”两步，应用启动真相源与日志观测真相源分裂。未发现更大的系统设计缺陷，问题集中在本地开发体验缺少统一入口。
- 当前修复：
  - 新增根目录 `./dev`，默认先执行 `bash macos/scripts/setup-ghostty-framework.sh --verify-only`；
  - 默认以 unified log 观察 `DevHavenNative` 与 `com.mitchellh.ghostty`；
  - 前台执行 `swift run --package-path macos DevHavenApp`，并通过 `trap` 回收后台日志进程；
  - 新增 `--dry-run`、`--no-log`、`--logs all|app|ghostty`，保证脚本具备最小可测试/可排障能力；
  - `README.md`、`AGENTS.md`、`tasks/lessons.md` 已同步更新。
- 长期建议：后续如果再增加新的原生诊断 subsystem、环境变量或调试开关，优先继续收口到 `./dev`，不要重新散落成多套“启动命令 + 文档说明 + 临时 shell alias”。
- 验证证据：
  - TDD 红灯：`bash macos/scripts/test-dev-command.sh` → 初次失败，报 `/Users/zhaotianzeng/WebstormProjects/DevHaven/dev: No such file or directory`，证明新测试确实先锁住了缺失的入口。
  - 定向绿灯：`bash macos/scripts/test-dev-command.sh` → 通过，输出 `dev command smoke ok`。
  - 帮助输出：`./dev --help` → 通过，已展示 `--dry-run`、`--no-log`、`--logs all|app|ghostty`。
  - dry-run：`./dev --dry-run` → 通过，已打印 vendor 校验、`log stream` 与 `swift run --package-path macos DevHavenApp` 三条命令。
  - 依赖前置：`bash macos/scripts/setup-ghostty-framework.sh --verify-only` → 通过，确认当前 `macos/Vendor` 完整。
  - 代码差异：`git diff --check` → 通过。
- 当前边界：本轮验证已覆盖脚本外部行为、参数分支与 vendor 前置条件，但没有在自动化会话里实际长时间运行 `./dev` 打开 GUI 应用并观察你桌面上的最终体感；如果你要确认真实开发体验，建议本机手动跑一遍 `./dev`。

## 排查 Ghostty 配置不再加载（2026-03-21）

- [x] 先确认当前 Ghostty 配置加载真相源、最近相关改动与用户现象是否一致
- [x] 定位直接原因与是否存在设计层诱因
- [x] 在最小改动下恢复预期配置加载行为，并补充回归验证
- [x] 更新 `tasks/todo.md` Review，必要时同步文档/测试

## Review（排查 Ghostty 配置不再加载）

- 直接原因：`GhosttyRuntime` 这轮未提交改动把配置加载从 `ghostty_config_load_default_files(config)` 改成了“只读取 `~/.devhaven/ghostty/config*`”。而当前机器上这两个 DevHaven 专属配置文件都不存在，实际只有 `~/Library/Application Support/com.mitchellh.ghostty/config`，因此启动后不再加载你原本就在 Ghostty 里使用的主题 / 键位 / 字体配置。
- 设计层诱因：存在。我们之前为了隔离 DevHaven 和独立 Ghostty App 的字体配置，把“配置真相源”从共享的 Ghostty 默认搜索路径收口到了 DevHaven 私有目录，但**没有提供迁移、显式开关或 fallback**，于是已有用户会在升级后直接感知成“配置突然失效”。问题集中在配置边界切换过猛；未发现更大的系统设计缺陷。
- 当前修复：
  1. `GhosttyRuntime` 新增 `preferredConfigFileURLs(...)`，配置加载改为“优先 `~/.devhaven/ghostty/config*`，若不存在则回退到 `~/Library/Application Support/com.mitchellh.ghostty/config*`”；
  2. 保留 `ghostty_config_load_recursive_files(config)`，因此无论是 DevHaven 专属配置还是原有 Ghostty 配置，`config-file` 拆分能力都还在；
  3. `GhosttyRuntimeConfigLoaderTests` 改成两条回归边界：`没有 DevHaven 专属配置时会回退到独立 Ghostty 配置`、`存在 DevHaven 专属配置时优先使用它`；
  4. `README.md` 与 `AGENTS.md` 同步把配置优先级说明改成“DevHaven 专属优先，缺省回退到现有 Ghostty 配置”。
- 长期建议：如果后续还想把 DevHaven 和独立 Ghostty App 完全隔离，不要再用“静默切断旧配置路径”的方式推进；至少提供一次性迁移、显式开关，或在首次启动时提示“当前正在沿用旧 Ghostty 配置，创建 `~/.devhaven/ghostty/config` 后即可覆盖”。
- 验证证据：
  - 本机现状：`~/.devhaven/ghostty/config` 与 `~/.devhaven/ghostty/config.ghostty` 均不存在；`~/Library/Application Support/com.mitchellh.ghostty/config` 存在，且含 `theme = iTerm2 Solarized Dark`、`font-family = Hack`、`font-family = Noto Sans SC` 等用户配置。
  - TDD 红灯：`swift test --package-path macos --filter GhosttyRuntimeConfigLoaderTests/testPreferredConfigFileURLsFallbackToStandaloneGhosttyConfigWhenDevHavenConfigMissing` 初次失败，报 `type 'GhosttyRuntime' has no member 'preferredConfigFileURLs'`。
  - 定向绿灯：`swift test --package-path macos --filter GhosttyRuntimeConfigLoaderTests` → 通过，`2 tests, 0 failures`。
  - 全量验证：`swift test --package-path macos` → 通过，`115 tests, 5 skipped, 0 failures`。
  - 差异校验：`git diff --check` → 通过。

## 整理当前工作区并执行 git commit（2026-03-21）

- [x] 核对当前分支、已修改文件与未跟踪文件，确认本次提交范围
- [x] 运行 fresh 验证，确保当前工作区具备提交证据
- [x] 整理提交内容并执行本地 `git commit`

## Review（整理当前工作区并执行 git commit）

- 提交范围：当前工作区包含同一批次的原生 Ghostty runtime / pasteboard / split surface 复用修复、根目录 `./release` 入口、相关测试、README / `AGENTS.md` / `tasks/*` 文档同步，以及对应实施计划文档；本轮按当前工作区真实状态统一提交。
- 验证证据：
  - `swift test --package-path macos` → 通过，`120 tests, 5 skipped, 0 failures`。
  - `bash macos/scripts/test-release-command.sh` → 通过，输出 `release command smoke ok`。
  - `bash macos/scripts/build-native-app.sh --help` → 通过，帮助文案正常打印。
  - `git diff --check` → 通过。
- 交付结果：已完成本地 `git commit`；具体 commit hash 以本轮命令输出和最终 `git log -1 --oneline` 为准。
