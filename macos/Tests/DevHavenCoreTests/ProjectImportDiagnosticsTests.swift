import XCTest
@testable import DevHavenCore

@MainActor
final class ProjectImportDiagnosticsTests: XCTestCase {
    func testDiagnosticsEmitReadableProjectImportMessages() {
        var messages = [String]()
        let diagnostics = ProjectImportDiagnostics(logSink: { messages.append($0) })

        diagnostics.recordImporterCallback(action: .addDirectory, urlCount: 1)
        diagnostics.recordSecurityScope(action: .addDirectory, requestedCount: 1, grantedCount: 1)
        diagnostics.recordImportAttempt(action: .addProjects, paths: ["/tmp/a", "/tmp/b"])
        diagnostics.recordValidationRejected(path: "/tmp/wt", reason: "不支持导入 Git worktree：/tmp/wt")
        diagnostics.recordDirectoryPersisted(path: "/tmp/projects", totalCount: 3)
        diagnostics.recordDirectProjectsPersisted(requestedCount: 2, acceptedCount: 1, rejectedCount: 1, totalCount: 4)
        diagnostics.recordSelectionApplied(action: .addProjects, filter: "direct-projects")
        diagnostics.recordFailure(action: .addProjects, errorDescription: "不支持导入 Git worktree：/tmp/wt")

        XCTAssertTrue(messages.contains("[project-import] importer-callback action=add-directory urlCount=1"))
        XCTAssertTrue(messages.contains("[project-import] security-scope action=add-directory requested=1 granted=1"))
        XCTAssertTrue(messages.contains("[project-import] import-attempt action=add-projects pathCount=2 paths=/tmp/a,/tmp/b"))
        XCTAssertTrue(messages.contains("[project-import] validate path=/tmp/wt result=rejected reason=不支持导入 Git worktree：/tmp/wt"))
        XCTAssertTrue(messages.contains("[project-import] persist-directory path=/tmp/projects totalDirectories=3"))
        XCTAssertTrue(messages.contains(where: { $0.contains("[project-import] persist-direct-projects requested=2") && $0.contains("accepted=1") && $0.contains("rejected=1") && $0.contains("totalDirectProjects=4") }))
        XCTAssertTrue(messages.contains("[project-import] selection-applied action=add-projects filter=direct-projects"))
        XCTAssertTrue(messages.contains("[project-import] failure action=add-projects error=不支持导入 Git worktree：/tmp/wt"))
    }
}
