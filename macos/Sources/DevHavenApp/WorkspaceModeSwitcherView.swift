import SwiftUI
import DevHavenCore

struct WorkspaceModeSwitcherView: View {
    @Binding var selection: WorkspacePrimaryMode

    var body: some View {
        HStack(spacing: 8) {
            ForEach(WorkspacePrimaryMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Text(mode.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(selection == mode ? Color.white : NativeTheme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(selection == mode ? NativeTheme.accent : NativeTheme.elevated)
                        .clipShape(.capsule)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}
