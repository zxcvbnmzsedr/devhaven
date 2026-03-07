# 当前任务：整改终端工作区持久化写放大

- [x] 读取仓库约束、相关技能与现有保存链路
- [x] 明确问题根因与最小可行整改方案
- [x] 先写失败测试，锁定缓存/批量落盘行为
- [x] 实现 Rust 侧终端工作区内存缓存与延迟刷盘
- [x] 保持现有命令接口与跨窗口同步兼容
- [x] 跑针对性测试与构建验证
- [x] 追加复盘总结

## Review
- 已将终端工作区保存改为“内存更新 + debounce 异步刷盘”，避免每次 UI 微调都全量读改写 `terminal_workspaces.json`。
- 保持前端调用协议、同步事件与现有文件格式兼容；退出应用时会补一次同步 flush，降低 debounce 窗口内状态丢失风险。
- 新增两条 Rust 单测覆盖缓存状态机与摘要行为；`cargo test --manifest-path src-tauri/Cargo.toml` 与 `npm run build` 已通过。
