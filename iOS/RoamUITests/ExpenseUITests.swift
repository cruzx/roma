import XCTest

final class ExpenseUITests: XCTestCase {
    func testAddTwoExpensesAndShowDailyTotal() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset"]
        app.launch()
        app.buttons["trip-tokyo"].tap()
        let card = app.descendants(matching: .any)["day-header-0"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        let add = app.buttons["add-多少钱"]
        for (name, amount) in [("午餐测试", "12.30"), ("门票测试", "7.70")] {
            for _ in 0..<10 { if add.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(add.isHittable)
            add.tap()
            let title = app.textFields["item-title"].exists ? app.textFields["item-title"] : app.textViews["item-title"]
            title.tap(); title.typeText(name)
            let value = app.textFields["expense-amount"]
            value.tap(); value.typeText(amount)
            app.buttons["save-item"].tap()
        }
        XCTAssertTrue(app.staticTexts["合计 CNY 20.00"].waitForExistence(timeout: 5))
    }
}
