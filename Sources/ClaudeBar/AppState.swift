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
    @Published private(set) var todaySummary = TodaySummary(allow: 0, deny: 0, sessions: 0)
    private var todaySessionIds: Set<String> = []
    @Published var activeSessions: [SessionInfo] = []  // hook-based: used by LogView green dot
    @Published var scannedSessions: [SessionInfo] = [] // process-scan: used by dashboard
    @Published var isServerRunning = false
    @Published var enableNativeNotifications: Bool
    @Published var intentState: IntentState = .none
    @Published var autoAllowEnabled: Bool
    @Published var autoAllowRules: [AutoAllowRule]
    @Published var pendingAskQuestion: HookRequest? = nil
    // Sessions shown in the dashboard: process-scan as primary, hook-only sessions as supplement
    var displayedSessions: [SessionInfo] {
        let scannedCwds = Set(scannedSessions.compactMap { $0.workingDirectory })
        let hookOnly = activeSessions.filter { !scannedCwds.contains($0.workingDirectory ?? "") }
        return scannedSessions + hookOnly
    }
    @Published var serverError: String?
    @Published var isSetupComplete: Bool
    @Published var blockApprovals: Bool

    var pendingApproval: PendingApproval? { approvalQueue.first }

    private enum Keys {
        static let isSetupComplete = "isSetupComplete"
        static let blockApprovals = "blockApprovals"
        static let enableNativeNotifications = "enableNativeNotifications"
        static let autoAllowEnabled = "autoAllowEnabled"
        static let autoAllowRules = "autoAllowRules"
    }

    private init() {
        self.isSetupComplete = UserDefaults.standard.bool(forKey: Keys.isSetupComplete)
        self.blockApprovals = UserDefaults.standard.bool(forKey: Keys.blockApprovals)
        self.enableNativeNotifications = UserDefaults.standard.bool(forKey: Keys.enableNativeNotifications)
        self.autoAllowEnabled = UserDefaults.standard.bool(forKey: Keys.autoAllowEnabled)
        if let data = UserDefaults.standard.data(forKey: Keys.autoAllowRules),
           let rules = try? JSONDecoder().decode([AutoAllowRule].self, from: data) {
            self.autoAllowRules = rules
        } else {
            self.autoAllowRules = AutoAllowRule.defaults
        }
        self.recentActivity = ActivityStore.shared.fetchRecent()
        Task { @MainActor [self] in
            let todayItems = await ActivityStore.shared.fetchToday()
            self.todaySessionIds = Set(todayItems.compactMap { $0.sessionId })
            self.todaySummary = ActivityStats.todaySummary(items: todayItems)
        }
    }

    func presentApproval(request: HookRequest, server: HookServer, isEnvWarning: Bool = false) {
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
        let response = HookResponse(decision: .allow, reason: nil, requestId: approval.request.requestId)
        addActivity(from: approval.request, decision: .allow)
        approval.respond(response)
        advanceQueue()
    }

    func allowAll() {
        guard !approvalQueue.isEmpty else { return }
        let approval = approvalQueue.removeFirst()
        addActivity(from: approval.request, decision: .allow)
        approval.allowAll?()
        advanceQueue()
    }

    func deny(reason: String) {
        guard !approvalQueue.isEmpty else { return }
        let approval = approvalQueue.removeFirst()
        let text = reason.isEmpty ? "Denied via ClaudeBar" : reason
        let response = HookResponse(decision: .deny, reason: text, requestId: approval.request.requestId)
        addActivity(from: approval.request, decision: .deny)
        approval.respond(response)
        advanceQueue()
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
        todaySummary = TodaySummary(allow: 0, deny: 0, sessions: 0)
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
        guard !name.isEmpty, !autoAllowRules.contains(where: { $0.toolName == name }) else { return }
        let pattern = commandPattern?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        autoAllowRules.append(AutoAllowRule(toolName: name, commandPattern: pattern))
        saveAutoAllowRules()
    }

    func removeAutoAllowRule(id: UUID) {
        autoAllowRules.removeAll { $0.id == id }
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

    func matchesAutoAllowRule(_ request: HookRequest) -> Bool {
        guard autoAllowEnabled, let toolName = request.toolName else { return false }
        guard !needsEnvWarning(request) else { return false }
        guard let rule = autoAllowRules.first(where: { $0.isEnabled && $0.toolName == toolName }) else { return false }
        if let pattern = rule.commandPattern, !pattern.isEmpty {
            let command = request.commandPreview
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  regex.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)) != nil else {
                return false
            }
        }
        return true
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
        addActivity(from: request, decision: .allow)
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

    private func addActivity(from request: HookRequest, decision: Decision) {
        addActivity(ActivityItem(
            sessionId: request.sessionId,
            toolName: request.toolName ?? "Unknown",
            decision: decision,
            preview: request.commandPreview,
            workingDirectory: request.workingDirectory
        ))
    }

    private func addActivity(_ item: ActivityItem) {
        recentActivity.insert(item, at: 0)
        if recentActivity.count > 200 { recentActivity.removeLast() }
        ActivityStore.shared.insert(item)
        let allow = todaySummary.allow + (item.decision == .allow ? 1 : 0)
        let deny  = todaySummary.deny  + (item.decision == .deny  ? 1 : 0)
        if let sid = item.sessionId { todaySessionIds.insert(sid) }
        todaySummary = TodaySummary(allow: allow, deny: deny, sessions: todaySessionIds.count)
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
