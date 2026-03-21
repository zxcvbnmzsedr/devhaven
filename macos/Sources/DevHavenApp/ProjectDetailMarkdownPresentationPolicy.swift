import Foundation
import DevHavenCore

struct ProjectDetailMarkdownPresentationPolicy: Equatable {
    static let previewCharacterLimit = 4_000

    let previewContent: String
    let isTruncated: Bool

    static func resolve(readme: MarkdownDocument, previewCharacterLimit: Int = previewCharacterLimit) -> ProjectDetailMarkdownPresentationPolicy {
        let trimmedContent = readme.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedContent.count > previewCharacterLimit else {
            return ProjectDetailMarkdownPresentationPolicy(
                previewContent: trimmedContent,
                isTruncated: false
            )
        }

        let prefix = String(trimmedContent.prefix(previewCharacterLimit))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ProjectDetailMarkdownPresentationPolicy(
            previewContent: prefix + "\n\n…（README 内容较长，详情面板仅预览前 4000 个字符）",
            isTruncated: true
        )
    }
}
