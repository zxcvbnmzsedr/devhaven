# IDEA Log 右侧信息栏回归与错误底部面板删除设计

## 背景

用户提供的 IDEA 截图表明，Git Log 的正确主结构应为：

- 左侧：branches panel
- 中间：log table
- 右侧：信息栏（changes tree + commit details）

而当前 DevHaven `.log` 仍延续了先前错误假设：

- 把 changes / details / diff preview 做成了底部 pane；
- 导致最右侧信息栏缺失；
- 也让当前 diff preview 落在错误位置，整体信息架构偏离 IDEA。

## 目标

把 `.log` 改回更接近截图的主布局：

- 保留左侧 branches panel；
- 保留中间 log table；
- 新增右侧信息栏；
- 删除当前错误的底部 changes/details/diff preview 接线与 toolbar 显隐入口。

## 非目标

- 不重写 graph / table / refs 数据主链；
- 不在本轮继续实现独立 diff preview；
- 不改非 `.log` section。

## 方案

采用“**右侧信息栏取代底部 pane**”方案：

1. `WorkspaceGitIdeaLogView` 从“中间 table + 底部 pane”改成“中间 table + 右侧 sidebar”；
2. 新增 `WorkspaceGitIdeaLogRightSidebarView.swift`，内部再用纵向 split 承接：
   - 上：`WorkspaceGitIdeaLogChangesView`
   - 下：`WorkspaceGitIdeaLogDetailsView`
3. `WorkspaceGitIdeaLogBottomPaneView.swift` 与 `WorkspaceGitIdeaLogDiffPreviewView.swift` 从 `.log` 主链移除；
4. `WorkspaceGitIdeaLogToolbarView` 删除 details / diff preview toggle，只保留过滤与刷新。

## 成功标准

1. `.log` 主结构变成 `左 branches | 中 table | 右 sidebar`；
2. 不再存在底部 changes/details/diff preview 主链；
3. toolbar 不再保留 details / diff preview 切换按钮；
4. 右侧 sidebar 继续显示 changes 与 commit details；
5. 定向测试通过。
