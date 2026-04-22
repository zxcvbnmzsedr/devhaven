import AppKit

enum WorkspaceTerminalCloseRequirement: Equatable {
    case canClose
    case needsConfirmation(displayTitle: String)
}

@MainActor
protocol WorkspaceTerminalCloseRequirementEvaluating: AnyObject {
    func evaluateCloseRequirement(
        _ completion: @escaping (WorkspaceTerminalCloseRequirement) -> Void
    )
}

@MainActor
protocol WorkspaceTerminalClosePrompting {
    func confirmCloseTerminals(
        displayTitles: [String],
        actionDescription: String
    ) -> Bool
}

@MainActor
struct AppKitWorkspaceTerminalClosePrompt: WorkspaceTerminalClosePrompting {
    func confirmCloseTerminals(
        displayTitles: [String],
        actionDescription: String
    ) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "继续\(actionDescription)？"
        alert.informativeText = informativeText(
            for: displayTitles,
            actionDescription: actionDescription
        )
        alert.addButton(withTitle: "继续")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func informativeText(
        for displayTitles: [String],
        actionDescription: String
    ) -> String {
        let cleanedTitles = displayTitles
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let uniqueTitles = Array(NSOrderedSet(array: cleanedTitles)) as? [String] ?? cleanedTitles

        if uniqueTitles.count <= 1 {
            let displayTitle = uniqueTitles.first ?? "终端"
            return "终端“\(displayTitle)”中仍有正在运行的命令。继续\(actionDescription)会中断当前 shell 或前台任务。"
        }

        let previewTitles = uniqueTitles.prefix(3).map { "• \($0)" }.joined(separator: "\n")
        let remainingCount = uniqueTitles.count - min(uniqueTitles.count, 3)
        let remainingSummary = remainingCount > 0 ? "\n• 还有 \(remainingCount) 个终端" : ""
        return """
以下终端中仍有正在运行的命令：

\(previewTitles)\(remainingSummary)

继续\(actionDescription)会中断这些终端中的前台任务。
"""
    }
}

@MainActor
enum WorkspaceTerminalCloseCoordinator {
    static func confirmIfNeeded(
        evaluators: [any WorkspaceTerminalCloseRequirementEvaluating],
        actionDescription: String,
        prompt: any WorkspaceTerminalClosePrompting = AppKitWorkspaceTerminalClosePrompt(),
        performClose: @escaping () -> Void
    ) {
        let uniqueEvaluators = uniquedEvaluators(from: evaluators)
        collectCloseRequirements(from: uniqueEvaluators) { requirements in
            let displayTitles = requirements.compactMap { requirement -> String? in
                guard case let .needsConfirmation(displayTitle) = requirement else {
                    return nil
                }
                return displayTitle
            }
            if displayTitles.isEmpty || prompt.confirmCloseTerminals(
                displayTitles: displayTitles,
                actionDescription: actionDescription
            ) {
                performClose()
            }
        }
    }

    private static func collectCloseRequirements(
        from evaluators: [any WorkspaceTerminalCloseRequirementEvaluating],
        index: Int = 0,
        accumulated: [WorkspaceTerminalCloseRequirement] = [],
        completion: @escaping ([WorkspaceTerminalCloseRequirement]) -> Void
    ) {
        guard index < evaluators.count else {
            completion(accumulated)
            return
        }

        evaluators[index].evaluateCloseRequirement { requirement in
            var nextAccumulated = accumulated
            nextAccumulated.append(requirement)
            collectCloseRequirements(
                from: evaluators,
                index: index + 1,
                accumulated: nextAccumulated,
                completion: completion
            )
        }
    }

    private static func uniquedEvaluators(
        from evaluators: [any WorkspaceTerminalCloseRequirementEvaluating]
    ) -> [any WorkspaceTerminalCloseRequirementEvaluating] {
        var seen = Set<ObjectIdentifier>()
        return evaluators.filter { evaluator in
            let identifier = ObjectIdentifier(evaluator)
            return seen.insert(identifier).inserted
        }
    }
}
