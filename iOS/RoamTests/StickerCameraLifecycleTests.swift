import AVFoundation
import XCTest
@testable import Roam

final class StickerCameraLifecycleTests: XCTestCase {
    @MainActor func testClosingKeepsMainResponsiveAndRetainsPreviewUntilSessionWorkFinishes() async {
        let queue = DispatchQueue(label: "test.camera.slow-stop")
        queue.suspend()
        var resumed = false
        defer { if !resumed { queue.resume() } }
        let camera = StickerCameraController(sessionQueue: queue)
        var surface: StickerCameraPreviewSurface? = StickerCameraPreviewSurface()
        weak var retainedSurface = surface
        let layer = surface!.layer as! AVCaptureVideoPreviewLayer
        surface!.connect(camera)
        XCTAssertTrue(layer.session === camera.session)

        // Simulate an unfinished start/stop operation on the real retirement queue.
        // Closing must return and retain the view instead of detaching its live session.
        surface!.disconnect()
        surface!.disconnect()
        surface = nil
        let heartbeat = expectation(description: "Main queue responds while camera queue is blocked")
        DispatchQueue.main.async {
            XCTAssertNotNil(retainedSurface)
            XCTAssertTrue(layer.session === camera.session)
            heartbeat.fulfill()
        }
        await fulfillment(of: [heartbeat], timeout: 1)

        queue.resume()
        resumed = true
        await waitUntil { layer.session == nil && retainedSurface == nil }
        XCTAssertNil(layer.session)
        XCTAssertNil(retainedSurface)
    }

    @MainActor func testLateShutdownCannotDetachReopenedCameraOrReviveRetiredController() async {
        let oldQueue = DispatchQueue(label: "test.camera.old")
        oldQueue.suspend()
        var resumed = false
        defer { if !resumed { oldQueue.resume() } }
        let oldCamera = StickerCameraController(sessionQueue: oldQueue)
        let oldSurface = StickerCameraPreviewSurface()
        let oldLayer = oldSurface.layer as! AVCaptureVideoPreviewLayer
        oldSurface.connect(oldCamera)
        oldSurface.disconnect()

        let newCamera = StickerCameraController(sessionQueue: DispatchQueue(label: "test.camera.new"))
        let newSurface = StickerCameraPreviewSurface()
        let newLayer = newSurface.layer as! AVCaptureVideoPreviewLayer
        newSurface.connect(newCamera)

        oldCamera.appear(active: true, onCapture: { _ in XCTFail("Retired camera delivered a photo") })
        oldCamera.retry()
        oldSurface.connect(newCamera)
        XCTAssertFalse(oldCamera.acceptsPreviewUpdates)
        XCTAssertTrue(oldLayer.session === oldCamera.session)

        oldQueue.resume()
        resumed = true
        await waitUntil { oldLayer.session == nil }
        XCTAssertNil(oldLayer.session)
        XCTAssertTrue(newLayer.session === newCamera.session)
        newSurface.disconnect()
        await waitUntil { newLayer.session == nil }
        XCTAssertNil(newLayer.session)
    }

    @MainActor private func waitUntil(_ predicate: () -> Bool) async {
        let deadline = Date().addingTimeInterval(2)
        while !predicate(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
