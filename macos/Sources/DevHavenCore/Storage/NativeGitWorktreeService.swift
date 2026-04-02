import Foundation

public struct NativeGitWorktreeService: NativeWorktreeServicing {
    private let homeDirectoryURL: URL

    public init(homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectoryURL = homeDirectoryURL
    }

    public func managedWorktreePath(for sourceProjectPath: String, branch: String) throws -> String {
        try resolveTargetPath(sourceProjectPath: sourceProjectPath, branch: branch, explicitTargetPath: nil)
    }

    public func preflightCreateWorktree(_ request: NativeWorktreeCreateRequest) throws -> String {
        try ensureGitRepository(at: request.sourceProjectPath)
        let branch = try normalizeBranchName(request.branch)
        try validateBranchName(branch, at: request.sourceProjectPath)
        let targetPath = try resolveTargetPath(
            sourceProjectPath: request.sourceProjectPath,
            branch: branch,
            explicitTargetPath: request.targetPath
        )
        try validateTargetPath(targetPath, sourceProjectPath: request.sourceProjectPath)
        try validateCreateRequest(request, branch: branch)
        _ = try resolveCreateBranchStartPointIfNeeded(request, branch: branch)
        return targetPath
    }

    public func currentBranch(at projectPath: String) throws -> String {
        try ensureGitRepository(at: projectPath)
        if let output = try? runGit(["symbolic-ref", "--quiet", "--short", "HEAD"], at: projectPath).stdout {
            let branch = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !branch.isEmpty {
                return branch
            }
        }

        let output = try runGit(["rev-parse", "--abbrev-ref", "HEAD"], at: projectPath).stdout
        let branch = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else {
            throw NativeWorktreeError.commandFailed("无法获取当前分支")
        }
        return branch
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

    public func listBaseBranchReferences(at projectPath: String) throws -> [NativeGitBaseBranchReference] {
        try ensureGitRepository(at: projectPath)
        let localBranches = try listBranches(at: projectPath)
        let mainBranchName = localBranches.first(where: \.isMain)?.name

        let localReferences = localBranches.map { branch in
            NativeGitBaseBranchReference(
                name: branch.name,
                kind: .local,
                isMain: branch.isMain
            )
        }

        let remoteOutput = (try? runGit(
            ["for-each-ref", "--format=%(refname:short)|%(refname)", "refs/remotes"],
            at: projectPath
        ).stdout) ?? ""
        let remoteReferences = remoteOutput
            .split(whereSeparator: \.isNewline)
            .compactMap { rawLine -> (shortName: String, fullRef: String)? in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else {
                    return nil
                }
                let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
                guard parts.count == 2 else {
                    return nil
                }
                let shortName = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let fullRef = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !shortName.isEmpty, !fullRef.isEmpty else {
                    return nil
                }
                return (shortName, fullRef)
            }
            .filter { !$0.fullRef.hasSuffix("/HEAD") }
            .map { reference in
                NativeGitBaseBranchReference(
                    name: reference.shortName,
                    kind: .remote,
                    isMain: remoteBranchShortName(reference.shortName) == mainBranchName
                )
            }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

        return localReferences + remoteReferences
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
        try validateBranchName(branch, at: request.sourceProjectPath)
        let targetPath = try resolveTargetPath(
            sourceProjectPath: request.sourceProjectPath,
            branch: branch,
            explicitTargetPath: request.targetPath
        )
        try validateTargetPath(targetPath, sourceProjectPath: request.sourceProjectPath)

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
                step: .syncing,
                message: "Git worktree 已创建"
            )
        )

        return NativeWorktreeCreateResult(
            worktreePath: targetPath,
            branch: branch,
            baseBranch: request.baseBranch,
            warning: nil
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
            _ = try runGit(["worktree", "remove", "--force", request.worktreePath], at: request.sourceProjectPath)
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

    public func cleanupFailedWorktreeCreate(_ request: NativeWorktreeCleanupRequest) throws -> NativeWorktreeCleanupResult {
        try ensureGitRepository(at: request.sourceProjectPath)

        let normalizedWorktreePath = normalizePathForCompare(request.worktreePath)
        guard !normalizedWorktreePath.isEmpty else {
            return NativeWorktreeCleanupResult(warning: "清理失败 worktree 时未提供有效路径")
        }

        var removedWorktree = false
        var removedDirectory = false
        var removedBranch = false
        var warnings = [String]()

        if let listed = try? listWorktrees(at: request.sourceProjectPath),
           listed.contains(where: { normalizePathForCompare($0.path) == normalizedWorktreePath }) {
            do {
                _ = try runGit(["worktree", "remove", "--force", request.worktreePath], at: request.sourceProjectPath)
                removedWorktree = true
            } catch {
                warnings.append("移除残留 worktree 失败：\(error.localizedDescription)")
            }
        }

        if request.shouldDeleteCreatedBranch,
           let branch = request.branch?.trimmingCharacters(in: .whitespacesAndNewlines),
           !branch.isEmpty {
            let listedAfterRemove = (try? listWorktrees(at: request.sourceProjectPath)) ?? []
            let branchOccupied = listedAfterRemove.contains(where: { $0.branch == branch })
            if !branchOccupied {
                let localBranches = (try? listBranches(at: request.sourceProjectPath).map(\.name)) ?? []
                if localBranches.contains(branch) {
                    do {
                        _ = try runGit(["branch", "-D", branch], at: request.sourceProjectPath)
                        removedBranch = true
                    } catch {
                        warnings.append("删除残留分支 \(branch) 失败：\(error.localizedDescription)")
                    }
                }
            }
        }

        let targetURL = URL(fileURLWithPath: request.worktreePath)
        if FileManager.default.fileExists(atPath: targetURL.path),
           isManagedWorktreePath(request.worktreePath, for: request.sourceProjectPath) {
            do {
                try FileManager.default.removeItem(at: targetURL)
                removedDirectory = true
            } catch {
                warnings.append("删除残留目录失败：\(error.localizedDescription)")
            }
        }

        do {
            _ = try runGit(["worktree", "prune"], at: request.sourceProjectPath)
        } catch {
            warnings.append("执行 git worktree prune 失败：\(error.localizedDescription)")
        }

        return NativeWorktreeCleanupResult(
            removedWorktree: removedWorktree,
            removedDirectory: removedDirectory,
            removedBranch: removedBranch,
            warning: warnings.isEmpty ? nil : warnings.joined(separator: "\n")
        )
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
                if shouldForceDeleteBranchAfterSafeDeleteFailure(message) {
                    do {
                        _ = try runGit(["branch", "-D", branch], at: request.sourceProjectPath)
                        return NativeWorktreeRemoveResult(warning: nil)
                    } catch let forcedError as NativeWorktreeError {
                        if case let .commandFailed(forcedMessage) = forcedError {
                            return NativeWorktreeRemoveResult(warning: normalizeDeleteBranchError(forcedMessage))
                        }
                        throw forcedError
                    }
                }
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

        if let remoteReference = resolveExplicitRemoteReference(projectPath: projectPath, baseBranch: baseBranch) {
            return try resolveExplicitRemoteStartPoint(projectPath: projectPath, remoteReference: remoteReference)
        }

        if refExistsLocally(projectPath: projectPath, reference: baseBranch) {
            return baseBranch
        }

        throw NativeWorktreeError.invalidBaseBranch("基线分支不可用：未找到本地分支 \(baseBranch)")
    }

    private func resolveTargetPath(sourceProjectPath: String, branch: String, explicitTargetPath: String?) throws -> String {
        let trimmed = explicitTargetPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            guard NSString(string: trimmed).isAbsolutePath else {
                throw NativeWorktreeError.invalidPath("目标路径必须是绝对路径")
            }
            let explicitURL = URL(fileURLWithPath: trimmed, isDirectory: true)
            let normalizedExplicitPath = explicitURL.standardizedFileURL.path()
            let normalizedSourcePath = URL(fileURLWithPath: sourceProjectPath, isDirectory: true).standardizedFileURL.path()
            guard normalizePathForCompare(normalizedExplicitPath) != normalizePathForCompare(normalizedSourcePath) else {
                throw NativeWorktreeError.invalidPath("目标目录不能与主仓库目录相同")
            }
            return normalizedExplicitPath
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

    private func resolveExplicitRemoteStartPoint(
        projectPath: String,
        remoteReference: ExplicitRemoteReference
    ) throws -> String {
        switch branchExistsOnRemote(
            projectPath: projectPath,
            remoteName: remoteReference.remoteName,
            branch: remoteReference.branchName
        ) {
        case .exists:
            let fetchErrorMessage: String?
            do {
                try fetchRemoteBranch(
                    projectPath: projectPath,
                    remoteName: remoteReference.remoteName,
                    branch: remoteReference.branchName
                )
                fetchErrorMessage = nil
            } catch {
                fetchErrorMessage = error.localizedDescription
            }
            if refExistsLocally(projectPath: projectPath, reference: remoteReference.reference) {
                return remoteReference.reference
            }
            if let fetchErrorMessage {
                throw NativeWorktreeError.invalidBaseBranch(
                    "基线分支不可用：远端分支 \(remoteReference.reference) 刷新失败，且本地无法解析（\(fetchErrorMessage)）"
                )
            }
            throw NativeWorktreeError.invalidBaseBranch("基线分支不可用：远端分支 \(remoteReference.reference) 无法在本地解析")
        case .notFound:
            throw NativeWorktreeError.invalidBaseBranch("基线分支不可用：远端不存在分支 \(remoteReference.reference)")
        case let .error(message):
            throw NativeWorktreeError.invalidBaseBranch(
                "基线分支不可用：无法校验远端分支 \(remoteReference.reference)（\(message)）"
            )
        }
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

    private func validateBranchName(_ branch: String, at projectPath: String) throws {
        if branch.contains(where: \.isWhitespace) {
            throw NativeWorktreeError.invalidBranch("分支名不能包含空格")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "check-ref-format", "--branch", branch]
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath, isDirectory: true)
        let stderr = Pipe()
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw NativeWorktreeError.invalidBranch("分支名不合法：\(error.localizedDescription)")
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if stderrText.isEmpty {
                throw NativeWorktreeError.invalidBranch("分支名不合法，请检查后重试")
            }
            throw NativeWorktreeError.invalidBranch("分支名不合法：\(stderrText)")
        }
    }

    private func validateTargetPath(_ targetPath: String, sourceProjectPath: String) throws {
        let normalizedTargetPath = normalizePathForCompare(targetPath)
        guard !normalizedTargetPath.isEmpty else {
            throw NativeWorktreeError.invalidPath("目标路径不能为空")
        }
        let normalizedSourcePath = normalizePathForCompare(sourceProjectPath)
        if normalizedTargetPath == normalizedSourcePath {
            throw NativeWorktreeError.invalidPath("目标路径不能与主仓库目录相同")
        }
        let managedRoot = normalizePathForCompare(
            homeDirectoryURL
                .appending(path: ".devhaven", directoryHint: .isDirectory)
                .appending(path: "worktrees", directoryHint: .isDirectory)
                .appending(path: resolveRepositoryName(sourceProjectPath), directoryHint: .isDirectory)
                .path()
        )
        let targetComponents = URL(fileURLWithPath: normalizedTargetPath).standardizedFileURL.pathComponents
        let rootComponents = URL(fileURLWithPath: managedRoot).standardizedFileURL.pathComponents
        guard targetComponents.count >= rootComponents.count,
              Array(targetComponents.prefix(rootComponents.count)) == rootComponents else {
            throw NativeWorktreeError.invalidPath("目标路径必须位于 DevHaven 管理的 worktree 目录内")
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

    private func remoteNames(projectPath: String) -> Set<String> {
        let output = (try? runGit(["remote"], at: projectPath).stdout) ?? ""
        return Set(
            output
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    private func fetchRemoteBranch(projectPath: String, remoteName: String, branch: String) throws {
        _ = try runGit(["fetch", remoteName, branch], at: projectPath)
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

    private func branchExistsOnRemote(projectPath: String, remoteName: String, branch: String) -> RemoteBranchCheck {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "ls-remote", "--exit-code", "--heads", remoteName, branch]
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

    private func resolveExplicitRemoteReference(
        projectPath: String,
        baseBranch: String
    ) -> ExplicitRemoteReference? {
        let components = baseBranch.split(separator: "/", maxSplits: 1).map(String.init)
        guard components.count == 2 else {
            return nil
        }
        let remoteName = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let branchName = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remoteName.isEmpty,
              !branchName.isEmpty,
              remoteNames(projectPath: projectPath).contains(remoteName)
        else {
            return nil
        }
        return ExplicitRemoteReference(
            remoteName: remoteName,
            branchName: branchName,
            reference: "\(remoteName)/\(branchName)"
        )
    }

    private func remoteBranchShortName(_ reference: String) -> String {
        let components = reference.split(separator: "/", maxSplits: 1).map(String.init)
        guard components.count == 2 else {
            return reference
        }
        return components[1]
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

    private func isManagedWorktreePath(_ worktreePath: String, for sourceProjectPath: String) -> Bool {
        let managedRoot = homeDirectoryURL
            .appending(path: ".devhaven", directoryHint: .isDirectory)
            .appending(path: "worktrees", directoryHint: .isDirectory)
            .appending(path: resolveRepositoryName(sourceProjectPath), directoryHint: .isDirectory)

        let normalizedTarget = URL(fileURLWithPath: worktreePath).standardizedFileURL.pathComponents
        let normalizedRoot = managedRoot.standardizedFileURL.pathComponents
        guard normalizedTarget.count >= normalizedRoot.count else {
            return false
        }
        return Array(normalizedTarget.prefix(normalizedRoot.count)) == normalizedRoot
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

    private func shouldForceDeleteBranchAfterSafeDeleteFailure(_ raw: String) -> Bool {
        raw.lowercased().contains("not fully merged")
    }

}

private struct ProcessOutput {
    let stdout: String
    let stderr: String
}

private struct ExplicitRemoteReference {
    let remoteName: String
    let branchName: String
    let reference: String
}

private enum RemoteBranchCheck {
    case exists
    case notFound
    case error(String)
}
