<div align="center">

# DevHaven

### 🚀 macOS 原生多项目管理与终端工作区

[![version](https://img.shields.io/badge/version-3.1.0-blue)](https://github.com/zxcvbnmzsedr/DevHaven)
[![license](https://img.shields.io/badge/license-GPL--3.0-green)](./LICENSE)
[![macOS](https://img.shields.io/badge/macOS-Native-black)](https://developer.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange)](https://www.swift.org/)

DevHaven 现已切换为 **SwiftUI + AppKit + GhosttyKit** 驱动的 macOS 原生桌面应用，帮助你高效管理多个项目、查看 Git 活跃度，并在同一工作区里承载多项目终端与 worktree 流程。

[功能特性](#-功能特性) • [快速开始](#-快速开始) • [使用指南](#-使用指南) • [技术栈](#-技术栈)

</div>

---

## 📸 产品预览

**主界面 - 项目管理**

![主界面](./docs/screenshots/main-interface.png)

**Git 活跃度仪表盘**

![仪表盘](./docs/screenshots/dashboard.png)

> 显示 Git 提交热力图和统计数据

**项目详情面板**

![项目详情](./docs/screenshots/project-detail.png)

> 查看分支列表、编辑项目备注、快捷操作

**终端工作区**

![终端工作区](./docs/screenshots/terminal-workspace.png)

> 原生终端工作区，支持多项目、标签页、分屏与 worktree

---

## ✨ 功能特性

### 🗂️ 智能项目管理
- **批量扫描**：自动扫描工作目录及子目录，快速构建项目清单
- **灵活导入**：支持直接添加项目并长期保留
- **多维筛选**：通过标签、目录、关键字、时间范围、Git 状态快速定位项目

### 📊 Git 可视化分析
- **提交热力图**：直观展示每日代码活跃度
- **统计仪表盘**：项目提交次数、活跃度评估、时间分布
- **分支 / Worktree 管理**：查看分支状态并管理 worktree 生命周期

### 📝 项目内容与自动化
- **备注 / Todo**：读写 `PROJECT_NOTES.md`、`PROJECT_TODO.md`
- **Markdown 预览**：支持 README / Markdown 文件浏览
- **共享脚本中心**：兼容 `~/.devhaven/scripts` 的脚本清单与脚本文件

### 💻 原生终端工作区
- **多项目支持**：同时打开多个项目，保留各自 workspace 会话
- **标签与分屏**：支持多标签页、分屏、焦点切换与 pane 生命周期管理
- **GhosttyKit 承载**：终端内核走原生 GhosttyKit，不再依赖 Web 前端终端壳
- **会话保持**：返回主列表后 workspace 保持挂载，避免终端被误回收

### 🔄 自动升级基础设施
- **双通道更新**：内置 stable / nightly 更新通道，设置页可切换
- **Sparkle Runtime**：支持手动检查更新、自动检查、打开下载页与升级诊断导出；默认采用 manual-download 模式
- **Staged Appcast**：发布侧先上传 immutable 安装包，再提升 appcast feed，避免客户端先看到坏 feed
- **Universal 更新包**：CI 会把 arm64 / x86_64 产物合成为 universal `.app`，Sparkle feed 统一指向该安装包

---

## 🚀 快速开始

### 系统要求

- **macOS**：14.0+
- **Swift / Xcode**：Swift 6 + Xcode 或 Command Line Tools
- **Git**：用于读取仓库状态、分支与提交统计
- **Ghostty / Sparkle vendor**：首次本地开发前需准备 `macos/Vendor`（见下方说明）

### 构建步骤

```bash
# 克隆项目
git clone https://github.com/zxcvbnmzsedr/DevHaven.git
cd DevHaven

# 准备 Ghostty vendor（将路径替换为你本机的 ghostty 源码目录）
bash macos/scripts/setup-ghostty-framework.sh --source /path/to/ghostty --skip-build

# 准备 Sparkle vendor / tooling
bash macos/scripts/setup-sparkle-framework.sh --ensure-worktree-vendor

# 运行测试
swift test --package-path macos

# 构建 macOS 原生 App
./release
```

> 说明：`macos/Vendor/` 不会入库；GitHub Release / Nightly workflow 会先下载并构建固定版本的 Ghostty 源码（当前 pin 到 `da10707f93104c5466cd4e64b80ff48f789238a0`），并准备 Sparkle.xcframework + SparkleTools，再执行 `swift test`、原生打包、universal 合包与 appcast 生成。若你是在 linked worktree 里开发，`./dev` / `build-native-app.sh` 也会优先尝试复用同仓库其他 worktree 已准备好的 vendor。

### 开发态一键启动

如果你想要更接近 `pnpm dev` 的体验，可以直接使用仓库根目录的 `./dev`：

```bash
# 默认：校验 vendor + 观察 DevHaven/Ghostty unified log + 启动原生 App
./dev

# 只看 DevHaven 自己的日志
./dev --logs app

# 只启动应用，不接入 unified log
./dev --no-log

# 仅打印将要执行的命令，方便排查
./dev --dry-run
```

> `./dev` 内部会先执行 `bash macos/scripts/setup-ghostty-framework.sh --ensure-worktree-vendor` 与 `bash macos/scripts/setup-sparkle-framework.sh --ensure-worktree-vendor`；如果当前 worktree 没有本地 `macos/Vendor/`，但同仓库其他 worktree 已准备好 vendor，它会先自动同步，再按需启动 `log stream`，最后运行 `swift run --package-path macos DevHavenApp`。

### Release 打包入口

仓库根目录还提供了一个更直观的 `./release`：

```bash
# 默认执行 release 打包
./release

# 透传原生打包脚本参数
./release --no-open
./release --output-dir /tmp/devhaven-native-app
./release --triple x86_64-apple-macosx14.0 --no-open
```

> `./release` 内部固定执行 `bash macos/scripts/build-native-app.sh --release`，并继续透传其余参数；如果你需要 debug 包，请直接运行 `bash macos/scripts/build-native-app.sh --debug`。

> DevHaven 的内嵌 Ghostty 终端会优先读取 `~/.devhaven/ghostty/config` 或 `~/.devhaven/ghostty/config.ghostty`；如果这里还没有 DevHaven 专属配置，则会回退到你现有的 Ghostty 全局配置（例如 `~/Library/Application Support/com.mitchellh.ghostty/config*`）。

### 自动升级与发布约定

- 客户端更新设置位于应用内“设置 -> 应用升级”，支持：
  - stable / nightly 通道
  - 自动检查更新
  - 自动下载更新（仅当交付模式为 automatic 时生效）
  - 手动“立即检查更新”
  - “打开下载页” fallback
  - 复制升级诊断
- 开发态 `./dev` / `swift run --package-path macos DevHavenApp` 默认**禁用检查更新**，因为这不是 `.app` bundle 运行态。
- 正式 release / nightly 会把以下元数据写入 `.app/Contents/Info.plist`：
  - `CFBundleVersion`：单调递增 build number
  - `SUFeedURL`：当前默认通道对应 feed
  - `DevHavenStableFeedURL` / `DevHavenNightlyFeedURL`
  - `DevHavenUpdateDeliveryMode`：默认 `manualDownload`
  - `DevHavenStableDownloadsPageURL` / `DevHavenNightlyDownloadsPageURL`
  - `SUPublicEDKey`（未来切换 automatic 模式时使用）
- 默认情况下，DevHaven 正式构建采用 **manual-download** 交付模式：应用内负责检查新版本并打开下载页，而不是直接自动安装。若未来补齐 Apple Developer ID / notarization，可把 `updateDeliveryMode` 切换到 `automatic`。

- 发布链路固定为：
  1. 构建 arm64 / x86_64 原生 `.app`
  2. 合成 universal `.app`
  3. 上传 immutable release assets
  4. 生成 `appcast-staged.xml`
  5. Promote 到固定 feed alias：
     - stable：`stable-appcast/appcast.xml`
     - nightly：`nightly/appcast.xml`
- 仓库内相关脚本：
  - `bash macos/scripts/setup-sparkle-framework.sh --ensure-worktree-vendor`
  - `bash macos/scripts/create-universal-app.sh --arm64-app <...> --x86-app <...> --output <...>`
  - `bash macos/scripts/generate-appcast.sh --archives-dir <dir> --download-url-prefix <url>`
  - `bash macos/scripts/promote-appcast.sh --repo <owner/repo> --release-tag <tag> --appcast <file>`

### macOS 特别说明

3.0.0 起默认发布产物为 **macOS 原生 `.app`**。如果遇到“无法打开应用”的安全提示，可以移除隔离属性：

```bash
sudo xattr -r -d com.apple.quarantine "/Applications/DevHaven.app"
```

> 请替换为实际应用的安装路径

---

## 📖 使用指南

### 1️⃣ 添加项目

**方式一：扫描目录**
1. 在主界面添加工作目录
2. 等待 DevHaven 扫描子目录中的项目
3. 选择项目后查看详情或进入 workspace

**方式二：直接添加项目**
- 将具体项目路径加入列表，后续刷新时也会继续保留

### 2️⃣ 管理标签与内容

- 给项目添加 / 隐藏标签
- 编辑项目备注与 Todo
- 浏览项目内 Markdown / README
- 通过共享脚本中心维护常用脚本

### 3️⃣ 使用终端工作区

- 双击项目进入 workspace
- 在同一工作区中继续打开其它项目
- 使用标签页 / 分屏承载多个终端 pane
- 管理 worktree、查看 Git 状态、继续终端操作

---

## 🛠️ 技术栈

<table>
  <tr>
    <td align="center"><b>桌面壳</b></td>
    <td>SwiftUI + AppKit</td>
  </tr>
  <tr>
    <td align="center"><b>构建工具</b></td>
    <td>Swift Package Manager</td>
  </tr>
  <tr>
    <td align="center"><b>终端内核</b></td>
    <td>GhosttyKit + Sparkle</td>
  </tr>
  <tr>
    <td align="center"><b>数据兼容层</b></td>
    <td>LegacyCompatStore（兼容 `~/.devhaven/*`）</td>
  </tr>
  <tr>
    <td align="center"><b>Git / Worktree</b></td>
    <td>原生 Git 命令 + NativeGitWorktreeService</td>
  </tr>
</table>

---

## 📄 开源协议

本项目基于 [GPL-3.0](./LICENSE) 开源。
