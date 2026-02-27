# Quick Command 重构任务清单

- [x] 现状审查：梳理 quick command 运行/停止/结束链路与竞态点
- [x] 后端状态机收敛：实现严格迁移、幂等 finish/stop、终态保护
- [x] 前端监听改造：接入 quick command snapshot + event，改为事件驱动
- [x] 停止闭环改造：软停 -> 超时硬停 -> 终态收口，避免状态漂移
- [x] 运行/停止竞态修复：处理 run 后立即 stop、重复 finish 等问题
- [x] 验证：类型检查与关键流程自测

---

## Review
- 采用“后端状态机 + 前端快照/事件对账”的执行模型，避免前端本地状态漂移。
- 运行与停止链路加入幂等保护（finish once）和 run->stop 启动竞态兜底。
- 补充会话关闭时的任务终态回写，减少 running/stopping 残留任务。
- 本地验证通过：`npm run build`、`cargo check --manifest-path src-tauri/Cargo.toml`。
