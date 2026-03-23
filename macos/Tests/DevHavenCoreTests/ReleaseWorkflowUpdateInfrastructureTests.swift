import XCTest

final class ReleaseWorkflowUpdateInfrastructureTests: XCTestCase {
    func testReleaseWorkflowPublishesStagedAppcastAfterAssetBuild() throws {
        let source = try String(contentsOf: releaseWorkflowURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("appcast-staged.xml"), "stable release workflow 应先产出 staged appcast，避免安装资产未就绪就触发客户端升级")
        XCTAssertTrue(source.contains("promote-appcast.sh"), "stable release workflow 应有显式 promote 步骤，把 staged appcast 提升为正式 stable feed")
        XCTAssertTrue(source.contains("setup-sparkle-framework.sh"), "release workflow 应先准备 Sparkle vendor/tooling")
    }

    func testNightlyWorkflowExistsAndPublishesNightlyFeed() throws {
        let source = try String(contentsOf: nightlyWorkflowURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("nightly/appcast.xml"), "nightly workflow 应维护独立的 nightly feed")
        XCTAssertTrue(source.contains("generate-appcast.sh"), "nightly workflow 应复用统一的 appcast 生成脚本")
    }

    private func releaseWorkflowURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".github/workflows/release.yml")
    }

    private func nightlyWorkflowURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".github/workflows/nightly.yml")
    }
}
