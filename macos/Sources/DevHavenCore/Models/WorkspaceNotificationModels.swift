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

public struct WorkspaceAgentPresentationOverride: Equatable, Sendable {
    public var state: WorkspaceAgentState
    public var summary: String?

    public init(state: WorkspaceAgentState, summary: String?) {
        self.state = state
        self.summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

public struct WorkspaceAgentDisplayCandidate: Equatable, Sendable {
    public var projectPath: String
    public var paneID: String
    public var signalState: WorkspaceAgentState
    public var signalUpdatedAt: Date?

    public init(
        projectPath: String,
        paneID: String,
        signalState: WorkspaceAgentState,
        signalUpdatedAt: Date? = nil
    ) {
        self.projectPath = projectPath
        self.paneID = paneID
        self.signalState = signalState
        self.signalUpdatedAt = signalUpdatedAt
    }

    public static func observationStableSorted(
        _ candidates: [WorkspaceAgentDisplayCandidate]
    ) -> [WorkspaceAgentDisplayCandidate] {
        candidates.sorted { lhs, rhs in
            if lhs.projectPath != rhs.projectPath {
                return lhs.projectPath < rhs.projectPath
            }
            if lhs.paneID != rhs.paneID {
                return lhs.paneID < rhs.paneID
            }
            return lhs.signalState.rawValue < rhs.signalState.rawValue
        }
    }
}

public struct WorkspaceAttentionState: Equatable, Sendable {
    public var notifications: [WorkspaceTerminalNotification]
    public var taskStatusByPaneID: [String: WorkspaceTaskStatus]
    public var agentStateByPaneID: [String: WorkspaceAgentState]
    public var agentSummaryByPaneID: [String: String]
    public var agentKindByPaneID: [String: WorkspaceAgentKind]
    public var agentUpdatedAtByPaneID: [String: Date]

    public init(
        notifications: [WorkspaceTerminalNotification] = [],
        taskStatusByPaneID: [String: WorkspaceTaskStatus] = [:],
        agentStateByPaneID: [String: WorkspaceAgentState] = [:],
        agentSummaryByPaneID: [String: String] = [:],
        agentKindByPaneID: [String: WorkspaceAgentKind] = [:],
        agentUpdatedAtByPaneID: [String: Date] = [:]
    ) {
        self.notifications = notifications
        self.taskStatusByPaneID = taskStatusByPaneID
        self.agentStateByPaneID = agentStateByPaneID
        self.agentSummaryByPaneID = agentSummaryByPaneID
        self.agentKindByPaneID = agentKindByPaneID
        self.agentUpdatedAtByPaneID = agentUpdatedAtByPaneID
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

    public var agentState: WorkspaceAgentState? {
        prioritizedAgentRecord?.state
    }

    public var agentSummary: String? {
        prioritizedAgentRecord?.summary
    }

    public var agentKind: WorkspaceAgentKind? {
        prioritizedAgentRecord?.kind
    }

    public func resolvedAgentState(
        overridesByPaneID: [String: WorkspaceAgentPresentationOverride]
    ) -> WorkspaceAgentState? {
        prioritizedAgentRecord(overridesByPaneID: overridesByPaneID)?.state
    }

    public func resolvedAgentSummary(
        overridesByPaneID: [String: WorkspaceAgentPresentationOverride]
    ) -> String? {
        prioritizedAgentRecord(overridesByPaneID: overridesByPaneID)?.summary
    }

    public func resolvedAgentKind(
        overridesByPaneID: [String: WorkspaceAgentPresentationOverride]
    ) -> WorkspaceAgentKind? {
        prioritizedAgentRecord(overridesByPaneID: overridesByPaneID)?.kind
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

    public mutating func setAgentState(
        _ state: WorkspaceAgentState,
        kind: WorkspaceAgentKind,
        summary: String?,
        updatedAt: Date = Date(),
        for paneID: String
    ) {
        agentStateByPaneID[paneID] = state
        agentKindByPaneID[paneID] = kind
        agentUpdatedAtByPaneID[paneID] = updatedAt
        if let summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            agentSummaryByPaneID[paneID] = summary
        } else {
            agentSummaryByPaneID.removeValue(forKey: paneID)
        }
    }

    public mutating func clearAgentState(for paneID: String) {
        agentStateByPaneID.removeValue(forKey: paneID)
        agentSummaryByPaneID.removeValue(forKey: paneID)
        agentKindByPaneID.removeValue(forKey: paneID)
        agentUpdatedAtByPaneID.removeValue(forKey: paneID)
    }

    public mutating func clearAgentStates() {
        agentStateByPaneID.removeAll()
        agentSummaryByPaneID.removeAll()
        agentKindByPaneID.removeAll()
        agentUpdatedAtByPaneID.removeAll()
    }

    private var prioritizedAgentRecord: (paneID: String, state: WorkspaceAgentState, kind: WorkspaceAgentKind?, summary: String?, updatedAt: Date?)? {
        prioritizedAgentRecord(overridesByPaneID: [:])
    }

    private func prioritizedAgentRecord(
        overridesByPaneID: [String: WorkspaceAgentPresentationOverride]
    ) -> (paneID: String, state: WorkspaceAgentState, kind: WorkspaceAgentKind?, summary: String?, updatedAt: Date?)? {
        agentStateByPaneID
            .map { paneID, state in
                let presentationOverride = overridesByPaneID[paneID]
                return (
                    paneID: paneID,
                    state: presentationOverride?.state ?? state,
                    kind: agentKindByPaneID[paneID],
                    summary: presentationOverride != nil ? presentationOverride?.summary : agentSummaryByPaneID[paneID],
                    updatedAt: agentUpdatedAtByPaneID[paneID]
                )
            }
            .max { lhs, rhs in
                if lhs.state.priority != rhs.state.priority {
                    return lhs.state.priority < rhs.state.priority
                }
                return (lhs.updatedAt ?? .distantPast) < (rhs.updatedAt ?? .distantPast)
            }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
