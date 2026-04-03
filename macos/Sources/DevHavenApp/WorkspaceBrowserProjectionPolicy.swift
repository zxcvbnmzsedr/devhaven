import DevHavenCore

struct WorkspaceBrowserProjectionUpdate: Equatable {
    var title: String
    var urlString: String
    var isLoading: Bool
    var suppressedProjectionWhileLoading: Bool
}

enum WorkspaceBrowserProjectionPolicy {
    static func resolve(
        existing: WorkspaceBrowserState?,
        runtime: WorkspaceBrowserRuntimeSnapshot
    ) -> WorkspaceBrowserProjectionUpdate {
        let existingTitle = existing?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let existingURL = existing?.urlString.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasExistingState = existing != nil

        let resolvedTitle: String
        let resolvedURL: String
        let resolvedLoading: Bool

        let shouldSuppressProjectionWhileLoading = runtime.isLoading && hasExistingState

        if shouldSuppressProjectionWhileLoading {
            resolvedTitle = existingTitle.isEmpty ? runtime.title : existingTitle
            resolvedURL = existingURL
            resolvedLoading = existing?.isLoading ?? false
        } else {
            resolvedTitle = runtime.title
            resolvedURL = runtime.urlString
            resolvedLoading = runtime.isLoading
        }

        return WorkspaceBrowserProjectionUpdate(
            title: resolvedTitle,
            urlString: resolvedURL,
            isLoading: resolvedLoading,
            suppressedProjectionWhileLoading: shouldSuppressProjectionWhileLoading
        )
    }
}
