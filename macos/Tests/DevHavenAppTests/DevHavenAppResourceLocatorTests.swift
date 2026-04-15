import XCTest
@testable import DevHavenApp

final class DevHavenAppResourceLocatorTests: XCTestCase {
    func testResolveResourceBundleURLFindsSwiftPMBundleInsideAppResourcesDirectory() throws {
        let fixture = try makeFakeAppBundle()
        let resolvedURL = DevHavenAppResourceBundleLocator.resolveResourceBundleURL(
            fileManager: .default,
            mainBundle: fixture.mainBundle,
            allBundles: [],
            allFrameworks: []
        )

        XCTAssertEqual(resolvedURL?.standardizedFileURL, fixture.resourceBundleURL.standardizedFileURL)
    }

    func testResolveResourceURLFindsMonacoHTMLInsideResolvedResourceBundle() throws {
        let fixture = try makeFakeAppBundle()
        let editorIndexURL = fixture.resourceBundleURL
            .appending(path: "MonacoEditorResources", directoryHint: .isDirectory)
            .appending(path: "index.html", directoryHint: .notDirectory)
        try "<html><body>ok</body></html>".write(to: editorIndexURL, atomically: true, encoding: .utf8)

        let resolvedURL = DevHavenAppResourceLocator.resolveResourceURL(
            subdirectory: "MonacoEditorResources",
            resource: "index",
            withExtension: "html",
            fileManager: .default,
            mainBundle: fixture.mainBundle,
            allBundles: [],
            allFrameworks: []
        )

        XCTAssertEqual(resolvedURL?.standardizedFileURL, editorIndexURL.standardizedFileURL)
    }

    private func makeFakeAppBundle() throws -> (mainBundle: Bundle, resourceBundleURL: URL) {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let appBundleURL = rootURL.appending(path: "DevHaven.app", directoryHint: .isDirectory)
        let contentsURL = appBundleURL.appending(path: "Contents", directoryHint: .isDirectory)
        let resourcesURL = contentsURL.appending(path: "Resources", directoryHint: .isDirectory)
        let macOSURL = contentsURL.appending(path: "MacOS", directoryHint: .isDirectory)
        let resourceBundleURL = resourcesURL.appending(
            path: DevHavenAppResourceBundleLocator.resourceBundleName,
            directoryHint: .isDirectory
        )

        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: resourceBundleURL.appending(path: "MonacoEditorResources", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )

        let infoPlistURL = contentsURL.appending(path: "Info.plist", directoryHint: .notDirectory)
        let executableURL = macOSURL.appending(path: "DevHavenApp", directoryHint: .notDirectory)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleIdentifier</key>
          <string>com.devhaven.tests</string>
          <key>CFBundleName</key>
          <string>DevHaven</string>
          <key>CFBundleExecutable</key>
          <string>DevHavenApp</string>
          <key>CFBundlePackageType</key>
          <string>APPL</string>
        </dict>
        </plist>
        """
        try plist.write(to: infoPlistURL, atomically: true, encoding: .utf8)
        try "".write(to: executableURL, atomically: true, encoding: .utf8)

        guard let bundle = Bundle(url: appBundleURL) else {
            XCTFail("Failed to open fake app bundle")
            throw NSError(domain: "DevHavenAppResourceLocatorTests", code: 1)
        }
        return (bundle, resourceBundleURL)
    }
}
