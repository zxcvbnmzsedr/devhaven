import Foundation
import GhosttyKit

@MainActor
final class GhosttyAppRuntime {
    static let shared = GhosttyAppRuntime()

    let resourcesDirectoryURL: URL?
    private(set) var initializationError: String?

    private var didBootstrap = false
    private var sharedRuntime: GhosttyRuntime?

    private init(bundle: Bundle = .module) {
        let rootURL = bundle.resourceURL?.appending(path: "GhosttyResources", directoryHint: .isDirectory)
        let resourcesURL = rootURL?.appending(path: "ghostty", directoryHint: .isDirectory)
        if let resourcesURL, FileManager.default.fileExists(atPath: resourcesURL.path) {
            self.resourcesDirectoryURL = resourcesURL
        } else {
            self.resourcesDirectoryURL = nil
            self.initializationError = "未在应用 bundle 中找到 GhosttyResources/ghostty。"
        }
    }

    var runtime: GhosttyRuntime? {
        if let sharedRuntime {
            initializationError = sharedRuntime.initializationError
            return sharedRuntime
        }

        if let error = bootstrapIfNeeded() {
            initializationError = error
            return nil
        }

        let runtime = GhosttyRuntime()
        sharedRuntime = runtime
        initializationError = runtime.initializationError
        return runtime
    }

    @discardableResult
    func bootstrapIfNeeded() -> String? {
        if let initializationError, !didBootstrap {
            return initializationError
        }

        guard !didBootstrap else {
            return nil
        }

        guard let resourcesDirectoryURL else {
            let error = initializationError ?? "未在应用 bundle 中找到 GhosttyResources/ghostty。"
            initializationError = error
            return error
        }

        setenv("GHOSTTY_RESOURCES_DIR", resourcesDirectoryURL.path, 1)

        let result = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        guard result == GHOSTTY_SUCCESS else {
            let error = "ghostty_init 失败（code=\(result)）。"
            initializationError = error
            return error
        }

        didBootstrap = true
        initializationError = nil
        return nil
    }
}
