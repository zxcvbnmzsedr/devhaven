import AppKit
import SwiftUI
import WebKit

struct WorkspaceGitHubRenderedContentView: View {
    let content: String
    @State private var contentHeight: CGFloat = 120

    var body: some View {
        WorkspaceGitHubMarkdownWebView(
            html: WorkspaceGitHubMarkdownHTMLRenderer.documentHTML(for: content),
            contentHeight: $contentHeight
        )
        .frame(height: max(120, contentHeight))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WorkspaceGitHubMarkdownWebView: NSViewRepresentable {
    let html: String
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight)
    }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: Coordinator.heightMessageName)
        controller.addUserScript(WKUserScript(
            source: Coordinator.heightObserverScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller

        let webView = WorkspaceGitHubMarkdownNativeWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = false
        context.coordinator.update(html: html, on: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.update(html: html, on: nsView)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.navigationDelegate = nil
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.heightMessageName)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let heightMessageName = "devhavenGitHubHeight"
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

        init(contentHeight: Binding<CGFloat>) {
            _contentHeight = contentHeight
        }

        func update(html: String, on webView: WKWebView) {
            guard lastHTML != html else {
                evaluateHeight(on: webView)
                return
            }
            lastHTML = html
            configureEmbeddedScrollViewIfNeeded(in: webView)
            webView.loadHTMLString(html, baseURL: URL(string: "https://github.com"))
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            configureEmbeddedScrollViewIfNeeded(in: webView)
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
            guard message.name == Self.heightMessageName else {
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

        private func configureEmbeddedScrollViewIfNeeded(in webView: WKWebView) {
            for subview in webView.subviews {
                guard let scrollView = subview as? NSScrollView else {
                    continue
                }
                scrollView.hasVerticalScroller = false
                scrollView.hasHorizontalScroller = false
                scrollView.autohidesScrollers = true
                scrollView.drawsBackground = false
                scrollView.borderType = .noBorder
                scrollView.verticalScrollElasticity = .none
                scrollView.horizontalScrollElasticity = .none
            }
        }
    }
}

private final class WorkspaceGitHubMarkdownNativeWebView: WKWebView {
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

private enum WorkspaceGitHubMarkdownHTMLRenderer {
    private enum ListKind {
        case unordered
        case ordered

        var tagName: String {
            switch self {
            case .unordered:
                return "ul"
            case .ordered:
                return "ol"
            }
        }
    }

    static func documentHTML(for markdown: String) -> String {
        let body = renderBlocks(markdown)
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
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
              --success: #3fb950;
            }
            html, body {
              margin: 0;
              padding: 0;
              background: var(--bg);
              color: var(--fg);
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
              font-size: 14px;
              line-height: 1.6;
              overflow: hidden;
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
          </style>
        </head>
        <body>
          <div class="markdown-body">\(body)</div>
        </body>
        </html>
        """
    }

    private static func renderBlocks(_ markdown: String) -> String {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var htmlBlocks: [String] = []
        var paragraphLines: [String] = []
        var listKind: ListKind?
        var listItems: [String] = []
        var codeBlockLines: [String] = []
        var codeBlockLanguage: String?
        var inCodeBlock = false
        var blockquoteLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else {
                return
            }
            let paragraph = paragraphLines.joined(separator: " ")
            htmlBlocks.append("<p>\(renderInline(paragraph))</p>")
            paragraphLines.removeAll()
        }

        func flushList() {
            guard let listKind, !listItems.isEmpty else {
                listItems.removeAll()
                return
            }
            let items = listItems.map { "<li>\($0)</li>" }.joined()
            htmlBlocks.append("<\(listKind.tagName)>\(items)</\(listKind.tagName)>")
            selfResetList()
        }

        func selfResetList() {
            listKind = nil
            listItems.removeAll()
        }

        func flushCodeBlock() {
            guard inCodeBlock else {
                return
            }
            let languageClass: String
            if let codeBlockLanguage,
               !codeBlockLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                languageClass = " class=\"language-\(escapeHTMLAttribute(codeBlockLanguage))\""
            } else {
                languageClass = ""
            }
            let code = escapeHTML(codeBlockLines.joined(separator: "\n"))
            htmlBlocks.append("<pre><code\(languageClass)>\(code)</code></pre>")
            inCodeBlock = false
            codeBlockLines.removeAll()
            codeBlockLanguage = nil
        }

        func flushBlockquote() {
            guard !blockquoteLines.isEmpty else {
                return
            }
            let quoteContent = renderBlocks(blockquoteLines.joined(separator: "\n"))
            htmlBlocks.append("<blockquote>\(quoteContent)</blockquote>")
            blockquoteLines.removeAll()
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if inCodeBlock {
                if trimmed.hasPrefix("```") {
                    flushCodeBlock()
                } else {
                    codeBlockLines.append(line)
                }
                continue
            }

            if trimmed.hasPrefix("```") {
                flushParagraph()
                flushList()
                flushBlockquote()
                inCodeBlock = true
                let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                codeBlockLanguage = language.isEmpty ? nil : language
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                flushList()
                flushBlockquote()
                continue
            }

            if let quoteLine = capture(in: line, pattern: #"^\s*>\s?(.*)$"#, group: 1) {
                flushParagraph()
                flushList()
                blockquoteLines.append(quoteLine)
                continue
            } else {
                flushBlockquote()
            }

            if isRawHTMLBlock(trimmed) {
                flushParagraph()
                flushList()
                htmlBlocks.append(trimmed)
                continue
            }

            if isHorizontalRule(trimmed) {
                flushParagraph()
                flushList()
                htmlBlocks.append("<hr />")
                continue
            }

            if let headingHashes = capture(in: line, pattern: #"^\s*(#{1,6})\s+(.+)$"#, group: 1),
               let headingText = capture(in: line, pattern: #"^\s*(#{1,6})\s+(.+)$"#, group: 2) {
                flushParagraph()
                flushList()
                let level = min(6, headingHashes.count)
                htmlBlocks.append("<h\(level)>\(renderInline(headingText))</h\(level)>")
                continue
            }

            if let unorderedItem = capture(in: line, pattern: #"^\s*[-*+]\s+(.+)$"#, group: 1) {
                flushParagraph()
                if listKind != .unordered {
                    flushList()
                    listKind = .unordered
                }
                listItems.append(renderInline(unorderedItem))
                continue
            }

            if let orderedItem = capture(in: line, pattern: #"^\s*\d+\.\s+(.+)$"#, group: 1) {
                flushParagraph()
                if listKind != .ordered {
                    flushList()
                    listKind = .ordered
                }
                listItems.append(renderInline(orderedItem))
                continue
            }

            flushList()
            paragraphLines.append(trimmed)
        }

        flushParagraph()
        flushList()
        flushBlockquote()
        flushCodeBlock()

        return htmlBlocks.joined(separator: "\n")
    }

    private static func renderInline(_ text: String) -> String {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ""
        }

        var working = text
        var placeholders: [String: String] = [:]
        var placeholderIndex = 0

        func makePlaceholder(for html: String) -> String {
            let token = "DEVHAVENPLACEHOLDERTOKEN\(placeholderIndex)END"
            placeholderIndex += 1
            placeholders[token] = html
            return token
        }

        working = replace(
            in: working,
            pattern: #"!\[([^\]]*)\]\((https?://[^\s)]+)(?:\s+"[^"]*")?\)"#
        ) { groups in
            let alt = escapeHTMLAttribute(groups[0])
            let url = escapeHTMLAttribute(groups[1])
            return makePlaceholder(for: #"<img src="\#(url)" alt="\#(alt)" />"#)
        }

        working = replace(
            in: working,
            pattern: #"\[([^\]]+)\]\((https?://[^\s)]+)(?:\s+"[^"]*")?\)"#
        ) { groups in
            let title = escapeHTML(groups[0])
            let url = escapeHTMLAttribute(groups[1])
            return makePlaceholder(for: #"<a href="\#(url)">\#(title)</a>"#)
        }

        working = replace(
            in: working,
            pattern: #"`([^`]+)`"#
        ) { groups in
            makePlaceholder(for: "<code>\(escapeHTML(groups[0]))</code>")
        }

        working = escapeHTML(working)

        working = replaceSimple(in: working, pattern: #"\*\*([^*]+)\*\*"#, template: "<strong>$1</strong>")
        working = replaceSimple(in: working, pattern: #"__([^_]+)__"#, template: "<strong>$1</strong>")
        working = replaceSimple(in: working, pattern: #"~~([^~]+)~~"#, template: "<del>$1</del>")
        working = replaceSimple(in: working, pattern: #"(?<!\*)\*([^*]+)\*(?!\*)"#, template: "<em>$1</em>")
        working = replaceSimple(in: working, pattern: #"(?<!_)_([^_]+)_(?!_)"#, template: "<em>$1</em>")

        for token in placeholders.keys.sorted(by: { $0.count > $1.count }) {
            if let html = placeholders[token] {
                working = working.replacingOccurrences(of: token, with: html)
            }
        }

        return working
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

    private static func replaceSimple(in text: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: nsRange, withTemplate: template)
    }

    private static func capture(in text: String, pattern: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
              let range = Range(match.range(at: group), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private static func isRawHTMLBlock(_ text: String) -> Bool {
        text.hasPrefix("<img")
            || text.hasPrefix("<p")
            || text.hasPrefix("<div")
            || text.hasPrefix("<table")
            || text.hasPrefix("<details")
            || text.hasPrefix("<summary")
            || text.hasPrefix("<br")
    }

    private static func isHorizontalRule(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "")
        return compact == "---" || compact == "***" || compact == "___"
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeHTMLAttribute(_ text: String) -> String {
        escapeHTML(text)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
