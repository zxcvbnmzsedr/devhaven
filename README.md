<div align="center">

<img src="./docs/assets/logo.png" alt="DevHaven Logo" width="120" />

# DevHaven

### Native macOS workspace for terminal-first development

[![Version](https://img.shields.io/badge/version-3.2.0-blue)](https://github.com/zxcvbnmzsedr/DevHaven/releases)
[![License](https://img.shields.io/badge/license-GPL--3.0-green)](./LICENSE)
[![Platform](https://img.shields.io/badge/macOS-14.0%2B-black)](https://developer.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange)](https://www.swift.org/)

DevHaven is now focused on a **pure native macOS line** built with **SwiftUI + AppKit + Swift Package Manager**. It brings multi-project navigation, a GhosttyKit-powered terminal workspace, Git / Commit / Diff tool windows, typed run configurations, notifications, and Claude / Codex session awareness into one app.

[Highlights](#-highlights) · [Features](#-features) · [Getting Started](#-getting-started) · [Repository Layout](#-repository-layout) · [Tech Stack](#-tech-stack) · [中文文档](./README_cn.md)

</div>

---

## 🌟 Highlights

| Area | What DevHaven gives you |
|---|---|
| Native workspace shell | A real macOS app shell, not a browser container |
| Terminal-first workflow | GhosttyKit-powered terminal tabs, split panes, search, and workspace restore |
| Git tooling | Commit side tool window, IDEA-style log, branches / operations, and reusable diff tabs |
| Run experience | Typed run configurations, reusable sessions, and a bottom run console |
| Notifications & agents | Local notifications plus Claude / Codex session status surfaced in the workspace |
| Distribution | Local `./dev` and `./release` flows, Sparkle metadata, stable + nightly delivery pipeline |

---

## ✨ Features

### 🗂 Project hub and multi-project navigation

- Scan a working directory and discover Git repositories quickly.
- Import specific repositories directly and keep them in the project list.
- Open multiple projects into the same workspace without tearing down existing terminal sessions.
- Manage worktree-related actions from the project navigation flow.
- Keep project navigation separate from the workspace chrome so the terminal and tool windows stay focused.

<p align="center">
  <img src="./docs/pic/runtime/readme-projects.png" alt="DevHaven project hub" width="100%" />
</p>

### 💻 Terminal-first native workspace

- Built on **GhosttyKit**, so the terminal is backed by a native terminal engine rather than a web terminal wrapper.
- Supports workspace tabs, split panes, focused pane routing, and pane reuse.
- Integrates search into the workspace and macOS menu command flow.
- Preserves workspace context through restore snapshots, so returning to the app does not feel like starting over.
- Ships bundled shell wrappers for Claude / Codex integration and keeps the wrapper path normalized even when shell startup files rewrite `PATH`.

<p align="center">
  <img src="./docs/pic/runtime/readme-home.png" alt="DevHaven terminal workspace" width="100%" />
</p>

### 🧾 Git, Commit, and Diff tool windows

- A dedicated **Commit** side tool window for staged / unstaged / untracked changes, inclusion toggles, commit draft editing, amend / sign-off / author options, and execution feedback.
- A dedicated **Git** bottom tool window for branches, remote operations, and an IDEA-style log flow.
- Structured commit graph rendering, log filters, change browser, and commit details in the Git log view.
- Reusable diff tabs opened from Git log or working tree changes instead of scattered ad-hoc previews.
- Patch, two-side compare, and merge viewers for history diffs and working tree conflict workflows.

<p align="center">
  <img src="./docs/pic/runtime/readme-git-log.png" alt="DevHaven Git log tool window" width="100%" />
</p>

<p align="center">
  <img src="./docs/pic/runtime/readme-commit.png" alt="DevHaven commit tool window" width="100%" />
</p>

### ▶️ Run configurations, notifications, and agent status

- Typed run configurations attached to each project, with initial support for `customShell` and `remoteLogViewer`.
- A lightweight run toolbar at the top of the workspace and a reusable bottom run console for live output.
- Log persistence under `~/.devhaven/run-logs/` so sessions can be inspected after the fact.
- Local notification popover and system notification integration for workspace events.
- Claude / Codex session signal tracking, agent status accessories, and runtime heuristics that distinguish active work from waiting states.

<p align="center">
  <img src="./docs/pic/runtime/readme-run-console.png" alt="DevHaven run console" width="100%" />
</p>

### 🔄 Native distribution and update pipeline

- Sparkle metadata is embedded into release builds.
- Stable and nightly channels are both modeled in the app metadata and GitHub workflows.
- Public builds currently default to **manual download delivery**, which means DevHaven can check for updates and send you to the download page.
- The repository includes scripts for local app packaging, universal app assembly, appcast generation, and staged-to-alias promotion.

---

## 🚀 Getting Started

### Requirements

| Requirement | Version / Notes |
|---|---|
| macOS | 14.0+ |
| Swift / Xcode | Swift 6 and Xcode or Command Line Tools |
| Git | Any recent version |
| Ghostty source | Required only when you need to bootstrap `macos/Vendor` from scratch |

### Download

- **Stable**: download the latest stable release from the [GitHub Releases page](https://github.com/zxcvbnmzsedr/DevHaven/releases)
- **Nightly / preview**: check GitHub pre-releases published by the nightly workflow

> **macOS security note**
>
> DevHaven is not notarized yet. If macOS blocks the app on first launch, remove the quarantine attribute:
>
> ```bash
> sudo xattr -r -d com.apple.quarantine "/Applications/DevHaven.app"
> ```

### Build from source

If another DevHaven worktree on your machine already has a prepared `macos/Vendor`, `./dev` can reuse it automatically. On a clean machine, bootstrap Ghostty and Sparkle first:

```bash
git clone https://github.com/zxcvbnmzsedr/DevHaven.git
cd DevHaven

# Ghostty vendor: build or reuse artifacts from your local Ghostty source checkout
bash macos/scripts/setup-ghostty-framework.sh --source /path/to/ghostty

# Sparkle vendor: reuse another worktree if possible, otherwise download automatically
bash macos/scripts/setup-sparkle-framework.sh --ensure-worktree-vendor

# Test and run
swift test --package-path macos
./dev
```

### Development flow

```bash
# Start the native app in development mode
./dev

# Only stream DevHaven logs
./dev --logs app

# Disable unified log streaming
./dev --no-log

# Print the commands without executing
./dev --dry-run
```

`./dev` will:

1. Ensure Ghostty and Sparkle vendor assets are available
2. Build the `DevHavenCLI` helper
3. Optionally attach unified log streaming
4. Launch `swift run --package-path macos DevHavenApp`

### Release build

```bash
# Standard local release build
./release

# Release build without opening Finder afterward
./release --no-open

# Direct script usage if you need a custom channel or build number
bash macos/scripts/build-native-app.sh --release --update-channel nightly --build-number 3011001 --no-open
```

### Embedded terminal configuration

DevHaven reads Ghostty configuration in this order:

1. `~/.devhaven/ghostty/config`
2. `~/.devhaven/ghostty/config.ghostty`
3. Fallback to Ghostty's global config under `~/Library/Application Support/com.mitchellh.ghostty/`

---

## 📖 Typical workflow

1. **Add repositories** by scanning a parent directory or importing specific paths.
2. **Open a project into the workspace** and keep existing tabs / panes alive while opening more projects.
3. **Work in the terminal** using Ghostty-backed panes, menu-integrated search, and restore-aware sessions.
4. **Review changes** in the Commit or Git tool windows.
5. **Open reusable diff tabs** for history diffs, working tree comparisons, or merge resolution.
6. **Run project commands** through per-project run configurations and inspect logs in the bottom console.

---

## 🗃 Repository Layout

| Path | Purpose |
|---|---|
| `dev` | Local development entrypoint that prepares vendor assets, starts log streaming, and runs the app |
| `release` | Local release packaging entrypoint that delegates to `macos/scripts/build-native-app.sh --release` |
| `macos/Package.swift` | Swift Package entry for the native app, core module, and CLI helper |
| `macos/Sources/DevHavenApp/` | Native macOS app shell, Ghostty host, workspace UI, update integration, bundled agent resources |
| `macos/Sources/DevHavenCore/` | Models, storage, Git services, restore coordination, run management, and view models |
| `macos/scripts/` | Vendor bootstrap, app packaging, universal app assembly, and appcast tooling |
| `docs/pic/` | README screenshots |
| `.github/workflows/` | Stable release and nightly delivery automation |

---

## 🛠 Tech Stack

| Layer | Technology |
|---|---|
| UI shell | SwiftUI + AppKit |
| Package / build | Swift Package Manager |
| Terminal engine | [GhosttyKit](https://ghostty.org/) |
| Updates | [Sparkle](https://sparkle-project.org/) |
| Git integration | Native Git CLI services |
| Runtime storage | `~/.devhaven/*` compatibility and runtime stores |

---

## 🤝 Contributing

Issues and PRs are welcome. For significant changes, please open an issue first so the implementation approach can be discussed before code lands.

---

## 📄 License

[GPL-3.0](./LICENSE)
