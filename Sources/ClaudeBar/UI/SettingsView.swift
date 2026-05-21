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

            Section("Auto Allow") {
                Toggle(isOn: Binding(
                    get: { state.autoAllowEnabled },
                    set: { state.setAutoAllowEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Auto Allow")
                        Text("Automatically allow read-only tools with no side effects")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if state.autoAllowEnabled {
                    ForEach(state.autoAllowRules) { rule in
                        HStack {
                            Toggle(isOn: Binding(
                                get: { rule.isEnabled },
                                set: { _ in state.toggleAutoAllowRule(id: rule.id) }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rule.toolName).font(.body)
                                    if let p = rule.commandPattern, !p.isEmpty {
                                        Text(p)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    }
                                }
                            }
                            Spacer()
                            Button {
                                state.removeAutoAllowRule(id: rule.id)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        showAddRuleSheet = true
                    } label: {
                        Label("Add rule", systemImage: "plus.circle")
                    }
                    .sheet(isPresented: $showAddRuleSheet) {
                        AddAutoAllowRuleSheet(isPresented: $showAddRuleSheet)
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

    @State private var showAddRuleSheet = false
}

private struct AddAutoAllowRuleSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject private var state = AppState.shared
    @State private var toolName = ""
    @State private var commandPattern = ""
    @FocusState private var toolNameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("Add Rule")
                .font(.headline)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Form {
                Section {
                    TextField("Tool name (e.g. Bash, Read)", text: $toolName)
                        .focused($toolNameFocused)
                    TextField("Command pattern (optional, regex)", text: $commandPattern)
                        .font(.system(.body, design: .monospaced))
                }
                .textFieldStyle(.roundedBorder)
            }
            .formStyle(.grouped)
            .frame(height: 140)

            Divider()

            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Button("Add") {
                    let pattern = commandPattern.trimmingCharacters(in: .whitespacesAndNewlines)
                    state.addAutoAllowRule(
                        toolName: toolName,
                        commandPattern: pattern.isEmpty ? nil : pattern
                    )
                    isPresented = false
                }
                .keyboardShortcut(.return)
                .disabled(toolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: 360)
        .onAppear { toolNameFocused = true }
    }
}
