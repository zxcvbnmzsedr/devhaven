import AppKit
import SwiftUI
import WebKit

enum WorkspaceMarkdownRenderedContentLayout {
    case fitContent(minHeight: CGFloat = 120)
    case fillAvailableSpace

    var minimumHeight: CGFloat {
        switch self {
        case let .fitContent(minHeight):
            return max(0, minHeight)
        case .fillAvailableSpace:
            return 0
        }
    }

    var usesIntrinsicHeight: Bool {
        switch self {
        case .fitContent:
            return true
        case .fillAvailableSpace:
            return false
        }
    }
}

struct WorkspaceMarkdownRenderedContentView: View {
    let content: String
    var baseURL: URL?
    var layout: WorkspaceMarkdownRenderedContentLayout = .fitContent()

    @State private var contentHeight: CGFloat = 120

    var body: some View {
        let html = WorkspaceMarkdownHTMLRenderer.documentHTML(for: content, baseURL: baseURL)
        let minimumHeight = layout.minimumHeight

        Group {
            WorkspaceMarkdownWebView(
                html: html,
                baseURL: baseURL,
                layout: layout,
                contentHeight: $contentHeight
            )
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: layout.usesIntrinsicHeight ? nil : .infinity,
            alignment: .topLeading
        )
        .frame(
            height: layout.usesIntrinsicHeight ? max(minimumHeight, contentHeight) : nil,
            alignment: .topLeading
        )
    }
}

private struct WorkspaceMarkdownWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    let layout: WorkspaceMarkdownRenderedContentLayout
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight)
    }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: Coordinator.heightMessageName)
        controller.addUserScript(
            WKUserScript(
                source: Coordinator.heightObserverScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller

        let webView = WorkspaceMarkdownNativeWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = false
        context.coordinator.update(html: html, baseURL: baseURL, layout: layout, on: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.update(html: html, baseURL: baseURL, layout: layout, on: nsView)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.navigationDelegate = nil
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.heightMessageName)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let heightMessageName = "devhavenMarkdownHeight"
        static let heightObserverScript = """
        (function() {
          function postHeight() {
            var body = document.body;
            var doc = document.documentElement;
            if (!body || !doc || !window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.\(heightMessageName)) {
              return;
            }
            var height = Math.max(
              body.scrollHeight,
              body.offsetHeight,
              doc.clientHeight,
              doc.scrollHeight,
              doc.offsetHeight
            );
            window.webkit.messageHandlers.\(heightMessageName).postMessage(height);
          }
          window.addEventListener('load', postHeight);
          window.addEventListener('resize', postHeight);
          document.addEventListener('DOMContentLoaded', postHeight);
          if (window.ResizeObserver) {
            var observer = new ResizeObserver(function() { postHeight(); });
            observer.observe(document.documentElement);
          }
          Array.prototype.forEach.call(document.images, function(image) {
            if (!image.complete) {
              image.addEventListener('load', postHeight);
              image.addEventListener('error', postHeight);
            }
          });
          setTimeout(postHeight, 0);
          setTimeout(postHeight, 120);
          setTimeout(postHeight, 400);
        })();
        """

        @Binding private var contentHeight: CGFloat
        private var lastHTML: String?
        private var lastBaseURL: String?
        private var lastUsesIntrinsicHeight = true

        init(contentHeight: Binding<CGFloat>) {
            _contentHeight = contentHeight
        }

        func update(
            html: String,
            baseURL: URL?,
            layout: WorkspaceMarkdownRenderedContentLayout,
            on webView: WKWebView
        ) {
            let resolvedBaseURL = baseURL?.absoluteString
            let usesIntrinsicHeight = layout.usesIntrinsicHeight
            let shouldReload = lastHTML != html
                || lastBaseURL != resolvedBaseURL
                || lastUsesIntrinsicHeight != usesIntrinsicHeight

            lastHTML = html
            lastBaseURL = resolvedBaseURL
            lastUsesIntrinsicHeight = usesIntrinsicHeight

            configureEmbeddedScrollViewIfNeeded(in: webView, layout: layout)

            guard shouldReload else {
                if usesIntrinsicHeight {
                    evaluateHeight(on: webView)
                }
                return
            }

            webView.loadHTMLString(html, baseURL: baseURL)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let layout: WorkspaceMarkdownRenderedContentLayout = lastUsesIntrinsicHeight
                ? .fitContent(minHeight: 0)
                : .fillAvailableSpace
            configureEmbeddedScrollViewIfNeeded(in: webView, layout: layout)
            guard lastUsesIntrinsicHeight else {
                return
            }
            evaluateHeight(on: webView)
        }

        @MainActor
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.heightMessageName,
                  lastUsesIntrinsicHeight
            else {
                return
            }
            let resolvedHeight: CGFloat?
            if let value = message.body as? Double {
                resolvedHeight = CGFloat(value)
            } else if let value = message.body as? Int {
                resolvedHeight = CGFloat(value)
            } else {
                resolvedHeight = nil
            }
            guard let resolvedHeight else {
                return
            }
            DispatchQueue.main.async {
                self.contentHeight = max(120, resolvedHeight)
            }
        }

        private func evaluateHeight(on webView: WKWebView) {
            webView.evaluateJavaScript(
                "Math.max(document.body.scrollHeight, document.documentElement.scrollHeight, document.body.offsetHeight, document.documentElement.offsetHeight);"
            ) { [weak self] result, _ in
                guard let self else {
                    return
                }
                let resolvedHeight: CGFloat?
                if let value = result as? Double {
                    resolvedHeight = CGFloat(value)
                } else if let value = result as? Int {
                    resolvedHeight = CGFloat(value)
                } else {
                    resolvedHeight = nil
                }
                guard let resolvedHeight else {
                    return
                }
                DispatchQueue.main.async {
                    self.contentHeight = max(120, resolvedHeight)
                }
            }
        }

        private func configureEmbeddedScrollViewIfNeeded(
            in webView: WKWebView,
            layout: WorkspaceMarkdownRenderedContentLayout
        ) {
            for subview in webView.subviews {
                guard let scrollView = subview as? NSScrollView else {
                    continue
                }
                scrollView.hasVerticalScroller = !layout.usesIntrinsicHeight
                scrollView.hasHorizontalScroller = false
                scrollView.autohidesScrollers = true
                scrollView.drawsBackground = false
                scrollView.borderType = .noBorder
                scrollView.verticalScrollElasticity = layout.usesIntrinsicHeight ? .none : .automatic
                scrollView.horizontalScrollElasticity = .none
            }
        }
    }
}

private final class WorkspaceMarkdownNativeWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        if let outerScrollView = nearestAncestorScrollView() {
            outerScrollView.scrollWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }

    private func nearestAncestorScrollView() -> NSScrollView? {
        var candidate: NSView? = superview
        while let current = candidate {
            if let scrollView = current as? NSScrollView {
                return scrollView
            }
            candidate = current.superview
        }
        return nil
    }
}

private enum WorkspaceMarkdownWebRendererAssets {
    static let markedSource: String = loadMarkedSource()

    private static func loadMarkedSource() -> String {
        guard let resourceURL = DevHavenAppResourceLocator.resolveResourceURL(
            subdirectory: "MarkdownResources",
            resource: "marked.umd",
            withExtension: "js"
        ), let source = try? String(contentsOf: resourceURL, encoding: .utf8) else {
            return """
            window.marked = {
              parse: function(markdown) {
                const escaped = String(markdown)
                  .replace(/&/g, '&amp;')
                  .replace(/</g, '&lt;')
                  .replace(/>/g, '&gt;');
                return '<pre>' + escaped + '</pre>';
              }
            };
            """
        }

        // Prevent an embedded script body from accidentally terminating the host tag.
        return source.replacingOccurrences(of: "</script", with: "<\\/script")
    }
}

enum WorkspaceMarkdownHTMLRenderer {
    static func documentHTML(for markdown: String, baseURL: URL? = nil) -> String {
        let preprocessedMarkdown = preprocessMarkdownSource(markdown, baseURL: baseURL)
        let markdownLiteral = javaScriptStringLiteral(preprocessedMarkdown)
        let baseTag: String = {
            guard let baseURL else {
                return ""
            }
            return #"<base href="\#(escapeHTMLAttribute(normalizedBaseURLString(baseURL)))">"#
        }()

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          \(baseTag)
          <style>
            :root {
              color-scheme: dark;
              --bg: transparent;
              --fg: #e6edf3;
              --muted: #8b949e;
              --border: #30363d;
              --accent: #58a6ff;
              --canvas-subtle: #161b22;
              --canvas-default: #0d1117;
            }
            html, body {
              margin: 0;
              padding: 0;
              background: var(--bg);
              color: var(--fg);
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
              font-size: 14px;
              line-height: 1.6;
              overflow: auto;
            }
            .markdown-body {
              color: var(--fg);
              background: transparent;
              word-break: break-word;
              overflow-wrap: anywhere;
              overflow: hidden;
            }
            .markdown-body > *:first-child { margin-top: 0 !important; }
            .markdown-body > *:last-child { margin-bottom: 0 !important; }
            .markdown-body h1,
            .markdown-body h2,
            .markdown-body h3,
            .markdown-body h4,
            .markdown-body h5,
            .markdown-body h6 {
              margin: 24px 0 16px;
              font-weight: 600;
              line-height: 1.25;
            }
            .markdown-body h1,
            .markdown-body h2 {
              padding-bottom: 0.3em;
              border-bottom: 1px solid var(--border);
            }
            .markdown-body h1 { font-size: 2em; }
            .markdown-body h2 { font-size: 1.5em; }
            .markdown-body h3 { font-size: 1.25em; }
            .markdown-body h4 { font-size: 1em; }
            .markdown-body p,
            .markdown-body ul,
            .markdown-body ol,
            .markdown-body pre,
            .markdown-body blockquote,
            .markdown-body table {
              margin: 0 0 16px;
            }
            .markdown-body ul,
            .markdown-body ol {
              padding-left: 2em;
            }
            .markdown-body li + li {
              margin-top: 0.25em;
            }
            .markdown-body blockquote {
              margin-left: 0;
              padding: 0 1em;
              color: var(--muted);
              border-left: 0.25em solid var(--border);
            }
            .markdown-body code {
              font-family: ui-monospace, SFMono-Regular, SF Mono, Menlo, Consolas, monospace;
              font-size: 85%;
              padding: 0.2em 0.4em;
              background: rgba(110, 118, 129, 0.25);
              border-radius: 6px;
            }
            .markdown-body pre {
              padding: 16px;
              overflow: auto;
              background: var(--canvas-subtle);
              border: 1px solid var(--border);
              border-radius: 10px;
            }
            .markdown-body pre code {
              padding: 0;
              background: transparent;
              border-radius: 0;
            }
            .markdown-body a {
              color: var(--accent);
              text-decoration: none;
            }
            .markdown-body a:hover {
              text-decoration: underline;
            }
            .markdown-body hr {
              height: 1px;
              margin: 24px 0;
              background: var(--border);
              border: 0;
            }
            .markdown-body img {
              display: block;
              max-width: 100%;
              height: auto;
              margin: 12px 0;
              border-radius: 8px;
              border: 1px solid var(--border);
              background: var(--canvas-default);
            }
            .markdown-body table {
              width: 100%;
              border-collapse: collapse;
              display: block;
              overflow-x: auto;
            }
            .markdown-body th,
            .markdown-body td {
              padding: 6px 13px;
              border: 1px solid var(--border);
            }
            .markdown-body tr:nth-child(2n) {
              background: rgba(110, 118, 129, 0.08);
            }
            .markdown-body input[type="checkbox"] {
              margin-right: 0.45em;
            }
          </style>
        </head>
        <body>
          <div id="markdown-root" class="markdown-body"></div>
          <script>
          \(WorkspaceMarkdownWebRendererAssets.markedSource)
          </script>
          <script>
            (function() {
              const source = \(markdownLiteral);
              const container = document.getElementById('markdown-root');
              const seenSlugs = Object.create(null);

              function slugifyHeading(text) {
                const base = text
                  .toLowerCase()
                  .normalize('NFKD')
                  .replace(/[\\u0300-\\u036f]/g, '')
                  .trim()
                  .replace(/\\s+/g, '-')
                  .replace(/[^\\p{Letter}\\p{Number}_-]/gu, '')
                  .replace(/-+/g, '-');
                const slug = base || 'section';
                const count = seenSlugs[slug] || 0;
                seenSlugs[slug] = count + 1;
                return count === 0 ? slug : slug + '-' + count;
              }

              const renderedHTML = window.marked.parse(source, {
                gfm: true,
                breaks: false
              });
              container.innerHTML = renderedHTML;

              container.querySelectorAll('h1, h2, h3, h4, h5, h6').forEach((heading) => {
                if (!heading.id) {
                  heading.id = slugifyHeading(heading.textContent || '');
                }
              });
            })();
          </script>
        </body>
        </html>
        """
    }

    private static func preprocessMarkdownSource(_ markdown: String, baseURL: URL?) -> String {
        var rewritten = markdown
        rewritten = rewriteRawHTMLImageSources(in: rewritten, baseURL: baseURL)
        rewritten = rewriteMarkdownImageSources(in: rewritten, baseURL: baseURL)
        return rewritten
    }

    private static func rewriteRawHTMLImageSources(in markdown: String, baseURL: URL?) -> String {
        replace(
            in: markdown,
            pattern: #"(<img\b[^>]*\bsrc\s*=\s*["'])([^"']+)(["'][^>]*>)"#
        ) { groups in
            guard groups.count == 3 else {
                return markdown
            }
            return groups[0] + resolvedImageSource(groups[1], baseURL: baseURL) + groups[2]
        }
    }

    private static func rewriteMarkdownImageSources(in markdown: String, baseURL: URL?) -> String {
        replace(
            in: markdown,
            pattern: #"!\[([^\]]*)\]\(([^)\s]+)(?:\s+"([^"]*)")?\)"#
        ) { groups in
            guard groups.count >= 2 else {
                return markdown
            }
            let alt = groups[0]
            let source = resolvedImageSource(groups[1], baseURL: baseURL)
            let titleSuffix: String
            if groups.count >= 3, !groups[2].isEmpty {
                titleSuffix = #" "\#(groups[2])""#
            } else {
                titleSuffix = ""
            }
            return "![\(alt)](\(source)\(titleSuffix))"
        }
    }

    private static func normalizedBaseURLString(_ url: URL) -> String {
        let absoluteString = url.absoluteString
        guard url.hasDirectoryPath, !absoluteString.hasSuffix("/") else {
            return absoluteString
        }
        return absoluteString + "/"
    }

    private static func javaScriptStringLiteral(_ string: String) -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(string),
              let literal = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return literal
    }

    private static func resolvedImageSource(_ source: String, baseURL: URL?) -> String {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL, baseURL.isFileURL,
              let localFileURL = resolvedLocalFileURL(for: trimmedSource, baseURL: baseURL),
              let dataURL = localImageDataURL(for: localFileURL) else {
            return trimmedSource
        }
        return dataURL
    }

    private static func resolvedLocalFileURL(for source: String, baseURL: URL) -> URL? {
        guard !source.isEmpty,
              !hasExternalScheme(source),
              !source.hasPrefix("data:"),
              !source.hasPrefix("#")
        else {
            return nil
        }

        if source.hasPrefix("/") {
            return URL(fileURLWithPath: source)
        }

        return URL(string: source, relativeTo: baseURL)?.standardizedFileURL
    }

    private static func localImageDataURL(for fileURL: URL) -> String? {
        guard let data = try? Data(contentsOf: fileURL),
              let mimeType = imageMimeType(for: fileURL) else {
            return nil
        }
        return "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    private static func hasExternalScheme(_ source: String) -> Bool {
        guard let parsedURL = URL(string: source),
              let scheme = parsedURL.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https" || scheme == "mailto"
    }

    private static func imageMimeType(for fileURL: URL) -> String? {
        switch fileURL.pathExtension.lowercased() {
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "svg":
            return "image/svg+xml"
        default:
            return nil
        }
    }

    private static func replace(
        in text: String,
        pattern: String,
        transform: ([String]) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)
        guard !matches.isEmpty else {
            return text
        }

        var result = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else {
                continue
            }
            let groups: [String] = (1..<match.numberOfRanges).compactMap { index in
                guard let groupRange = Range(match.range(at: index), in: result) else {
                    return nil
                }
                return String(result[groupRange])
            }
            result.replaceSubrange(range, with: transform(groups))
        }
        return result
    }

    private static func escapeHTMLAttribute(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
