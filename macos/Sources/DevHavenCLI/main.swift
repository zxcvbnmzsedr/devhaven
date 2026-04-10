import Foundation
import Darwin
import DevHavenCore

private enum CLIExitCode: Int32 {
    case success = 0
    case appNotRunning = 2
    case usage = 3
    case timeout = 4
    case commandFailed = 5
    case ioFailure = 6
}

private enum CLIError: Error {
    case usage(String)
    case appNotRunning
    case timeout(TimeInterval)
    case io(String)
}

private struct ParsedCLIInput {
    var command: WorkspaceCLICommandPayload
    var outputJSON: Bool
    var timeout: TimeInterval
}

@main
private enum DevHavenCLI {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let environment = ProcessInfo.processInfo.environment

        do {
            let parsed = try parse(arguments: arguments, environment: environment)
            let store = WorkspaceCLICommandStore(
                baseDirectoryURL: controlDirectoryURL(environment: environment)
            )
            let client = WorkspaceCLIClient(store: store, environment: environment)
            let response = try client.perform(
                command: parsed.command,
                rawArguments: CommandLine.arguments,
                timeout: parsed.timeout
            )
            writeResponse(response, command: parsed.command.kind, asJSON: parsed.outputJSON)
            exit(response.status == .succeeded ? CLIExitCode.success.rawValue : CLIExitCode.commandFailed.rawValue)
        } catch let error as CLIError {
            exit(handle(error: error, outputJSON: arguments.contains("--json")))
        } catch {
            exit(handle(error: .io(error.localizedDescription), outputJSON: arguments.contains("--json")))
        }
    }

    private static func parse(
        arguments: [String],
        environment: [String: String]
    ) throws -> ParsedCLIInput {
        var outputJSON = false
        var timeout: TimeInterval = 5
        var filteredArguments: [String] = []

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--json":
                outputJSON = true
                index += 1
            case "--timeout":
                guard index + 1 < arguments.count,
                      let parsedTimeout = TimeInterval(arguments[index + 1]),
                      parsedTimeout > 0
                else {
                    throw CLIError.usage("`--timeout` 需要正数秒数")
                }
                timeout = parsedTimeout
                index += 2
            case "--help", "-h", "help":
                throw CLIError.usage(usageText)
            default:
                filteredArguments.append(argument)
                index += 1
            }
        }

        guard let first = filteredArguments.first else {
            throw CLIError.usage(usageText)
        }

        let command: WorkspaceCLICommandPayload
        switch first {
        case "capabilities":
            guard filteredArguments.count == 1 else {
                throw CLIError.usage("`capabilities` 不接受额外参数")
            }
            command = WorkspaceCLICommandPayload(kind: .capabilities)
        case "status":
            guard filteredArguments.count == 1 else {
                throw CLIError.usage("`status` 不接受额外参数")
            }
            command = WorkspaceCLICommandPayload(kind: .status)
        case "workspace":
            command = try parseWorkspaceCommand(
                arguments: Array(filteredArguments.dropFirst()),
                environment: environment
            )
        case "tool-window":
            command = try parseToolWindowCommand(arguments: Array(filteredArguments.dropFirst()))
        default:
            throw CLIError.usage("未知命令：\(first)\n\n\(usageText)")
        }

        return ParsedCLIInput(command: command, outputJSON: outputJSON, timeout: timeout)
    }

    private static func parseWorkspaceCommand(
        arguments: [String],
        environment: [String: String]
    ) throws -> WorkspaceCLICommandPayload {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("workspace 需要子命令")
        }
        let remaining = Array(arguments.dropFirst())

        switch subcommand {
        case "list":
            guard remaining.isEmpty else {
                throw CLIError.usage("`workspace list` 不接受额外参数")
            }
            return WorkspaceCLICommandPayload(kind: .workspaceList)
        case "enter":
            let path = try parseRequiredOption(named: "--path", from: remaining)
            return WorkspaceCLICommandPayload(
                kind: .workspaceEnter,
                target: WorkspaceCLICommandTarget(projectPath: path)
            )
        case "activate":
            let path = try parseRequiredOption(named: "--path", from: remaining)
            return WorkspaceCLICommandPayload(
                kind: .workspaceActivate,
                target: WorkspaceCLICommandTarget(projectPath: path)
            )
        case "exit":
            guard remaining.isEmpty else {
                throw CLIError.usage("`workspace exit` 不接受额外参数")
            }
            return WorkspaceCLICommandPayload(kind: .workspaceExit)
        case "close":
            let scopeRawValue = try parseRequiredOption(named: "--scope", from: remaining)
            guard let scope = WorkspaceCLICloseScope(rawValue: scopeRawValue) else {
                throw CLIError.usage("`workspace close --scope` 仅支持 session 或 project")
            }
            let target = try parseTarget(from: remaining, environment: environment)
            return WorkspaceCLICommandPayload(
                kind: .workspaceClose,
                target: target,
                closeScope: scope
            )
        default:
            throw CLIError.usage("未知 workspace 子命令：\(subcommand)")
        }
    }

    private static func parseToolWindowCommand(arguments: [String]) throws -> WorkspaceCLICommandPayload {
        guard let action = arguments.first else {
            throw CLIError.usage("tool-window 需要子命令")
        }
        let remaining = Array(arguments.dropFirst())
        let kind = try parseRequiredOption(named: "--kind", from: remaining)

        switch action {
        case "show":
            return WorkspaceCLICommandPayload(kind: .toolWindowShow, toolWindowKind: kind)
        case "hide":
            return WorkspaceCLICommandPayload(kind: .toolWindowHide, toolWindowKind: kind)
        case "toggle":
            return WorkspaceCLICommandPayload(kind: .toolWindowToggle, toolWindowKind: kind)
        default:
            throw CLIError.usage("未知 tool-window 子命令：\(action)")
        }
    }

    private static func parseRequiredOption(named optionName: String, from arguments: [String]) throws -> String {
        guard let optionIndex = arguments.firstIndex(of: optionName),
              optionIndex + 1 < arguments.count
        else {
            throw CLIError.usage("缺少参数：\(optionName)")
        }
        return arguments[optionIndex + 1]
    }

    private static func parseTarget(
        from arguments: [String],
        environment: [String: String]
    ) throws -> WorkspaceCLICommandTarget {
        var explicitPath: String?
        var useCurrent = false

        if let pathIndex = arguments.firstIndex(of: "--path"),
           pathIndex + 1 < arguments.count {
            explicitPath = arguments[pathIndex + 1]
        }
        if arguments.contains("--current") {
            useCurrent = true
        }

        guard explicitPath != nil || useCurrent else {
            throw CLIError.usage("需要 `--path <path>` 或 `--current`")
        }

        let currentProjectPath: String?
        if useCurrent {
            currentProjectPath = environment["DEVHAVEN_PROJECT_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        } else {
            currentProjectPath = nil
        }

        return WorkspaceCLICommandTarget(
            projectPath: explicitPath ?? currentProjectPath,
            workspaceID: environment["DEVHAVEN_WORKSPACE_ID"],
            paneID: environment["DEVHAVEN_PANE_ID"],
            terminalSessionID: environment["DEVHAVEN_TERMINAL_SESSION_ID"],
            useCurrentContext: useCurrent
        )
    }

    private static func controlDirectoryURL(environment: [String: String]) -> URL {
        if let explicitPath = environment["DEVHAVEN_CLI_CONTROL_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicitPath.isEmpty {
            return URL(fileURLWithPath: explicitPath, isDirectory: true)
        }
        return LegacyCompatStore().cliControlV1DirectoryURL
    }

    private static func handle(error: CLIError, outputJSON: Bool) -> Int32 {
        switch error {
        case let .usage(message):
            writeError(message, code: "usage_error", asJSON: outputJSON)
            return CLIExitCode.usage.rawValue
        case .appNotRunning:
            writeError("未检测到运行中的 DevHaven 实例", code: "app_not_running", asJSON: outputJSON)
            return CLIExitCode.appNotRunning.rawValue
        case let .timeout(seconds):
            writeError("等待 DevHaven 响应超时（\(seconds)s）", code: "timeout", asJSON: outputJSON)
            return CLIExitCode.timeout.rawValue
        case let .io(message):
            writeError(message, code: "io_failure", asJSON: outputJSON)
            return CLIExitCode.ioFailure.rawValue
        }
    }

    private static func writeResponse(
        _ response: WorkspaceCLIResponseEnvelope,
        command: WorkspaceCLICommandKind,
        asJSON: Bool
    ) {
        if asJSON {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(response),
               let text = String(data: data, encoding: .utf8) {
                print(text)
                return
            }
        }

        if response.status == .failed {
            fputs((response.message ?? "命令执行失败") + "\n", stderr)
            return
        }

        switch command {
        case .capabilities:
            if let capabilities = response.payload?.capabilities {
                print("protocolVersion: \(capabilities.protocolVersion)")
                print("namespaces:")
                capabilities.namespaces.forEach { print("- \($0)") }
                print("commands:")
                capabilities.commands.forEach { print("- \($0)") }
            } else {
                print(response.message ?? "ok")
            }
        case .status:
            if let status = response.payload?.status {
                print("running: \(status.isRunning ? "yes" : "no")")
                print("ready: \(status.isReady ? "yes" : "no")")
                if let activeWorkspaceProjectPath = status.activeWorkspaceProjectPath {
                    print("activeWorkspaceProjectPath: \(activeWorkspaceProjectPath)")
                }
                print("openWorkspaceCount: \(status.openWorkspaceCount)")
            } else {
                print(response.message ?? "ok")
            }
        case .workspaceList:
            let workspaces = response.payload?.workspaces ?? []
            if workspaces.isEmpty {
                print("暂无已打开工作区")
                return
            }
            for workspace in workspaces {
                let prefix = workspace.isActive ? "*" : "-"
                print("\(prefix) [\(workspace.kind)] \(workspace.projectPath)")
            }
        default:
            print(response.message ?? "ok")
        }
    }

    private static func writeError(_ message: String, code: String, asJSON: Bool) {
        if asJSON {
            let response = WorkspaceCLIResponseEnvelope(
                requestID: UUID().uuidString,
                status: .failed,
                code: code,
                message: message
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(response),
               let text = String(data: data, encoding: .utf8) {
                print(text)
                return
            }
        }
        fputs(message + "\n", stderr)
    }

    private static let usageText = """
    用法：
      devhaven [--json] [--timeout <seconds>] capabilities
      devhaven [--json] [--timeout <seconds>] status
      devhaven [--json] [--timeout <seconds>] workspace list
      devhaven [--json] [--timeout <seconds>] workspace enter --path <path>
      devhaven [--json] [--timeout <seconds>] workspace activate --path <path>
      devhaven [--json] [--timeout <seconds>] workspace exit
      devhaven [--json] [--timeout <seconds>] workspace close (--current | --path <path>) --scope <session|project>
      devhaven [--json] [--timeout <seconds>] tool-window <show|hide|toggle> --kind <project|commit|git>
    """
}

private final class WorkspaceCLIClient {
    private let store: WorkspaceCLICommandStore
    private let environment: [String: String]

    init(store: WorkspaceCLICommandStore, environment: [String: String]) {
        self.store = store
        self.environment = environment
    }

    func perform(
        command: WorkspaceCLICommandPayload,
        rawArguments: [String],
        timeout: TimeInterval
    ) throws -> WorkspaceCLIResponseEnvelope {
        let serverState = try store.loadServerState()
        guard let serverState, isProcessAlive(serverState.pid) else {
            if command.kind == .status {
                return WorkspaceCLIResponseEnvelope(
                    requestID: UUID().uuidString,
                    status: .succeeded,
                    payload: WorkspaceCLIResponsePayload(
                        status: .offline(),
                        workspaces: []
                    )
                )
            }
            throw CLIError.appNotRunning
        }

        let request = WorkspaceCLIRequestEnvelope(
            requestID: UUID().uuidString,
            source: WorkspaceCLIRequestSource(
                pid: ProcessInfo.processInfo.processIdentifier,
                currentWorkingDirectory: FileManager.default.currentDirectoryPath,
                arguments: rawArguments
            ),
            command: command
        )

        let requestURL = try store.writeRequest(request)
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let response = try store.loadResponse(requestID: request.requestID) {
                try? store.removeResponse(requestID: request.requestID)
                return response
            }
            usleep(50_000)
        }

        try? store.removeRequest(at: requestURL)
        throw CLIError.timeout(timeout)
    }

    private func isProcessAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else {
            return false
        }
        if Darwin.kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
