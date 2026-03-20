import Foundation

private let gitLogPrettyWithIdentity = "--pretty=format:%an\u{1f}%ae\u{1f}%cd"
private let gitLogPrettyDateOnly = "--pretty=format:%cd"
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

    let prettyArgument = matcher.matchesAll ? gitLogPrettyDateOnly : gitLogPrettyWithIdentity
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "log", prettyArgument, "--date=short"]
    process.currentDirectoryURL = repoURL

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    do {
        try process.run()
    } catch {
        return GitDailyRefreshResult(path: path, gitDaily: nil, error: "执行 git log 失败: \(error.localizedDescription)")
    }

    let deadline = Date().addingTimeInterval(gitLogTimeoutSeconds)
    while process.isRunning && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
    }

    if process.isRunning {
        process.terminate()
        process.waitUntilExit()
        return GitDailyRefreshResult(path: path, gitDaily: nil, error: "git log 超时（>\(Int(gitLogTimeoutSeconds)) 秒）")
    }

    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "未知错误"
        return GitDailyRefreshResult(path: path, gitDaily: nil, error: "git log 返回失败: \(message)")
    }

    let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let counts = parseGitLogCounts(output, matcher: matcher)
    guard !counts.isEmpty else {
        return GitDailyRefreshResult(path: path, gitDaily: nil, error: nil)
    }

    let gitDaily = counts
        .sorted(by: { $0.key < $1.key })
        .map { "\($0.key):\($0.value)" }
        .joined(separator: ",")
    return GitDailyRefreshResult(path: path, gitDaily: gitDaily, error: nil)
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
