import XCTest
import UIKit

final class StickerBoardUITests: XCTestCase {
    @MainActor func testPopulatedCanvasFastSwipesPreserveItemsAndRestoreOrigin() {
        let app = launchBoard(fixture: true, populated: true)
        let items = canvasItems(in: app)
        let first = items.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let itemID = first.identifier
        let originalFrame = first.frame
        let originalValue = first.value as? String
        let count = items.count
        XCTAssertEqual(count, 31)

        for direction in [-1.0, -1.0, -1.0, 1.0, -1.0] {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: direction < 0 ? 0.85 : 0.15, dy: 0.78))
            start.press(forDuration: 0.01,
                        thenDragTo: start.withOffset(CGVector(dx: direction * app.frame.width * 0.60, dy: 5)),
                        withVelocity: .fast, thenHoldForDuration: 0)
        }
        let reset = app.buttons["sticker-reset-viewport"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["sticker-camera-panel"].firstMatch.exists)
        XCTAssertEqual(items.count, count)
        attachScreenshot(app, name: "Populated journal after fast horizontal browsing")
        reset.tap()
        let restored = app.descendants(matching: .any)[itemID].firstMatch
        waitUntil { !reset.exists && restored.isHittable }
        XCTAssertEqual(restored.frame.midX, originalFrame.midX, accuracy: 6)
        XCTAssertEqual(restored.frame.midY, originalFrame.midY, accuracy: 6)
        XCTAssertEqual(restored.value as? String, originalValue)
        attachScreenshot(app, name: "Populated journal back at origin with solid and dashed borders")
    }

    @MainActor func testTextCanBeAddedMovedAndRestoredAfterRelaunch() {
        let app = launchBoard()
        app.buttons["sticker-add-text"].tap()
        // A vertical-axis SwiftUI TextField can be exposed as an XCUI text view.
        let input = app.descendants(matching: .any)["sticker-text-input"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Kyoto memories")
        app.buttons["sticker-save-text"].tap()

        let text = canvasItems(in: app).matching(NSPredicate(format: "label CONTAINS %@", "Kyoto memories")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        waitUntil { !input.exists }
        attachScreenshot(app, name: "Sticker canvas after saving text")
        let before = text.frame
        let valueBeforeMove = text.value as? String
        let start = text.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.65, thenDragTo: start.withOffset(CGVector(dx: 55, dy: 85)))
        waitUntil {
            abs(text.frame.midX - before.midX) > 25 && abs(text.frame.midY - before.midY) > 25
        }
        XCTAssertNotEqual(text.value as? String, valueBeforeMove)
        XCTAssertFalse(app.buttons["sticker-reset-viewport"].exists,
                       "Moving an activated text sticker must not pan the canvas")
        let moved = text.frame
        app.terminate()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let tab = app.buttons["home-tab-stickers"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
        let restored = canvasItems(in: app).matching(NSPredicate(format: "label CONTAINS %@", "Kyoto memories")).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 5))
        XCTAssertEqual(restored.frame.midX, moved.midX, accuracy: 6)
        XCTAssertEqual(restored.frame.midY, moved.midY, accuracy: 6)
    }

    @MainActor func testImageBorderDeletionAndUndo() {
        let app = launchBoard(fixture: true)
        let image = canvasItems(in: app).firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        let identifier = image.identifier
        image.tap()

        let borderColor = app.buttons["sticker-border-color"]
        XCTAssertTrue(borderColor.waitForExistence(timeout: 5))
        borderColor.tap()
        let blue = app.buttons["sticker-border-color-3E637A"]
        let saveColor = app.buttons["sticker-save-border-color"]
        XCTAssertTrue(blue.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["描边颜色"].exists)
        blue.tap()
        saveColor.tap()
        waitUntil { !saveColor.exists && (image.value as? String)?.contains("#3E637A") == true }

        let dashed = app.buttons["sticker-border-dashed"]
        XCTAssertTrue(dashed.waitForExistence(timeout: 5))
        dashed.tap()
        waitUntil { (image.value as? String)?.contains("虚线 · #3E637A") == true }
        let savedValue = image.value as? String
        attachScreenshot(app, name: "Sticker with saved blue dashed outline")

        app.terminate()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let tab = app.buttons["home-tab-stickers"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
        let restored = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 5))
        XCTAssertEqual(restored.value as? String, savedValue,
                       "The saved border color and style must survive relaunch")

        restored.tap()
        XCTAssertTrue(borderColor.waitForExistence(timeout: 5))
        borderColor.tap()
        let red = app.buttons["sticker-border-color-BC534B"]
        XCTAssertTrue(red.waitForExistence(timeout: 5))
        red.tap()
        let cancelColor = app.buttons["sticker-cancel-border-color"]
        XCTAssertTrue(cancelColor.exists)
        cancelColor.tap()
        waitUntil { !cancelColor.exists && borderColor.isHittable }
        XCTAssertEqual(restored.value as? String, savedValue,
                       "Cancelling a different preview color must keep the saved blue outline")

        app.buttons["sticker-border-solid"].tap()
        waitUntil { (restored.value as? String)?.contains("实线 · #3E637A") == true }
        let valueBeforeDeletion = restored.value as? String
        app.buttons["sticker-delete"].tap()
        waitUntil { !restored.exists }
        let undo = app.buttons["sticker-undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(restored.waitForExistence(timeout: 5))
        XCTAssertEqual(restored.value as? String, valueBeforeDeletion,
                       "Undo must restore the sticker with its saved border color and style")
    }

    @MainActor func testUndoDeleteNoticeDisappearsAfterFiveSeconds() {
        let app = launchBoard(fixture: true)
        let sticker = canvasItems(in: app).firstMatch
        XCTAssertTrue(sticker.waitForExistence(timeout: 5))
        sticker.tap()
        let delete = app.buttons["sticker-delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))

        let started = Date()
        delete.tap()
        let undo = app.buttons["sticker-undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 2))
        attachScreenshot(app, name: "Undo Delete visible immediately after deletion")

        // A usable undo window must remain visible, then expire without input.
        let disappearsTooSoon = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !undo.exists }, object: nil)
        disappearsTooSoon.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [disappearsTooSoon], timeout: 2), .completed)
        XCTAssertTrue(undo.waitForNonExistence(timeout: 4))
        XCTAssertLessThan(Date().timeIntervalSince(started), 8)
        XCTAssertFalse(sticker.exists, "Hiding the notice must not restore the deleted sticker")
        attachScreenshot(app, name: "Undo Delete automatically hidden after five seconds")

        app.buttons["home-tab-trips"].tap()
        app.buttons["home-tab-stickers"].tap()
        XCTAssertTrue(app.buttons["sticker-add-text"].waitForExistence(timeout: 5))
        XCTAssertFalse(undo.exists, "Returning to the journal must not revive an expired notice")
    }

    @MainActor func testCameraPanelCanOpenAndCloseWithoutLosingCanvas() {
        let app = launchBoard(fixture: true, cameraPreviewFixture: true)
        let image = canvasItems(in: app).firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        let identifier = image.identifier
        let originalFrame = image.frame
        let screenTop = app.frame.minY
        // Preserve the visible status bar boundary before the camera hides it.
        // The portrait iPhone 17 still needs at least the island-height top inset.
        let statusBar = app.statusBars.firstMatch
        let controlsMinimumY = max(screenTop + 59, statusBar.exists ? statusBar.frame.maxY : screenTop)
        XCTAssertFalse(app.buttons["sticker-open-camera"].exists)
        let title = app.staticTexts["sticker-page-title"].firstMatch
        let addText = app.buttons["sticker-add-text"]
        let importPhoto = app.buttons["sticker-import-photo"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(addText.isHittable)
        XCTAssertTrue(importPhoto.isHittable)
        // The whole header now starts directly below the safe area, without a camera row.
        for element in [title, addText, importPhoto] {
            XCTAssertGreaterThanOrEqual(element.frame.minY, controlsMinimumY)
            XCTAssertLessThan(element.frame.minY, controlsMinimumY + 24)
        }
        // The fixed title supports the same downward camera gesture as the canvas.
        let start = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: 160))
        start.press(forDuration: 0.05, thenDragTo: end)
        let panel = app.descendants(matching: .any)["sticker-camera-panel"].firstMatch
        let viewfinder = waitForCameraViewfinder(in: app)
        XCTAssertFalse(app.buttons["sticker-camera-close"].exists)
        XCTAssertFalse(app.buttons["sticker-camera-collapse"].exists)
        for removedTitle in ["拍摄贴纸", "Capture a Sticker", "上滑收起", "Swipe up to close"] {
            XCTAssertFalse(app.staticTexts[removedTitle].exists)
        }
        XCTAssertGreaterThanOrEqual(panel.frame.minY, screenTop)
        XCTAssertLessThan(panel.frame.minY, screenTop + 30)
        XCTAssertGreaterThanOrEqual(viewfinder.frame.minY, controlsMinimumY)
        XCTAssertLessThan(viewfinder.frame.minY, controlsMinimumY + 24,
                          "The viewfinder must begin below the safe area without the removed control row")
        let previewImage = app.images["相机取景测试画面"].firstMatch
        let shutter = app.buttons["sticker-camera-shutter"]
        XCTAssertTrue(previewImage.waitForExistence(timeout: 5))
        XCTAssertTrue(shutter.waitForExistence(timeout: 5))
        // SwiftUI propagates the row's horizontal accessibility bounds to its image.
        // Inspect rendered pixels to verify the real black frame and its inner edge.
        assertCameraBlackFrame(in: app, panel: panel.frame, preview: previewImage.frame)
        XCTAssertLessThanOrEqual(previewImage.frame.maxY, shutter.frame.minY)
        XCTAssertEqual(shutter.frame.width, 72, accuracy: 2)
        XCTAssertEqual(shutter.frame.height, 72, accuracy: 2)
        let trips = app.buttons["home-tab-trips"]
        waitUntil { !trips.exists || !trips.isHittable }
        attachScreenshot(app, name: "Camera expanded from island with solid black frame around viewfinder")

        let dismissStart = viewfinder.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        dismissStart.press(forDuration: 0.05, thenDragTo: dismissStart.withOffset(CGVector(dx: 0, dy: -140)))
        waitUntil { !panel.exists }
        waitUntil { trips.isHittable && addText.isHittable }
        XCTAssertFalse(app.buttons["sticker-open-camera"].exists)
        let restored = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(restored.exists)
        XCTAssertEqual(restored.frame.midX, originalFrame.midX, accuracy: 6)
        XCTAssertEqual(restored.frame.midY, originalFrame.midY, accuracy: 6)
        attachScreenshot(app, name: "Camera collapsed by swiping up with canvas and navigation restored")

        start.press(forDuration: 0.05, thenDragTo: end)
        waitForCameraViewfinder(in: app)
        XCTAssertLessThan(panel.frame.minY, screenTop + 30)
        waitUntil { !trips.exists || !trips.isHittable }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.90)).tap()
        waitUntil { !panel.exists }
        waitUntil { trips.isHittable && addText.isHittable }
        XCTAssertFalse(app.buttons["sticker-open-camera"].exists)
        XCTAssertTrue(restored.exists)
        XCTAssertTrue(app.buttons["sticker-add-text"].isHittable)
        trips.tap()
        attachScreenshot(app, name: "Trips with bottom navigation")
    }

    @MainActor func testLiveCameraPreviewDismissalsKeepCanvasAndNavigationResponsive() {
        // Keep the real preview/session lifecycle on simulator; the image fixture bypasses teardown.
        let app = launchBoard(fixture: true, cameraPreviewFixture: false)
        let fixture = canvasItems(in: app).firstMatch
        XCTAssertTrue(fixture.waitForExistence(timeout: 5))
        let fixtureID = fixture.identifier
        let originalFrame = fixture.frame
        let originalValue = fixture.value as? String
        let panel = app.descendants(matching: .any)["sticker-camera-panel"].firstMatch
        let addText = app.buttons["sticker-add-text"]
        let trips = app.buttons["home-tab-trips"]
        let journal = app.buttons["home-tab-stickers"]

        for cycle in 1...2 {
            for dismissal in ["viewfinder upward swipe", "scrim tap", "scrim upward swipe"] {
                XCTContext.runActivity(named: "Camera dismissal \(cycle): \(dismissal)") { _ in
                    let title = app.staticTexts["sticker-page-title"].firstMatch
                    XCTAssertTrue(title.waitForExistence(timeout: 5))
                    let start = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 160)))
                    let viewfinder = waitForCameraViewfinder(in: app)
                    XCTAssertFalse(app.images["相机取景测试画面"].exists)

                    switch dismissal {
                    case "scrim tap":
                        app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.90)).tap()
                    case "scrim upward swipe":
                        let swipe = app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.90))
                        swipe.press(forDuration: 0.1,
                                    thenDragTo: swipe.withOffset(CGVector(dx: 0, dy: -app.frame.height * 0.14)))
                    default:
                        let swipe = viewfinder.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
                        swipe.press(forDuration: 0.05, thenDragTo: swipe.withOffset(CGVector(dx: 0, dy: -140)))
                    }

                    // Exercise the restored controls without a teardown grace period.
                    waitUntil { addText.isHittable }
                    addText.tap()
                    let input = app.descendants(matching: .any)["sticker-text-input"].firstMatch
                    XCTAssertTrue(input.waitForExistence(timeout: 5))
                    let cancel = app.navigationBars.buttons.matching(
                        NSPredicate(format: "label == %@ OR label == %@", "取消", "Cancel")
                    ).firstMatch
                    XCTAssertTrue(cancel.waitForExistence(timeout: 5))
                    cancel.tap()
                    waitUntil { !input.exists && trips.isHittable }
                    trips.tap()
                    XCTAssertTrue(app.buttons["trip-tokyo"].waitForExistence(timeout: 5))
                    XCTAssertFalse(addText.isHittable)
                    journal.tap()
                    waitUntil { addText.isHittable && !panel.exists }

                    let restored = app.descendants(matching: .any)[fixtureID].firstMatch
                    XCTAssertTrue(restored.exists)
                    XCTAssertEqual(restored.frame.midX, originalFrame.midX, accuracy: 6)
                    XCTAssertEqual(restored.frame.midY, originalFrame.midY, accuracy: 6)
                    XCTAssertEqual(restored.value as? String, originalValue)
                }
            }
        }
    }

    @MainActor func testCameraGesturesStaySeparateFromToolsAndShutterControls() {
        let app = launchBoard(fixture: true, cameraPreviewFixture: true)
        let panel = app.descendants(matching: .any)["sticker-camera-panel"].firstMatch
        let addText = app.buttons["sticker-add-text"]
        let importPhoto = app.buttons["sticker-import-photo"]
        let input = app.descendants(matching: .any)["sticker-text-input"].firstMatch

        for tool in [addText, importPhoto] {
            let start = tool.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 160)))
            waitUntil { addText.isHittable && importPhoto.isHittable }
            XCTAssertFalse(panel.exists, "A drag starting on a tool must not open the camera")
            XCTAssertFalse(input.exists, "Dragging Aa must not open the text editor")
            XCTAssertEqual(app.sheets.count, 0, "Dragging a tool must not present a sheet")
        }

        let title = app.staticTexts["sticker-page-title"].firstMatch
        let horizontalStart = title.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5))
        horizontalStart.press(forDuration: 0.05, thenDragTo: horizontalStart.withOffset(CGVector(dx: -60, dy: 0)))
        XCTAssertFalse(panel.exists, "A horizontal title drag must not open the camera")
        XCTAssertTrue(addText.isHittable)

        let pullStart = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        pullStart.press(forDuration: 0.05, thenDragTo: pullStart.withOffset(CGVector(dx: 0, dy: 160)))
        let preview = waitForCameraViewfinder(in: app)
        let expandedFrame = panel.frame

        let shortSwipe = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        shortSwipe.press(forDuration: 0.05, thenDragTo: shortSwipe.withOffset(CGVector(dx: 0, dy: -22)))
        waitForCameraViewfinder(in: app)
        XCTAssertEqual(panel.frame.width, expandedFrame.width, accuracy: 3)
        XCTAssertEqual(panel.frame.height, expandedFrame.height, accuracy: 3)

        let shutter = app.buttons["sticker-camera-shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 5))
        let shutterDrag = shutter.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        shutterDrag.press(forDuration: 0.05, thenDragTo: shutterDrag.withOffset(CGVector(dx: 0, dy: -160)))
        waitForCameraViewfinder(in: app)
        XCTAssertEqual(panel.frame.height, expandedFrame.height, accuracy: 3,
                       "Dragging from the shutter row must not dismiss the camera")

        let dismissSwipe = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        dismissSwipe.press(forDuration: 0.1,
                           thenDragTo: dismissSwipe.withOffset(CGVector(dx: 0, dy: -140)))
        waitUntil { !panel.exists && addText.isHittable }
        addText.tap()
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        let cancel = app.navigationBars.buttons.matching(
            NSPredicate(format: "label == %@ OR label == %@", "取消", "Cancel")
        ).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        waitUntil { !input.exists && addText.isHittable }
    }

    @MainActor func testShortPullAndDraggingStickerDoNotOpenCamera() {
        let app = launchBoard(fixture: true, cameraPreviewFixture: true)
        let image = canvasItems(in: app).firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        let originalFrame = image.frame
        let originalValue = image.value as? String
        let panel = app.descendants(matching: .any)["sticker-camera-panel"].firstMatch
        let reset = app.buttons["sticker-reset-viewport"]
        let addText = app.buttons["sticker-add-text"]
        let pullStart = app.staticTexts["sticker-page-title"].firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        pullStart.press(forDuration: 0.1, thenDragTo: pullStart.withOffset(CGVector(dx: 0, dy: 24)))
        waitUntil { !panel.exists && addText.isHittable }
        XCTAssertFalse(app.buttons["sticker-open-camera"].exists)
        XCTAssertTrue(app.buttons["home-tab-trips"].isHittable)
        XCTAssertFalse(reset.exists)

        // A quick swipe beginning on an item pans the canvas, leaving its world coordinates intact.
        let swipe = image.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        swipe.press(forDuration: 0.1, thenDragTo: swipe.withOffset(CGVector(dx: 85, dy: 18)))
        waitUntil { reset.exists && image.frame.midX - originalFrame.midX > 50 }
        XCTAssertEqual(image.frame.midY, originalFrame.midY, accuracy: 6,
                       "Canvas panning must remain horizontal even with a diagonal finger path")
        XCTAssertEqual(image.value as? String, originalValue)
        XCTAssertFalse(panel.exists)
        reset.tap()
        waitUntil { !reset.exists && image.isHittable }
        XCTAssertEqual(image.frame.midX, originalFrame.midX, accuracy: 6)
        XCTAssertEqual(image.frame.midY, originalFrame.midY, accuracy: 6)
        XCTAssertEqual(image.value as? String, originalValue)

        // A downward swipe on the image opens the camera instead of moving the item.
        let downOnImage = image.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        downOnImage.press(forDuration: 0.1, thenDragTo: downOnImage.withOffset(CGVector(dx: 0, dy: 140)))
        waitForCameraViewfinder(in: app)
        let scrim = app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.90))
        scrim.press(forDuration: 0.1,
                    thenDragTo: scrim.withOffset(CGVector(dx: 0, dy: -app.frame.height * 0.14)))
        waitUntil { !panel.exists && addText.isHittable }
        XCTAssertEqual(image.value as? String, originalValue)
        XCTAssertEqual(image.frame.midX, originalFrame.midX, accuracy: 6)
        XCTAssertEqual(image.frame.midY, originalFrame.midY, accuracy: 6)
        XCTAssertFalse(reset.exists)

        // Blank paper also opens the camera vertically without moving the viewport.
        let downOnPaper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.48))
        downOnPaper.press(forDuration: 0.1,
                          thenDragTo: downOnPaper.withOffset(CGVector(dx: 0, dy: 140)))
        waitForCameraViewfinder(in: app)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.90)).tap()
        waitUntil { !panel.exists && addText.isHittable }
        XCTAssertEqual(image.value as? String, originalValue)
        XCTAssertFalse(reset.exists)

        // Holding activates free movement; releasing removes the temporary activation value.
        let before = image.frame
        let stickerStart = image.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        stickerStart.press(forDuration: 0.65, thenDragTo: stickerStart.withOffset(CGVector(dx: 45, dy: 110)))
        waitUntil {
            image.frame.midX - before.midX > 25 && image.frame.midY - before.midY > 60 &&
                (image.value as? String)?.contains("移动已激活") == false
        }
        let originalCoordinates = originalValue?.components(separatedBy: " · ").first?.components(separatedBy: ", ") ?? []
        let movedCoordinates = (image.value as? String)?.components(separatedBy: " · ").first?.components(separatedBy: ", ") ?? []
        XCTAssertEqual(originalCoordinates.count, 2)
        XCTAssertEqual(movedCoordinates.count, 2)
        XCTAssertNotEqual(movedCoordinates.first, originalCoordinates.first, "The item's world X must change")
        XCTAssertNotEqual(movedCoordinates.last, originalCoordinates.last, "The item's world Y must change")
        XCTAssertFalse(reset.exists, "Moving an activated sticker must not change the viewport")
        XCTAssertFalse(panel.exists)
        XCTAssertFalse(app.buttons["sticker-open-camera"].exists)
        XCTAssertTrue(addText.isHittable)
        XCTAssertTrue(app.buttons["home-tab-trips"].isHittable)
    }

    @MainActor func testTwoFingerTransformsDoNotBrowseOrOpenCamera() {
        let app = launchBoard(fixture: true, cameraPreviewFixture: true)
        let image = canvasItems(in: app).firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        let originalValue = image.value as? String
        let originalFrame = image.frame
        let reset = app.buttons["sticker-reset-viewport"]
        let panel = app.descendants(matching: .any)["sticker-camera-panel"].firstMatch

        image.pinch(withScale: 1.25, velocity: 1)
        waitUntil {
            image.frame.width > originalFrame.width * 1.12 &&
                image.frame.height > originalFrame.height * 1.12
        }
        XCTAssertEqual(image.value as? String, originalValue,
                       "Pinching must keep the sticker's world coordinates unchanged")
        XCTAssertFalse(reset.exists, "Pinching must not pan the viewport")
        XCTAssertFalse(panel.exists, "Pinching must not open the camera")

        let pinchedFrame = image.frame
        image.rotate(CGFloat.pi / 12, withVelocity: 1)
        waitUntil { abs(image.frame.width - pinchedFrame.width) > 5 }
        XCTAssertEqual(image.value as? String, originalValue,
                       "Rotation must keep the sticker's world coordinates unchanged")
        XCTAssertFalse(reset.exists, "Rotation must not pan the viewport")
        XCTAssertFalse(panel.exists, "Rotation must not open the camera")

        // Two-finger transforms must release their ownership so ordinary swipes can browse again.
        let transformedFrame = image.frame
        let swipe = image.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        swipe.press(forDuration: 0.1, thenDragTo: swipe.withOffset(CGVector(dx: 70, dy: 0)))
        waitUntil { reset.exists && image.frame.midX - transformedFrame.midX > 40 }
        XCTAssertEqual(image.frame.midY, transformedFrame.midY, accuracy: 6)
        XCTAssertEqual(image.frame.width, transformedFrame.width, accuracy: 6)
        XCTAssertEqual(image.frame.height, transformedFrame.height, accuracy: 6)
        XCTAssertEqual(image.value as? String, originalValue,
                       "Browsing after a transform must not move the sticker in world coordinates")
        XCTAssertFalse(panel.exists)
    }

    @MainActor func testInfiniteCanvasPansBeyondViewportAndRestoresAfterRelaunch() {
        let app = launchBoard(fixture: true)
        let fixture = canvasItems(in: app).firstMatch
        XCTAssertTrue(fixture.waitForExistence(timeout: 5))
        let fixtureID = fixture.identifier
        let originalValue = fixture.value as? String
        let originalFrame = fixture.frame
        let title = app.staticTexts["sticker-page-title"].firstMatch
        let titleFrame = title.frame
        let reset = app.buttons["sticker-reset-viewport"]
        let panel = app.descendants(matching: .any)["sticker-camera-panel"].firstMatch
        XCTAssertFalse(reset.exists)

        // Upward paper movement cannot scroll the canvas vertically.
        panBlankPaper(in: app, vertical: -0.30)
        XCTAssertFalse(reset.exists)
        XCTAssertEqual(fixture.frame.midY, originalFrame.midY, accuracy: 6)
        XCTAssertEqual(fixture.value as? String, originalValue)

        // Move farther than a complete screen horizontally using blank paper.
        // Screen coordinates deliberately avoid both the fixed header and the fixture.
        for _ in 0..<3 { panBlankPaper(in: app, horizontal: -0.42) }
        panBlankPaper(in: app, horizontal: 0.42)
        panBlankPaper(in: app, horizontal: -0.42)
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        XCTAssertFalse(panel.exists)
        XCTAssertEqual(title.frame.minX, titleFrame.minX, accuracy: 2)
        XCTAssertEqual(title.frame.minY, titleFrame.minY, accuracy: 2)
        XCTAssertTrue(app.buttons["home-tab-trips"].isHittable)

        // The Aa action must create content in the visible viewport, not at the old origin.
        app.buttons["sticker-add-text"].tap()
        saveText("Far away memories", in: app)
        let text = canvasItems(in: app).matching(NSPredicate(format: "label CONTAINS %@", "Far away memories")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        waitUntil { text.isHittable }
        XCTAssertTrue(app.frame.insetBy(dx: 16, dy: 120).contains(text.frame))
        let textID = text.identifier
        let savedFrame = text.frame
        let savedValue = text.value as? String
        attachScreenshot(app, name: "New text in a viewport beyond the original canvas")

        app.terminate()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let tab = app.buttons["home-tab-stickers"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
        let restoredText = app.descendants(matching: .any)[textID].firstMatch
        XCTAssertTrue(restoredText.waitForExistence(timeout: 5))
        waitUntil { restoredText.isHittable }
        XCTAssertEqual(restoredText.frame.midX, savedFrame.midX, accuracy: 6)
        XCTAssertEqual(restoredText.frame.midY, savedFrame.midY, accuracy: 6)
        XCTAssertEqual(restoredText.value as? String, savedValue)

        // Recentring reveals the original sticker without changing its stored position.
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        reset.tap()
        let restoredFixture = app.descendants(matching: .any)[fixtureID].firstMatch
        waitUntil { restoredFixture.isHittable && !reset.exists }
        XCTAssertEqual(restoredFixture.frame.midX, originalFrame.midX, accuracy: 6)
        XCTAssertEqual(restoredFixture.frame.midY, originalFrame.midY, accuracy: 6)
        XCTAssertEqual(restoredFixture.value as? String, originalValue)

        // The distant text remains on the board and can be found by panning back.
        for _ in 0..<3 { panBlankPaper(in: app, horizontal: -0.42) }
        waitUntil { restoredText.isHittable }
        XCTAssertEqual(restoredText.frame.midX, savedFrame.midX, accuracy: 10)
        XCTAssertEqual(restoredText.frame.midY, savedFrame.midY, accuracy: 10)
        XCTAssertEqual(restoredText.value as? String, savedValue)
        XCTAssertFalse(panel.exists)
    }

    @MainActor func testDoubleTapPlacesTextAtTouchAfterPanning() {
        let app = launchBoard()
        // Horizontal panning changes the world location represented by a screen touch.
        panBlankPaper(in: app, horizontal: 0.42)
        XCTAssertFalse(app.descendants(matching: .any)["sticker-camera-panel"].firstMatch.exists)
        XCTAssertTrue(app.buttons["sticker-reset-viewport"].waitForExistence(timeout: 5))

        let point = CGVector(dx: 0.68, dy: 0.55)
        let touch = app.coordinate(withNormalizedOffset: point)
        touch.doubleTap()
        saveText("Here", in: app)
        let text = canvasItems(in: app).matching(NSPredicate(format: "label CONTAINS %@", "Here")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        waitUntil { text.isHittable }
        XCTAssertEqual(text.frame.midX, app.frame.minX + app.frame.width * point.dx, accuracy: 12)
        XCTAssertEqual(text.frame.midY, app.frame.minY + app.frame.height * point.dy, accuracy: 12)

        // Double-tapping existing text edits it rather than adding another item.
        text.doubleTap()
        let input = app.descendants(matching: .any)["sticker-text-input"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "Here")
        let cancel = app.navigationBars.buttons.matching(
            NSPredicate(format: "label == %@ OR label == %@", "取消", "Cancel")
        ).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        waitUntil { !input.exists && text.isHittable }
    }

    @discardableResult
    @MainActor private func waitForCameraViewfinder(in app: XCUIApplication,
                                                   file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let panel = app.descendants(matching: .any)["sticker-camera-panel"].firstMatch
        let viewfinder = app.descendants(matching: .any)["sticker-camera-viewfinder"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(viewfinder.waitForExistence(timeout: 5), file: file, line: line)
        // The simulator may disable capture; interaction readiness belongs to the preview surface.
        waitUntil(file: file, line: line) { panel.isHittable && viewfinder.isHittable }
        return viewfinder
    }

    @MainActor private func panBlankPaper(in app: XCUIApplication, horizontal: CGFloat = 0,
                                          vertical: CGFloat = 0) {
        let start: XCUICoordinate
        let end: XCUICoordinate
        if horizontal != 0 {
            start = app.coordinate(withNormalizedOffset: CGVector(dx: horizontal < 0 ? 0.83 : 0.17, dy: 0.76))
            end = start.withOffset(CGVector(dx: app.frame.width * horizontal, dy: 0))
        } else {
            start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.87, dy: vertical < 0 ? 0.76 : 0.30))
            end = start.withOffset(CGVector(dx: 0, dy: app.frame.height * vertical))
        }
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    @MainActor private func saveText(_ text: String, in app: XCUIApplication) {
        let input = app.descendants(matching: .any)["sticker-text-input"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText(text)
        app.buttons["sticker-save-text"].tap()
        waitUntil { !input.exists }
    }

    @MainActor private func launchBoard(fixture: Bool = false, cameraPreviewFixture: Bool = false,
                                        populated: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset"]
        if fixture { app.launchArguments.append("--sticker-fixture") }
        if populated { app.launchArguments.append("--populated-sticker-fixture") }
        if cameraPreviewFixture { app.launchArguments.append("--camera-preview-fixture") }
        app.launch()
        let tab = app.buttons["home-tab-stickers"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
        XCTAssertTrue(app.buttons["sticker-add-text"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor private func canvasItems(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "sticker-item-"))
    }

    @MainActor private func assertCameraBlackFrame(in app: XCUIApplication, panel: CGRect, preview: CGRect,
                                                  file: StaticString = #filePath, line: UInt = #line) {
        let screenshot = app.screenshot()
        guard let image = screenshot.image.cgImage else {
            XCTFail("Unable to read camera screenshot pixels", file: file, line: line)
            return
        }
        let screen = app.frame
        let scaleX = CGFloat(image.width) / screen.width
        let scaleY = CGFloat(image.height) / screen.height

        func rgb(at point: CGPoint) -> [UInt8]? {
            let x = floor((point.x - screen.minX) * scaleX)
            let y = floor((point.y - screen.minY) * scaleY)
            guard x >= 0, y >= 0, x < CGFloat(image.width), y < CGFloat(image.height),
                  let sample = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }
            var rgba = [UInt8](repeating: 0, count: 4)
            let rendered = rgba.withUnsafeMutableBytes { bytes -> Bool in
                guard let context = CGContext(data: bytes.baseAddress, width: 1, height: 1,
                                              bitsPerComponent: 8, bytesPerRow: 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                                                CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                return true
            }
            return rendered ? Array(rgba.prefix(3)) : nil
        }

        // SwiftUI reports the unclipped, aspect-fill image bounds for ancestor AX frames.
        // Measure the two visible black runs in the rendered row instead of those bounds.
        let sampleY = screen.minY + screen.height * 0.25
        let row: [[UInt8]] = (0..<Int(screen.width)).map { x in
            rgb(at: CGPoint(x: screen.minX + CGFloat(x), y: sampleY)) ?? [255, 255, 255]
        }
        let black = row.map { ($0.max() ?? 255) <= 12 }
        guard let left = black.firstIndex(of: true), let right = black.lastIndex(of: true) else {
            XCTFail("The camera must have a visible opaque black frame", file: file, line: line)
            return
        }
        var leftEnd = left
        while leftEnd < black.count && black[leftEnd] { leftEnd += 1 }
        var rightStart = right
        while rightStart > 0 && black[rightStart - 1] { rightStart -= 1 }
        XCTAssertGreaterThanOrEqual(leftEnd - left, 35, "Left black border", file: file, line: line)
        XCTAssertGreaterThanOrEqual(right - rightStart + 1, 35, "Right black border", file: file, line: line)
        XCTAssertLessThan(leftEnd + 6, rightStart - 6, "The frame must contain a visible viewfinder", file: file, line: line)
        if leftEnd + 6 < rightStart - 6 {
            for x in [leftEnd + 6, rightStart - 6] {
                let brightness = row[x].reduce(0) { $0 + Int($1) } / 3
                XCTAssertGreaterThan(brightness, 80, "Bright fixture must be visible inside the border", file: file, line: line)
            }
        }
        let island = rgb(at: CGPoint(x: screen.midX, y: screen.minY + 32)) ?? [255, 255, 255]
        XCTAssertLessThanOrEqual(Int(island.max() ?? 255), 12, "The island area must remain black", file: file, line: line)
    }

    @MainActor private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private func waitUntil(file: StaticString = #filePath, line: UInt = #line,
                                     _ condition: @escaping () -> Bool) {
        let predicate = NSPredicate { _, _ in condition() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 5),
                       .completed, file: file, line: line)
    }
}
