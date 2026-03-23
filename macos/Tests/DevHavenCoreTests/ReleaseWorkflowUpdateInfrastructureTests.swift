import XCTest

final class ReleaseWorkflowUpdateInfrastructureTests: XCTestCase {
    func testReleaseWorkflowPublishesStagedAppcastAfterAssetBuild() throws {
        let source = try String(contentsOf: releaseWorkflowURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("appcast-staged.xml"), "stable release workflow 应先产出 staged appcast，避免安装资产未就绪就触发客户端升级")
        XCTAssertTrue(source.contains("promote-appcast.sh"), "stable release workflow 应有显式 promote 步骤，把 staged appcast 提升为正式 stable feed")
        XCTAssertTrue(source.contains("setup-sparkle-framework.sh"), "release workflow 应先准备 Sparkle vendor/tooling")
        XCTAssertTrue(
            source.contains("releases/download/$RELEASE_TAG/"),
            "stable appcast 生成时 download-url-prefix 必须带尾部斜杠，否则 enclosure URL 会把 tag 段吞掉"
        )
        XCTAssertTrue(
            source.contains("releases/tag/$RELEASE_TAG"),
            "stable appcast item link 应指向具体 release 页面，避免手动下载模式把用户带回仓库首页"
        )
    }

    func testNightlyWorkflowExistsAndPublishesNightlyFeed() throws {
        let source = try String(contentsOf: nightlyWorkflowURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("nightly/appcast.xml"), "nightly workflow 应维护独立的 nightly feed")
        XCTAssertTrue(source.contains("generate-appcast.sh"), "nightly workflow 应复用统一的 appcast 生成脚本")
        XCTAssertTrue(
            source.contains("releases/download/$RELEASE_TAG/"),
            "nightly appcast 生成时 download-url-prefix 也必须带尾部斜杠，避免 enclosure URL 缺失 tag 片段"
        )
        XCTAssertTrue(
            source.contains("releases/tag/$RELEASE_TAG"),
            "nightly appcast item link 也应指向当前 nightly release 页面"
        )
    }

    func testPromoteAppcastScriptRenamesUploadedAssetToFixedFeedName() throws {
        let source = try String(contentsOf: promoteScriptURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("staged_upload_path"),
            "promote-appcast 脚本应先构造与 feed 固定文件名一致的临时上传路径，不能直接把 appcast-staged.xml 用 label 冒充成 appcast.xml"
        )
        XCTAssertTrue(
            source.contains("\"$ASSET_NAME\""),
            "promote-appcast 脚本应按目标 asset 名生成上传文件，确保 GitHub release 下载 URL 真的命中 appcast.xml"
        )
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

    private func promoteScriptURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("macos/scripts/promote-appcast.sh")
    }
}
