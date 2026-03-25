import SwiftUI
import DevHavenCore

struct WorkspaceChromeContainerView<Content: View>: View {
    let viewModel: NativeAppViewModel
    private let content: () -> Content

    init(
        viewModel: NativeAppViewModel,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.viewModel = viewModel
        self.content = content
    }

    var body: some View {
        HStack(spacing: 0) {
            workspaceToolWindowStripe

            Rectangle()
                .fill(NativeTheme.border)
                .frame(width: 1)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NativeTheme.window)
        }
        .background(NativeTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(NativeTheme.border.opacity(1), lineWidth: 1)
        )
    }

    private var workspaceToolWindowStripe: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            toolWindowStripeButton(kind: .commit)
            toolWindowStripeButton(kind: .git)
        }
        .frame(width: 44)
        .frame(maxHeight: .infinity)
        .background(NativeTheme.surface.opacity(0.42))
    }

    private func toolWindowStripeButton(kind: WorkspaceToolWindowKind) -> some View {
        let isActive = viewModel.workspaceToolWindowState.activeKind == kind
            && viewModel.workspaceToolWindowState.isVisible
        return Button {
            viewModel.toggleWorkspaceToolWindow(kind)
        } label: {
            Image(systemName: kind.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isActive ? Color.white : NativeTheme.textSecondary)
                .frame(width: 28, height: 28)
                .background(isActive ? NativeTheme.accent : Color.clear)
                .clipShape(.rect(cornerRadius: 6))
                .accessibilityLabel(kind.title)
        }
        .buttonStyle(.plain)
    }
}
