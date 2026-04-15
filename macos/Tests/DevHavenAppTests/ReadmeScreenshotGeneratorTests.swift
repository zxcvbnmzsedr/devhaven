import XCTest
import SwiftUI
import AppKit
@testable import DevHavenApp
@testable import DevHavenCore

@MainActor
final class ReadmeScreenshotGeneratorTests: XCTestCase {
    func testGenerateReadmeScreenshots() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["DEVHAVEN_GENERATE_README_SCREENSHOTS"] == "1",
            "Only run this generator when DEVHAVEN_GENERATE_README_SCREENSHOTS=1 is set."
        )

        let outputDirectory = resolvedOutputDirectory()
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let viewModel = NativeAppViewModel()
        viewModel.load()

        let preferredColorScheme = NativeTheme.preferredColorScheme(
            for: viewModel.snapshot.appState.settings.appAppearanceMode
        )

        render(
            AppRootView(viewModel: viewModel)
                .preferredColorScheme(preferredColorScheme),
            size: NSSize(width: 1600, height: 980),
            to: outputDirectory.appendingPathComponent("readme-home.png")
        )

        render(
            MainContentView(viewModel: viewModel)
                .preferredColorScheme(preferredColorScheme),
            size: NSSize(width: 1440, height: 920),
            to: outputDirectory.appendingPathComponent("readme-projects.png")
        )

        render(
            GitDashboardView(viewModel: viewModel)
                .preferredColorScheme(preferredColorScheme),
            size: NSSize(width: 1440, height: 980),
            to: outputDirectory.appendingPathComponent("readme-dashboard.png")
        )

        let repositoryPath = resolvedRepositoryPath()
        let gitService = NativeGitRepositoryService()

        let gitViewModel = makeGitViewModel(
            repositoryPath: repositoryPath,
            service: gitService
        )
        gitViewModel.refreshForCurrentSection()

        render(
            WorkspaceGitRootView(
                viewModel: gitViewModel,
                gitHubViewModel: nil,
                onOpenDiff: { _ in }
            )
            .preferredColorScheme(preferredColorScheme),
            size: NSSize(width: 1560, height: 960),
            to: outputDirectory.appendingPathComponent("readme-git-log.png"),
            prepare: {
                self.waitUntil {
                    !gitViewModel.logViewModel.logSnapshot.commits.isEmpty
                }
                if let firstCommit = gitViewModel.logViewModel.logSnapshot.commits.first {
                    gitViewModel.logViewModel.selectCommit(firstCommit.hash)
                    self.waitUntil {
                        gitViewModel.logViewModel.selectedCommitDetail?.hash == firstCommit.hash
                    }
                }
                self.pumpMainRunLoop(ticks: 12)
            }
        )

        let commitViewModel = makeCommitViewModel(
            repositoryPath: repositoryPath,
            service: gitService
        )
        commitViewModel.refreshChangesSnapshot()

        render(
            WorkspaceCommitRootView(
                viewModel: commitViewModel,
                onSyncDiffIfNeeded: { _ in },
                onOpenDiff: { _ in }
            )
            .preferredColorScheme(preferredColorScheme),
            size: NSSize(width: 1160, height: 920),
            to: outputDirectory.appendingPathComponent("readme-commit.png"),
            prepare: {
                self.waitUntil {
                    commitViewModel.changesSnapshot != nil
                }
                if let firstChange = commitViewModel.changesSnapshot?.changes.first {
                    commitViewModel.selectChange(firstChange.path)
                    self.waitUntil {
                        commitViewModel.diffPreview.path == firstChange.path && !commitViewModel.diffPreview.isLoading
                    }
                }
                commitViewModel.commitMessage = "docs(readme): refresh screenshots and feature overview"
                commitViewModel.options.isSignOff = true
                self.pumpMainRunLoop(ticks: 12)
            }
        )

        render(
            ReadmeRunPreviewView(repositoryPath: repositoryPath)
                .preferredColorScheme(preferredColorScheme),
            size: NSSize(width: 1480, height: 560),
            to: outputDirectory.appendingPathComponent("readme-run-console.png")
        )
    }

    private func resolvedOutputDirectory() -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let customPath = environment["DEVHAVEN_README_SCREENSHOT_DIR"], !customPath.isEmpty {
            return URL(fileURLWithPath: customPath, isDirectory: true)
        }

        let workingDirectory = environment["PWD"] ?? FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: workingDirectory, isDirectory: true)
            .appendingPathComponent("docs/pic/runtime", isDirectory: true)
    }

    private func resolvedRepositoryPath() -> String {
        let environment = ProcessInfo.processInfo.environment
        return environment["PWD"] ?? FileManager.default.currentDirectoryPath
    }

    private func makeGitViewModel(
        repositoryPath: String,
        service: NativeGitRepositoryService
    ) -> WorkspaceGitViewModel {
        let worktree = WorkspaceGitWorktreeContext(
            path: repositoryPath,
            displayName: URL(fileURLWithPath: repositoryPath).lastPathComponent,
            branchName: nil,
            isRootProject: true
        )
        let family = WorkspaceGitRepositoryFamilyContext(
            id: repositoryPath,
            displayName: URL(fileURLWithPath: repositoryPath).lastPathComponent,
            repositoryPath: repositoryPath,
            preferredExecutionPath: repositoryPath,
            members: [worktree]
        )
        let context = WorkspaceGitRepositoryContext(
            rootProjectPath: repositoryPath,
            repositoryPath: repositoryPath,
            repositoryFamilies: [family],
            selectedRepositoryFamilyID: family.id
        )
        return WorkspaceGitViewModel(
            repositoryContext: context,
            executionWorktrees: [worktree],
            preferredExecutionWorktreePath: repositoryPath,
            section: .log,
            client: .live(service: service)
        )
    }

    private func makeCommitViewModel(
        repositoryPath: String,
        service: NativeGitRepositoryService
    ) -> WorkspaceCommitViewModel {
        let worktree = WorkspaceGitWorktreeContext(
            path: repositoryPath,
            displayName: URL(fileURLWithPath: repositoryPath).lastPathComponent,
            branchName: nil,
            isRootProject: true
        )
        let family = WorkspaceGitRepositoryFamilyContext(
            id: repositoryPath,
            displayName: URL(fileURLWithPath: repositoryPath).lastPathComponent,
            repositoryPath: repositoryPath,
            preferredExecutionPath: repositoryPath,
            members: [worktree]
        )
        let context = WorkspaceCommitRepositoryContext(
            rootProjectPath: repositoryPath,
            repositoryPath: repositoryPath,
            executionPath: repositoryPath,
            repositoryFamilies: [family],
            selectedRepositoryFamilyID: family.id
        )
        return WorkspaceCommitViewModel(
            repositoryContext: context,
            client: .live(service: service)
        )
    }

    private func render<V: View>(
        _ view: V,
        size: NSSize,
        to url: URL,
        prepare: (() -> Void)? = nil
    ) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        defer {
            window.orderOut(nil)
        }

        let hostingView = NSHostingView(
            rootView: view
                .frame(width: size.width, height: size.height)
        )
        hostingView.frame = NSRect(origin: .zero, size: size)
        window.contentView = hostingView
        window.setContentSize(size)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        pumpMainRunLoop(ticks: 30)
        prepare?()
        hostingView.layoutSubtreeIfNeeded()

        let bounds = hostingView.bounds
        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: bounds) else {
            XCTFail("Failed to allocate bitmap for \(url.lastPathComponent)")
            return
        }

        hostingView.cacheDisplay(in: bounds, to: bitmap)

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Failed to encode PNG for \(url.lastPathComponent)")
            return
        }

        do {
            try pngData.write(to: url)
        } catch {
            XCTFail("Failed to write screenshot \(url.lastPathComponent): \(error)")
        }
    }

    private func waitUntil(
        maxTicks: Int = 200,
        condition: @escaping @MainActor () -> Bool
    ) {
        for _ in 0..<maxTicks {
            if condition() {
                return
            }
            pumpMainRunLoop(ticks: 2)
        }
    }

    private func pumpMainRunLoop(ticks: Int) {
        for _ in 0..<ticks {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }
}

private struct ReadmeRunPreviewView: View {
    let repositoryPath: String

    private var toolbarConfigurations: [WorkspaceRunConfiguration] {
        [
            WorkspaceRunConfiguration(
                id: "devhaven-app",
                projectPath: repositoryPath,
                rootProjectPath: repositoryPath,
                source: .projectRunConfiguration,
                sourceID: "devhaven-app",
                name: "DevHavenApp",
                executable: .shell(command: "./dev --no-log"),
                displayCommand: "./dev --no-log",
                workingDirectory: repositoryPath,
                isShared: false
            ),
            WorkspaceRunConfiguration(
                id: "native-tests",
                projectPath: repositoryPath,
                rootProjectPath: repositoryPath,
                source: .projectRunConfiguration,
                sourceID: "native-tests",
                name: "Native Tests",
                executable: .shell(command: "swift test --package-path macos"),
                displayCommand: "swift test --package-path macos",
                workingDirectory: repositoryPath,
                isShared: false
            ),
        ]
    }

    private var consoleState: WorkspaceRunConsoleState {
        let selectedSession = WorkspaceRunSession(
            id: "session-devhaven-app",
            configurationID: "devhaven-app",
            configurationName: "DevHavenApp",
            configurationSource: .projectRunConfiguration,
            projectPath: repositoryPath,
            rootProjectPath: repositoryPath,
            command: "./dev --no-log",
            workingDirectory: repositoryPath,
            state: .running,
            processID: 46083,
            logFilePath: "\(repositoryPath)/docs/pic/runtime/devhaven-run.log",
            startedAt: Date().addingTimeInterval(-320),
            displayBuffer: """
            ==> Ensure Ghostty / Sparkle vendor is available
            ==> Build DevHavenCLI helper
            ==> Launch native app
            2026-04-15 15:23:00.859 DevHavenApp[46083:3678755] workspace restore ready
            2026-04-15 15:23:02.114 DevHavenApp[46083:3678755] run configuration selected: DevHavenApp
            2026-04-15 15:23:04.921 DevHavenApp[46083:3678755] Git tool window context warmed
            """
        )
        let completedSession = WorkspaceRunSession(
            id: "session-native-tests",
            configurationID: "native-tests",
            configurationName: "Native Tests",
            configurationSource: .projectRunConfiguration,
            projectPath: repositoryPath,
            rootProjectPath: repositoryPath,
            command: "swift test --package-path macos",
            workingDirectory: repositoryPath,
            state: .completed(exitCode: 0),
            processID: nil,
            logFilePath: "\(repositoryPath)/docs/pic/runtime/native-tests.log",
            startedAt: Date().addingTimeInterval(-1200),
            endedAt: Date().addingTimeInterval(-980),
            displayBuffer: """
            Building for debugging...
            Test Suite 'Selected tests' passed at 2026-04-15 15:39:20.468.
            Executed 1 test, with 0 failures (0 unexpected) in 5.068 seconds.
            """
        )
        return WorkspaceRunConsoleState(
            sessions: [selectedSession, completedSession],
            selectedSessionID: selectedSession.id,
            selectedConfigurationID: selectedSession.configurationID,
            isVisible: true,
            panelHeight: 340
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Run")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(NativeTheme.textPrimary)
                Spacer(minLength: 0)
                WorkspaceRunToolbarView(
                    configurations: toolbarConfigurations,
                    selectedConfigurationID: "devhaven-app",
                    canRun: true,
                    canStop: true,
                    hasSessions: true,
                    isLogsVisible: true,
                    onSelectConfiguration: { _ in },
                    onRun: {},
                    onStop: {},
                    onToggleLogs: {},
                    onConfigure: {}
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(NativeTheme.surface)

            WorkspaceRunConsolePanel(
                consoleState: consoleState,
                height: 340,
                onSelectSession: { _ in },
                onClear: {},
                onOpenLog: {},
                onHide: {}
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NativeTheme.window)
    }
}
