# DevHaven Swift 原生终端首开体验对齐 Ghostty / Supacode 实施计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让 Swift 原生版在首次打开项目进入 workspace 时，对齐 Ghostty / Supacode 的终端 owner 与首屏呈现：pane 先可见、当前项目 terminal state 可复用、active project 切换后立即触发 selected pane warm-up。

**Architecture:** 在 `DevHavenApp` 新增项目级 `WorkspaceTerminalSessionStore`，再由 `WorkspaceShellView` 持有 `projectPath -> store` registry，把现有 `WorkspaceSurfaceRegistry` 从 `WorkspaceHostView` 外提到 project-level shell owner；`WorkspaceShellView` 负责 active project warm-up，`GhosttySurfaceHost` 补稳定的“正在启动 shell”展示而不解析 prompt 文本。

**Tech Stack:** Swift 6、Observation、SwiftUI、XCTest、Ghostty shared runtime

---

### Task 1: 先补 App 层 terminal owner 失败测试

**Files:**
- Create: `macos/Tests/DevHavenAppTests/WorkspaceTerminalSessionStoreTests.swift`

**Steps:**
1. 写测试：同一个 `WorkspacePaneState` 多次取 model，必须返回同一个 `GhosttySurfaceHostModel`。
2. 写测试：`syncRetainedPaneIDs(...)` 只在 pane 真正移除时才释放旧 model。
3. 写测试：`warmSelectedPane(...)` 只预热当前 selected pane，不会顺手创建其它 pane 的 host model。
4. 跑 `swift test --package-path macos --filter WorkspaceTerminalSessionStoreTests`，确认先红。

### Task 2: 落 `WorkspaceTerminalSessionStore`

**Files:**
- Create: `macos/Sources/DevHavenApp/WorkspaceTerminalSessionStore.swift`

**Steps:**
1. 新增 `WorkspaceTerminalSessionStore`，吸收 `WorkspaceSurfaceRegistry` 的稳定 model 复用能力。
2. 给 store 增加 `model(for:)`、`syncRetainedPaneIDs(...)`、`releaseAll()`、`warmSelectedPane(...)`。
3. 让 warm-up 只触发当前 selected pane 的 model acquire。
4. 跑 `swift test --package-path macos --filter WorkspaceTerminalSessionStoreTests`，确认转绿。

### Task 3: 让 `WorkspaceShellView` 持有 project-level store registry 并触发 warm-up

**Files:**
- Modify: `macos/Sources/DevHavenApp/WorkspaceShellView.swift`
- Modify: `macos/Sources/DevHavenApp/WorkspaceHostView.swift`

**Steps:**
1. 在 `WorkspaceShellView.swift` 新增 `@StateObject` registry，按 `projectPath` 发放 `WorkspaceTerminalSessionStore`。
2. 调整 `WorkspaceHostView.swift`，把对应 store 作为依赖传入，而不是内部自己 new `WorkspaceSurfaceRegistry`。
3. 在 `WorkspaceShellView` 的 `onAppear` / activeProject change 上对 selected pane 做 warm-up。
4. 把 `retainedPaneIDs` 同步与释放逻辑切到 session-owned store。
5. 跑 `swift build --package-path macos`，确认编译通过。

### Task 4: 补稳定的“正在启动 shell”展示

**Files:**
- Create: `macos/Tests/DevHavenAppTests/WorkspaceTerminalStartupPresentationPolicyTests.swift`
- Create: `macos/Sources/DevHavenApp/WorkspaceTerminalStartupPresentationPolicy.swift`
- Modify: `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceHost.swift`

**Steps:**
1. 先写纯策略测试，锁定以下规则：
   - 初始化失败时不显示启动 overlay；
   - 进程已退出时不显示启动 overlay；
   - 处于 starting / warming 且没有失败时显示启动 overlay。
2. 新增 `WorkspaceTerminalStartupPresentationPolicy.swift` 收口这条展示逻辑。
3. 修改 `GhosttySurfaceHost.swift`，在正常 terminal view 上叠一层轻量“正在启动 shell...”提示，不做 prompt 文本解析。
4. 跑 `swift test --package-path macos --filter WorkspaceTerminalStartupPresentationPolicyTests`。

### Task 5: 文档与验证闭环

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`
- Modify: `tasks/lessons.md`

**Steps:**
1. 更新 `AGENTS.md`，明确 project-level terminal owner 已从 `WorkspaceHostView` 内部 state 抬到 `WorkspaceShellView` registry。
2. 在 `tasks/todo.md` 回填本轮 Review，明确直接原因、设计诱因、实施方案和验证证据。
3. 在 `tasks/lessons.md` 记录“设计里涉及跨 target owner 时，先核对 SwiftPM target 边界”这条教训。
4. 跑 `swift test --package-path macos`。
5. 跑 `swift build --package-path macos`。
6. 跑 `git diff --check`。
