import Foundation

public struct NativeGitRepositoryService: Sendable {
    private let runner: NativeGitCommandRunner
    private static let mutationLockRegistry = MutationLockRegistry()

    public init(runner: NativeGitCommandRunner = NativeGitCommandRunner()) {
        self.runner = runner
    }

    public func loadLogSnapshot(at repositoryPath: String, query: WorkspaceGitLogQuery = WorkspaceGitLogQuery()) throws -> WorkspaceGitLogSnapshot {
        let refs = try loadRefs(at: repositoryPath)
        let commits = try loadLog(at: repositoryPath, query: query)
        return WorkspaceGitLogSnapshot(refs: refs, commits: commits)
    }

    public func loadRefs(at repositoryPath: String) throws -> WorkspaceGitRefsSnapshot {
        let result = try runner.runAllowingFailure(
            arguments: [
                "for-each-ref",
                "--format=%(objectname)\t%(refname)\t%(refname:short)\t%(upstream:short)\t%(HEAD)",
                "refs/heads",
                "refs/remotes",
                "refs/tags",
            ],
            at: repositoryPath
        )
        guard result.isSuccess else {
            throw WorkspaceGitCommandError.commandFailed(command: result.command.joined(separator: " "), message: result.errorMessage)
        }
        return NativeGitParsers.parseRefs(result.stdout)
    }

    public func loadLog(at repositoryPath: String, query: WorkspaceGitLogQuery = WorkspaceGitLogQuery()) throws -> [WorkspaceGitCommitSummary] {
        var arguments = [
            "log",
            "--graph",
            "--all",
            "--date-order",
            "--date=unix",
            "--decorate=short",
            "--pretty=format:%x1f%H%x1f%h%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%d%x1f%s",
            "-n",
            String(query.limit),
        ]

        if let revision = query.revision?.trimmingCharacters(in: .whitespacesAndNewlines), !revision.isEmpty {
            arguments.removeAll { $0 == "--all" }
            arguments.append(revision)
        }

        if let author = query.author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
            arguments.append("--author=\(author)")
        }

        if let since = query.since?.trimmingCharacters(in: .whitespacesAndNewlines), !since.isEmpty {
            arguments.append("--since=\(since)")
        }

        if let path = query.path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            arguments.append("--")
            arguments.append(path)
        }

        let result = try runner.runAllowingFailure(arguments: arguments, at: repositoryPath)
        if result.isSuccess {
            let commits = NativeGitParsers.parseGraphLog(result.stdout)
            guard let searchTerm = query.searchTerm?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !searchTerm.isEmpty
            else {
                return commits
            }
            let normalizedSearch = searchTerm.lowercased()
            return commits.filter { commit in
                commit.hash.lowercased().contains(normalizedSearch)
                    || commit.shortHash.lowercased().contains(normalizedSearch)
                    || commit.subject.lowercased().contains(normalizedSearch)
            }
        }
        if isEmptyRepositoryFailure(result) {
            return []
        }
        throw WorkspaceGitCommandError.commandFailed(command: result.command.joined(separator: " "), message: result.errorMessage)
    }

    public func loadLogAuthors(at repositoryPath: String, limit: Int = 200) throws -> [String] {
        let result = try runner.runAllowingFailure(
            arguments: [
                "log",
                "--all",
                "--format=%an",
                "-n",
                String(max(1, limit)),
            ],
            at: repositoryPath
        )
        if result.isSuccess {
            let authors = result.stdout
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return Array(Set(authors))
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
        if isEmptyRepositoryFailure(result) {
            return []
        }
        throw WorkspaceGitCommandError.commandFailed(command: result.command.joined(separator: " "), message: result.errorMessage)
    }

    public func loadCommitSummary(at repositoryPath: String, commitHash: String) throws -> WorkspaceGitCommitDetail {
        let detailResult = try runner.runAllowingFailure(
            arguments: [
                "show",
                "--quiet",
                "--date=unix",
                "--pretty=format:%H%x1f%h%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%d%x1f%s%x1f%b",
                commitHash,
            ],
            at: repositoryPath
        )
        guard detailResult.isSuccess else {
            throw WorkspaceGitCommandError.commandFailed(command: detailResult.command.joined(separator: " "), message: detailResult.errorMessage)
        }

        let filesResult = try runner.runAllowingFailure(
            arguments: ["show", "--name-status", "--format=", commitHash],
            at: repositoryPath
        )
        guard filesResult.isSuccess else {
            throw WorkspaceGitCommandError.commandFailed(command: filesResult.command.joined(separator: " "), message: filesResult.errorMessage)
        }

        let changes = NativeGitParsers.parseNameStatus(filesResult.stdout)
        return try NativeGitParsers.parseCommitDetail(detailResult.stdout, changedFiles: changes)
    }

    public func loadCommitDetail(at repositoryPath: String, commitHash: String) throws -> WorkspaceGitCommitDetail {
        var detail = try loadCommitSummary(at: repositoryPath, commitHash: commitHash)
        detail.diff = try loadDiffForCommit(at: repositoryPath, commitHash: commitHash)
        return detail
    }

    public func loadDiffForCommit(at repositoryPath: String, commitHash: String) throws -> String {
        let result = try runner.runAllowingFailure(
            arguments: ["show", "--patch", "--format=", "--no-color", commitHash],
            at: repositoryPath,
            timeout: 30
        )
        guard result.isSuccess else {
            throw WorkspaceGitCommandError.commandFailed(command: result.command.joined(separator: " "), message: result.errorMessage)
        }
        return result.stdout
    }

    public func loadDiffForCommitFile(at repositoryPath: String, commitHash: String, filePath: String) throws -> String {
        let normalizedPath = filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            return ""
        }
        let result = try runner.runAllowingFailure(
            arguments: ["show", "-m", "--first-parent", "--patch", "--format=", "--no-color", commitHash, "--", normalizedPath],
            at: repositoryPath,
            timeout: 30
        )
        guard result.isSuccess else {
            throw WorkspaceGitCommandError.commandFailed(command: result.command.joined(separator: " "), message: result.errorMessage)
        }
        return result.stdout
    }

    public func loadWorkingTreeDiff(at repositoryPath: String, filePath: String) throws -> String {
        let normalizedPath = filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            return ""
        }

        let unstagedResult = try runner.runAllowingFailure(
            arguments: ["diff", "--patch", "--no-color", "--", normalizedPath],
            at: repositoryPath,
            timeout: 30
        )
        guard unstagedResult.isSuccess else {
            throw WorkspaceGitCommandError.commandFailed(command: unstagedResult.command.joined(separator: " "), message: unstagedResult.errorMessage)
        }
        if !unstagedResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return unstagedResult.stdout
        }

        let stagedResult = try runner.runAllowingFailure(
            arguments: ["diff", "--patch", "--no-color", "--cached", "--", normalizedPath],
            at: repositoryPath,
            timeout: 30
        )
        guard stagedResult.isSuccess else {
            throw WorkspaceGitCommandError.commandFailed(command: stagedResult.command.joined(separator: " "), message: stagedResult.errorMessage)
        }
        if !stagedResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stagedResult.stdout
        }

        let trackedCheck = try runner.runAllowingFailure(
            arguments: ["ls-files", "--error-unmatch", "--", normalizedPath],
            at: repositoryPath
        )
        guard !trackedCheck.isSuccess else {
            return ""
        }

        let absolutePath = URL(fileURLWithPath: repositoryPath, isDirectory: true)
            .appending(path: normalizedPath)
            .standardizedFileURL
            .path
        guard FileManager.default.fileExists(atPath: absolutePath) else {
            return ""
        }

        let untrackedResult = try runner.runAllowingFailure(
            arguments: ["diff", "--patch", "--no-color", "--no-index", "/dev/null", absolutePath],
            at: repositoryPath,
            timeout: 30
        )
        if !untrackedResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return untrackedResult.stdout
        }
        guard untrackedResult.isSuccess || untrackedResult.exitCode == 1 else {
            throw WorkspaceGitCommandError.commandFailed(command: untrackedResult.command.joined(separator: " "), message: untrackedResult.errorMessage)
        }
        return untrackedResult.stdout
    }

    public func loadHeadFileContent(at repositoryPath: String, filePath: String) throws -> String {
        let normalizedPath = normalizeFilePath(filePath)
        guard !normalizedPath.isEmpty else {
            return ""
        }
        return try loadGitObjectText(
            arguments: ["show", "HEAD:\(normalizedPath)"],
            at: repositoryPath,
            emptyOnMissing: true
        )
    }

    public func loadIndexFileContent(at repositoryPath: String, filePath: String) throws -> String {
        try loadIndexStageFileContent(stage: 0, at: repositoryPath, filePath: filePath)
    }

    public func loadConflictFileContents(at repositoryPath: String, filePath: String) throws -> WorkspaceDiffConflictFileContents {
        WorkspaceDiffConflictFileContents(
            base: try loadIndexStageFileContent(stage: 1, at: repositoryPath, filePath: filePath),
            ours: try loadIndexStageFileContent(stage: 2, at: repositoryPath, filePath: filePath),
            theirs: try loadIndexStageFileContent(stage: 3, at: repositoryPath, filePath: filePath),
            result: try loadLocalFileContent(at: repositoryPath, filePath: filePath)
        )
    }

    public func loadLocalFileContent(at repositoryPath: String, filePath: String) throws -> String {
        let fileURL = fileURL(at: repositoryPath, filePath: filePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ""
        }
        let data = try Data(contentsOf: fileURL)
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    public func saveLocalFileContent(at repositoryPath: String, filePath: String, content: String) throws {
        let fileURL = fileURL(at: repositoryPath, filePath: filePath)
        try withMutationLock(at: repositoryPath) {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    public func stagePatch(at repositoryPath: String, patch: String) throws {
        try applyPatchMutation(
            patch,
            arguments: ["apply", "--cached", "--unidiff-zero", "--whitespace=nowarn", "--recount"],
            at: repositoryPath
        )
    }

    public func unstagePatch(at repositoryPath: String, patch: String) throws {
        try applyPatchMutation(
            patch,
            arguments: ["apply", "--cached", "--reverse", "--unidiff-zero", "--whitespace=nowarn", "--recount"],
            at: repositoryPath
        )
    }

    public func loadChanges(at repositoryPath: String) throws -> WorkspaceGitWorkingTreeSnapshot {
        let result = try runner.runAllowingFailure(
            arguments: ["status", "--porcelain=v2", "--branch", "--untracked-files=all"],
            at: repositoryPath
        )
        guard result.isSuccess else {
            throw WorkspaceGitCommandError.commandFailed(command: result.command.joined(separator: " "), message: result.errorMessage)
        }
        return NativeGitParsers.parseStatusPorcelainV2(result.stdout)
    }

    public func loadRemotes(at repositoryPath: String) throws -> [WorkspaceGitRemoteSnapshot] {
        let result = try runner.runAllowingFailure(arguments: ["remote", "-v"], at: repositoryPath)
        guard result.isSuccess else {
            throw WorkspaceGitCommandError.commandFailed(command: result.command.joined(separator: " "), message: result.errorMessage)
        }
        return NativeGitParsers.parseRemotes(result.stdout)
    }

    public func loadAheadBehind(at repositoryPath: String) throws -> WorkspaceGitAheadBehindSnapshot {
        let result = try runner.runAllowingFailure(
            arguments: ["status", "--porcelain=v2", "--branch"],
            at: repositoryPath
        )
        guard result.isSuccess else {
            throw WorkspaceGitCommandError.commandFailed(command: result.command.joined(separator: " "), message: result.errorMessage)
        }
        return NativeGitParsers.parseAheadBehind(result.stdout)
    }

    public func resolveGitDirectory(at repositoryPath: String) throws -> String {
        let repositoryURL = URL(fileURLWithPath: repositoryPath, isDirectory: true)
        let markerURL = repositoryURL.appending(path: ".git")

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: markerURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return markerURL.standardizedFileURL.path
        }

        if FileManager.default.fileExists(atPath: markerURL.path),
           let content = try? String(contentsOf: markerURL, encoding: .utf8)
        {
            return try NativeGitParsers.parseGitDirFromDotGitFile(content, repositoryPath: repositoryPath)
        }

        let result = try runner.runAllowingFailure(arguments: ["rev-parse", "--git-dir"], at: repositoryPath)
        guard result.isSuccess else {
            throw WorkspaceGitCommandError.invalidRepository("不是有效的 Git 仓库：\(repositoryPath)")
        }
        return NativeGitParsers.resolveGitDirOutput(result.stdout, repositoryPath: repositoryPath)
    }

    public func resolveGitDir(at repositoryPath: String) throws -> String {
        try resolveGitDirectory(at: repositoryPath)
    }

    public func loadOperationState(at repositoryPath: String) throws -> WorkspaceGitOperationState {
        let gitDirectory = try resolveGitDirectory(at: repositoryPath)
        let gitDirectoryURL = URL(fileURLWithPath: gitDirectory, isDirectory: true)

        if exists(at: gitDirectoryURL.appending(path: "rebase-merge")) || exists(at: gitDirectoryURL.appending(path: "rebase-apply")) {
            return .rebasing
        }
        if exists(at: gitDirectoryURL.appending(path: "MERGE_HEAD")) {
            return .merging
        }
        if exists(at: gitDirectoryURL.appending(path: "CHERRY_PICK_HEAD")) {
            return .cherryPicking
        }
        return .idle
    }

    public func stage(paths: [String], at repositoryPath: String) throws {
        let normalizedPaths = normalizePaths(paths)
        guard !normalizedPaths.isEmpty else {
            return
        }
        try runMutation(arguments: ["add", "--"] + normalizedPaths, at: repositoryPath)
    }

    public func unstage(paths: [String], at repositoryPath: String) throws {
        let normalizedPaths = normalizePaths(paths)
        guard !normalizedPaths.isEmpty else {
            return
        }
        try runMutation(arguments: ["reset", "HEAD", "--"] + normalizedPaths, at: repositoryPath)
    }

    public func stageAll(at repositoryPath: String) throws {
        try runMutation(arguments: ["add", "--all"], at: repositoryPath)
    }

    public func unstageAll(at repositoryPath: String) throws {
        try runMutation(arguments: ["reset"], at: repositoryPath)
    }

    public func discard(paths: [String], at repositoryPath: String) throws {
        let normalizedPaths = normalizePaths(paths)
        guard !normalizedPaths.isEmpty else {
            return
        }

        try withMutationLock(at: repositoryPath) {
            let snapshot = try loadChanges(at: repositoryPath)
            let stagedByPath = Dictionary(uniqueKeysWithValues: snapshot.staged.map { ($0.path, $0) })
            let unstagedByPath = Dictionary(uniqueKeysWithValues: snapshot.unstaged.map { ($0.path, $0) })
            let untrackedPaths = Set(snapshot.untracked.map(\.path))

            var trackedRestorePaths = Set<String>()
            var cleanPaths = Set<String>()

            for path in normalizedPaths {
                if let stagedEntry = stagedByPath[path] {
                    if stagedEntry.indexStatus == "A", stagedEntry.originalPath == nil {
                        try runMutationLocked(
                            arguments: ["rm", "--force", "--cached", "--", path],
                            at: repositoryPath
                        )
                        cleanPaths.insert(path)
                    } else {
                        trackedRestorePaths.insert(path)
                        if let originalPath = stagedEntry.originalPath {
                            trackedRestorePaths.insert(originalPath)
                        }
                    }
                }

                if let unstagedEntry = unstagedByPath[path] {
                    trackedRestorePaths.insert(path)
                    if let originalPath = unstagedEntry.originalPath {
                        trackedRestorePaths.insert(originalPath)
                    }
                }

                if untrackedPaths.contains(path) {
                    cleanPaths.insert(path)
                }
            }

            if !trackedRestorePaths.isEmpty {
                try runMutationLocked(
                    arguments: ["restore", "--source=HEAD", "--staged", "--worktree", "--"] + trackedRestorePaths.sorted(),
                    at: repositoryPath
                )
            }

            if !cleanPaths.isEmpty {
                try runMutationLocked(
                    arguments: ["clean", "-fd", "--"] + cleanPaths.sorted(),
                    at: repositoryPath
                )
            }
        }
    }

    public func commit(message: String, at repositoryPath: String) throws {
        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMessage.isEmpty else {
            throw WorkspaceGitCommandError.parseFailure("提交信息不能为空")
        }
        try runMutation(
            arguments: ["commit", "-m", normalizedMessage],
            at: repositoryPath,
            environment: nonInteractiveEnvironment
        )
    }

    public func amend(message: String?, at repositoryPath: String) throws {
        if let message {
            let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedMessage.isEmpty else {
                throw WorkspaceGitCommandError.parseFailure("修订提交信息不能为空")
            }
            try runMutation(
                arguments: ["commit", "--amend", "-m", normalizedMessage],
                at: repositoryPath,
                environment: nonInteractiveEnvironment
            )
            return
        }
        try runMutation(
            arguments: ["commit", "--amend", "--no-edit"],
            at: repositoryPath,
            environment: nonInteractiveEnvironment
        )
    }

    public func createBranch(name: String, startPoint: String?, at repositoryPath: String) throws {
        let normalizedName = try normalizeBranchName(name)
        var arguments = ["branch", normalizedName]
        if let startPoint {
            let normalizedStartPoint = startPoint.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedStartPoint.isEmpty {
                arguments.append(normalizedStartPoint)
            }
        }
        try runMutation(arguments: arguments, at: repositoryPath)
    }

    public func checkoutBranch(name: String, at repositoryPath: String) throws {
        let normalizedName = try normalizeBranchName(name)
        try runMutation(arguments: ["checkout", normalizedName], at: repositoryPath)
    }

    public func deleteLocalBranch(name: String, at repositoryPath: String) throws {
        let normalizedName = try normalizeBranchName(name)
        let currentBranch = try currentBranchName(at: repositoryPath)
        if currentBranch == normalizedName {
            throw WorkspaceGitCommandError.operationRejected("不能删除当前分支：\(normalizedName)")
        }
        try runMutation(arguments: ["branch", "-d", normalizedName], at: repositoryPath)
    }

    public func fetch(at repositoryPath: String) throws {
        try runMutation(
            arguments: ["fetch", "--prune", "--tags"],
            at: repositoryPath,
            timeout: 90,
            environment: nonInteractiveEnvironment
        )
    }

    public func pull(at repositoryPath: String) throws {
        try runMutation(
            arguments: ["pull", "--ff-only"],
            at: repositoryPath,
            timeout: 90,
            environment: nonInteractiveEnvironment
        )
    }

    public func push(at repositoryPath: String) throws {
        try runMutation(
            arguments: ["push"],
            at: repositoryPath,
            timeout: 90,
            environment: nonInteractiveEnvironment
        )
    }

    public func abortOperation(at repositoryPath: String) throws {
        switch try loadOperationState(at: repositoryPath) {
        case .idle:
            throw WorkspaceGitCommandError.operationRejected("当前仓库没有可终止的 merge/rebase/cherry-pick 流程。")
        case .merging:
            try runMutation(arguments: ["merge", "--abort"], at: repositoryPath)
        case .rebasing:
            try runMutation(arguments: ["rebase", "--abort"], at: repositoryPath)
        case .cherryPicking:
            try runMutation(arguments: ["cherry-pick", "--abort"], at: repositoryPath)
        }
    }

    private func exists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func isEmptyRepositoryFailure(_ result: NativeGitCommandRunner.Result) -> Bool {
        let message = result.errorMessage.lowercased()
        return message.contains("does not have any commits yet")
            || message.contains("bad revision 'head'")
            || message.contains("unknown revision or path not in the working tree")
            || message.contains("your current branch")
    }

    private func runMutation(
        arguments: [String],
        at repositoryPath: String,
        timeout: TimeInterval? = nil,
        environment: [String: String] = [:]
    ) throws {
        try withMutationLock(at: repositoryPath) {
            try runMutationLocked(
                arguments: arguments,
                at: repositoryPath,
                timeout: timeout,
                environment: environment
            )
        }
    }

    private func withMutationLock<T>(
        at repositoryPath: String,
        _ body: () throws -> T
    ) throws -> T {
        let serializationKey = try resolveCommonGitDirectory(at: repositoryPath)
        return try Self.mutationLockRegistry.withLock(for: serializationKey, body)
    }

    private func runMutationLocked(
        arguments: [String],
        at repositoryPath: String,
        timeout: TimeInterval? = nil,
        environment: [String: String] = [:]
    ) throws {
        let result = try runner.runAllowingFailure(
            arguments: arguments,
            at: repositoryPath,
            timeout: timeout,
            environment: environment
        )
        guard result.isSuccess else {
            throw mapMutationError(
                command: result.command.joined(separator: " "),
                message: result.errorMessage
            )
        }
    }

    private func resolveCommonGitDirectory(at repositoryPath: String) throws -> String {
        let absoluteResult = try runner.runAllowingFailure(
            arguments: ["rev-parse", "--path-format=absolute", "--git-common-dir"],
            at: repositoryPath
        )
        if absoluteResult.isSuccess {
            let path = absoluteResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                return URL(fileURLWithPath: path).standardizedFileURL.path
            }
        }

        let fallbackResult = try runner.runAllowingFailure(
            arguments: ["rev-parse", "--git-common-dir"],
            at: repositoryPath
        )
        if fallbackResult.isSuccess {
            return NativeGitParsers.resolveGitDirOutput(fallbackResult.stdout, repositoryPath: repositoryPath)
        }

        return try resolveGitDirectory(at: repositoryPath)
    }

    private func mapMutationError(command: String, message: String) -> WorkspaceGitCommandError {
        let lowercasedMessage = message.lowercased()

        if lowercasedMessage.contains("terminal prompts disabled")
            || lowercasedMessage.contains("could not read username")
            || lowercasedMessage.contains("authentication failed")
            || lowercasedMessage.contains("permission denied (publickey)")
            || lowercasedMessage.contains("passphrase")
            || lowercasedMessage.contains("askpass")
            || lowercasedMessage.contains("credentials")
        {
            return .interactionRequired(command: command, reason: "检测到认证/凭据交互，请回到终端完成认证后重试。")
        }

        if lowercasedMessage.contains("editor")
            || lowercasedMessage.contains("waiting for your editor")
            || lowercasedMessage.contains("could not launch editor")
        {
            return .interactionRequired(command: command, reason: "命令需要编辑器交互，请回到终端处理。")
        }

        if lowercasedMessage.contains("gpg failed to sign")
            || lowercasedMessage.contains("failed to sign")
            || lowercasedMessage.contains("no pinentry")
            || lowercasedMessage.contains("signing")
        {
            return .interactionRequired(command: command, reason: "命令需要签名交互，请回到终端处理。")
        }

        if lowercasedMessage.contains("hook")
            || lowercasedMessage.contains("pre-commit")
            || lowercasedMessage.contains("pre-push")
            || lowercasedMessage.contains("prepare-commit-msg")
        {
            return .interactionRequired(command: command, reason: "命令被 hooks 拦截或需要交互，请回到终端查看详情。")
        }

        if lowercasedMessage.contains("resolve your current index first")
            || lowercasedMessage.contains("merge conflict")
            || lowercasedMessage.contains("needs merge")
            || lowercasedMessage.contains("rebase --continue")
            || lowercasedMessage.contains("cherry-pick --continue")
        {
            return .interactionRequired(command: command, reason: "仓库当前存在冲突或进行中的交互流程，请回到终端处理。")
        }

        return .commandFailed(command: command, message: message)
    }

    private func normalizePaths(_ paths: [String]) -> [String] {
        paths
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func normalizeBranchName(_ branchName: String) throws -> String {
        let normalized = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw WorkspaceGitCommandError.parseFailure("分支名不能为空")
        }
        return normalized
    }

    private func currentBranchName(at repositoryPath: String) throws -> String {
        let result = try runner.runAllowingFailure(
            arguments: ["rev-parse", "--abbrev-ref", "HEAD"],
            at: repositoryPath
        )
        guard result.isSuccess else {
            throw WorkspaceGitCommandError.commandFailed(
                command: result.command.joined(separator: " "),
                message: result.errorMessage
            )
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadIndexStageFileContent(stage: Int, at repositoryPath: String, filePath: String) throws -> String {
        let normalizedPath = normalizeFilePath(filePath)
        guard !normalizedPath.isEmpty else {
            return ""
        }
        return try loadGitObjectText(
            arguments: ["show", ":\(stage):\(normalizedPath)"],
            at: repositoryPath,
            emptyOnMissing: true
        )
    }

    private func loadGitObjectText(
        arguments: [String],
        at repositoryPath: String,
        emptyOnMissing: Bool
    ) throws -> String {
        let result = try runner.runAllowingFailure(arguments: arguments, at: repositoryPath, timeout: 30)
        if result.isSuccess {
            return result.stdout
        }
        if emptyOnMissing, isMissingObjectFailure(result) {
            return ""
        }
        throw WorkspaceGitCommandError.commandFailed(
            command: result.command.joined(separator: " "),
            message: result.errorMessage
        )
    }

    private func applyPatchMutation(
        _ patch: String,
        arguments: [String],
        at repositoryPath: String
    ) throws {
        guard !patch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        try withMutationLock(at: repositoryPath) {
            let patchURL = FileManager.default.temporaryDirectory
                .appending(path: "devhaven-git-patch-\(UUID().uuidString).patch")
            let payload = patch.hasSuffix("\n") ? patch : patch + "\n"
            try payload.write(to: patchURL, atomically: true, encoding: .utf8)
            defer {
                try? FileManager.default.removeItem(at: patchURL)
            }
            try runMutationLocked(arguments: arguments + [patchURL.path], at: repositoryPath)
        }
    }

    private func fileURL(at repositoryPath: String, filePath: String) -> URL {
        URL(fileURLWithPath: repositoryPath, isDirectory: true)
            .appending(path: normalizeFilePath(filePath))
            .standardizedFileURL
    }

    private func normalizeFilePath(_ filePath: String) -> String {
        filePath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isMissingObjectFailure(_ result: NativeGitCommandRunner.Result) -> Bool {
        let message = result.errorMessage.lowercased()
        return message.contains("exists on disk, but not in")
            || message.contains("does not exist in")
            || message.contains("not in the index")
            || message.contains("not at stage")
            || message.contains("unknown revision or path not in the working tree")
            || message.contains("bad revision")
    }

    private var nonInteractiveEnvironment: [String: String] {
        [
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_ASKPASS": "echo",
            "GIT_EDITOR": "true",
        ]
    }
}

private final class MutationLockRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var locksByKey: [String: NSLock] = [:]

    func withLock<T>(for key: String, _ body: () throws -> T) rethrows -> T {
        let mutationLock = lock.withLock { () -> NSLock in
            if let existing = locksByKey[key] {
                return existing
            }
            let created = NSLock()
            locksByKey[key] = created
            return created
        }

        mutationLock.lock()
        defer { mutationLock.unlock() }
        return try body()
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
