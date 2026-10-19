import XCTest

final class HomeSearchUITests: XCTestCase {
    @MainActor func testHomeHasTwoTabsWithoutSearch() {
        let app = launchHome()
        let bar = navigation(in: app)
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        XCTAssertTrue(bar.buttons["home-tab-trips"].exists)
        XCTAssertTrue(bar.buttons["home-tab-stickers"].exists)
        XCTAssertFalse(app.buttons["home-search-toggle"].exists)
        XCTAssertFalse(app.textFields["home-search-input"].exists)
        XCTAssertLessThan(bar.frame.width, 150)
        app.buttons["home-tab-stickers"].tap()
        XCTAssertTrue(app.buttons["sticker-add-text"].waitForExistence(timeout: 5))
        app.buttons["home-tab-trips"].tap()
        XCTAssertTrue(app.buttons["trip-tokyo"].waitForExistence(timeout: 5))
        screenshot(app, "Two-tab navigation without search")
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
