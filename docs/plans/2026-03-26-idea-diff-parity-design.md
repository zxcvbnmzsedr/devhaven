# IDEA Diff 逻辑复刻设计

## 1. 背景

当前 DevHaven 的 runtime diff tab 已经具备 compare / merge / patch 三类基础能力，也已经补过 block、overview gutter、inline highlight、side rail 与可编辑 compare / merge，但和 IntelliJ IDEA 的 diff 逻辑相比，仍然存在三类根本差距：

1. 顶部缺少真正的 `Previous Difference / Next Difference` 导航链路，当前仍以单文件视角和局部 block 交互为主；
2. 左右 pane 顶部信息仍以 `title + path` 为主，缺少 revision/hash/author/time/rename 等结构化标题元数据；
3. compare / merge / patch 虽然已经能显示和编辑，但还没有形成一套统一的 viewer framework，`current difference`、request chain、pane metadata 与 editor 内动作分布仍未收敛成单一真相源。

用户明确要求本轮按**强复刻版**推进：

- 范围同时覆盖 **working tree / commit diff** 与 **git log 历史 diff**；
- 优先做 working tree / commit diff，再补 git log 历史 diff；
- 顶部导航条采用完整链式版，对齐 IntelliJ 的 `previous / next difference` 心智，支持当前文件到头后继续切换到下一文件；
- 左右 pane 顶部信息按重度版对齐，需要统一 metadata provider，承载可复制 revision/hash、作者/时间、rename 等详情；
- compare / merge 编辑区按强复刻版推进，尽量补齐编辑器内块级动作、selected changes 语义、冲突间导航与更接近 IDEA 的动作分布。

## 2. 参考实现

本轮设计主要对照以下链路：

### DevHaven 当前实现

- `macos/Sources/DevHavenApp/WorkspaceDiffTabView.swift`
- `macos/Sources/DevHavenApp/WorkspaceTextEditorView.swift`
- `macos/Sources/DevHavenCore/Models/WorkspaceDiffModels.swift`
- `macos/Sources/DevHavenCore/ViewModels/WorkspaceDiffTabViewModel.swift`
- `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`

### IntelliJ 参考主链

- `platform/diff-impl/src/com/intellij/diff/tools/util/side/TwosideTextDiffViewer.java`
- `platform/diff-impl/src/com/intellij/diff/tools/simple/SimpleDiffViewer.java`
- `platform/diff-impl/src/com/intellij/diff/impl/DiffRequestProcessor.java`
- `platform/diff-impl/src/com/intellij/diff/impl/DiffEditorTitleDetails.kt`
- `platform/vcs-impl/src/com/intellij/openapi/diff/impl/DiffTitleWithDetailsCustomizers.kt`
- `platform/vcs-impl/src/com/intellij/openapi/diff/impl/ContentRevisionLabelProvider.kt`

对照结论是：DevHaven 当前最缺的不是像素，而是 **request chain / current difference / pane metadata / viewer 分层** 四个真相源。

## 3. 方案对比

### 方案 A：继续在现有 `WorkspaceDiffTabView` 上叠加 UI 和交互

优点：改动最短、短期见效快。

缺点：

- 继续把状态堆在 View 层；
- working tree / commit diff 与 git log diff 很容易继续分叉；
- request chain 与跨文件 navigation 很难优雅接入；
- 会把“像 IDEA”停留在表层 UI。

### 方案 B：在现有结构上增加一层 orchestration

优点：成本可控、能较好承接 request chain 与 pane metadata。

缺点：

- 仍保留较多旧的 viewer 形状；
- 从长期看仍不是一套真正对齐 IntelliJ `diff-impl` 的 viewer framework。

### 方案 C：按 IntelliJ `diff-impl` 的思路重做一套更接近 IDEA 的 Diff Viewer Framework（用户选择）

优点：

- 最接近“复刻 IDEA 逻辑”；
- 可把 request chain、current difference、pane metadata、viewer layout 统一成一套框架；
- 便于后续继续补充快捷键、更多 editor 内动作与 diff 交互。

缺点：

- 改动面较大；
- 需要谨慎控制边界，避免外溢为整个 workspace / Git 子系统重构。

## 4. 最终方案

本轮采用方案 C，但明确边界：**重做 diff viewer framework，不重写 workspace tab 系统、不重写 Git service 主链、不追求像素级复刻。**

总体升级路径为：

`Runtime Diff Tab -> Diff Session -> Viewer Processor -> Viewer Layout`

而不再继续维持：

`Runtime Diff Tab -> Loaded Document -> SwiftUI 拼界面`

## 5. 架构与状态边界

### 5.1 新分层

#### A. Diff Session / Request Chain 层

负责表达“当前 diff 标签页正在浏览哪一串文件，以及当前位于链中的哪一项”。

拟新增：

- `WorkspaceDiffRequestItem`
- `WorkspaceDiffRequestChain`
- `WorkspaceDiffSessionState`
- `WorkspaceDiffNavigatorState`
- `WorkspaceDiffDifferenceAnchor`

职责：

- 单文件 / 多文件 chain 统一表达；
- 当前 item index 管理；
- 当前 difference 序号与前后可导航性；
- 文件内到头后跨文件 navigation。

#### B. Viewer Descriptor / Pane Metadata 层

负责把当前 item 统一描述成某种 viewer，并为各 pane 生成结构化标题信息。

拟新增：

- `WorkspaceDiffViewerDescriptor`
- `WorkspaceDiffPaneDescriptor`
- `WorkspaceDiffPaneMetadata`
- `WorkspaceDiffPaneCopyPayload`
- `WorkspaceDiffPaneHeaderRole`

职责：

- 统一描述 patch / two-side compare / merge viewer；
- 统一输出 pane title/path/hash/revision/author/time/rename/tooltip/copy payload；
- App 层只渲染 metadata，不再自己拼标题字符串。

#### C. Viewer Processor 层

现有 `WorkspaceDiffTabViewModel` 升级为接近 IntelliJ `DiffRequestProcessor` 的 processor。

职责：

- 驱动当前 diff session；
- 维护 current difference 真相源；
- 执行 previous / next difference；
- 执行当前文件到头后的跨文件切换；
- 构建当前 viewer descriptor；
- 统一 compare / merge / patch 的差异选择与 block/action 逻辑。

#### D. App 渲染层

`WorkspaceDiffTabView` 收窄为布局壳，只做：

- load state 路由；
- 顶部 navigation bar；
- pane header；
- viewer 子视图分发；
- editor host 接线。

### 5.2 现有 ViewModel 边界调整

#### `NativeAppViewModel`

继续负责 workspace runtime diff tabs 与 origin context 恢复，但 diff 相关职责收窄为：

- 打开 / 关闭 diff session；
- 为 commit / git log 构造 request chain；
- 维持 runtime diff tabs，不自己承担 current difference 逻辑。

#### `WorkspaceDiffTabViewModel`

从“单 source 文档加载器”升级为“session 级 processor”：

- current request item；
- current difference anchor；
- previous / next difference；
- pane metadata；
- compare / merge / patch viewer descriptor；
- 块级动作与保存。

#### `WorkspaceTextEditorView`

仍然只做编辑器宿主：

- 文本显示；
- line / inline highlight；
- scroll sync；
- scroll request；
- editor 内动作锚点承载。

禁止承担：

- request chain；
- current difference 业务真相源；
- 跨文件 navigation。

## 6. 组件与文件改造

### 6.1 Core 模型新增

新增：

- `macos/Sources/DevHavenCore/Models/WorkspaceDiffSessionModels.swift`
- `macos/Sources/DevHavenCore/Models/WorkspaceDiffPaneMetadataModels.swift`

保留并扩展：

- `macos/Sources/DevHavenCore/Models/WorkspaceDiffModels.swift`

其中：

- `WorkspaceDiffModels.swift` 继续承载 compare/merge/pane/block/highlight/document；
- session/chain/navigator/pane metadata 拆到新文件，避免单文件膨胀。

### 6.2 App 视图拆分

新增：

- `macos/Sources/DevHavenApp/WorkspaceDiffNavigationBarView.swift`
- `macos/Sources/DevHavenApp/WorkspaceDiffPaneHeaderView.swift`
- `macos/Sources/DevHavenApp/WorkspaceDiffTwoSideViewerView.swift`
- `macos/Sources/DevHavenApp/WorkspaceDiffMergeViewerView.swift`
- `macos/Sources/DevHavenApp/WorkspaceDiffPatchViewerView.swift`

调整：

- `macos/Sources/DevHavenApp/WorkspaceDiffTabView.swift`
- `macos/Sources/DevHavenApp/WorkspaceTextEditorView.swift`

目标：

- `WorkspaceDiffTabView` 只做壳；
- navigation/header/viewer 子组件各自承载对应层；
- `WorkspaceTextEditorView` 只承载 editor 宿主与动作锚点。

### 6.3 NativeAppViewModel 接线扩展

需要调整：

- `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`

新增入口语义：

- `openWorkspaceDiffSession(...)`
- `openActiveWorkspaceDiffSession(...)`

commit / working tree 与 git log 两条入口都统一先构造 `WorkspaceDiffRequestChain`，再打开到 runtime diff tab 中。

## 7. 数据流与交互闭环

### 7.1 三种入口统一成 request chain

#### Commit / working tree changes browser

来源：

- `WorkspaceCommitChangesBrowserView`
- `WorkspaceCommitRootView`
- 相关 commit preview 打开链路

行为：

- 当前 execution worktree 的 changes snapshot 形成 request chain；
- 当前点击文件作为 active item；
- diff tab 打开的是 session，而不再是单文件孤立 source。

#### Git log 历史 diff

来源：

- `WorkspaceGitIdeaLogChangesView`
- `WorkspaceGitIdeaLogRightSidebarView`

行为：

- 当前 commit 的 changed files 形成 request chain；
- 双击文件时以该文件为 active item 打开 session；
- patch/log 浏览也走统一导航壳。

#### 单文件 fallback

当链式上下文不可用时，退化为单 item chain，但 processor 逻辑保持一致。

### 7.2 current difference 真相源

当前 View 层的：

- `selectedCompareBlockID`
- `selectedMergeBlockID`

将提升为 processor 维护的统一：

- `selectedDifferenceAnchor`

统一驱动：

- top previous / next；
- side rail 选中；
- overview gutter 选中；
- editor 自动滚动；
- editor 内块级动作；
- 文件切换后的默认差异选择。

### 7.3 previous / next difference 的完整行为

#### 文件内导航

- compare：在 `WorkspaceDiffCompareBlock` 间切换；
- merge：在 `WorkspaceDiffMergeConflictBlock` 间切换；
- patch：在 hunk 间切换。

执行时同时更新：

1. `selectedDifferenceAnchor`
2. side rail / gutter 高亮
3. editor 滚动定位
4. 顶部差异序号

#### 文件边界导航

- 当前文件无下一处差异时，若 chain 仍有下一文件，则切换到下一 item；
- 自动选中新文件第一处差异；
- `previous` 对称成立，回到上一文件最后一处差异。

#### 终点处理

- 链头 / 链尾时按钮禁用；
- 差异计数保持真实；
- 不做 silent failure。

### 7.4 compare / merge / patch viewer 的统一导航语义

- compare：差异单位为 block；
- merge：差异单位为 conflict block；
- patch：差异单位为 hunk。

顶部 navigation bar 不感知 viewer 细节，只消费 processor 暴露的 navigator state。

### 7.5 pane metadata 生成闭环

processor 对每个 pane 统一生成：

- display title
- displayed path / rename path
- revision / hash / branch
- author / timestamp
- tooltip
- copy payload

App 层只做渲染，不再通过 `currentSubtitle` 等 helper 现推导。

### 7.6 动作分布

#### 顶部 navigation bar

负责：

- previous / next difference
- 当前差异序号
- 当前文件序号
- refresh / viewer mode 等全局动作

#### pane header

负责：

- pane 标题
- path / hash / revision / author / time
- copy / tooltip affordance

#### editor 内 / block 附近

负责：

- compare 的 stage / unstage / revert / apply-like 动作；
- merge 的 accept ours / theirs / both；
- current difference 聚焦与 selected changes 语义。

side rail 退回为导航概览与辅助入口，而不是唯一动作主入口。

## 8. 错误处理与边界约束

### 8.1 错误处理

#### Request chain 构造失败

- 回退为单 item chain；
- 不阻塞 diff 打开；
- 记录结构化 fallback，而不是 silent fail。

#### current difference 不可定位

- 自动回退到首个/末个合法差异；
- 若无任何差异则显示 `0 / 0`，并禁用 navigation。

#### pane metadata 不完整

- provider 输出缺省字段；
- App 层按“有则显示、无则省略”；
- 不编造占位信息。

### 8.2 边界约束

1. 不重写 `NativeGitRepositoryService` / `NativeGitCommitWorkflowService` 主链；
2. 不推翻现有 runtime diff tab 与 origin context 机制；
3. 不把 `WorkspaceTextEditorView` 升级成业务层；
4. 不追求像素级复刻，只对齐交互逻辑；
5. 不一次性追满所有 IDEA diff 快捷键、上下文菜单与 combined diff。

### 8.3 明确不做项

- 完整快捷键系统复刻；
- 所有右键上下文菜单；
- combined diff / stacked multi-file diff 页面；
- review thread / comment 系统；
- 新的持久化协议（request chain / current difference / metadata cache 保持 runtime-only）。

## 9. 测试策略

### 9.1 Core 模型与 session 测试

新增：

- `macos/Tests/DevHavenCoreTests/WorkspaceDiffSessionModelsTests.swift`
- `macos/Tests/DevHavenCoreTests/WorkspaceDiffPaneMetadataModelsTests.swift`

覆盖：

- request chain 构造与切换；
- navigator state；
- pane metadata 的完整字段与降级逻辑。

### 9.2 Processor 测试

调整：

- `macos/Tests/DevHavenCoreTests/WorkspaceDiffTabViewModelTests.swift`
- 视情况新增 `macos/Tests/DevHavenCoreTests/WorkspaceDiffNavigationTests.swift`

覆盖：

- compare / merge / patch 默认差异选择；
- previous / next difference；
- 跨文件切换；
- request chain 切换后的 descriptor 与 metadata 更新；
- block action 后 current difference 的合法回收。

### 9.3 App 结构测试

新增：

- `macos/Tests/DevHavenAppTests/WorkspaceDiffNavigationBarViewTests.swift`
- `macos/Tests/DevHavenAppTests/WorkspaceDiffPaneHeaderViewTests.swift`

调整：

- `macos/Tests/DevHavenAppTests/WorkspaceDiffTabViewTests.swift`
- `macos/Tests/DevHavenAppTests/WorkspaceTextEditorViewTests.swift`

覆盖：

- navigation bar 的按钮、差异序号、文件序号与禁用态；
- pane header 按 metadata 渲染；
- `WorkspaceDiffTabView` 只做 viewer 分发；
- editor 宿主继续只承担显示与滚动桥接。

### 9.4 NativeAppViewModel 入口测试

调整：

- `macos/Tests/DevHavenCoreTests/NativeAppViewModelWorkspaceDiffTabTests.swift`

覆盖：

- commit preview 打开时构造 request chain；
- git log changes browser 打开时构造 request chain；
- 单实例 commit preview 仍能复用 identity，但内部 session item 正确切换；
- 关闭 diff tab 后 origin context 恢复不被破坏。

## 10. 验收标准

### 10.1 顶部导航条

必须满足：

- 存在 `Previous Difference / Next Difference`；
- 显示当前差异序号；
- 显示当前文件序号；
- 当前文件到头可自动跨文件；
- 链头 / 链尾正确禁用。

### 10.2 左右 pane 信息

必须满足：

- 不再只是 path；
- 统一通过 metadata provider 渲染：title / path / oldPath / revision/hash/branch / author/time；
- tooltip / copy affordance 可用。

### 10.3 compare / merge / patch 交互

必须满足：

- current difference 是统一真相源；
- top nav / side rail / gutter / editor 联动；
- compare / merge editor 内动作分布更接近 IDEA；
- merge 支持 conflict 级导航；
- git log 历史 diff 进入同一套 viewer 框架。

### 10.4 回归约束

必须保证：

- compare 可编辑保存；
- merge result 可编辑保存；
- stage / unstage / revert 不回退；
- origin context 恢复不回退；
- commit 单实例 preview 机制不回退。

## 11. 设计结论

本轮不是“继续往现有 diff 界面上叠加功能”，而是把 DevHaven diff 正式提升为一套**会话驱动、processor 驱动、metadata 驱动**的 viewer framework。只有这样，才能把用户要求的三件事——顶部 previous/next difference、左右 pane 详情、compare/merge/pattern viewer 的强交互——真正对齐到 IntelliJ IDEA 的逻辑心智，而不是停留在视觉相似。
