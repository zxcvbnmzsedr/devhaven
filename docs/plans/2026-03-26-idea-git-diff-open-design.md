# DevHaven 复刻 IDEA Git/Commit 独立 Diff 标签页设计

> 确认日期：2026-03-26  
> 用户决策：
> 1. 目标不是嵌入当前工具窗内部的 patch 预览，而是**像 IntelliJ IDEA 一样，双击后独立打开 Diff 标签页**。  
> 2. 范围不是只修 `Git Log`，而是 **`Git Log Changes Browser + Commit Changes Browser` 统一一套打开逻辑**。  
> 3. 视觉目标参考用户给出的 IDEA diff 面板截图，至少要具备“独立标签页 + side-by-side/unified diff viewer”的基本心智。

---

## 1. 背景

DevHaven 当前已经有两条与文件 diff 相关、但都不完整的链路：

1. `WorkspaceGitIdeaLogChangesView`
   - 单击文件会调用 `WorkspaceGitLogViewModel.selectCommitFile(...)`
   - `WorkspaceGitLogViewModel` 会异步加载 `selectedFileDiff`
   - 但 App 层当前**没有真正把这份 file diff 渲染成独立 viewer**
   - 结果是：用户双击 Git Log 变更时，没有像 IDEA 那样打开独立 diff 标签页

2. `WorkspaceCommitChangesBrowserView`
   - 单击文件会调用 `WorkspaceCommitViewModel.selectChange(...)`
   - `WorkspaceCommitViewModel` 会异步维护 `diffPreview`
   - 但 `WorkspaceCommitRootView` 当前已经按产品决策移除了内嵌 diff preview 分区
   - 结果是：Commit 工具窗里也缺少“打开真正 diff viewer”的主链

这导致当前产品在用户感知上会出现两个明显问题：

- **双击无效**：Changes Browser 更像“可选中列表”，不是“可打开 diff 的浏览器”
- **状态链路不闭环**：Core 层已经能读 patch，但 Workspace 层没有统一的“打开 diff 文档/标签页”能力

而用户已经明确要求：

- 复刻 IntelliJ Community 的 Git diff 打开逻辑
- 不是工具窗内小预览，而是**独立标签页**
- Git Log 与 Commit 要统一为同一套打开模型

---

## 2. IntelliJ Community 参考实现结论

本轮已对 `/Users/zhaotianzeng/Documents/business/tianzeng/intellij-community` 做了针对性源码确认，关键主链如下：

### 2.1 Changes Browser 的双击入口不是业务特判，而是统一 `showDiff()`

- `platform/vcs-impl/src/com/intellij/openapi/vcs/changes/ui/ChangesBrowserBase.java`
  - `onDoubleClick()` → `showDiff()`
  - `showDiff()` 会优先走 `DiffPreview.performDiffAction()`
  - 如果当前没有挂 preview，则退回 standalone diff

这说明 IDEA 的设计不是“每个 browser 自己决定如何弹 diff”，而是：

- browser 只负责 selection 和 diff producer
- open diff 是统一动作

### 2.2 VCS Log Changes Browser 只负责提供 diff producer

- `platform/vcs-log/impl/src/com/intellij/vcs/log/ui/frame/VcsLogChangesBrowser.kt`
  - `getDiffRequestProducer(...)`
  - `createChangeProcessor(...)`

也就是说，VCS Log 的 Changes Browser 本身不直接持有 diff window；它只负责把当前选中的 `Change` 变成可打开的 diff request producer。

### 2.3 独立打开 editor/tab diff 的动作由 diff preview 层负责

- `platform/vcs-log/impl/src/com/intellij/vcs/log/ui/frame/VcsLogEditorDiffPreview.kt`
- `platform/vcs-impl/src/com/intellij/openapi/vcs/changes/ui/TreeHandlerEditorDiffPreview.kt`
- `platform/vcs-impl/src/com/intellij/openapi/vcs/changes/EditorTabPreview.kt`

这里可以看出 IDEA 的真实分工是：

- **单击**：更新 selection / details / current file
- **双击 / Enter / Show Diff**：统一走 `performDiffAction()`
- `performDiffAction()` 再决定是：
  - 打开 editor tab diff
  - 还是走外部 diff tool

### 2.4 对 DevHaven 的直接启发

要复刻的不是单个 `.onTapGesture(count: 2)`，而是完整的责任分层：

1. Changes Browser 继续负责 selection
2. Git Log / Commit 都产出统一的 diff open request
3. Workspace 级 runtime 负责“打开独立标签页”
4. 独立标签页自己的 viewer 负责 side-by-side / unified 呈现

---

## 3. 当前问题与根因

### 3.1 直接原因

1. `WorkspaceGitIdeaLogChangesView` 当前只支持“单击选中文件”，没有把双击或等价动作接到统一 open diff 主链。
2. `WorkspaceCommitChangesBrowserView` 当前也只支持“单击选中 + inclusion toggle”，没有独立 diff 文档入口。
3. 当前 Workspace 顶部 tab 仍以 `GhosttyWorkspaceController` 的 terminal tab 为中心，缺少“非终端内容标签页”的正式宿主位。

### 3.2 设计层诱因

1. **状态职责混叠**  
   `WorkspaceGitLogViewModel.selectedFileDiff` 和 `WorkspaceCommitViewModel.diffPreview` 都带有明显的“preview 语义”，不是“独立文档语义”。

2. **Workspace tab 语义过窄**  
   现有 `WorkspaceTabState -> WorkspacePaneTree -> WorkspaceTerminalLaunchRequest` 链路天然表达的是“终端 tab”，而不是“任意 Workspace 内容 tab”。

3. **打开动作缺少统一收口**  
   Git Log 与 Commit 都能定位到“哪一个文件要看 diff”，但没有统一的 `open diff tab` API。因此每个 browser 最终都停在 selection，而不是 open。

### 3.3 当前结论

- 直接原因已经明确：**双击没有接到统一 open diff 主链**。
- 设计层诱因也已经明确：**Workspace 缺少 runtime 级文档标签页能力**。
- 未发现新的明显系统设计缺陷；当前问题集中在“tab 宿主层缺口”和“preview/document 语义未拆分”。

---

## 4. 方案对比

### 方案 A：只给现有列表补双击，然后弹独立窗口 / sheet 显示 patch

**结论：不采用**

优点：
- 实现最省
- 代码改动最少

缺点：
- 不是用户要的“独立标签页”
- 依然没有统一的 Workspace 文档打开能力
- Git Log / Commit 只是共享了一个弹窗 helper，不是真正统一的打开逻辑

### 方案 B：把 `GhosttyWorkspaceController / WorkspaceSessionState` 直接改造成“终端 tab + diff tab”混合模型

**结论：不采用**

优点：
- tab 顺序、选中、关闭都能复用现有 controller 体系
- 从抽象上最接近“所有 tab 都归同一控制器管理”

缺点：
- 侵入 `WorkspaceSessionState`、`WorkspacePaneTree`、restore snapshot 语义过深
- 当前 controller 明确是终端拓扑控制器，把 diff tab 塞进去会让 restore / split / pane API 都背上额外分支
- 对现有 terminal 主链改动过大，不符合“最少修改原则”

### 方案 C：保留 terminal controller 纯终端职责，在 Workspace runtime 层新增“展示标签页”能力，并把 diff tab 作为 runtime-only 文档挂到同一 tab bar

**结论：采用**

优点：
- 用户仍然看到统一顶栏标签页
- `GhosttyWorkspaceController` 继续只负责终端 tab / pane / split / restore
- diff tab 明确属于 runtime-only 文档态，不污染 restore snapshot
- Git Log / Commit 可以真正共用一个 `openWorkspaceDiffTab(...)` 主链
- 侵入面明显小于方案 B，更符合当前代码库边界

缺点：
- 顶部 tab bar 需要从“只会渲染 terminal tab”升级到“渲染 terminal tab + diff tab”
- 关闭快捷键 / tab 选择逻辑需要新增一层 runtime 选择语义

---

## 5. 目标架构

### 5.1 总体思路

保留现有终端主链不变：

- `GhosttyWorkspaceController`
- `WorkspaceSessionState`
- `WorkspaceTabState`
- `WorkspacePaneTree`

新增一层 Workspace runtime 的**展示标签页（presented tabs）**：

- terminal tab：对 `GhosttyWorkspaceController.tabs` 的 UI 代理
- diff tab：runtime-only 文档标签页

这样，用户看到的是统一 tab bar；但内部职责仍然分离：

- 终端拓扑继续由 terminal controller 管
- diff 文档由 App/Core runtime 管

### 5.2 关键新模型

建议新增以下核心模型：

#### A. `WorkspaceDiffOpenRequest`
统一表达“从哪里打开什么 diff”。

建议包含：

- `projectPath`：当前 workspace project path
- `source`：
  - `.gitLogCommitFile(repositoryPath, commitHash, filePath)`
  - `.workingTreeChange(repositoryPath, executionPath, filePath)`
- `preferredTitle`
- `preferredViewerMode`（默认 `.sideBySide`）

#### B. `WorkspaceDiffTabState`
表达一个已经打开的 diff 文档标签页。

建议包含：

- `id`
- `identity`（用于去重）
- `title`
- `source`
- `viewerMode`
- `isPinned`（当前可预留，不必首轮用到）

#### C. `WorkspacePresentedTabItem`
给 `WorkspaceTabBarView` 使用的统一渲染模型。

建议包含：

- `id`
- `title`
- `kind`：`.terminal(tabID)` / `.diff(diffTabID)`
- `isSelected`
- `canSplit`（diff tab 为 false）

#### D. `WorkspaceDiffDocumentState`
给 diff viewer 使用的完整文档态。

建议包含：

- `title`
- `viewerMode`
- `loadState`（idle / loading / loaded / failed）
- `parsedDiff`
- `notice`（如 binary / empty / too large）

### 5.3 关键状态归属

#### 终端 tab 真相源
- `GhosttyWorkspaceController`
- 继续负责：create/select/close/move terminal tab、split pane、focus pane、restore snapshot

#### diff tab 真相源
- `NativeAppViewModel`
- 建议新增：
  - `workspaceDiffTabsByProjectPath`
  - `workspaceSelectedPresentedTabByProjectPath`

#### 文档内容真相源
- `WorkspaceDiffTabViewModel`
- 不再复用 Git/Commit 的 preview state 作为最终 viewer 真相源

### 5.4 restore 边界

这一条必须明确：

- **terminal tab**：继续进入 `WorkspaceRestoreCoordinator / WorkspaceRestoreStore`
- **diff tab**：**不进入** restore snapshot，只存在于运行时内存

原因：
- 当前 restore 边界已经明确是 terminal workspace snapshot
- diff tab 属于 runtime-only 文档态
- 把 diff tab 持久化会把 restore 语义扩大成“恢复所有临时文档”，成本不值得本轮承担

---

## 6. 数据流与交互流

### 6.1 Git Log Changes Browser

```text
单击文件行
-> WorkspaceGitLogViewModel.selectCommitFile(path)
-> 更新当前 selection / details 上下文

双击文件行
-> WorkspaceGitIdeaLogChangesView 构造 WorkspaceDiffOpenRequest
-> NativeAppViewModel.openWorkspaceDiffTab(request)
-> Workspace runtime 查重/新建 diff tab
-> WorkspaceHostView 切到对应 diff tab
-> WorkspaceDiffTabViewModel 加载完整 diff
-> WorkspaceDiffTabView 渲染 side-by-side / unified viewer
```

### 6.2 Commit Changes Browser

```text
单击文件行
-> WorkspaceCommitViewModel.selectChange(path)
-> 更新当前 Commit selection / inclusion 上下文

双击文件行
-> WorkspaceCommitChangesBrowserView 构造 WorkspaceDiffOpenRequest
-> NativeAppViewModel.openWorkspaceDiffTab(request)
-> 后续与 Git Log 路径完全一致
```

### 6.3 去重策略

同一 diff 请求不应重复开多个标签页。

建议 identity 规则：

- Git Log：`git-log|repositoryPath|commitHash|filePath`
- Commit：`working-tree|executionPath|filePath`

再次双击同一文件时：
- 若已有标签页，直接切过去
- 不再新建副本

### 6.4 关闭行为

- 关闭 diff tab：只关闭当前 diff 文档，不影响 terminal tab
- 当 diff tab 关闭后：
  - 若仍有其它 diff tab，优先切相邻 diff tab
  - 否则回到最近一次 terminal 选中 tab

### 6.5 快捷键与 Close Planner

当前 `AppRootView -> MainWindowCloseShortcutPlanner` 的语义是：

- 先关 pane
- 再关 tab
- 最后 exit workspace

引入 diff tab 后，需要补一条更高优先级规则：

- **如果当前选中的是 diff tab，则 `⌘W` 应先关闭 diff tab**

也就是说，diff tab 在 close planner 中属于“比 terminal pane 更外层，但比 exit workspace 更内层”的关闭对象。

---

## 7. Diff 文档加载与渲染设计

### 7.1 为什么不能直接复用当前 preview 字段

#### Git Log
`WorkspaceGitLogViewModel.selectedFileDiff` 当前带有：
- 截断逻辑
- preview 语义
- 非文档生命周期

#### Commit
`WorkspaceCommitViewModel.diffPreview` 当前带有：
- selection-coupled 生命周期
- preview 三态
- 用于 changes browser 联动，而不是独立文档

因此本轮必须拆分：

- preview state：属于 browser 内部联动
- document state：属于独立 diff 标签页

### 7.2 完整 diff 加载源

#### Git Log
- `NativeGitRepositoryService.loadDiffForCommitFile(at:commitHash:filePath:)`

#### Commit / Working Tree
- 复用 `NativeGitCommitWorkflowService.loadDiffPreview(at:filePath:)`
- 但新文档链路不再对结果做 preview 截断

### 7.3 Patch 解析模型

为了实现 side-by-side / unified viewer，需要把 patch 从字符串提升为结构化模型。

建议新增纯解析层：

- `WorkspaceDiffPatchParser`
- 输出：
  - file header
  - hunk 列表
  - line items（context / added / removed / meta）
  - paired rows（供 side-by-side 使用）

### 7.4 Viewer 形态

#### 默认模式
- 默认使用 **Side-by-side**
- 更贴近用户截图和 IDEA 的主观心智

#### 切换模式
- 支持切到 **Unified**
- mode 是 diff tab 自己的 runtime state

#### 顶部工具栏
首轮至少应包含：
- 文件标题
- viewer mode 切换（side-by-side / unified）
- 刷新
- 关闭标签页

为了给后续更贴近 IDEA 的 toolbar 留扩展位，建议在结构上保留：
- ignore policy slot
- highlight lines slot

但本轮非目标是不要求完整复刻所有 ignore policy 矩阵或 JetBrains 级别的 editor action 生态。

### 7.5 空态与异常态

需要显式处理：

- 空 patch（例如 selection 变化后无差异）
- binary file
- parser failure
- Git 命令失败
- source disappeared（文件/commit 不存在）

所有错误都必须转成明确中文文案，而不是空白页。

---

## 8. App 层职责调整

### 8.1 `NativeAppViewModel`

新增职责：

- 管理 diff tab runtime state
- 暴露当前 active workspace 的 presented tabs
- 提供统一入口 `openWorkspaceDiffTab(...)`
- 提供 `selectWorkspacePresentedTab(...) / closeWorkspaceDiffTab(...)`

继续保持：
- 不直接承担 diff viewer 绘制
- 不把 diff tab 写入 restore snapshot

### 8.2 `WorkspaceHostView`

当前职责：
- tab bar
- terminal host

新增职责：
- 基于 presented tab 决定当前渲染：
  - terminal host
  - diff host

### 8.3 `WorkspaceTabBarView`

当前只能消费 `[WorkspaceTabState]`。

本轮需要升级为消费统一展示模型，比如：
- `[WorkspacePresentedTabItem]`

并支持：
- terminal tab
- diff tab
- diff tab 关闭按钮
- diff tab 选中态
- diff tab 被选中时禁用 split 按钮

### 8.4 `AppRootView`

需要更新：
- close shortcut planner context
- 当前选中 diff tab 时，`⌘W` 先关闭 diff tab

---

## 9. 测试策略

### 9.1 Core 行为测试

- `NativeAppViewModel`：
  - open diff tab 会创建 runtime tab
  - 同 identity 再次 open 只切换选中
  - close diff tab 不影响 terminal tabs
  - diff tab 不进入 restore snapshot

- `WorkspaceDiffPatchParser`：
  - 能正确解析 unified diff
  - 能正确输出 side-by-side 行对
  - rename / empty / binary patch 有稳定 fallback

- `WorkspaceDiffTabViewModel`：
  - 能根据 source 正确加载完整 diff
  - mode 切换不丢文档内容
  - 加载失败时返回稳定中文错误态

### 9.2 App 层 source contract 测试

- `WorkspaceGitIdeaLogChangesViewTests`
  - 双击文件行会调用统一 open diff 闭包/动作

- `WorkspaceCommitRootViewTests`
  - Commit changes browser 双击文件行会调用统一 open diff 闭包/动作

- `WorkspaceHostViewTests`
  - 当前选中 diff tab 时应渲染 diff host，而不是 terminal split tree

- `WorkspaceTabBarViewTests`
  - diff tab 与 terminal tab 共用同一 tab bar
  - diff tab 选中时 split 按钮禁用

- `InitialWindowActivatorTests` / close planner tests
  - 当前选中 diff tab 时，close planner 优先返回“关闭 diff tab”而不是“关闭 pane”

### 9.3 集成验证

建议最终至少执行：

```bash
swift test --package-path macos --filter 'NativeAppViewModelWorkspaceDiffTabTests|WorkspaceDiffPatchParserTests|WorkspaceDiffTabViewModelTests|WorkspaceGitIdeaLogViewTests|WorkspaceCommitRootViewTests|WorkspaceHostViewTests|WorkspaceTabBarViewTests|InitialWindowActivatorTests'
```

再补一轮与 workspace/gotty 主链相关的回归：

```bash
swift test --package-path macos --filter 'WorkspaceShellViewTests|WorkspaceShellViewGitModeTests|WorkspaceGitRootViewTests|WorkspaceCommitSideToolWindowHostViewTests|NativeAppViewModelWorkspaceEntryTests'
```

以及：

```bash
git diff --check
```

---

## 10. 当前修复方案与长期建议

### 10.1 当前修复方案

本轮采用以下修复方案：

1. 保留 `GhosttyWorkspaceController` 的纯终端职责
2. 在 `NativeAppViewModel` / `WorkspaceHostView` 这一层新增 runtime-only diff tab 能力
3. Git Log 与 Commit 统一调用 `openWorkspaceDiffTab(...)`
4. 独立 diff 标签页使用新的完整文档加载链路与结构化 viewer
5. diff tab 不写入 restore snapshot

### 10.2 长期建议

1. **后续如果要继续追平 IDEA，可再把 tab 顺序从“terminal segment + diff segment”升级为完整 mixed order。**
   当前首轮优先保证统一打开能力、独立标签页和 viewer correctness。

2. **`WorkspaceGitLogViewModel.selectedFileDiff` 与 `WorkspaceCommitViewModel.diffPreview` 长期应进一步去 preview-only 化。**
   当前可以先保留以降低改动面，但未来最好把“browser preview”与“document viewer”彻底拆清。

3. **如果后续要支持 Compare Revisions / File History / Shelf / Stash，也应全部接入 `WorkspaceDiffOpenRequest`。**
   这样 DevHaven 才会形成真正可扩展的 diff 文档主链，而不是功能点各自为政。

