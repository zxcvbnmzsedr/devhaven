import Foundation

@MainActor
public final class WorkspaceCLICommandExecutor {
    private let viewModel: NativeAppViewModel

    public init(viewModel: NativeAppViewModel) {
        self.viewModel = viewModel
    }

    public func execute(_ request: WorkspaceCLIRequestEnvelope) -> WorkspaceCLIResponseEnvelope {
        guard request.schemaVersion == WorkspaceCLIRequestEnvelope.schemaVersion else {
            return failure(
                requestID: request.requestID,
                code: "unsupported_schema",
                message: "CLI 请求 schema 版本不受支持"
            )
        }

        switch request.command.kind {
        case .capabilities:
            return success(
                requestID: request.requestID,
                payload: WorkspaceCLIResponsePayload(
                    capabilities: capabilities(),
                    status: statusSummary(),
                    workspaces: workspaceSummaries()
                )
            )
        case .status:
            return success(
                requestID: request.requestID,
                payload: WorkspaceCLIResponsePayload(
                    status: statusSummary(),
                    workspaces: workspaceSummaries()
                )
            )
        case .workspaceList:
            return success(
                requestID: request.requestID,
                payload: WorkspaceCLIResponsePayload(
                    status: statusSummary(),
                    workspaces: workspaceSummaries()
                )
            )
        case .workspaceEnter:
            guard let projectPath = request.command.target?.projectPath else {
                return failure(
                    requestID: request.requestID,
                    code: "invalid_arguments",
                    message: "workspace.enter 需要 --path"
                )
            }
            guard FileManager.default.fileExists(atPath: projectPath) else {
                return failure(
                    requestID: request.requestID,
                    code: "target_not_found",
                    message: "目标路径不存在：\(projectPath)"
                )
            }
            viewModel.enterWorkspace(projectPath)
            return success(
                requestID: request.requestID,
                message: "已打开工作区",
                payload: WorkspaceCLIResponsePayload(
                    status: statusSummary(),
                    workspaces: workspaceSummaries()
                )
            )
        case .workspaceActivate:
            guard let projectPath = request.command.target?.projectPath else {
                return failure(
                    requestID: request.requestID,
                    code: "invalid_arguments",
                    message: "workspace.activate 需要 --path"
                )
            }
            guard containsWorkspaceSession(projectPath) else {
                return failure(
                    requestID: request.requestID,
                    code: "target_not_found",
                    message: "目标工作区未打开，无法激活"
                )
            }
            viewModel.activateWorkspaceProject(projectPath)
            return success(
                requestID: request.requestID,
                message: "已激活工作区",
                payload: WorkspaceCLIResponsePayload(
                    status: statusSummary(),
                    workspaces: workspaceSummaries()
                )
            )
        case .workspaceExit:
            viewModel.exitWorkspace()
            return success(
                requestID: request.requestID,
                message: "已退出工作区视图",
                payload: WorkspaceCLIResponsePayload(
                    status: statusSummary(),
                    workspaces: workspaceSummaries()
                )
            )
        case .workspaceClose:
            guard let scope = request.command.closeScope else {
                return failure(
                    requestID: request.requestID,
                    code: "invalid_arguments",
                    message: "workspace.close 需要 --scope session|project"
                )
            }
            guard let projectPath = resolveProjectPath(from: request.command.target) else {
                return failure(
                    requestID: request.requestID,
                    code: "target_not_found",
                    message: "当前上下文无法解析 projectPath，请显式传 --path"
                )
            }
            let sessionCountBefore = viewModel.openWorkspaceSessions.count
            let message = closeMessage(for: projectPath, scope: scope)
            switch scope {
            case .session:
                viewModel.closeWorkspaceSession(projectPath)
            case .project:
                viewModel.closeWorkspaceProject(projectPath)
            }
            guard viewModel.openWorkspaceSessions.count != sessionCountBefore else {
                return failure(
                    requestID: request.requestID,
                    code: "target_not_found",
                    message: "目标工作区未打开，无法关闭"
                )
            }
            return success(
                requestID: request.requestID,
                message: message,
                payload: WorkspaceCLIResponsePayload(
                    status: statusSummary(),
                    workspaces: workspaceSummaries()
                )
            )
        case .toolWindowShow, .toolWindowHide, .toolWindowToggle:
            guard let toolWindowKind = toolWindowKind(from: request.command.toolWindowKind) else {
                return failure(
                    requestID: request.requestID,
                    code: "invalid_arguments",
                    message: "tool-window 命令需要合法的 --kind"
                )
            }
            switch request.command.kind {
            case .toolWindowShow:
                switch toolWindowKind.placement {
                case .side:
                    viewModel.showWorkspaceSideToolWindow(toolWindowKind)
                case .bottom:
                    viewModel.showWorkspaceBottomToolWindow(toolWindowKind)
                }
            case .toolWindowHide:
                switch toolWindowKind.placement {
                case .side:
                    if viewModel.workspaceSideToolWindowState.activeKind == toolWindowKind,
                       viewModel.workspaceSideToolWindowState.isVisible {
                        viewModel.hideWorkspaceSideToolWindow()
                    }
                case .bottom:
                    if viewModel.workspaceBottomToolWindowState.activeKind == toolWindowKind,
                       viewModel.workspaceBottomToolWindowState.isVisible {
                        viewModel.hideWorkspaceBottomToolWindow()
                    }
                }
            case .toolWindowToggle:
                viewModel.toggleWorkspaceToolWindow(toolWindowKind)
            default:
                break
            }

            return success(
                requestID: request.requestID,
                message: toolWindowMessage(kind: toolWindowKind, action: request.command.kind),
                payload: WorkspaceCLIResponsePayload(
                    status: statusSummary(),
                    workspaces: workspaceSummaries()
                )
            )
        }
    }

    private func capabilities() -> WorkspaceCLICapabilities {
        WorkspaceCLICapabilities(
            appVersion: bundleValue(for: "CFBundleShortVersionString"),
            buildVersion: bundleValue(for: "CFBundleVersion")
        )
    }

    private func statusSummary() -> WorkspaceCLIStatusSummary {
        WorkspaceCLIStatusSummary(
            isRunning: true,
            isReady: viewModel.hasLoadedInitialData,
            pid: ProcessInfo.processInfo.processIdentifier,
            appVersion: bundleValue(for: "CFBundleShortVersionString"),
            buildVersion: bundleValue(for: "CFBundleVersion"),
            activeWorkspaceProjectPath: viewModel.activeWorkspaceProjectPath,
            openWorkspaceCount: viewModel.openWorkspaceSessions.count,
            sideToolWindow: WorkspaceCLIToolWindowSnapshot(
                placement: "side",
                activeKind: viewModel.workspaceSideToolWindowState.activeKind?.rawValue,
                isVisible: viewModel.workspaceSideToolWindowState.isVisible,
                dimension: viewModel.workspaceSideToolWindowState.width
            ),
            bottomToolWindow: WorkspaceCLIToolWindowSnapshot(
                placement: "bottom",
                activeKind: viewModel.workspaceBottomToolWindowState.activeKind?.rawValue,
                isVisible: viewModel.workspaceBottomToolWindowState.isVisible,
                dimension: viewModel.workspaceBottomToolWindowState.height
            )
        )
    }

    private func workspaceSummaries() -> [WorkspaceCLIWorkspaceSummary] {
        viewModel.openWorkspaceSessions.map { session in
            WorkspaceCLIWorkspaceSummary(
                projectPath: session.projectPath,
                rootProjectPath: session.rootProjectPath,
                kind: workspaceKind(for: session),
                isActive: samePath(session.projectPath, viewModel.activeWorkspaceProjectPath),
                workspaceID: session.workspaceRootContext?.workspaceID,
                workspaceName: session.workspaceRootContext?.workspaceName
            )
        }
    }

    private func workspaceKind(for session: OpenWorkspaceSessionState) -> String {
        if session.workspaceRootContext != nil {
            return "workspaceRoot"
        }
        if session.isQuickTerminal {
            return "quickTerminal"
        }
        if !samePath(session.projectPath, session.rootProjectPath) {
            return "worktree"
        }
        return "project"
    }

    private func resolveProjectPath(from target: WorkspaceCLICommandTarget?) -> String? {
        if let projectPath = target?.projectPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !projectPath.isEmpty {
            return projectPath
        }
        if target?.useCurrentContext == true {
            return viewModel.activeWorkspaceProjectPath
        }
        return nil
    }

    private func containsWorkspaceSession(_ path: String) -> Bool {
        let normalized = normalizedPath(path)
        return viewModel.openWorkspaceSessions.contains { samePath($0.projectPath, normalized) }
    }

    private func closeMessage(for path: String, scope: WorkspaceCLICloseScope) -> String {
        if let session = matchingSession(for: path) {
            if let workspaceRootContext = session.workspaceRootContext {
                return "已关闭工作区「\(workspaceRootContext.workspaceName)」"
            }
            if session.isQuickTerminal {
                return "已结束快速终端"
            }
            switch scope {
            case .session:
                return "已关闭工作区会话「\(displayName(for: session.projectPath))」"
            case .project:
                return "已关闭项目「\(displayName(for: session.projectPath))」"
            }
        }
        switch scope {
        case .session:
            return "已关闭工作区会话"
        case .project:
            return "已关闭项目"
        }
    }

    private func toolWindowMessage(kind: WorkspaceToolWindowKind, action: WorkspaceCLICommandKind) -> String {
        switch action {
        case .toolWindowShow:
            return "已显示 \(kind.title)"
        case .toolWindowHide:
            return "已隐藏 \(kind.title)"
        case .toolWindowToggle:
            return "已切换 \(kind.title)"
        default:
            return kind.title
        }
    }

    private func toolWindowKind(from rawValue: String?) -> WorkspaceToolWindowKind? {
        guard let rawValue else {
            return nil
        }
        switch rawValue {
        case WorkspaceToolWindowKind.git.rawValue, "github":
            return .git
        default:
            return WorkspaceToolWindowKind(rawValue: rawValue)
        }
    }

    private func matchingSession(for path: String) -> OpenWorkspaceSessionState? {
        let normalized = normalizedPath(path)
        return viewModel.openWorkspaceSessions.first {
            samePath($0.projectPath, normalized) || samePath($0.rootProjectPath, normalized)
        }
    }

    private func displayName(for path: String) -> String {
        let normalized = normalizedPath(path)
        if let project = viewModel.snapshot.projects.first(where: { samePath($0.path, normalized) }) {
            return project.name
        }
        return URL(fileURLWithPath: normalized).lastPathComponent
    }

    private func samePath(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else {
            return false
        }
        return normalizedPath(lhs) == normalizedPath(rhs)
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL.path
    }

    private func bundleValue(for key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    private func success(
        requestID: String,
        message: String? = nil,
        payload: WorkspaceCLIResponsePayload? = nil
    ) -> WorkspaceCLIResponseEnvelope {
        WorkspaceCLIResponseEnvelope(
            requestID: requestID,
            status: .succeeded,
            message: message,
            payload: payload
        )
    }

    private func failure(
        requestID: String,
        code: String,
        message: String
    ) -> WorkspaceCLIResponseEnvelope {
        WorkspaceCLIResponseEnvelope(
            requestID: requestID,
            status: .failed,
            code: code,
            message: message
        )
    }
}
