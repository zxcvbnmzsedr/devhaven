# DevHaven 目录刷新与 Git 统计职责拆分设计

## 背景
当前 DevHaven 的“刷新项目”会走 `NativeAppViewModel.refreshProjectCatalog()`，并在一次全量 catalog rebuild 中同时完成两类工作：

1. 重新扫描目录、发现/移除项目；
2. 对每个 Git 仓库执行 `git rev-list --count HEAD` 与 `git log -n 1`，刷新提交数和最后提交摘要。

这导致“刷新目录”承担了不属于它的 Git 统计职责，用户在只想同步目录变化时，也必须等待整批 Git 子进程完成。结合当前本机数据，真正的慢点主要来自这部分 Git 调用，而不是目录枚举本身。

同时，现有模型与 UI 还存在一个边界问题：多处逻辑把 `gitCommits > 0` 当成“这是 Git 项目”的真相源。一旦把 Git 调用从目录刷新里移走，而不调整这层语义，新发现的 Git 项目就会被误判成“非 Git 项目”。

## 目标
1. 把“刷新目录”和“刷新 Git 元数据”拆成两条职责明确的链路；
2. 目录刷新只负责项目发现、目录属性更新和 worktree 过滤，不再执行任何 Git 子进程；
3. 旧项目在目录刷新后保留已有 Git 值，避免用户一刷新目录就丢失提交数/摘要；
4. 更新统计链路统一负责 `gitCommits`、`gitLastCommit`、`gitLastCommitMessage`、`gitDaily`；
5. 修正“Git 项目判断”语义，不再继续依赖 `gitCommits > 0` 作为 repo 类型真相源。

## 非目标
- 本次设计不直接引入后台自动 Git 刷新；
- 不在本次先解决 Git 统计链路的并发/缓存优化；
- 不修改现有 worktree 的业务语义；
- 不重做整个项目列表 UI，只做支撑新职责边界所必需的最小语义调整。

## 方案对比

### 方案 A：保留当前边界，只把 Git 调用改成 async / 并发
- 优点：不改产品语义，改动看起来较集中；
- 缺点：目录刷新仍然承担 Git 统计职责，只是“快一点”，没有解决边界不清的问题；用户“只刷新目录”的诉求仍然无法满足。

### 方案 B：目录刷新与 Git 统计彻底拆分，并新增轻量 Git 真相源（推荐）
- 做法：
  1. 目录刷新阶段只做目录发现、属性更新、轻量 Git repo 判定；
  2. 新增 `isGitRepository` 之类的显式字段，用于表示 repo 类型；
  3. 更新统计链路统一刷新所有昂贵 Git 元数据；
  4. 旧项目保留旧 Git 值，新项目显示为“Git 项目但统计未刷新”。
- 优点：职责边界最清楚，完全贴合用户需求；为后续并发/缓存优化预留了正确落点；
- 缺点：需要调整若干 UI / filter 对 `gitCommits > 0` 的依赖。

### 方案 C：目录刷新后立即显示列表，再后台异步补 Git 元数据
- 优点：用户体感最好，几乎秒回；
- 缺点：比方案 B 更复杂，需要明确多阶段 UI 状态与局部回填时序；如果不先拆清类型语义，很容易把旧问题带到后台任务里。

## 最终设计
采用 **方案 B**。

## 设计细节

### 1. `Project` 新增显式 Git 类型字段
在 `Project` 模型中新增轻量字段，建议命名：

- `isGitRepository: Bool`

职责边界：
- 只表示“这个路径是不是 Git repo”；
- 不表示 Git 统计是否最新；
- 不表示提交数是否已经计算。

该字段由目录刷新阶段通过轻量规则得出：
- 检查 `.git` 是否存在；
- 排除 Git worktree；
- 不执行任何 Git 子进程。

这样可以把“repo 类型真相”从 `gitCommits` 中独立出来。

### 2. 目录刷新只更新目录元数据，不再执行 Git 命令
`refreshProjectCatalog()` / `rebuildProjectCatalogSnapshot()` / `createProject()` 调整为：

目录刷新阶段仅更新：
- `id`
- `name`
- `path`
- `mtime`
- `size`
- `checksum`
- `checked`
- `isGitRepository`
- 既有标签 / scripts / worktrees 等非 Git 统计字段

目录刷新阶段明确不再更新：
- `gitCommits`
- `gitLastCommit`
- `gitLastCommitMessage`
- `gitDaily`

对于已存在项目：
- 保留旧 Git 值；
- 只覆写目录与类型相关字段。

对于新发现项目：
- `isGitRepository` 按轻量规则赋值；
- Git 统计字段保持默认空值/零值，等待后续“更新统计”刷新。

### 3. 更新统计链路统一负责 Git 元数据
把当前的 `refreshGitStatisticsAsync()` 从“只更新 gitDaily”升级成“统一刷新 Git 元数据 + 统计”。

刷新目标：
- `gitCommits`
- `gitLastCommit`
- `gitLastCommitMessage`
- `gitDaily`

刷新目标集也要同步调整：
- 从现在的 `project.gitCommits > 0` 改为 `project.isGitRepository == true`

这样新发现的 Git 项目，即使目录刷新阶段还没有 commitCount，也能被统计刷新链路正确覆盖。

### 4. 存储层新增 Git 元数据更新入口
当前 `LegacyCompatStore.updateProjectsGitDaily(...)` 只支持写 `git_daily`，新设计下需要新增或扩展为更完整的 Git 元数据更新入口，例如：

- `updateProjectsGitMetadata(...)`

职责：
- 根据路径匹配项目；
- 局部更新 Git 元数据字段；
- 不重新执行目录发现；
- 不影响与 Git 无关的项目字段。

这样可以避免“为了更新 Git 统计再走一遍目录 refresh”的职责倒灌。

### 5. UI 与过滤逻辑统一改用 `isGitRepository`
当前多个位置把 `gitCommits > 0` 当成 Git / 非 Git 的判定条件；这些地方都需要统一改语义。

#### 5.1 过滤逻辑
`NativeAppViewModel.matchesAllFilters(...)` 中：
- `gitOnly` 改为 `isGitRepository == true`
- `nonGitOnly` 改为 `isGitRepository == false`

#### 5.2 主列表 / 卡片展示
当前语义：
- `gitCommits > 0` → “xx 次提交”
- 否则 → “非 Git”

新语义：
- `isGitRepository == false` → “非 Git”
- `isGitRepository == true` 且已有 Git 统计 → “xx 次提交”
- `isGitRepository == true` 但尚未统计 → “Git 项目”或“待刷新统计”

为了最小改动，建议第一版显示：
- “Git 项目”

避免强行把尚未统计的 Git 项目误标成“非 Git”。

#### 5.3 详情页与工作区 Header
详情页中的“Git 提交”“最后摘要”以及 workspace 里的提交数 chip，也需要接受“Git 项目但统计尚未刷新”的状态：
- 提交数：显示“Git 项目”或“--”而不是“非 Git”
- 最后摘要：无值时显示 `--`

### 6. 旧值保留策略
用户已确认：
- 对已有项目，目录刷新后保留原有 Git 值；
- 只有手动触发“更新统计”时，才刷新新的 Git 元数据。

因此目录刷新不应主动清空：
- `gitCommits`
- `gitLastCommit`
- `gitLastCommitMessage`
- `gitDaily`

这意味着目录刷新之后，部分 Git 信息可能是旧值；这是新职责边界下的**有意缓存语义**，不是 bug。

## 影响范围
- `macos/Sources/DevHavenCore/Models/AppModels.swift`
- `macos/Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift`
- `macos/Sources/DevHavenCore/Storage/LegacyCompatStore.swift`
- 可能新增 Git 元数据存储模型 / helper
- `macos/Sources/DevHavenApp/MainContentView.swift`
- `macos/Sources/DevHavenApp/ProjectDetailRootView.swift`
- `macos/Sources/DevHavenApp/WorkspaceHostView.swift`
- 相关测试文件
- `tasks/todo.md`
- 如最终落地实现调整了架构边界，还需同步更新 `AGENTS.md`

## 风险与控制

### 风险 1：新发现 Git 项目被误显示为“非 Git”
控制：新增显式 `isGitRepository` 字段，统一改用它做 repo 类型判断。

### 风险 2：目录刷新后 Git 信息看起来“没更新”
控制：这是有意保留旧值的设计语义；UI 文案中避免把无统计值误表述为“非 Git”。

### 风险 3：统计刷新链路仍漏掉新 Git 项目
控制：统计刷新目标集从 `gitCommits > 0` 改为 `isGitRepository == true`。

### 风险 4：存储层局部更新逻辑破坏其他字段
控制：新增专用 Git 元数据更新入口，只按 path 局部更新 Git 字段，不重新覆盖整个项目对象。

## 验证策略
1. 先补失败测试，覆盖：
   - 目录刷新不再调用 Git 子进程；
   - 目录刷新会维护 `isGitRepository`，但保留旧 Git 值；
   - 新发现的 Git 项目在首次目录刷新后不会被判成非 Git；
   - 统计刷新会覆盖 `gitCommits` / `gitLastCommit` / `gitLastCommitMessage` / `gitDaily`；
   - Git filter 改为基于 `isGitRepository`；
2. 跑定向测试确认红灯；
3. 以最小改动实现职责拆分；
4. 跑相关 Core / App 测试与至少一轮 `swift test --package-path macos` 回归；
5. 人工验证：刷新目录后项目列表明显更快返回，且手动“更新统计”后 Git 提交数/摘要正确更新。
