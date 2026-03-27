import XCTest

final class WorkspaceProjectSidebarHostViewTests: XCTestCase {
    func testWorkspaceProjectSidebarHostUsesProjectionStoreInsteadOfDirectSidebarGetter() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("WorkspaceSidebarProjectionStore"), "WorkspaceProjectSidebarHostView 应持有独立的 sidebar projection store")
        XCTAssertTrue(source.contains("viewModel.workspaceSidebarProjectionRevision"), "WorkspaceProjectSidebarHostView 应通过 sidebar projection revision 驱动同步，而不是在 body 中直接现算 group getter")
        XCTAssertTrue(source.contains("sidebarProjectionStore.projection.groups"), "WorkspaceProjectSidebarHostView 应消费投影后的 groups")
        XCTAssertTrue(source.contains("sidebarProjectionStore.projection.availableProjects"), "WorkspaceProjectSidebarHostView 应消费投影后的 available projects")
        XCTAssertFalse(source.contains("groups: viewModel.workspaceSidebarGroups"), "WorkspaceProjectSidebarHostView 不应继续在 body 中直接读取 workspaceSidebarGroups")
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceProjectSidebarHostView.swift")
    }
}
