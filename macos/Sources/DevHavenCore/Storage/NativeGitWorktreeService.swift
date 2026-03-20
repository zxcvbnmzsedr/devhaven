import Foundation

public struct NativeGitWorktreeService: NativeWorktreeServicing {
    private let homeDirectoryURL: URL

    public init(homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectoryURL = homeDirectoryURL
    }

    public func managedWorktreePath(for sourceProjectPath: String, branch: String) throws -> String {
        try resolveTargetPath(sourceProjectPath: sourceProjectPath, branch: branch, explicitTargetPath: nil)
    }

    public func listBranches(at projectPath: String) throws -> [NativeGitBranch] {
        try ensureGitRepository(at: projectPath)
        let output = try runGit(["branch", "--list"], at: projectPath).stdout
        let branches = output
            .split(whereSeparator: \.isNewline)
            .map { $0.replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let defaultBranch = resolveDefaultBranch(branches: branches, projectPath: projectPath)
        return branches.map { NativeGitBranch(name: $0, isMain: $0 == defaultBranch) }
    }

    public func listWorktrees(at projectPath: String) throws -> [NativeGitWorktree] {
        try ensureGitRepository(at: projectPath)
        let output = try runGit(["worktree", "list", "--porcelain"], at: projectPath).stdout
        return parseWorktreeListOutput(basePath: projectPath, output: output)
    }

    public func createWorktree(
        _ request: NativeWorktreeCreateRequest,
        progress: @escaping @Sendable (NativeWorktreeProgress) -> Void
    ) throws -> NativeWorktreeCreateResult {
        try ensureGitRepository(at: request.sourceProjectPath)

        let branch = try normalizeBranchName(request.branch)
        let targetPath = try resolveTargetPath(
            sourceProjectPath: request.sourceProjectPath,
            branch: branch,
            explicitTargetPath: request.targetPath
        )

        progress(
            NativeWorktreeProgress(
                worktreePath: targetPath,
                branch: branch,
                baseBranch: request.baseBranch,
                step: .checkingBranch,
                message: request.createBranch ? "执行中：校验分支与基线可用性..." : "执行中：校验分支可用性..."
            )
        )

        try validateCreateRequest(request, branch: branch)
        let startPoint = try resolveCreateBranchStartPointIfNeeded(request, branch: branch)

        progress(
            NativeWorktreeProgress(
                worktreePath: targetPath,
                branch: branch,
                baseBranch: request.baseBranch,
                step: .creatingWorktree,
                message: "执行中：正在创建 Git worktree..."
            )
        )

        try addWorktree(
            sourceProjectPath: request.sourceProjectPath,
            targetPath: targetPath,
            branch: branch,
            createBranch: request.createBranch,
            startPoint: startPoint
        )

        progress(
            NativeWorktreeProgress(
                worktreePath: targetPath,
                branch: branch,
                baseBranch: request.baseBranch,
                step: .preparingEnvironment,
                message: "执行中：准备工作区环境..."
            )
        )

        let warning = prepareWorktreeEnvironment(
            mainRepositoryPath: request.sourceProjectPath,
            worktreePath: targetPath,
            workspaceName: branch
        )

        progress(
            NativeWorktreeProgress(
                worktreePath: targetPath,
                branch: branch,
                baseBranch: request.baseBranch,
                step: .syncing,
                message: "执行中：同步工作区状态..."
            )
        )

        _ = try? listWorktrees(at: request.sourceProjectPath)

        progress(
            NativeWorktreeProgress(
                worktreePath: targetPath,
                branch: branch,
                baseBranch: request.baseBranch,
                step: .ready,
                message: warning == nil ? "创建完成" : "创建完成（环境初始化存在告警）",
                error: warning
            )
        )

        return NativeWorktreeCreateResult(
            worktreePath: targetPath,
            branch: branch,
            baseBranch: request.baseBranch,
            warning: warning
        )
    }

    public func removeWorktree(_ request: NativeWorktreeRemoveRequest) throws -> NativeWorktreeRemoveResult {
        try ensureGitRepository(at: request.sourceProjectPath)

        let normalizedWorktreePath = normalizePathForCompare(request.worktreePath)
        let baseNormalizedPath = normalizePathForCompare(request.sourceProjectPath)
        guard normalizedWorktreePath != baseNormalizedPath else {
            throw NativeWorktreeError.invalidPath("不能删除主仓库目录")
        }

        let listed = try listWorktrees(at: request.sourceProjectPath)
        guard listed.contains(where: { normalizePathForCompare($0.path) == normalizedWorktreePath }) else {
            throw NativeWorktreeError.invalidPath("worktree 不存在或已移除")
        }

        do {
            _ = try runGit(["worktree", "remove", request.worktreePath], at: request.sourceProjectPath)
        } catch let error as NativeWorktreeError {
            if case let .commandFailed(message) = error, shouldPruneAfterRemoveFailure(message) {
                _ = try? runGit(["worktree", "prune"], at: request.sourceProjectPath)
                let remaining = try listWorktrees(at: request.sourceProjectPath)
                if !remaining.contains(where: { normalizePathForCompare($0.path) == normalizedWorktreePath }) {
                    return try deleteBranchIfNeeded(for: request)
                }
            }
            throw error
        }

        return try deleteBranchIfNeeded(for: request)
    }

    private func deleteBranchIfNeeded(for request: NativeWorktreeRemoveRequest) throws -> NativeWorktreeRemoveResult {
        guard request.shouldDeleteBranch, let branch = request.branch?.trimmingCharacters(in: .whitespacesAndNewlines), !branch.isEmpty else {
            return NativeWorktreeRemoveResult(warning: nil)
        }

        do {
            _ = try runGit(["branch", "-d", branch], at: request.sourceProjectPath)
            return NativeWorktreeRemoveResult(warning: nil)
        } catch let error as NativeWorktreeError {
            if case let .commandFailed(message) = error {
                return NativeWorktreeRemoveResult(warning: normalizeDeleteBranchError(message))
            }
            throw error
        }
    }

    private func validateCreateRequest(_ request: NativeWorktreeCreateRequest, branch: String) throws {
        if request.createBranch {
            guard let baseBranch = request.baseBranch?.trimmingCharacters(in: .whitespacesAndNewlines), !baseBranch.isEmpty else {
                throw NativeWorktreeError.invalidBaseBranch("基线分支不能为空")
            }
            let existingLocalBranches = try listBranches(at: request.sourceProjectPath).map(\.name)
            if existingLocalBranches.contains(branch) {
                throw NativeWorktreeError.invalidBranch("分支已存在，请改用“已有分支”模式或更换分支名")
            }
            return
        }

        let branches = try listBranches(at: request.sourceProjectPath).map(\.name)
        guard branches.contains(branch) else {
            throw NativeWorktreeError.invalidBranch("分支不存在或不可用，请检查分支名称")
        }
    }

    private func resolveCreateBranchStartPointIfNeeded(_ request: NativeWorktreeCreateRequest, branch: String) throws -> String? {
        guard request.createBranch else {
            return nil
        }
        let baseBranch = request.baseBranch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !baseBranch.isEmpty else {
            throw NativeWorktreeError.invalidBaseBranch("基线分支不能为空")
        }
        return try resolveCreateBranchStartPoint(projectPath: request.sourceProjectPath, baseBranch: baseBranch)
    }

    private func addWorktree(
        sourceProjectPath: String,
        targetPath: String,
        branch: String,
        createBranch: Bool,
        startPoint: String?
    ) throws {
        let parentURL = URL(fileURLWithPath: targetPath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)

        var arguments = ["worktree", "add"]
        if createBranch {
            arguments += ["-b", branch, targetPath]
            if let startPoint, !startPoint.isEmpty {
                arguments.append(startPoint)
            }
        } else {
            arguments += [targetPath, branch]
        }

        do {
            _ = try runGit(arguments, at: sourceProjectPath)
        } catch let error as NativeWorktreeError {
            if case let .commandFailed(message) = error {
                throw NativeWorktreeError.commandFailed(normalizeWorktreeAddError(message, createBranch: createBranch))
            }
            throw error
        }
    }

    private func resolveCreateBranchStartPoint(projectPath: String, baseBranch: String) throws -> String {
        guard !baseBranch.isEmpty else {
            throw NativeWorktreeError.invalidBaseBranch("基线分支不能为空")
        }

        if hasOriginRemote(projectPath) {
            switch branchExistsOnRemote(projectPath: projectPath, branch: baseBranch) {
            case .exists:
                let remoteRef = "origin/\(baseBranch)"
                let fetchErrorMessage: String?
                do {
                    try fetchOriginBranch(projectPath: projectPath, branch: baseBranch)
                    fetchErrorMessage = nil
                } catch {
                    fetchErrorMessage = error.localizedDescription
                }
                if refExistsLocally(projectPath: projectPath, reference: remoteRef) {
                    return remoteRef
                }
                if refExistsLocally(projectPath: projectPath, reference: baseBranch) {
                    return baseBranch
                }
                if let fetchErrorMessage {
                    throw NativeWorktreeError.invalidBaseBranch(
                        "基线分支不可用：远端分支 \(remoteRef) 刷新失败，且本地不存在同名分支（\(fetchErrorMessage)）"
                    )
                }
                throw NativeWorktreeError.invalidBaseBranch("基线分支不可用：远端分支 \(remoteRef) 无法在本地解析")
            case .notFound:
                if refExistsLocally(projectPath: projectPath, reference: baseBranch) {
                    return baseBranch
                }
                throw NativeWorktreeError.invalidBaseBranch("基线分支不可用：远端与本地均不存在分支 \(baseBranch)")
            case let .error(message):
                if refExistsLocally(projectPath: projectPath, reference: baseBranch) {
                    return baseBranch
                }
                throw NativeWorktreeError.invalidBaseBranch(
                    "基线分支不可用：无法校验远端分支 \(baseBranch)，且本地不存在同名分支（\(message)）"
                )
            }
        }

        if refExistsLocally(projectPath: projectPath, reference: baseBranch) {
            return baseBranch
        }

        throw NativeWorktreeError.invalidBaseBranch("基线分支不可用：未找到本地分支 \(baseBranch)")
    }

    private func resolveTargetPath(sourceProjectPath: String, branch: String, explicitTargetPath: String?) throws -> String {
        let trimmed = explicitTargetPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }

        let normalizedBranch = branch
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "/")

        guard !normalizedBranch.isEmpty else {
            throw NativeWorktreeError.invalidBranch("分支名不能为空")
        }

        let repositoryName = resolveRepositoryName(sourceProjectPath)
        return homeDirectoryURL
            .appending(path: ".devhaven", directoryHint: .isDirectory)
            .appending(path: "worktrees", directoryHint: .isDirectory)
            .appending(path: repositoryName, directoryHint: .isDirectory)
            .appending(path: normalizedBranch, directoryHint: .isDirectory)
            .path()
    }

    private func resolveRepositoryName(_ path: String) -> String {
        let raw = URL(fileURLWithPath: path).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "repository"
        let candidate = raw.isEmpty ? fallback : raw
        let sanitized = candidate.map { character -> Character in
            if character.isLetter || character.isNumber || character == "-" || character == "_" || character == "." {
                return character
            }
            return "-"
        }
        let result = String(sanitized).trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        return result.isEmpty ? fallback : result
    }

    private func normalizeBranchName(_ branch: String) throws -> String {
        let value = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw NativeWorktreeError.invalidBranch("分支名不能为空")
        }
        return value
    }

    private func ensureGitRepository(at projectPath: String) throws {
        let gitURL = URL(fileURLWithPath: projectPath).appending(path: ".git")
        guard FileManager.default.fileExists(atPath: gitURL.path) else {
            throw NativeWorktreeError.invalidRepository("不是 Git 仓库")
        }
    }

    private func runGit(_ arguments: [String], at projectPath: String) throws -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath, isDirectory: true)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw NativeWorktreeError.commandFailed("执行 git 命令失败：\(error.localizedDescription)")
        }
        process.waitUntilExit()

        let output = ProcessOutput(
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )

        guard process.terminationStatus == 0 else {
            let raw = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                : output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NativeWorktreeError.commandFailed(raw.isEmpty ? "未知错误" : raw)
        }

        return output
    }

    private func resolveDefaultBranch(branches: [String], projectPath: String) -> String? {
        if let symbolic = try? runGit(["symbolic-ref", "refs/remotes/origin/HEAD"], at: projectPath).stdout,
           let name = symbolic.split(separator: "/").last.map(String.init),
           branches.contains(name) {
            return name
        }
        if branches.contains("main") {
            return "main"
        }
        if branches.contains("master") {
            return "master"
        }
        return branches.first
    }

    private func hasOriginRemote(_ projectPath: String) -> Bool {
        (try? runGit(["remote", "get-url", "origin"], at: projectPath)) != nil
    }

    private func fetchOriginBranch(projectPath: String, branch: String) throws {
        _ = try runGit(["fetch", "origin", branch], at: projectPath)
    }

    private func refExistsLocally(projectPath: String, reference: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "rev-parse", "--verify", "--quiet", "\(reference)^{commit}"]
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath, isDirectory: true)
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private func branchExistsOnRemote(projectPath: String, branch: String) -> RemoteBranchCheck {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "ls-remote", "--exit-code", "--heads", "origin", branch]
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath, isDirectory: true)
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return .error("执行命令失败：\(error.localizedDescription)")
        }
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            return .exists
        }
        if process.terminationStatus == 2 {
            return .notFound
        }

        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let message = [stdoutText, stderrText]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return .error(message.isEmpty ? "未知错误" : message)
    }

    private func parseWorktreeListOutput(basePath: String, output: String) -> [NativeGitWorktree] {
        let baseNormalized = normalizePathForCompare(basePath)
        var items = [NativeGitWorktree]()
        var currentPath: String?
        var currentBranch: String?
        var currentDetached = false

        func flushCurrent() {
            guard let pathValue = currentPath else {
                currentBranch = nil
                currentDetached = false
                return
            }
            let branch = currentBranch ?? ""
            let normalizedPath = normalizePathForCompare(pathValue)
            if normalizedPath != baseNormalized, !currentDetached, !branch.isEmpty {
                items.append(NativeGitWorktree(path: pathValue, branch: branch))
            }
            currentPath = nil
            currentBranch = nil
            currentDetached = false
        }

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                flushCurrent()
                continue
            }
            if let path = line.split(separator: " ", maxSplits: 1).dropFirst().first, line.hasPrefix("worktree ") {
                flushCurrent()
                currentPath = String(path)
                continue
            }
            if line.hasPrefix("branch ") {
                let reference = String(line.dropFirst("branch ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                currentBranch = reference.replacingOccurrences(of: "refs/heads/", with: "")
                continue
            }
            if line == "detached" {
                currentDetached = true
            }
        }

        flushCurrent()
        return items.sorted { $0.path < $1.path }
    }
    private func normalizePathForCompare(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }
        var normalized = URL(fileURLWithPath: trimmed).standardizedFileURL.path
            .replacingOccurrences(of: "\\", with: "/")
        while normalized.count > 1 && normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }

    private func shouldPruneAfterRemoveFailure(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return lower.contains("not a working tree") || lower.contains("is missing") || lower.contains("no such file or directory")
    }

    private func normalizeWorktreeAddError(_ raw: String, createBranch: Bool) -> String {
        let lower = raw.lowercased()
        if lower.contains("already checked out") || lower.contains("already used by worktree") {
            return "该分支已在其他 worktree 检出，请切换分支或先移除旧 worktree"
        }
        if createBranch && lower.contains("already exists") && lower.contains("branch") {
            return "分支已存在，请改用“已有分支”模式或更换分支名"
        }
        if lower.contains("already exists") {
            return "目标目录已存在，无法创建 worktree"
        }
        if lower.contains("not a git repository") {
            return "不是 Git 仓库"
        }
        if lower.contains("invalid reference") || lower.contains("unknown revision") || lower.contains("not a valid object name") || lower.contains("pathspec") {
            return "分支不存在或不可用，请检查分支名称"
        }
        return raw
    }

    private func normalizeDeleteBranchError(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("not a git repository") {
            return "不是 Git 仓库"
        }
        if lower.contains("not found") && lower.contains("branch") {
            return "分支不存在或已删除"
        }
        if lower.contains("checked out") {
            return "分支正在当前仓库或其他 worktree 中使用，无法删除"
        }
        if lower.contains("not fully merged") {
            return "分支包含未合并提交，无法删除。请先合并后重试"
        }
        return raw
    }

    private func prepareWorktreeEnvironment(mainRepositoryPath: String, worktreePath: String, workspaceName: String) -> String? {
        var warnings = [String]()
        if let error = copySetupDirectory(mainRepositoryPath: mainRepositoryPath, worktreePath: worktreePath) {
            warnings.append(error)
        }
        if let error = runSetupCommandsIfNeeded(mainRepositoryPath: mainRepositoryPath, worktreePath: worktreePath, workspaceName: workspaceName) {
            warnings.append(error)
        }
        return warnings.isEmpty ? nil : warnings.joined(separator: "\n")
    }

    private func copySetupDirectory(mainRepositoryPath: String, worktreePath: String) -> String? {
        let sourceURL = URL(fileURLWithPath: mainRepositoryPath).appending(path: ".devhaven", directoryHint: .isDirectory)
        let targetURL = URL(fileURLWithPath: worktreePath).appending(path: ".devhaven", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return nil
        }
        guard !FileManager.default.fileExists(atPath: targetURL.path) else {
            return nil
        }

        do {
            try copyDirectoryRecursively(from: sourceURL, to: targetURL)
            return nil
        } catch {
            return "复制 .devhaven 目录失败：\(error.localizedDescription)"
        }
    }

    private func copyDirectoryRecursively(from sourceURL: URL, to targetURL: URL) throws {
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        for entry in try FileManager.default.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            let destinationURL = targetURL.appending(path: entry.lastPathComponent)
            let values = try entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isDirectory == true {
                try copyDirectoryRecursively(from: entry, to: destinationURL)
                continue
            }
            if values.isSymbolicLink == true {
                let metadata = try FileManager.default.attributesOfItem(atPath: entry.path)
                if metadata[.type] as? FileAttributeType == .typeDirectory {
                    continue
                }
            }
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: entry, to: destinationURL)
        }
    }

    private func runSetupCommandsIfNeeded(mainRepositoryPath: String, worktreePath: String, workspaceName: String) -> String? {
        let configURL = URL(fileURLWithPath: mainRepositoryPath)
            .appending(path: ".devhaven", directoryHint: .isDirectory)
            .appending(path: "config.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return nil
        }

        let commands: [String]
        do {
            commands = try loadSetupCommands(configURL: configURL)
        } catch {
            return error.localizedDescription
        }
        guard !commands.isEmpty else {
            return nil
        }

        for command in commands {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
            process.arguments = ["-lc", command]
            process.currentDirectoryURL = URL(fileURLWithPath: worktreePath, isDirectory: true)
            process.environment = ProcessInfo.processInfo.environment.merging([
                "DEVHAVEN_WORKSPACE_NAME": workspaceName,
                "DEVHAVEN_ROOT_PATH": mainRepositoryPath,
            ]) { _, new in new }

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            do {
                try process.run()
            } catch {
                return "执行 setup 命令失败（\(command)）：\(error.localizedDescription)"
            }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let combined = [stdoutText.isEmpty ? nil : "stdout:\n\(stdoutText)", stderrText.isEmpty ? nil : "stderr:\n\(stderrText)"]
                    .compactMap { $0 }
                    .joined(separator: "\n\n")
                return "环境初始化命令执行失败：\n$ \(command)\n退出码：\(process.terminationStatus)\n\(combined.isEmpty ? "命令无输出" : combined)"
            }
        }

        return nil
    }

    private func loadSetupCommands(configURL: URL) throws -> [String] {
        struct SetupConfig: Decodable {
            var setup: [String] = []
        }

        let data = try Data(contentsOf: configURL)
        let parsed = try JSONDecoder().decode(SetupConfig.self, from: data)
        return parsed.setup
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct ProcessOutput {
    let stdout: String
    let stderr: String
}

private enum RemoteBranchCheck {
    case exists
    case notFound
    case error(String)
}
