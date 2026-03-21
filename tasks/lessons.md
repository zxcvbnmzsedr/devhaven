# Lessons Learned

- 对 DevHaven 这种显式确认后的 “删除 worktree” 操作，不能直接透传裸 `git worktree remove`；Git 默认会因 modified / untracked 文件拒删并抛出原始 fatal。要么在服务层显式使用 `--force` 对齐产品语义，要么在 UI 先做 dirty-state 预检并给出清晰分支。
- 当用户已经明确要求“切到 Swift 原生打包主线”时，不要只删 Tauri 打包入口；要继续检查 release workflow、版本真相源、README、AGENTS 和设置页文案是否仍残留旧栈语义。
- 当用户进一步明确要求“源文件都删除”时，必须连同旧的 React / Vite / Tauri / Rust 兼容源码、Node 构建配置、历史实施文档与旧 release note 一起清理，避免仓库结构和产品口径继续分裂。
- 原生打包脚本不应依赖已经准备删除的 `package.json` 或 `src-tauri/tauri.conf.json`；版本号、bundle identifier、product name 这类真相源应提前迁到 `macos/Resources/AppMetadata.json` 这类原生侧元数据文件。
- `macos/Vendor/` 不是版本库真相源，只是本机开发时通过 `setup-ghostty-framework.sh` 准备的 Ghostty vendor 目录；相关验证可以依赖它，但不能把它当成应提交入库的源码。
- 当 Swift Package 通过本地 `binaryTarget(path: ...)` 依赖一个被 `.gitignore` 忽略的目录时，干净 checkout（尤其是 GitHub Actions runner）会在 `swift test` 阶段直接失败；CI 必须先显式 bootstrap 该 vendor，而不能假设本机已有产物。
- 对 Ghostty 这类会读取 Git 元数据的上游工程，CI 不能偷懒只下源码归档再 `zig build`；必须保留真实 Git checkout（至少是 fetch 到固定 commit），否则上游构建脚本可能因缺失仓库上下文而直接 panic。
- 当上游原生依赖（这里是 Ghostty）对 Xcode 主版本有隐含要求时，`macos-latest` 不是稳定真相源；需要显式固定到合适的 runner（这里是 `macos-26`），并把 `xcodebuild -version` 打到日志里，避免只看到 `code 65` 却不知道 runner 实际工具链。
- 对“历史文档痕迹”类清理，不要只删代码目录；还要同步检查 `docs/plans/`、旧版 `docs/releases/`、`work.md`、`PLAN.md`、`tasks/todo.md`、`tasks/lessons.md` 是否仍在讲已经不存在的技术栈。
- 手工组装 SwiftPM 可执行应用时，不要把运行时资源解析继续托付给 `Bundle.module` 的默认行为；打包脚本把资源 bundle 放在哪里，运行时代码就应该显式按最终 `.app` 布局去找，否则 release 产物很容易只在启动期才暴露崩溃。
- `.app` 根目录不是放 SwiftPM 资源 bundle 的安全兜底位点；即便那样能“碰巧”让 `Bundle.module` 工作，`codesign --verify --deep --strict` 也会因为 bundle root 出现未封装内容而失败。
- 当 GitHub release 要同时发多个 macOS 架构时，不要继续沿用单 runner + 通用 asset 文件名；应把“runner 架构”和“release asset 命名”一起显式化，否则多 job 上传时要么互相覆盖，要么让用户无法判断包对应的 CPU 架构。
- GitHub-hosted Intel runner 不等于“适合构建 Intel 目标”；如果上游依赖（这里是 Ghostty）已经要求更高版本的 Xcode，而 GitHub 当前可用 Intel runner 只有较老工具链，就应改成在较新 Apple Silicon runner 上用 `--triple x86_64-apple-macosx14.0` 交叉构建，而不是继续把 CPU 架构和 runner 机型绑死。
- 在 Apple Silicon 主机上跑 `swift test --triple x86_64-apple-macosx14.0` 时，测试二进制可以编出来，但默认无法直接执行 x86_64 test bundle；CI 若仍运行在 arm64 runner，上游验证边界应明确收口为“x86_64 编译/打包成功”，不要误把“可编译”当成“可在当前 runner 上直接执行测试”。
- 对纯 macOS 原生 GUI 应用，`swift run` 只是启动入口，不等于 Web 项目的 dev server；如果关键日志走 unified log，就应在仓库级开发命令里一并收口 `log stream` 与应用启动，否则用户很容易误以为“启动成功但没有日志”。
