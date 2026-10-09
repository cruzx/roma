import CoreGraphics
import XCTest
@testable import Roam

final class StickerCanvasNavigationTests: XCTestCase {
    func testHorizontalSwipeKeepsItsAxisThroughVerticalMovementAndReversal() {
        var navigation = StickerCanvasNavigation()
        XCTAssertEqual(navigation.update(translation: CGSize(width: 16, height: 3)), .horizontal)
        XCTAssertEqual(navigation.horizontalTranslation, 16)

        XCTAssertEqual(navigation.update(translation: CGSize(width: 22, height: 180)), .horizontal)
        XCTAssertEqual(navigation.horizontalTranslation, 22)
        XCTAssertEqual(navigation.update(translation: CGSize(width: -70, height: -240)), .horizontal)
        XCTAssertEqual(navigation.horizontalTranslation, -70)
    }

    func testCameraPullKeepsItsIntentThroughSidewaysMovementAndReversal() {
        var navigation = StickerCanvasNavigation()
        XCTAssertEqual(navigation.update(translation: CGSize(width: 3, height: 16)), .camera)
        XCTAssertEqual(navigation.horizontalTranslation, 0)

        XCTAssertEqual(navigation.update(translation: CGSize(width: 180, height: 22)), .camera)
        XCTAssertEqual(navigation.update(translation: CGSize(width: -240, height: -70)), .camera)
        XCTAssertEqual(navigation.horizontalTranslation, 0)
    }

    func testUpwardSwipeStaysIgnoredWhenFingerReversesDownward() {
        var navigation = StickerCanvasNavigation()
        XCTAssertEqual(navigation.update(translation: CGSize(width: 1, height: -12)), .ignored)
        XCTAssertEqual(navigation.update(translation: CGSize(width: 0, height: 100)), .ignored)
        XCTAssertEqual(navigation.update(translation: CGSize(width: 200, height: 0)), .ignored)
        XCTAssertEqual(navigation.horizontalTranslation, 0)
    }

    func testThresholdWaitsForTenPointsAndAmbiguousDiagonalWaitsForClearAxis() {
        var navigation = StickerCanvasNavigation()
        XCTAssertEqual(navigation.update(translation: CGSize(width: 9.9, height: 0)), .undecided)
        XCTAssertEqual(navigation.horizontalTranslation, 0)
        XCTAssertEqual(navigation.update(translation: CGSize(width: 10, height: 0)), .horizontal)
        XCTAssertEqual(navigation.horizontalTranslation, 10)

        navigation.reset()
        XCTAssertEqual(navigation.update(translation: CGSize(width: 7, height: 7)), .undecided)
        XCTAssertEqual(navigation.update(translation: CGSize(width: 20, height: 20)), .undecided)
        XCTAssertEqual(navigation.update(translation: CGSize(width: 25, height: 20)), .undecided)
        XCTAssertEqual(navigation.horizontalTranslation, 0)
        XCTAssertEqual(navigation.update(translation: CGSize(width: 26, height: 20)), .horizontal)
        XCTAssertEqual(navigation.horizontalTranslation, 26)

        navigation.reset()
        XCTAssertEqual(navigation.update(translation: CGSize(width: 20, height: 25)), .undecided)
        XCTAssertEqual(navigation.update(translation: CGSize(width: 20, height: 26)), .camera)
        XCTAssertEqual(navigation.horizontalTranslation, 0)
    }

    func testResetAfterCancellationClearsTranslationAndAllowsANewDirection() {
        var navigation = StickerCanvasNavigation()
        navigation.update(translation: CGSize(width: -120, height: 4))
        navigation.reset()
        XCTAssertEqual(navigation.intent, .undecided)
        XCTAssertEqual(navigation.horizontalTranslation, 0)
        XCTAssertEqual(navigation.update(translation: CGSize(width: 0, height: 12)), .camera)

        navigation.reset()
        XCTAssertEqual(navigation.intent, .undecided)
        XCTAssertEqual(navigation.update(translation: CGSize(width: 0, height: -12)), .ignored)
        navigation.reset()
        XCTAssertEqual(navigation.update(translation: CGSize(width: 12, height: 0)), .horizontal)
    }
}
