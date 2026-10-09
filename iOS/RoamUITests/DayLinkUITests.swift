import XCTest

final class DayLinkUITests: XCTestCase {
    func testTapCardBodyOpensDay() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset"]
        app.launch()
        app.buttons["trip-tokyo"].tap()
        let card = app.descendants(matching: .any)["day-header-0"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["daily-itinerary"].firstMatch.waitForExistence(timeout: 5))
    }

    func testSwipeBodyExpandsDayInsteadOfScrollingCard() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset"]
        app.launch()
        app.buttons["trip-tokyo"].tap()
        let card = app.descendants(matching: .any)["day-header-0"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let end = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.descendants(matching: .any)["daily-itinerary"].firstMatch.waitForExistence(timeout: 5))
    }

    func testCollectLinkDirectlyFromDayCard() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset"]
        app.launch()
        app.buttons["trip-tokyo"].tap()
        let card = app.descendants(matching: .any)["day-header-0"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["show-route"].exists)
        XCTAssertTrue(app.buttons["add-day"].exists)
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .press(forDuration: 0.05, thenDragTo: card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
        let collect = app.buttons["collect-day-link"].firstMatch
        XCTAssertTrue(collect.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "collect-day-link").count, 1)
        XCTAssertEqual(collect.label, "添加攻略")
        let collectIsHittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: collect)
        XCTAssertEqual(XCTWaiter.wait(for: [collectIsHittable], timeout: 5), .completed,
                       "The bottom guide button should be available without scrolling")
        XCTAssertFalse(app.buttons["show-route"].exists)
        XCTAssertFalse(app.buttons["add-day"].exists)
        collect.tap()
        let save = app.buttons["save-day-link"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
        let field = app.textViews["day-link-input"].exists ? app.textViews["day-link-input"] : app.textFields["day-link-input"]
        field.tap()
        field.typeText("https://example.invalid/day-one-guide")
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(collect.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["save-day-link"].exists)
        let notes = app.descendants(matching: .any)["day-notes-section"].firstMatch
        let guides = app.descendants(matching: .any)["day-guides-section"].firstMatch
        let edit = guides.buttons["编辑备忘"].firstMatch
        for _ in 0..<6 {
            if edit.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(notes.exists)
        XCTAssertTrue(notes.buttons["add-备忘"].exists)
        XCTAssertFalse(notes.buttons["编辑备忘"].exists, "Imported guides should be separate from ordinary notes")
        XCTAssertTrue(guides.exists)
        XCTAssertTrue(edit.isHittable, "Saved guide should be visible in the day's guide section")
        XCTAssertEqual(app.buttons.matching(identifier: "collect-day-link").count, 1)
    }
}
