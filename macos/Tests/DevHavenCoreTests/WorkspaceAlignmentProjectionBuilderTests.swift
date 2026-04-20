import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceAlignmentProjectionBuilderTests: XCTestCase {
    func testAlignedMemberUsesWorktreeOpenTargetAndWorktreeBranchLabel() {
        let projectPath = "/tmp/repo"
        let worktreePath = "/tmp/repo-feature-payment"
        let definition = WorkspaceAlignmentGroupDefinition(
            id: "group-1",
            name: "支付链路",
            targetBranch: "feature/payment",
            projectPaths: [projectPath]
        )
        let builder = makeBuilder(
            activeProjectPath: worktreePath,
            projectsByPath: [
                normalizeAlignmentProjectionTestPath(projectPath): makeProject(
                    id: "project-root",
                    name: "Repo",
                    path: projectPath,
                    worktrees: [
                        ProjectWorktree(
                            id: "worktree-payment",
                            name: "payment",
                            path: worktreePath,
                            branch: "feature/payment",
                            inheritConfig: true,
                            created: 0,
                            updatedAt: 0
                        ),
                    ]
                ),
            ],
            currentBranches: [normalizeAlignmentProjectionTestPath(projectPath): "main"],
            aliasesByGroupID: [
                definition.id: [normalizeAlignmentProjectionTestPath(projectPath): "repo-main"],
            ],
            statusesByGroupAndProjectPath: [
                "\(definition.id)|\(normalizeAlignmentProjectionTestPath(projectPath))": .aligned,
            ]
        )

        let group = try? XCTUnwrap(builder.groups(definitions: [definition]).first)
        let member = try? XCTUnwrap(group?.members.first)

        XCTAssertEqual(group?.isActive, true)
        XCTAssertEqual(member?.alias, "repo-main")
        XCTAssertEqual(member?.openTarget, .worktree(rootProjectPath: projectPath, worktreePath: worktreePath))
        XCTAssertEqual(member?.branchLabel, "feature/payment")
        XCTAssertEqual(member?.isActive, true)
    }

    func testUnalignedMemberUsesProjectOpenTargetAndCurrentBranchLabel() {
        let projectPath = "/tmp/repo"
        let definition = WorkspaceAlignmentGroupDefinition(
            id: "group-1",
            name: "支付链路",
            targetBranch: "feature/payment",
            projectPaths: [projectPath]
        )
        let builder = makeBuilder(
            activeProjectPath: projectPath,
            projectsByPath: [
                normalizeAlignmentProjectionTestPath(projectPath): makeProject(
                    id: "project-root",
                    name: "Repo",
                    path: projectPath
                ),
            ],
            currentBranches: [normalizeAlignmentProjectionTestPath(projectPath): "develop"],
            statusesByGroupAndProjectPath: [
                "\(definition.id)|\(normalizeAlignmentProjectionTestPath(projectPath))": .currentBranch("develop"),
            ]
        )

        let member = try? XCTUnwrap(builder.groups(definitions: [definition]).first?.members.first)

        XCTAssertEqual(member?.openTarget, .project(projectPath: normalizeAlignmentProjectionTestPath(projectPath)))
        XCTAssertEqual(member?.branchLabel, "develop")
        XCTAssertEqual(member?.isActive, false)
    }

    func testOwnedGroupMarksOnlyMatchingGroupMemberActive() {
        let projectPath = "/tmp/repo"
        let definitionA = WorkspaceAlignmentGroupDefinition(
            id: "group-a",
            name: "支付链路",
            targetBranch: "main",
            projectPaths: [projectPath]
        )
        let definitionB = WorkspaceAlignmentGroupDefinition(
            id: "group-b",
            name: "结算链路",
            targetBranch: "main",
            projectPaths: [projectPath]
        )
        let normalizedProjectPath = normalizeAlignmentProjectionTestPath(projectPath)
        let builder = makeBuilder(
            activeProjectPath: projectPath,
            activeWorkspaceOwnedGroupID: definitionA.id,
            projectsByPath: [
                normalizedProjectPath: makeProject(
                    id: "project-root",
                    name: "Repo",
                    path: projectPath
                ),
            ],
            currentBranches: [normalizedProjectPath: "main"],
            statusesByGroupAndProjectPath: [
                "\(definitionA.id)|\(normalizedProjectPath)": .aligned,
                "\(definitionB.id)|\(normalizedProjectPath)": .aligned,
            ]
        )

        let groups = builder.groups(definitions: [definitionA, definitionB])
        let groupA = groups.first { $0.id == definitionA.id }
        let groupB = groups.first { $0.id == definitionB.id }

        XCTAssertEqual(groupA?.isActive, true)
        XCTAssertEqual(groupA?.members.first?.isActive, true)
        XCTAssertEqual(groupB?.isActive, false)
        XCTAssertEqual(groupB?.members.first?.isActive, false)
    }

    func testRootWorkspaceGroupIDMarksGroupActiveWithoutActiveMember() {
        let projectPath = "/tmp/repo"
        let definition = WorkspaceAlignmentGroupDefinition(
            id: "group-root",
            name: "支付链路",
            targetBranch: "main",
            projectPaths: [projectPath]
        )
        let builder = makeBuilder(
            activeWorkspaceRootGroupID: definition.id,
            projectsByPath: [
                normalizeAlignmentProjectionTestPath(projectPath): makeProject(
                    id: "project-root",
                    name: "Repo",
                    path: projectPath
                ),
            ],
            currentBranches: [normalizeAlignmentProjectionTestPath(projectPath): "main"],
            statusesByGroupAndProjectPath: [
                "\(definition.id)|\(normalizeAlignmentProjectionTestPath(projectPath))": .aligned,
            ]
        )

        let group = try? XCTUnwrap(builder.groups(definitions: [definition]).first)

        XCTAssertEqual(group?.isActive, true)
        XCTAssertEqual(group?.members.first?.isActive, false)
    }

    private func makeBuilder(
        activeProjectPath: String? = nil,
        activeWorkspaceRootGroupID: String? = nil,
        activeWorkspaceOwnedGroupID: String? = nil,
        projectsByPath: [String: Project] = [:],
        currentBranches: [String: String] = [:],
        aliasesByGroupID: [String: [String: String]] = [:],
        statusesByGroupAndProjectPath: [String: WorkspaceAlignmentMemberStatus] = [:]
    ) -> WorkspaceAlignmentProjectionBuilder {
        WorkspaceAlignmentProjectionBuilder(
            normalizePath: { normalizeAlignmentProjectionTestPath($0) },
            activeProjectPath: { activeProjectPath },
            activeWorkspaceRootGroupID: { activeWorkspaceRootGroupID },
            activeWorkspaceOwnedGroupID: { activeWorkspaceOwnedGroupID },
            projectsByNormalizedPath: { projectsByPath },
            currentBranchByProjectPath: { currentBranches },
            aliasesForGroup: { definition, _ in
                aliasesByGroupID[definition.id] ?? [:]
            },
            statusForMember: { groupID, projectPath in
                statusesByGroupAndProjectPath["\(groupID)|\(projectPath)"]
            }
        )
    }

    private func makeProject(
        id: String,
        name: String,
        path: String,
        worktrees: [ProjectWorktree] = []
    ) -> Project {
        Project(
            id: id,
            name: name,
            path: path,
            tags: [],
            runConfigurations: [],
            worktrees: worktrees,
            mtime: 0,
            size: 0,
            checksum: "",
            gitCommits: 0,
            gitLastCommit: 0,
            created: 0,
            checked: 0
        )
    }
}

private func normalizeAlignmentProjectionTestPath(_ path: String) -> String {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return ""
    }
    var normalized = trimmed.replacingOccurrences(of: "\\", with: "/")
    while normalized.count > 1 && normalized.hasSuffix("/") {
        normalized.removeLast()
    }
    return normalized
}
