# DevHaven 升级终局方案设计

**目标：** 为 DevHaven 建立完整的 macOS 自升级体系，覆盖 stable/nightly 双通道、签名与 notarization、appcast staged 发布、用户侧更新设置与检查入口，并为后续 delta 更新保留扩展位。

**核心结论：** 继续复用现有 Swift Package 业务代码与原生 UI 主线，但把“升级能力”显式收口为独立的发布/运行时链路：应用内使用 Sparkle 运行更新检查与安装；发布侧使用 staged appcast 策略，先上传安装资产再提升 feed；版本比较以单调递增的 `CFBundleVersion` 为真相源。

## 设计范围

- 客户端：
  - 更新通道设置（stable / nightly）
  - 自动检查 / 自动下载设置
  - 手动“检查更新”入口
  - 更新诊断信息导出
  - 开发态 / 非 `.app` bundle 环境下自动禁用 updater
- 打包：
  - Sparkle.xcframework 与工具链 vendor 管理
  - `.app` 组装时嵌入 Sparkle.framework
  - Info.plist 写入 `CFBundleVersion`、`SUFeedURL`、`SUPublicEDKey` 等元数据
- 发布：
  - stable staged appcast 发布
  - nightly 独立 workflow 与 appcast
  - 为后续 delta 更新接入 `generate_appcast` 保留结构

## 模块边界

### 1. DevHavenCore
保留业务模型、设置、持久化与 ViewModel，不直接依赖 Sparkle。仅新增更新偏好设置字段与版本元数据模型。

### 2. DevHavenApp
保留原有 SwiftUI + Ghostty UI 主线，新增 updater runtime 封装与设置页/菜单入口，但 UI 只消费抽象更新状态与动作，不直接分散处理 feed 或发布逻辑。

### 3. Vendor / Packaging
新增 Sparkle vendor 准备脚本，与 Ghostty vendor 并列。`build-native-app.sh` 负责把 Sparkle.framework 嵌入 `.app` 的 `Contents/Frameworks/`，并写入 release 元数据。

### 4. Release Infrastructure
release workflow 改为：准备 tag/版本 -> 构建/签名/打包 -> 上传 zip/dmg/appcast-staged -> 验证 -> promote appcast。nightly workflow 走独立 tag/channel。

## 运行时数据流

```text
用户设置/菜单
  -> DevHavenUpdateController
  -> Sparkle updater
  -> 解析 stable/nightly feed
  -> 更新状态 / 诊断
  -> SettingsView / CommandMenu
```

## 发布数据流

```text
tag 或 nightly 触发
  -> 解析版本/build/channel
  -> 准备 Ghostty + Sparkle vendor
  -> 构建并组装 .app
  -> 签名/notarize
  -> 上传 immutable assets
  -> 生成 appcast-staged.xml
  -> 验证后 promote 到 stable/nightly appcast
```

## 关键设计决策

1. `CFBundleShortVersionString` 继续表达用户可见版本；`CFBundleVersion` 改为单调递增 build number。
2. updater 在开发态 `swift run` 中默认禁用，避免非 `.app` bundle 环境误触发 Sparkle。
3. stable 与 nightly 使用独立 feed；nightly workflow 可进一步扩展为独立 bundle id，但当前实现先收口 feed 隔离。
4. appcast 永远最后发布，避免客户端先看到 feed、后拿不到安装资产。
5. delta 更新先把工具链与 workflow 结构接入，但以完整包更新为当前主路径。
