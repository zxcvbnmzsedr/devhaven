import SwiftUI
import DevHavenCore

struct WorkspaceDiffNavigationBarView<TrailingContent: View>: View {
    let navigatorState: WorkspaceDiffNavigatorState
    @Binding var viewerMode: WorkspaceDiffViewerMode
    let availableViewerModes: [WorkspaceDiffViewerMode]
    let onRefresh: () -> Void
    let onPreviousDifference: () -> Void
    let onNextDifference: () -> Void
    @ViewBuilder let trailingContent: () -> TrailingContent

    init(
        navigatorState: WorkspaceDiffNavigatorState,
        viewerMode: Binding<WorkspaceDiffViewerMode>,
        availableViewerModes: [WorkspaceDiffViewerMode] = [.sideBySide, .unified],
        onRefresh: @escaping () -> Void,
        onPreviousDifference: @escaping () -> Void,
        onNextDifference: @escaping () -> Void,
        @ViewBuilder trailingContent: @escaping () -> TrailingContent
    ) {
        self.navigatorState = navigatorState
        self._viewerMode = viewerMode
        self.availableViewerModes = availableViewerModes
        self.onRefresh = onRefresh
        self.onPreviousDifference = onPreviousDifference
        self.onNextDifference = onNextDifference
        self.trailingContent = trailingContent
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPreviousDifference) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Previous Difference")
            .help("Previous Difference")
            .disabled(!navigatorState.canGoPrevious)

            Button(action: onNextDifference) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Next Difference")
            .help("Next Difference")
            .disabled(!navigatorState.canGoNext)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(navigatorState.currentDifferenceIndex)/\(navigatorState.totalDifferences)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(NativeTheme.textPrimary)
                Text("\(navigatorState.currentRequestIndex)/\(navigatorState.totalRequests)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(NativeTheme.textSecondary)
            }

            Spacer(minLength: 0)

            if availableViewerModes.count > 1 {
                Picker("查看模式", selection: $viewerMode) {
                    if availableViewerModes.contains(.sideBySide) {
                        Text("并排").tag(WorkspaceDiffViewerMode.sideBySide)
                    }
                    if availableViewerModes.contains(.unified) {
                        Text("统一").tag(WorkspaceDiffViewerMode.unified)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            trailingContent()

            Button("刷新", action: onRefresh)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(NativeTheme.surface)
    }
}
