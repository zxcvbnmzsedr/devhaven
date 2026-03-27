# IDEA Git Changes tree 展开/折叠控制设计

## 背景

在上一轮把 `Changes` 区域从扁平列表改成 tree changes browser 后，用户继续指出：还需要增加一个**全局展开 / 全局折叠文件夹**的控制。

用户已明确确认，本轮采用：

- **方案 A**：在 `Changes` 顶部 toolbar 中增加“全部展开 / 全部折叠”按钮；
- 不在每个文件夹节点旁边增加单独局部按钮。

## 目标

1. 在 `WorkspaceGitIdeaLogChangesView` 顶部 toolbar 中补齐：
   - 全部展开
   - 全部折叠
2. 当前 tree changes browser 必须具备统一的目录展开状态真相源；
3. 目录节点的展开/折叠要真正受全局按钮控制，而不只是视觉占位。

## 非目标

- 不新增每个目录节点旁边的局部展开/折叠按钮；
- 不实现更复杂的树状态持久化；
- 不改变现有文件节点的选中与展示文案；
- 不补 changes toolbar 其它按钮的真实行为。

## 设计

### 1. 展开状态真相源

`WorkspaceGitIdeaLogChangesView` 新增 App-only 展开状态：

- `expandedDirectoryIDs: Set<String>`

该状态只在当前 changes browser 视图内存中存在，不进入 Core 层，也不写入任何持久化存储。

### 2. 从 OutlineGroup 切到可控递归树

由于需要程序化控制全局展开/折叠，`OutlineGroup` 不再适合作为主渲染方式。本轮改为：

- 保留 `ChangeTreeNode / ChangeTreeBuilder`
- 使用递归 `DisclosureGroup` 树渲染目录节点
- 通过 `expandedDirectoryIDs` 的 binding 控制节点展开态

### 3. 全局控制按钮

在 `changesBrowserToolbar` 中新增两个按钮：

- `expandAllDirectories()`
- `collapseAllDirectories()`

其行为分别为：

- 展开：把当前树中所有目录节点 id 放入 `expandedDirectoryIDs`
- 折叠：清空 `expandedDirectoryIDs`

### 4. 默认行为

当新的 commit detail 加载完成后：

- 默认将当前树的所有目录设为展开，避免用户第一次看到树时还要逐层手动展开。

## 测试策略

继续使用 source-based XCTest 锁定结构：

1. changes view 必须存在 `expandedDirectoryIDs`；
2. 必须存在 `expandAllDirectories` / `collapseAllDirectories` helper；
3. toolbar 必须包含“展开全部 / 折叠全部”按钮；
4. 主体树渲染不应继续只依赖 `OutlineGroup`；
5. 目录节点必须通过显式 binding 绑定展开状态。

## 成功标准

1. Changes toolbar 出现展开全部 / 折叠全部控制；
2. 点击后目录树能整体展开或收起；
3. 文件节点选中行为不受破坏；
4. 定向测试通过。
