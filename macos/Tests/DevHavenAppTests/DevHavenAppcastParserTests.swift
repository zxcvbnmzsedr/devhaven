import XCTest
@testable import DevHavenApp

final class DevHavenAppcastParserTests: XCTestCase {
    func testParserExtractsLatestItemBuildVersionAndDownloadURL() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <title>DevHaven</title>
            <item>
              <title>DevHaven 3.0.1</title>
              <sparkle:version>3000001</sparkle:version>
              <sparkle:shortVersionString>3.0.1</sparkle:shortVersionString>
              <sparkle:releaseNotesLink>https://github.com/example/devhaven/releases/tag/v3.0.1</sparkle:releaseNotesLink>
              <enclosure url="https://github.com/example/devhaven/releases/download/v3.0.1/DevHaven-macos-universal.zip" sparkle:version="3000001" sparkle:shortVersionString="3.0.1" type="application/octet-stream" />
            </item>
            <item>
              <title>DevHaven 3.0.0</title>
              <sparkle:version>3000000</sparkle:version>
              <sparkle:shortVersionString>3.0.0</sparkle:shortVersionString>
              <enclosure url="https://github.com/example/devhaven/releases/download/v3.0.0/DevHaven-macos-universal.zip" sparkle:version="3000000" sparkle:shortVersionString="3.0.0" type="application/octet-stream" />
            </item>
          </channel>
        </rss>
        """

        let item = try XCTUnwrap(DevHavenAppcastParser.parse(data: Data(xml.utf8)).latestItem)

        XCTAssertEqual(item.buildVersion, "3000001")
        XCTAssertEqual(item.shortVersion, "3.0.1")
        XCTAssertEqual(item.downloadURL?.absoluteString, "https://github.com/example/devhaven/releases/download/v3.0.1/DevHaven-macos-universal.zip")
        XCTAssertEqual(item.releaseNotesURL?.absoluteString, "https://github.com/example/devhaven/releases/tag/v3.0.1")
    }
}
