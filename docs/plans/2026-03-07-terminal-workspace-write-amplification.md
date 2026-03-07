# 终端工作区持久化写放大整改计划

## 目标

- 降低 `terminal_workspaces.json` 的全量读改写频率。
- 保持现有前端调用方式、命令接口、同步事件不变。
- 优先做最小侵入整改，先解决热路径 I/O 放大。

## 根因

- 前端在工作区状态变化后 800ms 自动保存一次。
- 后端每次保存单个项目工作区时，都会读取整份 `terminal_workspaces.json`，修改一个 entry，再整份原子写回。
- 删除、摘要读取、重新加载同样依赖整份文件。

## 方案

### Task 1: 为终端工作区引入进程内缓存

**Files**
- Modify: `src-tauri/src/storage.rs`

**Step 1: 写失败测试**

- 为新的缓存状态机补测试：
  - 多次更新同一路径时，刷盘快照只保留最新值。
  - 删除后摘要与读取结果同步变化。

**Step 2: 运行测试确认失败**

- Run: `cargo test --manifest-path src-tauri/Cargo.toml terminal_workspace_store -- --nocapture`

**Step 3: 实现最小代码**

- 引入全局缓存状态：
  - 已加载标记
  - 当前 `TerminalWorkspacesFile`
  - dirty revision
  - flush 调度状态

### Task 2: 把保存改成“写内存 + 延迟刷盘”

**Files**
- Modify: `src-tauri/src/storage.rs`

**Step 1: 实现行为**

- `save_terminal_workspace`：
  - 只更新缓存
  - 标记 dirty
  - 调度 debounce flush
- `delete_terminal_workspace`：
  - 只更新缓存
  - 标记 dirty
  - 调度 debounce flush

**Step 2: 刷盘策略**

- debounce 200~300ms
- 写盘前复制快照，避免长时间持锁
- flush 完成后根据 revision 判断是否需要继续刷最新状态

### Task 3: 让读取/摘要直接走缓存

**Files**
- Modify: `src-tauri/src/storage.rs`

**Step 1: 兼容读取**

- `load_terminal_workspace` 优先读缓存
- `list_terminal_workspace_summaries` 优先读缓存

**Step 2: 保持文件格式兼容**

- 仍写回原有 `TerminalWorkspacesFile`
- 不修改前端 payload 结构

### Task 4: 验证

**Files**
- Test: `src-tauri/src/storage.rs`

**Step 1: 跑针对性测试**

- Run: `cargo test --manifest-path src-tauri/Cargo.toml terminal_workspace_store -- --nocapture`

**Step 2: 跑更宽验证**

- Run: `cargo test --manifest-path src-tauri/Cargo.toml`
- Run: `npm run build`

## 风险点

- 进程异常退出时，最后一个 debounce 窗口内的工作区状态可能尚未刷盘。
- 需要避免 flush 线程与新的 save/delete 竞争导致脏数据被覆盖。

## 取舍

- 当前优先解决 I/O 放大，不在这次引入单项目文件拆分。
- 当前保持同步事件即时发送，不把事件改成“刷盘后再广播”。
