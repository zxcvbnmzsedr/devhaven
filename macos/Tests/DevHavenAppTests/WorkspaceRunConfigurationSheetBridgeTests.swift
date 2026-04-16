import XCTest
@testable import DevHavenApp

@MainActor
final class WorkspaceRunConfigurationSheetBridgeTests: XCTestCase {
    func testBridgeLoadsFullSheetPayload() async throws {
        let bridge = WorkspaceRunConfigurationSheetBridge()
        let payload = makePayload()

        installBridge(bridge, payload: payload)

        let snapshot = try await waitForSnapshot(on: bridge) { snapshot in
            snapshot.projectPath == payload.projectPath
                && snapshot.configurationCount == payload.configurations.count
                && snapshot.selectedConfigurationID == payload.selectedConfigurationID
        }

        XCTAssertEqual(snapshot.theme, "dark")
        XCTAssertEqual(snapshot.projectPath, "/tmp/sample-project")
        XCTAssertEqual(snapshot.configurationCount, 2)
        XCTAssertEqual(snapshot.selectedConfigurationID, "remote-log")
        XCTAssertEqual(snapshot.selectedKind, "remoteLogViewer")
        XCTAssertEqual(snapshot.selectedCommandPreview, payload.configurations[1].commandPreview)
    }

    func testBridgeForwardsWholeSheetActions() async throws {
        let bridge = WorkspaceRunConfigurationSheetBridge()
        let payload = makePayload()

        let selectExpectation = expectation(description: "Select configuration")
        let addExpectation = expectation(description: "Add configuration")
        let stringChangeExpectation = expectation(description: "String field changed")
        let boolChangeExpectation = expectation(description: "Boolean field changed")
        let duplicateExpectation = expectation(description: "Duplicate requested")
        let deleteExpectation = expectation(description: "Delete requested")
        let cancelExpectation = expectation(description: "Cancel requested")
        let saveExpectation = expectation(description: "Save requested")

        var selectedConfigurationID: String?
        var addedKind: String?
        var changedString: (String, WorkspaceRunConfigurationStringField, String)?
        var changedBoolean: (String, WorkspaceRunConfigurationBooleanField, Bool)?
        var duplicatedConfigurationID: String?
        var deletedConfigurationID: String?

        bridge.update(
            payload: payload,
            onSelectConfiguration: {
                selectedConfigurationID = $0
                selectExpectation.fulfill()
            },
            onAddConfiguration: {
                addedKind = $0
                addExpectation.fulfill()
            },
            onStringFieldChanged: {
                changedString = ($0, $1, $2)
                stringChangeExpectation.fulfill()
            },
            onBooleanFieldChanged: {
                changedBoolean = ($0, $1, $2)
                boolChangeExpectation.fulfill()
            },
            onDuplicateRequested: {
                duplicatedConfigurationID = $0
                duplicateExpectation.fulfill()
            },
            onDeleteRequested: {
                deletedConfigurationID = $0
                deleteExpectation.fulfill()
            },
            onCancelRequested: {
                cancelExpectation.fulfill()
            },
            onSaveRequested: {
                saveExpectation.fulfill()
            }
        )

        _ = try await waitForSnapshot(on: bridge)

        try await bridge.webView.evaluateJavaScript(
            "window.__devHavenRunConfigurationSheet?.debugSelect?.('shell')"
        )
        try await bridge.webView.evaluateJavaScript(
            "window.__devHavenRunConfigurationSheet?.debugAdd?.('customShell')"
        )
        try await bridge.webView.evaluateJavaScript(
            "window.__devHavenRunConfigurationSheet?.debugSetField?.('remote-log', 'name', 'Nightly logs')"
        )
        try await bridge.webView.evaluateJavaScript(
            "window.__devHavenRunConfigurationSheet?.debugSetBool?.('remote-log', 'remoteFollow', false)"
        )
        try await bridge.webView.evaluateJavaScript(
            "window.__devHavenRunConfigurationSheet?.debugRequestDuplicate?.('remote-log')"
        )
        try await bridge.webView.evaluateJavaScript(
            "window.__devHavenRunConfigurationSheet?.debugRequestDelete?.('remote-log')"
        )
        try await bridge.webView.evaluateJavaScript(
            "window.__devHavenRunConfigurationSheet?.debugRequestCancel?.()"
        )
        try await bridge.webView.evaluateJavaScript(
            "window.__devHavenRunConfigurationSheet?.debugRequestSave?.()"
        )

        await fulfillment(
            of: [
                selectExpectation,
                addExpectation,
                stringChangeExpectation,
                boolChangeExpectation,
                duplicateExpectation,
                deleteExpectation,
                cancelExpectation,
                saveExpectation,
            ],
            timeout: 5.0
        )

        XCTAssertEqual(selectedConfigurationID, "shell")
        XCTAssertEqual(addedKind, "customShell")
        XCTAssertEqual(changedString?.0, "remote-log")
        XCTAssertEqual(changedString?.1, .name)
        XCTAssertEqual(changedString?.2, "Nightly logs")
        XCTAssertEqual(changedBoolean?.0, "remote-log")
        XCTAssertEqual(changedBoolean?.1, .remoteFollow)
        XCTAssertEqual(changedBoolean?.2, false)
        XCTAssertEqual(duplicatedConfigurationID, "remote-log")
        XCTAssertEqual(deletedConfigurationID, "remote-log")
    }

    private func installBridge(
        _ bridge: WorkspaceRunConfigurationSheetBridge,
        payload: WorkspaceRunConfigurationSheetPayload
    ) {
        bridge.update(
            payload: payload,
            onSelectConfiguration: { _ in },
            onAddConfiguration: { _ in },
            onStringFieldChanged: { _, _, _ in },
            onBooleanFieldChanged: { _, _, _ in },
            onDuplicateRequested: { _ in },
            onDeleteRequested: { _ in },
            onCancelRequested: {},
            onSaveRequested: {}
        )
    }

    private func makePayload() -> WorkspaceRunConfigurationSheetPayload {
        WorkspaceRunConfigurationSheetPayload(
            theme: "dark",
            title: "运行配置",
            subtitle: "按 IDEA 的思路维护项目内运行配置。",
            projectPath: "/tmp/sample-project",
            footerNote: "保存后会直接写回当前项目运行配置。",
            isSaving: false,
            validationMessage: nil,
            selectedConfigurationID: "remote-log",
            availableKinds: [
                WorkspaceRunConfigurationKindOptionPayload(
                    id: "customShell",
                    title: "Shell Script",
                    subtitle: "执行项目内自定义 Shell 命令"
                ),
                WorkspaceRunConfigurationKindOptionPayload(
                    id: "remoteLogViewer",
                    title: "Remote Log Viewer",
                    subtitle: "通过 SSH 查看远端日志"
                ),
            ],
            configurations: [
                WorkspaceRunConfigurationSheetConfigurationPayload(
                    id: "shell",
                    kind: "customShell",
                    kindTitle: "Shell Script",
                    kindSubtitle: "执行项目内自定义 Shell 命令",
                    name: "Run tests",
                    resolvedName: "Run tests",
                    suggestedName: "swift test",
                    rowSummary: "swift test --package-path macos",
                    commandPreview: "swift test --package-path macos",
                    customCommand: "swift test --package-path macos",
                    remoteServer: "",
                    remoteLogPath: "",
                    remoteUser: "",
                    remotePort: "22",
                    remoteIdentityFile: "",
                    remoteLines: "200",
                    remoteFollow: true,
                    remoteStrictHostKeyChecking: "accept-new",
                    remoteAllowPasswordPrompt: false
                ),
                WorkspaceRunConfigurationSheetConfigurationPayload(
                    id: "remote-log",
                    kind: "remoteLogViewer",
                    kindTitle: "Remote Log Viewer",
                    kindSubtitle: "通过 SSH 查看远端日志",
                    name: "Remote log tail",
                    resolvedName: "Remote log tail",
                    suggestedName: "远程日志 · prod-host · app.log",
                    rowSummary: "prod-host · /var/log/app.log",
                    commandPreview: "/usr/bin/ssh '-l' 'deploy' 'prod-host' 'tail -n 200 -F '\\''/var/log/app.log'\\'''",
                    customCommand: "",
                    remoteServer: "prod-host",
                    remoteLogPath: "/var/log/app.log",
                    remoteUser: "deploy",
                    remotePort: "22",
                    remoteIdentityFile: "~/.ssh/id_ed25519",
                    remoteLines: "200",
                    remoteFollow: true,
                    remoteStrictHostKeyChecking: "accept-new",
                    remoteAllowPasswordPrompt: false
                ),
            ]
        )
    }

    private func waitForSnapshot(
        on bridge: WorkspaceRunConfigurationSheetBridge,
        timeout: TimeInterval = 10.0,
        matching predicate: @escaping (RunConfigurationSheetDebugSnapshot) -> Bool = { _ in true }
    ) async throws -> RunConfigurationSheetDebugSnapshot {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let snapshot = try await debugSnapshot(for: bridge), predicate(snapshot) {
                return snapshot
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        let debugSummary = bridge.debugStateSummary()
        let debugEvents = bridge.debugEvents.joined(separator: "\n")
        XCTFail(
            """
            Timed out waiting for run configuration sheet snapshot
            Bridge: \(debugSummary)
            Events:
            \(debugEvents)
            """
        )
        return RunConfigurationSheetDebugSnapshot(
            theme: nil,
            projectPath: nil,
            configurationCount: nil,
            selectedConfigurationID: nil,
            selectedKind: nil,
            selectedRemoteFollow: nil,
            selectedCommandPreview: nil,
            validationMessage: nil,
            isSaving: nil
        )
    }

    private func debugSnapshot(
        for bridge: WorkspaceRunConfigurationSheetBridge
    ) async throws -> RunConfigurationSheetDebugSnapshot? {
        guard let rawSnapshot = try await bridge.webView.evaluateJavaScript(
            "window.__devHavenRunConfigurationSheet?.debugSnapshot?.()"
        ) as? [String: Any] else {
            return nil
        }

        return RunConfigurationSheetDebugSnapshot(
            theme: rawSnapshot["theme"] as? String,
            projectPath: rawSnapshot["projectPath"] as? String,
            configurationCount: rawSnapshot["configurationCount"] as? Int,
            selectedConfigurationID: rawSnapshot["selectedConfigurationID"] as? String,
            selectedKind: rawSnapshot["selectedKind"] as? String,
            selectedRemoteFollow: rawSnapshot["selectedRemoteFollow"] as? Bool,
            selectedCommandPreview: rawSnapshot["selectedCommandPreview"] as? String,
            validationMessage: rawSnapshot["validationMessage"] as? String,
            isSaving: rawSnapshot["isSaving"] as? Bool
        )
    }
}

private struct RunConfigurationSheetDebugSnapshot: Equatable {
    var theme: String?
    var projectPath: String?
    var configurationCount: Int?
    var selectedConfigurationID: String?
    var selectedKind: String?
    var selectedRemoteFollow: Bool?
    var selectedCommandPreview: String?
    var validationMessage: String?
    var isSaving: Bool?
}
