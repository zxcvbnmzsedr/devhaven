import SwiftUI

struct WorkspaceGitHubRenderedContentView: View {
    let content: String

    var body: some View {
        WorkspaceMarkdownRenderedContentView(
            content: content,
            baseURL: URL(string: "https://github.com"),
            layout: .fitContent(minHeight: 120)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
