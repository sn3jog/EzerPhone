import Foundation
import SwiftUI
import Combine

/// The app's look, switchable at runtime from Settings. `.ink` is the hand-drawn
/// sepia-on-parchment design; the classic choices use plain iOS colours and shapes.
final class AppTheme: ObservableObject {
    static let shared = AppTheme()

    enum Choice: String, CaseIterable {
        case ink, classicLight, classicDark, classicSystem

        var title: String {
            switch self {
            case .ink: return "Нарисованное"
            case .classicLight: return "Классическое светлое"
            case .classicDark: return "Классическое тёмное"
            case .classicSystem: return "Классическое, как в системе"
            }
        }

        /// `nil` follows the system.
        var colorScheme: ColorScheme? {
            switch self {
            case .ink, .classicLight: return .light
            case .classicDark: return .dark
            case .classicSystem: return nil
            }
        }
    }

    private static let key = "app.theme"

    @Published var choice: Choice {
        didSet { UserDefaults.standard.set(choice.rawValue, forKey: Self.key) }
    }

    var isClassic: Bool { choice != .ink }

    private init() {
        choice = Choice(rawValue: UserDefaults.standard.string(forKey: Self.key) ?? "") ?? .ink
    }
}
