import XCTest
import DevHavenCore
@testable import DevHavenApp

final class CodexSessionArtifactStoreTests: XCTestCase {
    func testReloadTracksBoundSessionAndMergesIndexWithTranscript() throws {
        let codexHomeURL = try makeTemporaryCodexHome()
        defer { try? FileManager.default.removeItem(at: codexHomeURL) }

        try write(
            """
            {"id":"session-1","thread_name":"实现 DevHaven agent watcher","updated_at":"2026-04-11T01:37:01.000Z"}
            """,
            to: codexHomeURL.appendingPathComponent("session_index.jsonl")
        )

        let transcriptURL = codexHomeURL
            .appendingPathComponent("sessions/2026/04/11", isDirectory: true)
            .appendingPathComponent("rollout-2026-04-11T09-37-03-session-1.jsonl")
        try write(
            """
            {"timestamp":"2026-04-11T01:37:03.634Z","type":"session_meta","payload":{"id":"session-1"}}
            {"timestamp":"2026-04-11T01:37:05.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"我先检查当前 agent runtime 的主链。"}]}}
            {"timestamp":"2026-04-11T01:37:06.000Z","type":"event_msg","payload":{"type":"task_complete","last_agent_message":"实现完成，等待你验收。"}}
            """,
            to: transcriptURL
        )

        let store = CodexSessionArtifactStore(
            codexHomeURL: codexHomeURL,
            reloadDebounceNanoseconds: 0
        )
        store.syncTrackedSessionIDs(["session-1"])

        let snapshot = try XCTUnwrap(store.currentSnapshots["session-1"])
        XCTAssertEqual(snapshot.sessionID, "session-1")
        XCTAssertEqual(snapshot.threadTitle, "实现 DevHaven agent watcher")
        XCTAssertEqual(snapshot.lastAssistantSummary, "我先检查当前 agent runtime 的主链。")
        XCTAssertEqual(snapshot.lastTaskCompleteSummary, "实现完成，等待你验收。")
        XCTAssertEqual(snapshot.preferredSummary(for: .waiting), "实现完成，等待你验收。")
        XCTAssertEqual(snapshot.preferredSummary(for: .running), "我先检查当前 agent runtime 的主链。")
        XCTAssertEqual(
            snapshot.sessionFileURL?.standardizedFileURL,
            transcriptURL.standardizedFileURL
        )
        XCTAssertEqual(
            snapshot.lastActivityAt,
            iso8601Date("2026-04-11T01:37:06.000Z")
        )
    }

    func testReloadFindsTranscriptWithoutIndexEntry() throws {
        let codexHomeURL = try makeTemporaryCodexHome()
        defer { try? FileManager.default.removeItem(at: codexHomeURL) }

        let transcriptURL = codexHomeURL
            .appendingPathComponent("sessions/2026/04/11", isDirectory: true)
            .appendingPathComponent("rollout-2026-04-11T09-38-00-session-2.jsonl")
        try write(
            """
            {"timestamp":"2026-04-11T01:38:00.000Z","type":"session_meta","payload":{"id":"session-2"}}
            {"timestamp":"2026-04-11T01:38:01.000Z","type":"event_msg","payload":{"type":"user_message","message":"继续推进 DevHaven Codex 监听演进"}}
            {"timestamp":"2026-04-11T01:38:02.000Z","type":"event_msg","payload":{"type":"agent_message","message":"继续同步当前 Codex 会话元数据。"}}
            {"timestamp":"2026-04-11T01:38:04.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":123}}}}
            """,
            to: transcriptURL
        )

        let store = CodexSessionArtifactStore(
            codexHomeURL: codexHomeURL,
            reloadDebounceNanoseconds: 0
        )
        store.syncTrackedSessionIDs(["session-2"])

        let snapshot = try XCTUnwrap(store.currentSnapshots["session-2"])
        XCTAssertEqual(snapshot.threadTitle, "继续推进 DevHaven Codex 监听演进")
        XCTAssertEqual(snapshot.lastAssistantSummary, "继续同步当前 Codex 会话元数据。")
        XCTAssertEqual(snapshot.lastActivityAt, iso8601Date("2026-04-11T01:38:04.000Z"))
    }

    func testSummaryNormalizationCondensesWhitespaceAndTruncatesLongTranscriptText() throws {
        let codexHomeURL = try makeTemporaryCodexHome()
        defer { try? FileManager.default.removeItem(at: codexHomeURL) }

        let longText = Array(repeating: "summary", count: 40).joined(separator: "   ")
        let transcriptURL = codexHomeURL
            .appendingPathComponent("sessions/2026/04/11", isDirectory: true)
            .appendingPathComponent("rollout-2026-04-11T09-39-00-session-3.jsonl")
        try write(
            """
            {"timestamp":"2026-04-11T01:39:00.000Z","type":"session_meta","payload":{"id":"session-3"}}
            {"timestamp":"2026-04-11T01:39:02.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"\(longText)"}]}}
            """,
            to: transcriptURL
        )

        let store = CodexSessionArtifactStore(
            codexHomeURL: codexHomeURL,
            reloadDebounceNanoseconds: 0
        )
        store.syncTrackedSessionIDs(["session-3"])

        let summary = try XCTUnwrap(store.currentSnapshots["session-3"]?.lastAssistantSummary)
        XCTAssertLessThanOrEqual(summary.count, 140)
        XCTAssertFalse(summary.contains("\n"))
        XCTAssertTrue(summary.hasPrefix("summary summary summary"))
    }

    func testPeriodicReloadFindsTranscriptCreatedAfterInitialTracking() throws {
        let codexHomeURL = try makeTemporaryCodexHome()
        defer { try? FileManager.default.removeItem(at: codexHomeURL) }

        let store = CodexSessionArtifactStore(
            codexHomeURL: codexHomeURL,
            reloadDebounceNanoseconds: 0,
            periodicReloadInterval: 0.05
        )

        let expectation = expectation(description: "artifact discovered after transcript appears")
        store.onSnapshotsChange = { snapshots in
            if snapshots["session-late"]?.lastAssistantSummary == "稍后创建的 transcript 已经被发现。" {
                expectation.fulfill()
            }
        }

        store.syncTrackedSessionIDs(["session-late"])
        XCTAssertNil(store.currentSnapshots["session-late"]?.lastAssistantSummary)

        let transcriptURL = codexHomeURL
            .appendingPathComponent("sessions/2026/04/11", isDirectory: true)
            .appendingPathComponent("rollout-2026-04-11T09-40-00-session-late.jsonl")
        try write(
            """
            {"timestamp":"2026-04-11T01:40:00.000Z","type":"session_meta","payload":{"id":"session-late"}}
            {"timestamp":"2026-04-11T01:40:02.000Z","type":"event_msg","payload":{"type":"agent_message","message":"稍后创建的 transcript 已经被发现。"}}
            """,
            to: transcriptURL
        )

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(
            store.currentSnapshots["session-late"]?.lastAssistantSummary,
            "稍后创建的 transcript 已经被发现。"
        )
    }

    private func makeTemporaryCodexHome() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(content.utf8).write(to: url)
    }

    private func iso8601Date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: value)
    }
}
