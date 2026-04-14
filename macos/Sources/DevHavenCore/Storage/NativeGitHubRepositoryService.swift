import Foundation

public struct NativeGitHubRepositoryService: Sendable {
    private let runner: NativeGitHubCommandRunner
    private let remoteResolver: WorkspaceGitHubRemoteResolver

    public init(
        runner: NativeGitHubCommandRunner = NativeGitHubCommandRunner(),
        remoteResolver: WorkspaceGitHubRemoteResolver = WorkspaceGitHubRemoteResolver()
    ) {
        self.runner = runner
        self.remoteResolver = remoteResolver
    }

    public func resolveRepositoryContext(
        rootProjectPath: String,
        repositoryPath: String,
        preferredRemoteName: String? = nil
    ) throws -> WorkspaceGitHubRepositoryContext {
        try remoteResolver.resolveRepositoryContext(
            rootProjectPath: rootProjectPath,
            repositoryPath: repositoryPath,
            preferredRemoteName: preferredRemoteName
        )
    }

    public func checkAuthStatus(host: String) throws -> WorkspaceGitHubAuthStatus {
        let response: GitHubAuthStatusResponse = try runJSON(
            GitHubAuthStatusResponse.self,
            arguments: [
                "auth",
                "status",
                "--active",
                "--hostname",
                host,
                "--json",
                "hosts",
            ],
            at: FileManager.default.homeDirectoryForCurrentUser.path
        )

        guard let account = response.hosts[host]?.first else {
            return WorkspaceGitHubAuthStatus(host: host, state: .unauthenticated)
        }

        let state = account.state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "success"
            ? WorkspaceGitHubAuthState.authenticated
            : WorkspaceGitHubAuthState.unauthenticated
        let scopes = account.scopes?
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        return WorkspaceGitHubAuthStatus(
            host: host,
            state: state,
            activeLogin: account.login,
            gitProtocol: account.gitProtocol,
            tokenSource: account.tokenSource,
            scopes: scopes
        )
    }

    public func loadPulls(
        in context: WorkspaceGitHubRepositoryContext,
        filter: WorkspaceGitHubPullFilter = WorkspaceGitHubPullFilter()
    ) throws -> [WorkspaceGitHubPullSummary] {
        var arguments = [
            "pr",
            "list",
            "-R",
            context.repoSelector,
            "--limit",
            String(filter.limit),
            "--state",
            filter.state.ghArgument,
            "--json",
            "id,number,title,state,isDraft,author,assignees,labels,comments,reviewDecision,createdAt,updatedAt,url,headRefName,baseRefName",
        ]

        if filter.draftOnly {
            arguments.append("--draft")
        }
        if let author = filter.normalizedAuthor {
            arguments += ["--author", author]
        }
        if let assignee = filter.normalizedAssignee {
            arguments += ["--assignee", assignee]
        }
        if let baseBranch = filter.normalizedBaseBranch {
            arguments += ["--base", baseBranch]
        }
        if let headBranch = filter.normalizedHeadBranch {
            arguments += ["--head", headBranch]
        }
        for label in filter.normalizedLabels {
            arguments += ["--label", label]
        }
        if let searchText = filter.normalizedSearchText {
            arguments += ["--search", searchText]
        }

        let payload: [PullListDTO] = try runJSON([PullListDTO].self, arguments: arguments, at: context.repositoryPath)
        return payload.map { dto in
            WorkspaceGitHubPullSummary(
                id: dto.id,
                number: dto.number,
                title: dto.title,
                state: dto.state,
                isDraft: dto.isDraft,
                author: dto.author,
                assignees: dto.assignees ?? [],
                labels: dto.labels,
                commentsCount: dto.comments?.count ?? 0,
                reviewDecision: dto.reviewDecision,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt,
                url: dto.url,
                headRefName: dto.headRefName,
                baseRefName: dto.baseRefName
            )
        }
    }

    public func loadIssues(
        in context: WorkspaceGitHubRepositoryContext,
        filter: WorkspaceGitHubIssueFilter = WorkspaceGitHubIssueFilter()
    ) throws -> [WorkspaceGitHubIssueSummary] {
        var arguments = [
            "issue",
            "list",
            "-R",
            context.repoSelector,
            "--limit",
            String(filter.limit),
            "--state",
            filter.state.ghArgument,
            "--json",
            "id,number,title,state,stateReason,author,assignees,labels,comments,createdAt,updatedAt,url,milestone",
        ]

        if let author = filter.normalizedAuthor {
            arguments += ["--author", author]
        }
        if let assignee = filter.normalizedAssignee {
            arguments += ["--assignee", assignee]
        }
        if let milestone = filter.normalizedMilestone {
            arguments += ["--milestone", milestone]
        }
        for label in filter.normalizedLabels {
            arguments += ["--label", label]
        }
        if let searchText = filter.normalizedSearchText {
            arguments += ["--search", searchText]
        }

        let payload: [IssueListDTO] = try runJSON([IssueListDTO].self, arguments: arguments, at: context.repositoryPath)
        return payload.map { dto in
            WorkspaceGitHubIssueSummary(
                id: dto.id,
                number: dto.number,
                title: dto.title,
                state: dto.state,
                stateReason: dto.stateReason ?? .none,
                author: dto.author,
                assignees: dto.assignees ?? [],
                labels: dto.labels,
                commentsCount: dto.comments?.count ?? 0,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt,
                url: dto.url
            )
        }
    }

    public func loadReviewRequests(
        in context: WorkspaceGitHubRepositoryContext,
        filter: WorkspaceGitHubReviewFilter = WorkspaceGitHubReviewFilter()
    ) throws -> [WorkspaceGitHubReviewRequestSummary] {
        var arguments = ["search", "prs"]
        if let searchText = filter.normalizedSearchText {
            arguments.append(searchText)
        }
        arguments += [
            "--repo",
            context.repoSelector,
            "--state",
            filter.state.ghArgument,
            "--limit",
            String(filter.limit),
            "--json",
            "id,number,title,state,isDraft,author,labels,commentsCount,createdAt,updatedAt,url",
        ]

        switch filter.scope {
        case .requestedToMe:
            arguments += ["--review-requested", "@me"]
        case .involvingMe:
            arguments += ["--involves", "@me"]
        }

        if let author = filter.normalizedAuthor {
            arguments += ["--author", author]
        }
        for label in filter.normalizedLabels {
            arguments += ["--label", label]
        }

        let payload: [ReviewSearchDTO] = try runJSON([ReviewSearchDTO].self, arguments: arguments, at: context.repositoryPath)
        return payload.map { dto in
            WorkspaceGitHubReviewRequestSummary(
                id: dto.id,
                number: dto.number,
                title: dto.title,
                state: dto.state,
                isDraft: dto.isDraft,
                author: dto.author,
                labels: dto.labels,
                commentsCount: dto.commentsCount,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt,
                url: dto.url
            )
        }
    }

    public func loadPullDetail(
        in context: WorkspaceGitHubRepositoryContext,
        number: Int
    ) throws -> WorkspaceGitHubPullDetail {
        let payload: PullDetailDTO = try runJSON(
            PullDetailDTO.self,
            arguments: [
                "pr",
                "view",
                String(number),
                "-R",
                context.repoSelector,
                "--json",
                "id,number,title,state,isDraft,author,assignees,labels,reviewDecision,mergeStateStatus,milestone,body,createdAt,updatedAt,mergedAt,mergedBy,url,headRefName,baseRefName,changedFiles,comments,commits",
            ],
            at: context.repositoryPath
        )

        return WorkspaceGitHubPullDetail(
            id: payload.id,
            number: payload.number,
            title: payload.title,
            state: payload.state,
            isDraft: payload.isDraft,
            author: payload.author,
            assignees: payload.assignees ?? [],
            labels: payload.labels,
            reviewDecision: payload.reviewDecision,
            mergeStateStatus: payload.mergeStateStatus,
            milestone: payload.milestone,
            body: payload.body?.nilIfEmpty,
            createdAt: payload.createdAt,
            updatedAt: payload.updatedAt,
            mergedAt: payload.mergedAt,
            mergedBy: payload.mergedBy,
            url: payload.url,
            headRefName: payload.headRefName,
            baseRefName: payload.baseRefName,
            changedFiles: payload.changedFiles,
            comments: payload.comments?.map(\.model) ?? [],
            commits: payload.commits ?? []
        )
    }

    public func loadIssueDetail(
        in context: WorkspaceGitHubRepositoryContext,
        number: Int
    ) throws -> WorkspaceGitHubIssueDetail {
        let payload: IssueDetailDTO = try runJSON(
            IssueDetailDTO.self,
            arguments: [
                "issue",
                "view",
                String(number),
                "-R",
                context.repoSelector,
                "--json",
                "id,number,title,state,stateReason,author,assignees,labels,milestone,body,createdAt,updatedAt,closedAt,url,comments",
            ],
            at: context.repositoryPath
        )

        return WorkspaceGitHubIssueDetail(
            id: payload.id,
            number: payload.number,
            title: payload.title,
            state: payload.state,
            stateReason: payload.stateReason ?? .none,
            author: payload.author,
            assignees: payload.assignees ?? [],
            labels: payload.labels,
            milestone: payload.milestone,
            body: payload.body?.nilIfEmpty,
            createdAt: payload.createdAt,
            updatedAt: payload.updatedAt,
            closedAt: payload.closedAt,
            url: payload.url,
            comments: payload.comments?.map(\.model) ?? []
        )
    }

    private func runJSON<T: Decodable>(
        _ type: T.Type,
        arguments: [String],
        at repositoryPath: String
    ) throws -> T {
        let result = try runner.runAllowingFailure(arguments: arguments, at: repositoryPath)
        guard result.isSuccess else {
            throw mapFailure(result)
        }
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            throw WorkspaceGitHubCommandError.parseFailure("GitHub 命令未返回可解析数据")
        }
        let data = Data(output.utf8)
        do {
            return try makeDecoder().decode(T.self, from: data)
        } catch {
            throw WorkspaceGitHubCommandError.parseFailure("GitHub 数据解析失败：\(error.localizedDescription)")
        }
    }

    private func mapFailure(_ result: NativeGitHubCommandRunner.Result) -> WorkspaceGitHubCommandError {
        let command = result.command.joined(separator: " ")
        let message = result.errorMessage
        let normalized = message.lowercased()
        if normalized.contains("not logged into")
            || normalized.contains("authenticate")
            || normalized.contains("gh auth login")
        {
            return .authRequired("GitHub CLI 未登录，请先执行 gh auth login")
        }
        if normalized.contains("could not resolve to a repository")
            || normalized.contains("no git remotes configured")
            || normalized.contains("none of the git remotes configured")
        {
            return .unsupportedRemote("当前仓库未能解析为 GitHub 仓库，请检查 remote 配置")
        }
        return .commandFailed(command: command, message: message)
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct GitHubAuthStatusResponse: Decodable {
    let hosts: [String: [GitHubAuthAccountDTO]]
}

private struct GitHubAuthAccountDTO: Decodable {
    let state: String
    let login: String?
    let tokenSource: String?
    let scopes: String?
    let gitProtocol: String?
}

private struct PullListDTO: Decodable {
    let id: String
    let number: Int
    let title: String
    let state: WorkspaceGitHubPullState
    let isDraft: Bool
    let author: WorkspaceGitHubActor?
    let assignees: [WorkspaceGitHubActor]?
    let labels: [WorkspaceGitHubLabel]
    let comments: [CommentCountDTO]?
    let reviewDecision: WorkspaceGitHubReviewDecision
    let createdAt: Date
    let updatedAt: Date
    let url: String
    let headRefName: String
    let baseRefName: String
}

private struct IssueListDTO: Decodable {
    let id: String
    let number: Int
    let title: String
    let state: WorkspaceGitHubIssueState
    let stateReason: WorkspaceGitHubIssueStateReason?
    let author: WorkspaceGitHubActor?
    let assignees: [WorkspaceGitHubActor]?
    let labels: [WorkspaceGitHubLabel]
    let comments: [CommentCountDTO]?
    let createdAt: Date
    let updatedAt: Date
    let url: String
    let milestone: WorkspaceGitHubMilestone?
}

private struct ReviewSearchDTO: Decodable {
    let id: String
    let number: Int
    let title: String
    let state: WorkspaceGitHubPullState
    let isDraft: Bool
    let author: WorkspaceGitHubActor?
    let labels: [WorkspaceGitHubLabel]
    let commentsCount: Int
    let createdAt: Date
    let updatedAt: Date
    let url: String
}

private struct PullDetailDTO: Decodable {
    let id: String
    let number: Int
    let title: String
    let state: WorkspaceGitHubPullState
    let isDraft: Bool
    let author: WorkspaceGitHubActor?
    let assignees: [WorkspaceGitHubActor]?
    let labels: [WorkspaceGitHubLabel]
    let reviewDecision: WorkspaceGitHubReviewDecision
    let mergeStateStatus: WorkspaceGitHubMergeStateStatus
    let milestone: WorkspaceGitHubMilestone?
    let body: String?
    let createdAt: Date
    let updatedAt: Date
    let mergedAt: Date?
    let mergedBy: WorkspaceGitHubActor?
    let url: String
    let headRefName: String
    let baseRefName: String
    let changedFiles: Int
    let comments: [CommentDTO]?
    let commits: [WorkspaceGitHubCommitSummary]?
}

private struct IssueDetailDTO: Decodable {
    let id: String
    let number: Int
    let title: String
    let state: WorkspaceGitHubIssueState
    let stateReason: WorkspaceGitHubIssueStateReason?
    let author: WorkspaceGitHubActor?
    let assignees: [WorkspaceGitHubActor]?
    let labels: [WorkspaceGitHubLabel]
    let milestone: WorkspaceGitHubMilestone?
    let body: String?
    let createdAt: Date
    let updatedAt: Date
    let closedAt: Date?
    let url: String
    let comments: [CommentDTO]?
}

private struct CommentCountDTO: Decodable {
    let id: String?
}

private struct CommentDTO: Decodable {
    let id: String
    let author: WorkspaceGitHubActor?
    let authorAssociation: String?
    let body: String
    let createdAt: Date
    let url: String

    var model: WorkspaceGitHubComment {
        WorkspaceGitHubComment(
            id: id,
            author: author,
            authorAssociation: authorAssociation,
            body: body,
            createdAt: createdAt,
            url: url
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
