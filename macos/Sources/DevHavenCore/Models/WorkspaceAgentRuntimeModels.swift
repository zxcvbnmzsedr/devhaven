import Foundation

public enum WorkspaceAgentPhase: String, Codable, Equatable, Sendable {
    case unknown
    case idle
    case launching
    case thinking
    case runningTool
    case awaitingApproval
    case awaitingInput
    case notifying
    case completed
    case failed
    case stale

    public var fallbackState: WorkspaceAgentState {
        switch self {
        case .unknown:
            .unknown
        case .idle:
            .idle
        case .launching, .thinking, .runningTool:
            .running
        case .awaitingApproval, .awaitingInput, .notifying:
            .waiting
        case .completed:
            .completed
        case .failed, .stale:
            .failed
        }
    }
}

public enum WorkspaceAgentAttentionRequirement: String, Codable, Equatable, Sendable {
    case none
    case input
    case approval
    case notification
    case error

    public var priority: Int {
        switch self {
        case .approval:
            400
        case .input:
            300
        case .error:
            200
        case .notification:
            100
        case .none:
            0
        }
    }

    public var requiresUserAction: Bool {
        switch self {
        case .input, .approval:
            true
        case .none, .notification, .error:
            false
        }
    }
}

public extension WorkspaceAgentState {
    var defaultPhase: WorkspaceAgentPhase {
        switch self {
        case .unknown:
            .unknown
        case .running:
            .thinking
        case .waiting:
            .awaitingInput
        case .idle:
            .idle
        case .completed:
            .completed
        case .failed:
            .failed
        }
    }
}

public extension WorkspaceAgentPhase {
    var defaultAttention: WorkspaceAgentAttentionRequirement {
        switch self {
        case .awaitingApproval:
            .approval
        case .awaitingInput:
            .input
        case .notifying:
            .notification
        case .failed, .stale:
            .error
        case .unknown, .idle, .launching, .thinking, .runningTool, .completed:
            .none
        }
    }
}
