# DevHaven Ghostty 风格路径粘贴对齐 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让 DevHaven 里的 Ghostty 终端在粘贴图片文件时，至少能像 Ghostty 原生一样把 file URL / utf8 plain text 解析成可插入终端的路径或字符串。

**Architecture:** 不引入 cmux 的图片物化或远端上传逻辑，只对齐 Ghostty 原生的 `getOpinionatedStringContents()` 语义：优先读取 file URL，再回退到 `.string` 和 `public.utf8-plain-text`。实现收口到一个独立 pasteboard helper，由 `GhosttyRuntime.handleReadClipboard(...)` 调用，避免把剪贴板细节继续散落在 runtime callback 里。

**Tech Stack:** Swift 6、Swift Package、AppKit `NSPasteboard`、GhosttyKit、XCTest。

---

### Task 1: 锁定 Ghostty 风格粘贴语义

**Files:**
- Test: `macos/Tests/DevHavenAppTests/GhosttyPasteboardTests.swift`

**Step 1: 写失败测试**

- `testOpinionatedStringContentsPrefersEscapedFileURLPaths`
- `testOpinionatedStringContentsFallsBackToUTF8PlainText`

**Step 2: 运行失败测试**

Run: `swift test --package-path macos --filter GhosttyPasteboardTests`

Expected: 编译失败或测试失败，提示缺少对应 helper/行为。

### Task 2: 实现 Ghostty 风格 pasteboard helper

**Files:**
- Create: `macos/Sources/DevHavenApp/Ghostty/GhosttyPasteboard.swift`
- Modify: `macos/Sources/DevHavenApp/Ghostty/GhosttyRuntime.swift`

**Step 1: 新增 helper**

- 增加 selection pasteboard 映射
- 增加 `getOpinionatedStringContents()`：
  - 优先读取 file URL 并做 shell escape
  - 回退 `.string`
  - 回退 `public.utf8-plain-text`

**Step 2: 接入 runtime**

- `handleReadClipboard(...)` 改用 helper，不再直接读 `.string`

### Task 3: 回归验证与文档同步

**Files:**
- Modify: `tasks/todo.md`
- Modify: `AGENTS.md`（若新增 helper 文件需补职责说明）

**Step 1: 定向验证**

Run: `swift test --package-path macos --filter GhosttyPasteboardTests`

**Step 2: 差异校验**

Run: `git diff --check`

**Step 3: 回填 Review**

- 在 `tasks/todo.md` 记录直接原因、设计层诱因、当前修复、验证证据与长期建议。
