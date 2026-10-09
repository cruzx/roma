import XCTest

final class HomeSearchUITests: XCTestCase {
    @MainActor func testSearchLivesInsideIconNavigationAndStillFiltersTrips() {
        let app = launchHome()
        let bar = navigation(in: app)
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        XCTAssertTrue(bar.buttons["home-tab-trips"].exists)
        XCTAssertTrue(bar.buttons["home-tab-stickers"].exists)
        XCTAssertTrue(bar.buttons["home-search-toggle"].exists)
        XCTAssertFalse(bar.staticTexts["Trips"].exists)
        XCTAssertFalse(bar.staticTexts["Stickers"].exists)
        XCTAssertFalse(app.textFields["home-search-input"].isHittable)
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        XCTAssertLessThan(bar.frame.width, 220)
        screenshot(app, "Icon-only bottom navigation")

        let content = app.scrollViews.firstMatch
        content.swipeUp()
        waitUntil { (bar.value as? String) == "已展开" && bar.frame.width > 180 }
        content.swipeDown()
        waitUntil { (bar.value as? String) == "已展开" && bar.frame.width > 180 }

        bar.buttons["home-search-toggle"].tap()
        let input = app.textFields["home-search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        waitUntil { bar.frame.width > 250 }
        input.typeText("东京")
        waitUntil { app.buttons["trip-tokyo"].exists && !app.buttons["trip-kyoto"].exists }
        screenshot(app, "Search expanded inside bottom navigation")
        input.typeText("\n")
        waitUntil { app.keyboards.count == 0 }
        app.buttons["trip-tokyo"].tap()
        waitUntil { !bar.isHittable }
        app.buttons["back-trip"].tap()
        waitUntil { bar.isHittable }
        XCTAssertEqual(app.keyboards.count, 0, "Returning from detail must not replay an old focus request")

        let clear = app.buttons["home-search-clear"]
        clear.tap()
        XCTAssertTrue(app.buttons["trip-kyoto"].waitForExistence(timeout: 5))
        clear.tap()
        waitUntil { !input.isHittable && app.keyboards.count == 0 && bar.frame.width < 220 }
        app.buttons["trip-tokyo"].tap()
        waitUntil { !bar.isHittable }
    }

    @MainActor func testSearchFromStickersReturnsToTripsAndFocusesInput() {
        let app = launchHome()
        app.buttons["home-tab-stickers"].tap()
        XCTAssertTrue(app.buttons["sticker-add-text"].waitForExistence(timeout: 5))
        app.buttons["home-search-toggle"].tap()
        let input = app.textFields["home-search-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.typeText("京都")
        waitUntil { app.buttons["trip-kyoto"].exists && !app.buttons["trip-tokyo"].exists }
        app.buttons["home-tab-stickers"].tap()
        waitUntil { app.buttons["sticker-add-text"].exists && app.keyboards.count == 0 }
        app.buttons["home-tab-trips"].tap()
        XCTAssertTrue(app.buttons["trip-tokyo"].waitForExistence(timeout: 5))
        XCTAssertFalse(input.isHittable)
    }

    @MainActor func testRecommendedTemplateHidesBottomNavigationAndRestoresItOnReturn() {
        let app = launchHome()
        let bar = navigation(in: app)
        let template = app.buttons["home-template-beijing"]
        for _ in 0..<5 {
            if template.exists && template.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(template.waitForExistence(timeout: 5))
        XCTAssertTrue(template.isHittable)
        template.tap()

        let create = app.buttons["create-template-trip"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        waitUntil { !bar.isHittable && !app.buttons["home-search-toggle"].isHittable }
        XCTAssertTrue(create.isHittable, "The template's own bottom action must remain available")
        screenshot(app, "Template detail hides persistent bottom navigation")

        let back = app.navigationBars["北京"].buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        waitUntil { bar.isHittable && app.buttons["home-tab-stickers"].isHittable }
        XCTAssertEqual(app.keyboards.count, 0)
        screenshot(app, "Bottom navigation restored after template preview")
    }

    @MainActor private func launchHome() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset"]
        app.launch()
        XCTAssertTrue(app.buttons["home-tab-trips"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor private func navigation(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["home-bottom-navigation"].firstMatch
    }

    @MainActor private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private func waitUntil(file: StaticString = #filePath, line: UInt = #line, _ condition: @escaping () -> Bool) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: 5),
                       .completed, file: file, line: line)
    }
}
