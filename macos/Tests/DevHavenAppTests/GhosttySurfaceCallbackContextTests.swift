import XCTest
@testable import DevHavenApp

@MainActor
final class GhosttySurfaceCallbackContextTests: XCTestCase {
    func testContextRetainsBridgeUntilInvalidated() {
        weak var weakBridge: GhosttySurfaceBridge?
        var context: GhosttySurfaceCallbackContext?

        do {
            let bridge = GhosttySurfaceBridge()
            weakBridge = bridge
            context = GhosttySurfaceCallbackContext(bridge: bridge)
        }

        XCTAssertNotNil(context?.activeBridge(), "active context 应该仍能拿到 bridge")
        XCTAssertNotNil(weakBridge, "callback context 应在失效前稳定持有 bridge，避免跨线程 hop 时桥接对象提前释放")

        context?.invalidate()

        XCTAssertNil(context?.activeBridge(), "invalidate 后不应再暴露 active bridge")
        XCTAssertNil(weakBridge, "invalidate 后应释放 bridge，避免 teardown 后晚到回调继续命中旧桥接对象")
    }

    func testAsyncHopSeesNilBridgeAfterInvalidation() {
        let context = GhosttySurfaceCallbackContext(bridge: GhosttySurfaceBridge())
        let expectation = expectation(description: "main async finished")
        var capturedBridge: GhosttySurfaceBridge?

        DispatchQueue.main.async {
            capturedBridge = context.activeBridge()
            expectation.fulfill()
        }

        context.invalidate()
        wait(for: [expectation], timeout: 1)

        XCTAssertNil(capturedBridge, "跨线程 hop 到主线程后，如果 surface 已 teardown，callback context 应返回 nil 而不是旧 bridge")
    }
}
