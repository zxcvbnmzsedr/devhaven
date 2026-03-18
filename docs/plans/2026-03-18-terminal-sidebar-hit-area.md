# 终端工作区左侧项目点击区域扩大 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让终端工作区左侧“已打开项目”里的根项目行与 worktree 行支持整行点击，降低误触和点不中的问题。

**Architecture:** 保持 `src/components/terminal/TerminalWorkspaceWindow.tsx` 现有布局与右侧操作按钮不变，只把“主选择动作”从文字按钮扩大为整行容器命中。根项目行与 worktree 行统一补上键盘可达性，右侧刷新/新建/关闭/删除等按钮继续通过 `stopPropagation()` 保持独立行为。

**Tech Stack:** React 19、TypeScript、UnoCSS 原子类、现有 Node/TypeScript 构建验证链路。

---

### Task 1: 收口左侧项目行与 worktree 行的整行点击行为

**Files:**
- Modify: `src/components/terminal/TerminalWorkspaceWindow.tsx`
- Verify: `node node_modules/typescript/bin/tsc --noEmit`
- Verify: `pnpm build`

**Step 1: 调整根项目行的命中区域**

- 把根项目行当前“只有名称按钮可点”的结构改成“整行容器可点”。
- 文字区域改为普通内容容器，不再嵌套主按钮，避免无效的 button 套 button 结构。
- 保持右侧状态点、未读数、Codex 运行点可继续显示。

**Step 2: 调整 worktree 行的命中区域**

- 把 worktree 行当前“主要只有文字区域可点”的结构改成整行容器点击。
- 保持创建中 / 失败态的禁用逻辑不变；不可打开时不提供整行激活。
- 保持右侧“重试 / 删除”等按钮的独立点击行为。

**Step 3: 补齐键盘可达性**

- 给可点击行补 `role="button"`、`tabIndex={0}`。
- 仅在行容器自身聚焦时响应 `Enter / Space` 激活，避免右侧内嵌按钮触发冒泡误选中。

**Step 4: 运行验证**

Run: `node node_modules/typescript/bin/tsc --noEmit`  
Expected: 通过，无 TypeScript 报错。

Run: `pnpm build`  
Expected: 构建通过，无新增编译错误。
