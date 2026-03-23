# DevHaven Ghostty 搜索浮层右上角定位设计

## 背景
当前 DevHaven 已经补齐 Ghostty 搜索闭环，但搜索浮层默认跟随 `GhosttySurfaceHost` 的 `topLeading` 布局，实际显示在 terminal 区域左上角。用户明确希望搜索框固定在 **右上角**，而不是可拖动或继续停留在左上角。

## 目标
1. 搜索浮层固定显示在 terminal 区域右上角；
2. 保持现有搜索功能、输入、上下一个、关闭逻辑不变；
3. 不引入新的拖动状态、持久化位置或额外布局真相源；
4. 尽量不影响 startup overlay 的现有显示位置。

## 非目标
- 不支持拖动搜索框；
- 不支持记住搜索框位置；
- 不重构全部 overlay 布局系统；
- 不修改搜索行为本身。

## 方案比较

### 方案 A：只把搜索浮层固定到右上角（推荐）
- 做法：
  1. 保持 `GhosttySurfaceSearchOverlay` 的内部内容和行为不变；
  2. 仅在 `GhosttySurfaceHost` 调整其父级布局，使其固定对齐到 `topTrailing`。
- 优点：改动最小、风险最低、完全符合当前需求；
- 缺点：未来若要支持拖动/记忆位置，还需要继续扩展。

### 方案 B：右上角固定 + 专门新增 overlay 位置策略类型
- 优点：后续扩展性更好；
- 缺点：对当前需求过度设计，会引入额外抽象。

### 方案 C：统一重构 startup/search overlay 布局系统
- 优点：未来 overlay 能力最完整；
- 缺点：明显超出本次范围，不符合最少修改原则。

## 最终设计
采用 **方案 A**。

### 1. 保留 `GhosttySurfaceSearchOverlay` 的逻辑
搜索输入、`search:<needle>`、`navigate_search:*`、`end_search`、关闭后恢复 terminal focus 等逻辑全部保持不变。

### 2. 只调整 `GhosttySurfaceHost` 中的定位
将搜索浮层的宿主布局从当前默认左上角，改成：

- 占满 terminal overlay 容器；
- 以 `topTrailing` 对齐；
- 保留既有 padding。

这样 startup overlay 仍可继续停留在左上角，而搜索浮层固定在右上角，两者不互相争夺同一角。

## 影响范围
- `macos/Sources/DevHavenApp/Ghostty/GhosttySurfaceHost.swift`
- `macos/Tests/DevHavenAppTests/GhosttySurfaceSearchOverlayTests.swift`
- `tasks/todo.md`

## 风险与控制

### 风险 1：改动父级布局后影响 startup overlay
控制：只对搜索浮层单独加 `topTrailing` 对齐，不修改 startup overlay 的原有布局。

### 风险 2：为了改定位误碰搜索行为
控制：不改 `GhosttySurfaceSearchOverlay.swift` 的搜索逻辑，只改宿主挂载位置。

## 验证策略
1. 先写失败测试，要求宿主层显式以 `topTrailing` 对齐搜索浮层；
2. 跑定向测试确认红灯；
3. 最小改动实现；
4. 跑定向测试和 `swift build --package-path macos` 验证。
