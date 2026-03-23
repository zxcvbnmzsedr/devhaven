import XCTest

final class NativeBuildScriptUpdateSupportTests: XCTestCase {
    func testPackageManifestDependsOnSparkleBinaryTarget() throws {
        let source = try String(contentsOf: packageFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("binaryTarget(") && source.contains("Sparkle"), "Package.swift 应接入本地 Sparkle binary target，供原生 App 编译 updater")
    }

    func testBuildScriptEmbedsSparkleFrameworkAndUpdateMetadata() throws {
        let source = try String(contentsOf: buildScriptURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("setup-sparkle-framework.sh"), "打包脚本应先确保 Sparkle vendor 可用")
        XCTAssertTrue(source.contains("Contents/Frameworks"), ".app 组装时应创建 Frameworks 目录嵌入 Sparkle.framework")
        XCTAssertTrue(source.contains("Sparkle.framework"), ".app 组装时应复制 Sparkle.framework")
        XCTAssertTrue(source.contains("install_name_tool"), "打包脚本应显式修正可执行文件的运行时查找路径，避免 Sparkle 在启动时找不到")
        XCTAssertTrue(source.contains("@executable_path/../Frameworks"), "打包脚本应为主可执行文件注入指向 Contents/Frameworks 的 rpath")
        XCTAssertTrue(source.contains("CFBundleVersion"), "Info.plist 应写入单调递增的 build number，而不是固定写死")
        XCTAssertTrue(source.contains("SUPublicEDKey"), "Info.plist 应写入 Sparkle 公钥，供更新包校验")
        XCTAssertTrue(source.contains("SUFeedURL"), "Info.plist 应写入默认 appcast feed")
        XCTAssertTrue(source.contains("DevHavenUpdateDeliveryMode"), "Info.plist 应写入当前升级交付模式，供客户端决定自动安装还是手动下载")
        XCTAssertTrue(source.contains("DevHavenStableDownloadsPageURL") && source.contains("DevHavenNightlyDownloadsPageURL"), "Info.plist 应写入 stable/nightly 下载页，供手动下载 fallback 使用")
    }

    private func packageFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("macos/Package.swift")
    }

    private func buildScriptURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("macos/scripts/build-native-app.sh")
    }
}
