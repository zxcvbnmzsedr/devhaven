import SwiftUI
import DevHavenCore

struct WorkspaceCommitPanelView: View {
    @Bindable var viewModel: WorkspaceCommitViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeader
            messageEditor
            optionsSection
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
    }

    private var panelHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Commit")
                .font(.callout.weight(.semibold))
                .foregroundStyle(NativeTheme.textPrimary)
            Spacer(minLength: 8)
            Text(viewModel.commitStatusLegend)
                .font(.caption.monospacedDigit())
                .foregroundStyle(NativeTheme.textSecondary)
        }
    }

    private var messageEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("提交信息")
                .font(.caption.weight(.medium))
                .foregroundStyle(NativeTheme.textSecondary)
            TextEditor(text: messageBinding)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 70)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(NativeTheme.window)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(NativeTheme.border, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Commit Options")
                .font(.caption.weight(.medium))
                .foregroundStyle(NativeTheme.textSecondary)
            Toggle("Amend", isOn: amendBinding)
            Toggle("Sign-off", isOn: signOffBinding)
            TextField("Author（可选）", text: authorBinding)
                .textFieldStyle(.roundedBorder)
        }
        .toggleStyle(.checkbox)
    }

    private var executionFeedbackRow: some View {
        HStack(spacing: 6) {
            Image(systemName: executionIndicator.systemImage)
                .font(.caption.weight(.semibold))
            Text(executionIndicator.text)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .foregroundStyle(executionIndicator.color)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button("Commit") {
                viewModel.executeCommit(action: .commit)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canExecuteCommit(action: .commit))

            Button("Commit & Push") {
                viewModel.executeCommit(action: .commitAndPush)
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canExecuteCommit(action: .commitAndPush))
        }
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

    private var executionIndicator: (text: String, systemImage: String, color: Color) {
        switch viewModel.executionState {
        case .idle:
            return ("等待提交", "clock", NativeTheme.textSecondary)
        case .running:
            return ("执行中…", "arrow.triangle.2.circlepath", .accentColor)
        case .succeeded:
            return ("提交成功", "checkmark.circle.fill", .green)
        case .failed(let message):
            let fallback = message.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = fallback.isEmpty ? "提交失败" : fallback
            return (text, "xmark.octagon.fill", .red)
        }
    }
}
