import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceAlignmentDefinitionResolverTests: XCTestCase {
    func testValidateRejectsEmptyNameDuplicateNameAndMissingBranches() {
        let project = makeProject(name: "Repo", path: "/repo")
        let resolver = makeResolver(
            projects: [normalizeAlignmentDefinitionTestPath(project.path): project],
            existingDefinitions: [
                WorkspaceAlignmentGroupDefinition(id: "existing", name: "支付链路", targetBranch: "main")
            ]
        )

        XCTAssertThrowsError(
            try resolver.validate(
                WorkspaceAlignmentGroupDefinition(name: " ", targetBranch: "main").sanitized(),
                replacing: nil
            )
        ) { error in
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, "工作区名称不能为空")
        }
        XCTAssertThrowsError(
            try resolver.validate(
                WorkspaceAlignmentGroupDefinition(id: "new", name: "支付链路", targetBranch: "main").sanitized(),
                replacing: nil
            )
        ) { error in
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, "已存在同名工作区")
        }
        XCTAssertThrowsError(
            try resolver.validate(
                WorkspaceAlignmentGroupDefinition(
                    name: "缺目标分支",
                    targetBranch: "",
                    members: [
                        WorkspaceAlignmentMemberDefinition(projectPath: "/repo", targetBranch: "", specifiedBaseBranch: "origin/main")
                    ]
                ).sanitized(),
                replacing: nil
            )
        ) { error in
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, "请为 Repo 填写目标 branch")
        }
        XCTAssertThrowsError(
            try resolver.validate(
                WorkspaceAlignmentGroupDefinition(
                    name: "缺基线分支",
                    targetBranch: "feature/a",
                    members: [
                        WorkspaceAlignmentMemberDefinition(projectPath: "/repo", targetBranch: "feature/a", specifiedBaseBranch: nil)
                    ]
                ).sanitized(),
                replacing: nil
            )
        ) { error in
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, "请为 Repo 选择基线分支")
        }
    }

    func testAliasesNormalizePathsSanitizeNamesAndAvoidCaseInsensitiveDuplicates() {
        let resolver = makeResolver(
            projects: [
                "/repo-a": makeProject(name: "API Gateway", path: "/repo-a"),
                "/repo-b": makeProject(name: "API Gateway", path: "/repo-b"),
                "/repo-c": makeProject(name: "___", path: "/repo-c"),
            ]
        )

        let aliases = resolver.aliases(
            for: ["/repo-a/", "/repo-b", "/repo-c"],
            existing: ["/repo-a": "Main API", "/repo-b": "main-api"]
        )

        XCTAssertEqual(aliases["/repo-a"], "Main-API")
        XCTAssertEqual(aliases["/repo-b"], "main-api-2")
        XCTAssertEqual(aliases["/repo-c"], "member")
    }

    func testMemberDefinitionAndNormalizedMembersUseNormalizedPathSemantics() {
        let resolver = makeResolver()
        let members = resolver.normalizedMembers([
            WorkspaceAlignmentMemberDefinition(
                projectPath: " /repo-a/ ",
                targetBranch: " feature/a ",
                specifiedBaseBranch: " origin/main "
            ),
            WorkspaceAlignmentMemberDefinition(
                projectPath: "/repo-a",
                targetBranch: "feature/duplicate",
                specifiedBaseBranch: "origin/main"
            ),
            WorkspaceAlignmentMemberDefinition(projectPath: " ", targetBranch: "main"),
        ])
        let definition = WorkspaceAlignmentGroupDefinition(
            name: "测试",
            targetBranch: "feature/a",
            members: members
        )

        XCTAssertEqual(members.count, 1)
        XCTAssertEqual(members.first?.projectPath, "/repo-a")
        XCTAssertEqual(members.first?.targetBranch, "feature/a")
        XCTAssertEqual(members.first?.specifiedBaseBranch, "origin/main")
        XCTAssertEqual(
            resolver.memberDefinition(for: "/repo-a/", in: definition)?.targetBranch,
            "feature/a"
        )
    }

    private func makeResolver(
        projects: [String: Project] = [:],
        existingDefinitions: [WorkspaceAlignmentGroupDefinition] = []
    ) -> WorkspaceAlignmentDefinitionResolver {
        WorkspaceAlignmentDefinitionResolver(
            normalizePath: normalizeAlignmentDefinitionTestPath,
            normalizePathList: { paths in
                var seen = Set<String>()
                return paths
                    .map(normalizeAlignmentDefinitionTestPath)
                    .filter { !$0.isEmpty }
                    .filter { seen.insert($0).inserted }
            },
            pathLastComponent: { URL(fileURLWithPath: $0).lastPathComponent },
            projectsByNormalizedPath: { projects },
            existingDefinitions: { existingDefinitions }
        )
    }

    private func makeProject(name: String, path: String) -> Project {
        Project(
            id: path,
            name: name,
            path: path,
            tags: [],
            runConfigurations: [],
            worktrees: [],
            mtime: 0,
            size: 0,
            checksum: path,
            isGitRepository: true,
            gitCommits: 1,
            gitLastCommit: 0,
            created: 0,
            checked: 0
        )
    }
}

private func normalizeAlignmentDefinitionTestPath(_ path: String) -> String {
    var normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\\", with: "/")
    while normalized.count > 1 && normalized.hasSuffix("/") {
        normalized.removeLast()
    }
    return normalized
}
