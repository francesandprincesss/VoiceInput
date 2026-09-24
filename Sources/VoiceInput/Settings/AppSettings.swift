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
        static let hotkeyShortcut = "hotkeyShortcut"
        static let speechProcessingMode = "speechProcessingMode"
    }

    private struct StoredShortcut: Codable {
        let shortcut: HotkeyShortcut?
    }

    @Published var hotkeyMode: HotkeyMode {
        didSet { defaults.set(hotkeyMode.rawValue, forKey: Key.hotkeyMode) }
    }

    @Published var language: Language {
        didSet { defaults.set(language.rawValue, forKey: Key.language) }
    }

    @Published var hotkeyShortcut: HotkeyShortcut? {
        didSet { persistHotkeyShortcut() }
    }

    @Published var speechProcessingMode: SpeechProcessingMode {
        didSet { defaults.set(speechProcessingMode.rawValue, forKey: Key.speechProcessingMode) }
    }

    private let defaults: UserDefaults

    var speechRecognitionLanguage: SpeechRecognitionLanguage {
        switch language {
        case .automatic: .automatic
        case .russian: .russian
        case .english: .english
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hotkeyMode = HotkeyMode(
            rawValue: defaults.string(forKey: Key.hotkeyMode) ?? ""
        ) ?? .toggle
        language = Language(
            rawValue: defaults.string(forKey: Key.language) ?? ""
        ) ?? .automatic
        speechProcessingMode = SpeechProcessingMode(
            rawValue: defaults.string(forKey: Key.speechProcessingMode) ?? ""
        ) ?? .local
        if let data = defaults.data(forKey: Key.hotkeyShortcut),
           let stored = try? JSONDecoder().decode(StoredShortcut.self, from: data) {
            hotkeyShortcut = stored.shortcut
        } else {
            hotkeyShortcut = .defaultShortcut
        }
    }

    private func persistHotkeyShortcut() {
        let stored = StoredShortcut(shortcut: hotkeyShortcut)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: Key.hotkeyShortcut)
    }
}
