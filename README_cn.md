<div align="center">

<img src="./docs/assets/logo.png" alt="DevHaven Logo" width="120" />

# DevHaven

### macOS 原生多项目管理与终端工作区

[![版本](https://img.shields.io/badge/version-3.1.10-blue)](https://github.com/zxcvbnmzsedr/DevHaven/releases)
[![协议](https://img.shields.io/badge/license-GPL--3.0-green)](./LICENSE)
[![平台](https://img.shields.io/badge/macOS-14.0%2B-black)](https://developer.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange)](https://www.swift.org/)

DevHaven 是一款基于 **SwiftUI + AppKit** 的 macOS 原生桌面应用，将你的所有项目整合到一处 — 内置由 GhosttyKit 驱动的原生终端、Git 活跃度可视化与 Worktree 管理，全程无需离开应用。

[功能特性](#-功能特性) · [截图预览](#-截图预览) · [快速开始](#-快速开始) · [使用指南](#-使用指南) · [技术栈](#-技术栈) · [English](./README.md)

</div>

---

## 🖼 截图预览

**主界面 — 项目列表**

![主界面.png](docs/pic/%E4%B8%BB%E7%95%8C%E9%9D%A2.png)

---

**Git 活跃度仪表盘**

![git活跃度.png](docs/pic/git%E6%B4%BB%E8%B7%83%E5%BA%A6.png)

---

**终端工作区**

![通知与项目.png](docs/pic/%E9%80%9A%E7%9F%A5%E4%B8%8E%E9%A1%B9%E7%9B%AE.png)
![通知配置.png](docs/pic/%E9%80%9A%E7%9F%A5%E9%85%8D%E7%BD%AE.png)
---

## ✨ 功能特性

### 🗂️ 智能项目管理
- **批量扫描** — 指定工作目录后自动发现其中所有 Git 项目
- **灵活导入** — 手动添加任意项目，刷新后依然保留
- **多维筛选** — 按标签、目录、关键字、时间范围、Git 状态快速定位项目

### 📊 Git 可视化分析
- **提交热力图** — 类 GitHub 风格，直观展示每日代码活跃度
- **统计仪表盘** — 提交次数、活跃度评分、时间分布
- **分支 / Worktree 管理** — 查看分支状态，管理 Worktree 生命周期

### 💻 原生终端工作区
- **多项目** — 同时打开多个项目，各自保留独立会话
- **标签与分屏** — 完整的标签页管理、分屏、焦点切换与 Pane 生命周期控制
- **GhosttyKit 内核** — 终端由 [Ghostty](https://ghostty.org/) 同款原生内核驱动，告别 Web 终端壳
- **会话保持** — 切回项目列表后工作区继续挂载，不会意外回收终端

---

## 🚀 快速开始

### 系统要求

| 依赖 | 版本 |
|---|---|
| macOS | 14.0+ |
| Swift / Xcode | Swift 6 + Xcode 或 CLT |
| Git | 任意近期版本 |

### 下载安装

前往 [Releases 页面](https://github.com/zxcvbnmzsedr/DevHaven/releases) 下载最新版本。

> **⚠️ macOS 安全提示**
> DevHaven 暂未完成公证。如果首次启动时 macOS 提示"无法打开应用"，执行以下命令解除隔离：
> ```bash
> sudo xattr -r -d com.apple.quarantine "/Applications/DevHaven.app"
> ```

### 源码构建

```bash
# 1. 克隆项目
git clone https://github.com/zxcvbnmzsedr/DevHaven.git
cd DevHaven

# 2. 准备 Ghostty vendor（替换为你本机的 ghostty 源码路径）
bash macos/scripts/setup-ghostty-framework.sh --source /path/to/ghostty --skip-build

# 3. 准备 Sparkle vendor
bash macos/scripts/setup-sparkle-framework.sh --ensure-worktree-vendor

# 4. 运行测试
swift test --package-path macos

# 5. 构建 Release App
./release
```

### 开发态启动

```bash
./dev            # 默认：校验 vendor + 实时日志 + 启动应用
./dev --logs app # 只看 DevHaven 自身日志
./dev --no-log   # 不接入日志
./dev --dry-run  # 仅打印命令，不执行
```

> `./dev` 会在启动前自动复用或准备所需 vendor 内容（Ghostty / Sparkle），然后启动 `swift run --package-path macos DevHavenApp`。

### 终端配置

DevHaven 内嵌的 Ghostty 终端按以下顺序读取配置：

1. `~/.devhaven/ghostty/config` 或 `~/.devhaven/ghostty/config.ghostty`
2. 回退到全局 Ghostty 配置：`~/Library/Application Support/com.mitchellh.ghostty/config*`

---

## 📖 使用指南

### 第一步 — 添加项目

**扫描目录**
1. 在侧边栏添加工作目录
2. DevHaven 自动扫描子目录中的 Git 项目并构建列表
3. 点击项目查看详情或进入工作区

**手动导入**
- 直接添加单个项目路径，刷新后持续保留

### 第二步 — 使用终端工作区

- 双击项目进入终端工作区
- 在同一工作区继续打开其它项目，不关闭已有终端
- 使用标签页与分屏管理多个终端 Pane
- 在工作区内管理 Worktree、查看 Git 状态、执行命令

---

## 🛠 技术栈

| 层级 | 技术 |
|---|---|
| 桌面壳 | SwiftUI + AppKit |
| 构建工具 | Swift Package Manager |
| 终端内核 | [GhosttyKit](https://ghostty.org/) |
| 自动升级 | [Sparkle](https://sparkle-project.org/) |
| 数据兼容层 | LegacyCompatStore (`~/.devhaven/*`) |
| Git / Worktree | 原生 Git CLI + `NativeGitWorktreeService` |

---

## 🤝 贡献

欢迎提 Issue 和 PR。较大的改动请先开 Issue 讨论方案。

---

## 📄 开源协议

本项目基于 [GPL-3.0](./LICENSE) 开源。
