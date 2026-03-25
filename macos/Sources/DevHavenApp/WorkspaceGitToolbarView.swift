import SwiftUI
import DevHavenCore

struct WorkspaceGitToolbarView: View {
    @Bindable var viewModel: WorkspaceGitViewModel

    private let gitSections: [WorkspaceGitSection] = [.changes, .branches, .operations]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    ForEach(gitSections) { section in
                        Button {
                            viewModel.setSection(section)
                        } label: {
                            Text(section.title)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(viewModel.section == section ? NativeTheme.textPrimary : NativeTheme.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(viewModel.section == section ? NativeTheme.accent.opacity(0.22) : Color.clear)
                                .clipShape(.capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer(minLength: 8)

                Button("刷新") {
                    viewModel.refreshForCurrentSection()
                }
                .buttonStyle(.borderedProminent)
                .tint(NativeTheme.accent)
            }

            Text(viewModel.repositoryContext.repositoryPath)
                .font(.caption2.monospaced())
                .foregroundStyle(NativeTheme.textSecondary)
                .textSelection(.enabled)
                .lineLimit(1)
        }
    }
}
