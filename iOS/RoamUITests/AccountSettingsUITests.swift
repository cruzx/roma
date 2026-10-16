import XCTest
final class AccountSettingsUITests: XCTestCase {
    @MainActor func testUnconfiguredAccountScreenDoesNotOfferLogin() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset", "--account-unconfigured", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["library-settings"].waitForExistence(timeout: 15))
        app.buttons["library-settings"].tap()
        app.buttons["账号与同步"].tap()
        XCTAssertTrue(app.staticTexts["账号云服务尚未配置。部署后即可使用邮箱验证码登录；当前保存方式不变。"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["发送验证码"].exists)
        XCTAssertFalse(app.buttons["立即同步"].exists)
        XCTAssertFalse(app.buttons["Sync Now"].exists)
        XCTAssertFalse(app.staticTexts["两台设备互通"].exists)
        XCTAssertTrue(app.staticTexts["账号同步会员"].exists)
        app.buttons["订阅管理与说明"].tap()
        XCTAssertFalse(app.buttons["启用账号同步"].exists)
        XCTAssertFalse(app.buttons["切回原 iCloud 资料（重启后生效）"].exists)
        XCTAssertTrue(app.buttons["恢复购买"].exists)
        XCTAssertFalse(app.buttons["恢复购买"].isEnabled)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "account-sync-unconfigured"; shot.lifetime = .keepAlways; add(shot)
    }
}
