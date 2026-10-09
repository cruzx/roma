import Foundation
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case chinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    func resolvedIdentifier(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        guard self == .system else { return rawValue }
        return preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? "zh-Hans" : "en"
    }
}

/// Uses an explicit resource bundle for strings outside SwiftUI, including background errors.
/// The app and its share extension read the same language preference.
enum AppLocalization {
    static let preferenceKey = "roam.appLanguage"
    static var isTesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitesting") ||
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
    }
    static var defaults: UserDefaults {
        if isTesting { return UserDefaults(suiteName: "com.xiangchengjin.roam.language-tests")! }
        return UserDefaults(suiteName: "group.com.xiangchengjin.roam") ?? .standard
    }
    static var language: AppLanguage {
        AppLanguage(rawValue: defaults.string(forKey: preferenceKey) ?? "") ?? (isTesting ? .chinese : .system)
    }
    static var identifier: String { language.resolvedIdentifier() }
    static var locale: Locale { Locale(identifier: identifier) }
    static var isEnglish: Bool { identifier == "en" }

    private static let englishBundle = Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))
    private static let chineseBundle = Bundle.main.path(forResource: "zh-Hans", ofType: "lproj").flatMap(Bundle.init(path:))

    static func text(_ key: String) -> String {
        let bundle = isEnglish ? englishBundle : chineseBundle
        return (bundle ?? Bundle.main).localizedString(forKey: key, value: key, table: "Localizable")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }
}

@MainActor
final class AppLanguageStore: ObservableObject {
    @Published private(set) var selection: AppLanguage
    @Published private(set) var identifier: String
    @Published var isSettingsPresented = false
    private let defaults: UserDefaults
    var locale: Locale { Locale(identifier: identifier) }

    init(defaults: UserDefaults = AppLocalization.defaults) {
        self.defaults = defaults
        let arguments = ProcessInfo.processInfo.arguments
        if AppLocalization.isTesting {
            if arguments.contains("--reset") { defaults.removeObject(forKey: AppLocalization.preferenceKey) }
            if let index = arguments.firstIndex(of: "--app-language"), arguments.indices.contains(index + 1),
               let language = AppLanguage(rawValue: arguments[index + 1]) {
                defaults.set(language.rawValue, forKey: AppLocalization.preferenceKey)
            }
        }
        let language = AppLanguage(rawValue: defaults.string(forKey: AppLocalization.preferenceKey) ?? "") ??
            (AppLocalization.isTesting ? .chinese : .system)
        selection = language
        identifier = language.resolvedIdentifier()
    }

    func select(_ language: AppLanguage) {
        defaults.set(language.rawValue, forKey: AppLocalization.preferenceKey)
        selection = language
        identifier = language.resolvedIdentifier()
    }

    func refresh() {
        let language = AppLanguage(rawValue: defaults.string(forKey: AppLocalization.preferenceKey) ?? "") ?? selection
        if selection != language { selection = language }
        let resolved = language.resolvedIdentifier()
        if identifier != resolved { identifier = resolved }
    }
}
