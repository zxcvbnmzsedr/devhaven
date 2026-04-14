import SwiftUI
import DevHavenCore

struct WorkspaceGitHubDetailSidebarView<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NativeTheme.surface)
    }
}

struct WorkspaceGitHubDetailSidebarSection<Content: View>: View {
    let title: String
    private let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeTheme.textSecondary)
                .textCase(.uppercase)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NativeTheme.elevated)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(NativeTheme.border, lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 12))
    }
}

struct WorkspaceGitHubMetadataRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(NativeTheme.textSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption)
                .foregroundStyle(NativeTheme.textPrimary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

struct WorkspaceGitHubActorListView: View {
    let actors: [WorkspaceGitHubActor]

    var body: some View {
        if actors.isEmpty {
            Text("暂无")
                .font(.caption)
                .foregroundStyle(NativeTheme.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(actorEntries, id: \.id) { entry in
                    Text(entry.title)
                        .font(.callout)
                        .foregroundStyle(NativeTheme.textPrimary)
                }
            }
        }
    }

    private var actorEntries: [(id: String, title: String)] {
        actors.enumerated().map { index, actor in
            let baseID = actor.nodeID ?? actor.login ?? actor.name ?? "actor"
            let title: String
            if let login = actor.login,
               let name = actor.name,
               !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               name != login {
                title = "\(name) (@\(login))"
            } else if let login = actor.login,
                      !login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                title = "@\(login)"
            } else {
                title = actor.displayName
            }
            return ("\(baseID)-\(index)", title)
        }
    }
}

struct WorkspaceGitHubLabelListView: View {
    let labels: [WorkspaceGitHubLabel]

    var body: some View {
        if labels.isEmpty {
            Text("暂无")
                .font(.caption)
                .foregroundStyle(NativeTheme.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(labels) { label in
                    Text(label.name)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(gitHubLabelColor(label.color ?? "").opacity(0.18))
                        .foregroundStyle(NativeTheme.textPrimary)
                        .clipShape(.capsule)
                }
            }
        }
    }
}
