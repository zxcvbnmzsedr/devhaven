# DevHaven 终端增强 Primitive-First 完整改造设计稿

## 背景

用户反馈：当前终端增强实现导致“终端内容都不见了，历史输入也没来”。

本轮排查已经确认，问题不只是单点回归，而是 **terminal launcher / shell integration / wrapper / agent hook** 四层职责耦合后，DevHaven 错误接管了用户 shell 的真实状态源：

- `src-tauri/src/terminal.rs` 为 zsh 强制注入 `HISTFILE`、`ZSH_COMPDUMP`、`ZDOTDIR`
- `scripts/shell-integration/zsh/.zshenv` 在 source 用户 `.zshenv` 后，又把 `ZDOTDIR` 恢复回 DevHaven 集成目录语义
- 实测 `zsh -ic 'print -r -- "$ZDOTDIR|$HISTFILE"'` 最终落到 `scripts/shell-integration/zsh/.zsh_history`
- 结果是 shell history、zsh-autosuggestions、补全缓存、用户 rc 语义全部被污染

这说明当前终端增强主线存在根本性设计问题：**DevHaven 把“注入能力”和“用户 shell 状态源”混成了一套机制。**

## 目标

以 **方案 C：primitive-first 完整改造** 为目标，将终端增强链路重构为：

1. DevHaven 只提供 primitive 与注入能力，不再接管用户 shell 状态。
2. shell integration 只负责 bootstrap，不再持有用户 history / compdump / ZDOTDIR 真相。
3. Codex / Claude 等 provider wrapper 统一退回适配层，只翻译 provider 事件到 DevHaven primitive。
4. Rust 侧逐步拥有通知、status、attention、session binding 等 durable primitive，前端只做 projection。
5. 在完成终端语义恢复的同时，为后续继续对齐 cmux 风格 primitive 打下稳定边界。

## 非目标

本轮不做：

- 完整重写 terminal runtime / PTY 传输层
- 一次性实现所有 provider 的深适配 parity
- tmux compatibility / claude teams / browser parity
- 彻底改写 quick command 主线
- 重做全部 UI 交互

## 根因总结

### 直接原因

当前 zsh 启动链路中，DevHaven 同时做了：

- login shell 启动
- `ZDOTDIR` wrapper 注入
- `HISTFILE` / `ZSH_COMPDUMP` 状态目录覆盖
- wrapper PATH 注入
- provider wrapper 注入

导致 zsh 的历史文件与 rc 语义不再指向用户的 HOME / 真实 ZDOTDIR。

### 设计层诱因

存在明显的职责不清与状态源分裂：

- launcher 负责太多
- shell bootstrap 和 shell state 难以区分
- wrapper 生效依赖 shell integration 细节
- provider 增强与终端基础语义耦合
- 前端/后端/脚本三层都可能偷偷“接管”用户 shell 行为

结论：**未发现只是单一代码错误；存在明显系统设计缺陷。**

## 架构原则

### 原则 1：DevHaven 不拥有用户 shell 状态源

DevHaven 不再持有以下真相：

- 用户 `HISTFILE`
- 用户 `ZDOTDIR`
- 用户 compdump 路径
- 用户 rc 生命周期

这些都必须回归用户自己的 HOME / 真实 shell 语义。

### 原则 2：DevHaven 只拥有注入能力

DevHaven 可以拥有：

- shell bootstrap 脚本
- wrapper bin PATH 注入
- `DEVHAVEN_*` / provider wrapper 路径注入
- control plane endpoint / identify / notify / session event primitive

### 原则 3：provider wrapper 只是 adapter

`codex` / `claude` wrapper 只允许：

- 定位真实命令
- 注入 hook / notify / session id
- 上报 primitive

不允许：

- 修改 history / compdump / rc 语义
- 依赖 integration 目录承载用户 shell 状态
- 把 provider 特判渗透到 launcher 层

### 原则 4：终端 primitive 先于 provider 体验

先建立稳定 primitive：

- terminal binding
- notify_target / notify
- set_status / clear_status
- set_agent_pid / clear_agent_pid
- mark read / unread / attention

provider 体验只是把各自 hook 翻译到这些 primitive。

## 目标分层

### Layer 1：Terminal Launcher

职责：

- 启动 login shell
- 注入最小必要环境（`TERM`、PATH 修正、`DEVHAVEN_*` 上下文）
- 注册 terminal binding

不负责：

- history / compdump 路径替换
- provider 生命周期判断
- 用户 rc 语义管理

### Layer 2：Shell Bootstrap

职责：

- 恢复真实 `ZDOTDIR` / 用户 shell 环境
- 追加 DevHaven bootstrap
- 保证 wrapper PATH 注入稳定可复现

不负责：

- 自己成为用户 shell 的状态目录
- 替代用户 `.zshenv/.zprofile/.zshrc/.zlogin`

### Layer 3：Wrapper / Hook Adapter

职责：

- 提供 `scripts/bin/{codex,claude}` shim
- 注入 provider 侧 hook / notify 配置
- 将 provider 事件翻译成 DevHaven primitive

不负责：

- 用户 shell 状态
- unread / focus auto-clear 生命周期
- UI 逻辑

### Layer 4：Primitive / Control Plane

职责：

- 持有 terminal binding / agent session / notification / status 等 durable primitive
- 对外提供统一 command / event
- 逐步承接 unread / focus / attention 生命周期

前端只消费 projection。

## 目标数据流

```text
terminal_create_session
  -> Rust launcher 注入最小 env + terminal binding
  -> 用户真实 login shell 启动
  -> shell bootstrap 恢复真实 ZDOTDIR / rc / history 语义
  -> wrapper PATH 生效
  -> 用户运行 codex/claude 等命令
  -> provider wrapper / hook 只翻译事件到 DevHaven primitive
  -> Rust control plane / primitive registry 更新状态
  -> 前端订阅 projection 渲染
```

## 分阶段整改方案

### Phase 1：恢复 shell 原生语义

目标：停止 DevHaven 对用户 history / ZDOTDIR / compdump 的接管。

动作：

- 删除 zsh `HISTFILE` / `ZSH_COMPDUMP` 强制注入
- 重写 `scripts/shell-integration/zsh/.zshenv`，在最早阶段恢复真实 `ZDOTDIR`
- 清理仓库中误写入的 `scripts/shell-integration/zsh/.zsh_history`
- 补最小回归测试，锁定 `ZDOTDIR` / `HISTFILE` 最终语义

交付标准：

- `zsh -ic 'print -r -- "$ZDOTDIR|$HISTFILE"'` 指向用户真实目录
- 历史输入、上箭头、autosuggestions 恢复

### Phase 2：重构 shell bootstrap 结构

目标：让 bootstrap 成为稳定薄层，而不是状态源。

动作：

- 重组 `scripts/shell-integration/` 目录
- 把 zsh bootstrap 从 wrapper 文件拆成“恢复用户语义”与“追加 DevHaven 注入”两段
- bash 也按同样原则整理，避免未来再次耦合
- 为 stacked injection（Ghostty/cmux/DevHaven 叠加）补回归测试

交付标准：

- shell integration 文件结构可解释
- 用户 shell 文件加载顺序明确且稳定
- PATH 注入与用户状态语义完全解耦

### Phase 3：引入 provider-neutral primitive

目标：让 wrapper 不再直接绑定 control plane 细节，而是走中间 primitive 层。

动作：

- Rust 侧补齐 / 收口：`notify_target`、`set_status`、`clear_status`、`set_agent_pid`、`clear_agent_pid` 等 primitive
- control plane 保留为 durable truth，但 provider wrapper 只依赖 primitive 命令契约
- 统一 Codex / Claude wrapper 的事件翻译形态

交付标准：

- provider wrapper 不再直接承载 UI 语义
- 后续新增 provider 时只需增加 adapter

### Phase 4：收口 unread / focus / attention 生命周期

目标：把当前散落在前端 effect 里的收尾逻辑逐步下沉到 Rust primitive 层。

动作：

- 梳理 auto-read / unread / focus-clear / notification suppression 规则
- 将可下沉逻辑优先迁移到 Rust
- 前端只保留投影与交互触发

交付标准：

- 通知闭环主要由 Rust primitive 拥有
- 前端不再承担终端增强的关键状态真相

### Phase 5：文档、设置与回滚能力

目标：使架构长期可维护。

动作：

- 更新 `AGENTS.md` 中终端增强边界与关键职责
- 增加设计文档 / 实施文档
- 提供 shell integration / wrapper 的降级开关
- 明确回滚路径

交付标准：

- 后续维护者能快速理解边界
- 出问题时可局部降级，不必整体回退终端功能

## 风险与应对

### 风险 1：用户个性化 shell 配置非常复杂

应对：

- 通过多层回归测试覆盖常见场景
- 提供 integration 关闭开关
- 优先保持“像原生 shell 一样”而不是“强控统一行为”

### 风险 2：wrapper 在 PATH 中失效

应对：

- 单独补 PATH/bootstrap 回归测试
- shell bootstrap 只负责 PATH 注入，不再混杂其他副作用

### 风险 3：control plane 与 primitive 双轨过渡期出现重复语义

应对：

- 先定义 primitive 契约，再逐步将 wrapper 从直接 control plane 写入迁移过去
- 每一阶段都保留兼容层，避免一次性大切换

## 验证策略

### 自动化验证

必须新增并长期保留：

- zsh `ZDOTDIR` 语义测试
- zsh `HISTFILE` 最终路径测试
- stacked injection（Ghostty/cmux/DevHaven）测试
- bash `PROMPT_COMMAND` / `HISTFILE` 语义测试
- wrapper PATH 命中测试
- provider wrapper 事件翻译测试
- primitive / control plane 契约测试

### 手工验证

至少验证：

- 上箭头能召回历史
- zsh-autosuggestions 恢复
- `which codex` / `which claude` 命中 wrapper
- `codex` / `claude` 运行增强能力仍生效
- 普通 shell 行为不受影响

## 推荐实施顺序

1. Phase 1 恢复 shell 原生语义
2. Phase 2 重构 shell bootstrap
3. Phase 3 建立 provider-neutral primitive
4. Phase 4 收口 notification lifecycle
5. Phase 5 文档、开关与回滚完善

## 预期收益

完成整改后，DevHaven 将从“通过 shell integration 偷接管用户状态源”的脆弱实现，转变为：

- 用户 shell 语义完整保留
- terminal enhancement 边界清晰
- provider 扩展成本降低
- control plane / primitive 方向与 cmux 更一致
- 后续继续做 Codex / Claude 增强时，不再以牺牲终端基础体验为代价
