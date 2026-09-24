import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Recording mode") {
                Picker("Mode", selection: $settings.hotkeyMode) {
                    ForEach(HotkeyMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                Text(settings.hotkeyMode.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Language") {
                Picker("Language", selection: $settings.language) {
                    ForEach(AppSettings.Language.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .frame(maxWidth: 220)
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .frame(minWidth: 400, minHeight: 300)
    }
}
