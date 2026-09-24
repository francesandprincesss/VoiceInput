import Foundation

@MainActor
final class AppSettings: ObservableObject {
    enum Language: String, CaseIterable, Identifiable, Sendable {
        case automatic
        case russian
        case english

        var id: Self { self }

        var title: String {
            switch self {
            case .automatic: "Auto"
            case .russian: "Russian"
            case .english: "English"
            }
        }
    }

    private enum Key {
        static let hotkeyMode = "hotkeyMode"
        static let language = "language"
    }

    @Published var hotkeyMode: HotkeyMode {
        didSet { defaults.set(hotkeyMode.rawValue, forKey: Key.hotkeyMode) }
    }

    @Published var language: Language {
        didSet { defaults.set(language.rawValue, forKey: Key.language) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hotkeyMode = HotkeyMode(
            rawValue: defaults.string(forKey: Key.hotkeyMode) ?? ""
        ) ?? .toggle
        language = Language(
            rawValue: defaults.string(forKey: Key.language) ?? ""
        ) ?? .automatic
    }
}
