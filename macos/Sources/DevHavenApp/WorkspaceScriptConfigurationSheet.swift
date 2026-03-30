import SwiftUI
import DevHavenCore

struct WorkspaceRunConfigurationSheet: View {
    private enum RunConfigurationKind: String, CaseIterable, Identifiable {
        case customShell
        case remoteLogViewer

        var id: String { rawValue }

        var title: String {
            switch self {
            case .customShell:
                return "Shell Script"
            case .remoteLogViewer:
                return "Remote Log Viewer"
            }
        }

        var subtitle: String {
            switch self {
            case .customShell:
                return "执行项目内自定义 Shell 命令"
            case .remoteLogViewer:
                return "通过 SSH 查看远端日志"
            }
        }

        var defaultName: String {
            switch self {
            case .customShell:
                return "Shell Script"
            case .remoteLogViewer:
                return "远程日志查看"
            }
        }
    }

    private struct RunConfigurationDraft: Identifiable {
        var id: String
        var name: String
        var kind: RunConfigurationKind
        var customCommand: String
        var remoteServer: String
        var remoteLogPath: String
        var remoteUser: String
        var remotePort: String
        var remoteIdentityFile: String
        var remoteLines: String
        var remoteFollow: Bool
        var remoteStrictHostKeyChecking: String
        var remoteAllowPasswordPrompt: Bool

        static func make(
            kind: RunConfigurationKind,
            id: String = UUID().uuidString.lowercased()
        ) -> RunConfigurationDraft {
            RunConfigurationDraft(
                id: id,
                name: "",
                kind: kind,
                customCommand: "",
                remoteServer: "",
                remoteLogPath: "",
                remoteUser: "",
                remotePort: "22",
                remoteIdentityFile: "",
                remoteLines: "200",
                remoteFollow: true,
                remoteStrictHostKeyChecking: "accept-new",
                remoteAllowPasswordPrompt: false
            )
        }
    }

    let viewModel: NativeAppViewModel
    let project: Project

    @Environment(\.dismiss) private var dismiss
    @State private var runConfigurations: [RunConfigurationDraft]
    @State private var selectedConfigurationID: String?
    @State private var validationMessage: String?
    @State private var isSaving = false

    init(viewModel: NativeAppViewModel, project: Project) {
        self.viewModel = viewModel
        self.project = project

        let drafts = project.runConfigurations.map(Self.makeDraft(from:))
        _runConfigurations = State(initialValue: drafts)
        _selectedConfigurationID = State(initialValue: drafts.first?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            HStack(alignment: .top, spacing: 16) {
                leftPanel
                rightPanel
            }

            footer
        }
        .padding(20)
        .frame(minWidth: 1040, minHeight: 700)
        .background(NativeTheme.window)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("运行配置")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(NativeTheme.textPrimary)
                Text("按 IDEA 的思路维护项目内运行配置：创建时确定类型，编辑时只关注该类型真正需要的字段。")
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
            }

            Text(project.path)
                .font(.caption.monospaced())
                .foregroundStyle(NativeTheme.textSecondary)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NativeTheme.elevated)
                .clipShape(.rect(cornerRadius: 12))
        }
    }

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("项目运行配置")
                        .font(.headline)
                        .foregroundStyle(NativeTheme.textPrimary)
                    Text("\(runConfigurations.count) 个配置")
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textSecondary)
                }
                Spacer()
                Menu {
                    Button("Shell Script · 自定义 Shell 命令") {
                        addRunConfiguration(kind: .customShell)
                    }
                    Button("Remote Log Viewer · 通过 SSH 查看远端日志") {
                        addRunConfiguration(kind: .remoteLogViewer)
                    }
                } label: {
                    Label("新增配置", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(NativeTheme.accent)
            }

            ScrollView {
                VStack(spacing: 8) {
                    if runConfigurations.isEmpty {
                        placeholder("暂无运行配置，点击右上角新增。")
                    } else {
                        ForEach(runConfigurations) { configuration in
                            configurationRow(configuration)
                        }
                    }
                }
            }
        }
        .frame(width: 320)
    }

    private func configurationRow(_ configuration: RunConfigurationDraft) -> some View {
        Button {
            selectedConfigurationID = configuration.id
            validationMessage = nil
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(resolvedName(for: configuration))
                    .font(.headline)
                    .foregroundStyle(NativeTheme.textPrimary)
                    .lineLimit(1)

                Text(configuration.kind.title)
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
                    .lineLimit(1)

                Text(rowSummary(for: configuration))
                    .font(.caption2.monospaced())
                    .foregroundStyle(NativeTheme.textSecondary)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selectedConfigurationID == configuration.id
                    ? NativeTheme.accent.opacity(0.14)
                    : NativeTheme.elevated
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        selectedConfigurationID == configuration.id
                            ? NativeTheme.accent.opacity(0.75)
                            : NativeTheme.border,
                        lineWidth: 1
                    )
            )
            .clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var rightPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let selectedIndex {
                    editorCard(for: selectedIndex)
                } else {
                    placeholder("请选择一个运行配置开始编辑。")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func editorCard(for index: Int) -> some View {
        let configuration = runConfigurations[index]

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(resolvedName(for: configuration))
                        .font(.headline)
                        .foregroundStyle(NativeTheme.textPrimary)

                    HStack(spacing: 8) {
                        typeBadge(configuration.kind)

                        Text("配置 ID：\(configuration.id)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(NativeTheme.textSecondary)
                            .textSelection(.enabled)
                    }
                }

                Spacer()

                HStack(spacing: 10) {
                    Button("复制当前配置") {
                        duplicateSelectedConfiguration(index: index)
                    }
                    .buttonStyle(.bordered)

                    Button("删除当前配置", role: .destructive) {
                        removeSelectedConfiguration(index: index)
                    }
                    .buttonStyle(.bordered)
                }
            }

            sectionCard(
                title: "基础信息",
                description: "类型在创建时就确定；如果选错了，建议直接复制当前配置后重建。"
            ) {
                labeledField(title: "名称（可留空，保存时自动生成）") {
                    TextField(
                        suggestedName(for: configuration),
                        text: Binding(
                            get: { runConfigurations[index].name },
                            set: {
                                runConfigurations[index].name = $0
                                validationMessage = nil
                            }
                        )
                    )
                    .textFieldStyle(.plain)
                    .foregroundStyle(NativeTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(NativeTheme.elevated)
                    .clipShape(.rect(cornerRadius: 12))
                }

                HStack(spacing: 8) {
                    Text("建议名称：")
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textSecondary)
                    Text(suggestedName(for: configuration))
                        .font(.caption.monospaced())
                        .foregroundStyle(NativeTheme.textPrimary)
                        .textSelection(.enabled)
                }
            }

            switch configuration.kind {
            case .customShell:
                customShellEditor(index: index)
            case .remoteLogViewer:
                remoteLogEditor(index: index)
            }

            sectionCard(
                title: "命令预览",
                description: "只读预览最终会交给执行器的命令，避免用户必须先点 Run 才知道发生了什么。"
            ) {
                Text(commandPreview(for: configuration))
                    .font(.caption.monospaced())
                    .foregroundStyle(NativeTheme.textPrimary)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NativeTheme.elevated)
                    .clipShape(.rect(cornerRadius: 12))
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(NativeTheme.danger)
            }
        }
        .padding(16)
        .background(NativeTheme.surface)
        .clipShape(.rect(cornerRadius: 16))
    }

    private func customShellEditor(index: Int) -> some View {
        sectionCard(
            title: "Shell Script",
            description: "与 IDEA 的 Shell Script 配置类似，这里只保留最核心的命令输入。"
        ) {
            labeledField(title: "Shell 命令") {
                TextEditor(
                    text: Binding(
                        get: { runConfigurations[index].customCommand },
                        set: {
                            runConfigurations[index].customCommand = $0
                            validationMessage = nil
                        }
                    )
                )
                .font(.body.monospaced())
                .foregroundStyle(NativeTheme.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 220)
                .padding(10)
                .background(NativeTheme.elevated)
                .clipShape(.rect(cornerRadius: 12))
            }
        }
    }

    private func remoteLogEditor(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionCard(
                title: "连接设置",
                description: "先填写目标主机、SSH 用户、端口与私钥。"
            ) {
                pairedInputs {
                    textInput(index: index, title: "服务器 *", placeholder: "例如：root@192.168.0.131", keyPath: \.remoteServer)
                    textInput(index: index, title: "SSH 用户", placeholder: "可留空", keyPath: \.remoteUser)
                    textInput(index: index, title: "端口", placeholder: "22", keyPath: \.remotePort)
                    textInput(index: index, title: "私钥文件", placeholder: "~/.ssh/id_ed25519", keyPath: \.remoteIdentityFile)
                }
            }

            sectionCard(
                title: "日志设置",
                description: "决定查看哪个文件、读取多少行，以及是否持续 follow。"
            ) {
                pairedInputs {
                    textInput(index: index, title: "日志路径 *", placeholder: "/var/log/app.log", keyPath: \.remoteLogPath)
                    textInput(index: index, title: "输出行数", placeholder: "200", keyPath: \.remoteLines)
                }

                Toggle(
                    "持续跟踪（follow）",
                    isOn: Binding(
                        get: { runConfigurations[index].remoteFollow },
                        set: {
                            runConfigurations[index].remoteFollow = $0
                            validationMessage = nil
                        }
                    )
                )
                .toggleStyle(.switch)
            }

            sectionCard(
                title: "安全设置",
                description: "控制 host key 校验与是否允许 SSH 密码交互。"
            ) {
                pairedInputs {
                    textInput(
                        index: index,
                        title: "StrictHostKeyChecking",
                        placeholder: "accept-new",
                        keyPath: \.remoteStrictHostKeyChecking
                    )
                }

                Toggle(
                    "允许密码交互（关闭 BatchMode）",
                    isOn: Binding(
                        get: { runConfigurations[index].remoteAllowPasswordPrompt },
                        set: {
                            runConfigurations[index].remoteAllowPasswordPrompt = $0
                            validationMessage = nil
                        }
                    )
                )
                .toggleStyle(.switch)
            }
        }
    }

    private func pairedInputs<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
            content()
        }
    }

    private func sectionCard<Content: View>(
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
        .padding(14)
        .background(NativeTheme.surface.opacity(0.7))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(NativeTheme.border, lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 14))
    }

    private func typeBadge(_ kind: RunConfigurationKind) -> some View {
        Text(kind.title)
            .font(.caption.weight(.medium))
            .foregroundStyle(NativeTheme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(NativeTheme.accent.opacity(0.12))
            .clipShape(.capsule)
    }

    private func textInput(
        index: Int,
        title: String,
        placeholder: String,
        keyPath: WritableKeyPath<RunConfigurationDraft, String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(NativeTheme.textSecondary)

            TextField(
                placeholder,
                text: Binding(
                    get: { runConfigurations[index][keyPath: keyPath] },
                    set: {
                        runConfigurations[index][keyPath: keyPath] = $0
                        validationMessage = nil
                    }
                )
            )
            .textFieldStyle(.plain)
            .foregroundStyle(NativeTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(NativeTheme.elevated)
            .clipShape(.rect(cornerRadius: 12))
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("保存后会直接写回当前项目运行配置。")
                .font(.caption)
                .foregroundStyle(NativeTheme.textSecondary)

            Spacer()

            Button("取消") {
                dismiss()
            }
            .buttonStyle(.bordered)

            Button(isSaving ? "保存中..." : "保存并关闭") {
                saveRunConfigurations()
            }
            .buttonStyle(.borderedProminent)
            .tint(NativeTheme.accent)
            .disabled(isSaving)
        }
    }

    private var selectedIndex: Int? {
        if let selectedConfigurationID,
           let index = runConfigurations.firstIndex(where: { $0.id == selectedConfigurationID }) {
            return index
        }
        return runConfigurations.indices.first
    }

    private func labeledField<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(NativeTheme.textSecondary)
            content()
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(NativeTheme.textSecondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NativeTheme.elevated)
            .clipShape(.rect(cornerRadius: 12))
    }

    private func addRunConfiguration(kind: RunConfigurationKind) {
        let draft = RunConfigurationDraft.make(kind: kind)
        runConfigurations.append(draft)
        selectedConfigurationID = draft.id
        validationMessage = nil
    }

    private func duplicateSelectedConfiguration(index: Int) {
        var duplicate = runConfigurations[index]
        duplicate.id = UUID().uuidString.lowercased()
        duplicate.name = "\(resolvedName(for: runConfigurations[index])) 副本"
        runConfigurations.insert(duplicate, at: index + 1)
        selectedConfigurationID = duplicate.id
        validationMessage = nil
    }

    private func removeSelectedConfiguration(index: Int) {
        runConfigurations.remove(at: index)
        if runConfigurations.indices.contains(index) {
            selectedConfigurationID = runConfigurations[index].id
        } else {
            selectedConfigurationID = runConfigurations.last?.id
        }
        validationMessage = nil
    }

    private func saveRunConfigurations() {
        isSaving = true
        defer { isSaving = false }

        do {
            try viewModel.saveWorkspaceRunConfigurations(validatedRunConfigurations(), in: project.path)
            dismiss()
        } catch {
            validationMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func validatedRunConfigurations() throws -> [ProjectRunConfiguration] {
        var seenIDs = Set<String>()

        return try runConfigurations.enumerated().map { offset, draft in
            let resolvedName = resolvedName(for: draft)
            guard seenIDs.insert(draft.id).inserted else {
                throw makeValidationError("检测到重复配置 ID：\(draft.id)")
            }

            switch draft.kind {
            case .customShell:
                let command = ScriptTemplateSupport
                    .normalizeShellTemplateText(draft.customCommand)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !command.isEmpty else {
                    throw makeValidationError("配置 “\(resolvedName)” 的 Shell 命令不能为空。")
                }

                return ProjectRunConfiguration(
                    id: draft.id,
                    name: resolvedName,
                    kind: .customShell,
                    customShell: ProjectRunCustomShellConfiguration(command: command)
                )

            case .remoteLogViewer:
                let server = draft.remoteServer.trimmed
                let logPath = draft.remoteLogPath.trimmed

                guard !server.isEmpty else {
                    throw makeValidationError("第 \(offset + 1) 个 Remote Log Viewer 缺少服务器地址。")
                }
                guard !logPath.isEmpty else {
                    throw makeValidationError("配置 “\(resolvedName)” 缺少日志路径。")
                }

                let linesText = draft.remoteLines.trimmed
                guard let lines = Int(linesText), lines > 0 else {
                    throw makeValidationError("配置 “\(resolvedName)” 的输出行数必须是正整数。")
                }

                let portText = draft.remotePort.trimmed
                let port: Int?
                if portText.isEmpty {
                    port = nil
                } else if let parsedPort = Int(portText), parsedPort > 0 {
                    port = parsedPort
                } else {
                    throw makeValidationError("配置 “\(resolvedName)” 的端口必须是正整数。")
                }

                return ProjectRunConfiguration(
                    id: draft.id,
                    name: resolvedName,
                    kind: .remoteLogViewer,
                    remoteLogViewer: ProjectRunRemoteLogViewerConfiguration(
                        server: server,
                        logPath: logPath,
                        user: draft.remoteUser.nilIfEmpty,
                        port: port,
                        identityFile: draft.remoteIdentityFile.nilIfEmpty,
                        lines: lines,
                        follow: draft.remoteFollow,
                        strictHostKeyChecking: draft.remoteStrictHostKeyChecking.nilIfEmpty,
                        allowPasswordPrompt: draft.remoteAllowPasswordPrompt
                    )
                )
            }
        }
    }

    private func makeValidationError(_ message: String) -> NSError {
        NSError(
            domain: "DevHavenApp.WorkspaceRunConfiguration",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private func rowSummary(for configuration: RunConfigurationDraft) -> String {
        switch configuration.kind {
        case .customShell:
            return configuration.customCommand.nilIfEmpty ?? "尚未填写命令"
        case .remoteLogViewer:
            let server = configuration.remoteServer.nilIfEmpty ?? "未填写服务器"
            let logPath = configuration.remoteLogPath.nilIfEmpty ?? "未填写日志路径"
            return "\(server) · \(logPath)"
        }
    }

    private func suggestedName(for configuration: RunConfigurationDraft) -> String {
        switch configuration.kind {
        case .customShell:
            let firstLine = configuration.customCommand
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmed }
                .first(where: { !$0.isEmpty })
            if let firstLine {
                return String(firstLine.prefix(48))
            }
            return configuration.kind.defaultName

        case .remoteLogViewer:
            let server = configuration.remoteServer.nilIfEmpty ?? "未命名主机"
            let logName: String? = configuration.remoteLogPath.nilIfEmpty
                .map { path in
                    let logName = (path as NSString).lastPathComponent
                    return logName.isEmpty ? path : logName
                }
                .flatMap { $0.isEmpty ? nil : $0 }

            if let logName = logName {
                return "远程日志 · \(server) · \(logName)"
            }
            return "远程日志 · \(server)"
        }
    }

    private func resolvedName(for configuration: RunConfigurationDraft) -> String {
        configuration.name.nilIfEmpty ?? suggestedName(for: configuration)
    }

    private func commandPreview(for configuration: RunConfigurationDraft) -> String {
        switch configuration.kind {
        case .customShell:
            return configuration.customCommand.nilIfEmpty ?? "# 尚未填写 Shell 命令"
        case .remoteLogViewer:
            return remoteLogViewerDisplayCommand(for: configuration)
        }
    }

    private func remoteLogViewerDisplayCommand(for configuration: RunConfigurationDraft) -> String {
        var arguments = [String]()

        if let user = configuration.remoteUser.nilIfEmpty {
            arguments.append(contentsOf: ["-l", user])
        }
        if let port = Int(configuration.remotePort.trimmed), port > 0 {
            arguments.append(contentsOf: ["-p", String(port)])
        }
        if let identityFile = configuration.remoteIdentityFile.nilIfEmpty {
            arguments.append(contentsOf: ["-i", identityFile])
        }
        if let strictHostKeyChecking = configuration.remoteStrictHostKeyChecking.nilIfEmpty {
            arguments.append(contentsOf: ["-o", "StrictHostKeyChecking=\(strictHostKeyChecking)"])
        }
        if !configuration.remoteAllowPasswordPrompt {
            arguments.append(contentsOf: ["-o", "BatchMode=yes"])
        }

        let server = configuration.remoteServer.nilIfEmpty ?? "<server>"
        let logPath = configuration.remoteLogPath.nilIfEmpty ?? "<log-path>"
        let lines = max(1, Int(configuration.remoteLines.trimmed) ?? 200)
        arguments.append(server)
        arguments.append(remoteTailCommand(logPath: logPath, lines: lines, follow: configuration.remoteFollow))

        return (["/usr/bin/ssh"] + arguments.map(shellQuote)).joined(separator: " ")
    }

    private func remoteTailCommand(logPath: String, lines: Int, follow: Bool) -> String {
        var components = ["tail", "-n", String(lines)]
        if follow {
            components.append("-F")
        }
        components.append(shellQuote(logPath))
        return components.joined(separator: " ")
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func makeDraft(from configuration: ProjectRunConfiguration) -> RunConfigurationDraft {
        switch configuration.kind {
        case .customShell:
            var draft = RunConfigurationDraft.make(kind: .customShell, id: configuration.id)
            draft.name = configuration.name
            draft.customCommand = configuration.customShell?.command ?? ""
            return draft

        case .remoteLogViewer:
            var draft = RunConfigurationDraft.make(kind: .remoteLogViewer, id: configuration.id)
            draft.name = configuration.name
            let remote = configuration.remoteLogViewer
            draft.remoteServer = remote?.server ?? ""
            draft.remoteLogPath = remote?.logPath ?? ""
            draft.remoteUser = remote?.user ?? ""
            draft.remotePort = remote?.port.map(String.init) ?? "22"
            draft.remoteIdentityFile = remote?.identityFile ?? ""
            draft.remoteLines = remote?.lines.map(String.init) ?? "200"
            draft.remoteFollow = remote?.follow ?? true
            draft.remoteStrictHostKeyChecking = remote?.strictHostKeyChecking ?? "accept-new"
            draft.remoteAllowPasswordPrompt = remote?.allowPasswordPrompt ?? false
            return draft
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }
}
