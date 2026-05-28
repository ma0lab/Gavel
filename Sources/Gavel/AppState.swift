import Foundation
import SwiftUI
import UserNotifications

enum IntentState: Sendable {
    case loading
    case found(String)
    case none
}

struct PendingApproval: Sendable {
    let request: HookRequest
    let isBlocking: Bool
    let isEnvWarning: Bool
    let respond: @Sendable (HookResponse) -> Void
    let allowAll: (@Sendable () -> Void)?  // non-blocking only: "2. Yes, allow all"
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var approvalQueue: [PendingApproval] = []
    @Published var pendingCompletions: [CompletionItem] = []
    @Published private(set) var recentActivity: [ActivityItem] = []
    @Published private(set) var todaySummary = TodaySummary(allow: 0, autoAllow: 0, deny: 0, sessions: 0)
    private var todaySessionIds: Set<String> = []
    private var todayStart: Date = Calendar.current.startOfDay(for: Date())
    @Published var activeSessions: [SessionInfo] = []  // hook-based: used by LogView green dot
    @Published var scannedSessions: [SessionInfo] = [] // process-scan: used by dashboard
    @Published var isServerRunning = false
    @Published var enableNativeNotifications: Bool
    @Published var intentState: IntentState = .none
    @Published var autoAllowEnabled: Bool
    @Published var autoAllowRules: [AutoAllowRule]
    @Published var dangerPatterns: [String]
    private var dangerRegexes: [NSRegularExpression] = []
    private var autoAllowRegexes: [UUID: NSRegularExpression] = [:]
    @Published var pendingAskQuestion: HookRequest? = nil
    // Sessions shown in the dashboard: process-scan as primary, hook-only sessions as supplement
    var displayedSessions: [SessionInfo] {
        let scannedCwds = Set(scannedSessions.compactMap { $0.workingDirectory })
        let hookOnly = activeSessions.filter { !scannedCwds.contains($0.workingDirectory ?? "") }
        return scannedSessions + hookOnly
    }
    @Published var popoverOpenCount = 0
    @Published var serverError: String?
    @Published var isSetupComplete: Bool
    @Published var blockApprovals: Bool

    var pendingApproval: PendingApproval? { approvalQueue.first }

    @Published var commandPaletteShortcut: CommandPaletteShortcut
    @Published var voiceInputEnabled: Bool
    @Published var whisperModelPath: String
    @Published var voiceTriggerKeyRaw: String
    @Published var fillerRemovalEnabled: Bool
    @Published var fillerWords: [String]
    @Published var correctionEnabled: Bool
    @Published var voiceVocabulary: [VocabularyEntry]
    @Published private(set) var voiceHistory: [String] = []

    private enum Keys {
        static let isSetupComplete = "isSetupComplete"
        static let blockApprovals = "blockApprovals"
        static let enableNativeNotifications = "enableNativeNotifications"
        static let autoAllowEnabled = "autoAllowEnabled"
        static let autoAllowRules = "autoAllowRules"
        static let dangerPatterns = "dangerPatterns"
        static let commandPaletteShortcut = "commandPaletteShortcut"
        static let voiceInputEnabled = "voiceInputEnabled"
        static let whisperModelPath = "whisperModelPath"
        static let voiceTriggerKeyRaw = "voiceTriggerKeyRaw"
        static let fillerRemovalEnabled = "fillerRemovalEnabled"
        static let fillerWords = "fillerWords"
        static let correctionEnabled = "correctionEnabled"
        static let voiceVocabulary = "voiceVocabulary"
    }

    private init() {
        self.isSetupComplete = UserDefaults.standard.bool(forKey: Keys.isSetupComplete)
        self.blockApprovals = UserDefaults.standard.bool(forKey: Keys.blockApprovals)
        self.enableNativeNotifications = UserDefaults.standard.bool(forKey: Keys.enableNativeNotifications)
        self.autoAllowEnabled = UserDefaults.standard.bool(forKey: Keys.autoAllowEnabled)
        if let data = UserDefaults.standard.data(forKey: Keys.autoAllowRules),
           let rules = try? JSONDecoder().decode([AutoAllowRule].self, from: data) {
            self.autoAllowRules = AutoAllowRule.migrated(rules)
        } else {
            self.autoAllowRules = AutoAllowRule.defaults
        }
        if let saved = UserDefaults.standard.stringArray(forKey: Keys.dangerPatterns) {
            self.dangerPatterns = saved
        } else {
            self.dangerPatterns = AppState.defaultDangerPatterns
        }
        let shortcutRaw = UserDefaults.standard.string(forKey: Keys.commandPaletteShortcut) ?? ""
        self.commandPaletteShortcut = CommandPaletteShortcut(rawValue: shortcutRaw) ?? .default
        self.voiceInputEnabled = UserDefaults.standard.bool(forKey: Keys.voiceInputEnabled)
        self.whisperModelPath = UserDefaults.standard.string(forKey: Keys.whisperModelPath) ?? ""
        self.voiceTriggerKeyRaw = UserDefaults.standard.string(forKey: Keys.voiceTriggerKeyRaw) ?? VoiceTriggerKey.rightCommand.rawValue
        self.fillerRemovalEnabled = UserDefaults.standard.object(forKey: Keys.fillerRemovalEnabled) as? Bool ?? true
        if let data = UserDefaults.standard.data(forKey: Keys.fillerWords),
           let words = try? JSONDecoder().decode([String].self, from: data) {
            self.fillerWords = words
        } else {
            self.fillerWords = AppState.defaultFillerWords
        }
        self.correctionEnabled = UserDefaults.standard.object(forKey: Keys.correctionEnabled) as? Bool ?? true
        if let data = UserDefaults.standard.data(forKey: Keys.voiceVocabulary),
           let entries = try? JSONDecoder().decode([VocabularyEntry].self, from: data) {
            self.voiceVocabulary = entries
        } else {
            self.voiceVocabulary = []
        }
        self.recentActivity = ActivityStore.shared.fetchRecent()
        rebuildDangerRegexes()
        rebuildAutoAllowRegexes()
        Task { @MainActor [self] in
            let todayItems = await ActivityStore.shared.fetchToday()
            self.todaySessionIds = Set(todayItems.compactMap { $0.sessionId })
            self.todaySummary = ActivityStats.todaySummary(items: todayItems)
        }
    }

    func presentApproval(request: HookRequest, server: HookServer, isEnvWarning: Bool = false) {
        ClLog.approval.info("present: tool=\(request.toolName ?? "?") envWarn=\(isEnvWarning) queueLen=\(approvalQueue.count + 1)")
        registerSession(from: request)
        clearCompletion(sessionId: request.sessionId, workingDirectory: request.workingDirectory)
        let approval = PendingApproval(request: request, isBlocking: true, isEnvWarning: isEnvWarning, respond: { response in
            Task { await server.resolve(requestId: response.requestId, with: response) }
        }, allowAll: nil)
        approvalQueue.append(approval)
        loadIntentIfNeeded(from: request)
        ApprovalWindowController.shared.show()
    }

    func trackToolUse(from request: HookRequest) {
        registerSession(from: request)
        clearCompletion(sessionId: request.sessionId, workingDirectory: request.workingDirectory)
        approvalQueue.removeAll { !$0.isBlocking }
        let approval = PendingApproval(
            request: request,
            isBlocking: false,
            isEnvWarning: false,
            respond: { _ in },
            allowAll: { }
        )
        approvalQueue.append(approval)
        loadIntentIfNeeded(from: request)
        if approvalQueue.count == 1 {
            ApprovalWindowController.shared.show()
        }
    }

    func allow() {
        guard !approvalQueue.isEmpty else { return }
        let approval = approvalQueue.removeFirst()
        ClLog.approval.info("allow: tool=\(approval.request.toolName ?? "?")")
        let response = HookResponse(decision: .allow, reason: nil, requestId: approval.request.requestId)
        addActivity(from: approval.request, decision: .allow)
        approval.respond(response)
        advanceQueue()
    }

    func allowAll() {
        guard !approvalQueue.isEmpty else { return }
        let approval = approvalQueue.removeFirst()
        ClLog.approval.info("allowAll: tool=\(approval.request.toolName ?? "?")")
        addActivity(from: approval.request, decision: .allow)
        approval.allowAll?()
        advanceQueue()
    }

    func deny(reason: String) {
        guard !approvalQueue.isEmpty else { return }
        let approval = approvalQueue.removeFirst()
        ClLog.approval.info("deny: tool=\(approval.request.toolName ?? "?") reason='\(reason)'")
        let text = reason.isEmpty ? "Denied via Gavel" : reason
        let response = HookResponse(decision: .deny, reason: text, requestId: approval.request.requestId)
        addActivity(from: approval.request, decision: .deny)
        approval.respond(response)
        advanceQueue()
    }

    func appendVoiceHistory(_ text: String) {
        var h = voiceHistory
        h.removeAll { $0 == text }
        h.insert(text, at: 0)
        if h.count > 10 { h = Array(h.prefix(10)) }
        voiceHistory = h
    }

    func addNotification(from request: HookRequest) {
        registerSession(from: request)
        addActivity(ActivityItem(
            sessionId: request.sessionId,
            toolName: "Notification",
            decision: .allow,
            preview: request.message ?? "",
            workingDirectory: request.workingDirectory
        ))
        if let msg = request.message, !msg.isEmpty {
            let item = CompletionItem(sessionId: request.sessionId, workingDirectory: request.workingDirectory, message: msg)
            addCompletion(item)
        }
    }

    func handleStop(from request: HookRequest) {
        if let id = request.sessionId {
            activeSessions.removeAll { $0.id == id }
        }
        addActivity(ActivityItem(
            sessionId: request.sessionId,
            toolName: "Stop",
            decision: .allow,
            preview: "Session \(request.sessionId?.prefix(8) ?? "—") finished",
            workingDirectory: request.workingDirectory
        ))
        let item = CompletionItem(sessionId: request.sessionId, workingDirectory: request.workingDirectory, message: nil)
        addCompletion(item)
    }

    func clearCompletion(for session: SessionInfo) {
        clearCompletion(sessionId: session.id, workingDirectory: session.workingDirectory)
    }

    func dismissSession(_ session: SessionInfo) {
        activeSessions.removeAll { $0.id == session.id }
        scannedSessions.removeAll { $0.id == session.id }
        clearCompletion(sessionId: session.id, workingDirectory: session.workingDirectory)
    }

    func clearActivity() {
        recentActivity.removeAll()
        ActivityStore.shared.clearAll()
        todaySessionIds.removeAll()
        todaySummary = TodaySummary(allow: 0, autoAllow: 0, deny: 0, sessions: 0)
    }

    func setEnableNativeNotifications(_ value: Bool) {
        enableNativeNotifications = value
        UserDefaults.standard.set(value, forKey: Keys.enableNativeNotifications)
        if value { requestNotificationPermission() }
    }

    private func addCompletion(_ item: CompletionItem) {
        pendingCompletions.removeAll { $0.matches(sessionId: item.sessionId, workingDirectory: item.workingDirectory) }
        pendingCompletions.append(item)
        if enableNativeNotifications { sendNativeNotification(for: item) }
    }

    private func clearCompletion(sessionId: String?, workingDirectory: String?) {
        pendingCompletions.removeAll { $0.matches(sessionId: sessionId, workingDirectory: workingDirectory) }
    }

    private func sendNativeNotification(for item: CompletionItem) {
        let content = UNMutableNotificationContent()
        let project = item.workingDirectory?.projectName ?? "Claude"
        content.title = "\(project) — Done"
        content.body = item.message ?? "Claude finished. Check the terminal."
        content.sound = .default
        let req = UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func advanceQueue() {
        if approvalQueue.isEmpty {
            ApprovalWindowController.shared.dismiss()
        } else {
            ApprovalWindowController.shared.show()
        }
    }

    func loadIntentIfNeeded(from request: HookRequest) {
        if let ctx = request.context, !ctx.isEmpty {
            intentState = .found(ctx)
            return
        }
        guard let path = request.transcriptPath else {
            intentState = .none
            return
        }
        intentState = .loading
        Task {
            let text = await TranscriptReader.extractLastIntent(from: path)
            intentState = text.map { .found($0) } ?? .none
        }
    }

    func setAutoAllowEnabled(_ value: Bool) {
        autoAllowEnabled = value
        UserDefaults.standard.set(value, forKey: Keys.autoAllowEnabled)
    }

    func addAutoAllowRule(toolName: String, commandPattern: String? = nil) {
        let name = toolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let pattern = commandPattern?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard !autoAllowRules.contains(where: { $0.toolName == name && $0.commandPattern == pattern }) else { return }
        autoAllowRules.append(AutoAllowRule(toolName: name, commandPattern: pattern))
        rebuildAutoAllowRegexes()
        saveAutoAllowRules()
    }

    func removeAutoAllowRule(id: UUID) {
        autoAllowRules.removeAll { $0.id == id }
        rebuildAutoAllowRegexes()
        saveAutoAllowRules()
    }

    func toggleAutoAllowRule(id: UUID) {
        guard let idx = autoAllowRules.firstIndex(where: { $0.id == id }) else { return }
        autoAllowRules[idx].isEnabled.toggle()
        saveAutoAllowRules()
    }

    func saveAutoAllowRules() {
        if let data = try? JSONEncoder().encode(autoAllowRules) {
            UserDefaults.standard.set(data, forKey: Keys.autoAllowRules)
        }
    }

    static let defaultDangerPatterns: [String] = [
        #"\brm\b"#, #"\bmv\b"#, #"\bdd\b"#, #"\bchmod\b"#,
        #"\bchown\b"#, #"\bsudo\b"#, #"\btruncate\b"#, #"\bshred\b"#,
    ]

    func isDangerous(_ request: HookRequest) -> Bool {
        guard request.toolName == AutoAllowRule.bash else { return false }
        return anyMatch(dangerRegexes, in: request.commandPreview)
    }

    private func anyMatch(_ regexes: [NSRegularExpression], in command: String) -> Bool {
        let range = NSRange(command.startIndex..., in: command)
        return regexes.contains { $0.firstMatch(in: command, range: range) != nil }
    }

    func addDangerPattern(_ pattern: String) {
        let p = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty, !dangerPatterns.contains(p) else { return }
        guard (try? NSRegularExpression(pattern: p)) != nil else { return }
        dangerPatterns.append(p)
        rebuildDangerRegexes()
        saveDangerPatterns()
    }

    func removeDangerPattern(_ pattern: String) {
        dangerPatterns.removeAll { $0 == pattern }
        rebuildDangerRegexes()
        saveDangerPatterns()
    }

    private func saveDangerPatterns() {
        UserDefaults.standard.set(dangerPatterns, forKey: Keys.dangerPatterns)
    }

    private func rebuildDangerRegexes() {
        dangerRegexes = dangerPatterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }

    private func rebuildAutoAllowRegexes() {
        autoAllowRegexes = autoAllowRules.reduce(into: [:]) { dict, rule in
            guard let p = rule.commandPattern, !p.isEmpty,
                  let regex = try? NSRegularExpression(pattern: p) else { return }
            dict[rule.id] = regex
        }
    }

    func matchesAutoAllowRule(_ request: HookRequest) -> Bool {
        guard autoAllowEnabled, let toolName = request.toolName else { return false }
        guard !needsEnvWarning(request) else { return false }
        let command = request.commandPreview
        return autoAllowRules.contains { rule in
            guard rule.isEnabled && rule.toolName == toolName else { return false }
            guard let p = rule.commandPattern, !p.isEmpty else { return true }
            guard let regex = autoAllowRegexes[rule.id] else { return false }
            return anyMatch([regex], in: command)
        }
    }

    func needsEnvWarning(_ request: HookRequest) -> Bool {
        guard request.toolName == "Read" else { return false }
        guard let input = request.toolInputRaw,
              let pathVal = input["file_path"],
              case .string(let path) = pathVal else { return false }
        return isEnvFilePath(path)
    }

    func logAutoAllow(_ request: HookRequest) {
        registerSession(from: request)
        addActivity(from: request, decision: .allow, isAutoAllowed: true)
    }

    func logAutoInterceptChange(enabled: Bool, reason: InterceptSwitchReason) {
        let preview = enabled
            ? "Intercept restored (\(reason.rawValue))"
            : "Intercept auto-disabled (\(reason.rawValue))"
        addActivity(ActivityItem(toolName: "Idle", decision: .allow, preview: preview))
    }

    private func registerSession(from request: HookRequest) {
        guard let id = request.sessionId else { return }
        if !activeSessions.contains(where: { $0.id == id }) {
            activeSessions.append(SessionInfo(id: id, workingDirectory: request.workingDirectory))
        }
    }

    func markSetupComplete() {
        isSetupComplete = true
        UserDefaults.standard.set(true, forKey: Keys.isSetupComplete)
    }

    func setBlockApprovals(_ value: Bool) {
        blockApprovals = value
        UserDefaults.standard.set(value, forKey: Keys.blockApprovals)
        if isSetupComplete {
            try? ClaudeSettingsManager.install(blockApprovals: value)
        }
    }

    func setCommandPaletteShortcut(_ value: CommandPaletteShortcut) {
        commandPaletteShortcut = value
        UserDefaults.standard.set(value.rawValue, forKey: Keys.commandPaletteShortcut)
        GlobalKeyMonitor.shared.stop()
        GlobalKeyMonitor.shared.shortcut = value
        GlobalKeyMonitor.shared.start()
    }

    func setVoiceInputEnabled(_ value: Bool) {
        voiceInputEnabled = value
        UserDefaults.standard.set(value, forKey: Keys.voiceInputEnabled)
        if value {
            VoiceInputCoordinator.shared.start()
        } else {
            VoiceInputCoordinator.shared.stop()
        }
    }

    func setWhisperModelPath(_ value: String) {
        whisperModelPath = value
        UserDefaults.standard.set(value, forKey: Keys.whisperModelPath)
        VoiceInputCoordinator.shared.syncSettings()
    }

    func setVoiceTriggerKey(_ key: VoiceTriggerKey) {
        voiceTriggerKeyRaw = key.rawValue
        UserDefaults.standard.set(key.rawValue, forKey: Keys.voiceTriggerKeyRaw)
        VoiceInputCoordinator.shared.syncSettings()
    }

    func setFillerRemovalEnabled(_ value: Bool) {
        fillerRemovalEnabled = value
        UserDefaults.standard.set(value, forKey: Keys.fillerRemovalEnabled)
        VoiceInputCoordinator.shared.syncSettings()
    }

    func setFillerWords(_ words: [String]) {
        fillerWords = words
        if let data = try? JSONEncoder().encode(words) {
            UserDefaults.standard.set(data, forKey: Keys.fillerWords)
        }
        VoiceInputCoordinator.shared.syncSettings()
    }

    func setCorrectionEnabled(_ value: Bool) {
        correctionEnabled = value
        UserDefaults.standard.set(value, forKey: Keys.correctionEnabled)
        VoiceInputCoordinator.shared.syncSettings()
    }

    func setVoiceVocabulary(_ entries: [VocabularyEntry]) {
        voiceVocabulary = entries
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Keys.voiceVocabulary)
        }
        VoiceInputCoordinator.shared.syncSettings()
    }

    static let defaultFillerWords = ["あー","あーあー","えー","えーと","えっと","うー","うーん","んー","まあ","そのー","なんか","なんかー"]

    private func addActivity(from request: HookRequest, decision: Decision, isAutoAllowed: Bool = false) {
        addActivity(ActivityItem(
            sessionId: request.sessionId,
            toolName: request.toolName ?? "Unknown",
            decision: decision,
            preview: request.commandPreview,
            workingDirectory: request.workingDirectory,
            isAutoAllowed: isAutoAllowed
        ))
    }

    private func addActivity(_ item: ActivityItem) {
        recentActivity.insert(item, at: 0)
        if recentActivity.count > 200 { recentActivity.removeLast() }
        ActivityStore.shared.insert(item)
        resetTodayIfNeeded()
        let allow     = todaySummary.allow     + (item.decision == .allow ? 1 : 0)
        let autoAllow = todaySummary.autoAllow + (item.isAutoAllowed ? 1 : 0)
        let deny      = todaySummary.deny      + (item.decision == .deny  ? 1 : 0)
        if let sid = item.sessionId { todaySessionIds.insert(sid) }
        todaySummary = TodaySummary(allow: allow, autoAllow: autoAllow, deny: deny, sessions: todaySessionIds.count)
    }

    private func resetTodayIfNeeded() {
        let newStart = Calendar.current.startOfDay(for: Date())
        guard newStart != todayStart else { return }
        todayStart = newStart
        todaySessionIds.removeAll()
        todaySummary = TodaySummary(allow: 0, autoAllow: 0, deny: 0, sessions: 0)
    }
    func presentAskQuestion(from request: HookRequest) {
        registerSession(from: request)
        pendingAskQuestion = request
        if pendingApproval == nil {
            AskQuestionWindowController.shared.show()
        }
    }

    func dismissAskQuestion() {
        pendingAskQuestion = nil
        AskQuestionWindowController.shared.dismiss()
    }

}
