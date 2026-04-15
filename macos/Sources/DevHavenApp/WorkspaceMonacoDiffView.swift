import SwiftUI
import WebKit
import DevHavenCore

struct WorkspaceMonacoDiffBlockPayload: Codable, Equatable {
    var id: String
    var leftStartLine: Int
    var leftLineCount: Int
    var rightStartLine: Int
    var rightLineCount: Int
}

struct WorkspaceMonacoDiffPanePayload: Codable, Equatable {
    var badge: String
    var fileName: String
    var path: String?
    var detailText: String?
    var renamedFrom: String?
}

struct WorkspaceMonacoDiffToolbarPayload: Codable, Equatable {
    var currentDifferenceIndex: Int
    var totalDifferences: Int
    var currentRequestIndex: Int
    var totalRequests: Int
    var canGoPrevious: Bool
    var canGoNext: Bool
    var viewerMode: String
    var availableViewerModes: [String]
    var compareModeLabel: String
    var languageLabel: String
    var isEditable: Bool
}

struct WorkspaceMonacoDiffPayload: Codable, Equatable {
    var originalText: String
    var modifiedText: String
    var language: String
    var theme: String
    var toolbar: WorkspaceMonacoDiffToolbarPayload
    var leftPane: WorkspaceMonacoDiffPanePayload
    var rightPane: WorkspaceMonacoDiffPanePayload
    var blocks: [WorkspaceMonacoDiffBlockPayload]
}

@MainActor
final class WorkspaceMonacoDiffBridge: NSObject, ObservableObject, WKScriptMessageHandler {
    private enum Constants {
        static let messageHandlerName = "devhavenMonacoDiff"
    }

    let webView: WKWebView

    private var isReady = false
    private var pendingPayload: WorkspaceMonacoDiffPayload?
    private var renderedPayload: WorkspaceMonacoDiffPayload?
    private var pendingSelectedBlockID: String?
    private var renderedSelectedBlockID: String?
    private var onContentChanged: ((String) -> Void)?
    private var onSaveRequested: (() -> Void)?
    private var onActiveBlockChanged: ((String) -> Void)?
    private var onPreviousDifferenceRequested: (() -> Void)?
    private var onNextDifferenceRequested: (() -> Void)?
    private var onRefreshRequested: (() -> Void)?
    private var onViewerModeChanged: ((WorkspaceDiffViewerMode) -> Void)?

    override init() {
        let contentController = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        self.webView = webView

        super.init()

        contentController.add(self, name: Constants.messageHandlerName)
        loadShellIfNeeded()
    }

    func update(
        payload: WorkspaceMonacoDiffPayload,
        selectedBlockID: String?,
        onContentChanged: @escaping (String) -> Void,
        onSaveRequested: @escaping () -> Void,
        onActiveBlockChanged: @escaping (String) -> Void,
        onPreviousDifferenceRequested: @escaping () -> Void,
        onNextDifferenceRequested: @escaping () -> Void,
        onRefreshRequested: @escaping () -> Void,
        onViewerModeChanged: @escaping (WorkspaceDiffViewerMode) -> Void
    ) {
        self.onContentChanged = onContentChanged
        self.onSaveRequested = onSaveRequested
        self.onActiveBlockChanged = onActiveBlockChanged
        self.onPreviousDifferenceRequested = onPreviousDifferenceRequested
        self.onNextDifferenceRequested = onNextDifferenceRequested
        self.onRefreshRequested = onRefreshRequested
        self.onViewerModeChanged = onViewerModeChanged
        pendingPayload = payload
        pendingSelectedBlockID = selectedBlockID
        applyPendingPayloadIfNeeded()
        applySelectedBlockIfNeeded()
    }

    func focusModifiedEditor() {
        evaluate(script: "window.__devHavenMonaco?.focusModifiedEditor?.();")
    }

    private func loadShellIfNeeded() {
        guard let htmlURL = DevHavenAppResourceLocator.resolveResourceURL(
            subdirectory: "MonacoDiffResources",
            resource: "index",
            withExtension: "html"
        ) else {
            return
        }
        webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
    }

    private func applyPendingPayloadIfNeeded() {
        guard isReady, let pendingPayload else {
            return
        }
        guard renderedPayload != pendingPayload else {
            return
        }
        renderedPayload = pendingPayload
        guard let payloadJSON = jsonString(pendingPayload) else {
            return
        }
        evaluate(script: "window.__devHavenMonaco?.applyPayload?.(\(payloadJSON));")
        applySelectedBlockIfNeeded()
    }

    private func applySelectedBlockIfNeeded() {
        guard isReady, renderedSelectedBlockID != pendingSelectedBlockID,
              let blockJSON = jsonString(pendingSelectedBlockID as String?)
        else {
            return
        }
        renderedSelectedBlockID = pendingSelectedBlockID
        evaluate(script: "window.__devHavenMonaco?.setSelectedBlock?.(\(blockJSON));")
    }

    private func evaluate(script: String) {
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func jsonString<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Constants.messageHandlerName,
              let body = message.body as? [String: Any],
              let type = body["type"] as? String
        else {
            return
        }

        switch type {
        case "ready":
            isReady = true
            applyPendingPayloadIfNeeded()
            applySelectedBlockIfNeeded()
        case "contentChanged":
            guard let text = body["text"] as? String else {
                return
            }
            onContentChanged?(text)
        case "saveRequested":
            onSaveRequested?()
        case "activeBlockChanged":
            guard let blockID = body["blockID"] as? String else {
                return
            }
            onActiveBlockChanged?(blockID)
        case "previousDifferenceRequested":
            onPreviousDifferenceRequested?()
        case "nextDifferenceRequested":
            onNextDifferenceRequested?()
        case "refreshRequested":
            onRefreshRequested?()
        case "viewerModeChanged":
            guard let modeRawValue = body["mode"] as? String,
                  let mode = WorkspaceDiffViewerMode(rawValue: modeRawValue)
            else {
                return
            }
            onViewerModeChanged?(mode)
        default:
            break
        }
    }
}

struct WorkspaceMonacoDiffView: View {
    @Bindable var viewModel: WorkspaceDiffTabViewModel
    let document: WorkspaceDiffCompareDocument
    let paneDescriptors: [WorkspaceDiffPaneDescriptor]
    let availableViewerModes: [WorkspaceDiffViewerMode]
    let selectedDifference: WorkspaceDiffDifferenceAnchor?

    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var bridge = WorkspaceMonacoDiffBridge()

    var body: some View {
        WorkspaceEmbeddedWebViewContainer(webView: bridge.webView)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NativeTheme.window)
            .onAppear {
                syncBridge()
            }
            .onChange(of: payload) { _, _ in
                syncBridge()
            }
            .onChange(of: selectedBlockID) { _, _ in
                syncBridge()
            }
    }

    private var payload: WorkspaceMonacoDiffPayload {
        WorkspaceMonacoDiffPayload(
            originalText: document.leftPane.text,
            modifiedText: document.rightPane.text,
            language: monacoLanguageID,
            theme: workspaceMonacoThemeName(for: colorScheme),
            toolbar: WorkspaceMonacoDiffToolbarPayload(
                currentDifferenceIndex: viewModel.sessionState.navigatorState.currentDifferenceIndex,
                totalDifferences: viewModel.sessionState.navigatorState.totalDifferences,
                currentRequestIndex: viewModel.sessionState.navigatorState.currentRequestIndex,
                totalRequests: viewModel.sessionState.navigatorState.totalRequests,
                canGoPrevious: viewModel.sessionState.navigatorState.canGoPrevious,
                canGoNext: viewModel.sessionState.navigatorState.canGoNext,
                viewerMode: viewModel.documentState.viewerMode.rawValue,
                availableViewerModes: availableViewerModes.map(\.rawValue),
                compareModeLabel: compareModeLabel,
                languageLabel: languageLabel,
                isEditable: document.rightPane.isEditable
            ),
            leftPane: panePayload(
                for: .left,
                fallbackTitle: document.leftPane.title,
                fallbackPath: document.leftPane.path
            ),
            rightPane: panePayload(
                for: .right,
                fallbackTitle: document.rightPane.title,
                fallbackPath: document.rightPane.path
            ),
            blocks: document.blocks.map {
                WorkspaceMonacoDiffBlockPayload(
                    id: $0.id,
                    leftStartLine: $0.leftLineRange.startLine,
                    leftLineCount: $0.leftLineRange.lineCount,
                    rightStartLine: $0.rightLineRange.startLine,
                    rightLineCount: $0.rightLineRange.lineCount
                )
            }
        )
    }

    private var selectedBlockID: String? {
        guard case let .compareBlock(blockID)? = selectedDifference else {
            return nil
        }
        return blockID
    }

    private func syncBridge() {
        bridge.update(
            payload: payload,
            selectedBlockID: selectedBlockID,
            onContentChanged: { text in
                viewModel.updateEditableContent(text)
            },
            onSaveRequested: {
                try? viewModel.saveEditableContent()
            },
            onActiveBlockChanged: { blockID in
                viewModel.selectDifferenceAnchor(.compareBlock(blockID))
            },
            onPreviousDifferenceRequested: {
                viewModel.goToPreviousDifference()
            },
            onNextDifferenceRequested: {
                viewModel.goToNextDifference()
            },
            onRefreshRequested: {
                viewModel.refresh()
            },
            onViewerModeChanged: { mode in
                guard availableViewerModes.contains(mode) else {
                    return
                }
                viewModel.updateViewerMode(mode)
            }
        )
    }

    private func panePayload(
        for role: WorkspaceDiffPaneHeaderRole,
        fallbackTitle: String,
        fallbackPath: String?
    ) -> WorkspaceMonacoDiffPanePayload {
        let metadata = paneDescriptor(
            for: role,
            fallbackTitle: fallbackTitle,
            fallbackPath: fallbackPath
        ).metadata

        return WorkspaceMonacoDiffPanePayload(
            badge: metadata.title,
            fileName: paneFileName(for: metadata),
            path: metadata.path,
            detailText: paneDetailText(for: metadata),
            renamedFrom: metadata.oldPath
        )
    }

    private func paneDescriptor(
        for role: WorkspaceDiffPaneHeaderRole,
        fallbackTitle: String,
        fallbackPath: String?
    ) -> WorkspaceDiffPaneDescriptor {
        if let descriptor = paneDescriptors.first(where: { $0.role == role }) {
            return descriptor
        }
        return WorkspaceDiffPaneDescriptor(
            role: role,
            metadata: WorkspaceDiffPaneMetadata(title: fallbackTitle, path: fallbackPath)
        )
    }

    private func paneFileName(for metadata: WorkspaceDiffPaneMetadata) -> String {
        guard let path = metadata.path else {
            return metadata.title
        }
        let fileName = URL(fileURLWithPath: path).lastPathComponent
        return fileName.isEmpty ? path : fileName
    }

    private func paneDetailText(for metadata: WorkspaceDiffPaneMetadata) -> String? {
        let items = metadata.primaryDetails + metadata.secondaryDetails
        guard !items.isEmpty else {
            return nil
        }
        return items.joined(separator: " · ")
    }

    private var monacoLanguageID: String {
        let candidatePath = document.rightPane.path ?? document.leftPane.path ?? ""
        return workspaceMonacoLanguageID(forFilePath: candidatePath)
    }

    private var compareModeLabel: String {
        switch document.mode {
        case .history:
            return "Commit"
        case .staged:
            return "Staged"
        case .unstaged:
            return "Local"
        case .untracked:
            return "Untracked"
        }
    }

    private var languageLabel: String {
        workspaceMonacoLanguageLabel(for: monacoLanguageID)
    }
}
