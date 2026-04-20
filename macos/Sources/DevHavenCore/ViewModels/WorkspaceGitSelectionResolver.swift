import Foundation

struct WorkspaceGitRepositorySelection: Equatable {
    let familyID: String
    let executionPath: String
}

@MainActor
final class WorkspaceGitSelectionResolver {
    private let normalizePath: @MainActor (String) -> String
    private let rootProjectForPath: @MainActor (String) -> Project?
    private let activeProjectPath: @MainActor () -> String?
    private let openWorkspaceSessions: @MainActor () -> [OpenWorkspaceSessionState]
    private let currentBranchByProjectPath: @MainActor () -> [String: String]
    private let storedFamilyID: @MainActor (String) -> String?
    private let storedExecutionPath: @MainActor (String) -> String?
    private let resolveDisplayProject: @MainActor (String, String?) -> Project?
    private let liveRootRepositoryPath: @MainActor (String) -> String?

    init(
        normalizePath: @escaping @MainActor (String) -> String,
        rootProjectForPath: @escaping @MainActor (String) -> Project?,
        activeProjectPath: @escaping @MainActor () -> String?,
        openWorkspaceSessions: @escaping @MainActor () -> [OpenWorkspaceSessionState],
        currentBranchByProjectPath: @escaping @MainActor () -> [String: String],
        storedFamilyID: @escaping @MainActor (String) -> String?,
        storedExecutionPath: @escaping @MainActor (String) -> String?,
        resolveDisplayProject: @escaping @MainActor (String, String?) -> Project?,
        liveRootRepositoryPath: @escaping @MainActor (String) -> String?
    ) {
        self.normalizePath = normalizePath
        self.rootProjectForPath = rootProjectForPath
        self.activeProjectPath = activeProjectPath
        self.openWorkspaceSessions = openWorkspaceSessions
        self.currentBranchByProjectPath = currentBranchByProjectPath
        self.storedFamilyID = storedFamilyID
        self.storedExecutionPath = storedExecutionPath
        self.resolveDisplayProject = resolveDisplayProject
        self.liveRootRepositoryPath = liveRootRepositoryPath
    }

    func selectionSnapshot(for rootProjectPath: String) -> WorkspaceGitSelectionSnapshot? {
        let normalizedRootProjectPath = normalizePath(rootProjectPath)
        guard !normalizedRootProjectPath.isEmpty else {
            return nil
        }

        if let repositoryPath = rootRepositoryPath(for: normalizedRootProjectPath) {
            let rootProject = rootProjectForPath(normalizedRootProjectPath)
            let executionContexts = workspaceGitExecutionContexts(
                rootProjectPath: repositoryPath,
                rootProjectName: rootProject?.name,
                persistedWorktrees: rootProject?.worktrees ?? []
            )
            let preferredExecutionPath = preferredWorkspaceGitExecutionPath(
                for: repositoryPath,
                allowedPaths: Set(executionContexts.map(\.path))
            )
            let repositoryDisplayName = {
                if let name = rootProject?.name, !name.isEmpty {
                    return name
                }
                let lastComponent = lastPathComponent(repositoryPath)
                return lastComponent.isEmpty ? repositoryPath : lastComponent
            }()
            let family = WorkspaceGitRepositoryFamilyContext(
                id: repositoryPath,
                displayName: repositoryDisplayName,
                repositoryPath: repositoryPath,
                preferredExecutionPath: preferredExecutionPath,
                members: executionContexts
            )
            let gitContext = WorkspaceGitRepositoryContext(
                rootProjectPath: repositoryPath,
                repositoryPath: repositoryPath,
                repositoryFamilies: [family],
                selectedRepositoryFamilyID: family.id
            )
            let commitContext = WorkspaceCommitRepositoryContext(
                rootProjectPath: repositoryPath,
                repositoryPath: repositoryPath,
                executionPath: preferredExecutionPath,
                repositoryFamilies: [family],
                selectedRepositoryFamilyID: family.id
            )
            return WorkspaceGitSelectionSnapshot(
                gitContext: gitContext,
                commitContext: commitContext
            )
        }

        let repositoryFamilies = discoverWorkspaceGitRepositoryFamilies(in: normalizedRootProjectPath)
        guard !repositoryFamilies.isEmpty else {
            return nil
        }

        let selectedFamilyID = resolveSelectedWorkspaceGitRepositoryFamilyID(
            rootProjectPath: normalizedRootProjectPath,
            families: repositoryFamilies
        )
        guard let selectedFamily = repositoryFamilies.first(where: { $0.id == selectedFamilyID }) ?? repositoryFamilies.first else {
            return nil
        }
        let selectedExecutionPath = resolveSelectedWorkspaceGitExecutionPath(
            rootProjectPath: normalizedRootProjectPath,
            family: selectedFamily
        )
        let gitContext = WorkspaceGitRepositoryContext(
            rootProjectPath: normalizedRootProjectPath,
            repositoryPath: selectedFamily.repositoryPath,
            repositoryFamilies: repositoryFamilies,
            selectedRepositoryFamilyID: selectedFamily.id
        )
        let commitContext = WorkspaceCommitRepositoryContext(
            rootProjectPath: normalizedRootProjectPath,
            repositoryPath: selectedFamily.repositoryPath,
            executionPath: selectedExecutionPath,
            repositoryFamilies: repositoryFamilies,
            selectedRepositoryFamilyID: selectedFamily.id
        )
        return WorkspaceGitSelectionSnapshot(
            gitContext: gitContext,
            commitContext: commitContext
        )
    }

    func selectionForProjectTreePath(
        _ selectedPath: String?,
        in rootProjectPath: String
    ) -> WorkspaceGitRepositorySelection? {
        let normalizedRootProjectPath = normalizePath(rootProjectPath)
        guard !normalizedRootProjectPath.isEmpty,
              let selectedPath = selectedPath
        else {
            return nil
        }

        let repositoryFamilies = discoverWorkspaceGitRepositoryFamilies(in: normalizedRootProjectPath)
        guard !repositoryFamilies.isEmpty else {
            return nil
        }
        return matchingWorkspaceGitFamilySelection(
            for: selectedPath,
            in: repositoryFamilies
        )
    }

    private func rootRepositoryPath(for rootProjectPath: String) -> String? {
        let normalizedRootProjectPath = normalizePath(rootProjectPath)
        guard !normalizedRootProjectPath.isEmpty else {
            return nil
        }
        if let rootProject = rootProjectForPath(normalizedRootProjectPath),
           rootProject.isGitRepository {
            return rootProject.path
        }
        return liveRootRepositoryPath(normalizedRootProjectPath)
    }

    private func preferredWorkspaceGitExecutionPath(
        for rootProjectPath: String,
        allowedPaths: Set<String>? = nil
    ) -> String {
        let normalizedRootProjectPath = normalizePath(rootProjectPath)
        if let storedExecutionPath = storedExecutionPath(normalizedRootProjectPath),
           allowedPaths?.contains(storedExecutionPath) != false {
            return storedExecutionPath
        }
        if let activeProjectPath = activeProjectPath().map(normalizePath),
           openWorkspaceSessions().contains(where: {
               $0.projectPath == activeProjectPath && $0.rootProjectPath == rootProjectPath
           }),
           allowedPaths?.contains(activeProjectPath) != false
        {
            return activeProjectPath
        }
        return rootProjectPath
    }

    private func workspaceGitExecutionContexts(
        rootProjectPath: String,
        rootProjectName: String?,
        persistedWorktrees: [ProjectWorktree]
    ) -> [WorkspaceGitWorktreeContext] {
        let displayName = {
            if let rootProjectName, !rootProjectName.isEmpty {
                return rootProjectName
            }
            let lastComponent = lastPathComponent(rootProjectPath)
            return lastComponent.isEmpty ? rootProjectPath : lastComponent
        }()
        let branchesByProjectPath = currentBranchByProjectPath()
        let rootContext = WorkspaceGitWorktreeContext(
            path: rootProjectPath,
            displayName: displayName,
            branchName: branchesByProjectPath[rootProjectPath],
            isRootProject: true
        )
        let worktreeContexts = persistedWorktrees.map { worktree in
            WorkspaceGitWorktreeContext(
                path: worktree.path,
                displayName: worktree.name,
                branchName: worktree.branch,
                isRootProject: false
            )
        }
        return [rootContext] + worktreeContexts
    }

    private func discoverWorkspaceGitRepositoryFamilies(in rootProjectPath: String) -> [WorkspaceGitRepositoryFamilyContext] {
        let normalizedRootProjectPath = normalizePath(rootProjectPath)
        guard !normalizedRootProjectPath.isEmpty else {
            return []
        }

        let candidates = workspaceGitRepositoryCandidates(in: normalizedRootProjectPath)
        var discoveredRepositories: [DiscoveredWorkspaceGitRepository] = []
        discoveredRepositories.reserveCapacity(candidates.count)
        let branchesByProjectPath = currentBranchByProjectPath()

        for candidate in candidates {
            let normalizedCandidatePath = normalizePath(candidate.path)
            guard !normalizedCandidatePath.isEmpty,
                  normalizedCandidatePath != normalizedRootProjectPath,
                  directoryExists(at: normalizedCandidatePath)
            else {
                continue
            }
            guard let gitDirectories = workspaceGitDirectoriesForCandidate(at: normalizedCandidatePath) else {
                continue
            }

            let branchName = branchesByProjectPath[normalizedCandidatePath]
            discoveredRepositories.append(
                DiscoveredWorkspaceGitRepository(
                    path: normalizedCandidatePath,
                    displayName: candidate.displayName,
                    branchName: branchName,
                    commonGitDirectory: gitDirectories.commonGitDirectory,
                    isRootRepository: gitDirectories.gitDirectory == gitDirectories.commonGitDirectory
                )
            )
        }

        let groupedRepositories = Dictionary(grouping: discoveredRepositories, by: \.commonGitDirectory)
        let activeProjectPath = activeProjectPath().map(normalizePath)
        let storedExecutionPath = storedExecutionPath(normalizedRootProjectPath)

        return groupedRepositories.values.compactMap { repositories in
            let members = repositories
                .sorted { discoveredWorkspaceRepositoryOrder(lhs: $0, rhs: $1) }
                .map { repository in
                    WorkspaceGitWorktreeContext(
                        path: repository.path,
                        displayName: repository.displayName,
                        branchName: repository.branchName,
                        isRootProject: repository.isRootRepository
                    )
                }
            guard !members.isEmpty else {
                return nil
            }

            let repositoryPath = members.first(where: \.isRootProject)?.path ?? members[0].path
            let familyDisplayName = members.first(where: \.isRootProject)?.displayName ?? members[0].displayName
            let preferredExecutionPath = resolvePreferredWorkspaceGitExecutionPath(
                members: members,
                storedExecutionPath: storedExecutionPath,
                activeProjectPath: activeProjectPath,
                fallbackPath: repositoryPath
            )

            return WorkspaceGitRepositoryFamilyContext(
                id: repositories[0].commonGitDirectory,
                displayName: familyDisplayName,
                repositoryPath: repositoryPath,
                preferredExecutionPath: preferredExecutionPath,
                members: members
            )
        }
        .sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private func workspaceGitRepositoryCandidates(in rootProjectPath: String) -> [WorkspaceGitRepositoryCandidate] {
        let rootURL = URL(fileURLWithPath: rootProjectPath, isDirectory: true)
        let fileManager = FileManager.default
        var candidates = [WorkspaceGitRepositoryCandidate]()
        var seenPaths = Set<String>()

        if let childURLs = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) {
            for childURL in childURLs {
                let normalizedPath = normalizePath(childURL.path)
                guard !normalizedPath.isEmpty,
                      seenPaths.insert(normalizedPath).inserted,
                      directoryExists(at: normalizedPath)
                else {
                    continue
                }
                candidates.append(
                    WorkspaceGitRepositoryCandidate(
                        path: childURL.path,
                        displayName: childURL.lastPathComponent
                    )
                )
            }
        }

        for session in openWorkspaceSessions() where
            !session.isQuickTerminal &&
            normalizePath(session.rootProjectPath) == rootProjectPath
        {
            let normalizedPath = normalizePath(session.projectPath)
            guard normalizedPath != rootProjectPath,
                  seenPaths.insert(normalizedPath).inserted
            else {
                continue
            }
            let displayName = resolveDisplayProject(
                session.projectPath,
                session.rootProjectPath
            )?.name ?? lastPathComponent(session.projectPath)
            candidates.append(
                WorkspaceGitRepositoryCandidate(
                    path: session.projectPath,
                    displayName: displayName
                )
            )
        }

        return candidates
    }

    private func workspaceGitDirectoriesForCandidate(
        at path: String
    ) -> (gitDirectory: String, commonGitDirectory: String)? {
        let repositoryURL = URL(fileURLWithPath: path, isDirectory: true)
        let markerURL = repositoryURL.appending(path: ".git")
        var isDirectory: ObjCBool = false
        let gitDirectory: String

        if FileManager.default.fileExists(atPath: markerURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            gitDirectory = normalizePath(markerURL.standardizedFileURL.path)
        } else if FileManager.default.fileExists(atPath: markerURL.path),
                  let content = try? String(contentsOf: markerURL, encoding: .utf8),
                  let parsedGitDirectory = workspaceGitDirectoryFromDotGitFile(
                    content,
                    repositoryPath: path
                  ) {
            gitDirectory = normalizePath(parsedGitDirectory)
        } else {
            return nil
        }

        guard directoryExists(at: gitDirectory) else {
            return nil
        }
        return (
            gitDirectory: gitDirectory,
            commonGitDirectory: workspaceCommonGitDirectory(forGitDirectory: gitDirectory)
        )
    }

    private func workspaceCommonGitDirectory(forGitDirectory gitDirectory: String) -> String {
        let gitDirectoryURL = URL(fileURLWithPath: gitDirectory, isDirectory: true)
        let commonDirURL = gitDirectoryURL.appending(path: "commondir")

        if let content = try? String(contentsOf: commonDirURL, encoding: .utf8),
           let firstLine = content.split(whereSeparator: \.isNewline).first {
            let rawPath = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if !rawPath.isEmpty {
                let resolvedURL = rawPath.hasPrefix("/")
                    ? URL(fileURLWithPath: rawPath)
                    : gitDirectoryURL.appending(path: rawPath)
                return normalizePath(resolvedURL.standardizedFileURL.path)
            }
        }

        let components = gitDirectoryURL.standardizedFileURL.pathComponents
        if let worktreesIndex = components.lastIndex(of: "worktrees"),
           worktreesIndex > 0 {
            return normalizePath(
                NSString.path(withComponents: Array(components.prefix(upTo: worktreesIndex)))
            )
        }

        return normalizePath(gitDirectory)
    }

    private func workspaceGitDirectoryFromDotGitFile(
        _ content: String,
        repositoryPath: String
    ) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let markerRange = trimmed.range(of: "gitdir:") else {
            return nil
        }

        let rawPath = trimmed[markerRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawPath.isEmpty else {
            return nil
        }
        if rawPath.hasPrefix("/") {
            return URL(fileURLWithPath: rawPath).standardizedFileURL.path
        }
        return URL(fileURLWithPath: repositoryPath, isDirectory: true)
            .appending(path: rawPath)
            .standardizedFileURL
            .path
    }

    private func resolveSelectedWorkspaceGitRepositoryFamilyID(
        rootProjectPath: String,
        families: [WorkspaceGitRepositoryFamilyContext]
    ) -> String {
        let normalizedRootProjectPath = normalizePath(rootProjectPath)
        if let storedFamilyID = storedFamilyID(normalizedRootProjectPath),
           families.contains(where: { $0.id == storedFamilyID }) {
            return storedFamilyID
        }

        if let activeProjectPath = activeProjectPath().map(normalizePath),
           let activeFamily = families.first(where: { family in
               family.members.contains(where: { $0.path == activeProjectPath })
           }) {
            return activeFamily.id
        }

        return families[0].id
    }

    private func resolveSelectedWorkspaceGitExecutionPath(
        rootProjectPath: String,
        family: WorkspaceGitRepositoryFamilyContext
    ) -> String {
        let normalizedRootProjectPath = normalizePath(rootProjectPath)
        return resolvePreferredWorkspaceGitExecutionPath(
            members: family.members,
            storedExecutionPath: storedExecutionPath(normalizedRootProjectPath),
            activeProjectPath: activeProjectPath().map(normalizePath),
            fallbackPath: family.preferredExecutionPath
        )
    }

    private func resolvePreferredWorkspaceGitExecutionPath(
        members: [WorkspaceGitWorktreeContext],
        storedExecutionPath: String?,
        activeProjectPath: String?,
        fallbackPath: String
    ) -> String {
        if let storedExecutionPath,
           members.contains(where: { $0.path == storedExecutionPath }) {
            return storedExecutionPath
        }
        if let activeProjectPath,
           members.contains(where: { $0.path == activeProjectPath }) {
            return activeProjectPath
        }
        if members.contains(where: { $0.path == fallbackPath }) {
            return fallbackPath
        }
        return members[0].path
    }

    private func matchingWorkspaceGitFamilySelection(
        for selectedPath: String,
        in families: [WorkspaceGitRepositoryFamilyContext]
    ) -> WorkspaceGitRepositorySelection? {
        let normalizedSelectedPath = normalizePath(selectedPath)
        var bestMatch: (familyID: String, executionPath: String, score: Int)?

        for family in families {
            for member in family.members {
                let normalizedMemberPath = normalizePath(member.path)
                guard normalizedSelectedPath == normalizedMemberPath
                    || normalizedSelectedPath.hasPrefix(normalizedMemberPath + "/")
                else {
                    continue
                }
                let score = normalizedMemberPath.count
                if let bestMatch, bestMatch.score >= score {
                    continue
                }
                bestMatch = (family.id, member.path, score)
            }
        }

        return bestMatch.map {
            WorkspaceGitRepositorySelection(
                familyID: $0.familyID,
                executionPath: $0.executionPath
            )
        }
    }

    private func discoveredWorkspaceRepositoryOrder(
        lhs: DiscoveredWorkspaceGitRepository,
        rhs: DiscoveredWorkspaceGitRepository
    ) -> Bool {
        if lhs.isRootRepository != rhs.isRootRepository {
            return lhs.isRootRepository && !rhs.isRootRepository
        }
        return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
    }

    private func directoryExists(at path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func lastPathComponent(_ path: String) -> String {
        let lastComponent = (path as NSString).lastPathComponent
        return lastComponent.isEmpty ? path : lastComponent
    }
}

private struct WorkspaceGitRepositoryCandidate {
    let path: String
    let displayName: String
}

private struct DiscoveredWorkspaceGitRepository {
    let path: String
    let displayName: String
    let branchName: String?
    let commonGitDirectory: String
    let isRootRepository: Bool
}
