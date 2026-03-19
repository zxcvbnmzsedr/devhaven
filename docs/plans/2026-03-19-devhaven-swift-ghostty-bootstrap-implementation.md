# DevHaven Swift Ghostty Bootstrap Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 把 Ghostty 资源解析、framework 完整性判断与 setup 指引收口成可测试 bootstrap 层，并把状态接到当前原生 workspace 占位区。

**Architecture:** 在 `DevHavenCore` 新增纯 Swift bootstrap 模块，不直接依赖 GhosttyKit；`DevHavenApp` 只消费 bootstrap 结果并展示状态。repo 内额外补一个 `macos/scripts/setup-ghostty-framework.sh`，先把 vendor framework/resources 的真相和修复入口固定下来，后续再接 runtime/surface。

**Tech Stack:** Swift Package Manager, Swift 6, XCTest, SwiftUI(macOS)

---

### Task 1: 建 bootstrap 测试

**Files:**
- Create: `macos/Tests/DevHavenCoreTests/GhosttyBootstrapTests.swift`

**Step 1: 写失败测试**
- 资源目录存在时，返回 `ready`，并补齐 `GHOSTTY_RESOURCES_DIR/TERM/TERM_PROGRAM/XDG_DATA_DIRS/MANPATH`
- 已有 `GHOSTTY_RESOURCES_DIR` 时，优先保留显式值
- 无资源时，返回 `missingResources`

**Step 2: 运行测试确认失败**
- Run: `swift test --package-path macos --filter GhosttyBootstrapTests`

### Task 2: 实现 DevHavenCore bootstrap

**Files:**
- Create: `macos/Sources/DevHavenCore/Terminal/GhosttyBootstrap.swift`

**Step 1: 写最小实现**
- 定义结果模型、状态枚举、环境补丁和 bootstrap 入口
- 使用可注入文件存在性判断，保证测试可控

**Step 2: 运行测试确认通过**
- Run: `swift test --package-path macos --filter GhosttyBootstrapTests`

### Task 3: 接入 App 与占位视图

**Files:**
- Modify: `macos/Sources/DevHavenApp/DevHavenApp.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspacePlaceholderView.swift`

**Step 1: App 启动执行 bootstrap**
- 保存 bootstrap 结果并下发到 workspace placeholder

**Step 2: 占位视图显示 Ghostty 状态**
- 区分“资源已准备好但 workspace 未接入”和“资源尚未准备好”

### Task 4: 文档与约束同步

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`

**Step 1: 更新 AGENTS 的模块职责**
- 说明新增 bootstrap 模块与当前阶段边界

**Step 2: 更新 todo review**
- 记录测试与构建证据

### Task 5: 补 vendor setup/verify 脚本

**Files:**
- Create: `macos/scripts/setup-ghostty-framework.sh`

**Step 1: 支持 verify-only / skip-build**
- `--verify-only`：只检查 `macos/Vendor` 是否满足最小完整性
- `--skip-build`：允许在临时伪造产物上验证复制链，而不依赖真实 zig build

**Step 2: 补正反向验证**
- 负向：对当前仓库 `macos/Vendor` 运行 `--verify-only`，应暴露当前 framework 不完整
- 正向：用临时目录伪造最小 Ghostty 输出，运行 `--skip-build --vendor-dir <temp>` 应成功
