import Foundation

public struct SharedScriptEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var absolutePath: String
    public var relativePath: String
    public var commandTemplate: String
    public var params: [ScriptParamField]

    public init(
        id: String,
        name: String,
        absolutePath: String,
        relativePath: String,
        commandTemplate: String,
        params: [ScriptParamField]
    ) {
        self.id = id
        self.name = name
        self.absolutePath = absolutePath
        self.relativePath = relativePath
        self.commandTemplate = commandTemplate
        self.params = params
    }
}

public struct SharedScriptManifestScript: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var path: String
    public var commandTemplate: String
    public var params: [ScriptParamField]

    public init(
        id: String,
        name: String,
        path: String,
        commandTemplate: String,
        params: [ScriptParamField]
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.commandTemplate = commandTemplate
        self.params = params
    }
}

public struct SharedScriptPresetRestoreResult: Codable, Equatable, Sendable {
    public var presetVersion: String
    public var addedScripts: Int
    public var skippedScripts: Int
    public var createdFiles: Int

    public init(presetVersion: String, addedScripts: Int, skippedScripts: Int, createdFiles: Int) {
        self.presetVersion = presetVersion
        self.addedScripts = addedScripts
        self.skippedScripts = skippedScripts
        self.createdFiles = createdFiles
    }
}

public struct GitDailyRefreshResult: Equatable, Sendable {
    public var path: String
    public var gitDaily: String?
    public var gitCommits: Int?
    public var gitLastCommit: SwiftDate?
    public var gitLastCommitMessage: String?
    public var error: String?

    public init(
        path: String,
        gitDaily: String?,
        gitCommits: Int? = nil,
        gitLastCommit: SwiftDate? = nil,
        gitLastCommitMessage: String? = nil,
        error: String?
    ) {
        self.path = path
        self.gitDaily = gitDaily
        self.gitCommits = gitCommits
        self.gitLastCommit = gitLastCommit
        self.gitLastCommitMessage = gitLastCommitMessage
        self.error = error
    }
}
