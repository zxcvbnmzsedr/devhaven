import Foundation

public struct WorkspaceBrowserState: Identifiable, Equatable, Codable, Sendable {
    public var surfaceId: String
    public var projectPath: String
    public var tabId: String
    public var paneId: String
    public var title: String
    public var urlString: String
    public var isLoading: Bool

    public var id: String { surfaceId }

    public init(
        surfaceId: String,
        projectPath: String,
        tabId: String,
        paneId: String,
        title: String = "浏览器",
        urlString: String = "",
        isLoading: Bool = false
    ) {
        self.surfaceId = surfaceId
        self.projectPath = projectPath
        self.tabId = tabId
        self.paneId = paneId
        self.title = title
        self.urlString = urlString
        self.isLoading = isLoading
    }

    public func rebinding(
        tabId: String? = nil,
        paneId: String
    ) -> WorkspaceBrowserState {
        WorkspaceBrowserState(
            surfaceId: surfaceId,
            projectPath: projectPath,
            tabId: tabId ?? self.tabId,
            paneId: paneId,
            title: title,
            urlString: urlString,
            isLoading: isLoading
        )
    }

    public func updating(
        title: String? = nil,
        urlString: String? = nil,
        isLoading: Bool? = nil
    ) -> WorkspaceBrowserState {
        WorkspaceBrowserState(
            surfaceId: surfaceId,
            projectPath: projectPath,
            tabId: tabId,
            paneId: paneId,
            title: title ?? self.title,
            urlString: urlString ?? self.urlString,
            isLoading: isLoading ?? self.isLoading
        )
    }
}
