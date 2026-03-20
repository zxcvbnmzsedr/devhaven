# 本次任务清单

## DevHaven 3.0.0 仓库收口为纯 macOS 原生主线（2026-03-20）

- [x] 保护当前工作区并核对 merge 前状态
- [x] 将 `swift` 合并到 `main`
- [x] 切换版本真相源到 `macos/Resources/AppMetadata.json`
- [x] 下线 Tauri / Node / pnpm 发布链路
- [x] 删除旧的 React / Vite / Tauri / Rust 兼容源码与构建配置
- [x] 清理历史实施文档与旧版本 release note
- [x] 同步更新 `README.md`、`AGENTS.md`、原生设置文案与 release note
- [x] 运行原生测试与原生打包验证

## Review（DevHaven 3.0.0 纯 macOS 原生主线收口）

- 合并结果：已在 `main` 上完成 `swift` 分支合并，merge commit 为 `5e50a98`（`Merge branch 'swift'`）。
- 仓库结构结果：旧的 `src/`、`src-tauri/`、`scripts/`、`public/` 以及 `package.json` / `pnpm-lock.yaml` / `vite.config.ts` 等旧构建配置已从仓库删除；当前源码仅保留 `macos/` 原生主线。
- 版本结果：版本真相源已切换到 `macos/Resources/AppMetadata.json`，当前版本为 `3.0.0`。
- 发布结果：`.github/workflows/release.yml` 已收口为纯 Swift/macOS 原生链路，只保留 `swift test --package-path macos`、原生 `.app` 构建、压缩与 release asset 上传。
- 文档结果：`README.md`、`AGENTS.md`、`docs/releases/v3.0.0.md` 已更新为原生主线口径；旧的 `docs/plans/`、旧版 release note、`work.md`、`PLAN.md` 已删除。
- 设计层判断：本轮真正的系统性问题是“发布链、仓库结构、版本真相源、历史文档四套边界长期不一致”。现在已经把源码、打包、版本和文档统一收口到 `macos/` 原生主线。
- 验证证据：
  - `swift test --package-path macos` → 通过，`105 tests, 5 skipped, 0 failures`。
  - `bash macos/scripts/setup-ghostty-framework.sh --source /Users/zhaotianzeng/Documents/business/tianzeng/ghostty --skip-build` → 通过，仅用于本机准备 `macos/Vendor/**`。
  - `bash macos/scripts/build-native-app.sh --release --no-open --output-dir /tmp/devhaven-native-app-verify-pure` → 通过，产物为 `/tmp/devhaven-native-app-verify-pure/DevHaven.app`。
  - `git diff --check` → 通过。

## 修复 GitHub Release 缺少 Ghostty vendor 导致的 `swift test` 失败（2026-03-20）

- [x] 复现干净 checkout 下的 `GhosttyKit` binary target 报错
- [x] 收口 CI bootstrap 方案并更新 workflow / 文档
- [x] 重新验证“干净 checkout + 准备 vendor + swift test / 原生打包”链路

## Review（GitHub Release Ghostty vendor bootstrap）

- 直接原因：`macos/Package.swift` 通过本地 `binaryTarget(path: "Vendor/GhosttyKit.xcframework")` 依赖 GhosttyKit，但 `macos/Vendor/` 被 `.gitignore` 忽略，GitHub Actions 的干净 checkout 在 `swift test --package-path macos` 前没有有效的二进制产物，因此直接报错 `does not contain a binary artifact`。
- 设计层诱因：发布 workflow 虽然已经切到纯 Swift/macOS，但仍把“本机已准备好 Ghostty vendor”当成默认前提；也就是说，Swift Package 的 binary target 真相源和 CI 的准备链路是脱节的。
- 当前修复：`.github/workflows/release.yml` 现在会先安装 Zig，再 `git fetch` 固定 commit `da10707f93104c5466cd4e64b80ff48f789238a0` 的 Ghostty 源码，执行 `bash macos/scripts/setup-ghostty-framework.sh --source "$RUNNER_TEMP/ghostty"` 准备临时 `macos/Vendor/`，然后再运行 `swift test` 和原生打包；`README.md`、`AGENTS.md`、`tasks/lessons.md` 已同步更新说明。
- 长期建议：后续如果继续升级 Ghostty 版本，必须把“上游 commit pin + CI bootstrap + 本地开发说明”视为同一组变更一起维护，避免再次出现“本机能过、干净 checkout 直接炸”的问题。
- 验证证据：
  - 干净 worktree 直接执行 `swift test --package-path macos` → 复现失败：`local binary target 'GhosttyKit' ... does not contain a binary artifact`。
  - `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release.yml")'` → 通过，确认 workflow YAML 合法。
  - 在干净 worktree 内按 workflow 新链路执行：
    - `git init "$RUNNER_TEMP/ghostty" && git -C "$RUNNER_TEMP/ghostty" fetch --depth 1 origin da10707f93104c5466cd4e64b80ff48f789238a0 && git -C "$RUNNER_TEMP/ghostty" checkout --detach FETCH_HEAD`
    - `bash macos/scripts/setup-ghostty-framework.sh --source "$RUNNER_TEMP/ghostty"`
    - `swift test --package-path macos`
    - `bash macos/scripts/build-native-app.sh --release --no-open --output-dir "$RUNNER_TEMP/native-app"`
  - 上述整条链路 → 通过，`105 tests, 5 skipped, 0 failures`，并产出 `/tmp/devhaven-workflow-verify-git-36433/.runner-temp/native-app/DevHaven.app`。
  - `git diff --check` → 通过。

## 修复 GitHub Actions 上 Ghostty 在 Xcode 16.4 编译失败（2026-03-20）

- [x] 拉取最新失败 run 并定位实际失败 step
- [x] 确认 root cause 为 runner Xcode 版本落后而非 vendor bootstrap 逻辑错误
- [x] 将 release workflow 切到 `macos-26` 并增加 Xcode 版本诊断输出
- [x] commit / push 并重打 `v3.0.0` 触发新的 release run
- [x] 检查新 run 是否成功起跑

## Review（GitHub Actions Xcode toolchain 对齐）

- 直接原因：最新失败 run `23343818716` 虽然已经成功完成 Ghostty 源码 checkout，但在 `Bootstrap Ghostty vendor` 阶段执行 `cd /Users/runner/work/_temp/ghostty/macos && xcodebuild -target Ghostty -configuration ReleaseLocal` 时退出 `code 65`，日志明确显示使用的是 `/Applications/Xcode_16.4.app/...`。
- 设计层诱因：上一轮只把“CI 缺失 Ghostty vendor bootstrap”补齐了，但没有把 GitHub runner 的 Xcode 主版本与当前 Ghostty 上游的构建要求一起锁定；结果变成“vendor 链路对了，工具链版本又漂移了”。
- 当前修复：`.github/workflows/release.yml` 已把 release runner 从 `macos-latest` 改成 `macos-26`，并新增 `Print Xcode version` 步骤输出 `xcodebuild -version`，用于让日志直接暴露实际工具链版本。
- 长期建议：后续只要升级 Ghostty commit 或切换 GitHub runner 标签，都要把“上游 commit pin / runner OS / Xcode 主版本 / 本地验证环境”作为同一组约束维护，而不是只盯单个脚本。
- 新进展（2026-03-20）：
  - `git push origin main` → 已成功把修复提交 `dd46da5` 推到远端。
  - `git tag -fa v3.0.0 -m "v3.0.0"` + `git push origin refs/tags/v3.0.0 --force` → 已成功把 `v3.0.0` 重指到 `dd46da5` 并推送远端。
  - `gh run list --workflow release.yml --limit 5 ...` → 新 run `23346369319` 已于 `2026-03-20T14:03:39Z` 起跑，当前 URL：`https://github.com/zxcvbnmzsedr/devhaven/actions/runs/23346369319`。

## 修复 GitHub workflow 产物启动即崩（2026-03-20）

- [x] 对照 crash log 与 Supacode 打包方式定位资源加载断裂点
- [x] 调整 `GhosttyAppRuntime` 的资源 bundle 定位逻辑并补回归测试
- [x] 验证原生测试、`.app` 布局、原生打包与启动 smoke test

## Review（GitHub workflow 产物启动即崩）

- 直接原因：GitHub workflow 产出的 `.app` 在启动时崩在 `static NSBundle.module` 初始化，说明运行时没有按 SwiftPM 期望的方式找到 `DevHavenNative_DevHavenApp.bundle`。`build-native-app.sh` 会把该 bundle 复制到 `DevHaven.app/Contents/Resources/`，但旧版 `GhosttyAppRuntime` 仍直接依赖 `Bundle.module`，导致打包后的应用在初始化 `GhosttyResources/ghostty` 时触发断言并直接崩溃。
- 设计层诱因：当前 release 仍是“SwiftPM executable + 手工组装 `.app`”模式，资源拷贝路径由打包脚本掌控，而运行时资源定位却交给 `Bundle.module` 的默认实现；也就是**打包布局真相源**和**运行时资源查找真相源**分裂了。未发现更大的系统设计缺陷，问题集中在这一处边界没有显式收口。
- 当前修复：
  - `GhosttyAppRuntime` 新增显式资源 bundle 定位逻辑，优先解析 `Bundle.main.resourceURL/DevHavenNative_DevHavenApp.bundle`，并兼容测试环境下的 sibling bundle fallback；
  - 新增 `GhosttyAppRuntimeBundleLocatorTests`，锁定“打包产物优先从 `Contents/Resources` 取 bundle”和“测试环境可从同级目录 fallback”两条路径；
  - 新增 `macos/scripts/test-native-app-layout.sh`，持续检查 `.app` 中资源 bundle 的实际落点；
  - 保持资源 bundle 放在 `Contents/Resources/`，不再尝试复制到 `.app` 根目录，避免 `codesign --verify --deep --strict` 报 `unsealed contents present in the bundle root`。
- Supacode 对照：Supacode 走 `xcodebuild archive/exportArchive`，资源通过 Xcode `PBXResourcesBuildPhase` 进入 `Contents/Resources/`，运行时直接按 `Bundle.main.resourceURL/...` 读取 `ghostty` / `terminfo` / `git-wt`。这次修复本质上是把 DevHaven 的运行时资源解析边界也收口到同样稳定的 app resources 语义上，而不是继续赌 `Bundle.module` 在手工组装 `.app` 时能自动对齐。
- 长期建议：如果后续继续沿用 SwiftPM executable + 手工 `.app` 组装路线，凡是要在发布版读取的资源，都应像这次一样显式绑定到最终 app 布局；不要让“构建时生成 bundle”和“运行时查找 bundle”分属两套默认约定。
- 验证证据：
  - `swift test --package-path macos` → 通过，`107 tests, 5 skipped, 0 failures`。
  - `bash macos/scripts/test-native-app-layout.sh` → 通过，确认资源 bundle 位于 `DevHaven.app/Contents/Resources/DevHavenNative_DevHavenApp.bundle`，且 app 根目录不存在非法副本。
  - `bash macos/scripts/build-native-app.sh --release --no-open --output-dir /tmp/devhaven-native-app-verify-launch-fix` → 通过，产物为 `/tmp/devhaven-native-app-verify-launch-fix/DevHaven.app`，脚本内 `codesign --verify --deep --strict` 通过。
  - 启动 smoke test：直接执行 `/tmp/devhaven-native-app-verify-launch-fix/DevHaven.app/Contents/MacOS/DevHavenApp`，5 秒后进程仍存活，输出 `STATUS=running_after_5s`，未再出现启动即崩。
- 额外核对：Supacode 安装产物 `/Applications/supacode.app/Contents/Resources/` 下确实存在 `ghostty`、`terminfo`、`git-wt`，与本次对照结论一致。

## 扩展 GitHub release 为 arm64 + x86_64 双产物（2026-03-21）

- [x] 确认当前单产物 release 只会跟随 runner 架构输出 arm64
- [x] 设计 dual-arch release 方案并记录到 `docs/plans/2026-03-21-devhaven-release-dual-arch.md`
- [x] 修改 `.github/workflows/release.yml` 为 arm64 / x86_64 matrix
- [x] 同步更新 `AGENTS.md` 的发布主链说明
- [x] 校验 workflow YAML 与本地 x86_64 构建验证

## Review（GitHub release dual-arch）

- 直接原因：当前 `.github/workflows/release.yml` 只有单个 `build-macos-native` job，且固定 `runs-on: macos-26`；`build-native-app.sh` 又直接调用不带 `--triple` 的 `swift build`，所以 release 产物天然跟随 runner 架构，只会产出 `arm64` 包。
- 设计层诱因：发布链原先把“目标架构”隐式绑定在 runner 上，但 release asset 名称却没有编码架构信息。这种做法在单 runner 时代问题不明显，一旦扩成多架构发布，构建真相源和发布资产命名就会发生冲突。
- 当前修复：
  - `.github/workflows/release.yml` 现在改为 matrix，同时跑 `arm64/macos-26` 与 `x86_64/macos-15-intel`；
  - 保持 `setup-ghostty-framework.sh`、`swift test --package-path macos`、`build-native-app.sh` 主链不变，不在本轮给脚本再加一套额外架构分支；
  - release asset 名称改成 `DevHaven-macos-arm64.zip` 和 `DevHaven-macos-x86_64.zip`，避免两个 job 互相覆盖。
- 长期建议：后续如果要继续做 universal 包，再单独评估“matrix 双包”与“lipo 合包”谁是正式发行策略；在这之前，不要把 runner 架构、target triple 和 release asset 命名继续混在一起。
- 验证证据：
  - `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release.yml"); puts "yaml ok"'` → 通过，输出 `yaml ok`。
  - `swift build --package-path macos -c release --triple x86_64-apple-macosx14.0` → 通过。
  - `file /Users/zhaotianzeng/WebstormProjects/DevHaven/macos/.build/x86_64-apple-macosx/release/DevHavenApp` → 输出 `Mach-O 64-bit executable x86_64`。
  - `git diff --check` → 通过。
