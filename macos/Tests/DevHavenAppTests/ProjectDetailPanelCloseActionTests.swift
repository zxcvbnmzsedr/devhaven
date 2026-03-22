import XCTest
import AppKit
import SwiftUI
@testable import DevHavenApp
@testable import DevHavenCore

@MainActor
final class ProjectDetailPanelCloseActionTests: XCTestCase {
    private static var retainedWindows: [NSWindow] = []

    func testClosingDetailPanelReleasesActiveEditorResponderBeforeHidingPanel() throws {
        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: makeHomeURL()))
        let project = Project(
            id: "project-1",
            name: "Alpha",
            path: "/tmp/alpha",
            tags: [],
            scripts: [],
            worktrees: [],
            mtime: 0,
            size: 1,
            checksum: "a",
            gitCommits: 1,
            gitLastCommit: 0,
            gitLastCommitMessage: "init",
            gitDaily: nil,
            created: 0,
            checked: 0
        )
        viewModel.snapshot.projects = [project]
        viewModel.selectProject(project.path)
        viewModel.notesDraft = "note"
        viewModel.todoDraft = "todo"
        viewModel.readmeFallback = MarkdownDocument(path: "README.md", content: String(repeating: "line\n", count: 10_000))
        viewModel.hasLoadedInitialData = true

        let hostingView = NSHostingView(rootView: AppRootView(viewModel: viewModel))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 900),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        Self.retainedWindows.append(window)
        let activator = InitialWindowActivator(application: AppKitApplicationActivationProxy())
        activator.activateIfNeeded(window: AppKitWindowActivationProxy(window: window))
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        let textView = try XCTUnwrap(findSubview(in: hostingView, ofType: NSTextView.self))
        XCTAssertTrue(window.makeFirstResponder(textView))
        XCTAssertTrue(window.firstResponder === textView)

        DetailPanelCloseAction.perform(for: viewModel, window: window)
        window.displayIfNeeded()
        waitUntil(timeout: 1.0) {
            window.firstResponder !== textView && !viewModel.isDetailPanelPresented
        }

        XCTAssertFalse(
            window.firstResponder === textView,
            "关闭详情面板前应先让当前编辑器释放 firstResponder，避免移除右侧面板后窗口仍挂着已脱离层级的 responder 而出现无响应"
        )
        XCTAssertFalse(viewModel.isDetailPanelPresented)
    }

    private func waitUntil(timeout: TimeInterval, pollInterval: TimeInterval = 0.01, condition: @escaping () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(pollInterval))
        }
    }

    private func findSubview<T: NSView>(in root: NSView, ofType type: T.Type) -> T? {
        if let root = root as? T {
            return root
        }
        for subview in root.subviews {
            if let match = findSubview(in: subview, ofType: type) {
                return match
            }
        }
        return nil
    }

    private func makeHomeURL() -> URL {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }
}
