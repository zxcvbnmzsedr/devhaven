import Darwin
import SwiftUI

/// cmux re-executes the host binary for paste preparation. Route the worker
/// before constructing any SwiftUI App state, windows, or restore coordinators.
@main
enum DevHavenMain {
    @MainActor
    static func main() {
        if let status = CmuxEmbeddedWorkerBootstrap.exitCodeIfRequested(arguments: CommandLine.arguments) {
            exit(status)
        }
        DevHavenApp.main()
    }
}
