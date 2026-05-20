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

            Section("Approval Popup") {
                Toggle(isOn: Binding(
                    get: { state.autoOpenAfterApproval },
                    set: { state.setAutoOpenAfterApproval($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-open next approval")
                        Text("If a new approval arrives within this duration after the last one, open the window automatically (expanded)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if state.autoOpenAfterApproval {
                    LabeledContent("Grace period") {
                        HStack(spacing: 8) {
                            Stepper(
                                value: Binding(
                                    get: { state.autoOpenDuration },
                                    set: { state.setAutoOpenDuration($0) }
                                ),
                                in: 1...30,
                                step: 1
                            ) {
                                EmptyView()
                            }
                            Text("\(Int(state.autoOpenDuration))s")
                                .monospacedDigit()
                                .frame(minWidth: 28, alignment: .trailing)
                        }
                    }
                }
            }

            Section("Activity") {
                LabeledContent("Recent events") {
                    Text("\(state.recentActivity.count)")
                        .foregroundStyle(.secondary)
                }
                Button("Clear activity") {
                    state.clearActivity()
                }
                .foregroundStyle(.secondary)
                Button("View Log...") {
                    MainWindowState.shared.selectedTab = .log
                }
            }

            Section {
                Button("Disconnect") {
                    try? ClaudeSettingsManager.uninstall()
                    state.markSetupComplete()
                }
                .foregroundStyle(.red)

                Button("Quit ClaudeBar") {
                    NSApplication.shared.terminate(nil)
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
    }
}
