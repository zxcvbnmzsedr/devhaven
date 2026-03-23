import XCTest

final class ReleaseWorkflowTests: XCTestCase {
    func testReleaseWorkflowPreparesReleaseBeforeMatrixAssetUpload() throws {
        let source = try String(contentsOf: workflowFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("prepare-release:"),
            "release workflow 应先有单独的 prepare-release job，集中处理 release 元数据与重复 draft 清理"
        )
        XCTAssertTrue(
            source.contains("needs: prepare-release"),
            "矩阵构建 job 应依赖 prepare-release，避免每个 job 自己争抢 release 创建/最终化"
        )
    }

    func testReleaseWorkflowUploadsAssetsWithoutActionGhReleaseFinalizeStep() throws {
        let source = try String(contentsOf: workflowFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("gh release upload"),
            "矩阵 job 应只上传 asset 到既有 release，而不是再次创建/最终化 release"
        )
        XCTAssertFalse(
            source.contains("uses: softprops/action-gh-release@v2"),
            "矩阵 job 不应继续直接调用 action-gh-release，否则重复 draft / finalize 冲突仍会复发"
        )
    }

    func testReleaseWorkflowDraftCleanupDoesNotUseUnsupportedGhReleaseListDatabaseIdField() throws {
        let source = try String(contentsOf: workflowFileURL(), encoding: .utf8)

        XCTAssertFalse(
            source.contains("gh release list --limit 100 --json databaseId,tagName,isDraft"),
            "draft release 清理不应再依赖 gh release list 不支持的 databaseId 字段，否则 prepare-release 会在 runner 上直接失败"
        )
        XCTAssertTrue(
            source.contains("repos/${GITHUB_REPOSITORY}/releases"),
            "draft release 清理应直接走 GitHub Releases API，拿到稳定的 release id 再删除重复 draft"
        )
    }

    func testReleaseWorkflowPrepareReleaseGhCommandsDoNotAssumeCheckedOutGitRepository() throws {
        let source = try String(contentsOf: workflowFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("gh release view \"$RELEASE_TAG\" -R \"$GITHUB_REPOSITORY\"") ||
            source.contains("gh release view \"$RELEASE_TAG\" --repo \"$GITHUB_REPOSITORY\""),
            "prepare-release job 没有 checkout 仓库，gh release view 必须显式指定目标 repo，不能隐式依赖本地 git 上下文"
        )
        XCTAssertTrue(
            source.contains("gh release edit \"$RELEASE_TAG\" -R \"$GITHUB_REPOSITORY\"") ||
            source.contains("gh release edit \"$RELEASE_TAG\" --repo \"$GITHUB_REPOSITORY\""),
            "prepare-release job 没有 checkout 仓库，gh release edit 必须显式指定目标 repo，避免 runner 上报 not a git repository"
        )
        XCTAssertTrue(
            source.contains("gh release create \"$RELEASE_TAG\" -R \"$GITHUB_REPOSITORY\"") ||
            source.contains("gh release create \"$RELEASE_TAG\" --repo \"$GITHUB_REPOSITORY\""),
            "prepare-release job 没有 checkout 仓库，gh release create 也必须显式指定目标 repo"
        )
    }

    func testReleaseWorkflowDoesNotMarkStableTagAsPrerelease() throws {
        let source = try String(contentsOf: workflowFileURL(), encoding: .utf8)

        XCTAssertFalse(
            source.contains("--prerelease"),
            "stable release workflow 不应把 v* 正式版本统一创建为 prerelease，否则 stable tag 与 stable-appcast 语义会继续错位"
        )
    }

    private func workflowFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".github/workflows/release.yml")
    }
}
