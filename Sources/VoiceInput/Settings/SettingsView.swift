import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var permissionManager: PermissionManager
    @ObservedObject var hotkeyManager: HotkeyManager
    @ObservedObject var dictationCoordinator: DictationCoordinator

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
            }

            Section("Debug / Diagnostics") {
                diagnosticsRow(
                    "Input Monitoring",
                    permissionManager.hasInputMonitoringPermission ? "Granted" : "Missing"
                )
                diagnosticsRow(
                    "Accessibility",
                    permissionManager.hasAccessibilityPermission ? "Granted" : "Missing"
                )
                diagnosticsRow(
                    "Event Tap",
                    hotkeyManager.eventTapStatus.diagnosticText
                )
                diagnosticsRow(
                    "Shortcut",
                    hotkeyManager.shortcut?.displayName ?? "Not set"
                )
                diagnosticsRow(
                    "Bound key down",
                    hotkeyManager.boundKeyIsDown ? "true" : "false"
                )
                diagnosticsRow(
                    "Dictation state",
                    String(describing: dictationCoordinator.state)
                )
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .frame(minWidth: 480, minHeight: 620)
        .onAppear {
            permissionManager.beginSettingsMonitoring()
        }
        .onDisappear {
            permissionManager.endSettingsMonitoring()
        }
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

    private func diagnosticsRow(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}
