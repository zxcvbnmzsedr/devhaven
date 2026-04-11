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
    public var phase: WorkspaceAgentPhase?
    public var attention: WorkspaceAgentAttentionRequirement?
    public var summary: String?

    public init(
        state: WorkspaceAgentState,
        phase: WorkspaceAgentPhase? = nil,
        attention: WorkspaceAgentAttentionRequirement? = nil,
        summary: String?
    ) {
        self.state = state
        self.phase = phase
        self.attention = attention
        self.summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

public struct WorkspaceAgentDisplayCandidate: Equatable, Sendable {
    public var projectPath: String
    public var paneID: String
    public var signalSessionID: String?
    public var signalState: WorkspaceAgentState
    public var signalPhase: WorkspaceAgentPhase?
    public var signalAttention: WorkspaceAgentAttentionRequirement?
    public var signalUpdatedAt: Date?

    public init(
        projectPath: String,
        paneID: String,
        signalSessionID: String? = nil,
        signalState: WorkspaceAgentState,
        signalPhase: WorkspaceAgentPhase? = nil,
        signalAttention: WorkspaceAgentAttentionRequirement? = nil,
        signalUpdatedAt: Date? = nil
    ) {
        self.projectPath = projectPath
        self.paneID = paneID
        self.signalSessionID = signalSessionID
        self.signalState = signalState
        self.signalPhase = signalPhase
        self.signalAttention = signalAttention
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
    public var agentSessionIDByPaneID: [String: String]
    public var agentPhaseByPaneID: [String: WorkspaceAgentPhase]
    public var agentAttentionByPaneID: [String: WorkspaceAgentAttentionRequirement]
    public var agentSummaryByPaneID: [String: String]
    public var agentKindByPaneID: [String: WorkspaceAgentKind]
    public var agentUpdatedAtByPaneID: [String: Date]

    public init(
        notifications: [WorkspaceTerminalNotification] = [],
        taskStatusByPaneID: [String: WorkspaceTaskStatus] = [:],
        agentStateByPaneID: [String: WorkspaceAgentState] = [:],
        agentSessionIDByPaneID: [String: String] = [:],
        agentPhaseByPaneID: [String: WorkspaceAgentPhase] = [:],
        agentAttentionByPaneID: [String: WorkspaceAgentAttentionRequirement] = [:],
        agentSummaryByPaneID: [String: String] = [:],
        agentKindByPaneID: [String: WorkspaceAgentKind] = [:],
        agentUpdatedAtByPaneID: [String: Date] = [:]
    ) {
        self.notifications = notifications
        self.taskStatusByPaneID = taskStatusByPaneID
        self.agentStateByPaneID = agentStateByPaneID
        self.agentSessionIDByPaneID = agentSessionIDByPaneID
        self.agentPhaseByPaneID = agentPhaseByPaneID
        self.agentAttentionByPaneID = agentAttentionByPaneID
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

    public var agentPhase: WorkspaceAgentPhase? {
        prioritizedAgentRecord?.phase
    }

    public var agentAttention: WorkspaceAgentAttentionRequirement? {
        prioritizedAgentRecord?.attention
    }

    public var agentKind: WorkspaceAgentKind? {
        prioritizedAgentRecord?.kind
    }

    public var agentUpdatedAt: Date? {
        prioritizedAgentRecord?.updatedAt
    }

    public func resolvedAgentState(
        overridesByPaneID: [String: WorkspaceAgentPresentationOverride]
    ) -> WorkspaceAgentState? {
        prioritizedAgentRecord(overridesByPaneID: overridesByPaneID)?.state
    }

    public func resolvedAgentState(
        overridesByPaneID: [String: WorkspaceAgentPresentationOverride],
        preferringPaneIDs preferredPaneIDs: Set<String>
    ) -> WorkspaceAgentState? {
        prioritizedAgentRecord(
            overridesByPaneID: overridesByPaneID,
            preferringPaneIDs: preferredPaneIDs
        )?.state
    }

    public func resolvedAgentSummary(
        overridesByPaneID: [String: WorkspaceAgentPresentationOverride]
    ) -> String? {
        prioritizedAgentRecord(overridesByPaneID: overridesByPaneID)?.summary
    }

    public func resolvedAgentSummary(
        overridesByPaneID: [String: WorkspaceAgentPresentationOverride],
        preferringPaneIDs preferredPaneIDs: Set<String>
    ) -> String? {
        prioritizedAgentRecord(
            overridesByPaneID: overridesByPaneID,
            preferringPaneIDs: preferredPaneIDs
        )?.summary
    }

    public func resolvedAgentPhase(
        overridesByPaneID: [String: WorkspaceAgentPresentationOverride]
    ) -> WorkspaceAgentPhase? {
        prioritizedAgentRecord(overridesByPaneID: overridesByPaneID)?.phase
    }

    public func resolvedAgentPhase(
        overridesByPaneID: [String: WorkspaceAgentPresentationOverride],
        preferringPaneIDs preferredPaneIDs: Set<String>
    ) -> WorkspaceAgentPhase? {
        prioritizedAgentRecord(
            overridesByPaneID: overridesByPaneID,
            preferringPaneIDs: preferredPaneIDs
        )?.phase
    }

    public func resolvedAgentAttention(
        overridesByPaneID: [String: WorkspaceAgentPresentationOverride]
    ) -> WorkspaceAgentAttentionRequirement? {
        prioritizedAgentRecord(overridesByPaneID: overridesByPaneID)?.attention
    }

    public func resolvedAgentAttention(
        overridesByPaneID: [String: WorkspaceAgentPresentationOverride],
        preferringPaneIDs preferredPaneIDs: Set<String>
    ) -> WorkspaceAgentAttentionRequirement? {
        prioritizedAgentRecord(
            overridesByPaneID: overridesByPaneID,
            preferringPaneIDs: preferredPaneIDs
        )?.attention
    }

    public func resolvedAgentKind(
        overridesByPaneID: [String: WorkspaceAgentPresentationOverride]
    ) -> WorkspaceAgentKind? {
        prioritizedAgentRecord(overridesByPaneID: overridesByPaneID)?.kind
    }

    public func resolvedAgentKind(
        overridesByPaneID: [String: WorkspaceAgentPresentationOverride],
        preferringPaneIDs preferredPaneIDs: Set<String>
    ) -> WorkspaceAgentKind? {
        prioritizedAgentRecord(
            overridesByPaneID: overridesByPaneID,
            preferringPaneIDs: preferredPaneIDs
        )?.kind
    }

    public func resolvedAgentUpdatedAt(
        overridesByPaneID: [String: WorkspaceAgentPresentationOverride]
    ) -> Date? {
        prioritizedAgentRecord(overridesByPaneID: overridesByPaneID)?.updatedAt
    }

    public func resolvedAgentUpdatedAt(
        overridesByPaneID: [String: WorkspaceAgentPresentationOverride],
        preferringPaneIDs preferredPaneIDs: Set<String>
    ) -> Date? {
        prioritizedAgentRecord(
            overridesByPaneID: overridesByPaneID,
            preferringPaneIDs: preferredPaneIDs
        )?.updatedAt
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
        sessionID: String,
        phase: WorkspaceAgentPhase?,
        attention: WorkspaceAgentAttentionRequirement?,
        summary: String?,
        updatedAt: Date = Date(),
        for paneID: String
    ) {
        agentStateByPaneID[paneID] = state
        agentSessionIDByPaneID[paneID] = sessionID
        if let phase {
            agentPhaseByPaneID[paneID] = phase
        } else {
            agentPhaseByPaneID.removeValue(forKey: paneID)
        }
        if let attention, attention != .none {
            agentAttentionByPaneID[paneID] = attention
        } else {
            agentAttentionByPaneID.removeValue(forKey: paneID)
        }
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
        agentSessionIDByPaneID.removeValue(forKey: paneID)
        agentPhaseByPaneID.removeValue(forKey: paneID)
        agentAttentionByPaneID.removeValue(forKey: paneID)
        agentSummaryByPaneID.removeValue(forKey: paneID)
        agentKindByPaneID.removeValue(forKey: paneID)
        agentUpdatedAtByPaneID.removeValue(forKey: paneID)
    }

    public mutating func clearAgentStates() {
        agentStateByPaneID.removeAll()
        agentSessionIDByPaneID.removeAll()
        agentPhaseByPaneID.removeAll()
        agentAttentionByPaneID.removeAll()
        agentSummaryByPaneID.removeAll()
        agentKindByPaneID.removeAll()
        agentUpdatedAtByPaneID.removeAll()
    }

    private var prioritizedAgentRecord: (
        paneID: String,
        state: WorkspaceAgentState,
        phase: WorkspaceAgentPhase?,
        attention: WorkspaceAgentAttentionRequirement?,
        kind: WorkspaceAgentKind?,
        summary: String?,
        updatedAt: Date?,
        isPreferred: Bool
    )? {
        prioritizedAgentRecord(overridesByPaneID: [:])
    }

    private func prioritizedAgentRecord(
        overridesByPaneID: [String: WorkspaceAgentPresentationOverride]
    ) -> (
        paneID: String,
        state: WorkspaceAgentState,
        phase: WorkspaceAgentPhase?,
        attention: WorkspaceAgentAttentionRequirement?,
        kind: WorkspaceAgentKind?,
        summary: String?,
        updatedAt: Date?,
        isPreferred: Bool
    )? {
        prioritizedAgentRecord(
            overridesByPaneID: overridesByPaneID,
            preferringPaneIDs: []
        )
    }

    private func prioritizedAgentRecord(
        overridesByPaneID: [String: WorkspaceAgentPresentationOverride],
        preferringPaneIDs preferredPaneIDs: Set<String>
    ) -> (
        paneID: String,
        state: WorkspaceAgentState,
        phase: WorkspaceAgentPhase?,
        attention: WorkspaceAgentAttentionRequirement?,
        kind: WorkspaceAgentKind?,
        summary: String?,
        updatedAt: Date?,
        isPreferred: Bool
    )? {
        agentStateByPaneID
            .map { paneID, state in
                let presentationOverride = overridesByPaneID[paneID]
                let resolvedPhase = presentationOverride?.phase
                    ?? agentPhaseByPaneID[paneID]
                    ?? presentationOverride?.state.defaultPhase
                let resolvedAttention = presentationOverride?.attention
                    ?? agentAttentionByPaneID[paneID]
                    ?? resolvedPhase?.defaultAttention
                return (
                    paneID: paneID,
                    state: presentationOverride?.state ?? state,
                    phase: resolvedPhase,
                    attention: resolvedAttention,
                    kind: agentKindByPaneID[paneID],
                    summary: presentationOverride != nil ? presentationOverride?.summary : agentSummaryByPaneID[paneID],
                    updatedAt: agentUpdatedAtByPaneID[paneID],
                    isPreferred: preferredPaneIDs.contains(paneID)
                )
            }
            .max { lhs, rhs in
                if lhs.isPreferred != rhs.isPreferred {
                    return !lhs.isPreferred && rhs.isPreferred
                }
                if (lhs.attention?.priority ?? 0) != (rhs.attention?.priority ?? 0) {
                    return (lhs.attention?.priority ?? 0) < (rhs.attention?.priority ?? 0)
                }
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
