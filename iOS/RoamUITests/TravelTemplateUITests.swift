import XCTest

final class TravelTemplateUITests: XCTestCase {
    func testHomeRecommendationPreviewAndCreateTemplateCopy() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset"]
        app.launch()
        let entry = app.buttons["home-template-beijing"]
        for _ in 0..<5 {
            if entry.exists && entry.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        let create = app.buttons["create-template-trip"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["template-departure"].firstMatch.exists)
        let photo = app.buttons["template-photo-beijing-0-0"]
        for _ in 0..<4 {
            if photo.exists && photo.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        photo.tap()
        let image = app.images["sight-photo-image"]
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        image.doubleTap()
        let zoomed = NSPredicate { _, _ in
            (image.value as? String).flatMap { Double($0.replacingOccurrences(of: "%", with: "")) }.map { $0 > 100 } ?? false
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: zoomed, object: nil)], timeout: 5), .completed)
        app.buttons["close-sight-photo"].tap()
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()
        let copy = app.buttons["trip-template-beijing"]
        XCTAssertTrue(copy.waitForExistence(timeout: 10))
        copy.tap()
        XCTAssertTrue(app.descendants(matching: .any)["day-cards"].firstMatch.waitForExistence(timeout: 5))
        app.descendants(matching: .any)["day-header-0"].firstMatch.tap()
        let copiedPhoto = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "day-photo-")).firstMatch
        XCTAssertTrue(copiedPhoto.waitForExistence(timeout: 5))
        copiedPhoto.tap()
        XCTAssertTrue(app.images["sight-photo-image"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["save-item"].exists)
        app.buttons["close-sight-photo"].tap()
    }
}
