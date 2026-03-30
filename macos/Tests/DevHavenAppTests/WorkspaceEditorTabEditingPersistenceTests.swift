import XCTest
import SwiftUI
import AppKit
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
    func testTypingPersistsAcrossViewUpdates() throws {
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

        let textView = try XCTUnwrap(findDescendant(ofType: NSTextView.self, in: hostingView))
        window.makeFirstResponder(textView)
        pumpMainRunLoop(ticks: 8)

        let insertedText = "struct Sample {}\nlet value = 1"
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        textView.insertText("\nlet value = 1", replacementRange: textView.selectedRange())
        pumpMainRunLoop(ticks: 20)

        XCTAssertEqual(viewModel.workspaceEditorTabState(for: projectURL.path, tabID: tabID)?.text, insertedText)
        XCTAssertEqual(textView.string, insertedText)

        pumpMainRunLoop(for: 0.8)
        XCTAssertEqual(viewModel.workspaceEditorTabState(for: projectURL.path, tabID: tabID)?.text, insertedText)
        XCTAssertEqual(textView.string, insertedText)

        var options = viewModel.workspaceEditorDisplayOptions
        options.showsWhitespaceCharacters.toggle()
        viewModel.updateWorkspaceEditorDisplayOptions(options)
        pumpMainRunLoop(ticks: 12)

        XCTAssertEqual(viewModel.workspaceEditorTabState(for: projectURL.path, tabID: tabID)?.text, insertedText)
        XCTAssertEqual(textView.string, insertedText)
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
