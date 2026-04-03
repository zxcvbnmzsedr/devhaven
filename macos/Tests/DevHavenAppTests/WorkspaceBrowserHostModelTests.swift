import XCTest
@testable import DevHavenApp
@testable import DevHavenCore

@MainActor
final class WorkspaceBrowserHostModelTests: XCTestCase {
    func testSyncDoesNotRepublishIdenticalSnapshot() {
        let state = WorkspaceBrowserState(
            surfaceId: "surface:browser-test",
            projectPath: "/tmp/browser-host-model",
            tabId: "tab:test",
            paneId: "pane:test",
            title: "浏览器",
            urlString: "",
            isLoading: false
        )
        let model = WorkspaceBrowserHostModel(state: state)

        var snapshots: [WorkspaceBrowserRuntimeSnapshot] = []
        model.sync(state: state) { snapshot in
            snapshots.append(snapshot)
        }
        XCTAssertEqual(snapshots.count, 0)

        model.sync(state: state) { snapshot in
            snapshots.append(snapshot)
        }
        XCTAssertEqual(snapshots.count, 0)

        let changedState = state.updating(urlString: "https://example.com", isLoading: true)
        model.sync(state: changedState) { snapshot in
            snapshots.append(snapshot)
        }
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.urlString, "https://example.com")
        XCTAssertEqual(snapshots.first?.isLoading, true)
    }
}
