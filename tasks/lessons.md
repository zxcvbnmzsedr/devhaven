# Lessons Learned

- 当用户已经明确要求“切到 Swift 原生打包主线”时，不要只删 Tauri 打包入口；要继续检查 release workflow、版本真相源、README、AGENTS 和设置页文案是否仍残留旧栈语义。
- 当用户进一步明确要求“源文件都删除”时，必须连同旧的 React / Vite / Tauri / Rust 兼容源码、Node 构建配置、历史实施文档与旧 release note 一起清理，避免仓库结构和产品口径继续分裂。
- 原生打包脚本不应依赖已经准备删除的 `package.json` 或 `src-tauri/tauri.conf.json`；版本号、bundle identifier、product name 这类真相源应提前迁到 `macos/Resources/AppMetadata.json` 这类原生侧元数据文件。
- `macos/Vendor/` 不是版本库真相源，只是本机开发时通过 `setup-ghostty-framework.sh` 准备的 Ghostty vendor 目录；相关验证可以依赖它，但不能把它当成应提交入库的源码。
- 当 Swift Package 通过本地 `binaryTarget(path: ...)` 依赖一个被 `.gitignore` 忽略的目录时，干净 checkout（尤其是 GitHub Actions runner）会在 `swift test` 阶段直接失败；CI 必须先显式 bootstrap 该 vendor，而不能假设本机已有产物。
- 对 Ghostty 这类会读取 Git 元数据的上游工程，CI 不能偷懒只下源码归档再 `zig build`；必须保留真实 Git checkout（至少是 fetch 到固定 commit），否则上游构建脚本可能因缺失仓库上下文而直接 panic。
- 当上游原生依赖（这里是 Ghostty）对 Xcode 主版本有隐含要求时，`macos-latest` 不是稳定真相源；需要显式固定到合适的 runner（这里是 `macos-26`），并把 `xcodebuild -version` 打到日志里，避免只看到 `code 65` 却不知道 runner 实际工具链。
- 对“历史文档痕迹”类清理，不要只删代码目录；还要同步检查 `docs/plans/`、旧版 `docs/releases/`、`work.md`、`PLAN.md`、`tasks/todo.md`、`tasks/lessons.md` 是否仍在讲已经不存在的技术栈。
