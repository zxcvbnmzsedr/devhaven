import DevHavenCore

struct WorkspaceAgentStatusAccessory: Equatable {
    let symbolName: String
    let label: String
    let state: WorkspaceAgentState

    init?(
        agentState: WorkspaceAgentState?,
        agentKind: WorkspaceAgentKind?,
        agentPhase: WorkspaceAgentPhase? = nil,
        agentAttention: WorkspaceAgentAttentionRequirement? = nil
    ) {
        guard let agentState else {
            return nil
        }
        let kindName = agentKind?.displayName ?? "Agent"
        if let agentAttention {
            switch agentAttention {
            case .approval:
                self.symbolName = "exclamationmark.triangle.fill"
                self.label = "\(kindName) 等待审批"
                self.state = .waiting
                return
            case .input:
                self.symbolName = "questionmark.circle.fill"
                self.label = "\(kindName) 等待你的回复"
                self.state = .waiting
                return
            case .notification:
                self.symbolName = "bell.fill"
                self.label = "\(kindName) 有新通知"
                self.state = .waiting
                return
            case .error:
                self.symbolName = "xmark.octagon.fill"
                self.label = "\(kindName) 需要处理错误"
                self.state = .failed
                return
            case .none:
                break
            }
        }

        if let agentPhase {
            switch agentPhase {
            case .launching:
                self.symbolName = "bolt.circle.fill"
                self.label = "\(kindName) 正在启动"
                self.state = .running
                return
            case .thinking:
                self.symbolName = "sparkles"
                self.label = "\(kindName) 正在思考"
                self.state = .running
                return
            case .runningTool:
                self.symbolName = "wrench.and.screwdriver.fill"
                self.label = "\(kindName) 正在执行工具"
                self.state = .running
                return
            case .awaitingApproval, .awaitingInput, .notifying, .unknown, .idle, .completed, .failed, .stale:
                break
            }
        }

        switch agentState {
        case .waiting:
            self.symbolName = "exclamationmark.circle.fill"
            if agentKind == .codex {
                self.label = "\(kindName) 等待输入"
            } else {
                self.label = "\(kindName) 等待处理"
            }
        case .running:
            self.symbolName = "bolt.fill"
            self.label = "\(kindName) 正在运行"
        case .completed:
            self.symbolName = "checkmark.circle.fill"
            self.label = "\(kindName) 已完成"
        case .failed:
            self.symbolName = "xmark.circle.fill"
            self.label = "\(kindName) 失败"
        case .idle, .unknown:
            return nil
        }
        self.state = agentState
    }
}
