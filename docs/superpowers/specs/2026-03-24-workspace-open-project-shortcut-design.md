# Workspace 打开项目快捷键与弹窗焦点设计

## 目标
- 在 workspace 中新增“打开项目”菜单命令，默认快捷键为 `⌘K`。
- 允许用户在设置页配置该快捷键。
- 修复“打开项目”弹窗默认焦点落到关闭按钮的问题，改为默认聚焦搜索输入框。

## 设计

### 1. 配置模型
- 在 `AppSettings` 中新增 `workspaceOpenProjectShortcut` 字段。
- 该字段只服务于应用菜单快捷键，固定包含 `⌘`，允许额外组合 `⇧ / ⌥ / ⌃`，并配置一个主按键。
- 老配置缺失该字段时，回退到默认值 `⌘K`。

### 2. 命令路由
- 新增 `WorkspaceProjectCommands.swift`。
- 命令层通过 `FocusedValue` 获取当前 scene 的“打开项目选择器”动作。
- `WorkspaceShellView` 负责提供该动作并持有 project picker 展示态；Core ViewModel 不承担这类壳层 UI 状态。
- 命令的快捷键由 `AppSettings.workspaceOpenProjectShortcut` 动态决定。

### 3. 设置页
- 在设置页常规页新增“快捷键”卡片。
- 暂只暴露一条配置：`打开项目`。
- 通过主按键选择 + 附加修饰键开关组合成菜单快捷键，并展示预览文案。

### 4. 焦点行为
- `WorkspaceProjectPickerView` 用 `@FocusState` 显式控制搜索框焦点。
- 弹窗出现时异步请求搜索框成为第一焦点。
- “关闭”按钮显式 `.focusable(false)`，避免抢走默认 focus。

## 边界
- 本轮不做通用 keymap 系统。
- 本轮不支持系统级全局热键。
- 本轮不引入复杂的按键录制器，只覆盖 DevHaven 应用菜单快捷键。
