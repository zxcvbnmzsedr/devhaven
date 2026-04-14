import Foundation

public struct WorkspaceGitHubRemoteResolver: Sendable {
    private let gitService: NativeGitRepositoryService

    public init(gitService: NativeGitRepositoryService = NativeGitRepositoryService()) {
        self.gitService = gitService
    }

    public func resolveRepositoryContext(
        rootProjectPath: String,
        repositoryPath: String,
        preferredRemoteName: String? = nil
    ) throws -> WorkspaceGitHubRepositoryContext {
        let remotes = try gitService.loadRemotes(at: repositoryPath)
        guard !remotes.isEmpty else {
            throw WorkspaceGitHubCommandError.unsupportedRemote("当前仓库未配置 remote，无法解析 GitHub 仓库")
        }

        let preferredName = preferredRemoteName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let orderedRemotes = remotes.sorted { lhs, rhs in
            if lhs.name == preferredName { return true }
            if rhs.name == preferredName { return false }
            if lhs.name == "origin" { return true }
            if rhs.name == "origin" { return false }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        for remote in orderedRemotes {
            guard let remoteURL = remote.fetchURL ?? remote.pushURL,
                  let parsed = parseRemote(remoteURL)
            else {
                continue
            }
            return WorkspaceGitHubRepositoryContext(
                rootProjectPath: rootProjectPath,
                repositoryPath: repositoryPath,
                remoteName: remote.name,
                remoteURL: remoteURL,
                host: parsed.host,
                owner: parsed.owner,
                name: parsed.repository
            )
        }

        throw WorkspaceGitHubCommandError.unsupportedRemote("未找到可解析的 GitHub remote，请确认仓库 remote 指向 GitHub")
    }

    private func parseRemote(_ rawRemoteURL: String) -> ParsedRemote? {
        let trimmedURL = rawRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            return nil
        }

        if let url = URL(string: trimmedURL), let host = url.host {
            let normalizedHost = normalizeHost(host)
            let pathComponents = url.path
                .split(separator: "/")
                .map(String.init)
                .filter { !$0.isEmpty }
            guard pathComponents.count >= 2 else {
                return nil
            }
            let owner = pathComponents[0]
            let repository = sanitizeRepositoryName(pathComponents[1])
            guard !owner.isEmpty, !repository.isEmpty else {
                return nil
            }
            return ParsedRemote(host: normalizedHost, owner: owner, repository: repository)
        }

        let pattern = #"^(?:[^@]+@)?([^:\/]+):(.+)$"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(location: 0, length: trimmedURL.utf16.count)
        guard let match = expression.firstMatch(in: trimmedURL, range: range),
              match.numberOfRanges == 3,
              let hostRange = Range(match.range(at: 1), in: trimmedURL),
              let pathRange = Range(match.range(at: 2), in: trimmedURL)
        else {
            return nil
        }

        let host = normalizeHost(String(trimmedURL[hostRange]))
        let path = String(trimmedURL[pathRange])
        let pathComponents = path
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard pathComponents.count >= 2 else {
            return nil
        }
        let owner = pathComponents[0]
        let repository = sanitizeRepositoryName(pathComponents[1])
        guard !owner.isEmpty, !repository.isEmpty else {
            return nil
        }
        return ParsedRemote(host: host, owner: owner, repository: repository)
    }

    private func sanitizeRepositoryName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix(".git") {
            return String(trimmed.dropLast(4))
        }
        return trimmed
    }

    private func normalizeHost(_ host: String) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch trimmed {
        case "ssh.github.com":
            return "github.com"
        default:
            return trimmed
        }
    }
}

private struct ParsedRemote: Equatable, Sendable {
    var host: String
    var owner: String
    var repository: String
}
