import CoreGraphics
import XCTest
@testable import Roam

final class StickerCameraPresentationTests: XCTestCase {
    func testOpeningDirectionLocksUntilTheGestureEnds() {
        var presentation = StickerCameraPresentation()
        let originalID = presentation.presentationID
        XCTAssertFalse(presentation.updateOpening(translation: CGSize(width: 3, height: 4), travel: 200))
        XCTAssertFalse(presentation.updateOpening(translation: CGSize(width: 20, height: 12), travel: 200))
        XCTAssertFalse(presentation.updateOpening(translation: CGSize(width: 0, height: 100), travel: 200))
        XCTAssertEqual(presentation.phase, .hidden)
        XCTAssertEqual(presentation.presentationID, originalID)
        XCTAssertNil(presentation.finishOpening(translation: CGSize(width: 0, height: 100), predicted: CGSize(width: 0, height: 200)))

        XCTAssertTrue(presentation.updateOpening(translation: CGSize(width: 1, height: 20), travel: 200))
        XCTAssertNotEqual(presentation.presentationID, originalID)
        // Once accepted, sideways movement cannot make the panel disappear mid-drag.
        XCTAssertTrue(presentation.updateOpening(translation: CGSize(width: 200, height: 60), travel: 200))
        XCTAssertEqual(presentation.phase, .pulling)
        XCTAssertEqual(presentation.progress, 0.3, accuracy: 0.001)
        XCTAssertEqual(presentation.finishOpening(translation: CGSize(width: 200, height: 80), predicted: CGSize(width: 200, height: 80)), true)
    }

    func testOppositeDirectionStaysRejectedUntilGestureEnds() {
        var presentation = StickerCameraPresentation()
        XCTAssertFalse(presentation.updateOpening(translation: CGSize(width: 0, height: -20), travel: 200))
        XCTAssertFalse(presentation.updateOpening(translation: CGSize(width: 0, height: 100), travel: 200))
        XCTAssertNil(presentation.cancelDrag())

        let opening = presentation.settle(open: true)
        XCTAssertTrue(presentation.complete(token: opening))
        XCTAssertFalse(presentation.updateClosing(translation: CGSize(width: 0, height: 20), travel: 200))
        XCTAssertFalse(presentation.updateClosing(translation: CGSize(width: 0, height: -100), travel: 200))
        XCTAssertNil(presentation.finishClosing(translation: CGSize(width: 0, height: -100), predicted: CGSize(width: 0, height: -200)))
        XCTAssertEqual(presentation.phase, .open)
        XCTAssertEqual(presentation.progress, 1)
        XCTAssertTrue(presentation.updateClosing(translation: CGSize(width: 0, height: -20), travel: 200))
        XCTAssertTrue(presentation.updateClosing(translation: CGSize(width: 200, height: -60), travel: 200))
        XCTAssertEqual(presentation.progress, 0.7, accuracy: 0.001)
    }

    func testOpeningAndClosingUseTheSameDragTravel() {
        var presentation = StickerCameraPresentation()
        XCTAssertTrue(presentation.updateOpening(translation: CGSize(width: 0, height: 80), travel: 200))
        XCTAssertEqual(presentation.progress, 0.4, accuracy: 0.001)
        XCTAssertTrue(presentation.updateOpening(translation: CGSize(width: 0, height: 500), travel: 200))
        XCTAssertEqual(presentation.progress, 0.95, accuracy: 0.001)
        let opening = presentation.settle(open: true)
        XCTAssertTrue(presentation.complete(token: opening))
        XCTAssertTrue(presentation.updateClosing(translation: CGSize(width: 0, height: -80), travel: 200))
        XCTAssertEqual(presentation.progress, 0.6, accuracy: 0.001)
        XCTAssertTrue(presentation.updateClosing(translation: CGSize(width: 0, height: -500), travel: 200))
        XCTAssertEqual(presentation.progress, 0)
    }

    func testShortPullAndCancelledDragReturnToTheirOriginalEndpoint() {
        var presentation = StickerCameraPresentation()
        XCTAssertTrue(presentation.updateOpening(translation: CGSize(width: 0, height: 25), travel: 200))
        XCTAssertEqual(presentation.finishOpening(translation: CGSize(width: 0, height: 25), predicted: CGSize(width: 0, height: 500)), false)
        let shortPull = presentation.settle(open: false)
        XCTAssertFalse(presentation.showsCamera)
        XCTAssertFalse(presentation.hidesStatusBar)
        XCTAssertTrue(presentation.complete(token: shortPull))
        XCTAssertEqual(presentation.phase, .hidden)

        XCTAssertTrue(presentation.updateOpening(translation: CGSize(width: 0, height: 50), travel: 200))
        XCTAssertEqual(presentation.cancelDrag(), false)
        let cancelledPull = presentation.settle(open: false)
        XCTAssertTrue(presentation.complete(token: cancelledPull))
        XCTAssertFalse(presentation.isMounted)

        let opening = presentation.settle(open: true)
        XCTAssertTrue(presentation.complete(token: opening))
        let cameraID = presentation.presentationID
        XCTAssertTrue(presentation.updateClosing(translation: CGSize(width: 0, height: -50), travel: 200))
        XCTAssertEqual(presentation.cancelDrag(), true)
        let cancelledClose = presentation.settle(open: true)
        XCTAssertEqual(presentation.phase, .opening)
        XCTAssertTrue(presentation.isActive, "A cancelled closing drag must keep its running camera through the rebound")
        XCTAssertFalse(presentation.isInteractive)
        XCTAssertTrue(presentation.complete(token: cancelledClose))
        XCTAssertEqual(presentation.phase, .open)
        XCTAssertEqual(presentation.presentationID, cameraID)
        XCTAssertNil(presentation.cancelDrag())

        XCTAssertTrue(presentation.updateClosing(translation: CGSize(width: 0, height: -25), travel: 200))
        XCTAssertEqual(presentation.finishClosing(translation: CGSize(width: 0, height: -25), predicted: CGSize(width: 0, height: -500)), true)
        let shortClose = presentation.settle(open: true)
        XCTAssertTrue(presentation.isActive, "A short closing drag must also preserve the active session")
        XCTAssertTrue(presentation.complete(token: shortClose))
    }

    func testProjectedReleaseNeedsEnoughActualTravelInBothDirections() {
        let releases: [(actual: CGFloat, projected: CGFloat, opens: Bool)] = [
            (25, 500, false), (26, 150, true), (75, 149, false), (76, 76, true)
        ]
        for release in releases {
            var presentation = StickerCameraPresentation()
            let down = CGSize(width: 0, height: release.actual)
            XCTAssertTrue(presentation.updateOpening(translation: down, travel: 200))
            XCTAssertEqual(presentation.finishOpening(translation: down, predicted: CGSize(width: 0, height: release.projected)), release.opens)
            let opening = presentation.settle(open: true)
            XCTAssertTrue(presentation.complete(token: opening))
            let up = CGSize(width: 0, height: -release.actual)
            XCTAssertTrue(presentation.updateClosing(translation: up, travel: 200))
            XCTAssertEqual(presentation.finishClosing(translation: up, predicted: CGSize(width: 0, height: -release.projected)), !release.opens)
        }
    }

    func testCameraActivityAndMountingFollowDifferentLifetimes() {
        var presentation = StickerCameraPresentation()
        XCTAssertFalse(presentation.isMounted)
        XCTAssertFalse(presentation.showsCamera)
        XCTAssertFalse(presentation.isActive)
        XCTAssertFalse(presentation.hidesStatusBar)
        XCTAssertTrue(presentation.updateOpening(translation: CGSize(width: 0, height: 40), travel: 200))
        XCTAssertTrue(presentation.isMounted)
        XCTAssertTrue(presentation.isDragging)
        XCTAssertFalse(presentation.showsCamera)
        XCTAssertFalse(presentation.isInteractive)

        let opening = presentation.settle(open: true)
        XCTAssertTrue(presentation.showsCamera)
        XCTAssertTrue(presentation.hidesStatusBar)
        XCTAssertFalse(presentation.isActive)
        XCTAssertFalse(presentation.isDragging)
        XCTAssertTrue(presentation.complete(token: opening))
        XCTAssertTrue(presentation.isActive)
        XCTAssertTrue(presentation.isInteractive)
        XCTAssertTrue(presentation.updateClosing(translation: CGSize(width: 0, height: -40), travel: 200))
        XCTAssertTrue(presentation.isActive)
        XCTAssertTrue(presentation.isDragging)

        let closing = presentation.settle(open: false)
        XCTAssertTrue(presentation.isMounted)
        XCTAssertTrue(presentation.showsCamera)
        XCTAssertTrue(presentation.hidesStatusBar)
        XCTAssertFalse(presentation.isActive)
        XCTAssertFalse(presentation.isInteractive)
        XCTAssertTrue(presentation.complete(token: closing))
        XCTAssertFalse(presentation.isMounted)
        XCTAssertFalse(presentation.showsCamera)
        XCTAssertFalse(presentation.hidesStatusBar)
    }

    func testStaleAnimationCompletionCannotRemoveReopenedCamera() {
        var presentation = StickerCameraPresentation()
        let initialOpen = presentation.settle(open: true)
        let initialID = presentation.presentationID
        let closing = presentation.settle(open: false)
        XCTAssertFalse(presentation.complete(token: initialOpen))
        XCTAssertEqual(presentation.phase, .closing)
        let reopened = presentation.settle(open: true)
        XCTAssertFalse(presentation.complete(token: closing))
        XCTAssertTrue(presentation.showsCamera)
        XCTAssertTrue(presentation.complete(token: reopened))
        XCTAssertFalse(presentation.complete(token: reopened))
        XCTAssertEqual(presentation.phase, .open)
        XCTAssertEqual(presentation.presentationID, initialID)

        let resetClose = presentation.settle(open: false)
        presentation.reset()
        XCTAssertFalse(presentation.complete(token: resetClose))
        XCTAssertFalse(presentation.isMounted)
        let nextOpen = presentation.settle(open: true)
        XCTAssertNotEqual(presentation.presentationID, initialID)
        XCTAssertTrue(presentation.complete(token: nextOpen))
        XCTAssertFalse(presentation.complete(token: resetClose))
        XCTAssertEqual(presentation.phase, .open)
    }
}
