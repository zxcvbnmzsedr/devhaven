import SwiftUI
import DevHavenCore

private enum WorkspaceGitTopLevelTab: String, CaseIterable, Identifiable {
    case git
    case log
    case console

    var id: String { rawValue }

    var title: String {
        switch self {
        case .git:
            return "Git"
        case .log:
            return "Log"
        case .console:
            return "Console"
        }
    }
}

struct WorkspaceGitRootView: View {
    @Bindable var viewModel: WorkspaceGitViewModel
    @State private var sidebarRatio = 0.22
    @State private var selectedTopLevelTab: WorkspaceGitTopLevelTab
    @State private var lastGitSection: WorkspaceGitSection

    init(viewModel: WorkspaceGitViewModel) {
        self.viewModel = viewModel
        let initialTopLevelTab: WorkspaceGitTopLevelTab = viewModel.section == .log ? .log : .git
        let initialGitSection: WorkspaceGitSection = viewModel.section == .log ? .branches : viewModel.section
        _selectedTopLevelTab = State(initialValue: initialTopLevelTab)
        _lastGitSection = State(initialValue: initialGitSection)
    }

    var body: some View {
        VStack(spacing: 0) {
            gitTopTabStrip

            Group {
                switch selectedTopLevelTab {
                case .git:
                    gitTabContent
                case .log:
                    WorkspaceGitIdeaLogView(viewModel: viewModel.logViewModel)
                case .console:
                    WorkspaceGitConsoleView(repositoryPath: viewModel.repositoryContext.repositoryPath)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NativeTheme.window)
        .onAppear {
            refreshVisibleContent()
        }
        .onChange(of: viewModel.repositoryContext.repositoryPath) { _, _ in
            syncTopLevelTab(with: viewModel.section)
            refreshVisibleContent()
        }
        .onChange(of: viewModel.section) { _, newSection in
            syncTopLevelTab(with: newSection)
        }
    }

    private var gitTopTabStrip: some View {
        HStack(spacing: 0) {
            gitToolWindowTitle
            topTabButton(.log)
            topTabButton(.console)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(NativeTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NativeTheme.border)
                .frame(height: 1)
        }
    }

    private var gitToolWindowTitle: some View {
        Text(WorkspaceGitTopLevelTab.git.title)
            .font(.callout.weight(.medium))
            .foregroundStyle(selectedTopLevelTab == .git ? NativeTheme.textPrimary : NativeTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selectedTopLevelTab == .git ? NativeTheme.elevated : Color.clear)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(selectedTopLevelTab == .git ? NativeTheme.accent : .clear)
                    .frame(height: 2)
            }
    }

    private func topTabButton(_ tab: WorkspaceGitTopLevelTab) -> some View {
        Button {
            selectTopLevelTab(tab)
        } label: {
            Text(tab.title)
                .font(.callout.weight(.medium))
                .foregroundStyle(selectedTopLevelTab == tab ? NativeTheme.textPrimary : NativeTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selectedTopLevelTab == tab ? NativeTheme.elevated : Color.clear)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(selectedTopLevelTab == tab ? NativeTheme.accent : .clear)
                        .frame(height: 2)
                }
        }
        .buttonStyle(.plain)
    }

    private var gitTabContent: some View {
        VStack(spacing: 0) {
            WorkspaceGitToolbarView(viewModel: viewModel)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(NativeTheme.surface)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(NativeTheme.border)
                        .frame(height: 1)
                }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(NativeTheme.warning)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NativeTheme.warning.opacity(0.12))
            }

            WorkspaceSplitView(
                direction: .horizontal,
                ratio: sidebarRatio,
                onRatioChange: { sidebarRatio = $0 },
                leading: {
                    WorkspaceGitSidebarView(
                        viewModel: viewModel,
                        showsExecutionWorktreeSelector: true
                    )
                    .background(NativeTheme.sidebar)
                },
                trailing: {
                    switch viewModel.section {
                    case .log:
                        EmptyView()
                    case .branches:
                        WorkspaceGitBranchesView(viewModel: viewModel)
                    case .operations:
                        WorkspaceGitOperationsView(viewModel: viewModel)
                    }
                }
            )
        }
    }

    private func selectTopLevelTab(_ tab: WorkspaceGitTopLevelTab) {
        if selectedTopLevelTab == tab {
            if tab == .git {
                viewModel.refreshForCurrentSection()
            } else {
                selectedTopLevelTab = .git
                if viewModel.section == lastGitSection {
                    viewModel.refreshForCurrentSection()
                } else {
                    viewModel.setSection(lastGitSection)
                }
            }
            return
        }

        selectedTopLevelTab = tab
        switch tab {
        case .git:
            if viewModel.section == lastGitSection {
                viewModel.refreshForCurrentSection()
            } else {
                viewModel.setSection(lastGitSection)
            }
        case .log:
            if viewModel.section == .log {
                viewModel.logViewModel.refresh()
            } else {
                viewModel.setSection(.log)
            }
        case .console:
            viewModel.cancelPendingReads()
        }
    }

    private func refreshVisibleContent() {
        switch selectedTopLevelTab {
        case .git:
            viewModel.refreshForCurrentSection()
        case .log:
            viewModel.logViewModel.refresh()
        case .console:
            break
        }
    }

    private func syncTopLevelTab(with section: WorkspaceGitSection) {
        guard selectedTopLevelTab != .console else {
            if section != .log {
                lastGitSection = section
            }
            return
        }

        if section == .log {
            selectedTopLevelTab = .log
        } else {
            lastGitSection = section
            selectedTopLevelTab = .git
        }
    }
}
