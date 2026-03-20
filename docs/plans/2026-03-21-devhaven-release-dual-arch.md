# DevHaven Release Dual-Arch Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让 GitHub release workflow 同时产出 macOS arm64 与 x86_64 两个安装包。

**Architecture:** 保持 `macos/scripts/build-native-app.sh` 继续按“当前 runner 原生架构”构建，不在脚本里引入额外架构分支；把双架构控制收口到 `.github/workflows/release.yml` 的 matrix，由不同 runner 分别产出 arm64 与 Intel 包，并用不同的 release asset 名称上传，避免互相覆盖。

**Tech Stack:** GitHub Actions、Swift Package Manager、GhosttyKit xcframework、macOS GitHub-hosted runners

---

### Task 1: 收口发布方案说明

**Files:**
- Modify: `AGENTS.md`
- Modify: `tasks/todo.md`

**Step 1: 记录目标 runner 与产物命名**

明确：
- `arm64` 使用 `macos-26`
- `x86_64` 使用 `macos-15-intel`
- release asset 以 `DevHaven-macos-<arch>.zip` 命名

**Step 2: 同步项目发布主链文档**

把 release workflow 已不再是单一 runner 的事实写入 `AGENTS.md`，并在 `tasks/todo.md` 追加本轮任务与验证证据。

### Task 2: 修改 workflow 为双架构发布

**Files:**
- Modify: `.github/workflows/release.yml`

**Step 1: 引入 matrix**

把 `build-macos-native` 改成：
- `arm64 / macos-26`
- `x86_64 / macos-15-intel`

**Step 2: 让打包产物带架构后缀**

修改 archive 步骤，把 zip 输出改成：

```bash
zip_path="$RUNNER_TEMP/DevHaven-macos-${{ matrix.arch }}.zip"
```

**Step 3: 保持现有 bootstrap / test / build 主链不变**

不要在这轮引入新的脚本参数或跨架构打包逻辑；继续复用：
- `setup-ghostty-framework.sh`
- `swift test --package-path macos`
- `build-native-app.sh`

### Task 3: 验证 workflow 与 x86_64 构建能力

**Files:**
- Verify: `.github/workflows/release.yml`
- Verify: `macos/`

**Step 1: 校验 workflow YAML**

Run:

```bash
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release.yml"); puts "yaml ok"'
```

Expected:
- 输出 `yaml ok`

**Step 2: 校验当前仓库能产出 x86_64 可执行文件**

Run:

```bash
swift build --package-path macos -c release --triple x86_64-apple-macosx14.0
```

Expected:
- 构建完成，无错误退出

**Step 3: 确认可执行文件架构**

Run:

```bash
BIN_DIR="$(swift build --package-path macos -c release --triple x86_64-apple-macosx14.0 --show-bin-path)"
file "$BIN_DIR/DevHavenApp"
```

Expected:
- 输出包含 `Mach-O 64-bit executable x86_64`
