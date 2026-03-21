# DevHaven 单命令开发入口设计

**日期：** 2026-03-21  
**目标：** 提供一个接近 `pnpm dev` 体验的根目录开发命令，让本机开发时可以用一条命令完成 vendor 校验、日志观测与原生应用启动。

---

## 背景

当前仓库已经收口为纯 macOS 原生主线，开发入口主要是：

- `swift test --package-path macos`
- `swift run --package-path macos DevHavenApp`
- `bash macos/scripts/build-native-app.sh --release`

但直接执行 `swift run` 时，应用级诊断日志主要进入 macOS unified log，而不是普通 stdout/stderr。结果是“应用能启动，但不像 `pnpm dev` 那样天然能在当前终端里看到有效日志”。

---

## 方案比较

### 方案 A：新增根目录 `./dev` 包装脚本（推荐）

由仓库根目录提供一个可执行脚本，按顺序完成：

1. 校验 `macos/Vendor/` 是否完整；
2. 后台启动 `log stream`；
3. 前台执行 `swift run --package-path macos DevHavenApp`；
4. 在应用退出时自动清理后台日志进程。

**优点**
- 最接近 `pnpm dev` 的一条命令体验；
- 不引入额外工具依赖；
- 可以继续复用现有 `setup-ghostty-framework.sh` 与 SwiftPM 主线；
- 容易为后续扩展调试参数保留入口。

**缺点**
- 需要自己管理 `log stream` 子进程生命周期；
- 需要为脚本增加最小可测试接口，避免只能靠人工试跑。

### 方案 B：新增 `Makefile` / `make dev`

通过 `Makefile` 包装现有命令。

**优点**
- 命令短；
- 许多开发者熟悉 `make dev`。

**缺点**
- 仓库当前没有 `Makefile` 传统；
- 仍要在 Makefile 里处理 `log stream` trap，复杂度并不会更低；
- 用户明确要“封装成一个命令”，根目录脚本更直接。

### 方案 C：只文档化“两终端方案”

保留现状，只在 README 里说明“一个终端看 log，一个终端跑 swift run”。

**优点**
- 零实现成本。

**缺点**
- 没有解决真实问题；
- 体验仍明显差于 `pnpm dev`；
- 用户已经明确希望封成一条命令。

---

## 最终设计

采用 **方案 A**，新增仓库根目录 `./dev`，作为 DevHaven 原生开发入口。

### 命令职责

- 默认执行 vendor 完整性校验：`bash macos/scripts/setup-ghostty-framework.sh --verify-only`
- 默认同时观测：
  - `subsystem == "DevHavenNative"`
  - `subsystem == "com.mitchellh.ghostty"`
- 默认启动命令：`swift run --package-path macos DevHavenApp`

### 支持的最小参数

- `--help`：显示帮助
- `--dry-run`：只打印将要执行的命令，不真正启动
- `--no-log`：只启动应用，不启动 `log stream`
- `--logs all|app|ghostty`：控制日志 predicate 范围

### 关键实现点

1. 脚本内部先 `cd` 到仓库根目录，避免调用目录变化导致相对路径失效。
2. `log stream` 以后台子进程运行，记录 PID。
3. 用 `trap` 在 `EXIT/INT/TERM` 时统一回收日志子进程。
4. 为了可测试性，`--dry-run` 必须打印稳定输出，供脚本测试断言。

---

## 验证策略

### 自动化

新增一个 shell 级验证脚本，覆盖：

- `./dev --help`
- `./dev --dry-run`
- `./dev --dry-run --logs app`
- `./dev --dry-run --no-log`

### 人工验证

执行 `./dev`，确认：

1. 能先看到 unified log 流；
2. 能启动 DevHaven App；
3. 退出应用后不会遗留后台 `log stream` 进程。

---

## 边界

- 本轮只封装“本机开发态启动”，不改 release / 打包链路。
- 本轮不引入 `Makefile`、`justfile`、npm script 等额外入口，避免重新制造多套真相源。
