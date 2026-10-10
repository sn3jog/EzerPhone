import Foundation
import SwiftUI
import Combine

/// The app's language, switchable at runtime from Settings. "System" follows the phone's
/// language list (English when neither Russian nor English is preferred).
final class AppLanguage: ObservableObject {
    static let shared = AppLanguage()

    enum Choice: String, CaseIterable {
        case system, ru, en, de, es, he, ar, lv, lt, et
        case zh = "zh-Hans"
        case ko, ja

        /// Each language is named in itself, so it can always be found.
        var nativeName: String {
            switch self {
            case .system: return ""
            case .ru: return "Русский"
            case .en: return "English"
            case .de: return "Deutsch"
            case .es: return "Español"
            case .he: return "עברית"
            case .ar: return "العربية"
            case .lv: return "Latviešu"
            case .lt: return "Lietuvių"
            case .et: return "Eesti"
            case .zh: return "简体中文"
            case .ko: return "한국어"
            case .ja: return "日本語"
            }
        }
    }

    private static let codes = ["en", "ru", "de", "es", "he", "ar", "lv", "lt", "et", "zh-Hans", "ko", "ja"]

    private static let key = "app.language"

    @Published var choice: Choice {
        didSet {
            UserDefaults.standard.set(choice.rawValue, forKey: Self.key)
            refresh()
        }
    }
    private(set) var bundle: Bundle = .main
    private(set) var locale: Locale = .current

    private init() {
        choice = Choice(rawValue: UserDefaults.standard.string(forKey: Self.key) ?? "") ?? .system
        refresh()
    }

    private var resolvedCode: String {
        switch choice {
        case .system: return Bundle.preferredLocalizations(from: Self.codes).first ?? "en"
        default: return choice.rawValue
        }
    }

    /// Hebrew and Arabic read right to left, so the interface mirrors.
    var layoutDirection: LayoutDirection {
        ["he", "ar"].contains(resolvedCode) ? .rightToLeft : .leftToRight
    }

    private func refresh() {
        let code = resolvedCode
        bundle = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        locale = Locale(identifier: code)
        objectWillChange.send()
    }
}
