import AppKit
import SwiftUI

/// 使用文件 URL 粘贴板调用真实终端的 AppKit 拖放回调，再由 shell 校验路径。
@MainActor
final class FileDraggingInfo: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    let draggingDestinationWindow: NSWindow?
    let draggingLocation: NSPoint
    let draggingSourceOperationMask: NSDragOperation = .copy
    let draggedImageLocation: NSPoint = .zero
    nonisolated var draggedImage: NSImage? { nil }
    let draggingSource: Any? = nil
    let draggingSequenceNumber = 1
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    init(target: NSView, urls: [URL]) {
        draggingDestinationWindow = target.window
        draggingLocation = target.convert(NSPoint(x: target.bounds.midX, y: target.bounds.midY), to: nil)
        draggingPasteboard = NSPasteboard(name: .init("devhaven.file-drop.\(UUID().uuidString)"))
        super.init()
        draggingPasteboard.writeObjects(urls.map { $0 as NSURL })
    }

    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions, for view: NSView?,
        classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}

@MainActor
@main
struct TerminalFileDropSmoke: App {
    @State private var store = CmuxEmbeddedHostStore()
    @State private var activePath = "/tmp"
    @State private var projects = [CmuxEmbeddedProject(path: "/tmp", name: "文件拖放测试一")]
    @State private var generation = 0
    @State private var started = false
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("devhaven-file-drop-\(UUID().uuidString)")

    var body: some Scene {
        WindowGroup("DevHaven 文件拖放回归") {
            CmuxEmbeddedHostView(workingDirectory: activePath, projects: projects, hostStore: store)
                .id(generation)
                .frame(width: 1100, height: 700)
                .onAppear {
                    guard !started else { return }
                    started = true
                    try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    later { run() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 75) { fail("测试超时") }
                }
        }
    }

    var window: NSWindow { NSApp.windows.first { $0.isVisible && $0.contentView != nil }! }
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    var dropTargets: [NSView] {
        descendants(window.contentView!.superview ?? window.contentView!).filter {
            String(reflecting: type(of: $0)).hasSuffix(".PaneDropTargetView") &&
                !$0.isHiddenOrHasHiddenAncestor && $0.bounds.width > 10 && $0.bounds.height > 10
        }
    }
    var terminals: [NSView] {
        descendants(window.contentView!.superview ?? window.contentView!).filter {
            String(reflecting: type(of: $0)).hasSuffix(".GhosttyNSView") &&
                !$0.isHiddenOrHasHiddenAncestor && $0.bounds.width > 10 && $0.bounds.height > 10
        }
    }
    var terminal: NSView {
        guard let view = window.firstResponder as? NSView,
              String(reflecting: type(of: view)).hasSuffix(".GhosttyNSView") else { fail("当前终端没有焦点") }
        return view
    }
    func later(_ action: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: action)
        }
    }
    func finish(_ code: Int32) -> Never {
        store.destroyAll()
        try? FileManager.default.removeItem(at: root)
        fflush(stdout)
        exit(code)
    }
    func fail(_ message: String) -> Never { print("FAIL: \(message)"); return finish(1) }
    func check(_ value: Bool, _ message: String) {
        guard value else { fail(message) }
        print("PASS: \(message)"); fflush(stdout)
    }

    func verifyDrop(_ label: String, names: [String], into destination: NSView? = nil,
        then next: @escaping @MainActor @Sendable () -> Void) {
        let view = destination ?? terminal
        let point = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        guard let target = dropTargets.first(where: { $0.convert($0.bounds, to: nil).contains(point) }) else {
            fail("找不到当前 pane 的拖放接收层")
        }
        let urls = names.map { root.appendingPathComponent($0) }
        for url in urls {
            if url.pathExtension == "txt" {
                check(FileManager.default.createFile(atPath: url.path, contents: Data("test".utf8)), "创建临时文件")
            } else {
                try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
        let output = root.appendingPathComponent("result-\(UUID().uuidString)")
        // 只向本测试的临时 shell 写入命令；拖入路径时不能自动按回车。
        view.insertText("printf '%s\\n' ")
        let sender = FileDraggingInfo(target: target, urls: urls)
        check(target.draggingEntered(sender) == .copy, "\(label)：接收文件拖入")
        check(target.draggingUpdated(sender) == .copy, "\(label)：保持拖放接收状态")
        check(target.prepareForDragOperation(sender), "\(label)：允许释放文件")
        check(target.performDragOperation(sender), "\(label)：投递路径")
        target.draggingEnded(sender)
        later {
            check(window.firstResponder === view, "\(label)：焦点落到目标终端")
            check(!FileManager.default.fileExists(atPath: output.path), "\(label)：没有自动执行命令")
            view.insertText(" > '\(output.path)'\n")
            later {
                let result = try? String(contentsOf: output, encoding: .utf8)
                check(result == urls.map(\.path).joined(separator: "\n") + "\n", "\(label)：shell 收到完整且正确转义的路径")
                next()
            }
        }
    }

    func run() {
        verifyDrop("普通目录", names: ["folder"]) {
            verifyDrop("中文、空格和特殊字符", names: ["中文 文件夹 ' $;", "second folder"]) {
                verifyDrop("普通文件", names: ["sample file.txt"]) {
                    check(CmuxEmbeddedWorkspaceActions.perform(.splitRight), "创建右侧分屏")
                    later {
                        verifyDrop("新分屏", names: ["split folder"]) {
                            guard let other = terminals.first(where: { $0 !== terminal }) else { fail("找不到另一分屏") }
                            verifyDrop("未聚焦分屏", names: ["unfocused folder"], into: other) {
                                projects.append(.init(path: "/private/tmp", name: "文件拖放测试二"))
                                activePath = "/private/tmp"
                                later {
                                    verifyDrop("切换项目", names: ["project folder"]) {
                                        activePath = "/tmp"
                                        generation += 1
                                        later {
                                            verifyDrop("返回项目并重挂宿主", names: ["remount folder"]) {
                                                print("PASS: terminal file drop regression complete")
                                                finish(0)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
