# IDEA Git 左右侧区域 1:1 复刻设计

## 背景

当前 DevHaven 的 `.log` section 已经具备比较接近 IDEA 的中间提交表格与 commit graph，但左右两侧仍存在明显偏差：

1. 左侧缺少 IDEA Git Log 的 **branches dashboard panel**，branch/revision 过滤主要还停留在顶部 toolbar 菜单中；
2. 右侧 `changes / commit details / diff preview` 虽然主链已接通，但信息层级、密度和面板组织仍明显偏向“自定义 Git 面板”，而不是 IDEA 的 `MainFrame + CommitDetailsPanel + ChangesBrowser` 结构。

用户已明确要求：本轮直接继续实现，不再逐段确认，只需要最终验收。

## 目标

把 `.log` section 调整为更接近 IDEA 的结构，重点覆盖：

- 左侧：新增 **可展开 / 可收起** 的 branches panel；
- 中间：保留现有 `WorkspaceGitIdeaLogTableView` 与 graph 主链；
- 右侧：收紧并重组 `changes / details / diff` 面板结构与展示层级。

## 非目标

本轮不做以下事项：

- 不重写中间 commit table / graph core；
- 不完整复刻 IntelliJ 的全部 branch dashboard 动作（如收藏、导航模式切换、快捷动作组）；
- 不把 branches panel 的展开态、搜索词写入持久化存储；
- 不改动非 `.log` section（`changes / branches / operations`）现有主链。

## 方案选择

采用“**外壳先对齐 IDEA MainFrame**”方案：

- 保留现有中间区；
- 在 `WorkspaceGitIdeaLogView` 外层加上 `.log` 专用的左侧 branches shell；
- 右侧 details/changes/diff 保持既有数据读取链路，只重构 App 层信息组织与交互语义。

该方案能最大化复用已经稳定的 log table / graph / diff 数据主链，同时把本轮偏差最大的左右两侧拉回正确方向。

## 结构设计

### 1. `.log` 顶层容器

`WorkspaceGitIdeaLogView` 调整为三段式：

- 顶部：`WorkspaceGitIdeaLogToolbarView`
- 主体：`左侧 branches control strip + 可选 branches panel + 右侧 main content`
- 右侧 main content：继续承载 `table / bottom pane / diff preview`

其中：

- branches panel 的展开/收起状态属于 `.log` 运行时 UI 状态，仅存在于 App 侧 `@State`；
- branches panel 宽度同样只保存在 `.log` 视图局部状态，不进入 Core 层持久化模型；
- 右侧 main content 继续复用现有 `bottomRatio / diffRatio`。

### 2. 左侧 branches panel

新增 `WorkspaceGitIdeaLogBranchesPanelView.swift`，职责限定为：

- 显示 branches panel header、搜索框与 refs tree；
- 支持本地 / 远端 / 标签分组的折叠；
- 支持搜索词对 refs 进行前端过滤；
- 点击 ref 后调用 `WorkspaceGitLogViewModel.selectRevisionFilter(...)`；
- 高亮当前选中的 revision filter；
- 提供“收起 panel”入口。

边界约束：

- 不直接发起 Git 读取；
- 不持有第二份 revision 真相源；
- 不承担 author/date/path 等其它过滤职责；
- 不复用旧的 `WorkspaceGitSidebarView`，避免把 `.log` 再耦合回非 `.log` sidebar 语义。

### 3. 顶部 toolbar 收口

`WorkspaceGitIdeaLogToolbarView` 改为聚焦：

- 文本搜索
- 作者过滤
- 日期过滤
- 路径过滤
- details / diff preview 显隐
- 刷新

branch/revision 主入口从 toolbar 移到左侧 branches panel，避免“左栏与顶部同时承担同一过滤主链”的职责重叠。

### 4. 右侧 details / changes / diff 联动区

维持现有 Core 数据链路：

- 选中 commit -> `loadCommitDetail`
- 选中 file -> `loadFileDiff`

但 App 层结构做以下调整：

- `WorkspaceGitIdeaLogChangesView`
  - 改成更紧凑的 changes browser 风格；
  - 在列表中明确 selected file、高亮和 rename/copy 等补充信息；
  - 使用更接近 IDEA 的 header 与空态语义。
- `WorkspaceGitIdeaLogDetailsView`
  - 改成更紧凑的 commit details panel；
  - message、author、time、hash、refs、parents 分区展示；
  - 降低当前大块滚动文本视图的“卡片感”。
- `WorkspaceGitIdeaLogDiffPreviewView`
  - 统一为更接近面板式 diff preview header + 内容容器；
  - 保留现有 diff 截断提示与文件级 diff 行为。

## 数据流

### 左侧 panel -> log filter

1. 用户在 branches panel 搜索 refs；
2. 用户点击某个 local/remote/tag 项；
3. `WorkspaceGitLogViewModel.selectRevisionFilter(...)` 更新 revision 真相源；
4. `refresh()` 触发新的 log snapshot 读取；
5. 左侧 panel 高亮与中间 table 内容同步刷新。

### 中间 table -> 右侧 details/diff

1. 用户在 table 中选中 commit；
2. `WorkspaceGitLogViewModel.loadCommitDetail(...)` 加载 commit detail；
3. 首个文件自动选中；
4. `WorkspaceGitLogViewModel.loadFileDiff(...)` 加载文件级 diff；
5. changes / details / diff preview 三块区域联动更新。

## 错误处理与空态

- branches panel 在 refs 为空时显示明确空态，而不是空白滚动区；
- details / diff preview 保持“未选择提交 / 未选择文件 / 正在加载 / 已截断”四类语义分离；
- 所有新增文案统一使用中文。

## 测试策略

本轮优先采用现有 App 层源码契约测试（source-based tests）锁定结构，测试重点：

1. `.log` 顶层容器必须包含可展开 / 可收起的 branches panel；
2. branches panel 必须包含搜索框与 local/remote/tags 分组；
3. toolbar 不再继续承担 branch filter 主入口；
4. 右侧 details / changes / diff 视图必须保留联动链路，并收口到新的紧凑面板实现；
5. 定向跑 `WorkspaceGitIdeaLogViewTests` / `WorkspaceGitRootViewTests`，必要时扩大到 `WorkspaceGitLogViewModelTests`。

## 风险与取舍

### 风险 1：左侧 panel 做得过重

如果试图一次性补齐 IntelliJ branch dashboard 的所有操作，会把本轮范围拉大。

**处理**：本轮只复刻结构与主交互链路，保留后续扩展空间。

### 风险 2：右侧视觉改动影响已有联动

details/diff 的 UI 调整如果侵入过深，可能破坏当前已稳定的 commit/file selection 主链。

**处理**：不改 Core 读取 API，只在 App 层收紧布局与层级。

## 成功标准

满足以下标准即可认为本轮达到目标：

1. `.log` 左侧出现可展开 / 可收起的 branches panel；
2. 选中 branch / remote / tag 会驱动 log revision filter；
3. 顶部 toolbar 不再是 branch filter 的主要入口；
4. 右侧 `changes / details / diff preview` 视觉和层级明显更接近 IDEA；
5. 定向测试与必要验证命令通过。
