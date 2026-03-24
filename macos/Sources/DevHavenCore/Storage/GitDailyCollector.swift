import Foundation

private let gitLogPrettyWithIdentity = "--pretty=format:%an\u{1f}%ae\u{1f}%cd"
private let gitLogPrettyDateOnly = "--pretty=format:%cd"
private let gitLastCommitPretty = "--format=%ct\u{1f}%s"
private let gitLogTimeoutSeconds: TimeInterval = 8
private let gitLogMaxConcurrentTasks = 4

func collectGitDaily(paths: [String], identities: [GitIdentity]) -> [GitDailyRefreshResult] {
    let matcher = GitIdentityMatcher(identities: identities)
    return paths.map { path in
        collectSingleGitDaily(path: path, matcher: matcher)
    }
}

func collectGitDailyAsync(
    paths: [String],
    identities: [GitIdentity],
    progress: (@Sendable (_ completed: Int, _ total: Int) async -> Void)? = nil
) async -> [GitDailyRefreshResult] {
    let matcher = GitIdentityMatcher(identities: identities)
    let total = paths.count
    guard total > 0 else {
        return []
    }

    await progress?(0, total)
    let workerCount = min(gitLogMaxConcurrentTasks, total)
    var results = Array<GitDailyRefreshResult?>(repeating: nil, count: total)
    var nextIndex = 0
    var completed = 0

    await withTaskGroup(of: (Int, GitDailyRefreshResult).self) { group in
        func enqueue(_ index: Int) {
            let path = paths[index]
            group.addTask {
                (index, collectSingleGitDaily(path: path, matcher: matcher))
            }
        }

        while nextIndex < workerCount {
            enqueue(nextIndex)
            nextIndex += 1
        }

        while let (index, result) = await group.next() {
            results[index] = result
            completed += 1
            await progress?(completed, total)

            if nextIndex < total {
                enqueue(nextIndex)
                nextIndex += 1
            }
        }
    }

    return results.compactMap { $0 }
}

private func collectSingleGitDaily(path: String, matcher: GitIdentityMatcher) -> GitDailyRefreshResult {
    let repoURL = URL(fileURLWithPath: path, isDirectory: true)
    guard FileManager.default.fileExists(atPath: repoURL.appending(path: ".git").path()) else {
        return GitDailyRefreshResult(path: path, gitDaily: nil, error: nil)
    }

    let metadata = collectGitHeadMetadata(path: path, repoURL: repoURL)
    if let error = metadata.error {
        return GitDailyRefreshResult(
            path: path,
            gitDaily: nil,
            gitCommits: metadata.commitCount,
            gitLastCommit: metadata.lastCommit,
            gitLastCommitMessage: metadata.lastCommitMessage,
            error: error
        )
    }
    guard metadata.commitCount > 0 else {
        return GitDailyRefreshResult(
            path: path,
            gitDaily: nil,
            gitCommits: 0,
            gitLastCommit: .zero,
            gitLastCommitMessage: nil,
            error: nil
        )
    }

    let prettyArgument = matcher.matchesAll ? gitLogPrettyDateOnly : gitLogPrettyWithIdentity
    let dailyResult = runGitCommand(["git", "log", prettyArgument, "--date=short"], in: repoURL)
    if dailyResult.timedOut {
        return GitDailyRefreshResult(
            path: path,
            gitDaily: nil,
            gitCommits: metadata.commitCount,
            gitLastCommit: metadata.lastCommit,
            gitLastCommitMessage: metadata.lastCommitMessage,
            error: "git log 超时（>\(Int(gitLogTimeoutSeconds)) 秒）"
        )
    }
    if let startupError = dailyResult.startupError {
        return GitDailyRefreshResult(
            path: path,
            gitDaily: nil,
            gitCommits: metadata.commitCount,
            gitLastCommit: metadata.lastCommit,
            gitLastCommitMessage: metadata.lastCommitMessage,
            error: "执行 git log 失败: \(startupError)"
        )
    }
    guard dailyResult.terminationStatus == 0 else {
        let message = dailyResult.stderr.isEmpty ? "未知错误" : dailyResult.stderr
        return GitDailyRefreshResult(
            path: path,
            gitDaily: nil,
            gitCommits: metadata.commitCount,
            gitLastCommit: metadata.lastCommit,
            gitLastCommitMessage: metadata.lastCommitMessage,
            error: "git log 返回失败: \(message)"
        )
    }

    let output = dailyResult.stdout
    let counts = parseGitLogCounts(output, matcher: matcher)
    let gitDaily = counts.isEmpty
        ? nil
        : counts
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")
    return GitDailyRefreshResult(
        path: path,
        gitDaily: gitDaily,
        gitCommits: metadata.commitCount,
        gitLastCommit: metadata.lastCommit,
        gitLastCommitMessage: metadata.lastCommitMessage,
        error: nil
    )
}

private struct GitCommandExecutionResult {
    let stdout: String
    let stderr: String
    let terminationStatus: Int32
    let startupError: String?
    let timedOut: Bool
}

private struct GitHeadMetadata {
    let commitCount: Int
    let lastCommit: SwiftDate
    let lastCommitMessage: String?
    let error: String?
}

private func collectGitHeadMetadata(path: String, repoURL: URL) -> GitHeadMetadata {
    let countResult = runGitCommand(["git", "rev-list", "--count", "HEAD"], in: repoURL)
    if countResult.timedOut {
        return GitHeadMetadata(commitCount: 0, lastCommit: .zero, lastCommitMessage: nil, error: "git rev-list 超时（>\(Int(gitLogTimeoutSeconds)) 秒）")
    }
    if let startupError = countResult.startupError {
        return GitHeadMetadata(commitCount: 0, lastCommit: .zero, lastCommitMessage: nil, error: "执行 git rev-list 失败: \(startupError)")
    }
    guard countResult.terminationStatus == 0 else {
        if isGitNoCommitsMessage(countResult.stderr) {
            return GitHeadMetadata(commitCount: 0, lastCommit: .zero, lastCommitMessage: nil, error: nil)
        }
        let message = countResult.stderr.isEmpty ? "未知错误" : countResult.stderr
        return GitHeadMetadata(commitCount: 0, lastCommit: .zero, lastCommitMessage: nil, error: "git rev-list 返回失败: \(message)")
    }

    let commitCount = Int(countResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    guard commitCount > 0 else {
        return GitHeadMetadata(commitCount: 0, lastCommit: .zero, lastCommitMessage: nil, error: nil)
    }

    let lastCommitResult = runGitCommand(["git", "log", gitLastCommitPretty, "-n", "1"], in: repoURL)
    if lastCommitResult.timedOut {
        return GitHeadMetadata(commitCount: commitCount, lastCommit: .zero, lastCommitMessage: nil, error: "git log 超时（>\(Int(gitLogTimeoutSeconds)) 秒）")
    }
    if let startupError = lastCommitResult.startupError {
        return GitHeadMetadata(commitCount: commitCount, lastCommit: .zero, lastCommitMessage: nil, error: "执行 git log 失败: \(startupError)")
    }
    guard lastCommitResult.terminationStatus == 0 else {
        if isGitNoCommitsMessage(lastCommitResult.stderr) {
            return GitHeadMetadata(commitCount: 0, lastCommit: .zero, lastCommitMessage: nil, error: nil)
        }
        let message = lastCommitResult.stderr.isEmpty ? "未知错误" : lastCommitResult.stderr
        return GitHeadMetadata(commitCount: commitCount, lastCommit: .zero, lastCommitMessage: nil, error: "git log 返回失败: \(message)")
    }

    let (lastCommit, lastCommitMessage) = parseLastCommitLogOutput(lastCommitResult.stdout)
    return GitHeadMetadata(
        commitCount: commitCount,
        lastCommit: lastCommit > 0 ? lastCommit : .zero,
        lastCommitMessage: lastCommitMessage,
        error: nil
    )
}

private func runGitCommand(_ arguments: [String], in repoURL: URL) -> GitCommandExecutionResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    process.currentDirectoryURL = repoURL

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    do {
        try process.run()
    } catch {
        return GitCommandExecutionResult(stdout: "", stderr: "", terminationStatus: -1, startupError: error.localizedDescription, timedOut: false)
    }

    let deadline = Date().addingTimeInterval(gitLogTimeoutSeconds)
    while process.isRunning && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
    }

    let timedOut = process.isRunning
    if timedOut {
        process.terminate()
    }
    process.waitUntilExit()

    return GitCommandExecutionResult(
        stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
        stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
        terminationStatus: process.terminationStatus,
        startupError: nil,
        timedOut: timedOut
    )
}

private func parseLastCommitLogOutput(_ output: String) -> (SwiftDate, String?) {
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return (.zero, nil)
    }

    let parts = trimmed.split(separator: "\u{1f}", maxSplits: 1, omittingEmptySubsequences: false)
    let lastCommit = TimeInterval(parts.first ?? "") ?? 0
    let message = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    return (lastCommit, message.isEmpty ? nil : message)
}

private func isGitNoCommitsMessage(_ message: String) -> Bool {
    let normalized = message.lowercased()
    return normalized.contains("does not have any commits yet")
        || normalized.contains("ambiguous argument 'head'")
        || normalized.contains("your current branch")
}

private struct GitIdentityMatcher: Sendable {
    let tokens: Set<String>

    init(identities: [GitIdentity]) {
        var nextTokens = Set<String>()
        for identity in identities {
            if let normalizedName = normalizeIdentityToken(identity.name) {
                nextTokens.insert(normalizedName)
            }
            if let normalizedEmail = normalizeIdentityToken(identity.email) {
                nextTokens.insert(normalizedEmail)
            }
        }
        self.tokens = nextTokens
    }

    var matchesAll: Bool {
        tokens.isEmpty
    }

    func matches(name: String, email: String) -> Bool {
        guard !matchesAll else {
            return true
        }
        return normalizeIdentityToken(name).map(tokens.contains) == true
            || normalizeIdentityToken(email).map(tokens.contains) == true
    }
}

private func parseGitLogCounts(_ output: String, matcher: GitIdentityMatcher) -> [String: Int] {
    var counts = [String: Int]()

    if matcher.matchesAll {
        for line in output.split(whereSeparator: \.isNewline) {
            let dateKey = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !dateKey.isEmpty else {
                continue
            }
            counts[dateKey, default: 0] += 1
        }
        return counts
    }

    for line in output.split(whereSeparator: \.isNewline) {
        let components = line.split(separator: "\u{1f}", omittingEmptySubsequences: false)
        guard components.count == 3 else {
            continue
        }
        let name = String(components[0])
        let email = String(components[1])
        let dateKey = String(components[2]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dateKey.isEmpty, matcher.matches(name: name, email: email) else {
            continue
        }
        counts[dateKey, default: 0] += 1
    }

    return counts
}

private func normalizeIdentityToken(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }
    return trimmed.lowercased()
}
