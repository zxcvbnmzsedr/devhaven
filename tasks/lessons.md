# Lessons Learned

- 当用户已经明确要求“切到 Swift 原生打包主线”时，不要只删 Tauri 打包入口；要继续检查 release workflow、版本真相源、README、AGENTS 和设置页文案是否仍残留旧栈语义。
- 当用户进一步明确要求“源文件都删除”时，必须连同旧的 React / Vite / Tauri / Rust 兼容源码、Node 构建配置、历史实施文档与旧 release note 一起清理，避免仓库结构和产品口径继续分裂。
- 原生打包脚本不应依赖已经准备删除的 `package.json` 或 `src-tauri/tauri.conf.json`；版本号、bundle identifier、product name 这类真相源应提前迁到 `macos/Resources/AppMetadata.json` 这类原生侧元数据文件。
- `macos/Vendor/` 不是版本库真相源，只是本机开发时通过 `setup-ghostty-framework.sh` 准备的 Ghostty vendor 目录；相关验证可以依赖它，但不能把它当成应提交入库的源码。
- 对“历史文档痕迹”类清理，不要只删代码目录；还要同步检查 `docs/plans/`、旧版 `docs/releases/`、`work.md`、`PLAN.md`、`tasks/todo.md`、`tasks/lessons.md` 是否仍在讲已经不存在的技术栈。
