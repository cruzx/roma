import CoreGraphics
import XCTest
@testable import Roam

final class StickerCanvasMotionTests: XCTestCase {
    func testDecelerationStartsAtCurrentPositionAndReachesItsExactEndpoint() {
        let motion = StickerCanvasDeceleration(start: 70, predictedAdditionalTravel: 100, viewportWidth: 400)
        XCTAssertEqual(motion.translation(at: 0), 70)
        XCTAssertEqual(motion.translation(at: motion.duration), 170)
        XCTAssertEqual(motion.translation(at: motion.duration * 3), 170)
        XCTAssertEqual(motion.translation(at: -1), 70)
        XCTAssertGreaterThanOrEqual(motion.duration, 0.25)
        XCTAssertLessThanOrEqual(motion.duration, 0.45)
    }

    func testCoastingMovesMonotonicallyAndSlowsInEitherDirection() {
        for direction in [CGFloat(-1), CGFloat(1)] {
            let motion = StickerCanvasDeceleration(start: -30, predictedAdditionalTravel: direction * 150,
                                                   viewportWidth: 400)
            var previous = motion.start
            var previousStep = CGFloat.infinity
            for frame in 1...120 {
                let position = motion.translation(at: motion.duration * Double(frame) / 120)
                let step = (position - previous) * direction
                XCTAssertGreaterThanOrEqual(step, 0)
                XCTAssertLessThanOrEqual(step, previousStep + 0.000_001)
                previous = position
                previousStep = step
            }
            XCTAssertEqual(previous, motion.end)
        }
    }

    func testPredictedTravelIsLimitedToFiftyFivePercentOfViewport() {
        for direction in [CGFloat(-1), CGFloat(1)] {
            let motion = StickerCanvasDeceleration(start: 0, predictedAdditionalTravel: direction * 10_000,
                                                   viewportWidth: 400)
            XCTAssertEqual(motion.distance, direction * 220, accuracy: 0.000_001)
            XCTAssertEqual(motion.duration, 0.45, accuracy: 0.000_001)
        }
    }

    func testSmallTravelAndReducedMotionSettleWithoutCoasting() {
        for predicted in [CGFloat(-1.99), CGFloat(0), CGFloat(1.99)] {
            let motion = StickerCanvasDeceleration(start: 80, predictedAdditionalTravel: predicted,
                                                   viewportWidth: 400)
            XCTAssertEqual(motion.duration, 0)
            XCTAssertEqual(motion.translation(at: 1), 80)
        }
        let reduced = StickerCanvasDeceleration(start: 80, predictedAdditionalTravel: 150,
                                                viewportWidth: 400, reduceMotion: true)
        XCTAssertEqual(reduced.duration, 0)
        XCTAssertEqual(reduced.end, 80)
    }

    func testNonfiniteAndExtremeInputsAlwaysProduceFinitePositions() {
        let values: [CGFloat] = [.nan, .infinity, -.infinity, 0, -400, 400,
                                 .greatestFiniteMagnitude, -.greatestFiniteMagnitude]
        for start in values {
            for predicted in values {
                for width in values {
                    let motion = StickerCanvasDeceleration(start: start,
                                                           predictedAdditionalTravel: predicted,
                                                           viewportWidth: width)
                    XCTAssertTrue(motion.start.isFinite)
                    XCTAssertTrue(motion.end.isFinite)
                    XCTAssertTrue(motion.duration.isFinite)
                    XCTAssertTrue(motion.translation(at: motion.duration / 2).isFinite)
                    XCTAssertTrue(motion.translation(at: .nan).isFinite)
                    XCTAssertTrue(motion.translation(at: .infinity).isFinite)
                    XCTAssertTrue(motion.translation(at: -.infinity).isFinite)
                    if width <= 0 || !width.isFinite { XCTAssertEqual(motion.distance, 0) }
                }
            }
        }
    }

    @MainActor func testRegrabbingCoastKeepsItsPositionAndDiscardsOldCompletion() {
        let motion = StickerCanvasMotion()
        defer { motion.stop() }
        var completions = 0
        motion.drag(to: 90)
        motion.endDrag(predictedAdditionalTravel: 120, viewportWidth: 400, reduceMotion: false) {
            completions += 1
        }
        XCTAssertTrue(motion.isMoving)
        XCTAssertFalse(motion.isDragging)
        motion.advance(at: 100)
        motion.advance(at: 100.1)
        XCTAssertGreaterThan(motion.translation, 90)

        let caughtPosition = motion.translation
        motion.drag(to: 0)
        XCTAssertEqual(motion.translation, caughtPosition)
        XCTAssertTrue(motion.isDragging)
        motion.drag(to: 15)
        XCTAssertEqual(motion.translation, caughtPosition + 15)
        motion.drag(to: -8)
        XCTAssertEqual(motion.translation, caughtPosition - 8)
        XCTAssertEqual(completions, 0)
        motion.endDrag(predictedAdditionalTravel: 0, viewportWidth: 400, reduceMotion: false) {
            completions += 1
        }
        XCTAssertEqual(completions, 1)
        XCTAssertFalse(motion.isMoving)
    }

    @MainActor func testDisplayTimestampsSettleAtEndpointAndCompleteOnlyOnce() {
        let motion = StickerCanvasMotion()
        defer { motion.stop() }
        var completions = 0
        motion.drag(to: -40)
        motion.endDrag(predictedAdditionalTravel: -100, viewportWidth: 400, reduceMotion: false) {
            completions += 1
            XCTAssertFalse(motion.isMoving)
        }
        motion.advance(at: 20)
        motion.advance(at: 20.1)
        XCTAssertLessThan(motion.translation, -40)
        XCTAssertGreaterThan(motion.translation, -140)
        motion.advance(at: 21)
        XCTAssertEqual(motion.translation, -140)
        XCTAssertEqual(completions, 1)
        motion.advance(at: 22)
        XCTAssertEqual(completions, 1)
    }

    @MainActor func testImmediateCompletionCanResetAndIsCalledOnlyOnce() {
        let motion = StickerCanvasMotion()
        var completions = 0
        motion.drag(to: 120)
        motion.endDrag(predictedAdditionalTravel: 160, viewportWidth: 400, reduceMotion: true) {
            completions += 1
            XCTAssertEqual(motion.translation, 120)
            motion.reset()
        }
        motion.endDrag(predictedAdditionalTravel: 0, viewportWidth: 400, reduceMotion: true) {
            completions += 1
        }
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(motion.translation, 0)
        XCTAssertFalse(motion.isMoving)
    }

    @MainActor func testStopFreezesTranslationAndInvalidDragValuesAreIgnored() {
        let motion = StickerCanvasMotion()
        var completions = 0
        motion.drag(to: .nan)
        XCTAssertFalse(motion.isDragging)
        motion.drag(to: 45)
        motion.drag(to: .infinity)
        XCTAssertEqual(motion.translation, 45)
        motion.endDrag(predictedAdditionalTravel: 160, viewportWidth: 400, reduceMotion: false) {
            completions += 1
        }
        motion.stop()
        XCTAssertEqual(motion.translation, 45)
        XCTAssertFalse(motion.isMoving)
        XCTAssertEqual(completions, 0)
        motion.reset()
        XCTAssertEqual(motion.translation, 0)
    }
}
