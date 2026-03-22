# DevHaven 主界面初始焦点修复设计

## 背景
当前 DevHaven 启动或回到主界面时，没有显式定义“默认焦点应该落在哪里”。在这种情况下，AppKit / SwiftUI 会退回默认 key-view 顺序，于是左侧边栏里最先出现的可聚焦 chrome 控件会抢到焦点。用户现场反馈看到焦点落在“目录”标题右侧的按钮上，而不是主界面的搜索框。

## 目标
1. DevHaven 进入主界面时，默认把键盘焦点放到顶部“搜索项目...”输入框；
2. 避免左侧边栏的目录操作按钮在启动时先于主输入入口抢焦点；
3. 保持修改最小，不引入新的窗口级焦点基础设施；
4. 为后续主界面其它显式焦点策略保留扩展空间。

## 非目标
- 不重构整个侧边栏的键盘导航模型；
- 不在本次修复中为所有按钮统一重写 focus policy；
- 不修改工作区终端 / 详情面板 / sheet 的焦点语义。

## 方案比较

### 方案 A：只给目录按钮加 `.focusable(false)`
- 优点：改动最小；
- 缺点：只是把焦点顺延给别的控件，不能保证落到搜索框。

### 方案 B：显式把主界面初始焦点放到搜索框，并避免目录按钮抢焦点（推荐）
- 做法：
  1. 在 `MainContentView` 为搜索框引入显式焦点状态；
  2. 主界面首次出现时主动请求把焦点放到搜索框；
  3. 给“目录操作”按钮加 `.focusable(false)`，避免它继续作为默认焦点竞争者。
- 优点：符合用户预期，焦点语义清晰；
- 缺点：需要补一层很轻量的焦点状态管理与测试。

### 方案 C：完全依赖窗口级 `makeFirstResponder(...)`
- 优点：理论上最直接；
- 缺点：需要桥接到底层 AppKit 搜索框实例，侵入性高，超出本次最小修复范围。

## 最终设计
采用 **方案 B**。

### 1. 主界面声明显式焦点字段
在 `MainContentView` 内新增轻量焦点枚举，例如 `FocusableField.search`，并用 `@FocusState` 绑定到顶部搜索框。

### 2. 主界面出现时请求搜索框焦点
在 `MainContentView` 中新增最小焦点请求逻辑：当主界面可见时，异步把焦点设为 `.search`。这样即使窗口刚完成激活，也会在下一轮主线程循环把第一输入目标落到搜索框，而不是把决定权交给默认 key-view 顺序。

### 3. 避免目录按钮参与默认焦点竞争
给 `ProjectSidebarView` 中“目录操作”菜单按钮增加 `.focusable(false)`。这不会改变鼠标点击行为，但可以避免它在没有显式焦点策略时成为默认 first responder 候选。

## 影响范围
- `macos/Sources/DevHavenApp/MainContentView.swift`
- `macos/Sources/DevHavenApp/ProjectSidebarView.swift`
- `macos/Tests/DevHavenAppTests/MainContentViewTests.swift`
- 视情况补一条 `ProjectSidebarView` 源码级回归测试
- `tasks/todo.md`

## 风险与控制
### 风险 1：搜索框焦点请求时机太早
控制：使用异步主线程请求，而不是在同步 body 构建阶段硬塞焦点。

### 风险 2：只靠搜索框 focus state 仍被边栏按钮抢走
控制：同时给“目录操作”按钮加 `.focusable(false)`，降低默认竞争。

### 风险 3：后续主界面新增输入控件后再次出现焦点语义冲突
控制：把焦点入口收口到 `MainContentView`，后续若产品要求变化，只改这一处策略即可。

## 验证策略
1. 先写失败测试，要求 `MainContentView` 对搜索框存在显式 focus state 绑定；
2. 再写失败测试，要求 `ProjectSidebarView` 的目录操作按钮不参与默认焦点；
3. 实现最小修复后运行定向测试；
4. 最后跑相关构建 / 测试命令确认没有引入回归。
