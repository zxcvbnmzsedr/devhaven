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

    private func workflowFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".github/workflows/release.yml")
    }
}
