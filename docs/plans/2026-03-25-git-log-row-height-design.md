# Git Log 行高与线条连贯度调整设计

## 背景

当前标准 IDEA Log 的 commit graph 已经解决了 lane 拓扑、row-local clipping 与像素对齐问题，但最新截图暴露出另一类视觉缺陷：

- 选中行背景在上下边缘留出明显暗色缝隙；
- 竖向 graph 线段虽然几何上连续，但视觉上像是悬在行中间，没有贴住相邻行；
- merge row 的 subject cell 看起来像一个嵌进表格中的卡片，而不是完整的一整行。

## 直接原因

当前 `WorkspaceGitCommitGraphView` 和 `WorkspaceGitIdeaLogTableView` 之间存在高度真相源不一致：

- graph renderer 自己固定使用 `rowHeight = 22`；
- table subject cell 只是 `minHeight = WorkspaceGitCommitGraphView.rowHeight`，并没有把内容区强制对齐到同一固定高度；
- `Table` 的真实可见行盒高度因此比 graph 的内部 row box 更高，选中背景和 graph 都只落在中间内容区，行上下剩余空间表现为截图里的“缝”。

## 目标

采用用户确认的方案 A：

1. 让 graph renderer 的 `rowHeight` 与 table subject cell 的可见内容盒高度重新对齐；
2. 在不回退现有 clipping / pixel alignment 方案的前提下，微调 line / node / overflow metrics；
3. 以最小改动消除“上下有一个间隔”的观感，让 commit graph 竖线看起来更连贯。

## 方案比较

### 方案 A：对齐 graph rowHeight 与 table 内容盒高度，并微调 metrics

做法：

- 提高 `WorkspaceGitCommitGraphView.rowHeight`；
- `WorkspaceGitIdeaLogTableView.subjectCell` 改为固定 `height`，而不是仅提供 `minHeight`；
- 视需要同步微调 `verticalOverflow`、`strokeWidth`、`nodeRadius`、文本/徽标 vertical rhythm。

优点：

- 直接命中当前根因；
- 只影响 graph row 与 subject cell，风险最低；
- 最容易把背景留缝和线条断续一起解决。

缺点：

- log 密度会略微下降；
- 需要选一个足够贴近当前 table 行盒的目标高度，避免过松。

### 方案 B：保持 graph 22pt，仅修改背景与容器拉伸

做法：

- 尝试让 subject cell 或 button 自身填满 table cell；
- 保持 graph 内部 rowHeight 不变。

优点：

- 视觉密度变化最小。

缺点：

- 容易出现“背景满了，但 graph 线还是悬在中间”的半修状态；
- SwiftUI `Table` 的 cell/inset 语义不透明，排障成本高于方案 A。

### 方案 C：整体紧凑化重排

做法：

- 一次性重排 rowHeight、badge padding、text spacing、stroke、node 等一整组视觉参数。

优点：

- 最有机会做到整体观感最优。

缺点：

- 超出本轮“先把这条缝修掉”的最小目标；
- 风险高于本轮需求。

## 选型

本轮采用 **方案 A**。

理由：

- 截图里的问题已经明确定位到高度真相源不一致；
- 用户目标不是重新设计整张 log，而是先去掉“上下有一个间隔”；
- 方案 A 可以在不碰 graph core 与排序逻辑的前提下完成最小修复。

## 设计细节

### 1. 高度真相源

- `WorkspaceGitCommitGraphView.rowHeight` 调整为更接近当前 `Table` 可见行盒的值；
- `WorkspaceGitIdeaLogTableView.subjectCell` 从 `minHeight` 改为固定 `height`，让 graph 与背景使用同一高度真相源；
- graph view 外层 frame 继续直接复用 `WorkspaceGitCommitGraphView.rowHeight`。

### 2. Graph 连贯度

- 保留现有 `visibleEndpoint(...)`、`pixelAligned(...)`、row-local clipping 策略；
- 仅对 `verticalOverflow`、`strokeWidth`、`nodeRadius` 做小幅微调，使更高的 rowHeight 下线条仍然足够连续，不显得细弱或漂浮。

### 3. 回归测试

- 在 `WorkspaceGitIdeaLogViewTests` 新增红灯测试：
  - 约束 graph renderer 的 `rowHeight` 已提升到新的目标值；
  - 约束 subject cell 使用固定 `height`，而不是继续只写 `minHeight`；
  - 保持现有“graph view 统一 rowHeight 真相源”的契约不回退。

## 涉及文件

- `macos/Sources/DevHavenApp/WorkspaceGitCommitGraphView.swift`
- `macos/Sources/DevHavenApp/WorkspaceGitIdeaLogTableView.swift`
- `macos/Tests/DevHavenAppTests/WorkspaceGitIdeaLogViewTests.swift`
- `tasks/todo.md`

## 验证计划

- 红灯：`swift test --package-path macos --filter WorkspaceGitIdeaLogViewTests`
- 定向：`swift test --package-path macos --filter 'WorkspaceGitIdeaLogViewTests|WorkspaceGitRootViewTests|WorkspaceShellViewGitModeTests|WorkspaceGitLogViewModelTests'`
- 质量：`git diff --check`

## 风险与边界

- 若仅提高 `rowHeight` 而不同步收口 subject cell `height`，很可能只会把缝的位置改变，而不会真正消失；
- 若把 rowHeight 调得过大，会让整个 log 视觉密度明显下降；
- 本轮不触碰 graph core / print element / BEK 排序，也不改非 `.log` section 的任何布局。
