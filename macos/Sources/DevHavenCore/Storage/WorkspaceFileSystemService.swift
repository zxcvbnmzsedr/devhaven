import Foundation

public struct WorkspaceFileSystemService: Sendable {
    public static let maxEditableFileSizeBytes = 2_000_000

    public init() {}

    public func listDirectory(at directoryPath: String) throws -> [WorkspaceProjectTreeNode] {
        let normalizedPath = normalizeWorkspaceFileSystemPath(directoryPath)
        let directoryURL = URL(fileURLWithPath: normalizedPath, isDirectory: true)
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isRegularFileKey,
        ]
        let entries = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        )

        return entries
            .filter { $0.lastPathComponent != ".git" }
            .compactMap { entryURL in
                guard let values = try? entryURL.resourceValues(forKeys: Set(keys)) else {
                    return nil
                }
                let kind: WorkspaceProjectTreeNodeKind
                if values.isSymbolicLink == true {
                    kind = .symlink
                } else if values.isDirectory == true {
                    kind = .directory
                } else {
                    kind = .file
                }
                return WorkspaceProjectTreeNode(
                    path: entryURL.standardizedFileURL.path,
                    parentPath: normalizedPath,
                    name: entryURL.lastPathComponent,
                    kind: kind,
                    isHidden: entryURL.lastPathComponent.hasPrefix(".")
                )
            }
            .sorted(by: workspaceProjectTreeNodeComparator)
    }

    public func loadDocument(at filePath: String) throws -> WorkspaceEditorDocumentSnapshot {
        let normalizedPath = normalizeWorkspaceFileSystemPath(filePath)
        let fileURL = URL(fileURLWithPath: normalizedPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
            return WorkspaceEditorDocumentSnapshot(
                filePath: normalizedPath,
                kind: .missing,
                isEditable: false,
                message: "文件不存在"
            )
        }
        guard !isDirectory.boolValue else {
            return WorkspaceEditorDocumentSnapshot(
                filePath: normalizedPath,
                kind: .unsupported,
                isEditable: false,
                message: "目录不能直接在编辑器中打开"
            )
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        if fileSize > Self.maxEditableFileSizeBytes {
            return WorkspaceEditorDocumentSnapshot(
                filePath: normalizedPath,
                kind: .unsupported,
                isEditable: false,
                message: "文件过大，基础版本暂不支持直接编辑"
            )
        }

        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        if data.contains(0) {
            return WorkspaceEditorDocumentSnapshot(
                filePath: normalizedPath,
                kind: .binary,
                isEditable: false,
                message: "基础版本暂不支持二进制文件预览"
            )
        }

        guard let text = String(data: data, encoding: .utf8) else {
            return WorkspaceEditorDocumentSnapshot(
                filePath: normalizedPath,
                kind: .unsupported,
                isEditable: false,
                message: "基础版本当前仅支持 UTF-8 文本文件"
            )
        }

        let modificationDate = (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate
        return WorkspaceEditorDocumentSnapshot(
            filePath: normalizedPath,
            kind: .text,
            text: text,
            isEditable: true,
            modificationDate: modificationDate
        )
    }

    public func saveTextDocument(_ text: String, to filePath: String) throws -> WorkspaceEditorDocumentSnapshot {
        let normalizedPath = normalizeWorkspaceFileSystemPath(filePath)
        let fileURL = URL(fileURLWithPath: normalizedPath)
        let parentURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true, attributes: nil)
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
        return try loadDocument(at: normalizedPath)
    }

    @discardableResult
    public func createFile(
        named name: String,
        inDirectory directoryPath: String
    ) throws -> WorkspaceProjectTreeNode {
        let normalizedDirectoryPath = normalizeWorkspaceFileSystemPath(directoryPath)
        let sanitizedName = try sanitizeFileSystemName(name)
        let fileURL = URL(fileURLWithPath: normalizedDirectoryPath, isDirectory: true)
            .appendingPathComponent(sanitizedName, isDirectory: false)
        try ensureTargetDoesNotExist(fileURL.path)
        let created = FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        guard created else {
            throw WorkspaceFileSystemError.writeFailed("创建文件失败：\(sanitizedName)")
        }
        return try makeNode(at: fileURL, parentPath: normalizedDirectoryPath)
    }

    @discardableResult
    public func createDirectory(
        named name: String,
        inDirectory directoryPath: String
    ) throws -> WorkspaceProjectTreeNode {
        let normalizedDirectoryPath = normalizeWorkspaceFileSystemPath(directoryPath)
        let sanitizedName = try sanitizeFileSystemName(name)
        let directoryURL = URL(fileURLWithPath: normalizedDirectoryPath, isDirectory: true)
            .appendingPathComponent(sanitizedName, isDirectory: true)
        try ensureTargetDoesNotExist(directoryURL.path)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: false, attributes: nil)
        return try makeNode(at: directoryURL, parentPath: normalizedDirectoryPath)
    }

    @discardableResult
    public func renameItem(
        at sourcePath: String,
        to newName: String
    ) throws -> WorkspaceProjectTreeNode {
        let normalizedSourcePath = normalizeWorkspaceFileSystemPath(sourcePath)
        let sanitizedName = try sanitizeFileSystemName(newName)
        let sourceURL = URL(fileURLWithPath: normalizedSourcePath)
        let destinationURL = sourceURL.deletingLastPathComponent()
            .appendingPathComponent(sanitizedName, isDirectory: false)
        let normalizedDestinationPath = destinationURL.standardizedFileURL.path

        guard normalizedSourcePath != normalizedDestinationPath else {
            let parentPath = sourceURL.deletingLastPathComponent().path
            return try makeNode(at: sourceURL, parentPath: parentPath)
        }

        try ensureTargetDoesNotExist(normalizedDestinationPath)
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        return try makeNode(at: destinationURL, parentPath: destinationURL.deletingLastPathComponent().path)
    }

    public func trashItem(at path: String) throws {
        let normalizedPath = normalizeWorkspaceFileSystemPath(path)
        let itemURL = URL(fileURLWithPath: normalizedPath)
        var trashedURL: NSURL?
        try FileManager.default.trashItem(at: itemURL, resultingItemURL: &trashedURL)
    }

    public func directoryExists(at directoryPath: String) -> Bool {
        let normalizedPath = normalizeWorkspaceFileSystemPath(directoryPath)
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: normalizedPath, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    public func parentDirectoryPath(for path: String) -> String {
        URL(fileURLWithPath: normalizeWorkspaceFileSystemPath(path))
            .deletingLastPathComponent()
            .path
    }

    public func itemExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: normalizeWorkspaceFileSystemPath(path))
    }

    public func itemKind(at path: String) -> WorkspaceProjectTreeNodeKind? {
        let url = URL(fileURLWithPath: normalizeWorkspaceFileSystemPath(path))
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return nil
        }
        if values.isSymbolicLink == true {
            return .symlink
        }
        if values.isDirectory == true {
            return .directory
        }
        return .file
    }

    public func itemDisplayName(at path: String) -> String {
        URL(fileURLWithPath: normalizeWorkspaceFileSystemPath(path)).lastPathComponent
    }

    public func modificationDate(at path: String) -> SwiftDate? {
        let normalizedPath = normalizeWorkspaceFileSystemPath(path)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: normalizedPath),
              let modificationDate = attributes[.modificationDate] as? Date
        else {
            return nil
        }
        return modificationDate.timeIntervalSinceReferenceDate
    }

    private func sanitizeFileSystemName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw WorkspaceFileSystemError.invalidName("名称不能为空")
        }
        guard !trimmed.contains("/") else {
            throw WorkspaceFileSystemError.invalidName("名称不能包含 /")
        }
        guard trimmed != "." && trimmed != ".." else {
            throw WorkspaceFileSystemError.invalidName("名称不合法")
        }
        return trimmed
    }

    private func ensureTargetDoesNotExist(_ path: String) throws {
        guard !itemExists(at: path) else {
            throw WorkspaceFileSystemError.itemAlreadyExists("目标已存在：\(URL(fileURLWithPath: path).lastPathComponent)")
        }
    }

    private func makeNode(at url: URL, parentPath: String?) throws -> WorkspaceProjectTreeNode {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let values = try url.resourceValues(forKeys: keys)
        let kind: WorkspaceProjectTreeNodeKind
        if values.isSymbolicLink == true {
            kind = .symlink
        } else if values.isDirectory == true {
            kind = .directory
        } else {
            kind = .file
        }

        return WorkspaceProjectTreeNode(
            path: url.standardizedFileURL.path,
            parentPath: parentPath,
            name: url.lastPathComponent,
            kind: kind,
            isHidden: url.lastPathComponent.hasPrefix(".")
        )
    }
}

public enum WorkspaceFileSystemError: LocalizedError {
    case invalidName(String)
    case itemAlreadyExists(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidName(message),
             let .itemAlreadyExists(message),
             let .writeFailed(message):
            return message
        }
    }
}

private func workspaceProjectTreeNodeComparator(
    lhs: WorkspaceProjectTreeNode,
    rhs: WorkspaceProjectTreeNode
) -> Bool {
    if lhs.isDirectory != rhs.isDirectory {
        return lhs.isDirectory && !rhs.isDirectory
    }
    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
}

private func normalizeWorkspaceFileSystemPath(_ path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.path
}
