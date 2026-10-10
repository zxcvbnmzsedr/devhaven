import AppKit
import SwiftUI
import CmuxFoundation
import Combine

/// Exercises the actual sidebar NSMenu actions in the packaged framework.
@MainActor
@main
struct WorkspaceGroupSmoke: App {
    @State private var store = CmuxEmbeddedHostStore()
    @State private var projects = CommandLine.arguments.contains("--restore-read") || CommandLine.arguments.contains("--restore-deleted")
        ? [CmuxEmbeddedProject(path: "/tmp", name: "First project"), CmuxEmbeddedProject(path: "/private/tmp", name: "Second project")]
        : [CmuxEmbeddedProject(path: "/tmp", name: "First project")]
    @State private var pickerRequests = 0
    @State private var closedProjects: [String] = []
    @State private var generation = 0
    @State private var started = false

    var body: some Scene {
        WindowGroup("DevHaven workspace group regression") {
            CmuxEmbeddedHostView(workingDirectory: "/tmp", projects: projects, hostStore: store)
                .id(generation)
                .frame(width: 1100, height: 700)
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DevHaven.CmuxEmbedded.OpenProjectPicker"))) { _ in
                    pickerRequests += 1
                }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DevHaven.CmuxEmbedded.ClosedProject"))) { notification in
                    if let path = notification.object as? String { closedProjects.append(path) }
                }
                .onAppear {
                    guard !started else { return }
                    started = true
                    later {
                        if CommandLine.arguments.contains("--restore-read") {
                            verifyRestoredLayout(removeGroup: true)
                        } else if CommandLine.arguments.contains("--restore-deleted") {
                            verifyRestoredLayout(removeGroup: false)
                        } else { run() }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 60) { fail("timed out") }
                }
        }
    }

    func field(_ value: Any, _ name: String) -> Any? {
        Mirror(reflecting: value).children.first { $0.label == name }?.value
    }

    func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    var window: NSWindow { NSApp.windows.first { $0.contentView != nil && $0.isVisible }! }
    var views: [NSView] { descendants(window.contentView!.superview ?? window.contentView!) }
    var host: NSView { views.first { field($0, "tabManager") != nil }! }
    var manager: Any { field(host, "tabManager")! }
    var workspaceCount: Int { Mirror(reflecting: field(manager, "workspacesById")!).children.count }
    var groupNames: [String] {
        let model = field(manager, "workspaces")!
        let groups = field(model, "_workspaceGroups") ?? field(model, "workspaceGroups")!
        return Mirror(reflecting: groups).children.compactMap { field($0.value, "name") as? String }
    }
    var projectIDs: [String: UUID] { field(host, "projectWorkspaceIds") as! [String: UUID] }
    var mappedProjectCount: Int { projectIDs.count }
    var groups: [Any] {
        let model = field(manager, "workspaces")!
        return (field(model, "_workspaceGroups") ?? field(model, "workspaceGroups")) as! [Any]
    }
    var workspaces: [Any] {
        let model = field(manager, "workspaces")!
        return (field(model, "_tabs") ?? field(model, "tabs")) as! [Any]
    }
    var tableActions: Any {
        let table = views.compactMap { $0 as? NSTableView }.first!
        return field(field(table.delegate!, "actions")!, "some")!
    }

    func groupID(of workspace: Any) -> UUID? {
        var membership = field(workspace, "_groupId") as! Published<UUID?>
        var value: UUID?
        let subscription = membership.projectedValue.sink { value = $0 }
        subscription.cancel()
        return value
    }

    func dropProject(_ path: String, intoGroupAt groupIndex: Int) {
        let group = groups[groupIndex]
        let groupID = field(group, "id") as! UUID
        let groupMembers = workspaces.enumerated().filter {
            self.groupID(of: $0.element) == groupID
        }
        let insertionIndex = groupMembers.last!.offset + 1
        let id = projectIDs[path]!
        let sourceIndex = workspaces.firstIndex { field($0, "id") as? UUID == id }!
        check(sourceIndex != insertionIndex && sourceIndex + 1 != insertionIndex,
              "drop actually reorders the dragged project")
        let commit = field(tableActions, "commitWorkspaceDropPlan") as! (SidebarWorkspaceReorderDropPlan) -> Bool
        _ = commit(.init(draggedWorkspaceId: id, indicator: nil,
                         action: .reorder(targetIndex: insertionIndex, usesTopLevelRows: false, explicitGroupId: groupID)))
    }

    func verifyGroupDrops(then finish: @escaping @MainActor @Sendable () -> Void) {
        let originalIDs = projectIDs
        dropProject("/private/tmp", intoGroupAt: 1)
        later {
            check(projectIDs == originalIDs && closedProjects.isEmpty && pickerRequests == 0,
                  "dragging second project into a group preserves mappings without close/picker events")
            let groupID = field(groups[1], "id") as! UUID
            let second = workspaces.first { field($0, "id") as? UUID == originalIDs["/private/tmp"] }!
            check(self.groupID(of: second) == groupID,
                  "second project belongs to the target group")
            dropProject("/private/tmp", intoGroupAt: 0)
            later {
                check(projectIDs == originalIDs && closedProjects.isEmpty && pickerRequests == 0,
                      "moving between groups preserves both project sessions")
                let movedProject = workspaces.first { field($0, "id") as? UUID == originalIDs["/private/tmp"] }!
                check(self.groupID(of: movedProject) == field(groups[0], "id") as? UUID,
                      "cross-group drop applies the new membership")
                let close = field(tableActions, "closeWorkspace") as! (UUID) -> Void
                close(originalIDs["/private/tmp"]!)
                later {
                    check(projectIDs["/private/tmp"] == nil && projectIDs["/tmp"] == originalIDs["/tmp"] &&
                          closedProjects == ["/private/tmp"] && pickerRequests == 0,
                          "a real close still removes exactly its project and never opens the picker")
                    finish()
                }
            }
        }
    }

    func clickGroupMenu(_ title: String, groupID: UUID) {
        guard let view = views.first(where: { view in
            guard String(reflecting: type(of: view)).hasSuffix(".SidebarGroupHeaderTableCellView"),
                  let model = field(field(view, "model")!, "some") else { return false }
            return field(model, "groupId") as? UUID == groupID
        }), let event = NSEvent.mouseEvent(with: .rightMouseDown,
            location: view.convert(NSPoint(x: 80, y: 10), to: nil), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1),
              let item = view.menu(for: event)?.items.first(where: { $0.title == title }),
              let action = item.action else { fail("missing group menu: \(title)") }
        check(NSApp.sendAction(action, to: item.target, from: item), "group menu dispatched: \(title)")
    }

    func moveProjectsToGroup(_ paths: [String], groupID: UUID, then finish: @escaping @MainActor @Sendable () -> Void) {
        guard let path = paths.first else { finish(); return }
        let id = projectIDs[path]!
        let group = groups.first { field($0, "id") as? UUID == groupID }!
        let groupName = field(group, "name") as! String
        guard let view = views.first(where: { view in
            guard String(reflecting: type(of: view)).hasSuffix(".SidebarWorkspaceRowTableCellView"),
                  let model = field(field(view, "model")!, "some") else { return false }
            return field(model, "workspaceId") as? UUID == id
        }), let event = NSEvent.mouseEvent(with: .rightMouseDown,
            location: view.convert(NSPoint(x: 80, y: 10), to: nil), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1),
              let menu = view.menu(for: event),
              let submenu = menu.items.first(where: { $0.title == String(localized: "contextMenu.workspaceGroup.moveTo", defaultValue: "Move to Group") })?.submenu,
              let item = submenu.items.first(where: { $0.title == groupName }), item.isEnabled,
              let action = item.action else { fail("missing move-to-group menu for \(path)") }
        check(NSApp.sendAction(action, to: item.target, from: item), "project move-to-group menu dispatched: \(path)")
        later {
            let workspace = workspaces.first { field($0, "id") as? UUID == id }!
            check(self.groupID(of: workspace) == groupID, "project joined the group: \(path)")
            moveProjectsToGroup(Array(paths.dropFirst()), groupID: groupID, then: finish)
        }
    }

    func verifyGroupWorkspace() {
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("devhaven-group-smoke-\(UUID())")
        // /tmp 与 /private/tmp 是同一目录。四项目用例必须使用四个不同目录。
        let extraPaths = ["second project", "third'project", "fourth project"].map { fixture.appendingPathComponent($0).path }
        for path in extraPaths { try! FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true) }
        let capture = fixture.appendingPathComponent("argv.bin")
        let fakeCodex = fixture.appendingPathComponent("fake-codex")
        let quotedCapture = "'" + capture.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        try! "#!/bin/bash\nprintf '%s\\0' \"$PWD\" \"$@\" > \(quotedCapture)\nsleep 20\n".write(to: fakeCodex, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCodex.path)
        setenv("DEVHAVEN_TEST_REAL_CODEX", fakeCodex.path, 1)
        projects = projects.filter { $0.path != "/private/tmp" }
            + extraPaths.enumerated().map { .init(path: $0.element, name: "Project \($0.offset + 2)") }
        later {
            let originalIDs = projectIDs
            let groupID = field(groups[0], "id") as! UUID
            moveProjectsToGroup(projects.map(\.path), groupID: groupID) {
                let root = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".devhaven/workspaces/cmux-group--\(groupID.uuidString.lowercased())")
                let manifest = try! JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("WORKSPACE.json"))) as! [String: Any]
                let members = manifest["members"] as! [[String: String]]
                check(members.count == 4 && Set(members.compactMap { $0["path"] }) == Set(projects.map(\.path)),
                      "group root includes all four actual projects")
                check(projectIDs == originalIDs && closedProjects.isEmpty && pickerRequests == 0,
                      "group membership retains every project session")
                clickGroupMenu("打开分组终端", groupID: groupID)
                later {
                    check(projectIDs == originalIDs && closedProjects.isEmpty && pickerRequests == 0,
                          "group terminal is separate from member projects")
                    clickGroupMenu("启动分组 Codex", groupID: groupID)
                    later {
                        guard let data = try? Data(contentsOf: capture) else { fail("fake Codex did not launch") }
                        let args = String(decoding: data, as: UTF8.self).split(separator: "\0").map(String.init)
                        check(args.first == root.path && args.dropFirst().prefix(2) == ["--cd", root.path],
                              "Codex starts in the shared group directory")
                        let scope = args.enumerated().compactMap { index, arg in arg == "--add-dir" ? args[index + 1] : nil }
                        check(scope.count == 4 && Set(scope) == Set(projects.map(\.path)),
                              "one Codex receives all four real paths including spaces and quotes")
                        check(projectIDs == originalIDs && closedProjects.isEmpty && pickerRequests == 0,
                              "launching group Codex leaves member terminals intact")
                        store.destroyAll()
                        try? FileManager.default.removeItem(at: root)
                        try? FileManager.default.removeItem(at: fixture)
                        print("PASS: workspace group regression complete"); fflush(stdout); exit(0)
                    }
                }
            }
        }
    }

    func later(_ action: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: action)
    }

    func fail(_ message: String) -> Never {
        print("FAIL: \(message)")
        fflush(stdout)
        store.destroyAll()
        exit(1)
    }

    func check(_ condition: Bool, _ message: String) {
        guard condition else {
            fail("\(message); groups=\(groupNames) workspaces=\(workspaceCount) projects=\(mappedProjectCount) picker=\(pickerRequests)")
        }
        print("PASS: \(message)")
        fflush(stdout)
    }

    func createGroup(fromEmptyArea: Bool) {
        let typeSuffix = fromEmptyArea ? ".SidebarWorkspaceTableClipView" : ".SidebarWorkspaceRowTableCellView"
        guard let view = views.first(where: { String(reflecting: type(of: $0)).hasSuffix(typeSuffix) }),
              let event = NSEvent.mouseEvent(with: .rightMouseDown,
                location: view.convert(NSPoint(x: 10, y: view.bounds.maxY - 5), to: nil),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1),
              let menu = view.menu(for: event),
              let item = menu.items.first(where: { $0.title == String(localized: "contextMenu.workspaceGroup.newEmpty", defaultValue: "New Empty Workspace Group") }),
              item.isEnabled, let action = item.action else {
            fail("missing enabled group menu for \(typeSuffix)")
        }
        if !fromEmptyArea {
            let colors = menu.items.first { $0.title == "工作区颜色" }?.submenu?.items.map(\.title) ?? []
            check(colors.contains("红色") && colors.contains("炭灰色") && !colors.contains("Red"),
                  "native color submenu uses Chinese display names")
        }
        check(NSApp.sendAction(action, to: item.target, from: item), "sidebar menu action dispatched")
    }

    func groupAction(_ name: String, groupID: UUID) {
        guard let view = views.first(where: { view in
            guard String(reflecting: type(of: view)).hasSuffix(".SidebarGroupHeaderTableCellView"),
                  let model = field(field(view, "model")!, "some") else { return false }
            return field(model, "groupId") as? UUID == groupID
        }), let actions = field(field(view, "actions")!, "some"),
              let action = field(actions, name) as? () -> Void else {
            fail("missing group action \(name)")
        }
        action()
    }

    func layoutSignature() -> Data {
        let paths = Dictionary(uniqueKeysWithValues: projectIDs.map { ($0.value, $0.key) })
        let rows = workspaces.map { workspace -> String in
            let id = field(workspace, "id") as! UUID
            return paths[id] ?? "anchor:\(groupID(of: workspace)!.uuidString)"
        }
        let metadata: [[String: Any]] = groups.map { group in
            let id = field(group, "id") as! UUID
            return ["id": id.uuidString, "name": field(group, "name") as! String,
                    "collapsed": field(group, "isCollapsed") as! Bool,
                    "pinned": field(group, "isPinned") as! Bool,
                    "members": workspaces.filter { groupID(of: $0) == id }.compactMap { paths[field($0, "id") as! UUID] }]
        }
        return try! JSONSerialization.data(withJSONObject: ["groups": metadata, "rows": rows], options: [.sortedKeys])
    }

    func preparePersistentLayout() {
        dropProject("/private/tmp", intoGroupAt: 1)
        later {
            let id = field(groups[1], "id") as! UUID
            clickGroupMenu("打开分组终端", groupID: id)
            UserDefaults.standard.set(id.uuidString, forKey: "smoke.groupRootId")
            groupAction("onToggleCollapsed", groupID: id)
            groupAction("onTogglePinned", groupID: id)
            later {
                check(pickerRequests == 0 && closedProjects.isEmpty, "group layout edits do not close or open projects")
                UserDefaults.standard.set(layoutSignature(), forKey: "smoke.expectedLayout")
                UserDefaults.standard.set(projectIDs.mapValues(\.uuidString), forKey: "smoke.oldProjectIds")
                // Exit without destroying the host: exercise app-termination saving.
                NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: NSApp)
                UserDefaults.standard.synchronize()
                check(UserDefaults.standard.data(forKey: "DevHaven.CmuxEmbedded.ProjectLayout.v1") != nil,
                      "group layout saved before process exit")
                print("PASS: group restore write complete"); fflush(stdout)
                exit(0)
            }
        }
    }

    func verifyRestoredLayout(removeGroup: Bool) {
        check(mappedProjectCount == 2 && pickerRequests == 0 && closedProjects.isEmpty,
              "fresh process restores both projects without close/picker events")
        check(layoutSignature() == UserDefaults.standard.data(forKey: "smoke.expectedLayout"),
              "fresh process preserves group identity/name/order/membership/collapse/pin including empty group")
        let oldIDs = UserDefaults.standard.dictionary(forKey: "smoke.oldProjectIds") as! [String: String]
        check(projectIDs.allSatisfy { oldIDs[$0.key] != $0.value.uuidString },
              "restoration maps project paths to newly created workspace IDs")
        if let saved = UserDefaults.standard.string(forKey: "smoke.groupRootId"), let id = UUID(uuidString: saved) {
            let root = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".devhaven/workspaces/cmux-group--\(id.uuidString.lowercased())")
            let pathsByID = Dictionary(uniqueKeysWithValues: projectIDs.map { ($0.value, $0.key) })
            guard let anchor = workspaces.first(where: {
                groupID(of: $0) == id && pathsByID[field($0, "id") as! UUID] == nil
            }), var directory = field(anchor, "_currentDirectory") as? Published<String> else {
                fail("restored group has no dedicated anchor")
            }
            var currentDirectory = ""
            let subscription = directory.projectedValue.sink { currentDirectory = $0 }
            subscription.cancel()
            check(currentDirectory == root.path && FileManager.default.fileExists(atPath: root.appendingPathComponent("WORKSPACE.json").path),
                  "fresh process restores the group terminal in its shared root")
        }
        guard removeGroup else {
            store.destroyAll()
            print("PASS: group restore deleted complete"); fflush(stdout); exit(0)
        }
        // Delete the unpinned, member-free group via its actual sidebar action.
        let id = field(groups[1], "id") as! UUID
        groupAction("onDelete", groupID: id)
        later {
            check(groups.count == 1 && closedProjects.isEmpty && pickerRequests == 0,
                  "deleting empty group removes only its layout, without project events")
            UserDefaults.standard.set(layoutSignature(), forKey: "smoke.expectedLayout")
            UserDefaults.standard.set(projectIDs.mapValues(\.uuidString), forKey: "smoke.oldProjectIds")
            store.destroyAll()
            print("PASS: group restore read complete"); fflush(stdout); exit(0)
        }
    }

    func run() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        check(String(localized: "contextMenu.workspaceGroup.newEmpty") == "新建空工作区组", "sidebar uses Simplified Chinese resources")
        check(workspaceCount == 1 && groupNames.isEmpty, "one project without groups")
        createGroup(fromEmptyArea: false)
        later {
            check(groupNames.count == 1 && workspaceCount == 2 && pickerRequests == 0,
                  "row menu creates a group that survives project cleanup")
            check(groupNames.first == "分组 1", "new group receives a Chinese default name")
            createGroup(fromEmptyArea: true)
            later {
                check(groupNames.count == 2 && workspaceCount == 3 && pickerRequests == 0,
                      "empty-area menu creates another group without opening the picker")
                let originalNames = groupNames
                projects.append(.init(path: "/private/tmp", name: "Second project"))
                later {
                    check(groupNames == originalNames && workspaceCount == 4 && mappedProjectCount == 2,
                          "opening a project does not reuse or rename either group anchor")
                    generation += 1
                    later {
                        check(groupNames == originalNames && workspaceCount == 4 && pickerRequests == 0,
                              "groups survive host detach and reattach")
                        if CommandLine.arguments.contains("--restore-write") {
                            preparePersistentLayout()
                            return
                        }
                        if CommandLine.arguments.contains("--group-workspace") {
                            verifyGroupWorkspace()
                            return
                        }
                        verifyGroupDrops {
                            store.destroyAll()
                            print("PASS: workspace group regression complete")
                            fflush(stdout)
                            exit(0)
                        }
                    }
                }
            }
        }
    }
}
