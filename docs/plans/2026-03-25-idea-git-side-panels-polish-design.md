# IDEA Git 左右侧区域视觉抛光（二轮）设计

## 背景

上一轮已经把 `.log` 的结构拉回到更接近 IDEA 的方向：左侧有可展开 / 可收起的 branches panel，右侧有更紧凑的 changes / details / diff pane。

但从当前代码与 IntelliJ 参考实现继续对照，仍有几个高可见度差距：

1. 左侧 branches panel header 仍直接显示原始 `refs/...` revision 字符串，信息语义太“底层”；
2. 左侧分组 header 只有纯标题，没有数量等辅助信息，密度还不像 IDEA branches dashboard；
3. changes browser 仍以整条 `file.path` 作为主文本，不够接近 IDEA 的“文件名主视觉 + 路径次信息”；
4. commit details 的 refs 仍是同一种通用 capsule，没有 branch/tag/HEAD 的语义区分。

## 本轮目标

在不改动 Core Git 数据读取链路的前提下，继续做一轮 **纯 App 层信息密度抛光**：

- 左侧：把 branches panel header / 分组信息做得更像 IDE 面板；
- 右侧：把 changes / details 的路径与 refs 展示做得更有层级。

## 非目标

- 不增加新的 Git 命令或 mutation；
- 不引入 branches dashboard 的复杂动作（收藏、导航模式、快捷动作等）；
- 不改 `WorkspaceGitLogViewModel` / `NativeGitRepositoryService` 的公共 API；
- 不动中间 log table / graph renderer。

## 方案选择

采用“**语义抛光，不扩功能**”方案：

- 左侧只优化标题、显示文案和分组 header，不再新增新的交互面；
- 右侧只优化 changes/details 的呈现模型和 badge 语义，不碰底层读取链路。

这样能在低风险下继续提升 IDEA 感，而不会把本轮范围拉回到底层重构。

## 设计细节

### 1. 左侧 branches panel

#### 1.1 选中 revision 标题收口

新增 `selectedRevisionTitle` 一类 helper，把：

- `refs/heads/main` -> `main`
- `refs/remotes/origin/main` -> `origin/main`
- `refs/tags/v1.0` -> `v1.0`

避免 header 继续显示原始 ref path。

#### 1.2 分组 header 补齐数量信息

把：

- `本地`
- `远端`
- `标签`

升级为带计数的组标题，例如：

- `本地 12`
- `远端 33`
- `标签 5`

这仍是轻量实现，但视觉信息密度更接近 IDEA branches 面板。

### 2. changes browser

把单行全路径改为“两层信息”：

- 主文本：文件名
- 次文本：父目录或 rename/copy 来源信息

例如：

- `WorkspaceGitIdeaLogView.swift`
- `DevHavenApp/` 或 `DevHavenApp/ · 从 OldName.swift 重命名`

这样更接近 IDE 中 changes browser 的扫描方式。

### 3. commit details refs badge

当前 refs 全部使用同一种中性 capsule。改为：

- branch/HEAD：accent 风格 badge
- tag：secondary/elevated badge

同时把 decorations 文本拆成更明确的两类：

- `branchReferenceItems`
- `tagReferenceItems`

继续在 App 层解析，不要求 Core 立即提供结构化 ref 模型。

## 测试策略

继续采用 App 源码契约测试：

1. branches panel 必须存在显示标题 helper 与 group count header；
2. changes browser 必须存在主文件名 / 次路径 subtitle helper；
3. details view 必须存在 branch/tag refs 分类与 badge style helper；
4. 跑 `WorkspaceGitIdeaLogViewTests` 红灯 -> 绿灯，再跑定向回归。

## 成功标准

1. 左侧 header 不再显示原始 `refs/...` 字符串；
2. 左侧本地 / 远端 / 标签分组具有数量语义；
3. changes browser 的文件列表更像 IDE 的“文件名 + 路径”；
4. details 的 refs badge 至少区分 branch/HEAD 与 tag 两种视觉语义；
5. 定向测试通过。
