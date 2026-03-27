# Workspace Tool Window Stripe 位置对齐 IDEA 设计

## 背景

上一轮实现已经把 Workspace 的 Git 交互从 `Terminal / Git` 一级主模式切换改成了：

- terminal 主区
- bottom tool window 宿主
- Git 作为第一个底部工具窗

但用户在验收时指出，**逻辑对了，入口位置不对**。

当前实现把 Git 入口放在 `WorkspaceShellView` 底部的 `bottomToolWindowBar` 中，这会让工具窗入口和底部内容面板混在一起，仍然不像 IntelliJ IDEA。

## 用户确认后的正确层级

用户明确给出的正确结构是：

```text
[ 项目导航 ] | [ 左侧 stripe | 主内容区 ]
```

即：

1. 项目导航仍在最左侧，独立于主工作区 chrome；
2. stripe 不在整个窗口最左外缘；
3. stripe 也不在底部；
4. stripe 属于右侧 Workspace 主工作区壳的一部分；
5. Git 内容面板仍然是主内容区内部的 bottom tool window。

## 目标

本轮目标是把工具窗**入口位置**对齐到 IDEA 风格，而不改动已做对的底部工具窗主链：

1. 删除底部 `Git` 按钮栏；
2. 在 `WorkspaceChromeContainerView` 内新增左侧竖向 stripe；
3. stripe 只放一个 **Git icon-only** 按钮；
4. 右侧主内容仍由 `WorkspaceShellView` 承接；
5. `WorkspaceShellView` 保留 terminal 主区 + bottom tool window host，不再负责入口按钮。

## 方案比较

### 方案 A：stripe 放在整个 Workspace 最左外缘

结构：

```text
[ stripe ][ 项目导航 | 主内容区 ]
```

优点：

- 接近“整个窗口左边一条工具栏”的直觉。

缺点：

- 不符合当前产品已经存在的“项目导航独立于 Workspace 主内容”的层级；
- 用户已明确否定这一版。

### 方案 B：stripe 放在项目导航和主内容区之间

结构：

```text
[ 项目导航 ] | [ stripe | 主内容区 ]
```

优点：

- 与用户明确确认的结构完全一致；
- stripe 属于 Workspace 主工作区壳，语义最准确；
- 只需要重构 `WorkspaceChromeContainerView`，不必重新发明更外层窗口布局。

缺点：

- 需要把 chrome 容器从“只包 content”改成“stripe + content”双列布局。

### 方案 C：保留底部 bar，同时额外新增左侧 stripe

优点：

- 过渡期间用户不容易“找不到入口”。

缺点：

- 会形成两套入口；
- 与 IDEA 心智冲突；
- 入口职责继续重复。

## 选型

本轮采用 **方案 B**：

```text
[ 项目导航 ] | [ 左侧 stripe | 主内容区 ]
```

同时删除底部 `Git` 按钮栏，避免形成重复入口。

## 设计细节

### 1. 布局职责

#### `WorkspaceRootView`

- 继续负责：
  - 左侧项目导航
  - 右侧 Workspace chrome
- 不承担 stripe 细节

#### `WorkspaceChromeContainerView`

- 从“只包 content”升级为：
  - 左列：`WorkspaceToolWindowStripeView`
  - 分隔线
  - 右列：主内容

也就是说，stripe 是 chrome 容器的一部分，不是 root 最外层导航。

#### `WorkspaceShellView`

- 删除 `bottomToolWindowBar`
- 只保留：
  - terminal 主区
  - bottom tool window host

### 2. Stripe 按钮

首期只放一个按钮：

- `Git`

表现：

- **icon-only**
- 竖向排布
- 激活态高亮
- 点击后继续调用现有 `toggleWorkspaceToolWindow(.git)`

### 3. 保持不变的逻辑

这轮不改动以下主链：

- `workspaceToolWindowState`
- `workspaceFocusedArea`
- `show/toggle/hideWorkspaceToolWindow`
- `syncActiveWorkspaceToolWindowContext`
- `gitToolWindowContent`
- Quick Terminal / 非 Git 项目空态

### 4. 测试策略

需要更新的 source-contract 测试重点：

1. `WorkspaceChromeContainerViewTests`
   - 不再断言“chrome 只包 content”
   - 改为断言：
     - 存在 stripe
     - stripe 在 chrome 内
     - 不再承载 `WorkspaceModeSwitcherView`

2. `WorkspaceRootViewTests`
   - 继续保证 root 只做：
     - 项目导航
     - 右侧 chrome
   - 不把 stripe 提升到 root 最外层

3. `WorkspaceShellViewGitModeTests`
   - 删除 `bottomToolWindowBar` 相关锚点
   - 改为只要求：
     - terminal 主区
     - bottom tool window host
   - 入口按钮不再属于 shell

## 涉及文件

- `macos/Sources/DevHavenApp/WorkspaceChromeContainerView.swift`
- `macos/Sources/DevHavenApp/WorkspaceShellView.swift`
- `macos/Sources/DevHavenApp/WorkspaceRootView.swift`
- `macos/Tests/DevHavenAppTests/WorkspaceChromeContainerViewTests.swift`
- `macos/Tests/DevHavenAppTests/WorkspaceShellViewGitModeTests.swift`
- `macos/Tests/DevHavenAppTests/WorkspaceRootViewTests.swift`
- `AGENTS.md`
- `tasks/todo.md`

## 风险与边界

- 如果 stripe 被放到 `WorkspaceRootView` 最外层，就会重新把“项目导航”和“工具窗入口”混成同一层，偏离用户明确确认的结构。
- 如果保留底部 bar，会形成两套入口，继续不像 IDEA。
- 本轮只调整入口位置，不扩展第二个工具窗，也不补 stripe 文本标签。
