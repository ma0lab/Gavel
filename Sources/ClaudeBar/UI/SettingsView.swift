import SwiftUI

struct SettingsView: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        Form {
            Section("Connection") {
                LabeledContent("Socket") {
                    Text("~/Library/Application Support/ClaudeBar/hook.sock")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(state.isServerRunning ? Color.green : .gray)
                            .frame(width: 8, height: 8)
                        Text(state.isServerRunning ? "Running" : "Stopped")
                    }
                }
                LabeledContent("Hooks installed") {
                    Text(ClaudeSettingsManager.isInstalled() ? "Yes" : "No")
                        .foregroundStyle(ClaudeSettingsManager.isInstalled() ? .green : .secondary)
                }
            }

            Section("Claude Code Integration") {
                if state.isSetupComplete {
                    Toggle(isOn: Binding(
                        get: { state.blockApprovals },
                        set: { state.setBlockApprovals($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Intercept approvals")
                            Text(state.blockApprovals
                                 ? "Popup controls approval. Terminal approval UI is bypassed."
                                 : "Terminal approval UI works normally. ClaudeBar monitors only.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("Uninstall hooks") {
                        try? ClaudeSettingsManager.uninstall()
                        state.markSetupComplete()
                    }
                    .foregroundStyle(.red)
                } else {
                    Text("Not connected. Use the menu to run setup.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Notifications") {
                Toggle(isOn: Binding(
                    get: { state.enableNativeNotifications },
                    set: { state.setEnableNativeNotifications($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("macOS notifications")
                        Text("Notify when Claude finishes a session (Stop / Notification hook)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Activity") {
                LabeledContent("Recent events") {
                    Text("\(state.recentActivity.count)")
                        .foregroundStyle(.secondary)
                }
                Button("Clear activity") {
                    state.recentActivity.removeAll()
                }
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 380)
    }
}
