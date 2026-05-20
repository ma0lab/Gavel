import SwiftUI

struct SettingsView: View {
    @ObservedObject private var state = AppState.shared
    @State private var showAddRuleSheet = false

    var body: some View {
        Form {
            Section("接続") {
                LabeledContent("ソケット") {
                    Text("~/Library/Application Support/ClaudeBar/hook.sock")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                LabeledContent("状態") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(state.isServerRunning ? Color.green : .gray)
                            .frame(width: 8, height: 8)
                        Text(state.isServerRunning ? "稼働中" : "停止中")
                    }
                }
                LabeledContent("フック設定") {
                    Text(ClaudeSettingsManager.isInstalled() ? "済" : "未設定")
                        .foregroundStyle(ClaudeSettingsManager.isInstalled() ? .green : .secondary)
                }
            }

            Section("Claude Code 連携") {
                if state.isSetupComplete {
                    Toggle(isOn: Binding(
                        get: { state.blockApprovals },
                        set: { state.setBlockApprovals($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("承認をインターセプト")
                            Text(state.blockApprovals
                                 ? "ポップアップで承認を制御。ターミナルの承認UIはバイパスされます。"
                                 : "ターミナルの承認UIが通常通り動作します。ClaudeBar は監視のみ。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("フックをアンインストール") {
                        try? ClaudeSettingsManager.uninstall()
                        state.markSetupComplete()
                    }
                    .foregroundStyle(.red)
                } else {
                    Text("未接続。メニューからセットアップを実行してください。")
                        .foregroundStyle(.secondary)
                }
            }

            Section("通知") {
                Toggle(isOn: Binding(
                    get: { state.enableNativeNotifications },
                    set: { state.setEnableNativeNotifications($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("macOS 通知")
                        Text("Claude がセッションを終了したときに通知（Stop / Notification フック）")
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
                        Text("Auto Allow を有効にする")
                        Text("副作用のない読み取り専用ツールを自動的に許可する")
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
                        Label("ルールを追加", systemImage: "plus.circle")
                    }
                    .sheet(isPresented: $showAddRuleSheet) {
                        AddAutoAllowRuleSheet(isPresented: $showAddRuleSheet)
                    }
                }
            }

            Section("アクティビティ") {
                LabeledContent("最近のイベント") {
                    Text("\(state.recentActivity.count)")
                        .foregroundStyle(.secondary)
                }
                Button("履歴をクリア") {
                    state.clearActivity()
                }
                .foregroundStyle(.secondary)
                Button("ログを表示...") {
                    MainWindowState.shared.selectedTab = .log
                }
            }

            Section {
                Button("切断") {
                    try? ClaudeSettingsManager.uninstall()
                    state.markSetupComplete()
                }
                .foregroundStyle(.red)

                Button("ClaudeBar を終了") {
                    NSApplication.shared.terminate(nil)
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AddAutoAllowRuleSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject private var state = AppState.shared
    @State private var toolName = ""
    @State private var commandPattern = ""
    @FocusState private var toolNameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("ルールを追加")
                .font(.headline)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Form {
                Section {
                    TextField("ツール名 (例: Bash, Read)", text: $toolName)
                        .focused($toolNameFocused)
                    TextField("コマンドパターン (任意, 正規表現)", text: $commandPattern)
                        .font(.system(.body, design: .monospaced))
                }
                .textFieldStyle(.roundedBorder)
            }
            .formStyle(.grouped)
            .frame(height: 140)

            Divider()

            HStack(spacing: 12) {
                Button("キャンセル") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Button("追加") {
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
