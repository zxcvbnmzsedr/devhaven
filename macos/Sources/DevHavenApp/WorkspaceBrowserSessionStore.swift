import AppKit
import Combine
import Foundation
import WebKit
import DevHavenCore

private enum WorkspaceBrowserUserAgentSettings {
    static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/26.2 Safari/605.1.15"
}

final class WorkspaceBrowserNativeWebView: WKWebView {
    var onPointerInteraction: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        onPointerInteraction?()
        super.mouseDown(with: event)
    }
}

@MainActor
struct WorkspaceBrowserRuntimeSnapshot: Equatable {
    var title: String
    var urlString: String
    var isLoading: Bool
    var canGoBack: Bool
    var canGoForward: Bool
}

@MainActor
final class WorkspaceBrowserHostModel: NSObject, ObservableObject {
    @Published private(set) var pageTitle: String
    @Published private(set) var currentURLString: String
    @Published private(set) var isLoading: Bool
    @Published private(set) var canGoBack: Bool
    @Published private(set) var canGoForward: Bool

    let webView: WKWebView

    private let surfaceId: String
    private let tabId: String
    private let paneId: String
    private var stateObserver: ((WorkspaceBrowserRuntimeSnapshot) -> Void)?
    private var navigationDelegateProxy: NavigationDelegateProxy?
    private var titleObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private var loadingObservation: NSKeyValueObservation?
    private var canGoBackObservation: NSKeyValueObservation?
    private var canGoForwardObservation: NSKeyValueObservation?
    private var lastPublishedSnapshot: WorkspaceBrowserRuntimeSnapshot?

    init(state: WorkspaceBrowserState) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WorkspaceBrowserNativeWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = WorkspaceBrowserUserAgentSettings.safariUserAgent
        webView.underPageBackgroundColor = NSColor.windowBackgroundColor
        self.webView = webView
        self.surfaceId = state.surfaceId
        self.tabId = state.tabId
        self.paneId = state.paneId
        self.pageTitle = state.title
        self.currentURLString = state.urlString
        self.isLoading = state.isLoading
        self.canGoBack = false
        self.canGoForward = false
        super.init()
        installObservers()
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        if !state.urlString.isEmpty {
            navigate(to: state.urlString)
        } else {
            syncNavigationState()
        }
    }

    func sync(state: WorkspaceBrowserState, stateObserver: ((WorkspaceBrowserRuntimeSnapshot) -> Void)?) {
        self.stateObserver = stateObserver
        let willNavigate = currentURLString.isEmpty && !state.urlString.isEmpty
        WorkspaceBrowserDiagnostics.recordSyncRequest(
            surfaceId: surfaceId,
            tabId: tabId,
            paneId: paneId,
            stateURL: state.urlString,
            currentURL: currentURLString,
            willNavigate: willNavigate
        )
        if willNavigate {
            navigate(to: state.urlString)
            return
        }
        if pageTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pageTitle = state.title
        }
        publishState(source: "sync")
    }

    func navigate(to rawInput: String) {
        let resolvedURL = Self.resolvedNavigableURL(from: rawInput)
        WorkspaceBrowserDiagnostics.recordNavigateRequest(
            surfaceId: surfaceId,
            tabId: tabId,
            paneId: paneId,
            rawInput: rawInput,
            resolvedURL: resolvedURL?.absoluteString
        )
        guard let url = resolvedURL else {
            return
        }
        webView.load(URLRequest(url: url))
        currentURLString = url.absoluteString
        pageTitle = Self.defaultTitle(for: url.absoluteString)
        isLoading = true
        publishState(source: "navigate")
    }

    func reload() {
        if webView.url == nil, !currentURLString.isEmpty {
            navigate(to: currentURLString)
        } else {
            webView.reload()
        }
    }

    func stopLoading() {
        webView.stopLoading()
        syncNavigationState()
    }

    func goBack() {
        guard webView.canGoBack else { return }
        webView.goBack()
    }

    func goForward() {
        guard webView.canGoForward else { return }
        webView.goForward()
    }

    func focusWebView() {
        webView.window?.makeFirstResponder(webView)
    }

    func setPointerInteractionHandler(_ handler: (() -> Void)?) {
        (webView as? WorkspaceBrowserNativeWebView)?.onPointerInteraction = handler
    }

    func evaluateJavaScript(_ script: String) async throws -> Any? {
        try await webView.evaluateJavaScript(script)
    }

    func takeSnapshot() async -> NSImage? {
        await withCheckedContinuation { continuation in
            let configuration = WKSnapshotConfiguration()
            webView.takeSnapshot(with: configuration) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private func installObservers() {
        let navigationDelegateProxy = NavigationDelegateProxy(owner: self)
        self.navigationDelegateProxy = navigationDelegateProxy
        webView.navigationDelegate = navigationDelegateProxy

        titleObservation = webView.observe(\.title, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.syncNavigationState()
            }
        }
        urlObservation = webView.observe(\.url, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.syncNavigationState()
            }
        }
        loadingObservation = webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.syncNavigationState()
            }
        }
        canGoBackObservation = webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.syncNavigationState()
            }
        }
        canGoForwardObservation = webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.syncNavigationState()
            }
        }
    }

    fileprivate func syncNavigationState() {
        currentURLString = webView.url?.absoluteString ?? currentURLString
        isLoading = webView.isLoading
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward

        let resolvedTitle = webView.title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let resolvedTitle, !resolvedTitle.isEmpty {
            pageTitle = resolvedTitle
        } else {
            pageTitle = Self.defaultTitle(for: currentURLString)
        }
        publishState(source: "webview")
    }

    private func publishState(source: String) {
        let snapshot = WorkspaceBrowserRuntimeSnapshot(
            title: pageTitle,
            urlString: currentURLString,
            isLoading: isLoading,
            canGoBack: canGoBack,
            canGoForward: canGoForward
        )
        guard lastPublishedSnapshot != snapshot else {
            WorkspaceBrowserDiagnostics.recordSnapshotPublish(
                surfaceId: surfaceId,
                tabId: tabId,
                paneId: paneId,
                source: source,
                emitted: false,
                snapshot: snapshot
            )
            return
        }
        lastPublishedSnapshot = snapshot
        WorkspaceBrowserDiagnostics.recordSnapshotPublish(
            surfaceId: surfaceId,
            tabId: tabId,
            paneId: paneId,
            source: source,
            emitted: true,
            snapshot: snapshot
        )
        stateObserver?(snapshot)
    }

    private static func resolvedNavigableURL(from rawInput: String) -> URL? {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let directURL = URL(string: trimmed),
           let scheme = directURL.scheme,
           !scheme.isEmpty {
            return directURL
        }

        if trimmed.contains(" ") {
            var components = URLComponents(string: "https://www.google.com/search")
            components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
            return components?.url
        }

        let lowercased = trimmed.lowercased()
        let looksLikeLocalHost =
            lowercased.hasPrefix("localhost")
            || lowercased.hasPrefix("127.0.0.1")
            || lowercased.hasPrefix("0.0.0.0")
            || lowercased.hasPrefix("[::1]")
        let schemePrefix = looksLikeLocalHost ? "http://" : "https://"
        return URL(string: schemePrefix + trimmed)
    }

    private static func defaultTitle(for urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "浏览器"
        }
        if let url = URL(string: trimmed),
           let host = url.host,
           !host.isEmpty {
            return host
        }
        return trimmed
    }

    fileprivate func recordNavigationEvent(
        phase: String,
        webView: WKWebView,
        error: Error?
    ) {
        WorkspaceBrowserDiagnostics.recordNavigationEvent(
            surfaceId: surfaceId,
            tabId: tabId,
            paneId: paneId,
            phase: phase,
            urlString: webView.url?.absoluteString ?? currentURLString,
            errorDescription: error?.localizedDescription
        )
    }
}

private final class NavigationDelegateProxy: NSObject, WKNavigationDelegate {
    weak var owner: WorkspaceBrowserHostModel?

    init(owner: WorkspaceBrowserHostModel) {
        self.owner = owner
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        owner?.recordNavigationEvent(phase: "didStartProvisionalNavigation", webView: webView, error: nil)
        owner?.syncNavigationState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        owner?.recordNavigationEvent(phase: "didFinish", webView: webView, error: nil)
        owner?.syncNavigationState()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        owner?.recordNavigationEvent(phase: "didFail", webView: webView, error: error)
        owner?.syncNavigationState()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        owner?.recordNavigationEvent(phase: "didFailProvisionalNavigation", webView: webView, error: error)
        owner?.syncNavigationState()
    }
}

@MainActor
final class WorkspaceBrowserSessionStore: ObservableObject {
    private var modelsByItemID: [String: WorkspaceBrowserHostModel] = [:]

    func model(
        for state: WorkspaceBrowserState,
        onStateChange: ((WorkspaceBrowserRuntimeSnapshot) -> Void)? = nil
    ) -> WorkspaceBrowserHostModel {
        if let existing = modelsByItemID[state.id] {
            existing.sync(state: state, stateObserver: onStateChange)
            return existing
        }

        let model = WorkspaceBrowserHostModel(state: state)
        model.sync(state: state, stateObserver: onStateChange)
        modelsByItemID[state.id] = model
        return model
    }

    func syncRetainedItemIDs(_ itemIDs: Set<String>) {
        let removedIDs = Set(modelsByItemID.keys).subtracting(itemIDs)
        for itemID in removedIDs {
            modelsByItemID.removeValue(forKey: itemID)
        }
    }
}
