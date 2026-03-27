# IDEA Git 布局 1:1 复刻设计

## 背景

用户要求以 IntelliJ IDEA Git Tool Window 为参考，对 DevHaven 当前 Git 工具窗进行 1:1 方向复刻。本轮优先级已经确认：**结构与交互最重要**，视觉像素级细节放在第二优先级。

本轮参考实现与截图主要来自：

- IntelliJ `platform/vcs-log/impl/src/com/intellij/vcs/log/ui/frame/MainFrame.java`
- IntelliJ `plugins/git4idea/src/git4idea/ui/branch/dashboard/BranchesInGitLogUiFactoryProvider.kt`
- IntelliJ `plugins/git4idea/src/git4idea/ui/branch/dashboard/BranchesDashboardTreeComponent.kt`
- IntelliJ `plugins/git4idea/src/git4idea/ui/branch/dashboard/ExpandStripeButton.kt`
- 用户提供的 IDEA Git Tool Window 截图（顶部 `Git / Log / Console`，中间为 Log 主视图）

## 目标

本轮把 DevHaven Git 工具窗拉回到更接近 IDEA 的布局与交互层级：

1. 顶部具备更接近 IDEA 的 `Git / Log / Console` 顶层 tab strip；
2. `Log` tab 使用 IntelliJ 风格外壳：`左侧 branches stripe + 可展开 branches panel + MainFrame`；
3. `MainFrame` 内部采用 `toolbar + log table | right sidebar` 的横向 split；
4. `right sidebar` 采用 `changes browser | commit details` 的纵向 split；
5. branches 选择默认驱动 revision filter，后续保留扩展为 navigate/filter 模式的空间。

## 非目标

本轮不做：

- 不重写 Git 数据读取服务与 graph core；
- 不完整复刻 IntelliJ 所有 branches dashboard 动作；
- 不引入真实 Git Console 后端；`Console` 仅先对齐顶层结构；
- 不做像素级色值、字号、圆角的最终抠图；
- 不把 `.log` 局部的展示态写入持久化存储。

## 设计

### 1. Git 工具窗根层级

`WorkspaceGitRootView` 从“直接按 section 切换内容”调整为更接近 IDEA 的根层级：

- 顶部：`Git / Log / Console` tab strip；
- 主体：根据所选顶层 tab 路由：
  - `Log` -> `WorkspaceGitIdeaLogView`
  - `Git` -> 现有非 `.log` 内容（changes / branches / operations）
  - `Console` -> App 层占位视图

这样可以先把截图里最显眼的根部交互结构对齐，而不一次性重写全部 Git 业务子页面。

### 2. IDEA Log 外壳

`WorkspaceGitIdeaLogView` 调整为 IntelliJ 风格的两级嵌套布局：

- 最左：常驻 branches stripe / expand control；
- 中间：可展开或收起的 branches panel；
- 右侧：MainFrame。

其中：

- branches panel 展开态、panel 宽度、right sidebar 宽度、changes/details split 比例均属于 App-only 展示状态；
- toolbar 不再作为整个 `.log` 的顶层通栏，而是只属于 MainFrame 左侧 log table 区。

### 3. MainFrame 结构

对齐 IntelliJ `MainFrame.java` 的核心布局语义：

- 左侧主区：`WorkspaceGitIdeaLogToolbarView + WorkspaceGitIdeaLogTableView`
- 右侧信息栏：`WorkspaceGitIdeaLogRightSidebarView`

`WorkspaceGitIdeaLogRightSidebarView` 保持 `changes browser` 在上、`commit details` 在下。

### 4. branches panel 交互

本轮默认交互：

- 点击 local / remote / tag -> 更新 `selectedRevisionFilter`；
- 清空筛选 -> 恢复全部提交；
- panel 展开/收起只影响布局，不改变当前 revision/filter 真相源。

内部实现上，为后续扩展保留“过滤 / 导航 / 无动作”模式的余地，但本轮默认只落地过滤语义。

### 5. Console 范围

由于当前 DevHaven 没有真实 Git Console 数据链路，本轮 `Console` 只作为 Git 工具窗顶层结构的一部分：

- 提供可选 tab；
- 进入后显示明确中文占位空态；
- 不新增 Git 命令日志协议或持久化。

## 测试策略

优先采用现有 source-based App 测试锁定结构：

1. `WorkspaceGitRootView` 必须具备 `Git / Log / Console` 顶层 tab strip；
2. `Log` 顶层路由必须挂载 IntelliJ 风格 `WorkspaceGitIdeaLogView`；
3. `WorkspaceGitIdeaLogView` 必须把 toolbar 收口到 MainFrame 左侧，而非整个页面顶层；
4. branches stripe / panel / MainFrame 的三段关系必须明确；
5. Console 占位视图必须存在明确中文空态。

## 成功标准

1. 顶部存在 `Git / Log / Console` 顶层 tab strip；
2. `Log` tab 的主布局与 IDEA 截图心智一致；
3. branches panel 的展开/收起与 revision filter 联动正确；
4. 右侧继续保持 `changes + details` 联动；
5. 定向测试通过，且不破坏现有 Git Log 主链。
