import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var permissionManager: PermissionManager
    @ObservedObject var hotkeyManager: HotkeyManager
    @ObservedObject var speechModelManager: SpeechModelManager

    var body: some View {
        Form {
            Section("Hotkey") {
                LabeledContent("Shortcut") {
                    HotkeyRecorderView(
                        shortcut: $settings.hotkeyShortcut,
                        hotkeyManager: hotkeyManager
                    )
                    .frame(width: 190, height: 28)
                }

                Text("Click the field and press a key or shortcut. Escape cancels; Delete clears.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

            Section("Permissions") {
                Text("VoiceInput needs permission to listen for and suppress the global shortcut.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                permissionRow(
                    title: "Input Monitoring",
                    granted: permissionManager.hasInputMonitoringPermission,
                    requestAction: { permissionManager.requestInputMonitoring() },
                    openSettingsAction: { permissionManager.openInputMonitoringSettings() }
                )

                Divider()

                permissionRow(
                    title: "Accessibility",
                    granted: permissionManager.hasAccessibilityPermission,
                    requestAction: { permissionManager.requestAccessibility() },
                    openSettingsAction: { permissionManager.openAccessibilitySettings() }
                )

                Divider()

                permissionRow(
                    title: "Microphone",
                    granted: permissionManager.hasMicrophonePermission,
                    requestAction: { permissionManager.requestMicrophone() },
                    openSettingsAction: { permissionManager.openMicrophoneSettings() }
                )
            }

            Section("Speech Recognition") {
                Toggle("Use API Transcription", isOn: apiModeBinding)

                if settings.speechProcessingMode == .local {
                    statusRow("Mode", "Local — Parakeet TDT 0.6B v3")
                    statusRow("Model", speechModelManager.status.displayText)
                    Text("Downloaded once by FluidAudio and then loaded from its local cache.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    statusRow("Mode", "API")
                    Text("API provider is not configured.")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.orange)
                    Text("No audio will be sent anywhere until a provider is configured.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        }
        .formStyle(.grouped)
        .padding(8)
        .frame(minWidth: 500, minHeight: 620)
        .onAppear {
            permissionManager.beginSettingsMonitoring()
        }
        .onDisappear {
            permissionManager.endSettingsMonitoring()
        }
    }

    private var apiModeBinding: Binding<Bool> {
        Binding(
            get: { settings.speechProcessingMode == .api },
            set: { settings.speechProcessingMode = $0 ? .api : .local }
        )
    }

    private func permissionRow(
        title: String,
        granted: Bool,
        requestAction: @escaping () -> Void,
        openSettingsAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.body.weight(.medium))
                Spacer()
                Label(
                    granted ? "Granted" : "Required",
                    systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(granted ? .green : .orange)
            }

            if !granted {
                HStack {
                    Button("Request \(title)", action: requestAction)
                    Button("Open \(title) Settings", action: openSettingsAction)
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    private func statusRow(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}
