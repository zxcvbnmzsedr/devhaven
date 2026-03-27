# DevHaven 复刻 IDEA Commit Tool Window 设计

> 确认日期：2026-03-25  
> 用户决策：选择 **A：全量 1:1 复刻 IDEA Commit Tool Window**，并明确要求“不是先做 MVP，而是一次性朝终态架构铺开实现”。

---

## 1. 背景

DevHaven 当前已经基本对齐了 IDEA 风格的 Workspace / Git Log / Tool Window 外壳，但提交链路仍停留在较轻量的 `WorkspaceGitChangesView`：

- `Git` 工具窗内的一个二级 section
- 明确暴露 `已暂存 / 未暂存 / 未跟踪`
- 只有基础 `commit / amend / stage / unstage / discard`
- 缺少独立的 commit 工作台、inclusion model、diff preview、commit options、checks/progress、多执行器

而 IntelliJ Community 的真实结构不是“Git 页里的提交表单”，而是：

- 独立的 **Commit Tool Window**
- 以 **Changes Browser + Inclusion Model** 为主心智
- 提交消息、选项、检查、进度、post-commit 行为都围绕同一个工作台展开

因此，如果目标是“复刻 IDEA 的 commit 面板功能”，正确方向不是继续堆胖 `WorkspaceGitChangesView`，而是：

1. 新增独立 `Commit` tool window  
2. 让 `Git` tool window 退出提交职责  
3. 把用户心智从 `staged/unstaged` 切换为 `included/excluded`

---

## 2. 目标

### 2.1 产品目标

在 DevHaven Workspace 中新增一个长期驻留、非模态、像 IDEA 一样的 **Commit Tool Window**，支持：

- Local Changes tree
- inclusion checkbox
- diff preview
- commit message editor
- amend / author / sign-off / commit and push 等 commit options
- commit checks / progress / error / success feedback
- 提交完成后的 refresh 与状态恢复

### 2.2 架构目标

- `Commit` 与 `Git` 分离成两个独立 tool window
- `Commit` 有单独的 Core 模型、ViewModel、Service 链路
- `Git` 工具窗移除 `.changes` section，只保留：
  - `log`
  - `console`
  - `branches`
  - `operations`
- App 层与 Core 层都改为围绕 **Commit 工作流** 组织，而不是继续围绕 staged/unstaged 页面组织

### 2.3 非目标

本轮不要求完全复制 IntelliJ 所有历史插件扩展点和 changelist 生态，但必须在架构上为以下能力留扩展位：

- partial commit / hunk 级 inclusion
- edited commit / amend specific commit
- pre/post commit checks 扩展
- 更多 commit executors

---

## 3. 当前问题与根因

### 3.1 直接问题

`WorkspaceGitChangesView` 当前承担的是“Git 页中的一个提交子页”，而不是“Commit 工具窗”。这导致：

- 提交与日志/分支/操作混在一套 section 模型里
- 提交语义绑定到 staged/unstaged，而不是 inclusion
- diff preview 只能作为补充功能，而不是主链的一部分
- commit options / progress / checks 没有稳定容器

### 3.2 设计层诱因

1. **职责混叠**  
   `WorkspaceGitViewModel` 同时负责 log、changes、branches、operations，提交工作流没有独立根状态。

2. **状态真相源偏差**  
   当前 Changes 页以 Git index/staging 为主心智，而 IDEA 的 commit 面板以 inclusion 为主心智。

3. **工具窗层级错误**  
   提交入口不应只是 Git 工具窗里的一个 section，而应是与 Git 并列的独立 tool window。

---

## 4. 方案对比

### 方案 A：继续增强 `Git > Changes`

**结论：不采用**

原因：
- 结构最省，但产品层级错误
- 只会得到“更胖的 Changes 页”
- 后续仍要返工拆成独立 Commit 工具窗

### 方案 B：Git 工具窗内新增顶层 `Commit` tab

**结论：不采用**

原因：
- 比方案 A 好，但仍然不是 IDEA 的真实心智
- Commit 依然属于 Git，而不是 Workspace 的独立工作态

### 方案 C：新增独立 `Commit Tool Window`

**结论：采用**

原因：
- 唯一真正与 IDEA 心智一致
- 允许提交工作流与日志/分支/操作彻底分离
- 能自然承接 inclusion、diff preview、checks、options、多执行器等完整工作流

---

## 5. 目标信息架构

```text
Workspace
├─ Project Sidebar
└─ Workspace Chrome
   ├─ Left Stripe
   │  ├─ Commit
   │  └─ Git
   └─ Main Content Area
      ├─ Terminal
      └─ Bottom Tool Window Host
         ├─ Commit Tool Window
         │  ├─ Changes Browser
         │  ├─ Diff Preview
         │  └─ Commit Panel
         └─ Git Tool Window
            ├─ Log
            ├─ Console
            ├─ Branches
            └─ Operations
```

关键调整：

- `WorkspaceToolWindowKind`：从仅 `.git` 扩展为 `.commit` + `.git`
- `WorkspaceGitSection`：移除 `.changes`
- 新增 `WorkspaceCommitRootView`
- 提交入口从 Git 内部迁移到独立 tool window stripe

---

## 6. Commit Tool Window 结构设计

### 6.1 Changes Browser

职责：

- 展示 local changes tree
- inclusion checkbox 选择本次提交范围
- 支持目录/文件层级
- 显示 rename / copy / delete / untracked / conflict 状态
- 支持 selection 与 diff preview 联动

产品原则：

- 不再把 `已暂存 / 未暂存 / 未跟踪` 当主产品模型
- 用户主心智变为：
  - 我有哪些本地变更
  - 哪些要纳入本次提交

### 6.2 Diff Preview

职责：

- 展示当前选中 change 的文件级 diff
- 支持大 diff 截断、binary 占位、加载态
- 支持 future：在编辑器或独立窗口打开

### 6.3 Commit Panel

职责：

- 展示 inclusion legend / 状态统计
- 提供 commit message editor
- 提供 commit options
- 提供 commit actions（Commit / Commit and Push）
- 提供 checks / progress / error / success surface

---

## 7. 核心领域模型调整

### 7.1 Tool Window 层

- `WorkspaceToolWindowKind.commit`
- `WorkspaceToolWindowKind.git`
- `WorkspaceFocusedArea.toolWindow(.commit/.git)`

### 7.2 Commit 根状态

新增独立 Commit 域，而不是继续塞回 `WorkspaceGitViewModel`。

建议新增：

- `WorkspaceCommitModels.swift`
- `WorkspaceCommitViewModel.swift`
- `NativeGitCommitWorkflowService.swift`（或同级 commit workflow service）

核心状态建议包括：

- `WorkspaceCommitRepositoryContext`
- `WorkspaceCommitChangesSnapshot`
- `WorkspaceCommitChangeNode`
- `WorkspaceCommitInclusionState`
- `WorkspaceCommitDraft`
- `WorkspaceCommitOptionsState`
- `WorkspaceCommitCheckState`
- `WorkspaceCommitExecutionState`
- `WorkspaceCommitDiffPreviewState`

### 7.3 staged → inclusion 迁移原则

UI/产品真相源改为 inclusion。

底层执行可以仍借助 Git staging/index，但必须满足：

- UI 不直接暴露 staged/unstaged 作为主分类
- inclusion 变更由 Commit workflow service 统一映射到执行层
- 后续如需 partial commit，不必再重写一套产品模型

---

## 8. 关键交互流

### 8.1 普通提交

1. 打开 `Commit` 工具窗
2. 浏览 local changes tree
3. 勾选 inclusion
4. 查看 diff preview
5. 输入 commit message
6. 点击 `Commit`
7. 在原位看到 checks / progress
8. 成功后 refresh tree、清理 draft、保留工作台

### 8.2 Commit and Push

1. 与普通提交相同
2. 执行器切换为 `Commit and Push`
3. commit 成功后继续 push
4. 若 push 失败，要清晰区分“commit 已成功，push 失败”

### 8.3 Amend

1. 打开 amend 选项
2. 自动加载上次 commit message
3. 用户决定是否修改 message
4. inclusion 决定本次 amend 附加哪些变更
5. 执行后刷新 local changes

### 8.4 阻塞场景

- unresolved conflicts
- hook 失败
- empty message
- no included changes
- push 失败

这些都必须通过 Commit Panel 的统一反馈层呈现，不能散落成多处 toast / alert。

---

## 9. 实现分期

### Phase 0：结构对齐

- 新增独立 Commit tool window
- Git 工具窗移除 `.changes`
- 建立 Commit / Git stripe 双入口

### Phase 1：Commit 主链闭环

- changes tree
- inclusion
- diff preview
- commit message
- commit / commit and push
- amend
- progress / error

### Phase 2：IDEA 感增强

- status legend
- commit options panel
- layout persistence
- selection/expand 恢复
- 更完整的 progress / checks surface

### Phase 3：高级 parity

- partial commit / hunk inclusion
- edited commit / amend specific commit
- 更丰富的 checks / executors / 扩展位

---

## 10. 风险与应对

### 风险 1：staged 语义与 inclusion 语义不一致

应对：
- UI 层统一切到 inclusion
- Service 层做 staged/inclusion 桥接

### 风险 2：Commit 与 Git 状态继续耦合

应对：
- Commit 独立 ViewModel / Models / Service
- Git 退出提交职责

### 风险 3：diff preview 复杂度高

应对：
- 首轮仅保文件级 diff
- 大 diff 截断
- binary/unsupported 类型显式占位

### 风险 4：worktree / repository 边界不清

应对：
- 执行真相源使用 selected execution worktree
- repository metadata 仍可从 root repository 读取

---

## 11. 设计结论

本轮的产品决策是：

1. **Commit 必须成为独立 Tool Window**
2. **Git Tool Window 不再承担 Changes/Commit 主链**
3. **Commit 面板的用户心智必须切换到 inclusion model**
4. **提交、diff、options、checks、progress 必须收口为一个统一工作台**

如果目标是“复刻 IDEA 的 commit 面板”，这是唯一不会在后续返工的方向。
