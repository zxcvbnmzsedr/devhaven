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
- [ ] commit / push 并重打 `v3.0.0` 触发新的 release run
- [ ] 检查新 run 是否成功起跑

## Review（GitHub Actions Xcode toolchain 对齐）

- 直接原因：最新失败 run `23343818716` 虽然已经成功完成 Ghostty 源码 checkout，但在 `Bootstrap Ghostty vendor` 阶段执行 `cd /Users/runner/work/_temp/ghostty/macos && xcodebuild -target Ghostty -configuration ReleaseLocal` 时退出 `code 65`，日志明确显示使用的是 `/Applications/Xcode_16.4.app/...`。
- 设计层诱因：上一轮只把“CI 缺失 Ghostty vendor bootstrap”补齐了，但没有把 GitHub runner 的 Xcode 主版本与当前 Ghostty 上游的构建要求一起锁定；结果变成“vendor 链路对了，工具链版本又漂移了”。
- 当前修复：`.github/workflows/release.yml` 已把 release runner 从 `macos-latest` 改成 `macos-26`，并新增 `Print Xcode version` 步骤输出 `xcodebuild -version`，用于让日志直接暴露实际工具链版本。
- 长期建议：后续只要升级 Ghostty commit 或切换 GitHub runner 标签，都要把“上游 commit pin / runner OS / Xcode 主版本 / 本地验证环境”作为同一组约束维护，而不是只盯单个脚本。
