import Foundation

public typealias SwiftDate = Double

public struct ColorData: Codable, Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}

public struct TagData: Codable, Equatable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var color: ColorData
    public var hidden: Bool

    public init(name: String, color: ColorData, hidden: Bool) {
        self.name = name
        self.color = color
        self.hidden = hidden
    }
}

public struct OpenToolSettings: Codable, Equatable, Sendable {
    public var commandPath: String
    public var arguments: [String]

    public init(commandPath: String, arguments: [String]) {
        self.commandPath = commandPath
        self.arguments = arguments
    }
}

public struct GitIdentity: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(name)|\(email)" }
    public var name: String
    public var email: String

    public init(name: String, email: String) {
        self.name = name
        self.email = email
    }
}

public enum ProjectListViewMode: String, Codable, Sendable, CaseIterable {
    case card
    case list
}

public enum NativeDateFilter: String, Sendable, CaseIterable, Identifiable {
    case all
    case lastDay
    case lastWeek

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "全部日期"
        case .lastDay: return "最近一天"
        case .lastWeek: return "最近一周"
        }
    }
}

public enum NativeGitFilter: String, Sendable, CaseIterable, Identifiable {
    case all
    case gitOnly
    case nonGitOnly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "全部项目"
        case .gitOnly: return "仅 Git 项目"
        case .nonGitOnly: return "仅非 Git 项目"
        }
    }
}

public enum AppMenuShortcutKey: String, Codable, CaseIterable, Sendable, Identifiable {
    case a
    case b
    case c
    case d
    case e
    case f
    case g
    case h
    case i
    case j
    case k
    case l
    case m
    case n
    case o
    case p
    case q
    case r
    case s
    case t
    case u
    case v
    case w
    case x
    case y
    case z

    public var id: String { rawValue }

    public var title: String {
        rawValue.uppercased()
    }
}

public struct AppMenuShortcut: Codable, Equatable, Sendable {
    public var key: AppMenuShortcutKey
    public var usesShift: Bool
    public var usesOption: Bool
    public var usesControl: Bool

    public init(
        key: AppMenuShortcutKey = .k,
        usesShift: Bool = false,
        usesOption: Bool = false,
        usesControl: Bool = false
    ) {
        self.key = key
        self.usesShift = usesShift
        self.usesOption = usesOption
        self.usesControl = usesControl
    }

    enum CodingKeys: String, CodingKey {
        case key
        case usesShift
        case usesOption
        case usesControl
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawKey = try container.decodeIfPresent(String.self, forKey: .key) ?? AppMenuShortcutKey.k.rawValue
        self.key = AppMenuShortcutKey(rawValue: rawKey.lowercased()) ?? .k
        self.usesShift = try container.decodeIfPresent(Bool.self, forKey: .usesShift) ?? false
        self.usesOption = try container.decodeIfPresent(Bool.self, forKey: .usesOption) ?? false
        self.usesControl = try container.decodeIfPresent(Bool.self, forKey: .usesControl) ?? false
    }

    public var displayLabel: String {
        let modifierLabel = "\(usesControl ? "⌃" : "")\(usesOption ? "⌥" : "")\(usesShift ? "⇧" : "")⌘"
        return "\(modifierLabel)\(key.title)"
    }
}

public enum SettingsNavigationSection: String, Codable, Sendable, CaseIterable, Identifiable {
    case general
    case terminal
    case workflow

    public var id: String { rawValue }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var editorOpenTool: OpenToolSettings
    public var terminalOpenTool: OpenToolSettings
    public var terminalUseWebglRenderer: Bool
    public var terminalTheme: String
    public var workspaceOpenProjectShortcut: AppMenuShortcut
    public var updateChannel: UpdateChannel
    public var updateAutomaticallyChecks: Bool
    public var updateAutomaticallyDownloads: Bool
    public var gitIdentities: [GitIdentity]
    public var projectListViewMode: ProjectListViewMode
    public var workspaceSidebarWidth: Double
    public var workspaceInAppNotificationsEnabled: Bool
    public var workspaceNotificationSoundEnabled: Bool
    public var workspaceSystemNotificationsEnabled: Bool
    public var moveNotifiedWorktreeToTop: Bool
    public var viteDevPort: Int
    public var webEnabled: Bool
    public var webBindHost: String
    public var webBindPort: Int

    public init(
        editorOpenTool: OpenToolSettings = .init(commandPath: "", arguments: []),
        terminalOpenTool: OpenToolSettings = .init(commandPath: "", arguments: []),
        terminalUseWebglRenderer: Bool = true,
        terminalTheme: String = "DevHaven Dark",
        workspaceOpenProjectShortcut: AppMenuShortcut = .init(),
        updateChannel: UpdateChannel = .stable,
        updateAutomaticallyChecks: Bool = true,
        updateAutomaticallyDownloads: Bool = false,
        gitIdentities: [GitIdentity] = [],
        projectListViewMode: ProjectListViewMode = .card,
        workspaceSidebarWidth: Double = 280,
        workspaceInAppNotificationsEnabled: Bool = true,
        workspaceNotificationSoundEnabled: Bool = true,
        workspaceSystemNotificationsEnabled: Bool = false,
        moveNotifiedWorktreeToTop: Bool = true,
        viteDevPort: Int = 1420,
        webEnabled: Bool = true,
        webBindHost: String = "0.0.0.0",
        webBindPort: Int = 3210
    ) {
        self.editorOpenTool = editorOpenTool
        self.terminalOpenTool = terminalOpenTool
        self.terminalUseWebglRenderer = terminalUseWebglRenderer
        self.terminalTheme = terminalTheme
        self.workspaceOpenProjectShortcut = workspaceOpenProjectShortcut
        self.updateChannel = updateChannel
        self.updateAutomaticallyChecks = updateAutomaticallyChecks
        self.updateAutomaticallyDownloads = updateAutomaticallyDownloads
        self.gitIdentities = gitIdentities
        self.projectListViewMode = projectListViewMode
        self.workspaceSidebarWidth = workspaceSidebarWidth
        self.workspaceInAppNotificationsEnabled = workspaceInAppNotificationsEnabled
        self.workspaceNotificationSoundEnabled = workspaceNotificationSoundEnabled
        self.workspaceSystemNotificationsEnabled = workspaceSystemNotificationsEnabled
        self.moveNotifiedWorktreeToTop = moveNotifiedWorktreeToTop
        self.viteDevPort = viteDevPort
        self.webEnabled = webEnabled
        self.webBindHost = webBindHost
        self.webBindPort = webBindPort
    }

    enum CodingKeys: String, CodingKey {
        case editorOpenTool
        case terminalOpenTool
        case terminalUseWebglRenderer
        case terminalTheme
        case workspaceOpenProjectShortcut
        case updateChannel
        case updateAutomaticallyChecks
        case updateAutomaticallyDownloads
        case gitIdentities
        case projectListViewMode
        case workspaceSidebarWidth
        case workspaceInAppNotificationsEnabled
        case workspaceNotificationSoundEnabled
        case workspaceSystemNotificationsEnabled
        case moveNotifiedWorktreeToTop
        case viteDevPort
        case webEnabled
        case webBindHost
        case webBindPort
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.editorOpenTool = try container.decodeIfPresent(OpenToolSettings.self, forKey: .editorOpenTool) ?? .init(commandPath: "", arguments: [])
        self.terminalOpenTool = try container.decodeIfPresent(OpenToolSettings.self, forKey: .terminalOpenTool) ?? .init(commandPath: "", arguments: [])
        self.terminalUseWebglRenderer = try container.decodeIfPresent(Bool.self, forKey: .terminalUseWebglRenderer) ?? true
        self.terminalTheme = try container.decodeIfPresent(String.self, forKey: .terminalTheme) ?? "DevHaven Dark"
        self.workspaceOpenProjectShortcut = try container.decodeIfPresent(AppMenuShortcut.self, forKey: .workspaceOpenProjectShortcut) ?? .init()
        self.updateChannel = try container.decodeIfPresent(UpdateChannel.self, forKey: .updateChannel) ?? .stable
        self.updateAutomaticallyChecks = try container.decodeIfPresent(Bool.self, forKey: .updateAutomaticallyChecks) ?? true
        self.updateAutomaticallyDownloads = try container.decodeIfPresent(Bool.self, forKey: .updateAutomaticallyDownloads) ?? false
        self.gitIdentities = try container.decodeIfPresent([GitIdentity].self, forKey: .gitIdentities) ?? []
        self.projectListViewMode = try container.decodeIfPresent(ProjectListViewMode.self, forKey: .projectListViewMode) ?? .card
        self.workspaceSidebarWidth = try container.decodeIfPresent(Double.self, forKey: .workspaceSidebarWidth) ?? 280
        self.workspaceInAppNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .workspaceInAppNotificationsEnabled) ?? true
        self.workspaceNotificationSoundEnabled = try container.decodeIfPresent(Bool.self, forKey: .workspaceNotificationSoundEnabled) ?? true
        self.workspaceSystemNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .workspaceSystemNotificationsEnabled) ?? false
        self.moveNotifiedWorktreeToTop = try container.decodeIfPresent(Bool.self, forKey: .moveNotifiedWorktreeToTop) ?? true
        self.viteDevPort = try container.decodeIfPresent(Int.self, forKey: .viteDevPort) ?? 1420
        self.webEnabled = try container.decodeIfPresent(Bool.self, forKey: .webEnabled) ?? true
        self.webBindHost = try container.decodeIfPresent(String.self, forKey: .webBindHost) ?? "0.0.0.0"
        self.webBindPort = try container.decodeIfPresent(Int.self, forKey: .webBindPort) ?? 3210
    }
}

public struct AppStateFile: Codable, Equatable, Sendable {
    public var version: Int
    public var tags: [TagData]
    public var directories: [String]
    public var directProjectPaths: [String]
    public var recycleBin: [String]
    public var favoriteProjectPaths: [String]
    public var settings: AppSettings

    public init(
        version: Int = 4,
        tags: [TagData] = [],
        directories: [String] = [],
        directProjectPaths: [String] = [],
        recycleBin: [String] = [],
        favoriteProjectPaths: [String] = [],
        settings: AppSettings = .init()
    ) {
        self.version = version
        self.tags = tags
        self.directories = directories
        self.directProjectPaths = directProjectPaths
        self.recycleBin = recycleBin
        self.favoriteProjectPaths = favoriteProjectPaths
        self.settings = settings
    }

    enum CodingKeys: String, CodingKey {
        case version
        case tags
        case directories
        case directProjectPaths
        case recycleBin
        case favoriteProjectPaths
        case settings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 4
        self.tags = try container.decodeIfPresent([TagData].self, forKey: .tags) ?? []
        self.directories = try container.decodeIfPresent([String].self, forKey: .directories) ?? []
        self.directProjectPaths = try container.decodeIfPresent([String].self, forKey: .directProjectPaths) ?? []
        self.recycleBin = try container.decodeIfPresent([String].self, forKey: .recycleBin) ?? []
        self.favoriteProjectPaths = try container.decodeIfPresent([String].self, forKey: .favoriteProjectPaths) ?? []
        self.settings = try container.decodeIfPresent(AppSettings.self, forKey: .settings) ?? .init()
    }
}

public enum ScriptParamFieldType: String, Codable, Equatable, Sendable {
    case text
    case number
    case secret
}

public struct ScriptParamField: Codable, Equatable, Sendable, Identifiable {
    public var id: String { key }
    public var key: String
    public var label: String
    public var type: ScriptParamFieldType
    public var required: Bool
    public var defaultValue: String?
    public var description: String?

    public init(key: String, label: String, type: ScriptParamFieldType, required: Bool, defaultValue: String? = nil, description: String? = nil) {
        self.key = key
        self.label = label
        self.type = type
        self.required = required
        self.defaultValue = defaultValue
        self.description = description
    }
}

private struct LegacyProjectScript: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var start: String
    var paramSchema: [ScriptParamField]
    var templateParams: [String: String]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case start
        case paramSchema
        case templateParams
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.start = try container.decode(String.self, forKey: .start)
        self.paramSchema = try container.decodeIfPresent([ScriptParamField].self, forKey: .paramSchema) ?? []
        self.templateParams = try container.decodeIfPresent([String: String].self, forKey: .templateParams) ?? [:]
    }
}

public enum ProjectRunConfigurationKind: String, Codable, Equatable, Sendable {
    case customShell
    case remoteLogViewer
}

public struct ProjectRunCustomShellConfiguration: Codable, Equatable, Sendable {
    public var command: String

    public init(command: String) {
        self.command = command
    }
}

public struct ProjectRunRemoteLogViewerConfiguration: Codable, Equatable, Sendable {
    public var server: String
    public var logPath: String
    public var user: String?
    public var port: Int?
    public var identityFile: String?
    public var lines: Int?
    public var follow: Bool
    public var strictHostKeyChecking: String?
    public var allowPasswordPrompt: Bool

    public init(
        server: String,
        logPath: String,
        user: String? = nil,
        port: Int? = 22,
        identityFile: String? = nil,
        lines: Int? = 200,
        follow: Bool = true,
        strictHostKeyChecking: String? = "accept-new",
        allowPasswordPrompt: Bool = false
    ) {
        self.server = server
        self.logPath = logPath
        self.user = user
        self.port = port
        self.identityFile = identityFile
        self.lines = lines
        self.follow = follow
        self.strictHostKeyChecking = strictHostKeyChecking
        self.allowPasswordPrompt = allowPasswordPrompt
    }
}

public struct ProjectRunConfiguration: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var kind: ProjectRunConfigurationKind
    public var customShell: ProjectRunCustomShellConfiguration?
    public var remoteLogViewer: ProjectRunRemoteLogViewerConfiguration?

    public init(
        id: String,
        name: String,
        kind: ProjectRunConfigurationKind,
        customShell: ProjectRunCustomShellConfiguration? = nil,
        remoteLogViewer: ProjectRunRemoteLogViewerConfiguration? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.customShell = customShell
        self.remoteLogViewer = remoteLogViewer
    }

    public init(id: String, name: String, command: String) {
        self.init(
            id: id,
            name: name,
            kind: .customShell,
            customShell: ProjectRunCustomShellConfiguration(command: command)
        )
    }

    fileprivate static func fromLegacyProjectScript(_ script: LegacyProjectScript) -> ProjectRunConfiguration {
        let resolution = ScriptTemplateSupport.resolveCommand(
            template: script.start,
            paramSchema: script.paramSchema,
            explicitValues: script.templateParams
        )
        return ProjectRunConfiguration(
            id: script.id,
            name: script.name,
            kind: .customShell,
            customShell: ProjectRunCustomShellConfiguration(command: resolution.command)
        )
    }
}

public struct ProjectWorktree: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var path: String
    public var branch: String
    public var baseBranch: String?
    public var inheritConfig: Bool
    public var created: SwiftDate
    public var status: String?
    public var initStep: String?
    public var initMessage: String?
    public var initError: String?
    public var initJobId: String?
    public var updatedAt: SwiftDate?

    public init(
        id: String,
        name: String,
        path: String,
        branch: String,
        baseBranch: String? = nil,
        inheritConfig: Bool,
        created: SwiftDate,
        status: String? = nil,
        initStep: String? = nil,
        initMessage: String? = nil,
        initError: String? = nil,
        initJobId: String? = nil,
        updatedAt: SwiftDate? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.branch = branch
        self.baseBranch = baseBranch
        self.inheritConfig = inheritConfig
        self.created = created
        self.status = status
        self.initStep = initStep
        self.initMessage = initMessage
        self.initError = initError
        self.initJobId = initJobId
        self.updatedAt = updatedAt
    }
}

public struct Project: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var path: String
    public var tags: [String]
    public var runConfigurations: [ProjectRunConfiguration]
    public var worktrees: [ProjectWorktree]
    public var mtime: SwiftDate
    public var size: Int64
    public var checksum: String
    public var isGitRepository: Bool
    public var gitCommits: Int
    public var gitLastCommit: SwiftDate
    public var gitLastCommitMessage: String?
    public var gitDaily: String?
    public var created: SwiftDate
    public var checked: SwiftDate

    public init(
        id: String,
        name: String,
        path: String,
        tags: [String],
        runConfigurations: [ProjectRunConfiguration],
        worktrees: [ProjectWorktree],
        mtime: SwiftDate,
        size: Int64,
        checksum: String,
        isGitRepository: Bool = false,
        gitCommits: Int,
        gitLastCommit: SwiftDate,
        gitLastCommitMessage: String? = nil,
        gitDaily: String? = nil,
        created: SwiftDate,
        checked: SwiftDate
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.tags = tags
        self.runConfigurations = runConfigurations
        self.worktrees = worktrees
        self.mtime = mtime
        self.size = size
        self.checksum = checksum
        self.isGitRepository = isGitRepository
        self.gitCommits = gitCommits
        self.gitLastCommit = gitLastCommit
        self.gitLastCommitMessage = gitLastCommitMessage
        self.gitDaily = gitDaily
        self.created = created
        self.checked = checked
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case tags
        case runConfigurations
        case worktrees
        case mtime
        case size
        case checksum
        case isGitRepository = "is_git_repository"
        case gitCommits = "git_commits"
        case gitLastCommit = "git_last_commit"
        case gitLastCommitMessage = "git_last_commit_message"
        case gitDaily = "git_daily"
        case created
        case checked
    }

    enum LegacyCodingKeys: String, CodingKey {
        case scripts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.path = try container.decode(String.self, forKey: .path)
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        if let decodedRunConfigurations = try? container.decode([ProjectRunConfiguration].self, forKey: .runConfigurations) {
            self.runConfigurations = decodedRunConfigurations
        } else {
            let legacyScripts = try legacyContainer.decodeIfPresent([LegacyProjectScript].self, forKey: .scripts) ?? []
            self.runConfigurations = legacyScripts.map(ProjectRunConfiguration.fromLegacyProjectScript)
        }
        self.worktrees = try container.decodeIfPresent([ProjectWorktree].self, forKey: .worktrees) ?? []
        self.mtime = try container.decodeIfPresent(SwiftDate.self, forKey: .mtime) ?? .zero
        self.size = try container.decodeIfPresent(Int64.self, forKey: .size) ?? .zero
        self.checksum = try container.decodeIfPresent(String.self, forKey: .checksum) ?? ""
        let decodedGitCommits = try container.decodeIfPresent(Int.self, forKey: .gitCommits) ?? .zero
        let decodedGitLastCommit = try container.decodeIfPresent(SwiftDate.self, forKey: .gitLastCommit) ?? .zero
        let decodedGitLastCommitMessage = try container.decodeIfPresent(String.self, forKey: .gitLastCommitMessage)
        let decodedGitDaily = try container.decodeIfPresent(String.self, forKey: .gitDaily)
        self.isGitRepository = (try container.decodeIfPresent(Bool.self, forKey: .isGitRepository))
            ?? (decodedGitCommits > 0
            || decodedGitLastCommit != .zero
            || decodedGitLastCommitMessage != nil
            || decodedGitDaily != nil)
        self.gitCommits = decodedGitCommits
        self.gitLastCommit = decodedGitLastCommit
        self.gitLastCommitMessage = decodedGitLastCommitMessage
        self.gitDaily = decodedGitDaily
        self.created = try container.decodeIfPresent(SwiftDate.self, forKey: .created) ?? .zero
        self.checked = try container.decodeIfPresent(SwiftDate.self, forKey: .checked) ?? .zero
    }
}

public struct MarkdownDocument: Equatable, Sendable {
    public var path: String
    public var content: String

    public init(path: String, content: String) {
        self.path = path
        self.content = content
    }
}

extension Project {
    public static let quickTerminalID = "__devhaven_quick_terminal__"

    public var isQuickTerminal: Bool {
        id == Self.quickTerminalID
    }

    public static func quickTerminal(at homePath: String) -> Project {
        Project(
            id: Self.quickTerminalID,
            name: "快速终端",
            path: homePath,
            tags: [],
            runConfigurations: [],
            worktrees: [],
            mtime: 0,
            size: 0,
            checksum: "",
            gitCommits: 0,
            gitLastCommit: 0,
            created: 0,
            checked: 0
        )
    }
}

public struct ProjectDocumentSnapshot: Equatable, Sendable {
    public var notes: String?
    public var todoItems: [TodoItem]
    public var readmeFallback: MarkdownDocument?

    public init(notes: String?, todoItems: [TodoItem], readmeFallback: MarkdownDocument?) {
        self.notes = notes
        self.todoItems = todoItems
        self.readmeFallback = readmeFallback
    }
}

public struct NativeAppSnapshot: Equatable, Sendable {
    public var appState: AppStateFile
    public var projects: [Project]

    public init(appState: AppStateFile = .init(), projects: [Project] = []) {
        self.appState = appState
        self.projects = projects
    }
}

private let appleReferenceEpoch = Date(timeIntervalSince1970: 978_307_200)

public func swiftDateToDate(_ swiftDate: SwiftDate) -> Date? {
    guard swiftDate != .zero else {
        return nil
    }
    return appleReferenceEpoch.addingTimeInterval(swiftDate)
}

public func formatSwiftDate(_ swiftDate: SwiftDate) -> String {
    guard let date = swiftDateToDate(swiftDate) else {
        return "--"
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}
