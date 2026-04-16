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
    @Environment(\.colorScheme) private var colorScheme
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
        WorkspaceRunConfigurationSheetReactView(
            payload: sheetPayload,
            onSelectConfiguration: selectConfiguration,
            onAddConfiguration: addConfiguration(kindRawValue:),
            onStringFieldChanged: updateConfigurationStringField,
            onBooleanFieldChanged: updateConfigurationBooleanField,
            onDuplicateRequested: duplicateConfiguration,
            onDeleteRequested: deleteConfiguration,
            onCancelRequested: { dismiss() },
            onSaveRequested: saveRunConfigurations
        )
        .frame(minWidth: 1040, minHeight: 700)
        .background(NativeTheme.window)
    }

    private var sheetPayload: WorkspaceRunConfigurationSheetPayload {
        WorkspaceRunConfigurationSheetPayload(
            theme: colorScheme == .dark ? "dark" : "light",
            title: "运行配置",
            subtitle: "按 IDEA 的思路维护项目内运行配置：创建时确定类型，编辑时只关注该类型真正需要的字段。",
            projectPath: project.path,
            footerNote: "保存后会直接写回当前项目运行配置。",
            isSaving: isSaving,
            validationMessage: validationMessage,
            selectedConfigurationID: effectiveSelectedConfigurationID,
            availableKinds: RunConfigurationKind.allCases.map {
                WorkspaceRunConfigurationKindOptionPayload(
                    id: $0.rawValue,
                    title: $0.title,
                    subtitle: $0.subtitle
                )
            },
            configurations: runConfigurations.map(configurationPayload(for:))
        )
    }

    private var effectiveSelectedConfigurationID: String? {
        if let selectedConfigurationID,
           runConfigurations.contains(where: { $0.id == selectedConfigurationID }) {
            return selectedConfigurationID
        }
        return runConfigurations.first?.id
    }

    private func configurationPayload(
        for configuration: RunConfigurationDraft
    ) -> WorkspaceRunConfigurationSheetConfigurationPayload {
        WorkspaceRunConfigurationSheetConfigurationPayload(
            id: configuration.id,
            kind: configuration.kind.rawValue,
            kindTitle: configuration.kind.title,
            kindSubtitle: configuration.kind.subtitle,
            name: configuration.name,
            resolvedName: resolvedName(for: configuration),
            suggestedName: suggestedName(for: configuration),
            rowSummary: rowSummary(for: configuration),
            commandPreview: commandPreview(for: configuration),
            customCommand: configuration.customCommand,
            remoteServer: configuration.remoteServer,
            remoteLogPath: configuration.remoteLogPath,
            remoteUser: configuration.remoteUser,
            remotePort: configuration.remotePort,
            remoteIdentityFile: configuration.remoteIdentityFile,
            remoteLines: configuration.remoteLines,
            remoteFollow: configuration.remoteFollow,
            remoteStrictHostKeyChecking: configuration.remoteStrictHostKeyChecking,
            remoteAllowPasswordPrompt: configuration.remoteAllowPasswordPrompt
        )
    }

    private func selectConfiguration(_ configurationID: String) {
        selectedConfigurationID = configurationID
        validationMessage = nil
    }

    private func addConfiguration(kindRawValue: String) {
        guard let kind = RunConfigurationKind(rawValue: kindRawValue) else {
            return
        }
        let draft = RunConfigurationDraft.make(kind: kind)
        runConfigurations.append(draft)
        selectedConfigurationID = draft.id
        validationMessage = nil
    }

    private func duplicateConfiguration(_ configurationID: String) {
        guard let index = runConfigurations.firstIndex(where: { $0.id == configurationID }) else {
            return
        }
        var duplicate = runConfigurations[index]
        duplicate.id = UUID().uuidString.lowercased()
        duplicate.name = "\(resolvedName(for: runConfigurations[index])) 副本"
        runConfigurations.insert(duplicate, at: index + 1)
        selectedConfigurationID = duplicate.id
        validationMessage = nil
    }

    private func deleteConfiguration(_ configurationID: String) {
        guard let index = runConfigurations.firstIndex(where: { $0.id == configurationID }) else {
            return
        }
        runConfigurations.remove(at: index)
        if runConfigurations.indices.contains(index) {
            selectedConfigurationID = runConfigurations[index].id
        } else {
            selectedConfigurationID = runConfigurations.last?.id
        }
        validationMessage = nil
    }

    private func updateConfigurationStringField(
        _ configurationID: String,
        field: WorkspaceRunConfigurationStringField,
        value: String
    ) {
        guard let index = runConfigurations.firstIndex(where: { $0.id == configurationID }) else {
            return
        }
        switch field {
        case .name:
            runConfigurations[index].name = value
        case .customCommand:
            runConfigurations[index].customCommand = value
        case .remoteServer:
            runConfigurations[index].remoteServer = value
        case .remoteLogPath:
            runConfigurations[index].remoteLogPath = value
        case .remoteUser:
            runConfigurations[index].remoteUser = value
        case .remotePort:
            runConfigurations[index].remotePort = value
        case .remoteIdentityFile:
            runConfigurations[index].remoteIdentityFile = value
        case .remoteLines:
            runConfigurations[index].remoteLines = value
        case .remoteStrictHostKeyChecking:
            runConfigurations[index].remoteStrictHostKeyChecking = value
        }
        validationMessage = nil
    }

    private func updateConfigurationBooleanField(
        _ configurationID: String,
        field: WorkspaceRunConfigurationBooleanField,
        value: Bool
    ) {
        guard let index = runConfigurations.firstIndex(where: { $0.id == configurationID }) else {
            return
        }
        switch field {
        case .remoteFollow:
            runConfigurations[index].remoteFollow = value
        case .remoteAllowPasswordPrompt:
            runConfigurations[index].remoteAllowPasswordPrompt = value
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
