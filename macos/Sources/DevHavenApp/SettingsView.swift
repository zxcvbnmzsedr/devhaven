import AppKit
import SwiftUI
import DevHavenCore

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    private enum Category: String, CaseIterable, Identifiable {
        case general
        case terminal
        case workflow

        var id: String { rawValue }

        init?(section: SettingsNavigationSection) {
            self.init(rawValue: section.rawValue)
        }

        var title: String {
            switch self {
            case .general:
                return "常规"
            case .terminal:
                return "终端"
            case .workflow:
                return "协作"
            }
        }

        var description: String {
            switch self {
            case .general:
                return "应用版本、发布边界与兼容说明。"
            case .terminal:
                return "直接编辑 Ghostty 配置文件与查看生效路径。"
            case .workflow:
                return "Git 身份与提交协作信息。"
            }
        }
    }

    private let originalSettings: AppSettings
    private let onCancel: () -> Void
    private let onSave: (AppSettings) -> Void
    private let updateSupportDescription: String
    private let updateDiagnostics: String
    private let isUpdaterSupported: Bool
    private let supportsAutomaticUpdates: Bool
    private let canOpenUpdateDownloadPage: Bool
    private let onCheckForUpdates: () -> Void
    private let onOpenUpdateDownloadPage: () -> Void
    private let onCopyUpdateDiagnostics: () -> Void

    @State private var gitIdentities: [GitIdentity]
    @State private var workspaceOpenProjectShortcut: AppMenuShortcut
    @State private var workspaceEditorDisplayOptions: WorkspaceEditorDisplayOptions
    @State private var updateChannel: UpdateChannel
    @State private var updateAutomaticallyChecks: Bool
    @State private var updateAutomaticallyDownloads: Bool
    @State private var workspaceInAppNotificationsEnabled: Bool
    @State private var workspaceNotificationSoundEnabled: Bool
    @State private var workspaceSystemNotificationsEnabled: Bool
    @State private var moveNotifiedWorktreeToTop: Bool
    @State private var activeCategory: Category = .general
    @State private var terminalConfigStatusMessage: String?
    @State private var terminalConfigErrorMessage: String?

    init(
        settings: AppSettings,
        initialCategory: SettingsNavigationSection? = nil,
        onCancel: @escaping () -> Void,
        onSave: @escaping (AppSettings) -> Void,
        updateSupportDescription: String = "当前运行态不支持自动升级。",
        updateDiagnostics: String = "",
        isUpdaterSupported: Bool = false,
        supportsAutomaticUpdates: Bool = false,
        canOpenUpdateDownloadPage: Bool = false,
        onCheckForUpdates: @escaping () -> Void = {},
        onOpenUpdateDownloadPage: @escaping () -> Void = {},
        onCopyUpdateDiagnostics: @escaping () -> Void = {}
    ) {
        self.originalSettings = settings
        self.onCancel = onCancel
        self.onSave = onSave
        self.updateSupportDescription = updateSupportDescription
        self.updateDiagnostics = updateDiagnostics
        self.isUpdaterSupported = isUpdaterSupported
        self.supportsAutomaticUpdates = supportsAutomaticUpdates
        self.canOpenUpdateDownloadPage = canOpenUpdateDownloadPage
        self.onCheckForUpdates = onCheckForUpdates
        self.onOpenUpdateDownloadPage = onOpenUpdateDownloadPage
        self.onCopyUpdateDiagnostics = onCopyUpdateDiagnostics
        _gitIdentities = State(initialValue: settings.gitIdentities)
        _workspaceOpenProjectShortcut = State(initialValue: settings.workspaceOpenProjectShortcut)
        _workspaceEditorDisplayOptions = State(initialValue: settings.workspaceEditorDisplayOptions)
        _updateChannel = State(initialValue: settings.updateChannel)
        _updateAutomaticallyChecks = State(initialValue: settings.updateAutomaticallyChecks)
        _updateAutomaticallyDownloads = State(initialValue: settings.updateAutomaticallyDownloads)
        _workspaceInAppNotificationsEnabled = State(initialValue: settings.workspaceInAppNotificationsEnabled)
        _workspaceNotificationSoundEnabled = State(initialValue: settings.workspaceNotificationSoundEnabled)
        _workspaceSystemNotificationsEnabled = State(initialValue: settings.workspaceSystemNotificationsEnabled)
        _moveNotifiedWorktreeToTop = State(initialValue: settings.moveNotifiedWorktreeToTop)
        _activeCategory = State(initialValue: initialCategory.flatMap(Category.init(section:)) ?? .general)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            HStack(spacing: 14) {
                categorySidebar
                contentPanel
            }
            .padding(18)

            footer
        }
        .frame(minWidth: 980, minHeight: 720)
        .background(NativeTheme.window)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("设置")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(NativeTheme.textPrimary)
                Text("统一管理应用阶段、终端体验与 Git 协作配置。")
                    .font(.subheadline)
                    .foregroundStyle(NativeTheme.textSecondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                statusBadge

                Button {
                    handleClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(NativeTheme.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(NativeTheme.elevated)
                        .clipShape(.rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭设置")
            }
        }
        .padding(22)
        .background(NativeTheme.surface)
    }

    private var categorySidebar: some View {
        VStack(spacing: 8) {
            ForEach(Category.allCases) { category in
                Button {
                    activeCategory = category
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(category.title)
                            .font(.headline)
                            .foregroundStyle(NativeTheme.textPrimary)
                        Text(category.description)
                            .font(.caption)
                            .foregroundStyle(NativeTheme.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(activeCategory == category ? NativeTheme.accent.opacity(0.12) : NativeTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(activeCategory == category ? NativeTheme.accent.opacity(0.7) : NativeTheme.border, lineWidth: 1)
                    )
                    .clipShape(.rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 250)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var contentPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(activeCategory.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(NativeTheme.textPrimary)
                Text(activeCategory.description)
                    .font(.subheadline)
                    .foregroundStyle(NativeTheme.textSecondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch activeCategory {
                    case .general:
                        generalContent
                    case .terminal:
                        terminalContent
                    case .workflow:
                        workflowContent
                    }
                }
                .padding(.trailing, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
        .background(NativeTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(NativeTheme.border, lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 18))
    }

    private var generalContent: some View {
        Group {
            settingsCard(title: "版本与阶段", description: "当前仓库已切换为纯 macOS 原生主线，旧的 React / Tauri 兼容源码已移除。") {
                HStack(spacing: 10) {
                    infoBadge(title: "当前版本", value: versionLabel)
                    infoBadge(title: "运行范围", value: "仅 macOS")
                }
            }

            settingsCard(title: "打开项目快捷键", description: "配置 workspace 中“打开项目”菜单命令的快捷键；Command（⌘）固定启用。") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        labeledField(title: "主按键") {
                            Picker("主按键", selection: $workspaceOpenProjectShortcut.key) {
                                ForEach(AppMenuShortcutKey.allCases) { key in
                                    Text(key.title).tag(key)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }

                        Toggle("Shift（⇧）", isOn: $workspaceOpenProjectShortcut.usesShift)
                            .toggleStyle(.switch)
                        Toggle("Option（⌥）", isOn: $workspaceOpenProjectShortcut.usesOption)
                            .toggleStyle(.switch)
                        Toggle("Control（⌃）", isOn: $workspaceOpenProjectShortcut.usesControl)
                            .toggleStyle(.switch)
                    }

                    Text("当前预览：\(workspaceOpenProjectShortcut.displayLabel)")
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textSecondary)
                }
            }

            settingsCard(title: "编辑器显示", description: "配置普通文件编辑器的默认显示选项，尽量贴近 IDEA 的常用 view options。") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("显示行号", isOn: $workspaceEditorDisplayOptions.showsLineNumbers)
                    Toggle("高亮当前行", isOn: $workspaceEditorDisplayOptions.highlightsCurrentLine)
                    Toggle("软换行", isOn: $workspaceEditorDisplayOptions.usesSoftWraps)
                    Toggle("显示空白字符", isOn: $workspaceEditorDisplayOptions.showsWhitespaceCharacters)
                    Toggle("显示右边界", isOn: $workspaceEditorDisplayOptions.showsRightMargin)

                    if workspaceEditorDisplayOptions.showsRightMargin {
                        HStack(spacing: 12) {
                            Text("右边界列")
                                .font(.caption)
                                .foregroundStyle(NativeTheme.textSecondary)

                            Stepper(
                                value: $workspaceEditorDisplayOptions.rightMarginColumn,
                                in: 40...240,
                                step: 4
                            ) {
                                Text("\(workspaceEditorDisplayOptions.rightMarginColumn)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(NativeTheme.textPrimary)
                            }
                            .labelsHidden()
                        }
                    }
                }
                .toggleStyle(.switch)
            }

            settingsCard(title: "仓库边界", description: "3.0.0 起 GitHub Release 只发布 macOS 原生 `.app`。") {
                Text("仓库内仅保留 `macos/` 原生应用主线；旧的 React / Vite / Tauri 源码与对应打包入口已从仓库移除。数据文件仍继续兼容 `~/.devhaven/*`。")
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
            }

            settingsCard(title: "应用升级", description: "管理稳定版 / Nightly 通道，以及自动检查和自动下载策略。") {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("升级通道")
                            .font(.caption)
                            .foregroundStyle(NativeTheme.textSecondary)

                        Picker("升级通道", selection: $updateChannel) {
                            ForEach(UpdateChannel.allCases) { channel in
                                Text(channel.title).tag(channel)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Toggle("自动检查更新", isOn: $updateAutomaticallyChecks)
                        .toggleStyle(.switch)

                    Toggle("自动下载更新", isOn: $updateAutomaticallyDownloads)
                        .toggleStyle(.switch)
                        .disabled(!updateAutomaticallyChecks || !supportsAutomaticUpdates)

                    Text(updateSupportDescription)
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textSecondary)

                    HStack {
                        Button("立即检查更新") {
                            onCheckForUpdates()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(NativeTheme.accent)
                        .disabled(!isUpdaterSupported)

                        Button("打开下载页") {
                            onOpenUpdateDownloadPage()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!canOpenUpdateDownloadPage)

                        Button("复制升级诊断") {
                            onCopyUpdateDiagnostics()
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }

                    Text(updateDiagnostics)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(NativeTheme.textSecondary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NativeTheme.elevated)
                        .clipShape(.rect(cornerRadius: 12))
                }
            }
        }
    }

    private var terminalContent: some View {
        Group {
            settingsCard(
                title: "Ghostty 配置",
                description: "原生终端的主题、字体、键位与渲染行为统一以 Ghostty 配置文件为真相源。"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("DevHaven 会优先读取 `~/.devhaven/ghostty/config` 或 `config.ghostty`；如果这里还没有 DevHaven 专属配置，则会回退到独立 Ghostty 的现有全局配置。首次点击“编辑 Ghostty 配置文件”时，会自动创建 `~/.devhaven/ghostty/config`。")
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textSecondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("当前直达路径")
                            .font(.caption)
                            .foregroundStyle(NativeTheme.textSecondary)
                        Text(ghosttyConfigFileURL.path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(NativeTheme.textPrimary)
                            .textSelection(.enabled)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(NativeTheme.elevated)
                            .clipShape(.rect(cornerRadius: 12))
                    }

                    HStack(spacing: 12) {
                        Button("编辑 Ghostty 配置文件") {
                            editGhosttyConfigFile()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(NativeTheme.accent)

                        Button("打开配置目录") {
                            openGhosttyConfigDirectory()
                        }
                        .buttonStyle(.bordered)
                    }

                    if let terminalConfigStatusMessage {
                        terminalConfigNotice(terminalConfigStatusMessage, isError: false)
                    }

                    if let terminalConfigErrorMessage {
                        terminalConfigNotice(terminalConfigErrorMessage, isError: true)
                    }
                }
            }

            settingsCard(
                title: "工作区通知",
                description: "控制工作区内的 bell、系统通知与收到事件后的排序提升策略。"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("应用内工作区通知", isOn: $workspaceInAppNotificationsEnabled)
                    Toggle("提示音", isOn: $workspaceNotificationSoundEnabled)
                    Toggle("系统通知", isOn: $workspaceSystemNotificationsEnabled)
                    Toggle("收到通知时将 worktree 置顶", isOn: $moveNotifiedWorktreeToTop)
                }
                .toggleStyle(.switch)
            }
        }
    }

    private var workflowContent: some View {
        settingsCard(title: "Git 身份", description: "维护常用提交身份，保存时会自动清理空行。") {
            if gitIdentities.isEmpty {
                Text("暂无 Git 身份，点击下方按钮添加。")
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NativeTheme.elevated)
                    .clipShape(.rect(cornerRadius: 12))
            }

            VStack(spacing: 12) {
                ForEach(Array(gitIdentities.enumerated()), id: \.offset) { index, identity in
                    VStack(alignment: .leading, spacing: 10) {
                        Text("身份 \(index + 1)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NativeTheme.textSecondary)

                        HStack(spacing: 12) {
                            labeledField(title: "用户名") {
                                TextField("用户名", text: Binding(
                                    get: { gitIdentities[index].name },
                                    set: { gitIdentities[index].name = $0 }
                                ))
                                .textFieldStyle(.plain)
                                .foregroundStyle(NativeTheme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(NativeTheme.elevated)
                                .clipShape(.rect(cornerRadius: 12))
                            }

                            labeledField(title: "邮箱") {
                                TextField("邮箱", text: Binding(
                                    get: { gitIdentities[index].email },
                                    set: { gitIdentities[index].email = $0 }
                                ))
                                .textFieldStyle(.plain)
                                .foregroundStyle(NativeTheme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(NativeTheme.elevated)
                                .clipShape(.rect(cornerRadius: 12))
                            }

                            Button("移除", role: .destructive) {
                                gitIdentities.remove(at: index)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(14)
                    .background(NativeTheme.elevated)
                    .clipShape(.rect(cornerRadius: 14))
                }
            }

            HStack {
                Spacer()
                Button("添加身份") {
                    gitIdentities.append(GitIdentity(name: "", email: ""))
                }
                .buttonStyle(.borderedProminent)
                .tint(NativeTheme.accent)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(isDirty ? "检测到未保存变更，关闭时会自动写回到 `app_state.json`。" : "当前设置已同步。")
                .font(.caption)
                .foregroundStyle(NativeTheme.textSecondary)

            Spacer(minLength: 12)

            Button(isDirty ? "保存并关闭" : "关闭") {
                handleClose()
            }
            .buttonStyle(.borderedProminent)
            .tint(NativeTheme.accent)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(NativeTheme.surface)
    }

    private var statusBadge: some View {
        Text(isDirty ? "有未保存变更" : "已同步")
            .font(.caption.weight(.medium))
            .foregroundStyle(isDirty ? NativeTheme.accent : NativeTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isDirty ? NativeTheme.accent.opacity(0.12) : NativeTheme.elevated)
            .clipShape(.capsule)
    }

    private var versionLabel: String {
        if let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, !short.isEmpty {
            return short
        }
        return "DevHaven Native Preview"
    }

    private var normalizedGitIdentities: [GitIdentity] {
        gitIdentities.filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !$0.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var nextSettings: AppSettings {
        AppSettings(
            editorOpenTool: originalSettings.editorOpenTool,
            workspaceEditorDisplayOptions: workspaceEditorDisplayOptions,
            terminalOpenTool: originalSettings.terminalOpenTool,
            terminalUseWebglRenderer: originalSettings.terminalUseWebglRenderer,
            terminalTheme: originalSettings.terminalTheme,
            workspaceOpenProjectShortcut: workspaceOpenProjectShortcut,
            updateChannel: updateChannel,
            updateAutomaticallyChecks: updateAutomaticallyChecks,
            updateAutomaticallyDownloads: updateAutomaticallyDownloads,
            gitIdentities: normalizedGitIdentities,
            projectListViewMode: originalSettings.projectListViewMode,
            workspaceSidebarWidth: originalSettings.workspaceSidebarWidth,
            workspaceInAppNotificationsEnabled: workspaceInAppNotificationsEnabled,
            workspaceNotificationSoundEnabled: workspaceNotificationSoundEnabled,
            workspaceSystemNotificationsEnabled: workspaceSystemNotificationsEnabled,
            moveNotifiedWorktreeToTop: moveNotifiedWorktreeToTop,
            viteDevPort: originalSettings.viteDevPort,
            webEnabled: originalSettings.webEnabled,
            webBindHost: originalSettings.webBindHost,
            webBindPort: originalSettings.webBindPort
        )
    }

    private var ghosttyConfigFileURL: URL {
        GhosttyRuntime.editableConfigFileURL()
    }

    private var isDirty: Bool {
        normalizedGitIdentities != originalSettings.gitIdentities.filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !$0.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
            || workspaceOpenProjectShortcut != originalSettings.workspaceOpenProjectShortcut
            || workspaceEditorDisplayOptions != originalSettings.workspaceEditorDisplayOptions
            || updateChannel != originalSettings.updateChannel
            || updateAutomaticallyChecks != originalSettings.updateAutomaticallyChecks
            || updateAutomaticallyDownloads != originalSettings.updateAutomaticallyDownloads
            || workspaceInAppNotificationsEnabled != originalSettings.workspaceInAppNotificationsEnabled
            || workspaceNotificationSoundEnabled != originalSettings.workspaceNotificationSoundEnabled
            || workspaceSystemNotificationsEnabled != originalSettings.workspaceSystemNotificationsEnabled
            || moveNotifiedWorktreeToTop != originalSettings.moveNotifiedWorktreeToTop
    }

    private func handleClose() {
        if isDirty {
            onSave(nextSettings)
        } else {
            onCancel()
        }
        dismiss()
    }

    private func settingsCard<Content: View>(title: String, description: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(NativeTheme.textPrimary)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(NativeTheme.window)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(NativeTheme.border, lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 16))
    }

    private func infoBadge(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(NativeTheme.textSecondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(NativeTheme.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(NativeTheme.elevated)
        .clipShape(.rect(cornerRadius: 12))
    }

    private func labeledField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(NativeTheme.textSecondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func terminalConfigNotice(_ text: String, isError: Bool) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(isError ? Color.red : NativeTheme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isError ? Color.red.opacity(0.08) : NativeTheme.elevated)
            .clipShape(.rect(cornerRadius: 12))
    }

    private func editGhosttyConfigFile() {
        do {
            let configURL = try GhosttyRuntime.ensureEditableConfigFile()
            terminalConfigErrorMessage = nil
            terminalConfigStatusMessage = "已打开配置文件：\(configURL.path)"
            NSWorkspace.shared.open(configURL)
        } catch {
            terminalConfigStatusMessage = nil
            terminalConfigErrorMessage = error.localizedDescription
        }
    }

    private func openGhosttyConfigDirectory() {
        let directoryURL = ghosttyConfigFileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            terminalConfigErrorMessage = nil
            terminalConfigStatusMessage = "已打开配置目录：\(directoryURL.path)"
            NSWorkspace.shared.open(directoryURL)
        } catch {
            terminalConfigStatusMessage = nil
            terminalConfigErrorMessage = "Ghostty 配置目录创建失败：\(directoryURL.path)"
        }
    }
}
