import Darwin

enum CmuxEmbeddedWorkerBootstrap {
    static let pasteWorkerArgument = "--cmux-paste-preparation-worker"

    /// A missing worker implementation must fail locally, never fall through
    /// to normal app startup and open a second DevHaven window.
    static func exitCodeIfRequested(
        arguments: [String],
        runWorker: () -> Int32? = runPasteWorker
    ) -> Int32? {
        guard arguments.dropFirst().contains(pasteWorkerArgument) else { return nil }
        return runWorker() ?? 78 // EX_CONFIG: incompatible/missing embedded framework.
    }

    private static func runPasteWorker() -> Int32? {
        typealias WorkerFunction = @convention(c) () -> Int32
        guard let handle = dlopen("@rpath/CmuxEmbedded.framework/CmuxEmbedded", RTLD_NOW) else { return nil }
        // Keep Swift code loaded until process exit; the worker owns dispatch
        // sources whose cancellation handlers can still be completing.
        guard let address = dlsym(handle, "cmux_embedded_run_paste_preparation_worker") else { return nil }
        return unsafeBitCast(address, to: WorkerFunction.self)()
    }
}
