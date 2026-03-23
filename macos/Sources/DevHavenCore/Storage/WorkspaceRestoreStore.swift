import Foundation

public final class WorkspaceRestoreStore {
    public typealias ManifestWriter = (Data, URL) throws -> Void

    private let homeDirectoryURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let manifestWriter: ManifestWriter

    public init(
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        manifestWriter: @escaping ManifestWriter = { data, url in
            try data.write(to: url, options: .atomic)
        }
    ) {
        self.homeDirectoryURL = homeDirectoryURL
        self.fileManager = fileManager
        self.manifestWriter = manifestWriter
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func loadSnapshot() -> WorkspaceRestoreSnapshot? {
        if let snapshot = loadSnapshot(from: manifestFileURL) {
            return snapshot
        }
        return loadSnapshot(from: previousManifestFileURL)
    }

    public func saveSnapshot(_ snapshot: WorkspaceRestoreSnapshot) throws {
        try fileManager.createDirectory(at: restoreDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: panesDirectoryURL, withIntermediateDirectories: true)

        let primarySnapshotBeforeSave = loadSnapshot(from: manifestFileURL)
        let previousSnapshotBeforeSave = loadSnapshot(from: previousManifestFileURL)

        var persistedSnapshot = snapshot
        persistedSnapshot.savedAt = Date()
        persistedSnapshot = assignFreshTextRefs(in: persistedSnapshot, generationID: UUID().uuidString)

        try writePaneTexts(from: persistedSnapshot)

        if let primarySnapshotBeforeSave {
            try writeManifest(primarySnapshotBeforeSave, to: previousManifestFileURL)
        }

        try writeManifest(persistedSnapshot, to: manifestFileURL)

        let retainedPreviousSnapshot = primarySnapshotBeforeSave ?? previousSnapshotBeforeSave
        let retainedFileNames = paneTextFileNames(in: persistedSnapshot)
            .union(paneTextFileNames(in: retainedPreviousSnapshot))
        try pruneObsoletePaneTextFiles(keeping: retainedFileNames)
    }

    public func removeSnapshot() throws {
        guard fileManager.fileExists(atPath: restoreDirectoryURL.path) else {
            return
        }
        try fileManager.removeItem(at: restoreDirectoryURL)
    }

    public func loadPaneText(for ref: WorkspacePaneSnapshotTextRef?) -> String? {
        guard let ref else {
            return nil
        }
        guard let text = try? String(contentsOf: paneTextFileURL(for: ref), encoding: .utf8) else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : text
    }

    private func loadSnapshot(from fileURL: URL) -> WorkspaceRestoreSnapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? decoder.decode(WorkspaceRestoreSnapshot.self, from: data),
              snapshot.version == WorkspaceRestoreSnapshot.currentVersion,
              !snapshot.sessions.isEmpty
        else {
            return nil
        }
        return snapshot
    }

    private func assignFreshTextRefs(in snapshot: WorkspaceRestoreSnapshot, generationID: String) -> WorkspaceRestoreSnapshot {
        var snapshot = snapshot
        snapshot.sessions = snapshot.sessions.map { session in
            var session = session
            session.tabs = session.tabs.map { tab in
                var tab = tab
                tab.tree = WorkspacePaneTreeRestoreSnapshot(
                    root: assignFreshTextRefs(in: tab.tree.root, generationID: generationID),
                    zoomedPaneId: tab.tree.zoomedPaneId
                )
                return tab
            }
            return session
        }
        return snapshot
    }

    private func assignFreshTextRefs(
        in node: WorkspacePaneTreeRestoreSnapshot.Node,
        generationID: String
    ) -> WorkspacePaneTreeRestoreSnapshot.Node {
        switch node {
        case let .leaf(pane):
            var pane = pane
            if pane.snapshotText != nil {
                pane.snapshotTextRef = .forPaneSnapshot(pane.paneId, generationID: generationID)
            } else {
                pane.snapshotTextRef = nil
            }
            return .leaf(pane)
        case let .split(split):
            return .split(
                WorkspaceSplitRestoreSnapshot(
                    direction: split.direction,
                    ratio: split.ratio,
                    left: assignFreshTextRefs(in: split.left, generationID: generationID),
                    right: assignFreshTextRefs(in: split.right, generationID: generationID)
                )
            )
        }
    }

    private func writePaneTexts(from snapshot: WorkspaceRestoreSnapshot) throws {
        for pane in snapshot.sessions.flatMap(\.tabs).flatMap(\.tree.leaves) {
            guard let ref = pane.snapshotTextRef else {
                continue
            }
            guard let text = pane.snapshotText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                continue
            }
            try text.write(to: paneTextFileURL(for: ref), atomically: true, encoding: .utf8)
        }
    }

    private func pruneObsoletePaneTextFiles(keeping expectedFileNames: Set<String>) throws {
        guard fileManager.fileExists(atPath: panesDirectoryURL.path) else {
            return
        }
        for fileURL in try fileManager.contentsOfDirectory(at: panesDirectoryURL, includingPropertiesForKeys: nil) {
            guard !expectedFileNames.contains(fileURL.lastPathComponent) else {
                continue
            }
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private func paneTextFileURL(for ref: WorkspacePaneSnapshotTextRef) -> URL {
        panesDirectoryURL.appending(path: textFileName(for: ref), directoryHint: .notDirectory)
    }

    private func textFileName(for ref: WorkspacePaneSnapshotTextRef) -> String {
        "\(ref.storageKey).txt"
    }

    private func paneTextFileNames(in snapshot: WorkspaceRestoreSnapshot?) -> Set<String> {
        guard let snapshot else {
            return []
        }
        return Set(
            snapshot.sessions
                .flatMap(\.tabs)
                .flatMap(\.tree.leaves)
                .compactMap { $0.snapshotTextRef.map(textFileName(for:)) }
        )
    }

    private func writeManifest(_ snapshot: WorkspaceRestoreSnapshot, to fileURL: URL) throws {
        let data = try encoder.encode(snapshot)
        try manifestWriter(data, fileURL)
    }

    private var restoreDirectoryURL: URL {
        homeDirectoryURL
            .appending(path: ".devhaven", directoryHint: .isDirectory)
            .appending(path: "session-restore", directoryHint: .isDirectory)
    }

    private var panesDirectoryURL: URL {
        restoreDirectoryURL.appending(path: "panes", directoryHint: .isDirectory)
    }

    private var manifestFileURL: URL {
        restoreDirectoryURL.appending(path: "manifest.json", directoryHint: .notDirectory)
    }

    private var previousManifestFileURL: URL {
        restoreDirectoryURL.appending(path: "manifest.prev.json", directoryHint: .notDirectory)
    }
}
