# DevHaven Swift 工作区入口设计

## 背景

当前 `macos/` 原生子工程已具备项目列表、详情抽屉、设置、回收站与自动化只读骨架，但终端工作区尚未迁入主界面主路径。用户已经明确要求“像之前 Tauri 那样进入工作区”，并优先希望恢复一条可用的命令行进入路径。

## 方案对比

### 方案 A：直接补完整内置 Ghostty 终端
- 优点：最终形态最接近目标
- 缺点：当前源码里缺少可复用的 workspace/runtime/source，范围远超本轮；高风险且无法在当前回合安全完成

### 方案 B：双击进入原生 workspace 页面，页面内提供“在系统 Terminal 打开项目”
- 优点：最小改动即可恢复“进入工作区”的主路径；对用户立即可用；不伪装成已经有内置终端
- 缺点：命令行仍依赖系统 Terminal，而不是 App 内嵌终端

### 方案 C：单击直接切到 workspace，详情改按钮触发
- 优点：更像 IDE 主路径
- 缺点：会打破当前已经落地的“单击看详情”交互，回归风险更高

## 结论

本轮采用 **方案 B**：

1. 主列表 **单击** 项目继续打开详情抽屉
2. 主列表 **双击** 项目进入原生 workspace 页面
3. workspace 页面展示当前项目、Ghostty bootstrap 状态与阶段说明
4. workspace 页面提供 **“在 Terminal 打开”** 与 **“返回项目列表”** 两个明确动作
5. 系统 Terminal 入口优先使用 `/usr/bin/open -a Terminal <projectPath>`，失败时回传错误提示到现有 `errorMessage`

## 组件与数据流

- `NativeAppViewModel`
  - 新增 workspace 选中状态与进入/退出动作
  - 负责系统 Terminal 打开动作与错误上抛
- `AppRootView`
  - 在中心区域根据状态切换 `MainContentView` / `WorkspacePlaceholderView`
- `MainContentView`
  - 卡片 / 列表支持双击进入 workspace
  - 保持单击详情抽屉不变
- `WorkspacePlaceholderView`
  - 从“孤立预留文件”升级为真正挂载的 workspace 页面
  - 补按钮回调：打开 Terminal / 返回列表 / 打开详情

## 测试策略

1. 先补 `NativeAppViewModel` 行为测试：进入 workspace、退出 workspace、打开 Terminal 命令构造
2. 再补 `MainContentView`/相关交互的最小单元覆盖（若当前测试基础不足，则把主要行为锁在 view model）
3. 跑定向测试、全量测试、`swift build` 与 `git diff --check`
