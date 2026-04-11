import Foundation

public enum WorkspaceAgentKind: String, Codable, Equatable, Sendable {
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .claude:
            "Claude"
        case .codex:
            "Codex"
        }
    }
}

public enum WorkspaceAgentState: String, Codable, Equatable, Sendable {
    case unknown
    case running
    case waiting
    case idle
    case completed
    case failed

    public var priority: Int {
        switch self {
        case .waiting:
            500
        case .running:
            400
        case .failed:
            300
        case .completed:
            200
        case .idle:
            100
        case .unknown:
            0
        }
    }

    public var isActiveAttentionState: Bool {
        switch self {
        case .waiting, .running:
            true
        case .unknown, .idle, .completed, .failed:
            false
        }
    }

    public static func mostRelevant<S: Sequence>(_ states: S) -> WorkspaceAgentState? where S.Element == WorkspaceAgentState {
        states.max { lhs, rhs in
            lhs.priority < rhs.priority
        }
    }
}

public struct WorkspaceAgentSessionSignal: Codable, Equatable, Sendable {
    public var projectPath: String
    public var workspaceId: String
    public var tabId: String
    public var paneId: String
    public var surfaceId: String
    public var terminalSessionId: String
    public var agentKind: WorkspaceAgentKind
    public var sessionId: String
    public var pid: Int32?
    public var state: WorkspaceAgentState
    public var phase: WorkspaceAgentPhase?
    public var attention: WorkspaceAgentAttentionRequirement?
    public var toolName: String?
    public var summary: String?
    public var detail: String?
    public var updatedAt: Date

    public init(
        projectPath: String,
        workspaceId: String,
        tabId: String,
        paneId: String,
        surfaceId: String,
        terminalSessionId: String,
        agentKind: WorkspaceAgentKind,
        sessionId: String,
        pid: Int32? = nil,
        state: WorkspaceAgentState,
        phase: WorkspaceAgentPhase? = nil,
        attention: WorkspaceAgentAttentionRequirement? = nil,
        toolName: String? = nil,
        summary: String? = nil,
        detail: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.projectPath = projectPath
        self.workspaceId = workspaceId
        self.tabId = tabId
        self.paneId = paneId
        self.surfaceId = surfaceId
        self.terminalSessionId = terminalSessionId
        self.agentKind = agentKind
        self.sessionId = sessionId
        self.pid = pid
        self.state = state
        self.phase = phase
        self.attention = attention
        self.toolName = toolName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case projectPath
        case workspaceId
        case tabId
        case paneId
        case surfaceId
        case terminalSessionId
        case agentKind
        case sessionId
        case pid
        case state
        case phase
        case attention
        case toolName
        case summary
        case detail
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let updatedAt = try Self.decodeUpdatedAt(from: container)
        try self.init(
            projectPath: container.decode(String.self, forKey: .projectPath),
            workspaceId: container.decode(String.self, forKey: .workspaceId),
            tabId: container.decode(String.self, forKey: .tabId),
            paneId: container.decode(String.self, forKey: .paneId),
            surfaceId: container.decode(String.self, forKey: .surfaceId),
            terminalSessionId: container.decode(String.self, forKey: .terminalSessionId),
            agentKind: container.decode(WorkspaceAgentKind.self, forKey: .agentKind),
            sessionId: container.decode(String.self, forKey: .sessionId),
            pid: container.decodeIfPresent(Int32.self, forKey: .pid),
            state: container.decode(WorkspaceAgentState.self, forKey: .state),
            phase: container.decodeIfPresent(WorkspaceAgentPhase.self, forKey: .phase),
            attention: container.decodeIfPresent(WorkspaceAgentAttentionRequirement.self, forKey: .attention),
            toolName: container.decodeIfPresent(String.self, forKey: .toolName),
            summary: container.decodeIfPresent(String.self, forKey: .summary),
            detail: container.decodeIfPresent(String.self, forKey: .detail),
            updatedAt: updatedAt
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(projectPath, forKey: .projectPath)
        try container.encode(workspaceId, forKey: .workspaceId)
        try container.encode(tabId, forKey: .tabId)
        try container.encode(paneId, forKey: .paneId)
        try container.encode(surfaceId, forKey: .surfaceId)
        try container.encode(terminalSessionId, forKey: .terminalSessionId)
        try container.encode(agentKind, forKey: .agentKind)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encodeIfPresent(pid, forKey: .pid)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(phase, forKey: .phase)
        try container.encodeIfPresent(attention, forKey: .attention)
        try container.encodeIfPresent(toolName, forKey: .toolName)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(detail, forKey: .detail)
        try container.encode(Self.encodeUpdatedAt(updatedAt), forKey: .updatedAt)
    }

    public var effectivePhase: WorkspaceAgentPhase {
        phase ?? state.defaultPhase
    }

    public var effectiveAttention: WorkspaceAgentAttentionRequirement {
        attention ?? effectivePhase.defaultAttention
    }

    public var effectiveState: WorkspaceAgentState {
        if phase != nil {
            return effectivePhase.fallbackState
        }
        return state
    }

    private static func decodeUpdatedAt(from container: KeyedDecodingContainer<CodingKeys>) throws -> Date {
        if let timestamp = try? container.decode(Double.self, forKey: .updatedAt) {
            return Date(timeIntervalSince1970: timestamp)
        }
        if let timestamp = try? container.decode(Int.self, forKey: .updatedAt) {
            return Date(timeIntervalSince1970: Double(timestamp))
        }
        if let value = try container.decodeIfPresent(String.self, forKey: .updatedAt),
           let date = iso8601Date(from: value) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            forKey: .updatedAt,
            in: container,
            debugDescription: "updatedAt 必须是 Unix 时间戳或 ISO8601 字符串"
        )
    }

    private static func encodeUpdatedAt(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func iso8601Date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
