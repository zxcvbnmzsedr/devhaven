import AppKit
import Foundation
import GhosttyKit

extension NSPasteboard {
    private static let ghosttyEscapeCharacters = "\\ ()[]{}<>\"'`!#$&;|*?\t"
    private static let ghosttyUTF8PlainTextType = NSPasteboard.PasteboardType("public.utf8-plain-text")

    private static let ghosttySelectionName = NSPasteboard.Name("com.devhaven.ghostty.selection")

    static func ghosttyEscape(_ string: String) -> String {
        var result = string
        for character in ghosttyEscapeCharacters {
            result = result.replacingOccurrences(of: String(character), with: "\\\(character)")
        }
        return result
    }

    func getOpinionatedStringContents() -> String? {
        if let urls = readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            return urls
                .map { $0.isFileURL ? Self.ghosttyEscape($0.path) : $0.absoluteString }
                .joined(separator: " ")
        }

        if let value = string(forType: .string) {
            return value
        }

        return string(forType: Self.ghosttyUTF8PlainTextType)
    }

    static func ghostty(_ clipboard: ghostty_clipboard_e) -> NSPasteboard? {
        switch clipboard {
        case GHOSTTY_CLIPBOARD_STANDARD:
            return .general
        case GHOSTTY_CLIPBOARD_SELECTION:
            return NSPasteboard(name: Self.ghosttySelectionName)
        default:
            return nil
        }
    }
}
