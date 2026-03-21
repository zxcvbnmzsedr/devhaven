# Lessons
- 发布 tag 前先核对仓库既有版本标签命名（如 `v3.0.0` vs `3.0.0`）与远端现状，避免在错误命名上新增 tag 后再返工。
- 发布矩阵 job 不要同时承担 release 元数据创建/最终化职责；应先单独准备 release，再让各架构 job 仅上传资产，避免 stale draft release 把同 tag 发布流程炸掉。
