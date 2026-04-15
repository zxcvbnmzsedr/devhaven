import SwiftUI
import WebKit

func workspaceMonacoLanguageID(forFilePath candidatePath: String) -> String {
    let fileName = URL(fileURLWithPath: candidatePath).lastPathComponent.lowercased()
    if fileName == "package.resolved" {
        return "json"
    }
    if fileName == ".gitignore" {
        return "plaintext"
    }

    switch URL(fileURLWithPath: candidatePath).pathExtension.lowercased() {
    case "swift":
        return "swift"
    case "json":
        return "json"
    case "md", "markdown":
        return "markdown"
    case "yml", "yaml":
        return "yaml"
    case "sh", "bash", "zsh", "fish", "command":
        return "shell"
    case "js", "mjs", "cjs", "jsx":
        return "javascript"
    case "ts", "tsx":
        return "typescript"
    case "css", "scss", "less":
        return "css"
    case "html", "htm", "xhtml":
        return "html"
    case "xml", "plist", "xib", "storyboard", "svg":
        return "xml"
    case "toml", "ini", "properties", "env":
        return "ini"
    case "m", "mm", "h":
        return "objective-c"
    case "c", "cc", "cpp", "cxx", "hpp", "hh", "hxx":
        return "cpp"
    case "cs":
        return "csharp"
    case "java":
        return "java"
    case "kt", "kts":
        return "kotlin"
    case "py":
        return "python"
    case "rb":
        return "ruby"
    case "go":
        return "go"
    case "rs":
        return "rust"
    case "sql":
        return "sql"
    default:
        return "plaintext"
    }
}

func workspaceMonacoThemeName(for colorScheme: ColorScheme) -> String {
    colorScheme == .dark ? "vs-dark" : "vs"
}

func workspaceMonacoLanguageLabel(for languageID: String) -> String {
    switch languageID {
    case "swift":
        return "Swift"
    case "typescript":
        return "TypeScript"
    case "javascript":
        return "JavaScript"
    case "markdown":
        return "Markdown"
    case "json":
        return "JSON"
    case "yaml":
        return "YAML"
    case "shell":
        return "Shell"
    case "html":
        return "HTML"
    case "css":
        return "CSS"
    case "xml":
        return "XML"
    case "ini":
        return "TOML/INI"
    case "objective-c":
        return "Objective-C"
    case "cpp":
        return "C/C++"
    case "csharp":
        return "C#"
    case "java":
        return "Java"
    case "kotlin":
        return "Kotlin"
    case "python":
        return "Python"
    case "ruby":
        return "Ruby"
    case "go":
        return "Go"
    case "rust":
        return "Rust"
    case "sql":
        return "SQL"
    default:
        return "Plain Text"
    }
}

struct WorkspaceEmbeddedWebViewContainer: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> ContainerView {
        let view = ContainerView()
        view.host(webView)
        return view
    }

    func updateNSView(_ nsView: ContainerView, context: Context) {
        nsView.host(webView)
    }

    final class ContainerView: NSView {
        private weak var hostedWebView: WKWebView?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        func host(_ webView: WKWebView) {
            if hostedWebView !== webView {
                hostedWebView?.removeFromSuperview()
                hostedWebView = webView
                addSubview(webView)
            }
            webView.frame = bounds
            needsLayout = true
        }

        override func layout() {
            super.layout()
            hostedWebView?.frame = bounds
        }
    }
}
