import Foundation
import GhosttyKit

@MainActor
final class GhosttyAppRuntime {
    static let shared = GhosttyAppRuntime()
    static let resourceBundleName = "DevHavenNative_DevHavenApp.bundle"

    let resourcesDirectoryURL: URL?
    private(set) var initializationError: String?

    private var didBootstrap = false
    private var sharedRuntime: GhosttyRuntime?

    private init(bundle: Bundle? = nil) {
        let resolvedBundle = bundle ?? Self.resolveResourceBundle()
        let rootURL = resolvedBundle?.resourceURL?.appending(path: "GhosttyResources", directoryHint: .isDirectory)
        let resourcesURL = rootURL?.appending(path: "ghostty", directoryHint: .isDirectory)
        if let resourcesURL, FileManager.default.fileExists(atPath: resourcesURL.path) {
            self.resourcesDirectoryURL = resourcesURL
        } else {
            self.resourcesDirectoryURL = nil
            self.initializationError = "未在应用 bundle 中找到 GhosttyResources/ghostty。"
        }
    }

    static func resolveResourceBundleURL(
        fileManager: FileManager = .default,
        mainBundle: Bundle = .main
    ) -> URL? {
        let candidates = candidateResourceBundleURLs(mainBundle: mainBundle)
            + Bundle.allBundles.flatMap(candidateResourceBundleURLs(mainBundle:))
            + Bundle.allFrameworks.flatMap(candidateResourceBundleURLs(mainBundle:))
        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    static func resolveResourceBundle(mainBundle: Bundle = .main) -> Bundle? {
        guard let bundleURL = resolveResourceBundleURL(mainBundle: mainBundle) else {
            return nil
        }
        return Bundle(url: bundleURL)
    }

    static func candidateResourceBundleURLs(mainBundle: Bundle = .main) -> [URL] {
        var candidates: [URL] = []
        if let resourceURL = mainBundle.resourceURL {
            candidates.append(resourceURL.appending(path: resourceBundleName, directoryHint: .isDirectory))
        }
        candidates.append(mainBundle.bundleURL.appending(path: resourceBundleName, directoryHint: .isDirectory))
        candidates.append(mainBundle.bundleURL.deletingLastPathComponent().appending(path: resourceBundleName, directoryHint: .isDirectory))
        return candidates.uniquedByPath()
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

private extension Array where Element == URL {
    func uniquedByPath() -> [URL] {
        var seen = Set<String>()
        return filter { seen.insert($0.path).inserted }
    }
}
