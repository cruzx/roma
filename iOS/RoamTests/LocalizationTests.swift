import XCTest
@testable import Roam

final class LocalizationTests: XCTestCase {
    func testSystemLanguageResolutionAndManualOverride() {
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["zh-Hant-TW", "en"]), "zh-Hans")
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["en-GB", "zh-Hans"]), "en")
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["fr-FR"]), "en")
        XCTAssertEqual(AppLanguage.chinese.resolvedIdentifier(preferredLanguages: ["en"]), "zh-Hans")
        XCTAssertEqual(AppLanguage.english.resolvedIdentifier(preferredLanguages: ["zh-Hans"]), "en")
    }

    @MainActor func testLanguageSelectionPersistsAndDoesNotChangeStoredCategoryCodes() throws {
        let defaults = AppLocalization.defaults
        let old = defaults.string(forKey: AppLocalization.preferenceKey)
        defer {
            if let old { defaults.set(old, forKey: AppLocalization.preferenceKey) }
            else { defaults.removeObject(forKey: AppLocalization.preferenceKey) }
        }
        let item = PlanItem(title: "我的自定义备注", detail: "原文 English", category: .notes)
        let original = try JSONEncoder().encode(item)
        let language = AppLanguageStore()
        language.select(.english)
        XCTAssertEqual(AppLanguageStore().selection, .english)
        XCTAssertEqual(AppLocalization.text("Travel Journal"), "Travel Journal")
        XCTAssertEqual(AppLocalization.text("保存"), "Save")
        XCTAssertEqual(PlanCategory.notes.localizedTitle, "Notes")
        XCTAssertEqual(PlanCategory.notes.rawValue, "备忘")
        XCTAssertEqual(AppLocalization.format("第 %lld 天 · %@", 3, "Kyoto"), "Day 3 · Kyoto")
        XCTAssertEqual(try JSONDecoder().decode(PlanItem.self, from: original), item)

        language.select(.chinese)
        XCTAssertEqual(AppLocalization.text("Travel Journal"), "旅游手账")
        XCTAssertEqual(PlanCategory.notes.localizedTitle, "备忘")
        XCTAssertEqual(AppLanguageStore().selection, .chinese)
        XCTAssertEqual(try JSONDecoder().decode(PlanItem.self, from: original).title, "我的自定义备注")
    }
}
