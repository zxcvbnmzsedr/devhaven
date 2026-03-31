import Foundation

public final class WorkspaceRunLogStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let baseDirectoryURL: URL
    private let writeQueue = DispatchQueue(label: "DevHavenCore.WorkspaceRunLogStore")
    private var openFileHandlesByPath = [String: FileHandle]()

    public init(baseDirectoryURL: URL, fileManager: FileManager = .default) {
        self.baseDirectoryURL = baseDirectoryURL
        self.fileManager = fileManager
    }

    deinit {
        writeQueue.sync {
            closeAllHandlesLocked()
        }
    }

    public func createLogFile(scriptName: String, sessionID: String, date: Date = Date()) throws -> URL {
        let directoryURL = logsDirectoryURL
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: date)
        let safeScriptName = sanitizeComponent(scriptName)
        let safeSessionID = sanitizeComponent(sessionID)
        let fileURL = directoryURL.appending(path: "\(timestamp)-\(safeScriptName)-\(safeSessionID).log")
        fileManager.createFile(atPath: fileURL.path, contents: Data())
        return fileURL
    }

    public func append(_ chunk: String, to fileURL: URL) throws {
        try writeQueue.sync {
            let data = Data(chunk.utf8)
            let handle = try fileHandle(for: fileURL)
            try handle.write(contentsOf: data)
        }
    }

    public func closeLogFile(at fileURL: URL) {
        writeQueue.sync {
            closeHandleLocked(forPath: fileURL.path)
        }
    }

    private var logsDirectoryURL: URL {
        baseDirectoryURL
            .appending(path: ".devhaven", directoryHint: .isDirectory)
            .appending(path: "run-logs", directoryHint: .isDirectory)
    }

    private func sanitizeComponent(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let value = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return value.isEmpty ? "run" : value
    }

    private func fileHandle(for fileURL: URL) throws -> FileHandle {
        let path = fileURL.path
        if let handle = openFileHandlesByPath[path] {
            return handle
        }

        if !fileManager.fileExists(atPath: path) {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            fileManager.createFile(atPath: path, contents: Data())
        }

        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()
        openFileHandlesByPath[path] = handle
        return handle
    }

    private func closeHandleLocked(forPath path: String) {
        guard let handle = openFileHandlesByPath.removeValue(forKey: path) else {
            return
        }
        try? handle.synchronize()
        try? handle.close()
    }

    private func closeAllHandlesLocked() {
        for path in openFileHandlesByPath.keys {
            closeHandleLocked(forPath: path)
        }
    }
}
