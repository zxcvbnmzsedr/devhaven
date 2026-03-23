import Foundation

struct DevHavenAppcastItem: Equatable, Sendable {
    var title: String?
    var shortVersion: String?
    var buildVersion: String?
    var downloadURL: URL?
    var releaseNotesURL: URL?

    var comparableBuildNumber: Int64? {
        guard let buildVersion else {
            return nil
        }
        return Int64(buildVersion)
    }

    var preferredDownloadURL: URL? {
        releaseNotesURL ?? downloadURL
    }
}

struct DevHavenAppcastDocument: Equatable, Sendable {
    let items: [DevHavenAppcastItem]

    var latestItem: DevHavenAppcastItem? {
        items.max { lhs, rhs in
            switch (lhs.comparableBuildNumber, rhs.comparableBuildNumber) {
            case let (lhs?, rhs?):
                return lhs < rhs
            case (.none, .some):
                return true
            case (.some, .none):
                return false
            case (.none, .none):
                return (lhs.shortVersion ?? lhs.title ?? "") < (rhs.shortVersion ?? rhs.title ?? "")
            }
        } ?? items.first
    }
}

enum DevHavenAppcastParser {
    static func parse(data: Data) throws -> DevHavenAppcastDocument {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? NSError(
                domain: "DevHavenUpdate",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "无法解析 appcast XML"]
            )
        }
        return DevHavenAppcastDocument(items: delegate.items)
    }
}

private final class Delegate: NSObject, XMLParserDelegate {
    private(set) var items: [DevHavenAppcastItem] = []
    private var currentItem: DevHavenAppcastItem?
    private var currentText: String = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = qName ?? elementName
        currentText = ""

        switch name {
        case "item":
            currentItem = DevHavenAppcastItem()
        case "enclosure":
            guard var currentItem else {
                return
            }
            if currentItem.downloadURL == nil {
                currentItem.downloadURL = URL(string: attributeDict["url"] ?? "")
            }
            if currentItem.buildVersion == nil {
                currentItem.buildVersion = attributeDict["sparkle:version"]?.trimmedNonEmpty
            }
            if currentItem.shortVersion == nil {
                currentItem.shortVersion = attributeDict["sparkle:shortVersionString"]?.trimmedNonEmpty
            }
            self.currentItem = currentItem
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = qName ?? elementName
        let text = currentText.trimmedNonEmpty

        guard var currentItem else {
            currentText = ""
            return
        }

        switch name {
        case "title":
            currentItem.title = text
        case "sparkle:version":
            currentItem.buildVersion = text
        case "sparkle:shortVersionString":
            currentItem.shortVersion = text
        case "sparkle:releaseNotesLink", "sparkle:fullReleaseNotesLink", "link":
            if currentItem.releaseNotesURL == nil {
                currentItem.releaseNotesURL = URL(string: text ?? "")
            }
        case "item":
            items.append(currentItem)
            self.currentItem = nil
        default:
            self.currentItem = currentItem
        }

        if name != "item" {
            self.currentItem = currentItem
        }
        currentText = ""
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
