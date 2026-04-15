import XCTest
import SwiftUI
import AppKit
import WebKit
@testable import DevHavenApp
@testable import DevHavenCore

final class WorkspaceEditorTabEditingPersistenceTests: XCTestCase {
    private var rootURL: URL!
    private var homeURL: URL!
    private var projectURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("devhaven-workspace-editor-ui-\(UUID().uuidString)", isDirectory: true)
        homeURL = rootURL.appendingPathComponent("home", isDirectory: true)
        projectURL = rootURL.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
        projectURL = nil
        homeURL = nil
        rootURL = nil
        try super.tearDownWithError()
    }

    @MainActor
    func testTypingPersistsAcrossViewUpdates() async throws {
        let fileURL = projectURL.appendingPathComponent("Sample.swift")
        try "struct Sample {}".write(to: fileURL, atomically: true, encoding: .utf8)

        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: homeURL))
        viewModel.snapshot = NativeAppSnapshot(projects: [makeProject()])
        viewModel.enterWorkspace(projectURL.path)
        viewModel.openWorkspaceEditorTab(for: fileURL.path, in: projectURL.path)
        let tabID = try XCTUnwrap(viewModel.activeWorkspaceEditorTabs.first?.id)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }

        let hostingView = NSHostingView(
            rootView: WorkspaceEditorTabView(
                viewModel: viewModel,
                projectPath: projectURL.path,
                tabID: tabID
            )
            .frame(width: 800, height: 600)
        )
        window.contentView = hostingView
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        pumpMainRunLoop(ticks: 12)

        let webView = try XCTUnwrap(findDescendant(ofType: WKWebView.self, in: hostingView))
        _ = try await waitForMonacoEditor(in: webView)

        let insertedText = "struct Sample {}\nlet value = 1"
        try await webView.evaluateJavaScript(
            "window.__devHavenMonacoEditor?.debugSetText?.('struct Sample {}\\nlet value = 1')"
        )
        pumpMainRunLoop(ticks: 24)
        try await waitUntil {
            viewModel.workspaceEditorTabState(for: self.projectURL.path, tabID: tabID)?.text == insertedText
        }

        XCTAssertEqual(viewModel.workspaceEditorTabState(for: projectURL.path, tabID: tabID)?.text, insertedText)
        var renderedText = try await monacoEditorText(in: webView)
        XCTAssertEqual(renderedText, insertedText)

        pumpMainRunLoop(for: 0.8)
        XCTAssertEqual(viewModel.workspaceEditorTabState(for: projectURL.path, tabID: tabID)?.text, insertedText)
        renderedText = try await monacoEditorText(in: webView)
        XCTAssertEqual(renderedText, insertedText)

        var options = viewModel.workspaceEditorDisplayOptions
        options.showsWhitespaceCharacters.toggle()
        viewModel.updateWorkspaceEditorDisplayOptions(options)
        pumpMainRunLoop(ticks: 12)

        XCTAssertEqual(viewModel.workspaceEditorTabState(for: projectURL.path, tabID: tabID)?.text, insertedText)
        renderedText = try await monacoEditorText(in: webView)
        XCTAssertEqual(renderedText, insertedText)
    }

    @MainActor
    func testSearchSessionStatePersistsPerTabInRuntimeSession() throws {
        let expected = WorkspaceEditorSearchPresentationState(
            query: "alpha",
            replacement: "beta",
            isPresented: true,
            showsReplace: true,
            isCaseSensitive: true,
            matchesWholeWords: true,
            usesRegularExpression: false,
            preservesReplacementCase: true
        )
        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: homeURL))
        viewModel.snapshot = NativeAppSnapshot(projects: [makeProject()])
        viewModel.enterWorkspace(projectURL.path)

        let fileURL = projectURL.appendingPathComponent("Session.swift")
        try "struct Session {}".write(to: fileURL, atomically: true, encoding: .utf8)
        viewModel.openWorkspaceEditorTab(for: fileURL.path, in: projectURL.path)
        let actualTabID = try XCTUnwrap(viewModel.activeWorkspaceEditorTabs.first?.id)

        var session = viewModel.workspaceEditorRuntimeSession(for: projectURL.path, tabID: actualTabID)
        session.searchPresentation = expected
        viewModel.updateWorkspaceEditorRuntimeSession(session, tabID: actualTabID, in: projectURL.path)

        let restored = viewModel.workspaceEditorRuntimeSession(for: projectURL.path, tabID: actualTabID)

        XCTAssertEqual(restored.searchPresentation, expected)
    }

    private func makeProject() -> Project {
        let now = Date().timeIntervalSinceReferenceDate
        return Project(
            id: UUID().uuidString,
            name: projectURL.lastPathComponent,
            path: projectURL.path,
            tags: [],
            runConfigurations: [],
            worktrees: [],
            mtime: now,
            size: 0,
            checksum: UUID().uuidString,
            isGitRepository: false,
            gitCommits: 0,
            gitLastCommit: now,
            created: now,
            checked: now
        )
    }

    private func pumpMainRunLoop(ticks: Int = 8) {
        for _ in 0..<ticks {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    private func pumpMainRunLoop(for duration: TimeInterval) {
        let endDate = Date().addingTimeInterval(duration)
        while Date() < endDate {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 5.0,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            pumpMainRunLoop(ticks: 4)
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for editor runtime state")
    }

    @MainActor
    private func waitForMonacoEditor(
        in webView: WKWebView,
        timeout: TimeInterval = 10.0
    ) async throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let snapshot = try await monacoEditorSnapshot(in: webView),
               snapshot["hasEditor"] as? Bool == true
            {
                return snapshot
            }
            pumpMainRunLoop(ticks: 4)
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTFail("Timed out waiting for Monaco editor web view to become ready")
        return [:]
    }

    @MainActor
    private func monacoEditorText(in webView: WKWebView) async throws -> String? {
        try await monacoEditorSnapshot(in: webView)?["text"] as? String
    }

    @MainActor
    private func monacoEditorSnapshot(in webView: WKWebView) async throws -> [String: Any]? {
        try await webView.evaluateJavaScript(
            "window.__devHavenMonacoEditor?.debugSnapshot?.()"
        ) as? [String: Any]
    }

    @MainActor
    private func findDescendant<T: NSView>(ofType type: T.Type, in root: NSView) -> T? {
        if let match = root as? T {
            return match
        }
        for subview in root.subviews {
            if let match = findDescendant(ofType: type, in: subview) {
                return match
            }
        }
        return nil
    }
}
