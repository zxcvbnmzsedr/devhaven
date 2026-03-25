# IDEA Git 布局验收纠偏（二轮）设计

## 背景

在上一轮实现后，用户进行了第一轮 UI 验收，并指出两处关键偏差：

1. 左上角 `Git` 在 IDEA 中不应作为可点击入口；
2. 右侧 `Changes` 区域不应是扁平列表，而应更接近 IDEA 的 tree changes browser，并带有顶部那排小操作入口。

用户已进一步确认：**本轮优先级仍是结构优先**，也就是先把层级和容器心智做对；toolbar 小操作只要求布局和入口先对齐，不要求一次性补齐全部行为。

## 目标

本轮修正以下结构偏差：

1. 把 Git 工具窗顶部从“`Git / Log / Console` 三个等权按钮”改为“`Git` 标题 + `Log / Console` 次级入口”；
2. 把 `WorkspaceGitIdeaLogChangesView` 从扁平文件列表改为 tree changes browser；
3. 在 Changes 区域顶部补一排更接近 IDEA 的 toolbar 小操作入口。

## 非目标

本轮不做：

- 不补真实 Git Console 后端；
- 不完整复刻 IntelliJ changes browser 的所有 toolbar 行为；
- 不引入复杂 merge parent grouping 或全部 popup menu；
- 不做像素级 icon / hover / padding 最终抠图。

## 设计

### 1. Git 工具窗顶部层级

`WorkspaceGitRootView` 顶部改为：

- 左侧：`Git` 纯标题（不可点击）
- 右侧：`Log` / `Console` 可点击入口

其中：

- 默认状态仍是 Git 主内容；
- 点击 `Log` 进入标准 IDEA Log；
- 点击 `Console` 进入占位视图；
- 为避免“进入 Log/Console 后无法回到 Git”，允许点击当前已选中的 `Log` / `Console` 再次返回 Git 主内容。

### 2. Changes browser 容器

`WorkspaceGitIdeaLogChangesView` 由扁平 `List(detail.files)` 升级为 tree 容器：

- 顶部：pane header
- 次顶部：changes browser toolbar
- 主体：树形 changes browser

树的第一轮分层采取“目录树 + 文件节点”方案：

- 目录节点只负责结构展示；
- 文件节点保留现有 status icon、主文件名和次路径信息；
- 选择文件时仍驱动现有 `viewModel.selectCommitFile(...)`。

### 3. Changes toolbar

顶部 toolbar 本轮只要求“结构对齐”，不要求全量行为对齐：

- 放入 4 个更接近 IDEA 心智的 icon-only toolbar 按钮；
- 能直接接通的基础行为后续再补；
- 当前阶段允许使用 disabled / placeholder 入口，但布局、位置和容器关系必须先到位。

### 4. 测试策略

继续使用 source-based XCTest 锁定结构：

1. `WorkspaceGitRootView` 中 `Git` 不再通过 `topTabButton(.git)` 渲染；
2. `WorkspaceGitRootView` 存在 `gitToolWindowTitle` 一类标题 helper；
3. `WorkspaceGitIdeaLogChangesView` 必须存在 changes toolbar；
4. `WorkspaceGitIdeaLogChangesView` 必须使用树形容器，而不是继续 `List(detail.files)`；
5. 文件节点 helper 仍保留主文件名 / 次路径分层。

## 成功标准

1. 左上角 `Git` 已变为不可点击标题；
2. `Log / Console` 仍可作为次级入口存在；
3. Changes 区域明显已是 tree changes browser，而不是扁平文件列表；
4. Changes 顶部出现一排 IDEA 风格的小操作入口；
5. 定向测试通过。
