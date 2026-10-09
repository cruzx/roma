import XCTest

final class LocalizationUITests: XCTestCase {
    @MainActor func testLanguageSwitchAppliesImmediatelyPersistsAndPreservesTrips() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset"]
        app.launch()
        XCTAssertTrue(app.staticTexts["我的旅行"].waitForExistence(timeout: 10))
        openSettings(in: app)
        app.buttons["app-language-en"].tap()
        XCTAssertTrue(app.navigationBars["Language"].waitForExistence(timeout: 5))
        app.buttons["language-settings-done"].tap()
        XCTAssertTrue(app.staticTexts["Trips"].waitForExistence(timeout: 5))
        app.buttons["library-settings"].tap()
        XCTAssertTrue(app.buttons["Home Background"].waitForExistence(timeout: 5),
                      "Hand-drawn button labels must retain localized string-key semantics")
        XCTAssertTrue(app.buttons["iCloud Sync"].exists)
        app.buttons["language-settings"].tap()
        app.buttons["language-settings-done"].tap()
        XCTAssertTrue(app.buttons["trip-tokyo"].exists, "User trips must survive a language switch")
        app.buttons["home-tab-stickers"].tap()
        let title = app.staticTexts["sticker-page-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Travel Journal")
        XCTAssertTrue(app.buttons["sticker-add-text"].isHittable)
        XCTAssertTrue(app.buttons["sticker-import-photo"].isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "English Travel Journal"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["sticker-add-text"].tap()
        XCTAssertTrue(app.navigationBars["Add Text"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Save"].exists)
        app.buttons["Cancel"].tap()

        app.terminate()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Trips"].waitForExistence(timeout: 10))
        openSettings(in: app)
        app.buttons["app-language-zh-Hans"].tap()
        XCTAssertTrue(app.navigationBars["语言"].waitForExistence(timeout: 5))
        app.buttons["language-settings-done"].tap()
        XCTAssertTrue(app.staticTexts["我的旅行"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["trip-tokyo"].exists)
        app.buttons["home-tab-stickers"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "旅游手账")
    }

    @MainActor private func openSettings(in app: XCUIApplication) {
        let settings = app.buttons["library-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let language = app.buttons["language-settings"]
        XCTAssertTrue(language.waitForExistence(timeout: 5))
        language.tap()
        XCTAssertTrue(app.buttons["app-language-en"].waitForExistence(timeout: 5))
    }
}
