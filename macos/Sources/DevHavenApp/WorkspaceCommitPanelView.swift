import SwiftUI
import DevHavenCore

struct WorkspaceCommitPanelView: View {
    @Bindable var viewModel: WorkspaceCommitViewModel
    @State private var isShowingMoreOptions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeader
            amendToggle
            messageEditor
            executionFeedbackRow
            actionRow
        }
        .padding(12)
        .background(NativeTheme.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(NativeTheme.border)
                .frame(height: 1)
        }
        .popover(isPresented: $isShowingMoreOptions, arrowEdge: .top) {
            moreOptionsPopover
        }
    }

    private var panelHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Commit")
                .font(.callout.weight(.semibold))
                .foregroundStyle(NativeTheme.textPrimary)
            Spacer(minLength: 8)
        }
    }

    private var amendToggle: some View {
        Toggle("Amend", isOn: amendBinding)
            .toggleStyle(.checkbox)
            .foregroundStyle(NativeTheme.textPrimary)
    }

    private var messageEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: messageBinding)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(NativeTheme.window)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(NativeTheme.border, lineWidth: 1)
                }

            if viewModel.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Commit Message")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(NativeTheme.textSecondary)
                    .padding(.leading, 14)
                    .padding(.top, 16)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var executionFeedbackRow: some View {
        switch viewModel.executionState {
        case .idle:
            EmptyView()
        case .running:
            feedbackRow(
                text: "正在执行提交…",
                systemImage: "arrow.triangle.2.circlepath",
                color: NativeTheme.accent
            )
        case .succeeded:
            feedbackRow(
                text: "提交成功",
                systemImage: "checkmark.circle.fill",
                color: NativeTheme.success
            )
        case .failed(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            feedbackRow(
                text: trimmed.isEmpty ? "提交失败" : trimmed,
                systemImage: "xmark.octagon.fill",
                color: NativeTheme.danger
            )
        }
    }

    private func feedbackRow(text: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
            Text(text)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .foregroundStyle(color)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button(primaryActionTitle) {
                viewModel.executeCommit(action: .commit)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canExecuteCommit(action: .commit))

            Button("Commit and Push...") {
                viewModel.executeCommit(action: .commitAndPush)
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canExecuteCommit(action: .commitAndPush))

            Spacer(minLength: 8)

            Button {
                isShowingMoreOptions.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NativeTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(NativeTheme.elevated)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(NativeTheme.border, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .help("更多提交选项")
        }
    }

    private var moreOptionsPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("More Options")
                .font(.callout.weight(.semibold))
                .foregroundStyle(NativeTheme.textPrimary)

            Toggle("Sign-off", isOn: signOffBinding)
                .toggleStyle(.checkbox)
                .foregroundStyle(NativeTheme.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Author")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(NativeTheme.textSecondary)
                TextField("Author（可选）", text: authorBinding)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(14)
        .frame(width: 240)
        .background(NativeTheme.surface)
    }

    private var primaryActionTitle: String {
        viewModel.options.isAmend ? "Amend Commit" : "Commit"
    }

    private var messageBinding: Binding<String> {
        Binding(
            get: { viewModel.commitMessage },
            set: { viewModel.updateCommitMessage($0) }
        )
    }

    private var amendBinding: Binding<Bool> {
        Binding(
            get: { viewModel.options.isAmend },
            set: { viewModel.updateOptionAmend($0) }
        )
    }

    private var signOffBinding: Binding<Bool> {
        Binding(
            get: { viewModel.options.isSignOff },
            set: { viewModel.updateOptionSignOff($0) }
        )
    }

    private var authorBinding: Binding<String> {
        Binding(
            get: { viewModel.options.author ?? "" },
            set: { viewModel.updateOptionAuthor($0) }
        )
    }
}
