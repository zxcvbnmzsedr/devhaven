import XCTest
import DevHavenCore

final class WorkspaceAlignmentModelsTests: XCTestCase {
    func testGroupProjectionSummaryWhenAllMembersAligned() {
        let definition = WorkspaceAlignmentGroupDefinition(name: "支付链路", targetBranch: "feature/payment")
        let projection = WorkspaceAlignmentGroupProjection(
            definition: definition,
            members: [
                WorkspaceAlignmentMemberProjection(groupID: definition.id, projectPath: "/tmp/A", projectName: "A", status: .aligned),
                WorkspaceAlignmentMemberProjection(groupID: definition.id, projectPath: "/tmp/B", projectName: "B", status: .aligned)
            ]
        )

        XCTAssertEqual(projection.branchMetadataText, "feature/payment · 2 项目")
        XCTAssertEqual(projection.summaryText, "全部已对齐")
    }

    func testGroupProjectionSummaryCombinesAlignedAndDriftedCounts() {
        let definition = WorkspaceAlignmentGroupDefinition(name: "支付链路", targetBranch: "feature/payment")
        let projection = WorkspaceAlignmentGroupProjection(
            definition: definition,
            members: [
                WorkspaceAlignmentMemberProjection(groupID: definition.id, projectPath: "/tmp/A", projectName: "A", status: .aligned),
                WorkspaceAlignmentMemberProjection(groupID: definition.id, projectPath: "/tmp/B", projectName: "B", status: .currentBranch("develop"))
            ]
        )

        XCTAssertEqual(projection.summaryText, "1 已对齐 · 1 偏离")
    }

    func testMemberStatusDisplayTextAndDetail() {
        XCTAssertEqual(WorkspaceAlignmentMemberStatus.branchMissing.displayText, "未创建分支")
        XCTAssertEqual(
            WorkspaceAlignmentMemberStatus.currentBranch("develop").detailText(targetBranch: "feature/payment"),
            "当前分支为 develop，目标分支为 feature/payment"
        )
    }

    func testMemberProjectionDefaultsOpenTargetToProjectPath() {
        let member = WorkspaceAlignmentMemberProjection(
            groupID: "workspace-1",
            projectPath: "/tmp/root",
            projectName: "Root",
            status: .checking
        )

        XCTAssertEqual(member.openTarget, .project(projectPath: "/tmp/root"))
        XCTAssertEqual(member.openTarget.path, "/tmp/root")
    }

    func testMemberProjectionCanRepresentWorktreeOpenTarget() {
        let member = WorkspaceAlignmentMemberProjection(
            groupID: "workspace-1",
            projectPath: "/tmp/root",
            projectName: "Root",
            status: .aligned,
            openTarget: .worktree(rootProjectPath: "/tmp/root", worktreePath: "/tmp/root-feature")
        )

        XCTAssertEqual(member.openTarget, .worktree(rootProjectPath: "/tmp/root", worktreePath: "/tmp/root-feature"))
        XCTAssertEqual(member.openTarget.path, "/tmp/root-feature")
    }

    func testGroupDefinitionDecodesLegacyPayloadWithoutNewFields() throws {
        let json = """
        {
          "id": "FA99B08E-F7AC-4B9D-B006-A32991162DC5",
          "name": "test",
          "targetBranch": "test123",
          "baseBranchMode": "auto_detect",
          "projectPaths": [
            "/Users/example/A",
            "/Users/example/B"
          ],
          "createdAt": 796300488.18898,
          "updatedAt": 796301693.158217
        }
        """

        let decoded = try JSONDecoder().decode(
            WorkspaceAlignmentGroupDefinition.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(decoded.id, "FA99B08E-F7AC-4B9D-B006-A32991162DC5")
        XCTAssertEqual(decoded.name, "test")
        XCTAssertEqual(decoded.targetBranch, "test123")
        XCTAssertEqual(decoded.baseBranchMode, .autoDetect)
        XCTAssertEqual(decoded.projectPaths, ["/Users/example/A", "/Users/example/B"])
        XCTAssertNil(decoded.rootDirectoryName)
        XCTAssertEqual(decoded.memberAliases, [:])
    }
}
