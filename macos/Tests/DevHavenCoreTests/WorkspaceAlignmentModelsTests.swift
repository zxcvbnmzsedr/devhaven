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
}
