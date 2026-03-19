# DevHaven Swift Ghostty Bootstrap 设计

## 目标

在当前 Swift checkout 仍未接入 `GhosttyKit` 二进制 target 的前提下，先把 Ghostty 启动前必须的资源解析与环境变量注入从 App 入口里抽离出来，形成可测试、可复用、可诊断的 bootstrap 层，为后续真正接入 runtime / surface host 做准备。

## 本轮范围

- 新增 `DevHavenCore` 侧 Ghostty bootstrap 模块。
- 统一解析 Ghostty 资源目录与环境补丁。
- 明确 `GhosttyKit.xcframework` 的最小完整性契约，并补 repo 内 `setup-ghostty-framework.sh`。
- 在 `DevHavenApp` 启动时执行 bootstrap，并把状态投影到 workspace placeholder。
- 补充单元测试覆盖资源解析、环境补丁和缺资源诊断。

## 明确不做

- 本轮不接 `GhosttyKit.xcframework`。
- 本轮不新增 `ghostty_init(...)` 真调用。
- 本轮不实现 pane/tab/split 原生终端。
- 本轮不修改 `terminal_workspaces.json` 或 workspace runtime 真相源。

## 设计

### 1. 分层

- `GhosttyBootstrap`：唯一对外入口，输入环境和候选资源目录，输出 bootstrap 结果。
- `GhosttyBootstrapResult`：包含状态、最终资源目录、环境补丁和诊断消息。
- `GhosttyEnvironmentPatch`：承载应写入进程环境的键值对。

### 2. 资源目录优先级

1. 已存在的 `GHOSTTY_RESOURCES_DIR`
2. app bundle / caller 提供的 bundled resources
3. 本地 vendor fallback
4. 若都不存在，则返回 `missingResources`

### 3. 环境补丁

在成功解析资源目录后，补：

- `GHOSTTY_RESOURCES_DIR`
- `TERM=xterm-ghostty`
- `TERM_PROGRAM=ghostty`
- `XDG_DATA_DIRS += <resourcesParent>`
- `MANPATH += <resourcesParent>/man`

若资源缺失，则只保留基础终端标识或直接不注入 Ghostty 资源相关变量，由结果状态决定 UI 提示。

### 4. framework 完整性与 setup 契约

- `GhosttyKit.xcframework` 至少满足：根目录 `Info.plist` 存在，且至少一个 slice 下有真正的 framework/library payload，而不只是 `Headers`。
- repo 内新增 `macos/scripts/setup-ghostty-framework.sh`，负责把 Ghostty 源码 checkout 的 framework / resources 同步到 `macos/Vendor`。
- bootstrap 结果在 runtime 未就绪时给出可执行 setup command，减少“知道不完整，但不知道怎么补”的断层。

### 5. App 接线

`DevHavenApp` 启动时执行 bootstrap，并把结果保存在轻量 app context 中；`WorkspacePlaceholderView` 显示当前 Ghostty bootstrap 状态，帮助后续排查“资源没准备好”和“只是 workspace 还没接 runtime”的区别。

## 验证

- `DevHavenCoreTests`：资源目录解析、环境补丁合并、缺资源状态。
- shell 验证：对当前 `macos/Vendor` 运行 `--verify-only`，以及对临时伪造输出目录运行 `--skip-build` 正向验证。
- `swift test` 至少覆盖新增测试与受影响现有测试。
