import SwiftUI
import DevHavenCore

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    private enum Category: String, CaseIterable, Identifiable {
        case general
        case terminal
        case scripts
        case workflow

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general:
                return "常规"
            case .terminal:
                return "终端"
            case .scripts:
                return "脚本"
            case .workflow:
                return "协作"
            }
        }

        var description: String {
            switch self {
            case .general:
                return "应用阶段说明与浏览器访问端口。"
            case .terminal:
                return "终端渲染与主题显示配置。"
            case .scripts:
                return "通用脚本目录与后续迁移进度。"
            case .workflow:
                return "Git 身份与提交协作信息。"
            }
        }
    }

    private let originalSettings: AppSettings
    private let onCancel: () -> Void
    private let onSave: (AppSettings) -> Void

    @State private var terminalUseWebglRenderer: Bool
    @State private var terminalFollowSystem: Bool
    @State private var terminalSingleTheme: String
    @State private var terminalLightTheme: String
    @State private var terminalDarkTheme: String
    @State private var viteDevPortInput: String
    @State private var gitIdentities: [GitIdentity]
    @State private var activeCategory: Category = .general

    init(settings: AppSettings, onCancel: @escaping () -> Void, onSave: @escaping (AppSettings) -> Void) {
        self.originalSettings = settings
        self.onCancel = onCancel
        self.onSave = onSave

        let parsed = TerminalThemeSetting.parse(settings.terminalTheme)
        _terminalUseWebglRenderer = State(initialValue: settings.terminalUseWebglRenderer)
        _terminalFollowSystem = State(initialValue: parsed.isSystem)
        _terminalSingleTheme = State(initialValue: parsed.singleTheme)
        _terminalLightTheme = State(initialValue: parsed.lightTheme)
        _terminalDarkTheme = State(initialValue: parsed.darkTheme)
        _viteDevPortInput = State(initialValue: String(settings.viteDevPort))
        _gitIdentities = State(initialValue: settings.gitIdentities)
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
                Text("统一管理应用阶段、终端体验、脚本目录与 Git 协作配置。")
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
                    case .scripts:
                        scriptsContent
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
            settingsCard(title: "版本与阶段", description: "当前原生版以追平 Tauri 主界面为主，暂不覆盖终端工作区与脚本中心。") {
                HStack(spacing: 10) {
                    infoBadge(title: "当前版本", value: versionLabel)
                    infoBadge(title: "运行范围", value: "仅 macOS")
                }
            }

            settingsCard(title: "浏览器访问端口", description: "用于浏览器访问 DevHaven 的端口；修改后需重启应用或开发服务。") {
                labeledField(title: "端口") {
                    TextField("1420", text: $viteDevPortInput)
                        .textFieldStyle(.plain)
                        .foregroundStyle(NativeTheme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(NativeTheme.elevated)
                        .clipShape(.rect(cornerRadius: 12))
                        .frame(maxWidth: 220)
                }
                Text("当前原生版继续沿用 `app_state.json` 里的 `viteDevPort` 字段，便于与旧数据保持兼容。")
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
            }
        }
    }

    private var terminalContent: some View {
        Group {
            settingsCard(title: "渲染性能", description: "根据设备能力选择终端渲染策略。") {
                SettingsToggleRow(
                    title: "启用 WebGL 渲染",
                    description: "通常可提升高频输出与滚动场景下的终端性能。",
                    isOn: $terminalUseWebglRenderer
                )
            }

            settingsCard(title: "主题", description: "支持固定主题或跟随系统浅/深色。") {
                SettingsToggleRow(
                    title: "跟随系统浅 / 深色",
                    description: "开启后可分别设置浅色与深色主题。",
                    isOn: $terminalFollowSystem
                )

                if terminalFollowSystem {
                    HStack(spacing: 12) {
                        labeledField(title: "浅色主题") {
                            Picker("浅色主题", selection: $terminalLightTheme) {
                                ForEach(TerminalThemeSetting.availableThemes, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        labeledField(title: "深色主题") {
                            Picker("深色主题", selection: $terminalDarkTheme) {
                                ForEach(TerminalThemeSetting.availableThemes, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    labeledField(title: "终端主题") {
                        Picker("终端主题", selection: $terminalSingleTheme) {
                            ForEach(TerminalThemeSetting.availableThemes, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var scriptsContent: some View {
        SharedScriptsManagerView(root: sharedScriptsRoot)
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

    private var sharedScriptsRoot: String {
        let trimmed = originalSettings.sharedScriptsRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "~/.devhaven/scripts" : trimmed
    }

    private var normalizedViteDevPort: Int {
        let trimmed = viteDevPortInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), (1...65535).contains(value) else {
            return originalSettings.viteDevPort
        }
        return value
    }

    private var nextSettings: AppSettings {
        AppSettings(
            editorOpenTool: originalSettings.editorOpenTool,
            terminalOpenTool: originalSettings.terminalOpenTool,
            terminalUseWebglRenderer: terminalUseWebglRenderer,
            terminalTheme: terminalThemeSetting,
            gitIdentities: normalizedGitIdentities,
            projectListViewMode: originalSettings.projectListViewMode,
            sharedScriptsRoot: sharedScriptsRoot,
            viteDevPort: normalizedViteDevPort,
            webEnabled: originalSettings.webEnabled,
            webBindHost: originalSettings.webBindHost,
            webBindPort: originalSettings.webBindPort
        )
    }

    private var terminalThemeSetting: String {
        if terminalFollowSystem {
            return "light:\(terminalLightTheme),dark:\(terminalDarkTheme)"
        }
        return terminalSingleTheme
    }

    private var isDirty: Bool {
        canonicalThemeSetting(nextSettings.terminalTheme) != canonicalThemeSetting(originalSettings.terminalTheme)
            || nextSettings.terminalUseWebglRenderer != originalSettings.terminalUseWebglRenderer
            || nextSettings.viteDevPort != originalSettings.viteDevPort
            || normalizedGitIdentities != originalSettings.gitIdentities.filter {
                !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !$0.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
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

    private func canonicalThemeSetting(_ value: String) -> String {
        let parsed = TerminalThemeSetting.parse(value)
        if parsed.isSystem {
            return "light:\(parsed.lightTheme),dark:\(parsed.darkTheme)"
        }
        return parsed.singleTheme
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let description: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(NativeTheme.textPrimary)
                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textSecondary)
                }
            }

            Spacer(minLength: 8)

            Button {
                isOn.toggle()
            } label: {
                RoundedRectangle(cornerRadius: 16)
                    .fill(isOn ? NativeTheme.accent.opacity(0.28) : NativeTheme.elevated)
                    .frame(width: 52, height: 30)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 22, height: 22)
                            .padding(4)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isOn ? "已开启" : "已关闭")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(NativeTheme.elevated)
        .clipShape(.rect(cornerRadius: 14))
    }
}

private struct TerminalThemeSetting {
    static let availableThemes = [
        "DevHaven Dark",
        "iTerm2 Solarized Dark",
        "iTerm2 Solarized Light",
    ]

    let isSystem: Bool
    let singleTheme: String
    let lightTheme: String
    let darkTheme: String

    static func parse(_ rawValue: String) -> TerminalThemeSetting {
        let raw = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let lightTheme = parts.first(where: { $0.lowercased().hasPrefix("light:") })?
            .dropFirst("light:".count)
        let darkTheme = parts.first(where: { $0.lowercased().hasPrefix("dark:") })?
            .dropFirst("dark:".count)

        let normalizedLightTheme = lightTheme.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let normalizedDarkTheme = darkTheme.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        if let normalizedLightTheme, let normalizedDarkTheme, !normalizedLightTheme.isEmpty, !normalizedDarkTheme.isEmpty {
            return TerminalThemeSetting(
                isSystem: true,
                singleTheme: "DevHaven Dark",
                lightTheme: sanitizeTheme(normalizedLightTheme),
                darkTheme: sanitizeTheme(normalizedDarkTheme)
            )
        }

        return TerminalThemeSetting(
            isSystem: false,
            singleTheme: sanitizeTheme(raw.isEmpty ? "DevHaven Dark" : raw),
            lightTheme: "iTerm2 Solarized Light",
            darkTheme: "iTerm2 Solarized Dark"
        )
    }

    private static func sanitizeTheme(_ value: String) -> String {
        availableThemes.contains(value) ? value : "DevHaven Dark"
    }
}
