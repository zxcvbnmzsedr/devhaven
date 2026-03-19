import SwiftUI
import DevHavenCore

struct WorkspaceTerminalPaneView: View {
    let request: WorkspaceTerminalLaunchRequest

    var body: some View {
        GhosttySurfaceHost(request: request)
    }
}
