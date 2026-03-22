import Foundation

enum DevHavenAppResourceBundleLocator {
    static let resourceBundleName = "DevHavenNative_DevHavenApp.bundle"

    static func resolveResourceBundleURL(
        fileManager: FileManager = .default,
        mainBundle: Bundle = .main,
        allBundles: [Bundle] = Bundle.allBundles,
        allFrameworks: [Bundle] = Bundle.allFrameworks
    ) -> URL? {
        let candidates = candidateResourceBundleURLs(mainBundle: mainBundle)
            + allBundles.flatMap(candidateResourceBundleURLs(mainBundle:))
            + allFrameworks.flatMap(candidateResourceBundleURLs(mainBundle:))
        return candidates.uniquedByPath().first { fileManager.fileExists(atPath: $0.path) }
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
}

enum DevHavenAppResourceLocator {
    static let resourceBundleName = DevHavenAppResourceBundleLocator.resourceBundleName

    static func resolveAgentResourcesURL(
        fileManager: FileManager = .default,
        mainBundle: Bundle = .main,
        allBundles: [Bundle] = Bundle.allBundles,
        allFrameworks: [Bundle] = Bundle.allFrameworks
    ) -> URL? {
        let bundleURLs = DevHavenAppResourceBundleLocator.candidateResourceBundleURLs(mainBundle: mainBundle)
            + allBundles.flatMap(DevHavenAppResourceBundleLocator.candidateResourceBundleURLs(mainBundle:))
            + allFrameworks.flatMap(DevHavenAppResourceBundleLocator.candidateResourceBundleURLs(mainBundle:))

        return bundleURLs.uniquedByPath()
            .map { $0.appending(path: "AgentResources", directoryHint: .isDirectory) }
            .first { fileManager.fileExists(atPath: $0.path) }
    }
}

private extension Array where Element == URL {
    func uniquedByPath() -> [URL] {
        var seenPaths = Set<String>()
        return filter { seenPaths.insert($0.path).inserted }
    }
}
