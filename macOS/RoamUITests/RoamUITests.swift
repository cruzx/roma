import XCTest

final class RoamUITests: XCTestCase {
    @MainActor func testPlanAndPersistTrip() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["trip-tokyo"].waitForExistence(timeout: 15))
        capture("01-home")
        app.buttons["trip-tokyo"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["day-header-0"].waitForExistence(timeout: 5))
        capture("02-table")
        app.buttons["day-header-0"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["add-逛什么"].waitForExistence(timeout: 5))
        capture("03-day")
        app.buttons["add-item"].tap()
        let title = app.textFields["item-title"].exists ? app.textFields["item-title"] : app.textViews["item-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText("Coffee stop")
        app.buttons["save-item"].tap()
        XCTAssertTrue(app.buttons["day-item-Coffee stop"].waitForExistence(timeout: 5))
        capture("15-day-added")
        app.terminate()
        app.launchArguments = ["--uitesting", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        app.buttons["trip-tokyo"].tap()
        app.buttons["day-header-0"].tap()
        XCTAssertTrue(app.buttons["day-item-Coffee stop"].waitForExistence(timeout: 5))
    }

    @MainActor func testCreateTripAndAddDay() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        app.buttons["new-trip"].tap()
        let field = app.descendants(matching: .any).matching(identifier: "destination-field").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Weekend")
        app.buttons["save-trip"].tap()
        XCTAssertTrue(app.buttons["trip-Weekend"].waitForExistence(timeout: 5))
        app.buttons["trip-Weekend"].tap()
        app.buttons["add-day"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "day-title").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "trip-summary").firstMatch.label.contains("4 天"))
        app.buttons["add-item"].tap()
        capture("04-native-form")
        XCTAssertFalse(app.buttons["save-item"].isEnabled)
    }

    @MainActor func testFrozenDayHeader() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["trip-tokyo"].waitForExistence(timeout: 10))
        app.buttons["trip-tokyo"].tap()
        let header = app.buttons["day-header-0"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        let initialY = header.frame.minY
        let firstCell = app.buttons["cell-0-逛什么"]
        let cellY = firstCell.frame.minY
        firstCell.swipeUp()
        XCTAssertEqual(header.frame.minY, initialY, accuracy: 2)
        XCTAssertLessThanOrEqual(firstCell.frame.minY, cellY + 2) // On a tall Mac window the full table can fit without vertical scrolling.
        let foodCell = app.buttons["cell-0-吃什么"]
        foodCell.swipeLeft()
        let secondHeader = app.buttons["day-header-1"]
        let secondCell = app.buttons["cell-1-吃什么"]
        XCTAssertEqual(secondHeader.frame.minX, secondCell.frame.minX, accuracy: 2)
        capture("05-frozen-header-scrolled")
        app.segmentedControls["view-mode"].buttons["按天查看"].tap()
        XCTAssertTrue(app.buttons["add-逛什么"].waitForExistence(timeout: 5))
    }

    @MainActor func testLiveMapSearchAndRoute() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["trip-tokyo"].waitForExistence(timeout: 10))
        app.buttons["trip-tokyo"].tap()
        for query in ["广州塔", "广州图书馆"] {
            app.buttons["add-item"].tap()
            app.buttons["choose-place"].tap()
            changeSearchCity(app, to: "中国 广州")
            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.press(forDuration: 1.2)
            if app.menuItems["全选"].waitForExistence(timeout: 2) { app.menuItems["全选"].tap() }
            else {
                let old = field.value as? String ?? ""
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
            }
            field.typeText(query)
            field.typeText("\n")
            let result = app.buttons.matching(identifier: "place-result").firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 30))
            result.tap()
            capture("06-place-search")
            app.buttons["save-place"].tap()
            XCTAssertTrue(app.buttons["save-item"].waitForExistence(timeout: 5))
            capture("07-place-editor")
            app.buttons["save-item"].tap()
        }
        app.buttons["show-route"].tap()
        XCTAssertTrue(app.buttons["calculate-route"].waitForExistence(timeout: 5))
        app.buttons["calculate-route"].tap()
        let success = app.staticTexts["道路路线已更新，时间为估算。"]
        XCTAssertTrue(success.waitForExistence(timeout: 60))
        capture("08-map-route")
        app.buttons["完成"].tap()
        app.terminate()
        app.launchArguments = ["--uitesting", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        app.buttons["trip-tokyo"].tap()
        app.buttons["show-route"].tap()
        XCTAssertTrue(app.staticTexts["2 个地点"].waitForExistence(timeout: 5))
    }

    @MainActor func testManualMapPinCanBeSaved() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["trip-tokyo"].waitForExistence(timeout: 10))
        app.buttons["trip-tokyo"].tap()
        app.buttons["add-item"].tap()
        app.buttons["choose-place"].tap()
        app.segmentedControls.buttons["地图选点"].tap()
        let name = app.textFields["pin-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Manual meeting point")
        XCTAssertTrue(app.buttons["save-place"].isEnabled)
        app.buttons["save-place"].tap()
        app.buttons["save-item"].tap()
        app.buttons["show-route"].tap()
        XCTAssertTrue(app.staticTexts["Manual meeting point"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["calculate-route"].isEnabled)
    }

    @MainActor func testChooseThreePlacesInOnePlanAndFilterRoute() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["trip-tokyo"].waitForExistence(timeout: 10))
        app.buttons["trip-tokyo"].tap()
        app.buttons["add-item"].tap()
        app.buttons["choose-place"].tap()
            changeSearchCity(app, to: "中国 广州")
        for query in ["广州塔", "广州图书馆", "广东省博物馆"] {
            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeKey("a", modifierFlags: .command)
            field.typeText(XCUIKeyboardKey.delete.rawValue)
            field.typeText(query)
            field.typeText("\n")
            XCTAssertEqual(field.value as? String, query)
            let result = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "place-result", query)).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 30))
            result.tap()
        }
        XCTAssertEqual(app.buttons["save-place"].label, "添加 3 个地点")
        capture("09-multi-select")
        app.buttons["save-place"].tap()
        app.buttons["save-item"].tap()
        app.buttons["show-route"].tap()
        XCTAssertTrue(app.buttons["选择地点 (3)"].exists || app.buttons["select-route-stops"].label.contains("3"))
        app.buttons["calculate-route"].tap()
        XCTAssertTrue(app.staticTexts["道路路线已更新，时间为估算。"].waitForExistence(timeout: 60))
        capture("10-three-stop-route")
        app.buttons["select-route-stops"].tap()
        let switches = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "route-select-"))
        XCTAssertEqual(switches.count, 3)
        switches.element(boundBy: 1).tap()
        XCTAssertEqual(switches.element(boundBy: 1).value as? String, "未选")
        app.buttons["route-selection-done"].tap()
        XCTAssertTrue(app.buttons["select-route-stops"].label.contains("2"))
        app.terminate()
        app.launchArguments = ["--uitesting", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        app.buttons["trip-tokyo"].tap()
        app.buttons["show-route"].tap()
        XCTAssertTrue(app.buttons["select-route-stops"].label.contains("2"))
        app.buttons["select-route-stops"].tap()
        app.buttons["全选"].tap()
        app.buttons["route-selection-done"].tap()
        XCTAssertTrue(app.buttons["select-route-stops"].label.contains("3"))
    }

    @MainActor func testTokyoTypingShowsSuggestionsAndKeepsMultipleSelection() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["trip-tokyo"].waitForExistence(timeout: 10))
        app.buttons["trip-tokyo"].tap()
        app.buttons["add-item"].tap()
        app.buttons["choose-place"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        for query in ["池袋", "日本桥", "银座"] {
            field.tap()
            let old = field.value as? String ?? ""
            if old != "城市、店名或地址" && old != "输入景点、餐厅、酒店名称" { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
            field.typeText(query)
            let result = app.buttons.matching(identifier: "place-result").firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 35), query)
            XCTAssertTrue(result.label.contains("日本"), result.label)
            capture("11-tokyo-autocomplete")
            result.tap()
        }
        XCTAssertEqual(app.buttons["save-place"].label, "添加 3 个地点")
        capture("12-tokyo-three-places")
        app.buttons["save-place"].tap()
        app.buttons["save-item"].tap()
        app.buttons["show-route"].tap()
        XCTAssertTrue(app.buttons["select-route-stops"].label.contains("3"))
    }

    @MainActor func testDomesticAutocompleteResolvesChosenSuggestion() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["trip-tokyo"].waitForExistence(timeout: 10))
        app.buttons["trip-tokyo"].tap()
        app.buttons["add-item"].tap()
        app.buttons["choose-place"].tap()
        changeSearchCity(app, to: "中国 广州")
        let field = app.searchFields.firstMatch
        field.tap(); field.typeText("广州图书")
        let suggestion = app.buttons.matching(identifier: "place-suggestion").firstMatch
        let appeared = suggestion.waitForExistence(timeout: 30)
        capture("13-domestic-search-state")
        XCTAssertTrue(appeared)
        suggestion.tap()
        let result = app.buttons.matching(identifier: "place-result").firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 20))
        XCTAssertTrue(result.label.contains("广州"))
        result.tap()
        XCTAssertEqual(app.buttons["save-place"].label, "添加 1 个地点")
    }

    @MainActor private func changeSearchCity(_ app: XCUIApplication, to city: String) {
        app.buttons["search-city"].tap()
        app.buttons["choose-country"].tap()
        app.buttons["country-CN"].tap()
        app.buttons["city-广州"].tap()
        capture("14-country-city-selection")
        app.buttons["confirm-search-city"].tap()
        XCTAssertTrue(app.buttons["search-city"].label.contains("广州"))
    }

    @MainActor private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent(name + ".png"))
        }
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
