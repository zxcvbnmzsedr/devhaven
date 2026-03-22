import DevHavenCore

struct WorkspaceAgentStatusAccessory: Equatable {
    let symbolName: String
    let label: String
    let state: WorkspaceAgentState

    init?(agentState: WorkspaceAgentState?, agentKind: WorkspaceAgentKind?) {
        guard let agentState else {
            return nil
        }
        let kindName = agentKind?.displayName ?? "Agent"
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
