import Foundation

public enum WorkspaceTaskStatus: String, Equatable, Sendable {
    case idle
    case running
}

public struct WorkspaceTerminalNotification: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var projectPath: String
    public var rootProjectPath: String
    public var workspaceId: String
    public var tabId: String
    public var paneId: String
    public var title: String
    public var body: String
    public var createdAt: Date
    public var isRead: Bool

    public init(
        id: UUID = UUID(),
        projectPath: String,
        rootProjectPath: String,
        workspaceId: String,
        tabId: String,
        paneId: String,
        title: String,
        body: String,
        createdAt: Date = Date(),
        isRead: Bool = false
    ) {
        self.id = id
        self.projectPath = projectPath
        self.rootProjectPath = rootProjectPath
        self.workspaceId = workspaceId
        self.tabId = tabId
        self.paneId = paneId
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.isRead = isRead
    }

    public var content: String {
        [title, body].filter { !$0.isEmpty }.joined(separator: " - ")
    }
}

public struct WorkspaceAttentionState: Equatable, Sendable {
    public var notifications: [WorkspaceTerminalNotification]
    public var taskStatusByPaneID: [String: WorkspaceTaskStatus]

    public init(
        notifications: [WorkspaceTerminalNotification] = [],
        taskStatusByPaneID: [String: WorkspaceTaskStatus] = [:]
    ) {
        self.notifications = notifications
        self.taskStatusByPaneID = taskStatusByPaneID
    }

    public var unreadCount: Int {
        notifications.reduce(into: 0) { count, notification in
            if !notification.isRead {
                count += 1
            }
        }
    }

    public var hasUnreadNotifications: Bool {
        unreadCount > 0
    }

    public var taskStatus: WorkspaceTaskStatus {
        taskStatusByPaneID.values.contains(.running) ? .running : .idle
    }

    public var latestNotificationDate: Date? {
        notifications.first?.createdAt
    }

    public mutating func appendNotification(_ notification: WorkspaceTerminalNotification) {
        notifications.insert(notification, at: 0)
    }

    public mutating func markNotificationRead(id: UUID) {
        guard let index = notifications.firstIndex(where: { $0.id == id }) else {
            return
        }
        notifications[index].isRead = true
    }

    public mutating func markNotificationsRead(for paneID: String) {
        for index in notifications.indices where notifications[index].paneId == paneID {
            notifications[index].isRead = true
        }
    }

    public mutating func setTaskStatus(_ status: WorkspaceTaskStatus, for paneID: String) {
        taskStatusByPaneID[paneID] = status
    }
}
