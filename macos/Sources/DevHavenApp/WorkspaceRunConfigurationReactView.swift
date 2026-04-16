import SwiftUI
import WebKit

enum WorkspaceRunConfigurationStringField: String, Codable {
    case name
    case customCommand
    case remoteServer
    case remoteLogPath
    case remoteUser
    case remotePort
    case remoteIdentityFile
    case remoteLines
    case remoteStrictHostKeyChecking
}

enum WorkspaceRunConfigurationBooleanField: String, Codable {
    case remoteFollow
    case remoteAllowPasswordPrompt
}

struct WorkspaceRunConfigurationKindOptionPayload: Codable, Equatable {
    var id: String
    var title: String
    var subtitle: String
}

struct WorkspaceRunConfigurationSheetConfigurationPayload: Codable, Equatable {
    var id: String
    var kind: String
    var kindTitle: String
    var kindSubtitle: String
    var name: String
    var resolvedName: String
    var suggestedName: String
    var rowSummary: String
    var commandPreview: String
    var customCommand: String
    var remoteServer: String
    var remoteLogPath: String
    var remoteUser: String
    var remotePort: String
    var remoteIdentityFile: String
    var remoteLines: String
    var remoteFollow: Bool
    var remoteStrictHostKeyChecking: String
    var remoteAllowPasswordPrompt: Bool
}

struct WorkspaceRunConfigurationSheetPayload: Codable, Equatable {
    var theme: String
    var title: String
    var subtitle: String
    var projectPath: String
    var footerNote: String
    var isSaving: Bool
    var validationMessage: String?
    var selectedConfigurationID: String?
    var availableKinds: [WorkspaceRunConfigurationKindOptionPayload]
    var configurations: [WorkspaceRunConfigurationSheetConfigurationPayload]
}

@MainActor
final class WorkspaceRunConfigurationSheetBridge: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    private enum Constants {
        static let messageHandlerName = "devhavenRunConfigurationSheet"
        static let runtimeDiagnosticsUserScript = #"""
window.addEventListener("error", function(event) {
  try {
    window.webkit?.messageHandlers?.devhavenRunConfigurationSheet?.postMessage({
      type: "debugError",
      message: String(event.message || ""),
      source: String(event.filename || ""),
      line: Number(event.lineno || 0),
      column: Number(event.colno || 0)
    });
  } catch (_) {}
});

window.addEventListener("unhandledrejection", function(event) {
  try {
    var reason = event.reason;
    var description = "";
    if (reason && typeof reason === "object" && "message" in reason) {
      description = String(reason.message || "");
    } else {
      description = String(reason || "");
    }

    window.webkit?.messageHandlers?.devhavenRunConfigurationSheet?.postMessage({
      type: "debugUnhandledRejection",
      message: description
    });
  } catch (_) {}
});
"""#
    }

    let webView: WKWebView

    private var isReady = false
    private var pendingPayload: WorkspaceRunConfigurationSheetPayload?
    private var renderedPayload: WorkspaceRunConfigurationSheetPayload?
    private var onSelectConfiguration: ((String) -> Void)?
    private var onAddConfiguration: ((String) -> Void)?
    private var onStringFieldChanged: ((String, WorkspaceRunConfigurationStringField, String) -> Void)?
    private var onBooleanFieldChanged: ((String, WorkspaceRunConfigurationBooleanField, Bool) -> Void)?
    private var onDuplicateRequested: ((String) -> Void)?
    private var onDeleteRequested: ((String) -> Void)?
    private var onCancelRequested: (() -> Void)?
    private var onSaveRequested: (() -> Void)?
    private(set) var debugEvents: [String] = []

    override init() {
        let contentController = WKUserContentController()
        let diagnosticsScript = WKUserScript(
            source: Constants.runtimeDiagnosticsUserScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(diagnosticsScript)
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

        webView.navigationDelegate = self
        contentController.add(
            WeakWorkspaceRunConfigurationSheetScriptMessageHandler(delegate: self),
            name: Constants.messageHandlerName
        )
        loadShellIfNeeded()
    }

    func update(
        payload: WorkspaceRunConfigurationSheetPayload,
        onSelectConfiguration: @escaping (String) -> Void,
        onAddConfiguration: @escaping (String) -> Void,
        onStringFieldChanged: @escaping (String, WorkspaceRunConfigurationStringField, String) -> Void,
        onBooleanFieldChanged: @escaping (String, WorkspaceRunConfigurationBooleanField, Bool) -> Void,
        onDuplicateRequested: @escaping (String) -> Void,
        onDeleteRequested: @escaping (String) -> Void,
        onCancelRequested: @escaping () -> Void,
        onSaveRequested: @escaping () -> Void
    ) {
        self.onSelectConfiguration = onSelectConfiguration
        self.onAddConfiguration = onAddConfiguration
        self.onStringFieldChanged = onStringFieldChanged
        self.onBooleanFieldChanged = onBooleanFieldChanged
        self.onDuplicateRequested = onDuplicateRequested
        self.onDeleteRequested = onDeleteRequested
        self.onCancelRequested = onCancelRequested
        self.onSaveRequested = onSaveRequested
        pendingPayload = payload
        applyPendingPayloadIfNeeded()
    }

    private func loadShellIfNeeded() {
        guard let htmlURL = DevHavenAppResourceLocator.resolveResourceURL(
            subdirectory: "WorkspaceRunConfigurationResources",
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
        evaluate(script: "window.__devHavenRunConfigurationSheet?.applyPayload?.(\(payloadJSON));")
    }

    private func evaluate(script: String) {
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func appendDebugEvent(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        debugEvents.append("[\(timestamp)] \(message)")
        if debugEvents.count > 50 {
            debugEvents.removeFirst(debugEvents.count - 50)
        }
    }

    func debugStateSummary() -> String {
        let lastEvent = debugEvents.last ?? "none"
        return "isReady=\(isReady) hasPendingPayload=\(pendingPayload != nil) hasRenderedPayload=\(renderedPayload != nil) url=\(webView.url?.absoluteString ?? "nil") lastEvent=\(lastEvent)"
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
            appendDebugEvent("ready")
            isReady = true
            applyPendingPayloadIfNeeded()

        case "debugError":
            let message = body["message"] as? String ?? ""
            let source = body["source"] as? String ?? ""
            let line = body["line"] as? Int ?? 0
            let column = body["column"] as? Int ?? 0
            appendDebugEvent("js-error message=\(message) source=\(source) line=\(line) column=\(column)")

        case "debugUnhandledRejection":
            let message = body["message"] as? String ?? ""
            appendDebugEvent("js-unhandled-rejection message=\(message)")

        case "selectConfiguration":
            guard let configurationID = body["configurationID"] as? String else {
                return
            }
            onSelectConfiguration?(configurationID)

        case "addConfiguration":
            guard let kind = body["kind"] as? String else {
                return
            }
            onAddConfiguration?(kind)

        case "updateStringField":
            guard let configurationID = body["configurationID"] as? String,
                  let fieldRawValue = body["field"] as? String,
                  let field = WorkspaceRunConfigurationStringField(rawValue: fieldRawValue),
                  let value = body["value"] as? String
            else {
                return
            }
            onStringFieldChanged?(configurationID, field, value)

        case "updateBooleanField":
            guard let configurationID = body["configurationID"] as? String,
                  let fieldRawValue = body["field"] as? String,
                  let field = WorkspaceRunConfigurationBooleanField(rawValue: fieldRawValue),
                  let value = body["value"] as? Bool
            else {
                return
            }
            onBooleanFieldChanged?(configurationID, field, value)

        case "duplicateConfiguration":
            guard let configurationID = body["configurationID"] as? String else {
                return
            }
            onDuplicateRequested?(configurationID)

        case "deleteConfiguration":
            guard let configurationID = body["configurationID"] as? String else {
                return
            }
            onDeleteRequested?(configurationID)

        case "cancelRequested":
            onCancelRequested?()

        case "saveRequested":
            onSaveRequested?()

        default:
            break
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        appendDebugEvent("navigation-start url=\(webView.url?.absoluteString ?? "nil")")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        appendDebugEvent("navigation-finish url=\(webView.url?.absoluteString ?? "nil")")
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        appendDebugEvent("navigation-fail error=\(error.localizedDescription)")
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        appendDebugEvent("navigation-provisional-fail error=\(error.localizedDescription)")
    }
}

private final class WeakWorkspaceRunConfigurationSheetScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

struct WorkspaceRunConfigurationSheetReactView: View {
    let payload: WorkspaceRunConfigurationSheetPayload
    let onSelectConfiguration: (String) -> Void
    let onAddConfiguration: (String) -> Void
    let onStringFieldChanged: (String, WorkspaceRunConfigurationStringField, String) -> Void
    let onBooleanFieldChanged: (String, WorkspaceRunConfigurationBooleanField, Bool) -> Void
    let onDuplicateRequested: (String) -> Void
    let onDeleteRequested: (String) -> Void
    let onCancelRequested: () -> Void
    let onSaveRequested: () -> Void

    @StateObject private var bridge = WorkspaceRunConfigurationSheetBridge()

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
    }

    private func syncBridge() {
        bridge.update(
            payload: payload,
            onSelectConfiguration: onSelectConfiguration,
            onAddConfiguration: onAddConfiguration,
            onStringFieldChanged: onStringFieldChanged,
            onBooleanFieldChanged: onBooleanFieldChanged,
            onDuplicateRequested: onDuplicateRequested,
            onDeleteRequested: onDeleteRequested,
            onCancelRequested: onCancelRequested,
            onSaveRequested: onSaveRequested
        )
    }
}
