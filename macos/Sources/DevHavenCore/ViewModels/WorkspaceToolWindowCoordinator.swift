import Foundation

@MainActor
final class WorkspaceToolWindowCoordinator {
    private let presentationState: WorkspacePresentationState
    private let supportsKind: @MainActor (WorkspaceToolWindowKind) -> Bool
    private let prepareProjectTree: @MainActor () -> Void
    private let prepareCommit: @MainActor () -> Void
    private let prepareGit: @MainActor () -> Void

    init(
        presentationState: WorkspacePresentationState,
        supportsKind: @escaping @MainActor (WorkspaceToolWindowKind) -> Bool,
        prepareProjectTree: @escaping @MainActor () -> Void,
        prepareCommit: @escaping @MainActor () -> Void,
        prepareGit: @escaping @MainActor () -> Void
    ) {
        self.presentationState = presentationState
        self.supportsKind = supportsKind
        self.prepareProjectTree = prepareProjectTree
        self.prepareCommit = prepareCommit
        self.prepareGit = prepareGit
    }

    func toggle(_ kind: WorkspaceToolWindowKind) {
        guard supportsKind(kind) else {
            return
        }
        switch kind.placement {
        case .side:
            if presentationState.sideToolWindowState.activeKind == kind,
               presentationState.sideToolWindowState.isVisible {
                hideSide()
                return
            }
            showSide(kind)
        case .bottom:
            if presentationState.bottomToolWindowState.activeKind == kind,
               presentationState.bottomToolWindowState.isVisible {
                hideBottom()
                return
            }
            showBottom(kind)
        }
    }

    func showSide(_ kind: WorkspaceToolWindowKind) {
        guard kind.placement == .side, supportsKind(kind) else {
            return
        }
        presentationState.sideToolWindowState.activeKind = kind
        presentationState.sideToolWindowState.isVisible = true
        presentationState.sideToolWindowState.width = presentationState.sideToolWindowState.lastExpandedWidth
        syncVisibleContexts()
        presentationState.focusedArea = .sideToolWindow(kind)
    }

    func hideSide() {
        if presentationState.sideToolWindowState.isVisible {
            presentationState.sideToolWindowState.lastExpandedWidth = presentationState.sideToolWindowState.width
        }
        presentationState.sideToolWindowState.isVisible = false
        if case .sideToolWindow = presentationState.focusedArea {
            presentationState.focusedArea = .terminal
        }
    }

    func updateSideWidth(_ width: Double) {
        let clamped = max(220, width)
        presentationState.sideToolWindowState.width = clamped
        presentationState.sideToolWindowState.lastExpandedWidth = clamped
    }

    func showBottom(_ kind: WorkspaceToolWindowKind) {
        guard kind.placement == .bottom, supportsKind(kind) else {
            return
        }
        presentationState.bottomToolWindowState.activeKind = kind
        presentationState.bottomToolWindowState.isVisible = true
        presentationState.bottomToolWindowState.height = presentationState.bottomToolWindowState.lastExpandedHeight
        syncVisibleContexts()
        presentationState.focusedArea = .bottomToolWindow(kind)
    }

    func hideBottom() {
        if presentationState.bottomToolWindowState.isVisible {
            presentationState.bottomToolWindowState.lastExpandedHeight = presentationState.bottomToolWindowState.height
        }
        presentationState.bottomToolWindowState.isVisible = false
        if case .bottomToolWindow = presentationState.focusedArea {
            presentationState.focusedArea = .terminal
        }
    }

    func updateBottomHeight(_ height: Double) {
        let clamped = max(160, height)
        presentationState.bottomToolWindowState.height = clamped
        presentationState.bottomToolWindowState.lastExpandedHeight = clamped
    }

    func setFocusedArea(_ area: WorkspaceFocusedArea) {
        presentationState.focusedArea = area
    }

    func syncVisibleContexts() {
        if !supportsKind(.commit),
           presentationState.sideToolWindowState.activeKind == .commit {
            hideSide()
        }
        if !supportsKind(.git),
           presentationState.bottomToolWindowState.activeKind == .git {
            hideBottom()
        }

        var neededKinds = Set<WorkspaceToolWindowKind>()
        if presentationState.sideToolWindowState.isVisible,
           let kind = presentationState.sideToolWindowState.activeKind {
            neededKinds.insert(kind)
        }
        if presentationState.bottomToolWindowState.isVisible,
           let kind = presentationState.bottomToolWindowState.activeKind {
            neededKinds.insert(kind)
        }

        for kind in neededKinds {
            switch kind {
            case .project:
                prepareProjectTree()
            case .commit:
                prepareCommit()
            case .git:
                prepareGit()
            }
        }
    }
}
