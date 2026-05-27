import SwiftUI
import IOKit.hid

struct SettingsView: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var correctionService = VoiceCorrectionService.shared
    @State private var inputMonitoringAccess: IOHIDAccessType = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
    @State private var accessibilityTrusted: Bool = AXIsProcessTrusted()
    @State private var showFillerSheet = false
    @State private var showCorrectionsSheet = false
    @State private var showVocabularySheet = false

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
                } else {
                    Text("Not connected. Use the menu to run setup.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Keyboard Shortcuts") {
                LabeledContent("Open ClaudeBar") {
                    Picker("", selection: Binding(
                        get: { state.commandPaletteShortcut },
                        set: { state.setCommandPaletteShortcut($0) }
                    )) {
                        ForEach(CommandPaletteShortcut.allCases, id: \.self) { s in
                            Text(s.displayName).tag(s)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                if state.commandPaletteShortcut.regularKeyCode != nil {
                    LabeledContent {
                        if inputMonitoringAccess == kIOHIDAccessTypeGranted {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Granted")
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 11))
                            }
                        } else {
                            Button("Grant Access") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                                NSWorkspace.shared.selectFile("/Applications/ClaudeBar.app", inFileViewerRootedAtPath: "/Applications")
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Input Monitoring Required")
                            Text("Click \"Grant Access\" — then drag ClaudeBar from the Finder window into the list.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
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
                    VStack(spacing: 0) {
                        HStack {
                            Text("Rules")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(editingRules ? "Done" : "Edit") {
                                withAnimation(.easeInOut(duration: 0.18)) { editingRules.toggle() }
                            }
                            .foregroundStyle(editingRules ? Color.accentColor : .secondary)
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                        Divider().padding(.leading, 12)

                        ForEach(state.autoAllowRules) { rule in
                            HStack(spacing: 10) {
                                if editingRules {
                                    Button {
                                        state.removeAutoAllowRule(id: rule.id)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                    .transition(.move(edge: .leading).combined(with: .opacity))
                                }
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
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { rule.isEnabled },
                                    set: { _ in state.toggleAutoAllowRule(id: rule.id) }
                                ))
                                .labelsHidden()
                                .toggleStyle(.switch)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .animation(.easeInOut(duration: 0.18), value: editingRules)

                            Divider().padding(.leading, 12)
                        }

                        Button {
                            showAddRuleSheet = true
                        } label: {
                            Label("Add rule", systemImage: "plus.circle")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .sheet(isPresented: $showAddRuleSheet) {
                            AddAutoAllowRuleSheet(isPresented: $showAddRuleSheet)
                        }
                    }
                    .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                }
            }

            Section("Danger Patterns") {
                Text("Bash commands matching these patterns show a danger warning.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(state.dangerPatterns, id: \.self) { pattern in
                    HStack(spacing: 10) {
                        if editingPatterns {
                            Button {
                                state.removeDangerPattern(pattern)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                        Text(pattern.replacingOccurrences(of: #"\b"#, with: ""))
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                    .animation(.easeInOut(duration: 0.18), value: editingPatterns)
                }

                HStack(spacing: 12) {
                    AddDangerPatternRow()
                    Spacer()
                    Button(editingPatterns ? "Done" : "Edit") {
                        withAnimation(.easeInOut(duration: 0.18)) { editingPatterns.toggle() }
                    }
                    .foregroundStyle(editingPatterns ? Color.accentColor : .secondary)
                    .font(.system(size: 12))
                }
            }

            Section("Voice Input") {
                Toggle(isOn: Binding(
                    get: { state.voiceInputEnabled },
                    set: { state.setVoiceInputEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable voice input")
                        Text("PTTキーを長押しで録音 → Whisper で文字起こし → 任意のアプリにペースト")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if state.voiceInputEnabled {
                    LabeledContent("Accessibility") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(accessibilityTrusted ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(accessibilityTrusted ? "Granted" : "Required for paste")
                                .foregroundStyle(accessibilityTrusted ? Color.primary : Color.orange)
                            if !accessibilityTrusted {
                                Button("Allow…") { requestAccessibilityPermission() }
                                    .font(.caption)
                            }
                        }
                    }
                    .onAppear { accessibilityTrusted = AXIsProcessTrusted() }
                    .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
                        accessibilityTrusted = AXIsProcessTrusted()
                    }

                    LabeledContent("Trigger key") {
                        Picker("", selection: Binding(
                            get: { VoiceTriggerKey(rawValue: state.voiceTriggerKeyRaw) ?? .rightCommand },
                            set: { state.setVoiceTriggerKey($0) }
                        )) {
                            ForEach(VoiceTriggerKey.allCases, id: \.self) { key in
                                Text(key.displayName).tag(key)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    LabeledContent("Whisper model") {
                        WhisperModelPicker()
                    }

                    Toggle(isOn: Binding(
                        get: { state.fillerRemovalEnabled },
                        set: { state.setFillerRemovalEnabled($0) }
                    )) {
                        Text("フィラー除去")
                    }
                    if state.fillerRemovalEnabled {
                        LabeledContent("フィラー語") {
                            Button("編集…") { showFillerSheet = true }
                                .font(.caption)
                        }
                        .sheet(isPresented: $showFillerSheet) { FillerWordsSheet() }
                    }

                    Toggle(isOn: Binding(
                        get: { state.correctionEnabled },
                        set: { state.setCorrectionEnabled($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("学習機能")
                            Text("確認パネルでの編集を記憶し次回の文字起こしに自動適用")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if state.correctionEnabled {
                        LabeledContent("学習データ") {
                            HStack(spacing: 8) {
                                Text("\(correctionService.corrections.count) 件")
                                    .foregroundStyle(.secondary)
                                if !correctionService.corrections.isEmpty {
                                    Button("管理…") { showCorrectionsSheet = true }
                                        .font(.caption)
                                }
                            }
                        }
                        .sheet(isPresented: $showCorrectionsSheet) { CorrectionsSheet() }

                        LabeledContent("カスタム語彙") {
                            HStack(spacing: 8) {
                                Text(state.voiceVocabulary.isEmpty ? "なし" : "\(state.voiceVocabulary.count) 語")
                                    .foregroundStyle(.secondary)
                                Button("編集…") { showVocabularySheet = true }
                                    .font(.caption)
                            }
                        }
                        .sheet(isPresented: $showVocabularySheet) { VocabularySheet() }
                    }
                }
            }

            Section("Activity") {
                LabeledContent("Recent events") {
                    HStack(spacing: 8) {
                        Text("\(state.recentActivity.count)")
                            .foregroundStyle(.secondary)
                        Button("Clear") {
                            state.clearActivity()
                        }
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                        Button("View Log") {
                            MainWindowState.shared.selectedTab = .log
                        }
                        .font(.system(size: 11))
                    }
                }
            }

            Section("Danger Zone") {
                dangerRow(title: "Disconnect",
                          description: "Claude Code hooks を削除し、ClaudeBar との連携を解除します",
                          buttonLabel: "Disconnect") {
                    try? ClaudeSettingsManager.uninstall()
                    state.markSetupComplete()
                }
                dangerRow(title: "Quit ClaudeBar",
                          description: "アプリを終了します。メニューバーから再起動できます",
                          buttonLabel: "Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            inputMonitoringAccess = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        }
    }

    @State private var showAddRuleSheet = false
    @State private var editingRules = false
    @State private var editingPatterns = false

    private func dangerRow(title: String, description: String, buttonLabel: String, action: @escaping () -> Void) -> some View {
        LabeledContent {
            Button(buttonLabel, action: action).foregroundStyle(.red)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct AddAutoAllowRuleSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject private var state = AppState.shared
    @State private var toolName = AutoAllowRule.bash
    @State private var commandPattern = ""
    @FocusState private var patternFocused: Bool

    private var patternRequired: Bool { toolName == AutoAllowRule.bash }
    private var isValid: Bool {
        patternRequired ? !commandPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : true
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Add Rule")
                .font(.headline)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Form {
                Section {
                    Picker("Tool", selection: $toolName) {
                        ForEach(AutoAllowRule.knownTools, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)

                    VStack(alignment: .leading, spacing: 4) {
                        TextField(
                            patternRequired ? "Pattern (regex, required)" : "Pattern (regex, optional)",
                            text: $commandPattern
                        )
                        .font(.system(.body, design: .monospaced))
                        .focused($patternFocused)
                        if toolName == AutoAllowRule.bash {
                            Text("e.g.  ^git diff   ^npm run dev:   ^defaults read")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .textFieldStyle(.roundedBorder)
            }
            .formStyle(.grouped)
            .frame(height: toolName == AutoAllowRule.bash ? 160 : 140)

            Divider()

            HStack(spacing: 12) {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.escape)

                Button("Add") {
                    let pattern = commandPattern.trimmingCharacters(in: .whitespacesAndNewlines)
                    state.addAutoAllowRule(toolName: toolName, commandPattern: pattern.isEmpty ? nil : pattern)
                    isPresented = false
                }
                .keyboardShortcut(.return)
                .disabled(!isValid)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: 360)
        .onAppear { patternFocused = true }
    }
}

private struct AddDangerPatternRow: View {
    @ObservedObject private var state = AppState.shared
    @State private var pattern = ""
    @State private var isEditing = false
    @FocusState private var focused: Bool

    var body: some View {
        if isEditing {
            HStack(spacing: 8) {
                TextField(#"e.g. \bdrop\b"#, text: $pattern)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit { commit() }
                Button("Add") { commit() }
                    .disabled(pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Cancel") { isEditing = false; pattern = "" }
                    .controlSize(.small)
            }
            .onAppear { focused = true }
        } else {
            Button {
                isEditing = true
            } label: {
                Label("Add pattern", systemImage: "plus.circle")
            }
        }
    }

    private func commit() {
        state.addDangerPattern(pattern)
        pattern = ""
        isEditing = false
    }
}

// MARK: - Whisper model picker + downloader

private struct WhisperModelPicker: View {
    @ObservedObject private var state = AppState.shared
    @State private var downloadingID: String? = nil
    @State private var downloadProgress: Double = 0
    @State private var downloadTask: URLSessionDownloadTask? = nil
    @State private var observation: NSKeyValueObservation? = nil

    private var whisperDir: URL { VoiceInputService.whisperDirectory }

    private struct ModelInfo: Identifiable {
        let id: String
        let name: String
        let size: String
        let filename: String
        var localURL: URL { VoiceInputService.whisperDirectory.appendingPathComponent(filename) }
        var isDownloaded: Bool { FileManager.default.fileExists(atPath: localURL.path) }
        var downloadURL: URL? { URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)") }
    }

    private static let models: [ModelInfo] = [
        ModelInfo(id: "tiny",   name: "Tiny",   size: "75 MB",  filename: "ggml-tiny.bin"),
        ModelInfo(id: "base",   name: "Base",   size: "142 MB", filename: "ggml-base.bin"),
        ModelInfo(id: "small",  name: "Small",  size: "466 MB", filename: "ggml-small.bin"),
        ModelInfo(id: "medium", name: "Medium", size: "1.5 GB", filename: "ggml-medium.bin"),
    ]

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            let downloaded = Self.models.filter { $0.isDownloaded }
            if downloaded.isEmpty {
                Text("モデル未設定")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                Picker("", selection: Binding(
                    get: { state.whisperModelPath },
                    set: { state.setWhisperModelPath($0) }
                )) {
                    Text("未選択").tag("")
                    ForEach(downloaded) { m in
                        Text("\(m.name) (\(m.size))").tag(m.localURL.path)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 200)
            }

            Menu("ダウンロード") {
                ForEach(Self.models) { m in
                    if m.isDownloaded {
                        Button("\(m.name) — 削除") { deleteModel(m) }
                    } else if downloadingID == m.id {
                        Button("\(m.name) (\(Int(downloadProgress * 100))%) — キャンセル") { cancelDownload() }
                    } else {
                        Button("\(m.name) (\(m.size))") { startDownload(m) }
                            .disabled(downloadingID != nil)
                    }
                }
            }
            .font(.system(size: 11))
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func startDownload(_ model: ModelInfo) {
        guard let url = model.downloadURL else { return }
        downloadingID = model.id
        downloadProgress = 0
        try? FileManager.default.createDirectory(at: whisperDir, withIntermediateDirectories: true)
        let task = URLSession.shared.downloadTask(with: url) { tmpURL, _, error in
            DispatchQueue.main.async {
                observation?.invalidate()
                observation = nil
                downloadingID = nil
                downloadProgress = 0
                downloadTask = nil
                guard let tmpURL, error == nil else { return }
                try? FileManager.default.moveItem(at: tmpURL, to: model.localURL)
                if state.whisperModelPath.isEmpty { state.setWhisperModelPath(model.localURL.path) }
            }
        }
        observation = task.progress.observe(\.fractionCompleted) { progress, _ in
            DispatchQueue.main.async { downloadProgress = progress.fractionCompleted }
        }
        downloadTask = task
        task.resume()
    }

    private func cancelDownload() {
        observation?.invalidate()
        observation = nil
        downloadTask?.cancel()
        downloadTask = nil
        downloadingID = nil
        downloadProgress = 0
    }

    private func deleteModel(_ model: ModelInfo) {
        try? FileManager.default.removeItem(at: model.localURL)
        if state.whisperModelPath == model.localURL.path { state.setWhisperModelPath("") }
    }
}

// MARK: - フィラー除去シート

private struct FillerWordsSheet: View {
    @ObservedObject private var state = AppState.shared
    @State private var newWord = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("フィラー語の編集")
                    .font(.headline)
                Spacer()
                Button("完了") { dismiss() }
            }
            .padding()

            Divider()

            ScrollView {
                FlowLayout(spacing: 8) {
                    ForEach(state.fillerWords, id: \.self) { word in
                        HStack(spacing: 4) {
                            Text(word)
                                .font(.system(size: 13))
                            Button {
                                state.setFillerWords(state.fillerWords.filter { $0 != word })
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.quaternary, in: Capsule())
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                TextField("単語を追加", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addWord() }
                Button("追加", action: addWord)
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 320)
    }

    private func addWord() {
        let word = newWord.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty, !state.fillerWords.contains(word) else { return }
        state.setFillerWords(state.fillerWords + [word])
        newWord = ""
    }
}

// MARK: - 簡易フロータグレイアウト

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - カスタム語彙シート

private struct VocabularySheet: View {
    @ObservedObject private var state = AppState.shared
    @State private var newWord = ""
    @State private var newReading = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("カスタム語彙")
                        .font(.headline)
                    Text("固有名詞・専門用語を登録して Whisper の認識精度を向上")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完了") { dismiss() }
            }
            .padding()

            Divider()

            if state.voiceVocabulary.isEmpty {
                Spacer()
                Text("語彙がありません")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List {
                    ForEach(state.voiceVocabulary) { entry in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.word)
                                    .font(.system(size: 13, weight: .medium))
                                if !entry.reading.isEmpty {
                                    Text(entry.reading)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(entry.promptToken)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Button {
                                state.setVoiceVocabulary(state.voiceVocabulary.filter { $0.id != entry.id })
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                TextField("単語", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 120)
                TextField("読み方（任意）", text: $newReading)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 120)
                    .foregroundStyle(.secondary)
                Button("追加", action: addEntry)
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 480, height: 380)
    }

    private func addEntry() {
        let word = newWord.trimmingCharacters(in: .whitespaces)
        let reading = newReading.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty,
              !state.voiceVocabulary.contains(where: { $0.word == word }) else { return }
        state.setVoiceVocabulary(state.voiceVocabulary + [VocabularyEntry(word: word, reading: reading)])
        newWord = ""
        newReading = ""
    }
}

// MARK: - 学習データ管理シート

private struct CorrectionsSheet: View {
    @ObservedObject private var service = VoiceCorrectionService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("学習データ (\(service.corrections.count) 件)")
                    .font(.headline)
                Spacer()
                Button("完了") { dismiss() }
            }
            .padding()

            Divider()

            if service.corrections.isEmpty {
                Spacer()
                Text("学習データはありません")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List {
                    ForEach(service.corrections, id: \.original) { c in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(c.original)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "arrow.right")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(c.corrected)
                                        .fontWeight(.medium)
                                }
                                .font(.system(size: 13))
                                Text("\(c.count) 回")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                service.delete(original: c.original)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .frame(width: 460, height: 400)
    }
}
